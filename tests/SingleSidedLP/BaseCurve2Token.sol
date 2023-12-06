// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./BaseSingleSidedLPVault.sol";
import "../../contracts/vaults/Curve2TokenConvexVault.sol";
import "../../contracts/vaults/curve/ConvexStakingMixin.sol";

abstract contract BaseCurve2Token is DeployProxyVault, BaseSingleSidedLPVault {
    address lpToken;

    function getTradingPermissions() internal pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](1);
        permissions = new ITradingModule.TokenPermissions[](1);

        token[0] = 0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978; // CRV

        permissions[0] = ITradingModule.TokenPermissions(
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

    function deployTestVault() internal override returns (IStrategyVault) {
        numTokens = 2;
        address impl = deployVaultImplementation();
        bytes memory initData = getInitializeData();

        vm.prank(NOTIONAL.owner());
        nProxy proxy = new nProxy(impl, initData);

        // NOTE: no token permissions set, single sided join by default
        return IStrategyVault(address(proxy));
    }
}

