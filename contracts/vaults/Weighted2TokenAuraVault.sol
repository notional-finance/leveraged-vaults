// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {Token, VaultAccount} from "../global/Types.sol";
import {SafeInt256} from "../global/SafeInt256.sol";
import {Constants} from "../global/Constants.sol";

import {TokenUtils} from "../utils/TokenUtils.sol";
import {NotionalUtils} from "../utils/NotionalUtils.sol";
import {BalancerUtils} from "./balancer/internal/BalancerUtils.sol";
import {BaseVaultStorage} from "./balancer/BaseVaultStorage.sol";
import {Weighted2TokenVaultMixin} from "./balancer/mixins/Weighted2TokenVaultMixin.sol";
import {AuraStakingMixin} from "./balancer/mixins/AuraStakingMixin.sol";
import {Weighted2TokenAuraRewardHelper} from "./balancer/external/Weighted2TokenAuraRewardHelper.sol";
import {Weighted2TokenAuraVaultHelper} from "./balancer/external/Weighted2TokenAuraVaultHelper.sol";
import {AuraRewardHelperExternal} from "./balancer/external/AuraRewardHelperExternal.sol";
import {SettlementHelper} from "./balancer/SettlementHelper.sol";
import {Weighted2TokenVaultHelper} from "./balancer/Weighted2TokenVaultHelper.sol";
import {
    TwoTokenAuraDeploymentParams, 
    InitParams, 
    StrategyVaultSettings, 
    StrategyVaultState,
    ReinvestRewardParams,
    DepositParams,
    RedeemParams,
    SecondaryTradeParams,
    SettlementState,
    WeightedOracleContext,
    TwoTokenPoolContext,
    Weighted2TokenAuraStrategyContext,
    StrategyContext
} from "./balancer/BalancerVaultTypes.sol";

import {IERC20} from "../../interfaces/IERC20.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {ITradingModule} from "../../interfaces/trading/ITradingModule.sol";
import {VaultUtils} from "./balancer/internal/VaultUtils.sol";
import {TwoTokenAuraStrategyUtils} from "./balancer/internal/TwoTokenAuraStrategyUtils.sol";
import {TwoTokenPoolUtils} from "./balancer/internal/TwoTokenPoolUtils.sol";
import {Weighted2TokenOracleMath} from "./balancer/internal/Weighted2TokenOracleMath.sol";

