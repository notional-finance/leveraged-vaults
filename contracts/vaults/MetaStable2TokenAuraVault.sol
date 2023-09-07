// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {BalancerConstants} from "./balancer/internal/BalancerConstants.sol";
import {Errors} from "../global/Errors.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";
import {
    AuraVaultDeploymentParams,
    InitParams,
    StableOracleContext,
    Balancer2TokenPoolContext,
    MetaStable2TokenAuraStrategyContext
} from "./balancer/BalancerVaultTypes.sol";
import {
    StrategyContext,
    StrategyVaultSettings,
    StrategyVaultState,
    TwoTokenPoolContext,
    DepositParams,
    RedeemParams,
    ReinvestRewardParams
} from "./common/VaultTypes.sol";
import {MetaStable2TokenVaultMixin} from "./balancer/mixins/MetaStable2TokenVaultMixin.sol";
import {AuraStakingMixin} from "./balancer/mixins/AuraStakingMixin.sol";
import {VaultStorage} from "./common/VaultStorage.sol";
import {StrategyUtils} from "./common/internal/strategy/StrategyUtils.sol";
import {SettlementUtils} from "./common/internal/settlement/SettlementUtils.sol";
import {Balancer2TokenPoolUtils} from "./balancer/internal/pool/Balancer2TokenPoolUtils.sol";
import {Stable2TokenOracleMath} from "./balancer/internal/math/Stable2TokenOracleMath.sol";
import {MetaStable2TokenAuraHelper} from "./balancer/external/MetaStable2TokenAuraHelper.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IAuraRewardPool} from "../../interfaces/aura/IAuraRewardPool.sol";

contract MetaStable2TokenAuraVault is MetaStable2TokenVaultMixin {
    using VaultStorage for StrategyVaultSettings;
    using VaultStorage for StrategyVaultState;
    using StrategyUtils for StrategyContext;
    using SettlementUtils for StrategyContext;
    using Balancer2TokenPoolUtils for Balancer2TokenPoolContext;
    using Balancer2TokenPoolUtils for TwoTokenPoolContext;
    using MetaStable2TokenAuraHelper for MetaStable2TokenAuraStrategyContext;
    using TokenUtils for IERC20;
    
    constructor(
        NotionalProxy notional_, 
        AuraVaultDeploymentParams memory params) 
        MetaStable2TokenVaultMixin(notional_, params) {
    }

    function strategy() external override view returns (bytes4) {
        return bytes4(keccak256("MetaStable2TokenAura"));
    }

    function initialize(InitParams calldata params)
        external
        initializer
        onlyNotionalOwner
    {
        __INIT_VAULT(params.name, params.borrowCurrencyId);
        VaultStorage.setStrategyVaultSettings(params.settings);
        _twoTokenPoolContext().basePool._approveBalancerTokens(address(_auraStakingContext().booster));
    }

    function _depositFromNotional(
        address account,
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

    function convertStrategyToUnderlying(
        address account,
        uint256 vaultShares,
        uint256 maturity
    ) public view virtual override whenNotLocked returns (int256 underlyingValue) {
        MetaStable2TokenAuraStrategyContext memory context = _strategyContext();
        underlyingValue = context.poolContext._convertStrategyToUnderlying({
            strategyContext: context.baseStrategy,
            oracleContext: context.oracleContext,
            strategyTokenAmount: vaultShares
        });
    }

    function settleVaultEmergency(uint256 maturity, bytes calldata data) 
        external whenNotLocked onlyRole(EMERGENCY_SETTLEMENT_ROLE) {
        MetaStable2TokenAuraHelper.settleVaultEmergency(
            _strategyContext(), maturity, data
        );
        _lockVault();
    }

    function restoreVault(uint256 minBPT) external whenLocked onlyNotionalOwner {
        MetaStable2TokenAuraStrategyContext memory context = _strategyContext();

        uint256 bptAmount = context.poolContext._joinPoolAndStake({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            primaryAmount: TokenUtils.tokenBalance(PRIMARY_TOKEN),
            secondaryAmount: TokenUtils.tokenBalance(SECONDARY_TOKEN),
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
        return MetaStable2TokenAuraHelper.reinvestReward(_strategyContext(), params);
    }

    /// @notice Updates the vault settings
    /// @param settings vault settings
    function setStrategyVaultSettings(StrategyVaultSettings calldata settings)
        external
        onlyNotionalOwner
    {
        VaultStorage.setStrategyVaultSettings(settings);
    }
    
    function getStrategyContext() external view returns (MetaStable2TokenAuraStrategyContext memory) {
        return _strategyContext();
    }

    function getSpotPrice(uint256 tokenIndex) external view returns (uint256 spotPrice) {
        MetaStable2TokenAuraStrategyContext memory context = _strategyContext();
        spotPrice = Stable2TokenOracleMath._getSpotPrice(
            context.oracleContext, 
            context.poolContext, 
            context.poolContext.basePool.primaryBalance,
            context.poolContext.basePool.secondaryBalance,
            tokenIndex
        );
    }

    function getEmergencySettlementPoolClaimAmount(uint256 maturity) external view returns (uint256 poolClaimToSettle) {
        MetaStable2TokenAuraStrategyContext memory context = _strategyContext();
        poolClaimToSettle = context.baseStrategy._getEmergencySettlementParams({
            maturity: maturity, 
            totalPoolSupply: context.poolContext.basePool.poolToken.totalSupply()
        });
    }
}
