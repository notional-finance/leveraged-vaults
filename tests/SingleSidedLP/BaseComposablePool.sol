// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./BaseSingleSidedLPVault.sol";
import "../../contracts/vaults/BalancerComposableAuraVault.sol";
import "../../contracts/vaults/balancer/mixins/AuraStakingMixin.sol";
import "../../interfaces/balancer/IBalancerPool.sol";
import "../../contracts/trading/adapters/BalancerV2Adapter.sol";

abstract contract BaseComposablePool is BaseSingleSidedLPVault {
    bytes32 balancerPoolId;

    function getTradingPermissions() internal pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](3);
        permissions = new ITradingModule.TokenPermissions[](3);

        token[0] = 0x1509706a6c66CA549ff0cB464de88231DDBe213B; // AURA
        token[1] = 0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8; // BAL
        token[2] = 0x912CE59144191C1204E64559FE8253a0e49E6548; // ARB

        permissions[0] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        permissions[1] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        permissions[1] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
    }

    function setUp() public override virtual {
        // BAL on Arbitrum
        rewardToken = IERC20(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
        super.setUp();
    }

    function deployVaultImplementation() internal override returns (address impl) {
        poolToken = IERC20(IAuraRewardPool(address(rewardPool)).asset());
        balancerPoolId = IBalancerPool(address(poolToken)).getPoolId();

        impl = address(new BalancerComposableAuraVault(
            NOTIONAL, AuraVaultDeploymentParams({
                rewardPool: IAuraRewardPool(address(rewardPool)),
                whitelistedReward: whitelistedReward,
                baseParams: DeploymentParams({
                    primaryBorrowCurrencyId: primaryBorrowCurrency,
                    balancerPoolId: balancerPoolId,
                    tradingModule: Deployments.TRADING_MODULE
                })
            }),
            // NOTE: this is hardcoded so if you want to run tests against it
            // you need to change the deployment
            BalancerSpotPrice(Deployments.BALANCER_SPOT_PRICE)
        ));
    }

}
