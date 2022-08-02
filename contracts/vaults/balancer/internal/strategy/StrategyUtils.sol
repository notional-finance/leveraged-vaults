// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {StrategyContext, StrategyVaultState} from "../../BalancerVaultTypes.sol";
import {NotionalUtils} from "../../../../utils/NotionalUtils.sol";
import {BalancerUtils} from "../pool/BalancerUtils.sol";
import {Constants} from "../../../../global/Constants.sol";
import {VaultUtils} from "../VaultUtils.sol";

library StrategyUtils {
    using VaultUtils for StrategyVaultState;

    /// @notice Converts strategy tokens to BPT
    function _convertStrategyTokensToBPTClaim(
        StrategyContext memory context,
        uint256 strategyTokenAmount, 
        uint256 totalSupplyInMaturity
    ) internal pure returns (uint256 bptClaim) {
        StrategyVaultState memory state = context.vaultState;
        if (state.totalStrategyTokenGlobal == 0) {
            // Strategy tokens are in 8 decimal precision, BPT is in 18
            return (strategyTokenAmount * BalancerUtils.BALANCER_PRECISION) /
                uint256(Constants.INTERNAL_TOKEN_PRECISION);
        }

        uint256 bptHeldInMaturity = state._getBPTHeldInMaturity(totalSupplyInMaturity, context.totalBPTHeld);

        if (totalSupplyInMaturity == 0) {
            // Strategy tokens are in 8 decimal precision, BPT is in 18
            return (strategyTokenAmount * BalancerUtils.BALANCER_PRECISION) /
                uint256(Constants.INTERNAL_TOKEN_PRECISION);
        }

        bptClaim = (bptHeldInMaturity * strategyTokenAmount) / totalSupplyInMaturity;
    }

    /// @notice Converts BPT to strategy tokens
    function _convertBPTClaimToStrategyTokens(
        StrategyContext memory context,
        uint256 bptClaim, 
        uint256 totalSupplyInMaturity
    ) internal pure returns (uint256 strategyTokenAmount) {
        StrategyVaultState memory state = context.vaultState;
        if (state.totalStrategyTokenGlobal == 0) {
            // Strategy tokens are in 8 decimal precision, BPT is in 18. Scale the minted amount down.
            return (bptClaim * uint256(Constants.INTERNAL_TOKEN_PRECISION)) / 
                BalancerUtils.BALANCER_PRECISION;
        }

        uint256 bptHeldInMaturity = state._getBPTHeldInMaturity(totalSupplyInMaturity, context.totalBPTHeld);

        if (bptHeldInMaturity == 0) {
            // Strategy tokens are in 8 decimal precision, BPT is in 18. Scale the minted amount down.
            return (bptClaim * uint256(Constants.INTERNAL_TOKEN_PRECISION)) / 
                BalancerUtils.BALANCER_PRECISION;
        }

        // BPT held in maturity is calculated before the new BPT tokens are minted, so this calculation
        // is the tokens minted that will give the account a corresponding share of the new bpt balance held.
        // The precision here will be the same as strategy token supply.
        strategyTokenAmount = (bptClaim * totalSupplyInMaturity) / bptHeldInMaturity;
    }
}
