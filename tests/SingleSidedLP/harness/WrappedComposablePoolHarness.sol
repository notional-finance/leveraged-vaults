// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./SingleSidedLPHarness.sol";
import "@contracts/vaults/balancer/BalancerComposableWrappedTwoToken.sol";
import "@contracts/vaults/balancer/mixins/AuraStakingMixin.sol";
import "@interfaces/balancer/IBalancerPool.sol";
import "@contracts/trading/adapters/BalancerV2Adapter.sol";

abstract contract WrappedComposablePoolHarness is SingleSidedLPHarness {
    function deployVaultImplementation() public override returns (
        address impl, bytes memory _metadata
    ) {
        SingleSidedLPMetadata memory _m = getMetadata();

        _m.poolToken = IERC20(IAuraRewardPool(address(_m.rewardPool)).asset());
        _m.balancerPoolId = IBalancerPool(address(_m.poolToken)).getPoolId();

        impl = address(new BalancerComposableWrappedTwoToken(
            0,
            0,
            bytes32(0),
            address(0),
            Deployments.NOTIONAL, AuraVaultDeploymentParams({
                rewardPool: IAuraRewardPool(address(_m.rewardPool)),
                whitelistedReward: _m.whitelistedReward,
                baseParams: DeploymentParams({
                    primaryBorrowCurrencyId: 7,
                    balancerPoolId: _m.balancerPoolId,
                    tradingModule: Deployments.TRADING_MODULE
                })
            }),
            // NOTE: this is hardcoded so if you want to run tests against it
            // you need to change the deployment
            BalancerSpotPrice(Deployments.BALANCER_SPOT_PRICE)
        ));

        _metadata = setMetadata(_m);
    }
}
