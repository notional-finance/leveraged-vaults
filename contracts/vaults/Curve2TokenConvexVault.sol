// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Deployments} from "../global/Deployments.sol";
import {Constants} from "../global/Constants.sol";
import {IERC20} from "../utils/TokenUtils.sol";
import {ConvexStakingMixin, ConvexVaultDeploymentParams} from "./curve/ConvexStakingMixin.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {IConvexBooster, IConvexBoosterArbitrum} from "../../interfaces/convex/IConvexBooster.sol";
import {IConvexRewardPool, IConvexRewardPoolArbitrum} from "../../interfaces/convex/IConvexRewardPool.sol";
import {
    ICurvePool,
    ICurve2TokenPool,
    ICurve2TokenPoolV1,
    ICurve2TokenPoolV2
} from "../../interfaces/curve/ICurvePool.sol";

contract Curve2TokenConvexVault is ConvexStakingMixin {
    constructor(NotionalProxy notional_, ConvexVaultDeploymentParams memory params) 
        ConvexStakingMixin(notional_, params) {}

    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("Curve2TokenConvexVault"));
    }

    function _joinPoolAndStake(
        uint256[] memory _amounts, uint256 minPoolClaim
    ) internal override returns (uint256 lpTokens) {
        // Only two tokens are ever allowed in this strategy, remaps the array
        // into a fixed length array here.
        uint256[2] memory amounts;
        amounts[0] = _amounts[0];
        amounts[1] = _amounts[1];

        // Although Curve uses ALT_ETH to represent native ETH, it is rewritten in the Curve2TokenPoolMixin
        // to the Deployments.ETH_ADDRESS which we use internally.
        (IERC20[] memory tokens, /* */) = TOKENS();
        uint256 msgValue;
        if (address(tokens[0]) == Deployments.ETH_ADDRESS) {
            msgValue = amounts[0];
        } else if (address(tokens[1]) == Deployments.ETH_ADDRESS) {
            msgValue = amounts[1];
        }

        // Slightly different method signatures in v1 and v2
        if (IS_CURVE_V2) {
            lpTokens = ICurve2TokenPoolV2(CURVE_POOL).add_liquidity{value: msgValue}(
                amounts, minPoolClaim, 0 < msgValue // use_eth = true if msgValue > 0
            );
        } else {
            lpTokens = ICurve2TokenPoolV1(CURVE_POOL).add_liquidity{value: msgValue}(
                amounts, minPoolClaim
            );
        }

        // Method signatures are slightly different on mainnet and arbitrum
        bool success;
        if (Deployments.CHAIN_ID == Constants.CHAIN_ID_MAINNET) {
            success = IConvexBooster(CONVEX_BOOSTER).deposit(CONVEX_POOL_ID, lpTokens, true);
        } else if (Deployments.CHAIN_ID == Constants.CHAIN_ID_ARBITRUM) {
            success = IConvexBoosterArbitrum(CONVEX_BOOSTER).deposit(CONVEX_POOL_ID, lpTokens);
        }
        require(success);
    }

    function _unstakeAndExitPool(
        uint256 poolClaim, uint256[] memory _minAmounts, bool isSingleSided
    ) internal override returns (uint256[] memory exitBalances) {
        bool success;
        // Do not claim rewards when unstaking
        if (Deployments.CHAIN_ID == Constants.CHAIN_ID_MAINNET) {
            success = IConvexRewardPool(CONVEX_REWARD_POOL).withdrawAndUnwrap(poolClaim, false);
        } else if (Deployments.CHAIN_ID == Constants.CHAIN_ID_ARBITRUM) {
            success = IConvexRewardPoolArbitrum(CONVEX_REWARD_POOL).withdraw(poolClaim, false);
        }
        require(success);

        ICurve2TokenPool pool = ICurve2TokenPool(CURVE_POOL);
        exitBalances = new uint256[](2);
        if (isSingleSided) {
            // Redeem single-sided
            exitBalances[_PRIMARY_INDEX] = pool.remove_liquidity_one_coin(
                poolClaim, int8(_PRIMARY_INDEX), _minAmounts[_PRIMARY_INDEX]
            );
        } else {
            // Redeem proportionally, min amounts are rewritten to a fixed length array
            uint256[2] memory minAmounts;
            minAmounts[0] = _minAmounts[0];
            minAmounts[1] = _minAmounts[1];

            uint256[2] memory _exitBalances = pool.remove_liquidity(poolClaim, minAmounts);
            exitBalances[0] = _exitBalances[0];
            exitBalances[1] = _exitBalances[1];
        }
    }

    function _checkPriceAndCalculateValue() internal view override returns (uint256 oneLPValueInPrimary) {
        uint256[] memory balances = new uint256[](2);
        balances[0] = ICurvePool(CURVE_POOL).balances(0);
        balances[1] = ICurvePool(CURVE_POOL).balances(1);

        // The primary index spot price is left as zero.
        uint256[] memory spotPrices = new uint256[](2);
        uint256 primaryPrecision = 10 ** PRIMARY_DECIMALS;
        uint256 secondaryPrecision = 10 ** SECONDARY_DECIMALS;

        // `get_dy` returns the price of one unit of the primary token
        // converted to the secondary token. The spot price is in secondary
        // precision and then we convert it to POOL_PRECISION.
        spotPrices[SECONDARY_INDEX] = ICurvePool(CURVE_POOL).get_dy(
            int8(_PRIMARY_INDEX), int8(SECONDARY_INDEX), primaryPrecision
        ) * POOL_PRECISION() / secondaryPrecision;

        return _calculateLPTokenValue(balances, spotPrices);
    }
}
