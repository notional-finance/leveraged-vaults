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

    function deployVaultImplementation() internal override returns (address impl) {
        poolToken = IERC20(IAuraRewardPool(address(rewardPool)).asset());
        balancerPoolId = IBalancerPool(address(poolToken)).getPoolId();
        console.log(address(rewardPool));
        console.log(address(poolToken));

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
            spotPrice
        ));
    }

    function deployTestVault() internal override returns (IStrategyVault) {
        spotPrice = new BalancerSpotPrice();

        address impl = deployVaultImplementation();
        bytes memory initData = getInitializeData();

        (IERC20[] memory tokens, /* */) = SingleSidedLPVaultBase(payable(address(impl))).TOKENS();
        numTokens = tokens.length;

        vm.prank(NOTIONAL.owner());
        nProxy proxy = new nProxy(address(impl), initData);

        // NOTE: no token permissions set, single sided join by default
        return IStrategyVault(address(proxy));
    }
}
