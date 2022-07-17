// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {Token, VaultAccount} from "../global/Types.sol";
import {SafeInt256} from "../global/SafeInt256.sol";
import {Constants} from "../global/Constants.sol";

import {TokenUtils} from "../utils/TokenUtils.sol";
import {BalancerUtils} from "./balancer/BalancerUtils.sol";
import {BalancerVaultStorage} from "./balancer/BalancerVaultStorage.sol";
import {RewardHelper} from "./balancer/RewardHelper.sol";
import {SettlementHelper} from "./balancer/SettlementHelper.sol";
import {VaultHelper} from "./balancer/VaultHelper.sol";
import {
    DeploymentParams, 
    InitParams, 
    StrategyVaultSettings, 
    StrategyVaultState,
    ReinvestRewardParams,
    DepositParams,
    RedeemParams,
    SecondaryTradeParams,
    SettlementState
} from "./balancer/BalancerVaultTypes.sol";

import {IERC20} from "../../interfaces/IERC20.sol";
import {WETH9} from "../../interfaces/WETH9.sol";
import {IStrategyVault} from "../../interfaces/notional/IStrategyVault.sol";
import {VaultConfig} from "../../interfaces/notional/IVaultController.sol";
import {IBoostController} from "../../interfaces/notional/IBoostController.sol";
import {IVeBalDelegator} from "../../interfaces/notional/IVeBalDelegator.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {IBalancerVault} from "../../interfaces/balancer/IBalancerVault.sol";
import {IBalancerMinter} from "../../interfaces/balancer/IBalancerMinter.sol";
import {ILiquidityGauge} from "../../interfaces/balancer/ILiquidityGauge.sol";
import {IBalancerPool} from "../../interfaces/balancer/IBalancerPool.sol";
import {IPriceOracle} from "../../interfaces/balancer/IPriceOracle.sol";
import {ITradingModule} from "../../interfaces/trading/ITradingModule.sol";

