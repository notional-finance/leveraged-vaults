// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {Deployments} from "@deployments/Deployments.sol";
import {Constants} from "@contracts/global/Constants.sol";
import {IERC20, TokenUtils} from "@contracts/utils/TokenUtils.sol";
import {ConvexStakingMixin, ConvexVaultDeploymentParams} from "./mixins/ConvexStakingMixin.sol";
import {NotionalProxy} from "@interfaces/notional/NotionalProxy.sol";
import {IConvexBooster, IConvexBoosterArbitrum} from "@interfaces/convex/IConvexBooster.sol";
import {IConvexRewardPool, IConvexRewardPoolArbitrum} from "@interfaces/convex/IConvexRewardPool.sol";
import {
    CurveInterface,
    ICurvePool,
    ICurve2TokenPoolV1,
    ICurve2TokenPoolV2,
    ICurveStableSwapNG
} from "@interfaces/curve/ICurvePool.sol";

contract Curve2TokenConvexVault is ConvexStakingMixin {
    // This contract does not properly support Curve pools where one of the tokens is
    // held as an LP token. However, unlike Balancer pools there is no reliable way to
    // determine if the token held in the Curve pool is an LP token or not, therefore
    // we do not have an explicit check here.
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
        if (CURVE_INTERFACE == CurveInterface.V1) {
            lpTokens = ICurve2TokenPoolV1(CURVE_POOL).add_liquidity{value: msgValue}(
                amounts, minPoolClaim
            );
        } else if (CURVE_INTERFACE == CurveInterface.V2) {
            lpTokens = ICurve2TokenPoolV2(CURVE_POOL).add_liquidity{value: msgValue}(
                amounts, minPoolClaim, 0 < msgValue // use_eth = true if msgValue > 0
            );
        } else if (CURVE_INTERFACE == CurveInterface.StableSwapNG) {
            // StableSwapNG uses dynamic arrays
            lpTokens = ICurveStableSwapNG(CURVE_POOL).add_liquidity{value: msgValue}(
                _amounts, minPoolClaim
            );
        } else {
            revert();
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

        exitBalances = new uint256[](2);
        if (isSingleSided) {
            // Redeem single-sided
            if (CURVE_INTERFACE == CurveInterface.V1 || CURVE_INTERFACE == CurveInterface.StableSwapNG) {
                // Method signature is the same for v1 and stable swap ng
                exitBalances[_PRIMARY_INDEX] = ICurve2TokenPoolV1(CURVE_POOL).remove_liquidity_one_coin(
                    poolClaim, int8(_PRIMARY_INDEX), _minAmounts[_PRIMARY_INDEX]
                );
            } else if (CURVE_INTERFACE == CurveInterface.V2) {
                exitBalances[_PRIMARY_INDEX] = ICurve2TokenPoolV2(CURVE_POOL).remove_liquidity_one_coin(
                    // Last two parameters are useEth = true and receiver = this contract
                    poolClaim, _PRIMARY_INDEX, _minAmounts[_PRIMARY_INDEX], true, address(this)
                );
            } else {
                revert();
            }
        } else {
            // Redeem proportionally, min amounts are rewritten to a fixed length array
            uint256[2] memory minAmounts;
            minAmounts[0] = _minAmounts[0];
            minAmounts[1] = _minAmounts[1];

            if (CURVE_INTERFACE == CurveInterface.V1) {
                uint256[2] memory _exitBalances = ICurve2TokenPoolV1(CURVE_POOL).remove_liquidity(poolClaim, minAmounts);
                exitBalances[0] = _exitBalances[0];
                exitBalances[1] = _exitBalances[1];
            } else if (CURVE_INTERFACE == CurveInterface.V2) {
                exitBalances[0] = TokenUtils.tokenBalance(TOKEN_1);
                exitBalances[1] = TokenUtils.tokenBalance(TOKEN_2);
                // Remove liquidity on CurveV2 does not return the exit amounts so we have to measure
                // them before and after.
                ICurve2TokenPoolV2(CURVE_POOL).remove_liquidity(
                    // Last two parameters are useEth = true and receiver = this contract
                    poolClaim, minAmounts, true, address(this)
                );
                exitBalances[0] = TokenUtils.tokenBalance(TOKEN_1) - exitBalances[0];
                exitBalances[1] = TokenUtils.tokenBalance(TOKEN_2) - exitBalances[1];
            } else if (CURVE_INTERFACE == CurveInterface.StableSwapNG) {
                exitBalances = ICurveStableSwapNG(CURVE_POOL).remove_liquidity(poolClaim, _minAmounts);
            } else {
                revert();
            }
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