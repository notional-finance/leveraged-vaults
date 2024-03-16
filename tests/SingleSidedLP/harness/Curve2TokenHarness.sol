// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./SingleSidedLPHarness.sol";
import "@contracts/vaults/curve/Curve2TokenConvexVault.sol";
import "@contracts/vaults/curve/mixins/ConvexStakingMixin.sol";

abstract contract Curve2TokenHarness is SingleSidedLPHarness {
    address lpToken;
    CurveInterface curveInterface;

    // // TODO: this is wrong.....
    // function getTradingPermissions() internal pure override returns (
    //     address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    // ) {
    //     token = new address[](2);
    //     permissions = new ITradingModule.TokenPermissions[](2);

    //     token[0] = 0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978; // CRV
    //     token[1] = 0x912CE59144191C1204E64559FE8253a0e49E6548; // ARB

    //     permissions[0] = ITradingModule.TokenPermissions(
    //         // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
    //         { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
    //     );
    //     permissions[1] = ITradingModule.TokenPermissions(
    //         // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
    //         { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
    //     );
    // }

    function deployVaultImplementation() public override returns (
        address impl, bytes memory _metadata
    ) {
        SingleSidedLPMetadata memory _m = abi.decode(metadata, (SingleSidedLPMetadata));

        impl = address(new Curve2TokenConvexVault(
            Deployments.NOTIONAL, ConvexVaultDeploymentParams({
                rewardPool: address(_m.rewardPool),
                whitelistedReward: _m.whitelistedReward,
                baseParams: DeploymentParams({
                    primaryBorrowCurrencyId: _m.primaryBorrowCurrency,
                    pool: address(_m.poolToken),
                    tradingModule: Deployments.TRADING_MODULE,
                    poolToken: address(lpToken),
                    curveInterface: curveInterface
                })
            })
        ));

        _metadata = abi.encode(_m);
    }
}

