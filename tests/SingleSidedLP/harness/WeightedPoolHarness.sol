// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./SingleSidedLPHarness.sol";
import "@contracts/vaults/balancer/BalancerWeightedAuraVault.sol";
import "@contracts/vaults/balancer/mixins/AuraStakingMixin.sol";
import "@interfaces/balancer/IBalancerPool.sol";
import "@contracts/trading/adapters/BalancerV2Adapter.sol";

abstract contract WeightedPoolHarness is SingleSidedLPHarness {

    function deployVaultImplementation() public override returns (
        address impl, bytes memory _metadata
    ) {
        SingleSidedLPMetadata memory _m = abi.decode(metadata, (SingleSidedLPMetadata));

        _m.poolToken = IERC20(IAuraRewardPool(address(_m.rewardPool)).asset());
        _m.balancerPoolId = IBalancerPool(address(_m.poolToken)).getPoolId();

        impl = address(new BalancerWeightedAuraVault(
            Deployments.NOTIONAL, AuraVaultDeploymentParams({
                rewardPool: IAuraRewardPool(address(_m.rewardPool)),
                whitelistedReward: _m.whitelistedReward,
                baseParams: DeploymentParams({
                    primaryBorrowCurrencyId: _m.primaryBorrowCurrency,
                    balancerPoolId: _m.balancerPoolId,
                    tradingModule: Deployments.TRADING_MODULE
                })
            }),
            // NOTE: this is hardcoded so if you want to run tests against it
            // you need to change the deployment
            BalancerSpotPrice(Deployments.BALANCER_SPOT_PRICE)
        ));

        _metadata = abi.encode(_m);
    }
}

