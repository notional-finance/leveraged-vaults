// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./SingleSidedLPHarness.sol";
import "@contracts/vaults/balancer/BalancerComposableWrappedTwoToken.sol";
import "@contracts/vaults/balancer/mixins/AuraStakingMixin.sol";
import "@interfaces/balancer/IBalancerPool.sol";
import "@contracts/trading/adapters/BalancerV2Adapter.sol";

abstract contract WrappedComposablePoolHarness is SingleSidedLPHarness {
    struct WrappedComposableMetadata {
        SingleSidedLPMetadata meta;
        uint32 defaultSlippage;
        uint16 dexId;
        bytes32 exchangeData;
        address borrowToken;
    }

    function getMetadata() override public view returns (SingleSidedLPMetadata memory _m) {
        return abi.decode(metadata, (WrappedComposableMetadata)).meta;
    }

    function setMetadata(WrappedComposableMetadata memory _m) public returns (bytes memory) {
        metadata = abi.encode(_m);
        return metadata;
    }

    function deployVaultImplementation() public override returns (
        address impl, bytes memory _metadata
    ) {
        WrappedComposableMetadata memory meta = abi.decode(metadata, (WrappedComposableMetadata));
        SingleSidedLPMetadata memory _m = meta.meta;

        _m.poolToken = IERC20(IAuraRewardPool(address(_m.rewardPool)).asset());
        _m.balancerPoolId = IBalancerPool(address(_m.poolToken)).getPoolId();

        impl = address(new BalancerComposableWrappedTwoToken(
            meta.defaultSlippage,
            meta.dexId,
            meta.exchangeData,
            meta.borrowToken,
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

        setMetadata(meta);
        _metadata = abi.encode(meta.meta);
    }
}
