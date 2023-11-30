// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./BaseSingleSidedLPVault.sol";
import "../../contracts/vaults/BalancerComposableAuraVault.sol";
import "../../contracts/vaults/balancer/mixins/AuraStakingMixin.sol";
import "../../interfaces/balancer/IBalancerPool.sol";
import "../../contracts/trading/adapters/BalancerV2Adapter.sol";

abstract contract BaseComposablePool is BaseSingleSidedLPVault {
    bytes32 balancerPoolId;
    BalancerSpotPrice spotPrice;

    function setUp() public override virtual {
        // BAL on Arbitrum
        rewardToken = IERC20(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
        super.setUp();
    }

    function deployVault() internal override returns (IStrategyVault) {
        spotPrice = new BalancerSpotPrice();
        poolToken = IERC20(IAuraRewardPool(address(rewardPool)).asset());
        balancerPoolId = IBalancerPool(address(poolToken)).getPoolId();
        (address[] memory tokens, ,) = IBalancerVault(Deployments.BALANCER_VAULT)
            .getPoolTokens(balancerPoolId);
        numTokens = tokens.length;

        IStrategyVault impl = new BalancerComposableAuraVault(
            NOTIONAL, AuraVaultDeploymentParams({
                rewardPool: IAuraRewardPool(address(rewardPool)),
                whitelistedReward: whitelistedReward,
                baseParams: DeploymentParams({
                    primaryBorrowCurrencyId: primaryBorrowCurrency,
                    balancerPoolId: balancerPoolId,
                    tradingModule: TRADING_MODULE
                })
            }),
            spotPrice
        );

        bytes memory initData = abi.encodeWithSelector(
            ISingleSidedLPStrategyVault.initialize.selector, InitParams({
                name: "Vault",
                borrowCurrencyId: primaryBorrowCurrency,
                settings: settings
            })
        );

        vm.prank(NOTIONAL.owner());
        nProxy proxy = new nProxy(address(impl), initData);

        // NOTE: no token permissions set, single sided join by default
        return IStrategyVault(address(proxy));
    }
}
