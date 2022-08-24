// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {BalancerConstants} from "./balancer/internal/BalancerConstants.sol";
import {Errors} from "../global/Errors.sol";
import {
    DepositParams,
    RedeemParams,
    AuraVaultDeploymentParams,
    InitParams,
    ReinvestRewardParams,
    StrategyVaultSettings,
    StrategyVaultState,
    PoolContext,
    TwoTokenPoolContext,
    StableOracleContext,
    MetaStable2TokenAuraStrategyContext,
    StrategyContext
} from "./balancer/BalancerVaultTypes.sol";
import {BalancerStrategyBase} from "./balancer/BalancerStrategyBase.sol";
import {MetaStable2TokenVaultMixin} from "./balancer/mixins/MetaStable2TokenVaultMixin.sol";
import {AuraStakingMixin} from "./balancer/mixins/AuraStakingMixin.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {BalancerVaultStorage} from "./balancer/internal/BalancerVaultStorage.sol";
import {StrategyUtils} from "./balancer/internal/strategy/StrategyUtils.sol";
import {SettlementUtils} from "./balancer/internal/settlement/SettlementUtils.sol";
import {TwoTokenPoolUtils} from "./balancer/internal/pool/TwoTokenPoolUtils.sol";
import {MetaStable2TokenAuraHelper} from "./balancer/external/MetaStable2TokenAuraHelper.sol";

