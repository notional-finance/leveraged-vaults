// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {ConvexVaultDeploymentParams} from "./curve/CurveVaultTypes.sol";
import {Deployments} from "../global/Deployments.sol";
import {Constants} from "../global/Constants.sol";
import {IERC20} from "../utils/TokenUtils.sol";
import {ConvexStakingMixin} from "./curve/mixins/ConvexStakingMixin.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {IConvexBooster, IConvexBoosterArbitrum} from "../../interfaces/convex/IConvexBooster.sol";
import {IConvexRewardPool, IConvexRewardPoolArbitrum} from "../../interfaces/convex/IConvexRewardPool.sol";
import {
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
        uint256[2] memory amounts;
        amounts[0] = _amounts[0];
        amounts[1] = _amounts[1];
        (IERC20[] memory tokens, /* */) = TOKENS();

        uint256 msgValue;
        if (address(tokens[0]) == Deployments.ETH_ADDRESS) {
            msgValue = amounts[0];
        } else if (address(tokens[1]) == Deployments.ETH_ADDRESS) {
            msgValue = amounts[1];
        }

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
            // Redeem proportionally
            uint256[2] memory minAmounts;
            minAmounts[_PRIMARY_INDEX] = _minAmounts[_PRIMARY_INDEX];
            minAmounts[SECONDARY_INDEX] = _minAmounts[SECONDARY_INDEX];
            uint256[2] memory _exitBalances = pool.remove_liquidity(poolClaim, minAmounts);

            exitBalances[0] = _exitBalances[0];
            exitBalances[1] = _exitBalances[1];
        }
    }

    function _checkPriceAndCalculateValue(uint256 vaultShares) internal view override returns (int256 underlyingValue) {
        // Curve2TokenConvexStrategyContext memory context = _strategyContext();
        // return context.poolContext._convertStrategyToUnderlying({
        //     strategyContext: context.baseStrategy,
        //     vaultShareAmount: vaultShares
        // });
    } 

    function getSpotPrice(uint256 tokenIndex) external view returns (uint256 spotPrice) {
        // spotPrice = _strategyContext().poolContext._getSpotPrice(tokenIndex);
    }
}
