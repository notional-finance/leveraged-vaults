// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {AuraStakingContext, AuraVaultDeploymentParams} from "../BalancerVaultTypes.sol";
import {IAuraBooster, IAuraBoosterLite} from "../../../../interfaces/aura/IAuraBooster.sol";
import {IAuraRewardPool} from "../../../../interfaces/aura/IAuraRewardPool.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {SingleSidedLPVaultBase} from "../../common/SingleSidedLPVaultBase.sol";

/**
 * Base class for all Aura strategies
 */
abstract contract AuraStakingMixin is SingleSidedLPVaultBase {

    /// @notice Aura booster contract used for staking BPT
    address internal immutable AURA_BOOSTER;
    /// @notice Aura reward pool contract used for unstaking and claiming reward tokens
    IAuraRewardPool internal immutable AURA_REWARD_POOL;
    /// @notice Aura pool ID used for staking
    uint256 internal immutable AURA_POOL_ID;

    constructor(NotionalProxy notional_, AuraVaultDeploymentParams memory params) 
        SingleSidedLPVaultBase(notional_, params.baseParams.tradingModule) {
        AURA_REWARD_POOL = params.rewardPool;

        AURA_BOOSTER = AURA_REWARD_POOL.operator();
        AURA_POOL_ID = AURA_REWARD_POOL.pid();
    }

    /// @notice returns the Aura staking context
    /// @return aura staking context
    function _auraStakingContext() internal view returns (AuraStakingContext memory) {
        return AuraStakingContext({
            booster: AURA_BOOSTER,
            rewardPool: AURA_REWARD_POOL,
            poolId: AURA_POOL_ID
        });
    }
    
    /// @notice Claim reward tokens
    function _claimRewardTokens() internal override {
        // Claim all reward tokens including extra tokens
        bool success = AURA_REWARD_POOL.getReward(address(this), true); // claimExtraRewards = true
        require(success);
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}