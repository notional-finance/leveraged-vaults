// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {Deployments} from "../global/Deployments.sol";
import {BalancerSpotPrice} from "./balancer/BalancerSpotPrice.sol";
import {
    AuraStakingMixin,
    AuraVaultDeploymentParams,
    DeploymentParams
} from "./balancer/mixins/AuraStakingMixin.sol";
import {IComposablePool} from "../../interfaces/balancer/IBalancerPool.sol";
import {IBalancerVault} from "../../interfaces/balancer/IBalancerVault.sol";

contract BalancerWeightedAuraVault is AuraStakingMixin {
    /// @notice Helper singleton contract for calculating spot prices
    BalancerSpotPrice immutable SPOT_PRICE;

    constructor(
        NotionalProxy notional_,
        AuraVaultDeploymentParams memory params,
        BalancerSpotPrice _spotPrice
    ) AuraStakingMixin(notional_, params) {
        // BPT_INDEX is not defined for WeightedPool
        require(BPT_INDEX == NOT_FOUND);
        // Only two token pools are supported
        require(NUM_TOKENS() == 2);
        SPOT_PRICE = _spotPrice;
    }

    /// @notice strategy identifier
    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("BalancerWeightedAuraVault"));
    }

    function _joinPoolAndStake(
        uint256[] memory amounts, uint256 minPoolClaim
    ) internal override returns (uint256 lpTokens) {
        bytes memory customData = abi.encode(
            IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
            amounts,
            minPoolClaim
        );

        lpTokens = _joinPoolExactTokensIn(amounts, customData);

        // Transfer token to Aura protocol for boosted staking
        bool success = AURA_BOOSTER.deposit(AURA_POOL_ID, lpTokens, true);
        require(success);
    }

    function _unstakeAndExitPool(
        uint256 poolClaim, uint256[] memory minAmounts, bool isSingleSided
    ) internal override returns (uint256[] memory exitBalances) {
        bool success = AURA_REWARD_POOL.withdrawAndUnwrap(poolClaim, false); // claimRewards = false
        require(success);

        bytes memory customData;
        if (isSingleSided) {
            uint256 primaryIndex = PRIMARY_INDEX();
            customData = abi.encode(
                IBalancerVault.WeightedPoolExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
                poolClaim,
                primaryIndex
            );
        } else {
            customData = abi.encode(
                IBalancerVault.WeightedPoolExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT,
                poolClaim
            );
        }

        exitBalances = _exitPoolExactBPTIn(minAmounts, customData);
    }
 
    function _checkPriceAndCalculateValue() internal view override returns (uint256) {
        (/* */, uint8[] memory decimals) = TOKENS();

        (uint256[] memory balances, uint256[] memory spotPrices) = SPOT_PRICE.getWeightedSpotPrices(
            BALANCER_POOL_ID,
            address(BALANCER_POOL_TOKEN),
            PRIMARY_INDEX(),
            decimals[1 - PRIMARY_INDEX()]
        );

        // Spot prices are returned in native decimals, convert them all to POOL_PRECISION
        // as required in the _calculateLPTokenValue method.
        for (uint256 i; i < spotPrices.length; i++) {
            spotPrices[i] = spotPrices[i] * POOL_PRECISION() / 10 ** decimals[i];
        }

        return _calculateLPTokenValue(balances, spotPrices);
    }
}