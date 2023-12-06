// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./BaseSingleSidedLPVault.sol";
import "../../contracts/vaults/Curve2TokenConvexVault.sol";
import "../../contracts/vaults/curve/ConvexStakingMixin.sol";

abstract contract BaseCurve2Token is DeployProxyVault, BaseSingleSidedLPVault {
    address lpToken;

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

    function deployVault() internal override returns (IStrategyVault) {
        numTokens = 2;
        address impl = deployVaultImplementation();
        bytes memory initData = getInitializeData();

        vm.prank(NOTIONAL.owner());
        nProxy proxy = new nProxy(impl, initData);

        // NOTE: no token permissions set, single sided join by default
        return IStrategyVault(address(proxy));
    }
}

