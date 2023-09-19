// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Errors} from "../global/Errors.sol";
import {Deployments} from "../global/Deployments.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";
import {
    AuraVaultDeploymentParams,
    InitParams,
    BalancerComposableAuraStrategyContext,
    BalancerComposablePoolContext
} from "./balancer/BalancerVaultTypes.sol";
import {
    StrategyContext,
    StrategyVaultSettings,
    StrategyVaultState,
    ComposablePoolContext,
    DepositParams,
    ReinvestRewardParams
} from "./common/VaultTypes.sol";
import {StrategyUtils} from "./common/internal/strategy/StrategyUtils.sol";
import {BalancerConstants} from "./balancer/internal/BalancerConstants.sol";
import {BalancerComposablePoolUtils} from "./balancer/internal/pool/BalancerComposablePoolUtils.sol";
import {ComposableOracleMath} from "./balancer/internal/math/ComposableOracleMath.sol";
import {ComposableAuraHelper} from "./balancer/external/ComposableAuraHelper.sol";
import {BalancerComposablePoolMixin} from "./balancer/mixins/BalancerComposablePoolMixin.sol";
import {AuraStakingMixin} from "./balancer/mixins/AuraStakingMixin.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {VaultStorage} from "./common/VaultStorage.sol";
import {SettlementUtils} from "./common/internal/settlement/SettlementUtils.sol";
import {IBalancerPool} from "../../interfaces/balancer/IBalancerPool.sol";
import {IERC20} from "../../interfaces/IERC20.sol";

contract BalancerComposableAuraVault is BalancerComposablePoolMixin {
    using StrategyUtils for StrategyContext;
    using VaultStorage for StrategyVaultState;
    using SettlementUtils for StrategyContext;
    using ComposableAuraHelper for BalancerComposableAuraStrategyContext;
    using BalancerComposablePoolUtils for ComposablePoolContext;
    using BalancerComposablePoolUtils for BalancerComposablePoolContext;

    constructor(NotionalProxy notional_, AuraVaultDeploymentParams memory params) 
        BalancerComposablePoolMixin(notional_, params)
    {}

    function strategy() external override view returns (bytes4) {
        return bytes4(keccak256("BalancerComposableAuraVault"));
    }

    function initialize(InitParams calldata params)
        external
        initializer
        onlyNotionalOwner
    {
        __INIT_VAULT(params.name, params.borrowCurrencyId);
        VaultStorage.setStrategyVaultSettings(params.settings);

        _composablePoolContext().basePool._approveBalancerTokens(address(_auraStakingContext().booster));
    }

    function _depositFromNotional(
        address /* account */,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override whenNotLocked returns (uint256 vaultSharesMinted) {
        vaultSharesMinted = _strategyContext().deposit(deposit, data);
    }

    function _redeemFromNotional(
        address account,
        uint256 vaultShares,
        uint256 maturity,
        bytes calldata data
    ) internal override whenNotLocked returns (uint256 finalPrimaryBalance) {
        finalPrimaryBalance = _strategyContext().redeem(vaultShares, data);
    }

    function settleVaultEmergency(uint256 maturity, bytes calldata data) 
        external whenNotLocked onlyRole(EMERGENCY_SETTLEMENT_ROLE) {
        ComposableAuraHelper.settleVaultEmergency(
            _strategyContext(), maturity, data
        );
        _lockVault();
    }

    function restoreVault(uint256 minBPT) external whenLocked onlyNotionalOwner {
        BalancerComposableAuraStrategyContext memory context = _strategyContext();

        uint256[] memory amounts = new uint256[](context.poolContext.basePool.tokens.length);

        for (uint256 i; i < context.poolContext.basePool.tokens.length; i++) {
            if (i == context.poolContext.bptIndex) continue;
            amounts[i] = TokenUtils.tokenBalance(context.poolContext.basePool.tokens[i]);
        }

        uint256 bptAmount = context.poolContext._joinPoolAndStake({
            oracleContext: context.oracleContext,
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            amounts: amounts,
            minBPT: minBPT
        });

        context.baseStrategy.vaultState.totalPoolClaim += bptAmount;
        context.baseStrategy.vaultState.setStrategyVaultState(); 

        _unlockVault();
    }

    function reinvestReward(ReinvestRewardParams calldata params) 
        external whenNotLocked onlyRole(REWARD_REINVESTMENT_ROLE) returns (
            address rewardToken,
            uint256 amountSold, 
            uint256 poolClaimAmount
    ) {
        return ComposableAuraHelper.reinvestReward(_strategyContext(), params);
    }

    function convertStrategyToUnderlying(
        address account,
        uint256 vaultShares,
        uint256 maturity
    ) public view virtual override whenNotLocked returns (int256 underlyingValue) {
        BalancerComposableAuraStrategyContext memory context = _strategyContext();
        underlyingValue = context.poolContext._convertStrategyToUnderlying({
            strategyContext: context.baseStrategy,
            oracleContext: context.oracleContext,
            strategyTokenAmount: vaultShares
        });
    }

    /// @notice Updates the vault settings
    /// @param settings vault settings
    function setStrategyVaultSettings(StrategyVaultSettings calldata settings)
        external
        onlyNotionalOwner
    {
        VaultStorage.setStrategyVaultSettings(settings);
    }
    
    function getStrategyContext() external view returns (BalancerComposableAuraStrategyContext memory) {
        return _strategyContext();
    }

    function getSpotPrice(uint8 tokenIndex) external view returns (uint256 spotPrice) {
        BalancerComposableAuraStrategyContext memory context = _strategyContext();
        spotPrice = ComposableOracleMath._getSpotPrice(
            context.oracleContext, 
            context.poolContext,
            context.poolContext.basePool.primaryIndex,
            tokenIndex
        );
    }

    function getEmergencySettlementPoolClaimAmount(uint256 maturity) external view returns (uint256 poolClaimToSettle) {
        BalancerComposableAuraStrategyContext memory context = _strategyContext();
        poolClaimToSettle = context.baseStrategy._getEmergencySettlementParams({
            maturity: maturity, 
            totalPoolSupply: context.oracleContext.virtualSupply
        });
    }
}