contract Weighted2TokenAuraVault is UUPSUpgradeable, Initializable, Weighted2TokenVaultHelper {
    using TokenUtils for IERC20;
    using SafeInt256 for uint256;
    using SafeInt256 for int256;
    using VaultUtils for StrategyVaultSettings;
    using VaultUtils for StrategyVaultState;
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using Weighted2TokenOracleMath for WeightedOracleContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;

    /** Errors */
    error NotionalOwnerRequired(address sender);
    error DepositNotAllowedInSettlementWindow();
    error RedeemNotAllowedInSettlementWindow();

    /** Events */
    event StrategyVaultSettingsUpdated(StrategyVaultSettings settings);

    constructor(NotionalProxy notional_, TwoTokenAuraDeploymentParams memory params)
        BaseVaultStorage(notional_, params.baseParams) 
        Weighted2TokenVaultMixin(
            params.primaryBorrowCurrencyId,
            params.baseParams.balancerPoolId,
            params.secondaryBorrowCurrencyId
        )
        AuraStakingMixin(params.baseParams.liquidityGauge, params.auraRewardPool)
    {}

    function initialize(InitParams calldata params)
        external
        initializer
        onlyNotionalOwner
    {
        __INIT_VAULT(params.name, params.borrowCurrencyId);
        _setStrategyVaultSettings(params.settings);

        BalancerUtils.approveBalancerTokens(_twoTokenPoolContext(), _auraStakingContext());
    }

    function _setStrategyVaultSettings(StrategyVaultSettings memory settings) private {
        settings._validateStrategyVaultSettings(uint32(MAX_ORACLE_QUERY_WINDOW));
        settings._setStrategyVaultSettings();
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
        Weighted2TokenAuraStrategyContext memory context = _strategyContext();
        StrategyContext memory strategyContext = context.baseContext;
        WeightedOracleContext memory oracleContext = context.oracleContext;
        TwoTokenPoolContext memory poolContext = context.poolContext;

        uint256 bptClaim = strategyContext._convertStrategyTokensToBPTClaim(
            strategyTokenAmount, maturity
        );

        uint256 primaryBalance = oracleContext._getTimeWeightedPrimaryBalance(
            poolContext, bptClaim
        );

        // Oracle price for the pair in 18 decimals
        uint256 oraclePairPrice = poolContext._getOraclePairPrice(
            oracleContext.baseContext, TRADING_MODULE
        );

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

    function _depositFromNotional(
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {
        // Entering the vault is not allowed within the settlement window
        _revertInSettlementWindow(maturity);
        Weighted2TokenAuraVaultHelper._depositFromNotional(
            _strategyContext(), account, deposit, maturity, data
        );
    }

    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 finalPrimaryBalance) {
        require(strategyTokens <= type(uint80).max); /// @dev strategyTokens overflow

     /*   if (account == address(this) && data.length == 32) {
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
            // TODO: fix this
            uint256 primaryBalance;
            uint256 secondaryBalance;
            uint256[] memory exitBalances = AuraStakingUtils._unstakeAndExitPoolExactBPTIn({
                stakingContext: _auraStakingContext(), 
                poolContext: _twoTokenPoolContext(),
                poolParams: poolContext._getPoolParams(
                    params.minPrimary, 
                    params.minSecondary
                ),
                bptExitAmount: bptClaim
            });

            (uint256 primaryBalance, uint256 secondaryBalance) 
                = (exitBalances[PRIMARY_INDEX], exitBalances[SECONDARY_INDEX]);

            if (SECONDARY_BORROW_CURRENCY_ID != 0) {
                // Returns the amount of secondary debt shares that need to be repaid
                (uint256 debtSharesToRepay,*/ /*  */ /*) = getDebtSharesToRepay(
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

            // Update global strategy token balance
            // This only needs to be updated for normal redemption
            // and emergency settlement. For normal and post-maturity settlement
            // scenarios (account == address(this) && data.length == 32), we
            // update totalStrategyTokenGlobal before this function is called.
            StrategyVaultState memory strategyVaultState = VaultUtils._getStrategyVaultState();
            strategyVaultState.totalStrategyTokenGlobal -= uint80(strategyTokens);
            VaultUtils._setStrategyVaultState(strategyVaultState); 
        } */
    }

    /// @notice Validates the number of strategy tokens to redeem against
    /// the total strategy tokens already redeemed for the current maturity
    /// to ensure that we don't redeem tokens from other maturities
    function _validateTokensToRedeem(uint256 maturity, uint256 strategyTokensToRedeem) 
        internal view returns (SettlementState memory) {
        SettlementState memory state = VaultUtils._getSettlementState(maturity);
        uint256 totalInMaturity = NotionalUtils._totalSupplyInMaturity(maturity);
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
        StrategyVaultState memory strategyVaultState = VaultUtils._getStrategyVaultState();
        StrategyVaultSettings memory strategyVaultSettings = VaultUtils._getStrategyVaultSettings();
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
        StrategyVaultState memory strategyVaultState = VaultUtils._getStrategyVaultState();
        StrategyVaultSettings memory strategyVaultSettings = VaultUtils._getStrategyVaultSettings();
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

    function _getEmergencySettlementParams(
        StrategyVaultSettings memory settings,
        StrategyVaultState memory state,
        uint256 maturity
    ) 
        private view returns(uint256 bptToSettle, uint256 maxUnderlyingSurplus) {
        // Not in settlement window, check if BPT held is greater than maxBalancerPoolShare * total BPT supply
        uint256 totalBPTSupply = BALANCER_POOL_TOKEN.totalSupply();
        uint256 totalBPTHeld = _bptHeld();
        uint256 emergencyBPTWithdrawThreshold = settings._bptThreshold(totalBPTSupply);

        if (totalBPTHeld <= emergencyBPTWithdrawThreshold)
            revert SettlementHelper.InvalidEmergencySettlement();

        uint256 bptHeldInMaturity = state._getBPTHeldInMaturity(
            NotionalUtils._totalSupplyInMaturity(maturity),
            totalBPTHeld
        );

        bptToSettle = SettlementHelper._getEmergencySettlementBPTAmount({
            bptTotalSupply: totalBPTSupply,
            maxBalancerPoolShare: settings.maxBalancerPoolShare,
            totalBPTHeld: totalBPTHeld,
            bptHeldInMaturity: bptHeldInMaturity
        });
        maxUnderlyingSurplus = settings.maxUnderlyingSurplus;
    }

    /// @notice In the case where the total BPT held by the vault is greater than some threshold
    /// of the total vault supply, we may need to redeem strategy tokens to cash to ensure that
    /// the vault will not run into liquidity issues during settlement.
    function settleVaultEmergency(uint256 maturity, bytes calldata data) external {
        // No need for emergency settlement during the settlement window
        _revertInSettlementWindow(maturity);

 /*       (uint256 bptToSettle, uint256 maxUnderlyingSurplus) = _getEmergencySettlementParams(
            VaultUtils._getStrategyVaultSettings(),
            VaultUtils._getStrategyVaultState(),
            maturity
        );

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
            maxUnderlyingSurplus: maxUnderlyingSurplus,
            redeemStrategyTokenAmount: redeemStrategyTokenAmount,
            data: data
        }); */
    }

    /// @notice Claim other liquidity gauge reward tokens (i.e. LIDO)
    function claimRewardTokens() external {
        StrategyVaultSettings memory strategyVaultSettings = VaultUtils._getStrategyVaultSettings();
        AuraRewardHelperExternal.claimRewardTokens(
            _auraStakingContext(), 
            strategyVaultSettings.feePercentage,
            FEE_RECEIVER
        );
    }

    /// @notice Sell reward tokens for BPT and reinvest the proceeds
    /// @param params reward reinvestment params
    function reinvestReward(ReinvestRewardParams calldata params) external {
        Weighted2TokenAuraRewardHelper.reinvestReward(_strategyContext(), TRADING_MODULE, params);
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
        return _strategyContext().baseContext._convertBPTClaimToStrategyTokens(bptClaim, maturity);
    }

   /// @notice Converts strategy tokens to BPT
    function convertStrategyTokensToBPTClaim(uint256 strategyTokenAmount, uint256 maturity) 
        external view returns (uint256 bptClaim) {
        return _strategyContext().baseContext._convertStrategyTokensToBPTClaim(strategyTokenAmount, maturity);
    }

    function getStrategyContext() external view returns (Weighted2TokenAuraStrategyContext memory) {
        return _strategyContext();
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal override onlyNotionalOwner {}
}