contract MetaStable2TokenAuraVault is
    BalancerStrategyBase,
    MetaStable2TokenVaultMixin,
    AuraStakingMixin
{
    using BalancerVaultStorage for StrategyVaultSettings;
    using BalancerVaultStorage for StrategyVaultState;
    using StrategyUtils for StrategyContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    
    constructor(NotionalProxy notional_, AuraVaultDeploymentParams memory params) 
        MetaStable2TokenVaultMixin(
            notional_, 
            params.baseParams,
            params.primaryBorrowCurrencyId,
            params.baseParams.balancerPoolId
        )
        AuraStakingMixin(params.baseParams.liquidityGauge, params.auraRewardPool, params.baseParams.feeReceiver)
    {}

    function strategy() external override view returns (bytes4) {
        return bytes4(keccak256("MetaStable2TokenAura"));
    }

    function initialize(InitParams calldata params)
        external
        initializer
        onlyNotionalOwner
    {
        __INIT_VAULT(params.name, params.borrowCurrencyId);
        BalancerVaultStorage.setStrategyVaultSettings(
            params.settings, MAX_ORACLE_QUERY_WINDOW, BalancerConstants.VAULT_PERCENT_BASIS
        );
        _twoTokenPoolContext()._approveBalancerTokens(address(_auraStakingContext().auraBooster));
    }

    function _depositFromNotional(
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {
        DepositParams memory params = abi.decode(data, (DepositParams));
        MetaStable2TokenAuraStrategyContext memory context = _strategyContext();

        strategyTokensMinted = context.poolContext._deposit({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            deposit: deposit,
            params: params
        });
    }

    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 finalPrimaryBalance) {        
        RedeemParams memory params = abi.decode(data, (RedeemParams));
        MetaStable2TokenAuraStrategyContext memory context = _strategyContext();

        finalPrimaryBalance = context.poolContext._redeem({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            account: account,
            strategyTokens: strategyTokens,
            maturity: maturity,
            params: params
        });
    }

    function convertStrategyToUnderlying(
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view override returns (int256 underlyingValue) {
        MetaStable2TokenAuraStrategyContext memory context = _strategyContext();
        underlyingValue = context.poolContext._convertStrategyToUnderlying({
            strategyContext: context.baseStrategy,
            oracleContext: context.oracleContext.baseOracle,
            strategyTokenAmount: strategyTokenAmount
        });
    }

    function settleVaultNormal(
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        if (maturity <= block.timestamp) {
            revert Errors.PostMaturitySettlement();
        }
        if (block.timestamp < maturity - SETTLEMENT_PERIOD_IN_SECONDS) {
            revert Errors.NotInSettlementWindow();
        }
        MetaStable2TokenAuraStrategyContext memory context = _strategyContext();
        RedeemParams memory params = SettlementUtils._decodeParamsAndValidate(
            context.baseStrategy.vaultState.lastSettlementTimestamp,
            context.baseStrategy.vaultSettings.settlementCoolDownInMinutes,
            context.baseStrategy.vaultSettings.settlementSlippageLimitPercent,
            data
        );
        MetaStable2TokenAuraHelper.settleVault(
            context, maturity, strategyTokensToRedeem, params
        );
        context.baseStrategy.vaultState.lastSettlementTimestamp = uint32(block.timestamp);
        context.baseStrategy.vaultState.setStrategyVaultState();
    }

    function settleVaultPostMaturity(
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external onlyNotionalOwner {
        if (block.timestamp < maturity) {
            revert Errors.HasNotMatured();
        }
        MetaStable2TokenAuraStrategyContext memory context = _strategyContext();
        RedeemParams memory params = SettlementUtils._decodeParamsAndValidate(
            context.baseStrategy.vaultState.lastPostMaturitySettlementTimestamp,
            context.baseStrategy.vaultSettings.postMaturitySettlementCoolDownInMinutes,
            context.baseStrategy.vaultSettings.postMaturitySettlementSlippageLimitPercent,
            data
        );
        MetaStable2TokenAuraHelper.settleVault(
            context, maturity, strategyTokensToRedeem, params
        );
        context.baseStrategy.vaultState.lastPostMaturitySettlementTimestamp = uint32(block.timestamp);    
        context.baseStrategy.vaultState.setStrategyVaultState();  
    }

    function settleVaultEmergency(uint256 maturity, bytes calldata data) external {
        // No need for emergency settlement during the settlement window
        _revertInSettlementWindow(maturity);
        MetaStable2TokenAuraHelper.settleVaultEmergency(
            _strategyContext(), maturity, data
        );
    }

    function reinvestReward(ReinvestRewardParams calldata params) external {
        MetaStable2TokenAuraHelper.reinvestReward(_strategyContext(), params);
    }

    /// @notice Updates the vault settings
    /// @param settings vault settings
    function setStrategyVaultSettings(StrategyVaultSettings calldata settings)
        external
        onlyNotionalOwner
    {
        BalancerVaultStorage.setStrategyVaultSettings(
            settings, MAX_ORACLE_QUERY_WINDOW, BalancerConstants.VAULT_PERCENT_BASIS
        );
    }

    function _strategyContext() private view returns (MetaStable2TokenAuraStrategyContext memory) {
        return MetaStable2TokenAuraStrategyContext({
            poolContext: _twoTokenPoolContext(),
            oracleContext: _stableOracleContext(),
            stakingContext: _auraStakingContext(),
            baseStrategy: StrategyContext({
                totalBPTHeld: _bptHeld(),
                settlementPeriodInSeconds: SETTLEMENT_PERIOD_IN_SECONDS,
                tradingModule: TRADING_MODULE,
                vaultSettings: BalancerVaultStorage.getStrategyVaultSettings(),
                vaultState: BalancerVaultStorage.getStrategyVaultState(),
                feeReceiver: FEE_RECEIVER
            })
        });
    }
    
    function getStrategyContext() external view returns (MetaStable2TokenAuraStrategyContext memory) {
        return _strategyContext();
    }
    
    // @audit consolidate some of this into the pool mixin
    function convertBPTClaimToStrategyTokens(uint256 bptClaim, uint256 maturity)
        external view returns (uint256 strategyTokenAmount) {
        return _strategyContext().baseStrategy._convertBPTClaimToStrategyTokens(bptClaim);
    }

   /// @notice Converts strategy tokens to BPT
    function convertStrategyTokensToBPTClaim(uint256 strategyTokenAmount, uint256 maturity) 
        external view returns (uint256 bptClaim) {
        return _strategyContext().baseStrategy._convertStrategyTokensToBPTClaim(strategyTokenAmount);
    }

    /// @dev Gets the total BPT held by the aura reward pool
    function _bptHeld() internal view returns (uint256) {
        return AURA_REWARD_POOL.balanceOf(address(this));
    }

}
