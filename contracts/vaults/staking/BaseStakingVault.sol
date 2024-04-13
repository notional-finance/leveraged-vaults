// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import { Constants } from "@contracts/global/Constants.sol";
import { TokenUtils } from "@contracts/utils/TokenUtils.sol";
import {
    WithdrawRequestBase,
    WithdrawRequest,
    SplitWithdrawRequest
} from "../common/WithdrawRequestBase.sol";
import { Deployments } from "@deployments/Deployments.sol";
import {
    BaseStrategyVault,
    IERC20,
    NotionalProxy
} from "../common/BaseStrategyVault.sol";
import {
    ITradingModule,
    Trade,
    TradeType
} from "@interfaces/trading/ITradingModule.sol";
import { VaultAccountHealthFactors } from "@interfaces/notional/IVaultController.sol";

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

abstract contract BaseStakingVault is WithdrawRequestBase, BaseStrategyVault {
    using TokenUtils for IERC20;

    address public immutable STAKING_TOKEN;
    uint256 immutable STAKING_PRECISION;
    address public immutable BORROW_TOKEN;
    uint256 immutable BORROW_PRECISION;
    uint256 internal constant EXCHANGE_RATE_PRECISION = 1e18;

    constructor(
        NotionalProxy notional_,
        ITradingModule tradingModule_,
        address stakingToken,
        address borrowToken
    ) BaseStrategyVault(notional_, tradingModule_) {
        STAKING_TOKEN = stakingToken;
        STAKING_PRECISION = 10 ** TokenUtils.getDecimals(stakingToken);
        BORROW_TOKEN = borrowToken;
        BORROW_PRECISION = 10 ** TokenUtils.getDecimals(borrowToken);
    }

    function _initialize() internal virtual {
        // NO-OP in here but inheriting contracts can override
    }

    function initialize(
        string memory name,
        uint16 borrowCurrencyId
    ) public virtual initializer {
        __INIT_VAULT(name, borrowCurrencyId);
        // Double check to ensure that these tokens are matching
        require(BORROW_TOKEN == address(_underlyingToken()));

        _initialize();
    }

    function convertStrategyToUnderlying(
        address account,
        uint256 vaultShares,
        uint256 /* maturity */
    ) public virtual override view returns (int256 underlyingValue) {
        uint256 stakeAssetPrice = uint256(getExchangeRate(0));

        (
            WithdrawRequest memory f,
            WithdrawRequest memory w
        ) = getWithdrawRequests(account);
        uint256 withdrawValue = _getValueOfWithdrawRequest(w, stakeAssetPrice);
        uint256 forcedValue = _getValueOfWithdrawRequest(f, stakeAssetPrice);
        uint256 vaultSharesNotInWithdrawQueue = (
            vaultShares - w.vaultShares - f.vaultShares
        );

        uint256 vaultSharesValue = (vaultSharesNotInWithdrawQueue * stakeAssetPrice * BORROW_PRECISION) /
            (uint256(Constants.INTERNAL_TOKEN_PRECISION) * EXCHANGE_RATE_PRECISION);
        return int256(withdrawValue + forcedValue + vaultSharesValue);
    }

    function getExchangeRate(uint256 /* maturity */) public view virtual override returns (int256) {
        (int256 rate, /* int256 rateDecimals */) = TRADING_MODULE.getOraclePrice(
            STAKING_TOKEN, BORROW_TOKEN
        );
        require(rate > 0);
        return rate;
    }

    function _depositFromNotional(
        address account,
        uint256 depositUnderlyingExternal,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 vaultShares) {
        // Short circuit any zero deposit amounts
        if (depositUnderlyingExternal == 0) return 0;

        (
            WithdrawRequest memory forcedWithdraw,
            WithdrawRequest memory accountWithdraw
        ) = getWithdrawRequests(account);

        // Cannot deposit when the account has forced withdraw requests
        require(forcedWithdraw.requestId == 0);
        if (accountWithdraw.requestId != 0) {
            // Allows an account to borrow against their withdraw request, subject to a
            // collateral check. Allows liquidators to get more leverage against the
            // withdraw requests when there is a lot of illiquidity in the staking token.
            bool borrowAgainstWithdrawRequest = abi.decode(data, (bool));
            if (borrowAgainstWithdrawRequest) {
                if (_isUnderlyingETH()) {
                    payable(account).transfer(depositUnderlyingExternal);
                } else {
                    IERC20(BORROW_TOKEN).checkTransfer(account, depositUnderlyingExternal);
                }
            } else {
                revert();
            }

            return 0;
        }

        return _stakeTokens(account, depositUnderlyingExternal, maturity, data);
    }

    function _redeemFromNotional(
        address account,
        uint256 vaultShares,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 borrowedCurrencyAmount) {
        // Short circuit here to allow for direct repayment of debts.
        if (vaultShares == 0) return 0;

        (
            WithdrawRequest memory forcedWithdraw,
            WithdrawRequest memory accountWithdraw
        ) = getWithdrawRequests(account);

        if (data.length == 0) {
            (uint256 vaultSharesRedeemed, uint256 tokensClaimed) = _redeemActiveWithdrawRequests(
                account,
                accountWithdraw,
                forcedWithdraw
            );
            // Once a withdraw request is initiated, the full amount must be redeemed
            // from the vault.
            require(vaultShares == vaultSharesRedeemed);

            return tokensClaimed;
        } else {
            if (forcedWithdraw.requestId != 0 || accountWithdraw.requestId != 0) {
                uint256 accountVaultShares = Deployments.NOTIONAL.getVaultAccount(
                    account, address(this)
                ).vaultShares;
                uint256 liquidVaultShares = (
                    accountVaultShares - forcedWithdraw.vaultShares - accountWithdraw.vaultShares
                );
                require(vaultShares <= liquidVaultShares, "Insufficient Shares");
            }

            return _executeInstantRedemption(account, vaultShares, maturity, data);
        }
    }

    function _executeInstantRedemption(
        address /* account */,
        uint256 vaultShares,
        uint256 /* maturity */,
        bytes calldata data
    ) internal virtual returns (uint256 borrowedCurrencyAmount) {
        uint256 sellAmount = vaultShares * uint256(STAKING_PRECISION) /
            uint256(Constants.INTERNAL_TOKEN_PRECISION);
        RedeemParams memory params = abi.decode(data, (RedeemParams));

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

        (VaultAccountHealthFactors memory healthBefore, /* */, /* */) = NOTIONAL.getVaultAccountHealthFactors(
            account, vault
        );
        require(0 <= healthBefore.collateralRatio);

        uint256 vaultSharesBefore = NOTIONAL.getVaultAccount(account, address(this)).vaultShares;

        (vaultSharesFromLiquidation, depositAmountPrimeCash) = NOTIONAL.deleverageAccount{value: msg.value}(
            account, vault, liquidator, currencyIndex, depositUnderlyingInternal
        );

        _splitWithdrawRequest(account, liquidator, vaultSharesBefore, vaultSharesFromLiquidation);

        (VaultAccountHealthFactors memory healthAfter, /* */, /* */) = NOTIONAL.getVaultAccountHealthFactors(
            account, vault
        );
        // Ensure that the health ratio increases as a result of liquidation
        require(healthBefore.collateralRatio < healthAfter.collateralRatio, "Collateral Decrease");
    }

    function initiateWithdraw(uint256 vaultShares) external {
        require(0 < vaultShares);
        _initiateWithdraw({account: msg.sender, vaultShares: vaultShares, isForced: false});
    }

    function forceWithdraw(address account) external onlyRole(EMERGENCY_EXIT_ROLE) {
        // Forced withdraw will withdraw all vault shares
        _initiateWithdraw({account: account, vaultShares: 0, isForced: true});
    }

    function finalizeWithdrawsOutOfBand(address account) external {
        return _finalizeWithdrawsOutOfBand(account);
    }
}