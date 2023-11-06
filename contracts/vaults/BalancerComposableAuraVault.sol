// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

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
    ReinvestRewardParams
} from "../../interfaces/notional/ISingleSidedLPStrategyVault.sol";
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
        uint256[] memory amounts, DepositParams memory params
    ) internal override returns (uint256 lpTokens) {
        BalancerComposablePoolContext memory poolContext = _composablePoolContext();

        PoolParams memory poolParams = BalancerUtils._getPoolParams({
            context: poolContext,
            amounts: amounts,
            isJoin: true,
            isSingleSided: false,
            bptAmount: params.minPoolClaim
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
        uint256 vaultShares, RedeemParams memory params
    ) internal override returns (uint256[] memory exitBalances) {

    }
 

    /// @notice Remove liquidity from Balancer in the event of an emergency (i.e. pool gets hacked)
    /// @notice Vault will be locked after an emergency exit, restoreVault can be used to unlock the vault
    /// @param claimToExit amount of LP tokens to withdraw, if set to zero will withdraw all LP tokens
    function _emergencyExitPoolClaim(uint256 claimToExit, bytes calldata /* data */) internal override {
        BalancerComposableAuraStrategyContext memory context = _strategyContext();
        // Min amounts are set to 0 here because we want to be sure that the liquidity can
        // be withdrawn in the event of an emergency where the spot price differs significantly
        // from the oracle price.
        uint256[] memory minAmounts = new uint256[](context.poolContext.basePool.tokens.length);
        
        // Unstake and remove from pool
        context.poolContext._unstakeAndExitPool(context.stakingContext, claimToExit, minAmounts, false);
    }

    /// @notice Restores and unlocks the vault after an emergency exit
    /// @param minPoolClaim bpt slippage limit
    function _restoreVault(
        uint256 minPoolClaim, bytes calldata /* data */
    ) internal override returns (uint256 poolTokens) {
        BalancerComposableAuraStrategyContext memory context = _strategyContext();
        uint256[] memory amounts = new uint256[](context.poolContext.basePool.tokens.length);

        for (uint256 i; i < context.poolContext.basePool.tokens.length; i++) {
            // Skip BPT index
            if (i == context.poolContext.bptIndex) continue;
            amounts[i] = TokenUtils.tokenBalance(context.poolContext.basePool.tokens[i]);
        }

        // No trades are specified so this joins proportionally
        DepositParams memory params;
        params.minPoolClaim = minPoolClaim;
        poolTokens = _joinPoolAndStake(amounts, params);
    }

    /// @notice Reinvests the harvested reward tokens
    /// @notice This function needs to be called multiple times if the strategy
    /// has multiple reward tokens.
    /// @notice Can't be called when the vault is locked
    /// @param params reward reinvestment parameters
    /// @return rewardToken reward token address
    /// @return amountSold amount of reward tokens sold
    /// @return poolClaimAmount amount of pool claim tokens reinvested
    function reinvestReward(ReinvestRewardParams calldata params) 
        external whenNotLocked onlyRole(REWARD_REINVESTMENT_ROLE) returns (
            address rewardToken, uint256 amountSold, uint256 poolClaimAmount
        ) {
        return ComposableAuraHelper.reinvestReward(_strategyContext(), params);
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
