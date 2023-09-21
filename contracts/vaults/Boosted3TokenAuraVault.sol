// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Errors} from "../global/Errors.sol";
import {Deployments} from "../global/Deployments.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";
import {
    AuraVaultDeploymentParams,
    InitParams,
    Balancer3TokenPoolContext,
    Boosted3TokenAuraStrategyContext
} from "./balancer/BalancerVaultTypes.sol";
import {
    StrategyContext,
    StrategyVaultSettings,
    StrategyVaultState,
    ThreeTokenPoolContext,
    DepositParams,
    RedeemParams,
    ReinvestRewardParams
} from "./common/VaultTypes.sol";
import {StrategyUtils} from "./common/internal/strategy/StrategyUtils.sol";
import {BalancerConstants} from "./balancer/internal/BalancerConstants.sol";
import {Boosted3TokenPoolMixin} from "./balancer/mixins/Boosted3TokenPoolMixin.sol";
import {AuraStakingMixin} from "./balancer/mixins/AuraStakingMixin.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {VaultStorage} from "./common/VaultStorage.sol";
import {SettlementUtils} from "./common/internal/settlement/SettlementUtils.sol";
import {Balancer3TokenBoostedPoolUtils} from "./balancer/internal/pool/Balancer3TokenBoostedPoolUtils.sol";
import {Boosted3TokenAuraHelper} from "./balancer/external/Boosted3TokenAuraHelper.sol";
import {IBalancerPool} from "../../interfaces/balancer/IBalancerPool.sol";
import {IERC20} from "../../interfaces/IERC20.sol";

contract Boosted3TokenAuraVault is Boosted3TokenPoolMixin {
    using Balancer3TokenBoostedPoolUtils for Balancer3TokenPoolContext;
    using Balancer3TokenBoostedPoolUtils for ThreeTokenPoolContext;
    using StrategyUtils for StrategyContext;
    using VaultStorage for StrategyVaultState;
    using SettlementUtils for StrategyContext;
    using Boosted3TokenAuraHelper for Boosted3TokenAuraStrategyContext;

    constructor(NotionalProxy notional_, AuraVaultDeploymentParams memory params) 
        Boosted3TokenPoolMixin(notional_, params)
    {}

    function strategy() external override view returns (bytes4) {
        return bytes4(keccak256("Boosted3TokenAuraVault"));
    }

    function initialize(InitParams calldata params)
        external
        initializer
        onlyNotionalOwner
    {
        __INIT_VAULT(params.name, params.borrowCurrencyId);
        VaultStorage.setStrategyVaultSettings(params.settings);
        (uint256[] memory balances, uint256[] memory scalingFactors) = _getBalancesAndScaleFactors();

        _threeTokenPoolContext(balances, scalingFactors).basePool._approveBalancerTokens(
            address(_auraStakingContext().booster)
        );
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
        Boosted3TokenAuraHelper.settleVaultEmergency(
            _strategyContext(), maturity, data
        );
        _lockVault();
    }

    function restoreVault(uint256 minBPT) external whenLocked onlyNotionalOwner {
        Boosted3TokenAuraStrategyContext memory context = _strategyContext();

        uint256 bptAmount = context.poolContext._joinPoolAndStake({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            oracleContext: context.oracleContext,
            deposit: TokenUtils.tokenBalance(PRIMARY_TOKEN),
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
        return Boosted3TokenAuraHelper.reinvestReward(_strategyContext(), params);
    }

    function convertStrategyToUnderlying(
        address account,
        uint256 vaultShares,
        uint256 maturity
    ) public view virtual override whenNotLocked returns (int256 underlyingValue) {
        Boosted3TokenAuraStrategyContext memory context = _strategyContext();
        underlyingValue = context.convertStrategyToUnderlying(vaultShares);
    }

    /// @notice Updates the vault settings
    /// @param settings vault settings
    function setStrategyVaultSettings(StrategyVaultSettings calldata settings)
        external
        onlyNotionalOwner
    {
        VaultStorage.setStrategyVaultSettings(settings);
    }
    
    function getStrategyContext() external view returns (Boosted3TokenAuraStrategyContext memory) {
        return _strategyContext();
    }

    function getSpotPrice(uint8 tokenIndex) external view returns (uint256 spotPrice) {
        Boosted3TokenAuraStrategyContext memory context = _strategyContext();
        spotPrice = Boosted3TokenAuraHelper.getSpotPrice(context, tokenIndex);
    }

    function getEmergencySettlementPoolClaimAmount(uint256 maturity) external view returns (uint256 poolClaimToSettle) {
        Boosted3TokenAuraStrategyContext memory context = _strategyContext();
        poolClaimToSettle = context.baseStrategy._getEmergencySettlementParams({
            maturity: maturity, 
            totalPoolSupply: context.oracleContext.virtualSupply
        });
    }
}
