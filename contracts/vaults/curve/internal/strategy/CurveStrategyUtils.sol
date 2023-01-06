// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {StrategyContext} from "../../CurveVaultTypes.sol";
import {TokenUtils, IERC20} from "../../../../utils/TokenUtils.sol";
import {Deployments} from "../../../../global/Deployments.sol";
import {Constants} from "../../../../global/Constants.sol";
import {CurveConstants} from "../CurveConstants.sol";

library CurveStrategyUtils {
    using TokenUtils for IERC20;

    /// @notice Converts strategy tokens to LP tokens
    function _convertStrategyTokensToPoolClaim(StrategyContext memory context, uint256 strategyTokenAmount)
        internal pure returns (uint256 poolClaim) {
        require(strategyTokenAmount <= context.vaultState.totalStrategyTokenGlobal);
        if (context.vaultState.totalStrategyTokenGlobal > 0) {
            poolClaim = (strategyTokenAmount * context.vaultState.totalPoolClaim) / context.vaultState.totalStrategyTokenGlobal;
        }
    }

    /// @notice Converts LP tokens to strategy tokens
    function _convertPoolClaimToStrategyTokens(StrategyContext memory context, uint256 poolClaim)
        internal pure returns (uint256 strategyTokenAmount) {
        if (context.vaultState.totalPoolClaim == 0) {
            // Strategy tokens are in 8 decimal precision, BPT is in 18. Scale the minted amount down.
            return (poolClaim * uint256(Constants.INTERNAL_TOKEN_PRECISION)) / 
                CurveConstants.POOL_TOKEN_PRECISION;
        }

        // Pool claim in maturity is calculated before the new pool tokens are minted, so this calculation
        // is the tokens minted that will give the account a corresponding share of the new pool balance held.
        // The precision here will be the same as strategy token supply.
        strategyTokenAmount = (poolClaim * context.vaultState.totalStrategyTokenGlobal) / context.vaultState.totalPoolClaim;
    }
}
