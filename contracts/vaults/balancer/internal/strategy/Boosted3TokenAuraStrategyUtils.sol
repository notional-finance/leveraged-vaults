// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    DepositParams, 
    RedeemParams,
    PoolParams,
    StrategyContext, 
    ThreeTokenPoolContext, 
    BoostedOracleContext,
    AuraStakingContext,
    StrategyVaultSettings,
    StrategyVaultState,
    SettlementState
} from "../../BalancerVaultTypes.sol";
import {SafeInt256} from "../../../../global/SafeInt256.sol";
import {NotionalUtils} from "../../../../utils/NotionalUtils.sol";
import {Boosted3TokenPoolUtils} from "../pool/Boosted3TokenPoolUtils.sol";
import {AuraStakingUtils} from "../staking/AuraStakingUtils.sol";
import {SettlementUtils} from "../settlement/SettlementUtils.sol";
import {StrategyUtils} from "./StrategyUtils.sol";
import {VaultUtils} from "../VaultUtils.sol";
import {BalancerUtils} from "../pool/BalancerUtils.sol";
import {IBoostedPool} from "../../../../../interfaces/balancer/IBalancerPool.sol";

library Boosted3TokenAuraStrategyUtils {
    using SafeInt256 for uint256;
    using Boosted3TokenAuraStrategyUtils for StrategyContext;
    using Boosted3TokenPoolUtils for ThreeTokenPoolContext;
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
        uint256 minBPT
    ) internal returns (uint256 strategyTokensMinted) {
        uint256 bptMinted = poolContext._joinPoolExactTokensIn(deposit, minBPT);

        // Transfer token to Aura protocol for boosted staking
        stakingContext.auraBooster.deposit(stakingContext.auraPoolId, bptMinted, true); // stake = true

        strategyTokensMinted = strategyContext._convertBPTClaimToStrategyTokens(
            bptMinted, NotionalUtils._totalSupplyInMaturity(maturity)
        );
        require(strategyTokensMinted <= type(uint80).max); /// @dev strategyTokensMinted overflow

        // Update global supply count
        strategyContext.vaultState.totalStrategyTokenGlobal += uint80(strategyTokensMinted);
        strategyContext.vaultState._setStrategyVaultState(); 
    }

    function _redeem(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        ThreeTokenPoolContext memory poolContext,
        uint256 strategyTokens,
        uint256 maturity,
        uint256 minPrimary
    ) internal returns (uint256 finalPrimaryBalance) {
        uint256 bptClaim = strategyContext._convertStrategyTokensToBPTClaim(
            strategyTokens, NotionalUtils._totalSupplyInMaturity(maturity)
        );

        if (bptClaim == 0) return 0;

        // Withdraw BPT tokens back to the vault for redemption
        stakingContext.auraRewardPool.withdrawAndUnwrap(bptClaim, false); // claimRewards = false

        uint256 primaryBalance = poolContext._exitPoolExactBPTIn(bptClaim, minPrimary);

        // Update global strategy token balance
        // This only needs to be updated for normal redemption
        // and emergency settlement. For normal and post-maturity settlement
        // scenarios (account == address(this) && data.length == 32), we
        // update totalStrategyTokenGlobal before this function is called.
        strategyContext.vaultState.totalStrategyTokenGlobal -= uint80(strategyTokens);
        strategyContext.vaultState._setStrategyVaultState(); 
        
        return primaryBalance;
    }

    function _convertStrategyToUnderlying(
        StrategyContext memory strategyContext,
        BoostedOracleContext memory oracleContext,
        ThreeTokenPoolContext memory poolContext,
        uint256 strategyTokenAmount,
        uint256 totalSupplyInMaturity
    ) internal view returns (int256 underlyingValue) {
        uint256 bptClaim = strategyContext._convertStrategyTokensToBPTClaim(
            strategyTokenAmount, totalSupplyInMaturity
        );
        
        underlyingValue = poolContext._getTimeWeightedPrimaryBalance(
            oracleContext, 
            strategyContext.tradingModule, 
            bptClaim
        ).toInt();
    }
}
