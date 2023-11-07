// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {Deployments} from "../global/Deployments.sol";
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

    /// @notice constructor
    /// @param notional_ Notional proxy address
    /// @param params deployment parameters
    constructor(NotionalProxy notional_, AuraVaultDeploymentParams memory params)
        AuraStakingMixin(notional_, params) {
        // BPT_INDEX must be defined for a composable pool
        require(BPT_INDEX != NOT_FOUND);
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
 
    /**
     * @notice Converts the amount of pool tokens the vault holds into underlying denomination for the
     * borrow currency.
     * @param vaultShares amount of vault shares
     * @return underlyingValue the value of the BPT in terms of the borrowed currency
     */
    function _checkPriceAndCalculateValue(uint256 vaultShares) internal view override returns (int256) {
        // return _strategyContext().convertStrategyToUnderlying(vaultShares);
    }

    function _totalPoolSupply() internal view override returns (uint256) {
        return IComposablePool(address(BALANCER_POOL_TOKEN)).getActualSupply();
    }

    /// @notice returns the value of 1 vault share
    /// @return exchange rate of 1 vault share
    function getExchangeRate(uint256 /* maturity */) public view override returns (int256) {
        // BalancerComposableAuraStrategyContext memory context = _strategyContext();
        // return ComposableAuraHelper.getExchangeRate(context);
    }

    // /// @notice Returns information related to the strategy
    // /// @return strategy context
    // function getStrategyContext() external view returns (BalancerComposableAuraStrategyContext memory) {
    //     return _strategyContext();
    // }

    // /// @notice Gets the current spot price with a given token index
    // /// @notice Spot price is always denominated in the primary token
    // /// @param index1 first pool token index, BPT index is not allowed
    // /// @param index2 second pool token index, BPT index is not allowed
    // /// @return spotPrice spot price of 1 vault share
    // function getSpotPrice(uint8 index1, uint8 index2) external view returns (uint256 spotPrice) {
    //     spotPrice = ComposableAuraHelper.getSpotPrice(_strategyContext(), index1, index2);
    // }
}
