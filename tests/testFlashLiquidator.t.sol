// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "@contracts/vaults/balancer/BalancerComposableAuraVault.sol";
import "@contracts/vaults/balancer/mixins/AuraStakingMixin.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@contracts/liquidator/AaveFlashLiquidator.sol";
import "@deployments/Deployments.sol";
import "@interfaces/notional/NotionalProxy.sol";
import "@interfaces/notional/IVaultController.sol";
import "@interfaces/notional/ISingleSidedLPStrategyVault.sol";
import "@contracts/vaults/common/VaultRewarderLib.sol";
import "@contracts/vaults/common/SingleSidedLPVaultBase.sol";

contract TestFlashLiquidator is Test {
    string RPC_URL = vm.envString("RPC_URL");

    address constant AAVE = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    NotionalProxy constant NOTIONAL = NotionalProxy(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);

    function deployLiquidator() internal returns (AaveFlashLiquidator liquidator) {
        // All currencies should be automatically enabled in constructor
        liquidator = new AaveFlashLiquidator(NOTIONAL, AAVE);
        return liquidator;
    }

    function getAsset(uint16 currencyId) internal view returns (address asset) {
        (/* */, Token memory t) = NOTIONAL.getCurrency(currencyId);
        return t.tokenAddress == address(0) ? address(Deployments.WETH) : t.tokenAddress;
    }

    function getParams(
        uint256 numTokens,
        uint16 currencyId,
        address account,
        address vault
    ) internal view returns (
        FlashLiquidatorBase.LiquidationParams memory params,
        address asset
    ) {
        RedeemParams memory redeem = RedeemParams({
            minAmounts: new uint256[](numTokens),
            redemptionTrades: new TradeParams[](0)
        });

        params = FlashLiquidatorBase.LiquidationParams({
            liquidationType: FlashLiquidatorBase.LiquidationType.DELEVERAGE_VAULT_ACCOUNT,
            currencyId: currencyId,
            currencyIndex: 0,
            account: account,
            vault: vault,
            useVaultDeleverage: true,
            actionData: abi.encode(redeem)
        });

        asset = getAsset(currencyId);
    }

    function test_RevertIf_VaultAccountCollateralized() public {
        // https://arbiscan.io/tx/0x07c30d2f9058de2226c608e5a28063806a08eeb3cf02bf78c83a784a7cd16abb
        vm.createSelectFork(RPC_URL, 174110893);
        address vault = 0x37dD23Ab1885982F789A2D6400B583B8aE09223d;
        address account = 0xd74e7325dFab7D7D1ecbf22e6E6874061C50f243;
        AaveFlashLiquidator liquidator = deployLiquidator();
        uint16 currencyId = 5; // wstETH
        (/* */, int256 maxUnderlying) = liquidator.getOptimalDeleveragingParams(
            account, vault
        );
        assertEq(maxUnderlying, 0, "Zero Deposit");

        (
            FlashLiquidatorBase.LiquidationParams memory params,
            address asset
        ) = getParams(4, currencyId, account, vault);

        vm.expectRevert();
        liquidator.flashLiquidate(asset, uint256(maxUnderlying) * 1e10, params);
    }

    function test_deleverageVariableBorrow() public {
        // https://arbiscan.io/tx/0x1e6c0039da8da056170e2e0173340bbddc360e1cf4c982a12e72ad6123db770d
        vm.createSelectFork(RPC_URL, 174119121);
        address vault = 0x37dD23Ab1885982F789A2D6400B583B8aE09223d;
        address account = 0xd74e7325dFab7D7D1ecbf22e6E6874061C50f243;
        AaveFlashLiquidator liquidator = deployLiquidator();
        uint16 currencyId = 5; // wstETH
        (/* */, int256 maxUnderlying) = liquidator.getOptimalDeleveragingParams(
            account, vault
        );
        assertGt(maxUnderlying, 0, "Zero Deposit");

        (
            FlashLiquidatorBase.LiquidationParams memory params,
            address asset
        ) = getParams(4, currencyId, account, vault);

        liquidator.flashLiquidate(asset, uint256(maxUnderlying) * 1e10, params);

        // Assert liquidation was a success
        (/* */, maxUnderlying) = liquidator.getOptimalDeleveragingParams(
            account, vault
        );
        assertEq(maxUnderlying, 0, "Zero Deposit");
    }

    function test_deleverageVariableBorrow_accruedFees() public {
        // https://arbiscan.io/tx/0x9f25703bca3bc21ebc9d1e5bb62ff0c6b801d833926b387029bf0c61923594c3
        vm.createSelectFork(RPC_URL, 174178022);
        address vault = 0x0E8C1A069f40D0E8Fa861239D3e62003cBF3dCB2;
        address account = 0xd74e7325dFab7D7D1ecbf22e6E6874061C50f243;
        AaveFlashLiquidator liquidator = deployLiquidator();
        uint16 currencyId = 1; // ETH
        (/* */, int256 maxUnderlying) = liquidator.getOptimalDeleveragingParams(
            account, vault
        );
        assertGt(maxUnderlying, 0, "Zero Deposit");

        (
            FlashLiquidatorBase.LiquidationParams memory params,
            address asset
        ) = getParams(3, currencyId, account, vault);

        liquidator.flashLiquidate(asset, uint256(maxUnderlying) * 1e10, params);

        // Assert liquidation was a success
        (/* */, maxUnderlying) = liquidator.getOptimalDeleveragingParams(
            account, vault
        );
        assertEq(maxUnderlying, 0, "Zero Deposit");
    }

    function test_deleverageFixedBorrow_noCashPurchase() public {
        // https://arbiscan.io/tx/0x0febc1d04e2cdecc7bb1b553957594576f2b7a44a02cf7ab9137c2954f8a6415
        vm.createSelectFork(RPC_URL, 160447900);
        address vault = 0x8Ae7A8789A81A43566d0ee70264252c0DB826940;
        address account = 0xf5c4e22e63F1eb3451cBE41Bd906229DCf9dba15;
        uint16 currencyId = 3; // USDC
        AaveFlashLiquidator liquidator = deployLiquidator();
        (/* */, int256 maxUnderlying) = liquidator.getOptimalDeleveragingParams(
            account, vault
        );
        assertGt(maxUnderlying, 0, "Zero Deposit");

        (
            FlashLiquidatorBase.LiquidationParams memory params,
            address asset
        ) = getParams(5, currencyId, account, vault);

        liquidator.flashLiquidate(asset, uint256(maxUnderlying) / 100 + 1e6, params);
        VaultAccount memory va = NOTIONAL.getVaultAccount(account, vault);

        // Assert liquidation was a success
        (/* */, maxUnderlying) = liquidator.getOptimalDeleveragingParams(
            account, vault
        );
        assertEq(maxUnderlying, 0, "Zero Deposit");
        assertGt(va.tempCashBalance, 0, "Cash Balance");
    }

    function test_deleverageFixedBorrow_cashPurchase() public {
        // https://arbiscan.io/tx/0x0febc1d04e2cdecc7bb1b553957594576f2b7a44a02cf7ab9137c2954f8a6415
        vm.createSelectFork(RPC_URL, 160447900);
        new VaultRewarderLib(); // address is hardcoded in Deployments
        address vault = 0x8Ae7A8789A81A43566d0ee70264252c0DB826940;
        address account = 0xf5c4e22e63F1eb3451cBE41Bd906229DCf9dba15;
        uint16 currencyId = 3; // USDC
        AaveFlashLiquidator liquidator = deployLiquidator();
        (/* */, int256 maxUnderlying) = liquidator.getOptimalDeleveragingParams(
            account, vault
        );
        assertGt(maxUnderlying, 0, "Zero Deposit");

        // New impl:
        address impl = address(new BalancerComposableAuraVault(
            NOTIONAL, AuraVaultDeploymentParams({
                rewardPool: IAuraRewardPool(0x416C7Ad55080aB8e294beAd9B8857266E3B3F28E),
                whitelistedReward: address(0),
                baseParams: DeploymentParams({
                    primaryBorrowCurrencyId: currencyId,
                    balancerPoolId: 0x423a1323c871abc9d89eb06855bf5347048fc4a5000000000000000000000496,
                    tradingModule: Deployments.TRADING_MODULE
                })
            }),
            // NOTE: this is hardcoded so if you want to run tests against it
            // you need to change the deployment
            BalancerSpotPrice(Deployments.BALANCER_SPOT_PRICE)
        ));
        vm.prank(NOTIONAL.owner());
        UUPSUpgradeable(vault).upgradeToAndCall(
            impl,
            abi.encodeWithSelector(SingleSidedLPVaultBase.setRewardPoolStorage.selector)
        );

        (
            FlashLiquidatorBase.LiquidationParams memory params,
            address asset
        ) = getParams(5, currencyId, account, vault);
        params.liquidationType = FlashLiquidatorBase.LiquidationType.DELEVERAGE_VAULT_ACCOUNT_AND_LIQUIDATE_CASH;

        liquidator.flashLiquidate(asset, uint256(maxUnderlying) / 100 + 1e6, params);
        VaultAccount memory va = NOTIONAL.getVaultAccount(account, vault);

        // Assert liquidation was a success
        (/* */, maxUnderlying) = liquidator.getOptimalDeleveragingParams(
            account, vault
        );
        assertEq(maxUnderlying, 0, "Zero Deposit");
        // Allow for a little dust in the cash balance rather than the liquidator
        assertLt(va.tempCashBalance, 100, "Cash Balance");
    }
}