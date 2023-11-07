// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {IERC20} from "../../interfaces/IERC20.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";
import {
    AuraStakingContext,
    AuraVaultDeploymentParams,
    BalancerComposableAuraStrategyContext,
    BalancerComposablePoolContext,
    PoolParams
} from "./balancer/BalancerVaultTypes.sol";
import{BalancerUtils} from "./balancer/internal/pool/BalancerUtils.sol";
import {
    StrategyContext,
    StrategyVaultState,
    ComposablePoolContext,
    DepositParams,
    RedeemParams
} from "./common/VaultTypes.sol";
import {VaultEvents} from "./common/VaultEvents.sol";
import {Errors} from "../global/Errors.sol";
import {StrategyUtils} from "./common/internal/strategy/StrategyUtils.sol";
import {BalancerComposablePoolUtils} from "./balancer/internal/pool/BalancerComposablePoolUtils.sol";
import {ComposableAuraHelper} from "./balancer/external/ComposableAuraHelper.sol";
import {BalancerComposablePoolMixin} from "./balancer/mixins/BalancerComposablePoolMixin.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {VaultStorage} from "./common/VaultStorage.sol";
import {
    IComposablePool
} from "../../interfaces/balancer/IBalancerPool.sol";

/**
 * @notice This vault borrows the primary currency and provides liquidity
 * to Balancer in exchange for BPT tokens. The BPT tokens are then staked
 * through Aura to earn reward tokens. The reward tokens are periodically
 * harvested and sold for more BPT tokens.
 */
contract BalancerComposableAuraVault is BalancerComposablePoolMixin {
    using StrategyUtils for StrategyContext;
    using VaultStorage for StrategyVaultState;
    using ComposableAuraHelper for BalancerComposableAuraStrategyContext;
    using BalancerComposablePoolUtils for ComposablePoolContext;
    using BalancerComposablePoolUtils for BalancerComposablePoolContext;

    /// @notice constructor
    /// @param notional_ Notional proxy address
    /// @param params deployment parameters
    constructor(NotionalProxy notional_, AuraVaultDeploymentParams memory params)
        BalancerComposablePoolMixin(notional_, params)
    {}

    /// @notice strategy identifier
    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("BalancerComposableAuraVault"));
    }

    function _joinPoolAndStake(
        uint256[] memory amounts, uint256 minPoolClaim
    ) internal override returns (uint256 lpTokens) {
        BalancerComposablePoolContext memory poolContext = _composablePoolContext();

        PoolParams memory poolParams = BalancerUtils._getPoolParams({
            context: poolContext,
            amounts: amounts,
            isJoin: true,
            isSingleSided: false,
            bptAmount: minPoolClaim
        });

        lpTokens = BalancerUtils._joinPoolExactTokensIn({
            poolId: poolContext.poolId,
            poolToken: poolContext.basePool.poolToken,
            params: poolParams
        });

        // Transfer token to Aura protocol for boosted staking
        AuraStakingContext memory stakingContext = _auraStakingContext();
        bool success = stakingContext.booster.deposit(stakingContext.poolId, lpTokens, true); // stake = true
        if (!success) revert Errors.StakeFailed();
    }

    function _unstakeAndExitPool(
        uint256 poolClaim, uint256[] memory minAmounts, bool isSingleSided
    ) internal override returns (uint256[] memory exitBalances) {
        AuraStakingContext memory stakingContext = _auraStakingContext();
        // Withdraw BPT tokens back to the vault for redemption
        bool success = stakingContext.rewardPool.withdrawAndUnwrap(poolClaim, false); // claimRewards = false
        if (!success) revert Errors.UnstakeFailed();

        BalancerComposablePoolContext memory poolContext = _composablePoolContext();
        exitBalances = BalancerUtils._exitPoolExactBPTIn({
            poolId: poolContext.poolId,
            poolToken: poolContext.basePool.poolToken,
            params: BalancerUtils._getPoolParams({
                context: poolContext,
                amounts: minAmounts,
                isJoin: false,
                isSingleSided: isSingleSided,
                bptAmount: poolClaim
            })
        });
    }
 
    /**
     * @notice Converts the amount of pool tokens the vault holds into underlying denomination for the
     * borrow currency.
     * @param vaultShares amount of vault shares
     * @return underlyingValue the value of the BPT in terms of the borrowed currency
     */
    function _checkPriceAndCalculateValue(uint256 vaultShares) internal view override returns (int256) {
        return _strategyContext().convertStrategyToUnderlying(vaultShares);
    }

    function _totalPoolSupply() internal view override returns (uint256) {
        return IComposablePool(address(BALANCER_POOL_TOKEN)).getActualSupply();
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
