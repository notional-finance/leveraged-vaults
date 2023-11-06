// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {TokenUtils} from "../utils/TokenUtils.sol";
import {AuraVaultDeploymentParams} from "./balancer/BalancerVaultTypes.sol";
import {BalancerComposableAuraStrategyContext, BalancerComposablePoolContext} from "./balancer/BalancerVaultTypes.sol";
import {
    StrategyContext,
    StrategyVaultState,
    ComposablePoolContext,
    DepositParams
} from "./common/VaultTypes.sol";
import {VaultEvents} from "./common/VaultEvents.sol";
import {StrategyUtils} from "./common/internal/strategy/StrategyUtils.sol";
import {BalancerComposablePoolUtils} from "./balancer/internal/pool/BalancerComposablePoolUtils.sol";
import {ComposableAuraHelper} from "./balancer/external/ComposableAuraHelper.sol";
import {BalancerComposablePoolMixin} from "./balancer/mixins/BalancerComposablePoolMixin.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {VaultStorage} from "./common/VaultStorage.sol";
import {
    ReinvestRewardParams
} from "../../interfaces/notional/ISingleSidedLPStrategyVault.sol";

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

    /// @notice Processes a deposit request from Notional
    /// @notice Can't be called when the vault is locked
    /// @param deposit deposit amount
    /// @param data custom deposit data
    /// @return vaultSharesMinted amount of vault shares minted
    function _depositFromNotional(
        address /* account */, uint256 deposit, uint256 /* maturity */, bytes calldata data
    ) internal override whenNotLocked returns (uint256 vaultSharesMinted) {
        vaultSharesMinted = _strategyContext().deposit(deposit, data);
    }

    /// @notice Processes a redemption request from notional
    /// @notice Can't be called when the vault is locked
    /// @param vaultShares the amount of vault shares to redeem
    /// @param data custom redeem data
    /// @return finalPrimaryBalance redeemed amount denominated in primary token
    function _redeemFromNotional(
        address /* account */, uint256 vaultShares, uint256 /* maturity */, bytes calldata data
    ) internal override whenNotLocked returns (uint256 finalPrimaryBalance) {
        finalPrimaryBalance = _strategyContext().redeem(vaultShares, data);
    }

    /// @notice Remove liquidity from Balancer in the event of an emergency (i.e. pool gets hacked)
    /// @notice Vault will be locked after an emergency exit, restoreVault can be used to unlock the vault
    /// @param claimToExit amount of LP tokens to withdraw, if set to zero will withdraw all LP tokens
    function emergencyExit(uint256 claimToExit, bytes calldata /* data */) external
        onlyRole(EMERGENCY_EXIT_ROLE) {
        BalancerComposableAuraStrategyContext memory context = _strategyContext();
        if (claimToExit == 0) claimToExit = context.baseStrategy.vaultState.totalPoolClaim;

        // Min amounts are set to 0 here because we want to be sure that the liquidity can
        // be withdrawn in the event of an emergency where the spot price differs significantly
        // from the oracle price.
        uint256[] memory minAmounts = new uint256[](context.poolContext.basePool.tokens.length);
        
        // Unstake and remove from pool
        context.poolContext._unstakeAndExitPool(
            context.stakingContext, claimToExit, minAmounts, false
        );

        context.baseStrategy.vaultState.totalPoolClaim =
            context.baseStrategy.vaultState.totalPoolClaim - claimToExit;
        context.baseStrategy.vaultState.setStrategyVaultState(); 

        emit VaultEvents.EmergencyExit(claimToExit);

        // Lock vault after emergency settlement
        _lockVault();
    }

    /// @notice Restores and unlocks the vault after an emergency exit
    /// @param minPoolClaim bpt slippage limit
    function restoreVault(uint256 minPoolClaim, bytes calldata /* data */) external
        whenLocked onlyNotionalOwner {
        BalancerComposableAuraStrategyContext memory context = _strategyContext();

        uint256[] memory amounts = new uint256[](context.poolContext.basePool.tokens.length);

        for (uint256 i; i < context.poolContext.basePool.tokens.length; i++) {
            // Skip BPT index
            if (i == context.poolContext.bptIndex) continue;
            amounts[i] = TokenUtils.tokenBalance(context.poolContext.basePool.tokens[i]);
        }

        // Join proportionally here to minimize slippage
        uint256 bptAmount = context.poolContext._joinPoolAndStake(
            context.oracleContext, context.baseStrategy, context.stakingContext, amounts, minPoolClaim
        );

        // Update internal accounting
        context.baseStrategy.vaultState.totalPoolClaim += bptAmount;
        context.baseStrategy.vaultState.setStrategyVaultState(); 

        // Unlock vault after re-entering the Balancer pool
        _unlockVault();
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
    function convertStrategyToUnderlying(
        address /* account */, uint256 vaultShares, uint256 /* maturity */
    ) public view virtual override whenNotLocked returns (int256 underlyingValue) {
        underlyingValue = _strategyContext().convertStrategyToUnderlying(vaultShares);
    }

    /// @notice Returns information related to the strategy
    /// @return strategy context
    function getStrategyContext() external view returns (BalancerComposableAuraStrategyContext memory) {
        return _strategyContext();
    }

    /// @notice Gets the current spot price with a given token index
    /// @notice Spot price is always denominated in the primary token
    /// @param index1 first pool token index, BPT index is not allowed
    /// @param index2 second pool token index, BPT index is not allowed
    /// @return spotPrice spot price of 1 vault share
    function getSpotPrice(uint8 index1, uint8 index2) external view returns (uint256 spotPrice) {
        spotPrice = ComposableAuraHelper.getSpotPrice(_strategyContext(), index1, index2);
    }
}
