// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {AuraStakingContext} from "../BalancerVaultTypes.sol";
import {ILiquidityGauge} from "../../../../interfaces/balancer/ILiquidityGauge.sol";
import {IAuraBooster} from "../../../../interfaces/aura/IAuraBooster.sol";
import {IAuraRewardPool} from "../../../../interfaces/aura/IAuraRewardPool.sol";
import {IAuraStakingProxy} from "../../../../interfaces/aura/IAuraStakingProxy.sol";
import {TokenUtils, IERC20} from "../../../utils/TokenUtils.sol";
import {StrategyVaultSettings, VaultUtils} from "../internal/VaultUtils.sol";
import {BalancerConstants} from "../internal/BalancerConstants.sol";
import {BalancerEvents} from "../BalancerEvents.sol";

abstract contract AuraStakingMixin {
    using TokenUtils for IERC20;

    // @audit maybe some documentation about what each of these contracts do?
    ILiquidityGauge internal immutable LIQUIDITY_GAUGE;
    IAuraBooster internal immutable AURA_BOOSTER;
    IAuraRewardPool internal immutable AURA_REWARD_POOL;
    uint256 internal immutable AURA_POOL_ID;
    address internal immutable FEE_RECEIVER;
    IERC20 internal immutable BAL_TOKEN;
    IERC20 internal immutable AURA_TOKEN;

    constructor(ILiquidityGauge liquidityGauge, IAuraRewardPool auraRewardPool, address feeReceiver) {
        LIQUIDITY_GAUGE = liquidityGauge;
        AURA_REWARD_POOL = auraRewardPool;
        FEE_RECEIVER = feeReceiver;
        AURA_BOOSTER = IAuraBooster(AURA_REWARD_POOL.operator());
        AURA_POOL_ID = AURA_REWARD_POOL.pid();

        IAuraStakingProxy stakingProxy = IAuraStakingProxy(AURA_BOOSTER.stakerRewards());
        BAL_TOKEN = IERC20(stakingProxy.crv());
        AURA_TOKEN = IERC20(stakingProxy.cvx());
    }

    function _rewardTokens() private view returns (IERC20[] memory tokens) {
        uint256 rewardTokenCount = LIQUIDITY_GAUGE.reward_count() + 2;
        tokens = new IERC20[](rewardTokenCount);
        tokens[0] = BAL_TOKEN;
        tokens[1] = AURA_TOKEN;
        for (uint256 i = 2; i < rewardTokenCount; i++) {
            tokens[i] = IERC20(LIQUIDITY_GAUGE.reward_tokens(i - 2));
        }
    }

    function _auraStakingContext() internal view returns (AuraStakingContext memory) {
        return AuraStakingContext({
            liquidityGauge: LIQUIDITY_GAUGE,
            auraBooster: AURA_BOOSTER,
            auraRewardPool: AURA_REWARD_POOL,
            auraPoolId: AURA_POOL_ID,
            rewardTokens: _rewardTokens()
        });
    }

    function claimRewardTokens() external returns (uint256[] memory claimedBalances) {
        uint16 feePercentage = VaultUtils.getStrategyVaultSettings().feePercentage;
        IERC20[] memory rewardTokens = _rewardTokens();

        uint256 numRewardTokens = rewardTokens.length;

        claimedBalances = new uint256[](numRewardTokens);
        for (uint256 i; i < numRewardTokens; i++) {
            claimedBalances[i] = rewardTokens[i].balanceOf(address(this));
        }

        AURA_REWARD_POOL.getReward(address(this), true);
        for (uint256 i; i < numRewardTokens; i++) {
            claimedBalances[i] = rewardTokens[i].balanceOf(address(this)) - claimedBalances[i];

            if (claimedBalances[i] > 0 && feePercentage != 0 && FEE_RECEIVER != address(0)) {
                uint256 feeAmount = claimedBalances[i] * feePercentage / BalancerConstants.VAULT_PERCENT_BASIS;
                // @audit doesn't the claimedBalance need to decrease by the feeAmount?
                // @audit-ok claimedBalances is only used for return values, but that should be noted here
                // or we make this internal and enforce it. We don't want to run into a situation where
                // the return value is used later and it is inaccurate.
                rewardTokens[i].checkTransfer(FEE_RECEIVER, feeAmount);
            }
        }

        emit BalancerEvents.ClaimedRewardTokens(rewardTokens, claimedBalances);
    }
}
