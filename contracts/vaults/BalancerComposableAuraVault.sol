// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {Deployments} from "../global/Deployments.sol";
import {ComposablePoolSpotPrice} from "./balancer/ComposablePoolSpotPrice.sol";
import {
    AuraStakingMixin,
    AuraVaultDeploymentParams,
    DeploymentParams
} from "./balancer/mixins/AuraStakingMixin.sol";
import {IComposablePool} from "../../interfaces/balancer/IBalancerPool.sol";
import {IBalancerVault} from "../../interfaces/balancer/IBalancerVault.sol";

/**
 * @notice This vault borrows the primary currency and provides liquidity
 * to Balancer in exchange for BPT tokens. The BPT tokens are then staked
 * through Aura to earn reward tokens. The reward tokens are periodically
 * harvested and sold for more BPT tokens.
 */
contract BalancerComposableAuraVault is AuraStakingMixin {
    ComposablePoolSpotPrice immutable SPOT_PRICE;

    constructor(
        NotionalProxy notional_,
        AuraVaultDeploymentParams memory params,
        ComposablePoolSpotPrice _spotPrice
    ) AuraStakingMixin(notional_, params) {
        // BPT_INDEX must be defined for a composable pool
        require(BPT_INDEX != NOT_FOUND);
        SPOT_PRICE = _spotPrice;
    }

    function _validateRewardToken(address token) internal override view {
        if (
            token == TOKEN_1 ||
            token == TOKEN_2 ||
            token == TOKEN_3 ||
            token == TOKEN_4 ||
            token == TOKEN_5 ||
            token == address(AURA_BOOSTER) ||
            token == address(AURA_REWARD_POOL) ||
            token == address(Deployments.WETH)
        ) { revert(); }
    }

    /// @notice strategy identifier
    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("BalancerComposableAuraVault"));
    }

    function _joinPoolAndStake(
        uint256[] memory amounts, uint256 minPoolClaim
    ) internal override returns (uint256 lpTokens) {
        // Composable pool custom data does not include the BPT token amount so 
        // we loop here to remove it from the customData
        uint256[] memory amountsWithoutBpt = new uint256[](amounts.length - 1);
        uint256 j;
        for (uint256 i; i < amounts.length; i++) {
            if (i == BPT_INDEX) continue;
            amountsWithoutBpt[j++] = amounts[i];
        }

        bytes memory customData = abi.encode(
            IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
            amountsWithoutBpt,
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
            // See this line here:
            // https://github.com/balancer/balancer-v2-monorepo/blob/c7d4abbea39834e7778f9ff7999aaceb4e8aa048/pkg/pool-stable/contracts/ComposableStablePool.sol#L927
            // While "assets" sent to the vault include the BPT token the tokenIndex passed in by this
            // function does not include the BPT. primaryIndex in this code is inclusive of the BPT token in
            // the assets array. Therefore, if primaryIndex > bptIndex subtract one to ensure that the primaryIndex
            // does not include the BPT token here.
            uint256 primaryIndex = PRIMARY_INDEX();
            customData = abi.encode(
                IBalancerVault.ComposableExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
                poolClaim,
                primaryIndex < BPT_INDEX ?  primaryIndex : primaryIndex - 1
            );
        } else {
            customData = abi.encode(
                IBalancerVault.ComposableExitKind.EXACT_BPT_IN_FOR_ALL_TOKENS_OUT,
                poolClaim
            );
        }

        exitBalances = _exitPoolExactBPTIn(minAmounts, customData);
    }
 
    function _checkPriceAndCalculateValue() internal view override returns (uint256) {
        (uint256[] memory balances, uint256[] memory spotPrices) = SPOT_PRICE.getSpotPrices(
            BALANCER_POOL_ID,
            address(BALANCER_POOL_TOKEN),
            PRIMARY_INDEX()
        );

        // // Spot prices are returned in native decimals, convert them all to POOL_PRECISION
        // // as required in the _calculateLPTokenValue method.
        // (/* */, uint8[] memory decimals) = TOKENS();
        // for (uint256 i; i < spotPrices.length; i++) {
        //     spotPrices[i] = spotPrices[i] * POOL_PRECISION() / 10 ** decimals[i];
        // }

        // return _calculateLPTokenValue(balances, spotPrices);
    }

    function _totalPoolSupply() internal view override returns (uint256) {
        return IComposablePool(address(BALANCER_POOL_TOKEN)).getActualSupply();
    }
}
