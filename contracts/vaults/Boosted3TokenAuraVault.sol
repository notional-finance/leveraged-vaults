// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {Errors} from "../global/Errors.sol";
import {Deployments} from "../global/Deployments.sol";
import {
    DepositParams,
    RedeemParams,
    AuraVaultDeploymentParams,
    InitParams,
    ReinvestRewardParams,
    StrategyVaultSettings,
    StrategyVaultState,
    PoolContext,
    ThreeTokenPoolContext,
    Boosted3TokenAuraStrategyContext,
    StrategyContext
} from "./balancer/BalancerVaultTypes.sol";
import {BalancerStrategyBase} from "./balancer/BalancerStrategyBase.sol";
import {Boosted3TokenPoolMixin} from "./balancer/mixins/Boosted3TokenPoolMixin.sol";
import {AuraStakingMixin} from "./balancer/mixins/AuraStakingMixin.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {BalancerVaultStorage} from "./balancer/internal/BalancerVaultStorage.sol";
import {StrategyUtils} from "./balancer/internal/strategy/StrategyUtils.sol";
import {SettlementUtils} from "./balancer/internal/settlement/SettlementUtils.sol";
import {Boosted3TokenPoolUtils} from "./balancer/internal/pool/Boosted3TokenPoolUtils.sol";
import {Boosted3TokenAuraHelper} from "./balancer/external/Boosted3TokenAuraHelper.sol";

contract Boosted3TokenAuraVault is Boosted3TokenPoolMixin {
    using Boosted3TokenPoolUtils for ThreeTokenPoolContext;
    using StrategyUtils for StrategyContext;
    using BalancerVaultStorage for StrategyVaultState;

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
        // 3 token vaults do not use the Balancer oracle
        BalancerVaultStorage.setStrategyVaultSettings(
            params.settings, 
            0, // Max Balancer oracle window size
            0  // Balancer oracle weight
        );

        (
            /* address[] memory tokens */,
            uint256[] memory balances,
            /* uint256 lastChangeBlock */
        ) = Deployments.BALANCER_VAULT.getPoolTokens(BALANCER_POOL_ID);

        _threeTokenPoolContext(balances)._approveBalancerTokens(address(_auraStakingContext().auraBooster));
    }

    function _depositFromNotional(
        address /* account */,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {
        // Entering the vault is not allowed within the settlement window
        DepositParams memory params = abi.decode(data, (DepositParams));
        Boosted3TokenAuraStrategyContext memory context = _strategyContext();

        strategyTokensMinted = context.poolContext._deposit({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            oracleContext: context.oracleContext, 
            deposit: deposit,
            minBPT: params.minBPT
        });
    }

    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 finalPrimaryBalance) {
        RedeemParams memory params = abi.decode(data, (RedeemParams));
        Boosted3TokenAuraStrategyContext memory context = _strategyContext();

        finalPrimaryBalance = context.poolContext._redeem({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            strategyTokens: strategyTokens,
            minPrimary: params.minPrimary
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
        Boosted3TokenAuraStrategyContext memory context = _strategyContext();
        SettlementUtils._validateCoolDown(
            context.baseStrategy.vaultState.lastSettlementTimestamp,
            context.baseStrategy.vaultSettings.settlementCoolDownInMinutes
        );
        RedeemParams memory params = SettlementUtils._decodeParamsAndValidate(
            context.baseStrategy.vaultSettings.settlementSlippageLimitPercent,
            data
        );
        Boosted3TokenAuraHelper.settleVault(
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
        Boosted3TokenAuraStrategyContext memory context = _strategyContext();
        SettlementUtils._validateCoolDown(
            context.baseStrategy.vaultState.lastPostMaturitySettlementTimestamp,
            context.baseStrategy.vaultSettings.postMaturitySettlementCoolDownInMinutes
        );
        RedeemParams memory params = SettlementUtils._decodeParamsAndValidate(
            context.baseStrategy.vaultSettings.postMaturitySettlementSlippageLimitPercent,
            data
        );
        Boosted3TokenAuraHelper.settleVault(
            context, maturity, strategyTokensToRedeem, params
        );
        context.baseStrategy.vaultState.lastPostMaturitySettlementTimestamp = uint32(block.timestamp);    
        context.baseStrategy.vaultState.setStrategyVaultState();  
    }

    function settleVaultEmergency(uint256 maturity, bytes calldata data) external {
        // No need for emergency settlement during the settlement window
        _revertInSettlementWindow(maturity);
        Boosted3TokenAuraHelper.settleVaultEmergency(
            _strategyContext(), maturity, data
        );
    }

    function reinvestReward(ReinvestRewardParams calldata params) external {
        Boosted3TokenAuraHelper.reinvestReward(_strategyContext(), params);
    }

    function convertStrategyToUnderlying(
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view virtual override returns (int256 underlyingValue) {
        Boosted3TokenAuraStrategyContext memory context = _strategyContext();
        underlyingValue = context.poolContext._convertStrategyToUnderlying({
            strategyContext: context.baseStrategy,
            oracleContext: context.oracleContext,
            strategyTokenAmount: strategyTokenAmount
        });
    }

    /// @notice Updates the vault settings
    /// @param settings vault settings
    function setStrategyVaultSettings(StrategyVaultSettings calldata settings)
        external
        onlyNotionalOwner
    {
        // 3 token vaults do not use the Balancer oracle
        BalancerVaultStorage.setStrategyVaultSettings(
            settings, 
            0, // Max Balancer oracle window size
            0  // Balancer oracle weight
        );
    }

    function _strategyContext() private view returns (Boosted3TokenAuraStrategyContext memory) {
        (
            /* address[] memory tokens */,
            uint256[] memory balances,
            /* uint256 lastChangeBlock */
        ) = Deployments.BALANCER_VAULT.getPoolTokens(BALANCER_POOL_ID);

        return Boosted3TokenAuraStrategyContext({
            poolContext: _threeTokenPoolContext(balances),
            oracleContext: _boostedOracleContext(balances),
            stakingContext: _auraStakingContext(),
            baseStrategy: _baseStrategyContext()
        });
    }
    
    function getStrategyContext() external view returns (Boosted3TokenAuraStrategyContext memory) {
        return _strategyContext();
    }
}
