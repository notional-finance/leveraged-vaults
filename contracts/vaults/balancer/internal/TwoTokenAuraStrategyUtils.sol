// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    PoolParams,
    TwoTokenPoolContext,
    AuraStakingContext,
    StrategyContext,
    StrategyVaultSettings,
    StrategyVaultState
} from "../BalancerVaultTypes.sol";
import {AuraStakingUtils} from "./AuraStakingUtils.sol";
import {VaultUtils} from "./VaultUtils.sol";
import {TwoTokenPoolUtils} from "./TwoTokenPoolUtils.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {Constants} from "../../../global/Constants.sol";
import {NotionalUtils} from "../../../utils/NotionalUtils.sol";

library TwoTokenAuraStrategyUtils {
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using AuraStakingUtils for AuraStakingContext;
    using VaultUtils for StrategyVaultSettings;
    using VaultUtils for StrategyVaultState;

    function _joinPoolAndStake(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        TwoTokenPoolContext memory poolContext,
        uint256 primaryAmount,
        uint256 secondaryAmount,
        uint256 minBPT
    ) internal returns (uint256 bptMinted) {
        // prettier-ignore
        PoolParams memory poolParams = poolContext._getPoolParams( 
            primaryAmount, 
            secondaryAmount,
            true // isJoin
        );

        // Join the balancer pool and stake the tokens for boosting
        bptMinted = stakingContext._joinPoolAndStake({
            poolContext: poolContext.baseContext,
            poolParams: poolParams,
            totalBPTHeld: strategyContext.totalBPTHeld,
            bptThreshold: strategyContext.vaultSettings._bptThreshold(
                poolContext.baseContext.pool.totalSupply()
            ),
            minBPT: minBPT
        });
    }

    /// @notice Converts strategy tokens to BPT
    function _convertStrategyTokensToBPTClaim(
        StrategyContext memory context,
        uint256 strategyTokenAmount, 
        uint256 maturity
    ) internal view returns (uint256 bptClaim) {
        StrategyVaultState memory state = context.vaultState;
        if (state.totalStrategyTokenGlobal == 0)
            return strategyTokenAmount;

        uint256 totalSupplyInMaturity = NotionalUtils._totalSupplyInMaturity(maturity);
        uint256 bptHeldInMaturity = state._getBPTHeldInMaturity(totalSupplyInMaturity, context.totalBPTHeld);
        bptClaim = (bptHeldInMaturity * strategyTokenAmount) / totalSupplyInMaturity;
    }

    /// @notice Converts BPT to strategy tokens
    function _convertBPTClaimToStrategyTokens(
        StrategyContext memory context,
        uint256 bptClaim, 
        uint256 maturity
    ) internal view returns (uint256 strategyTokenAmount) {
        StrategyVaultState memory state = context.vaultState;
        if (state.totalStrategyTokenGlobal == 0) {
            // Strategy tokens are in 8 decimal precision, BPT is in 18. Scale the minted amount down.
            return (bptClaim * uint256(Constants.INTERNAL_TOKEN_PRECISION)) / 
                BalancerUtils.BALANCER_PRECISION;
        }

        uint256 totalSupplyInMaturity = NotionalUtils._totalSupplyInMaturity(maturity);
        uint256 bptHeldInMaturity = state._getBPTHeldInMaturity(totalSupplyInMaturity, context.totalBPTHeld);

        // BPT held in maturity is calculated before the new BPT tokens are minted, so this calculation
        // is the tokens minted that will give the account a corresponding share of the new bpt balance held.
        // The precision here will be the same as strategy token supply.
        strategyTokenAmount = (bptClaim * totalSupplyInMaturity) / bptHeldInMaturity;
    }
}
