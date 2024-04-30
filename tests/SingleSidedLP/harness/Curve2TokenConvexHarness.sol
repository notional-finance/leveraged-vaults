// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./SingleSidedLPHarness.sol";
import "@contracts/vaults/curve/Curve2TokenConvexVault.sol";
import {CurveInterface} from "@interfaces/curve/ICurvePool.sol";
import "@contracts/vaults/curve/mixins/ConvexStakingMixin.sol";

abstract contract Curve2TokenConvexHarness is SingleSidedLPHarness {
    address lpToken;
    CurveInterface curveInterface;

    function deployVaultImplementation() public override returns (
        address impl, bytes memory _metadata
    ) {
        SingleSidedLPMetadata memory _m = abi.decode(metadata, (SingleSidedLPMetadata));

        impl = address(new Curve2TokenConvexVault(
            Deployments.NOTIONAL, ConvexVaultDeploymentParams({
                rewardPool: address(_m.rewardPool),
                baseParams: DeploymentParams({
                    primaryBorrowCurrencyId: _m.primaryBorrowCurrency,
                    pool: address(_m.poolToken),
                    tradingModule: Deployments.TRADING_MODULE,
                    poolToken: address(lpToken),
                    gauge: address(0),
                    whitelistedReward: _m.whitelistedReward,
                    curveInterface: curveInterface
                })
            })
        ));

        _metadata = abi.encode(_m);
    }
}