contract Balancer2TokenVault is UUPSUpgradeable, Initializable, VaultHelper {
    using TokenUtils for IERC20;
    using SafeInt256 for uint256;
    using SafeInt256 for int256;

    /** Errors */
    error NotionalOwnerRequired(address sender);
    error DepositNotAllowedInSettlementWindow();
    error RedeemNotAllowedInSettlementWindow();

    /** Events */
    event StrategyVaultSettingsUpdated(StrategyVaultSettings settings);

    constructor(NotionalProxy notional_, DeploymentParams memory params)
        BalancerVaultStorage(notional_, params)
    {}

    function initialize(InitParams calldata params)
        external
        initializer
        onlyNotionalOwner
    {
        __INIT_VAULT(params.name, params.borrowCurrencyId);
        _setStrategyVaultSettings(params.settings);

        BalancerUtils.approveBalancerTokens(_poolContext());
    }

    function _setStrategyVaultSettings(StrategyVaultSettings memory settings) private {
        require(settings.oracleWindowInSeconds <= uint32(MAX_ORACLE_QUERY_WINDOW));
        require(settings.settlementCoolDownInMinutes <= Constants.MAX_SETTLEMENT_COOLDOWN_IN_MINUTES);
        require(settings.postMaturitySettlementCoolDownInMinutes <= Constants.MAX_SETTLEMENT_COOLDOWN_IN_MINUTES);
        require(settings.balancerOracleWeight <= Constants.VAULT_PERCENT_BASIS);
        require(settings.maxBalancerPoolShare <= Constants.VAULT_PERCENT_BASIS);
        require(settings.settlementSlippageLimitPercent <= Constants.VAULT_PERCENT_BASIS);
        require(settings.postMaturitySettlementSlippageLimitPercent <= Constants.VAULT_PERCENT_BASIS);

        strategyVaultSettings.oracleWindowInSeconds = settings.oracleWindowInSeconds;
        strategyVaultSettings.balancerOracleWeight = settings.balancerOracleWeight;
        strategyVaultSettings.maxBalancerPoolShare = settings.maxBalancerPoolShare;
        strategyVaultSettings.maxUnderlyingSurplus = settings.maxUnderlyingSurplus;
        strategyVaultSettings.settlementSlippageLimitPercent = settings
            .settlementSlippageLimitPercent;
        strategyVaultSettings.postMaturitySettlementSlippageLimitPercent = settings
            .postMaturitySettlementSlippageLimitPercent;
        strategyVaultSettings.settlementCoolDownInMinutes = settings
            .settlementCoolDownInMinutes;
        strategyVaultSettings.postMaturitySettlementCoolDownInMinutes = settings
            .postMaturitySettlementCoolDownInMinutes;

        emit StrategyVaultSettingsUpdated(settings);
    }

    /// @notice Converts strategy tokens to underlyingValue
    /// @dev Secondary token value is converted to its primary token equivalent value
    /// using the Balancer time-weighted price oracle
    /// @param strategyTokenAmount strategy token amount
    /// @param maturity maturity timestamp
    /// @return underlyingValue underlying (primary token) value of the strategy tokens
    function convertStrategyToUnderlying(
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view override returns (int256 underlyingValue) {
        uint256 bptClaim = _convertStrategyTokensToBPTClaim(
            strategyTokenAmount,
            maturity
        );

        uint256 primaryBalance = BalancerUtils.getTimeWeightedPrimaryBalance(
            _oracleContext(), bptClaim
        );

        // Oracle price for the pair in 18 decimals
        uint256 oraclePairPrice = _getOraclePairPrice();

        if (SECONDARY_BORROW_CURRENCY_ID == 0) return primaryBalance.toInt();

        // prettier-ignore
        (
            /* uint256 debtShares */,
            uint256 borrowedSecondaryfCashAmount
        ) = getDebtSharesToRepay(account, maturity, strategyTokenAmount);

        // Do not discount secondary fCash amount to present value so that we do not introduce
        // interest rate risk in this calculation. fCash is always in 8 decimal precision, the
        // oraclePairPrice is always in 18 decimal precision and we want our result denominated
        // in the primary token precision.
        // primaryTokenValue = (fCash * rateDecimals * primaryDecimals) / (rate * 1e8)
        uint256 primaryPrecision = 10**PRIMARY_DECIMALS;

        uint256 secondaryBorrowedDenominatedInPrimary = (borrowedSecondaryfCashAmount *
                BalancerUtils.BALANCER_PRECISION *
                primaryPrecision) /
                (oraclePairPrice * uint256(Constants.INTERNAL_TOKEN_PRECISION));

        return
            primaryBalance.toInt() -
            secondaryBorrowedDenominatedInPrimary.toInt();
    }

    function _revertInSettlementWindow(uint256 maturity) internal view {
        if (maturity - SETTLEMENT_PERIOD_IN_SECONDS <= block.timestamp) {
            revert();
        }
    }

    function _depositFromNotional(
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {
        // Entering the vault is not allowed within the settlement window
        _revertInSettlementWindow(maturity);

        DepositParams memory params = abi.decode(data, (DepositParams));

        // prettier-ignore
        (
            uint256 bptHeldInMaturity,
            uint256 totalStrategyTokenSupplyInMaturity
        ) = _getBPTHeldInMaturity(maturity);

        // First borrow any secondary tokens (if required)
        uint256 borrowedSecondaryAmount = _borrowSecondaryCurrency(
            account,
            maturity,
            deposit,
            params
        );

        // Join the balancer pool and stake the tokens for boosting
        uint256 bptMinted = _joinPoolAndStake(
            deposit,
            borrowedSecondaryAmount,
            params.minBPT
        );

        // Calculate strategy token share for this account
        if (strategyVaultState.totalStrategyTokenGlobal == 0) {
            // Strategy tokens are in 8 decimal precision, BPT is in 18. Scale the minted amount down.
            strategyTokensMinted =
                (bptMinted * uint256(Constants.INTERNAL_TOKEN_PRECISION)) /
                BalancerUtils.BALANCER_PRECISION;
        } else {
            // BPT held in maturity is calculated before the new BPT tokens are minted, so this calculation
            // is the tokens minted that will give the account a corresponding share of the new bpt balance held.
            // The precision here will be the same as strategy token supply.
            strategyTokensMinted =
                (bptMinted * totalStrategyTokenSupplyInMaturity) /
                bptHeldInMaturity;
        }

        // Update global supply count
        strategyVaultState.totalStrategyTokenGlobal += strategyTokensMinted;
    }

    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 finalPrimaryBalance) {
        if (account == address(this) && data.length == 32) {
            // Check if this is called from one of the settlement functions
            // data = primaryAmountToRepay (uint256) in this case
            // Token transfers are handled in the base strategy
            (finalPrimaryBalance) = abi.decode(data, (uint256));
        } else {
            // Exiting the vault is not allowed within the settlement window
            _revertInSettlementWindow(maturity);

            RedeemParams memory params = abi.decode(data, (RedeemParams));
            // These min primary and min secondary amounts must be within some configured
            // delta of the current oracle price
            _validateMinExitAmounts(params.minPrimary, params.minSecondary);

            uint256 bptClaim = _convertStrategyTokensToBPTClaim(strategyTokens, maturity);

            if (bptClaim == 0) return 0;
            // Underlying token balances from exiting the pool
            (uint256 primaryBalance, uint256 secondaryBalance) = BalancerUtils._unstakeAndExitPoolExactBPTIn(
                _poolContext(), bptClaim, params.minPrimary, params.minSecondary
            );

            if (SECONDARY_BORROW_CURRENCY_ID != 0) {
                // Returns the amount of secondary debt shares that need to be repaid
                (uint256 debtSharesToRepay, /*  */) = getDebtSharesToRepay(
                    account, maturity, strategyTokens
                );

                finalPrimaryBalance = SettlementHelper._repaySecondaryBorrow(
                    account,
                    maturity,
                    SECONDARY_BORROW_CURRENCY_ID,
                    debtSharesToRepay,
                    params,
                    secondaryBalance,
                    primaryBalance
                );
            } else if (secondaryBalance > 0) {
                // If there is no secondary debt, we still need to sell the secondary balance
                // back to the primary token here.
                (SecondaryTradeParams memory tradeParams) = abi.decode(
                    params.secondaryTradeParams, (SecondaryTradeParams)
                );
                address primaryToken = address(_underlyingToken());
                uint256 primaryPurchased = sellSecondaryBalance(tradeParams, primaryToken, secondaryBalance);

                finalPrimaryBalance = primaryBalance + primaryPurchased;
            }
        }

        // Update global strategy token balance
        strategyVaultState.totalStrategyTokenGlobal -= strategyTokens;
    }

    /// @notice Validates the number of strategy tokens to redeem against
    /// the total strategy tokens already redeemed for the current maturity
    /// to ensure that we don't redeem tokens from other maturities
    function _validateTokensToRedeem(uint256 maturity, uint256 strategyTokensToRedeem) 
        internal view returns (SettlementState memory) {
        SettlementState memory state = settlementState[maturity];
        uint256 totalInMaturity = _totalSupplyInMaturity(maturity);
        require(state.strategyTokensRedeemed + strategyTokensToRedeem <= totalInMaturity);
        return state;
    }

    /// @notice Settles the vault after maturity, at this point we assume something has gone wrong
    /// and we allow the owner to take over to ensure that the vault is properly settled. This vault
    /// is presumed to be able to settle fully prior to maturity.
    /// @dev This settlement call is authenticated
    /// @param maturity maturity timestamp
    /// @param strategyTokensToRedeem the amount of strategy tokens to redeem
    /// @param data settlement parameters
    function settleVaultPostMaturity(
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external onlyNotionalOwner {
        if (block.timestamp < maturity) {
            revert SettlementHelper.HasNotMatured();
        }
        SettlementState memory state = _validateTokensToRedeem(maturity, strategyTokensToRedeem);
        RedeemParams memory params = SettlementHelper._decodeParamsAndValidate(
            strategyVaultState.lastPostMaturitySettlementTimestamp,
            strategyVaultSettings.postMaturitySettlementCoolDownInMinutes,
            strategyVaultSettings.postMaturitySettlementSlippageLimitPercent,
            data
        );

        _executeNormalSettlement(state, maturity, strategyTokensToRedeem, params);
        strategyVaultState.lastPostMaturitySettlementTimestamp = uint32(block.timestamp);
    }

    /// @notice Once the settlement window begins, the vault may begin to be settled by anyone
    /// who calls this method with valid parameters. Settlement includes redeeming BPT tokens 
    /// for the two underlying tokens and then trading appropriately until both remaining debts
    /// are repaid. Once the settlement window for a maturity begins, users can no longer enter
    /// or exit the maturity until it has completed settlement.
    /// NOTE: Calling this method is not incentivized.
    /// @param maturity maturity timestamp
    /// @param strategyTokensToRedeem the amount of strategy tokens to redeem
    /// @param data settlement parameters
    function settleVaultNormal(
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        if (maturity <= block.timestamp) {
            revert SettlementHelper.PostMaturitySettlement();
        }
        if (block.timestamp < maturity - SETTLEMENT_PERIOD_IN_SECONDS) {
            revert SettlementHelper.NotInSettlementWindow();
        }
        SettlementState memory state = _validateTokensToRedeem(maturity, strategyTokensToRedeem);
        RedeemParams memory params = SettlementHelper._decodeParamsAndValidate(
            strategyVaultState.lastSettlementTimestamp,
            strategyVaultSettings.settlementCoolDownInMinutes,
            strategyVaultSettings.settlementSlippageLimitPercent,
            data
        );

        _executeNormalSettlement(state, maturity, strategyTokensToRedeem, params);
        strategyVaultState.lastSettlementTimestamp = uint32(block.timestamp);
    }

    /// @notice In the case where the total BPT held by the vault is greater than some threshold
    /// of the total vault supply, we may need to redeem strategy tokens to cash to ensure that
    /// the vault will not run into liquidity issues during settlement.
    function settleVaultEmergency(uint256 maturity, bytes calldata data) external {
        // No need for emergency settlement during the settlement window
        _revertInSettlementWindow(maturity);

        // Not in settlement window, check if BPT held is greater than maxBalancerPoolShare * total BPT supply
        uint256 totalBPTSupply = BALANCER_POOL_TOKEN.totalSupply();
        uint256 totalBPTHeld = _bptHeld();
        uint256 emergencyBPTWithdrawThreshold = _bptThreshold(totalBPTSupply);

        if (totalBPTHeld <= emergencyBPTWithdrawThreshold)
            revert SettlementHelper.InvalidEmergencySettlement();

        // prettier-ignore
        (uint256 bptHeldInMaturity, /* */) = _getBPTHeldInMaturity(maturity);

        uint256 bptToSettle = SettlementHelper._getEmergencySettlementBPTAmount({
            bptTotalSupply: totalBPTSupply,
            maxBalancerPoolShare: strategyVaultSettings.maxBalancerPoolShare,
            totalBPTHeld: totalBPTHeld,
            bptHeldInMaturity: bptHeldInMaturity
        });

        uint256 redeemStrategyTokenAmount = _convertBPTClaimToStrategyTokens(bptToSettle, maturity);

        int256 expectedUnderlyingRedeemed = convertStrategyToUnderlying(
            address(this),
            redeemStrategyTokenAmount,
            maturity
        );

        SettlementHelper.settleVaultEmergency({
            maturity: maturity,
            bptToSettle: bptToSettle,
            expectedUnderlyingRedeemed: expectedUnderlyingRedeemed,
            maxUnderlyingSurplus: strategyVaultSettings.maxUnderlyingSurplus,
            redeemStrategyTokenAmount: redeemStrategyTokenAmount,
            data: data
        });
    }

    /// @notice Claim other liquidity gauge reward tokens (i.e. LIDO)
    function claimRewardTokens() external {
        RewardHelper.claimRewardTokens(_poolContext());
    }

    /// @notice Sell reward tokens for BPT and reinvest the proceeds
    /// @param params reward reinvestment params
    function reinvestReward(ReinvestRewardParams calldata params) external {
        RewardHelper.reinvestReward(params, TRADING_MODULE, _oracleContext());
    }

    /** Setters */

    /// @notice Updates the vault settings
    /// @param settings vault settings
    function setStrategyVaultSettings(StrategyVaultSettings calldata settings)
        external
        onlyNotionalOwner
    {
        _setStrategyVaultSettings(settings);
    }

    /** Public view functions */
    function convertBPTClaimToStrategyTokens(uint256 bptClaim, uint256 maturity)
        external view returns (uint256 strategyTokenAmount) {
        return _convertBPTClaimToStrategyTokens(bptClaim, maturity);
    }

   /// @notice Converts strategy tokens to BPT
    function convertStrategyTokensToBPTClaim(uint256 strategyTokenAmount, uint256 maturity) 
        external view returns (uint256 bptClaim) {
        return _convertStrategyTokensToBPTClaim(strategyTokenAmount, maturity);
    }

    function getStrategyVaultState() external view returns (StrategyVaultState memory) {
        return strategyVaultState;
    }

    function getStrategyVaultSettings() external view returns (StrategyVaultSettings memory) {
        return strategyVaultSettings;
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal override onlyNotionalOwner {}
}
