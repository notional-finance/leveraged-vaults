// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import "forge-std/console.sol";
import {TypeConvert} from "@contracts/global/TypeConvert.sol";
import {Constants} from "@contracts/global/Constants.sol";
import {VaultConfig} from "@contracts/global/Types.sol";
import {TokenUtils} from "@contracts/utils/TokenUtils.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {WithdrawRequestBase, WithdrawRequest, SplitWithdrawRequest} from "../common/WithdrawRequestBase.sol";
import {BaseStrategyVault, IERC20, NotionalProxy} from "../common/BaseStrategyVault.sol";
import {ITradingModule, Trade, TradeType} from "@interfaces/trading/ITradingModule.sol";
import {VaultAccountHealthFactors} from "@interfaces/notional/IVaultController.sol";
import {ClonedCoolDownHolder} from "@contracts/vaults/staking/protocols/ClonedCoolDownHolder.sol";

struct RedeemParams {
    uint8 dexId;
    uint256 minPurchaseAmount;
    bytes exchangeData;
}

struct DepositParams {
    uint8 dexId;
    uint256 minPurchaseAmount;
    bytes exchangeData;
}

/**
 * Supports vaults that borrow a token and stake it into a token that earns yield but may
 * require some illiquid redemption period.
 */
abstract contract BaseStakingVault is WithdrawRequestBase, BaseStrategyVault {
    using TokenUtils for IERC20;
    using TypeConvert for uint256;

    /// @notice token that will be held while staking
    address public immutable STAKING_TOKEN;
    /// @notice token that is borrowed by the vault
    address public immutable BORROW_TOKEN;
    /// @notice token that is redeemed from a withdraw request
    address public immutable REDEMPTION_TOKEN;

    uint256 immutable STAKING_PRECISION;
    uint256 immutable BORROW_PRECISION;

    constructor(
        address stakingToken,
        address borrowToken,
        address redemptionToken
    ) BaseStrategyVault(Deployments.NOTIONAL, Deployments.TRADING_MODULE) {
        STAKING_TOKEN = stakingToken;
        BORROW_TOKEN = borrowToken;
        REDEMPTION_TOKEN = redemptionToken;
        STAKING_PRECISION = 10 ** TokenUtils.getDecimals(stakingToken);
        BORROW_PRECISION = 10 ** TokenUtils.getDecimals(borrowToken);
    }

    function _initialize() internal virtual {
        // NO-OP in here but inheriting contracts can override
    }

    function initialize(string memory name, uint16 borrowCurrencyId) public virtual initializer {
        __INIT_VAULT(name, borrowCurrencyId);
        // Double check to ensure that these tokens are matching
        require(BORROW_TOKEN == address(_underlyingToken()));

        _initialize();
    }

    /// @notice Returns the total value in terms of the borrowed token of the account's position
    function convertStrategyToUnderlying(
        address account,
        uint256 vaultShares,
        uint256 /* maturity */
    ) public virtual override view returns (int256 underlyingValue) {
        uint256 stakeAssetPrice = uint256(getExchangeRate(0));

        WithdrawRequest memory w = getWithdrawRequest(account);
        uint256 withdrawValue = _calculateValueOfWithdrawRequest(
            w, stakeAssetPrice, BORROW_TOKEN, REDEMPTION_TOKEN
        );
        // This should always be zero if there is a withdraw request.
        uint256 vaultSharesNotInWithdrawQueue = (vaultShares - w.vaultShares);

        uint256 vaultSharesValue = (vaultSharesNotInWithdrawQueue * stakeAssetPrice * BORROW_PRECISION) /
            (uint256(Constants.INTERNAL_TOKEN_PRECISION) * Constants.EXCHANGE_RATE_PRECISION);
        return (withdrawValue + vaultSharesValue).toInt();
    }

    /// @notice Returns the exchange rate between the staking token and the borrowed token
    function getExchangeRate(uint256 /* */) public view virtual override returns (int256 rate) {
        (rate, /* */) = TRADING_MODULE.getOraclePrice(STAKING_TOKEN, BORROW_TOKEN);
    }

    /// @notice Converts vault shares into staking tokens
    function getStakingTokensForVaultShare(uint256 vaultShares) public view virtual returns (uint256) {
        // NOTE: this calculation works as long as staking tokens do not rebase and we do not
        // do any reinvestment into the staking token.
        return vaultShares * STAKING_PRECISION / uint256(Constants.INTERNAL_TOKEN_PRECISION);
    }

    /// @notice Required implementation to convert borrowed tokens into a staked token
    /// @param account the account that will hold the staked tokens
    /// @param depositUnderlyingExternal total amount of margin and borrowed tokens deposited
    /// into the vault from Notional
    /// @param maturity the target maturity of the borrowed tokens
    /// @param data arbitrary data passed from the user
    /// @return vaultShares the total vault shares minted after staking
    function _stakeTokens(
        address account,
        uint256 depositUnderlyingExternal,
        uint256 maturity,
        bytes calldata data
    ) internal virtual returns (uint256 vaultShares);

    /// @notice Called when an account enters a vault position
    /// @param account address that will hold the vault shares
    /// @param depositUnderlyingExternal total amount of borrowed tokens deposited
    /// @param maturity date of when the debt matures
    /// @param data arbitrary calldata for the vault entry
    function _depositFromNotional(
        address account,
        uint256 depositUnderlyingExternal,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 vaultShares) {
        // Short circuit any zero deposit amounts
        if (depositUnderlyingExternal == 0) return 0;

        // Cannot deposit when the account has any withdraw requests
        WithdrawRequest memory accountWithdraw = getWithdrawRequest(account);
        require(accountWithdraw.requestId == 0);

        return _stakeTokens(account, depositUnderlyingExternal, maturity, data);
    }

    /// @notice Called when an account exits from the vault.
    function _redeemFromNotional(
        address account,
        uint256 vaultShares,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 borrowedCurrencyAmount) {
        // Short circuit here to allow for direct repayment of debts. This method always
        // gets called by Notional on every exit, but in times of illiquidity an account
        // may want to pay down their debt without being able to instantly redeem their
        // vault shares to avoid liquidation.
        if (vaultShares == 0) return 0;

        WithdrawRequest memory accountWithdraw = getWithdrawRequest(account);

        RedeemParams memory params = abi.decode(data, (RedeemParams));
        if (accountWithdraw.requestId == 0) {
            return _executeInstantRedemption(account, vaultShares, maturity, params);
        } else {
            (
                uint256 vaultSharesRedeemed,
                uint256 tokensClaimed
            ) = _redeemActiveWithdrawRequest(account, accountWithdraw);
            // Once a withdraw request is initiated, the full amount must be redeemed from the vault.
            require(vaultShares == vaultSharesRedeemed);

            // Trades may be required here if the borrowed token is not the same as what is
            // received when redeeming.
            if (BORROW_TOKEN != REDEMPTION_TOKEN) {
                Trade memory trade = Trade({
                    tradeType: TradeType.EXACT_IN_SINGLE,
                    sellToken: address(REDEMPTION_TOKEN),
                    buyToken: address(BORROW_TOKEN),
                    amount: tokensClaimed,
                    limit: params.minPurchaseAmount,
                    deadline: block.timestamp,
                    exchangeData: params.exchangeData
                });

                (/* */, tokensClaimed) = _executeTrade(params.dexId, trade);
            }
            console.log('usdcOut', tokensClaimed);

            return tokensClaimed;
        }
    }

    /// @notice Default implementation for an instant redemption is to sell the staking token to the
    /// borrow token through the trading module. Can be overridden if required for different implementations.
    function _executeInstantRedemption(
        address /* account */,
        uint256 vaultShares,
        uint256 /* maturity */,
        RedeemParams memory params
    ) internal virtual returns (uint256 borrowedCurrencyAmount) {
        uint256 sellAmount = getStakingTokensForVaultShare(vaultShares);

        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(STAKING_TOKEN),
            buyToken: address(BORROW_TOKEN),
            amount: sellAmount,
            limit: params.minPurchaseAmount,
            deadline: block.timestamp,
            exchangeData: params.exchangeData
        });

        // Executes a trade on the given Dex, the vault must have permissions set for
        // each dex and token it wants to sell.
        (/* */, borrowedCurrencyAmount) = _executeTrade(params.dexId, trade);
    }

    /// @notice Executes a number of checks before and after liquidation and splits withdraw requests
    /// if required.
    function deleverageAccount(
        address account,
        address vault,
        address liquidator,
        uint16 currencyIndex,
        int256 depositUnderlyingInternal
    ) external payable override virtual returns (
        uint256 vaultSharesFromLiquidation,
        int256 depositAmountPrimeCash
    ) {
        require(msg.sender == liquidator);
        _checkReentrancyContext();

        // Do not allow liquidations if the result will be that the account is insolvent. This may occur if the
        // short term de-peg of an asset causes a bad debt to accrue to the protocol. In this case, we should be
        // able to execute a forced withdraw request and wait for a full return on the staked token.
        (VaultAccountHealthFactors memory healthBefore, /* */, /* */) = NOTIONAL.getVaultAccountHealthFactors(
            account, vault
        );
        require(0 <= healthBefore.collateralRatio, "Insolvent");
        console.logInt(healthBefore.collateralRatio);

        // Executes the liquidation on Notional, vault shares are transferred from the account to the liquidator
        // inside this process.
        console.log("here");
        (vaultSharesFromLiquidation, depositAmountPrimeCash) = NOTIONAL.deleverageAccount{value: msg.value}(
            account, vault, liquidator, currencyIndex, depositUnderlyingInternal
        );
        console.log("there");
        // Splits any withdraw requests, if required. Will revert if the liquidator cannot absorb the withdraw
        // request because they have another active one.
        _splitWithdrawRequest(account, liquidator, vaultSharesFromLiquidation);

        (VaultAccountHealthFactors memory healthAfter, /* */, /* */) = NOTIONAL.getVaultAccountHealthFactors(
            account, vault
        );
        // Ensure that the health ratio increases as a result of liquidation, this is similar the solvency check
        // above. If an account ends up in a worse collateral position due to the liquidation price we are better
        // off waiting until the withdraw request finalizes.
        require(healthBefore.collateralRatio < healthAfter.collateralRatio, "Collateral Decrease");
    }

    /// @notice Allows an account to initiate a withdraw of their vault shares
    function initiateWithdraw(bytes calldata data) external {
        _initiateWithdraw({account: msg.sender, isForced: false, data: data});

        (VaultAccountHealthFactors memory health, /* */, /* */) = NOTIONAL.getVaultAccountHealthFactors(
            msg.sender, address(this)
        );
        VaultConfig memory config = NOTIONAL.getVaultConfig(address(this));
        // Require that the account is collateralized
        require(config.minCollateralRatio <= health.collateralRatio, "Insufficient Collateral");
    }

    /// @notice Allows the emergency exit role to force an account to withdraw all their vault shares
    function forceWithdraw(address account, bytes calldata data) external onlyRole(EMERGENCY_EXIT_ROLE) {
        // Forced withdraw will withdraw all vault shares
        _initiateWithdraw({account: account, isForced: true, data: data});
    }

    /// @notice Finalizes withdraws manually
    function finalizeWithdrawsManual(address account) external {
        return _finalizeWithdrawsManual(account);
    }

    function rescueTokens(
        address cooldownHolder, IERC20 token, address receiver, uint256 amount
    ) external onlyRole(EMERGENCY_EXIT_ROLE) {
        ClonedCoolDownHolder(cooldownHolder).rescueTokens(token, receiver, amount);
    }
}