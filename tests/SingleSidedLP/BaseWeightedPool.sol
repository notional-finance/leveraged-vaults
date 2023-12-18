// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./BaseSingleSidedLPVault.sol";
import "../../contracts/vaults/BalancerWeightedAuraVault.sol";
import "../../contracts/vaults/balancer/mixins/AuraStakingMixin.sol";
import "../../interfaces/balancer/IBalancerPool.sol";
import "../../contracts/trading/adapters/BalancerV2Adapter.sol";

abstract contract BaseWeightedPool is BaseSingleSidedLPVault {
    bytes32 balancerPoolId;

    function setUp() public override virtual {
        // BAL on Arbitrum
        rewardToken = IERC20(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
        super.setUp();
    }

    function deployVaultImplementation() internal override returns (address impl) {
        poolToken = IERC20(IAuraRewardPool(address(rewardPool)).asset());
        balancerPoolId = IBalancerPool(address(poolToken)).getPoolId();

        impl = address(new BalancerWeightedAuraVault(
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

