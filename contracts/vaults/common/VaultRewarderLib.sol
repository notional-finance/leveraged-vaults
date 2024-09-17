// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import "./VaultStorage.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {TypeConvert} from "../../global/TypeConvert.sol";
import {TokenUtils} from "../../utils/TokenUtils.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";
import {IEIP20NonStandard} from "../../../interfaces/IEIP20NonStandard.sol";
import {IVaultRewarder} from "../../../interfaces/notional/IVaultRewarder.sol";
import {
    IConvexRewardPool,
    IConvexRewardPoolArbitrum
} from "../../../interfaces/convex/IConvexRewardPool.sol";
import {IAuraRewardPool} from "../../../interfaces/aura/IAuraRewardPool.sol";
import {IAuraBooster} from "@interfaces/aura/IAuraBooster.sol";
import {IConvexBooster, IConvexBoosterArbitrum} from "@interfaces/convex/IConvexBooster.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract VaultRewarderLib is IVaultRewarder, ReentrancyGuard {
    using TypeConvert for uint256;
    using TokenUtils for IERC20;

    /// @notice Returns the current reward claim method and reward state
    function getRewardSettings() public view override returns (
        VaultRewardState[] memory v,
        StrategyVaultSettings memory s,
        RewardPoolStorage memory r
    ) {
        s = VaultStorage.getStrategyVaultSettings();
        r = VaultStorage.getRewardPoolStorage();
        mapping(uint256 => VaultRewardState) storage store = VaultStorage.getVaultRewardState();
        v = new VaultRewardState[](s.numRewardTokens);

        for (uint256 i; i < v.length; i++) v[i] = store[i];
    }

    /// @notice Returns the reward debt for the given reward token and account, valid whenever
    /// the account will claim rewards.
    function getRewardDebt(address rewardToken, address account) external view override returns (
        uint256 rewardDebt
    ) {
        return VaultStorage.getAccountRewardDebt()[rewardToken][account];
    }

    /// @notice Returns the amount of rewards the account can claim at the given block time. Includes
    /// rewards given via emissions, rewards that have been claimed in the past via Convex or Aura, but
    /// does not include rewards that have not yet been claimed via Convex or Aura.
    function getAccountRewardClaim(address account, uint256 blockTime) external view override returns (
        uint256[] memory rewards
    ) {
        StrategyVaultSettings memory s = VaultStorage.getStrategyVaultSettings();
        mapping(uint256 => VaultRewardState) storage store = VaultStorage.getVaultRewardState();
        rewards = new uint256[](s.numRewardTokens);

        uint256 totalVaultSharesBefore = VaultStorage.getStrategyVaultState().totalVaultSharesGlobal;
        uint256 vaultSharesBefore = _getVaultSharesBefore(account);

        for (uint256 i; i < rewards.length; i++) {
            uint256 rewardsPerVaultShare = _getAccumulatedRewardViaEmissionRate(
                store[i], totalVaultSharesBefore, blockTime
            );
            rewards[i] = _getRewardsToClaim(
                store[i].rewardToken, account, vaultSharesBefore, rewardsPerVaultShare
            );
        }
    }

    /// @notice Sets a secondary reward rate for a given token, only callable via the owner. If no
    /// emissionRatePerYear is set (set to zero) then this will list the rewardToken. This is used
    /// to initialized the reward accumulators for a new token that is issued via a reward booster.
    function updateRewardToken(
        uint256 index,
        address rewardToken,
        uint128 emissionRatePerYear,
        uint32 endTime
    ) external override {
        require(msg.sender == Deployments.NOTIONAL.owner());
        // Check that token permissions are not set for selling so that automatic reinvest
        // does not sell the tokens
        (bool allowSell, /* */, /* */) = Deployments.TRADING_MODULE.tokenWhitelist(
            address(this), rewardToken
        );
        require(allowSell == false);
        uint256 totalVaultSharesBefore = VaultStorage.getStrategyVaultState().totalVaultSharesGlobal;

        StrategyVaultSettings memory settings = VaultStorage.getStrategyVaultSettings();
        VaultRewardState memory state = VaultStorage.getVaultRewardState()[index];

        if (index < settings.numRewardTokens) {
            // Safety check to ensure that the correct token is specified, we can never change the
            // token address once set.
            require(state.rewardToken == rewardToken);
            // Modifies the emission rate on an existing token, direct claims of the token will
            // not be affected by the emission rate.
            // First accumulate under the old regime up to the current time. Even if the previous
            // emissionRatePerYear is zero this will still set the lastAccumulatedTime to the current
            // blockTime.
            _accumulateSecondaryRewardViaEmissionRate(index, state, totalVaultSharesBefore);

            // Save the new emission rates
            state.emissionRatePerYear = emissionRatePerYear;
            if (state.emissionRatePerYear == 0) {
                state.endTime = 0;
            } else {
                require(block.timestamp < endTime);
                state.endTime = endTime;
            }
            VaultStorage.getVaultRewardState()[index] = state;
        } else if (index == settings.numRewardTokens) {
            // This sets a new reward token, ensure that the current slot is empty
            require(state.rewardToken == address(0));
            settings.numRewardTokens += 1;
            VaultStorage.setStrategyVaultSettings(settings);
            state.rewardToken = rewardToken;

            // If no emission rate is set then governance is just adding a token that can be claimed
            // via the LP tokens without an emission rate. These settings will be left empty and the
            // subsequent _claimVaultRewards method will set the initial accumulatedRewardPerVaultShare.
            if (0 < emissionRatePerYear) {
                state.emissionRatePerYear = emissionRatePerYear;
                require(block.timestamp < endTime);
                state.endTime = endTime;
                state.lastAccumulatedTime = uint32(block.timestamp);
            }
            VaultStorage.getVaultRewardState()[index] = state;
        } else {
            // Can only append or modify existing tokens
            revert();
        }

        // Claim all vault rewards up to the current time
        (VaultRewardState[] memory allStates, /* */, RewardPoolStorage memory rewardPool) = getRewardSettings();
        _claimVaultRewards(totalVaultSharesBefore, allStates, rewardPool);
        emit VaultRewardUpdate(rewardToken, emissionRatePerYear, endTime);
    }

    function _withdrawFromPreviousRewardPool(IERC20 poolToken, RewardPoolStorage memory r) internal {
        if (r.rewardPool == address(0)) return;

        // First, withdraw from existing pool and clear approval
        uint256 boosterBalance = IERC20(address(r.rewardPool)).balanceOf(address(this));
        if (r.poolType == RewardPoolType.AURA) {
            require(IAuraRewardPool(r.rewardPool).withdrawAndUnwrap(boosterBalance, true));
        } else if (r.poolType == RewardPoolType.CONVEX_MAINNET) {
            require(IConvexRewardPool(r.rewardPool).withdrawAndUnwrap(boosterBalance, true));
        } else if (r.poolType == RewardPoolType.CONVEX_ARBITRUM) {
            require(IConvexRewardPoolArbitrum(r.rewardPool).withdraw(boosterBalance, true));
        }

        // Clear approvals on the old pool.
        poolToken.checkApprove(address(r.rewardPool), 0);
    }

    function migrateRewardPool(IERC20 poolToken, RewardPoolStorage memory newRewardPool) external nonReentrant {
        require(msg.sender == Deployments.NOTIONAL.owner());

        // Claim all rewards from the previous reward pool before withdrawing
        uint256 totalVaultSharesBefore = VaultStorage.getStrategyVaultState().totalVaultSharesGlobal;
        (VaultRewardState[] memory state, , RewardPoolStorage memory rewardPool) = getRewardSettings();
        _claimVaultRewards(totalVaultSharesBefore, state, rewardPool);

        _withdrawFromPreviousRewardPool(poolToken, rewardPool);

        uint256 poolTokens = poolToken.balanceOf(address(this));

        if (newRewardPool.poolType == RewardPoolType.AURA) {
            uint256 poolId = IAuraRewardPool(newRewardPool.rewardPool).pid();
            address booster = IAuraRewardPool(newRewardPool.rewardPool).operator();
            poolToken.checkApprove(booster, type(uint256).max);
            require(IAuraBooster(booster).deposit(poolId, poolTokens, true));
        } else if (newRewardPool.poolType == RewardPoolType.CONVEX_MAINNET) {
            uint256 poolId = IConvexRewardPool(newRewardPool.rewardPool).pid();
            address booster = IConvexRewardPool(newRewardPool.rewardPool).operator();
            poolToken.checkApprove(booster, type(uint256).max);
            require(IConvexBooster(booster).deposit(poolId, poolTokens, true));
        } else if (newRewardPool.poolType == RewardPoolType.CONVEX_ARBITRUM) {
            uint256 poolId = IConvexRewardPoolArbitrum(newRewardPool.rewardPool).convexPoolId();
            address booster = IConvexRewardPoolArbitrum(newRewardPool.rewardPool).convexBooster();
            poolToken.checkApprove(booster, type(uint256).max);
            require(IConvexBoosterArbitrum(booster).deposit(poolId, poolTokens));
        }

        // Set the last claim timestamp to the current block timestamp since we re claiming all the rewards
        // earlier in this method.
        newRewardPool.lastClaimTimestamp = uint32(block.timestamp);
        VaultStorage.setRewardPoolStorage(newRewardPool);
    }

    /// @notice Claims all the rewards for the entire vault and updates the accumulators. Does not
    /// update emission rewarders since those are automatically updated on every account claim.
    function claimRewardTokens() public nonReentrant {
        // Ensures that this method is not called from inside a vault account action.
        require(msg.sender != address(Deployments.NOTIONAL));
        // This method is not executed from inside enter or exit vault positions, so this total
        // vault shares value is valid.
        uint256 totalVaultSharesBefore = VaultStorage.getStrategyVaultState().totalVaultSharesGlobal;
        (VaultRewardState[] memory state, , RewardPoolStorage memory rewardPool) = getRewardSettings();
        _claimVaultRewards(totalVaultSharesBefore, state, rewardPool);
    }

    /// @notice Executes a claim against the given reward pool type and updates internal
    /// rewarder accumulators.
    function _claimVaultRewards(
        uint256 totalVaultSharesBefore,
        VaultRewardState[] memory state,
        RewardPoolStorage memory rewardPool
    ) internal {
        uint256[] memory balancesBefore = new uint256[](state.length);
        // Run a generic call against the reward pool and then do a balance
        // before and after check.
        for (uint256 i; i < state.length; i++) {
            // Presumes that ETH will never be given out as a reward token.
            balancesBefore[i] = IERC20(state[i].rewardToken).balanceOf(address(this));
        }

        _executeClaim(rewardPool);

        rewardPool.lastClaimTimestamp = uint32(block.timestamp);
        VaultStorage.setRewardPoolStorage(rewardPool);

        // This only accumulates rewards claimed, it does not accumulate any secondary emissions
        // that are streamed to vault users.
        for (uint256 i; i < state.length; i++) {
            uint256 balanceAfter = IERC20(state[i].rewardToken).balanceOf(address(this));
            _accumulateSecondaryRewardViaClaim(
                i,
                state[i],
                // balanceAfter should never be less than balanceBefore
                balanceAfter - balancesBefore[i],
                totalVaultSharesBefore
            );
        }
    }

    /// @notice Executes the proper call for various rewarder types.
    function _executeClaim(RewardPoolStorage memory r) internal {
        if (r.poolType == RewardPoolType._UNUSED) {
            return;
        } else if (r.poolType == RewardPoolType.AURA) {
            require(IAuraRewardPool(r.rewardPool).getReward(address(this), true));
        } else if (r.poolType == RewardPoolType.CONVEX_MAINNET) {
            require(IConvexRewardPool(r.rewardPool).getReward(address(this), true));
        } else if (r.poolType == RewardPoolType.CONVEX_ARBITRUM) {
            IConvexRewardPoolArbitrum(r.rewardPool).getReward(address(this));
        } else {
            revert();
        }
    }

    /// @notice Callable by an account to claim their own rewards, we know that the vault shares have
    /// not changed in this transaction because the contract has not been called by Notional
    function claimAccountRewards(address account) external nonReentrant override {
        require(msg.sender == account);
        uint256 totalVaultSharesBefore = VaultStorage.getStrategyVaultState().totalVaultSharesGlobal;
        uint256 vaultSharesBefore = _getVaultSharesBefore(account);
        _claimAccountRewards(account, totalVaultSharesBefore, vaultSharesBefore, vaultSharesBefore);
    }

    /// @notice Called by the vault during enter and exit vault to update the account reward claims.
    function updateAccountRewards(
        address account,
        uint256 vaultShares,
        uint256 totalVaultSharesBefore,
        bool isMint
    ) external {
        // Can only be called via enter or exit vault
        require(msg.sender == address(Deployments.NOTIONAL));
        uint256 vaultSharesBefore = _getVaultSharesBefore(account);
        _claimAccountRewards(
            account,
            totalVaultSharesBefore,
            vaultSharesBefore,
            isMint ? vaultSharesBefore + vaultShares : vaultSharesBefore - vaultShares
        );
    }

    /// @notice Called to ensure that rewarders are properly updated during deleverage, when
    /// vault shares are transferred from an account to the liquidator.
    function deleverageAccount(
        address account,
        address vault,
        address liquidator,
        uint16 currencyIndex,
        int256 depositUnderlyingInternal
    ) external payable returns (uint256 vaultSharesFromLiquidation, int256 depositAmountPrimeCash) {
        // Record all vault share values before
        uint256 totalVaultSharesBefore = VaultStorage.getStrategyVaultState().totalVaultSharesGlobal;
        uint256 accountVaultSharesBefore = _getVaultSharesBefore(account);
        uint256 liquidatorVaultSharesBefore = _getVaultSharesBefore(liquidator);

        // Forward the liquidation call to Notional
        (
            vaultSharesFromLiquidation,
            depositAmountPrimeCash
        ) = Deployments.NOTIONAL.deleverageAccount{value: msg.value}(
            account, vault, liquidator, currencyIndex, depositUnderlyingInternal
        );

        _claimAccountRewards(
            account, totalVaultSharesBefore, accountVaultSharesBefore,
            accountVaultSharesBefore - vaultSharesFromLiquidation
        );
        // The second claim will be skipped as a gas optimization because the last claim
        // timestamp will equal the current timestamp.
        _claimAccountRewards(
            liquidator, totalVaultSharesBefore, liquidatorVaultSharesBefore,
            liquidatorVaultSharesBefore + vaultSharesFromLiquidation
        );
    }

    /// @notice Executes a claim on account rewards
    function _claimAccountRewards(
        address account,
        uint256 totalVaultSharesBefore,
        uint256 vaultSharesBefore,
        uint256 vaultSharesAfter
    ) internal {
        (VaultRewardState[] memory state, StrategyVaultSettings memory s, RewardPoolStorage memory r) = getRewardSettings();
        if (r.lastClaimTimestamp + s.forceClaimAfter < block.timestamp) {
            _claimVaultRewards(totalVaultSharesBefore, state, r);
        }

        for (uint256 i; i < state.length; i++) {
            if (0 < state[i].emissionRatePerYear) {
                // Accumulate any rewards with an emission rate here
                _accumulateSecondaryRewardViaEmissionRate(i, state[i], totalVaultSharesBefore);
            }

            _claimRewardToken(
                state[i].rewardToken,
                account,
                vaultSharesBefore,
                vaultSharesAfter,
                state[i].accumulatedRewardPerVaultShare
            );
        }
    }

    /** Reward Claim Methods **/
    function _getRewardsToClaim(
        address rewardToken,
        address account,
        uint256 vaultSharesBefore,
        uint256 rewardsPerVaultShare
    ) internal view returns (uint256 rewardToClaim) {
        // Vault shares are always in 8 decimal precision
        rewardToClaim = (
            (vaultSharesBefore * rewardsPerVaultShare) / uint256(Constants.INTERNAL_TOKEN_PRECISION)
        ) - VaultStorage.getAccountRewardDebt()[rewardToken][account];
    }

    function _claimRewardToken(
        address rewardToken,
        address account,
        uint256 vaultSharesBefore,
        uint256 vaultSharesAfter,
        uint256 rewardsPerVaultShare
    ) internal returns (uint256 rewardToClaim) {
        rewardToClaim = _getRewardsToClaim(
            rewardToken, account, vaultSharesBefore, rewardsPerVaultShare
        );

        VaultStorage.getAccountRewardDebt()[rewardToken][account] = (
            (vaultSharesAfter * rewardsPerVaultShare) /
                uint256(Constants.INTERNAL_TOKEN_PRECISION)
        );

        if (0 < rewardToClaim) {
            // Ignore transfer errors here so that any strange failures here do not
            // prevent normal vault operations from working. Failures may include a
            // lack of balances or some sort of blacklist that prevents an account
            // from receiving tokens.
            if (rewardToken.code.length > 0) {
                try IEIP20NonStandard(rewardToken).transfer(account, rewardToClaim) {
                    bool success = TokenUtils.checkReturnCode();
                    if (success) {
                        emit VaultRewardTransfer(rewardToken, account, rewardToClaim);
                    } else {
                        emit VaultRewardTransfer(rewardToken, account, 0);
                    }
                // Emits zero tokens transferred if the transfer fails.
                } catch {
                    emit VaultRewardTransfer(rewardToken, account, 0);
                }
            }
        }
    }

    /*** ACCUMULATORS  ***/

    function _accumulateSecondaryRewardViaClaim(
        uint256 index,
        VaultRewardState memory state,
        uint256 tokensClaimed,
        uint256 totalVaultSharesBefore
    ) private {
        if (tokensClaimed == 0) return;

        state.accumulatedRewardPerVaultShare += (
            (tokensClaimed * uint256(Constants.INTERNAL_TOKEN_PRECISION)) / totalVaultSharesBefore
        ).toUint128();

        VaultStorage.getVaultRewardState()[index] = state;
    }

    function _accumulateSecondaryRewardViaEmissionRate(
        uint256 index,
        VaultRewardState memory state,
        uint256 totalVaultSharesBefore
    ) private {
        state.accumulatedRewardPerVaultShare = _getAccumulatedRewardViaEmissionRate(
            state, totalVaultSharesBefore, block.timestamp
        ).toUint128();
        state.lastAccumulatedTime = uint32(block.timestamp);

        VaultStorage.getVaultRewardState()[index] = state;
    }

    function _getAccumulatedRewardViaEmissionRate(
        VaultRewardState memory state,
        uint256 totalVaultSharesBefore,
        uint256 blockTime
    ) private pure returns (uint256) {
        // Short circuit the method with no emission rate
        if (state.emissionRatePerYear == 0) return state.accumulatedRewardPerVaultShare;
        require(0 < state.endTime);
        uint256 time = blockTime < state.endTime ? blockTime : state.endTime;

        uint256 additionalIncentiveAccumulatedPerVaultShare;
        if (state.lastAccumulatedTime < time && 0 < totalVaultSharesBefore) {
            // NOTE: no underflow, checked in if statement
            uint256 timeSinceLastAccumulation = time - state.lastAccumulatedTime;
            // Precision here is:
            //  timeSinceLastAccumulation (SECONDS)
            //  emissionRatePerYear (REWARD_TOKEN_PRECISION)
            //  INTERNAL_TOKEN_PRECISION (1e8)
            // DIVIDE BY
            //  YEAR (SECONDS)
            //  INTERNAL_TOKEN_PRECISION (1e8)
            // => Precision = REWARD_TOKEN_PRECISION * INTERNAL_TOKEN_PRECISION / INTERNAL_TOKEN_PRECISION
            // => rewardTokenPrecision
            additionalIncentiveAccumulatedPerVaultShare =
                (timeSinceLastAccumulation
                    * uint256(Constants.INTERNAL_TOKEN_PRECISION)
                    * state.emissionRatePerYear)
                / (Constants.YEAR * totalVaultSharesBefore);
        }

        return state.accumulatedRewardPerVaultShare + additionalIncentiveAccumulatedPerVaultShare;
    }


    /// @notice Returns the vault shares held by an account prior to changes made by the vault.
    /// Vault account shares are not updated in storage until the vault completes its entry, exit
    /// or deleverage method call. Therefore, when this method is called from the context of the
    /// vault it will always return the amount of vault shares the account had before the action
    /// occurred.
    function _getVaultSharesBefore(address account) internal view returns (uint256) {
        return Deployments.NOTIONAL.getVaultAccount(account, address(this)).vaultShares;
    }

}