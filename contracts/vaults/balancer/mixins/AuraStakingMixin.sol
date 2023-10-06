// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {AuraStakingContext, AuraVaultDeploymentParams} from "../BalancerVaultTypes.sol";
import {ILiquidityGauge} from "../../../../interfaces/balancer/ILiquidityGauge.sol";
import {IAuraBooster, IAuraBoosterLite} from "../../../../interfaces/aura/IAuraBooster.sol";
import {IAuraRewardPool, IAuraL2Coordinator} from "../../../../interfaces/aura/IAuraRewardPool.sol";
import {IAuraStakingProxy} from "../../../../interfaces/aura/IAuraStakingProxy.sol";
import {TokenUtils, IERC20} from "../../../utils/TokenUtils.sol";
import {Deployments} from "../../../global/Deployments.sol";
import {Constants} from "../../../global/Constants.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {BalancerConstants} from "../internal/BalancerConstants.sol";
import {RewardUtils} from "../../common/internal/reward/RewardUtils.sol";
import {VaultEvents} from "../../common/VaultEvents.sol";
import {VaultBase} from "../../common/VaultBase.sol";

abstract contract AuraStakingMixin is VaultBase {
    using TokenUtils for IERC20;

    /// @notice Balancer liquidity gauge used to get a list of reward tokens
    ILiquidityGauge internal immutable LIQUIDITY_GAUGE;
    /// @notice Aura booster contract used for staking BPT
    address internal immutable AURA_BOOSTER;
    /// @notice Aura reward pool contract used for unstaking and claiming reward tokens
    IAuraRewardPool internal immutable AURA_REWARD_POOL;
    uint256 internal immutable AURA_POOL_ID;
    IERC20 internal immutable BAL_TOKEN;
    IERC20 internal immutable AURA_TOKEN;

    constructor(NotionalProxy notional_, AuraVaultDeploymentParams memory params) 
        VaultBase(notional_, params.baseParams.tradingModule) {
        LIQUIDITY_GAUGE = params.baseParams.liquidityGauge;
        AURA_REWARD_POOL = params.rewardPool;

        AURA_BOOSTER = AURA_REWARD_POOL.operator();
        AURA_POOL_ID = AURA_REWARD_POOL.pid();

        IERC20 balToken;
        IERC20 auraToken;

        if (Deployments.CHAIN_ID == Constants.CHAIN_ID_MAINNET) {
            IAuraStakingProxy stakingProxy = IAuraStakingProxy(IAuraBooster(AURA_BOOSTER).stakerRewards());

            balToken = IERC20(stakingProxy.crv());
            auraToken = IERC20(stakingProxy.cvx());
        } else if (Deployments.CHAIN_ID == Constants.CHAIN_ID_ARBITRUM) {
            IAuraBoosterLite booster = IAuraBoosterLite(AURA_BOOSTER);
            IAuraL2Coordinator rewards = IAuraL2Coordinator(booster.rewards());

            balToken = IERC20(booster.crv());
            auraToken = IERC20(rewards.auraOFT());
        } else {
            revert();
        }

        BAL_TOKEN = balToken;
        AURA_TOKEN = auraToken;
    }

    function _auraStakingContext() internal view returns (AuraStakingContext memory) {
        return AuraStakingContext({
            liquidityGauge: LIQUIDITY_GAUGE,
            booster: AURA_BOOSTER,
            rewardPool: AURA_REWARD_POOL,
            poolId: AURA_POOL_ID,
        });
    }

    function _claimAuraRewardTokens() internal returns (bool) {
        return AURA_REWARD_POOL.getReward(address(this), true); // claimExtraRewards = true
    }

    function claimRewardTokens()
        external onlyRole(REWARD_REINVESTMENT_ROLE) returns (
        IERC20[] memory rewardTokens,
        uint256[] memory claimedBalances
    ) {
        rewardTokens = _rewardTokens();
        claimedBalances = RewardUtils._claimRewardTokens(_claimAuraRewardTokens, rewardTokens);
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}