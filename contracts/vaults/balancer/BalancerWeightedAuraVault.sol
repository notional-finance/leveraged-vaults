// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {NotionalProxy} from "@interfaces/notional/NotionalProxy.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {BalancerSpotPrice} from "./BalancerSpotPrice.sol";
import {
    AuraStakingMixin,
    AuraVaultDeploymentParams,
    DeploymentParams
} from "./mixins/AuraStakingMixin.sol";
import {IWeightedPool} from "@interfaces/balancer/IBalancerPool.sol";
import {IBalancerVault} from "@interfaces/balancer/IBalancerVault.sol";

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

        // This version of the weighted vault does not support holding BPT as one
        // of the assets in the pool.
        require(_isBPT(TOKEN_1) == false);
        require(_isBPT(TOKEN_2) == false);
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
        // Spot prices are returned in POOL_PRECISION decimals.
        (uint256[] memory balances, uint256[] memory spotPrices) = SPOT_PRICE.getWeightedSpotPrices(
            BALANCER_POOL_ID,
            address(BALANCER_POOL_TOKEN),
            PRIMARY_INDEX()
        );

        return _calculateLPTokenValue(balances, spotPrices);
    }

    /// @notice Weighted pools may have pre-minted BPT. If that is the case then
    /// we need to call getActualSupply() instead. Legacy pools do not have the
    /// getActualSupply method. See:
    /// https://docs.balancer.fi/concepts/advanced/valuing-bpt/valuing-bpt.html#getting-bpt-supply
    function _totalPoolSupply() internal view override returns (uint256) {
        // As of this writing the documentation linked above appears inaccurate and the
        // pre-minted total supply returned by a pool is not a fixed constant. Therefore,
        // we use a try / catch here instead.
        try IWeightedPool(address(BALANCER_POOL_TOKEN)).getActualSupply() returns (uint256 totalSupply) {
            return totalSupply;
        } catch {
            return super._totalPoolSupply();
        }
    }
}