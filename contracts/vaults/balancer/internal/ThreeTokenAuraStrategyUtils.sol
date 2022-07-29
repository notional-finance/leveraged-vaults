// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    DepositParams, 
    RedeemParams,
    PoolParams,
    StrategyContext, 
    ThreeTokenPoolContext, 
    AuraStakingContext,
    StrategyVaultSettings,
    StrategyVaultState
} from "../BalancerVaultTypes.sol";
import {ThreeTokenPoolUtils} from "./ThreeTokenPoolUtils.sol";
import {AuraStakingUtils} from "./AuraStakingUtils.sol";
import {StrategyUtils} from "./StrategyUtils.sol";
import {VaultUtils} from "./VaultUtils.sol";

library ThreeTokenAuraStrategyUtils {
    using ThreeTokenAuraStrategyUtils for StrategyContext;
    using ThreeTokenPoolUtils for ThreeTokenPoolContext;
    using AuraStakingUtils for AuraStakingContext;
    using StrategyUtils for StrategyContext;
    using VaultUtils for StrategyVaultSettings;
    using VaultUtils for StrategyVaultState;

    function _deposit(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        ThreeTokenPoolContext memory poolContext,
        uint256 deposit,
        uint256 maturity,
        DepositParams memory params
    ) internal returns (uint256 strategyTokensMinted) {
        uint256 bptMinted = strategyContext._joinPoolAndStake({
            stakingContext: stakingContext,
            poolContext: poolContext,
            primaryAmount: deposit,
            secondaryAmount: 0,
            tertiaryAmount: 0,
            minBPT: params.minBPT
        });

        // Update _bptHeld() in memory
        strategyContext.totalBPTHeld += bptMinted;

        strategyTokensMinted = strategyContext._convertBPTClaimToStrategyTokens(bptMinted, maturity);
        require(strategyTokensMinted <= type(uint80).max); /// @dev strategyTokensMinted overflow

        // Update global supply count
        strategyContext.vaultState.totalStrategyTokenGlobal += uint80(strategyTokensMinted);
        strategyContext.vaultState._setStrategyVaultState(); 
    }

    function _redeem(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        ThreeTokenPoolContext memory poolContext,
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        RedeemParams memory params
    ) internal returns (uint256 finalPrimaryBalance) {
    
    }

    function _joinPoolAndStake(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        ThreeTokenPoolContext memory poolContext,
        uint256 primaryAmount,
        uint256 secondaryAmount,
        uint256 tertiaryAmount,
        uint256 minBPT
    ) internal returns (uint256 bptMinted) {
        // prettier-ignore
        PoolParams memory poolParams = poolContext._getBoostedPoolParams( 
            primaryAmount, 
            secondaryAmount,
            tertiaryAmount,
            true // isJoin
        );

        // Join the balancer pool and stake the tokens for boosting
        bptMinted = stakingContext._joinPoolAndStake({
            poolContext: poolContext.basePool.basePool,
            poolParams: poolParams,
            totalBPTHeld: strategyContext.totalBPTHeld,
            bptThreshold: strategyContext.vaultSettings._bptThreshold(
                poolContext.basePool.basePool.pool.totalSupply()
            ),
            minBPT: minBPT
        });
    }

    function _convertStrategyToUnderlying(
        StrategyContext memory strategyContext,
        ThreeTokenPoolContext memory poolContext,
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) internal view returns (int256 underlyingValue) {
        // TODO: implement this
    }
}
