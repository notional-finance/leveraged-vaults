// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../BaseSingleSidedLPVault.sol";
import "../../../contracts/vaults/Curve2TokenConvexVault.sol";
import "../../../contracts/vaults/curve/ConvexStakingMixin.sol";

abstract contract BaseCurve2Token is DeployProxyVault, BaseSingleSidedLPVault {
    address lpToken;

    function getTradingPermissions() internal pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](2);
        permissions = new ITradingModule.TokenPermissions[](2);

        token[0] = 0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978; // CRV
        token[1] = 0x912CE59144191C1204E64559FE8253a0e49E6548; // ARB

        permissions[0] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        permissions[1] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
    }

    function setUp() public override virtual {
        // CRV on Arbitrum
        rewardToken = IERC20(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
        super.setUp();
    }

    function deployVaultImplementation() internal override returns (address) {
        IStrategyVault impl = new Curve2TokenConvexVault(
            NOTIONAL, ConvexVaultDeploymentParams({
                rewardPool: address(rewardPool),
                whitelistedReward: whitelistedReward,
                baseParams: DeploymentParams({
                    primaryBorrowCurrencyId: primaryBorrowCurrency,
                    pool: address(poolToken),
                    tradingModule: Deployments.TRADING_MODULE,
                    poolToken: address(lpToken)
                })
            })
        );

        return address(impl);
    }
}

