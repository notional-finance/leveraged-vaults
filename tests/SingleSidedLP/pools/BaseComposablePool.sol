// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../BaseSingleSidedLPVault.sol";
import "../../../contracts/vaults/BalancerComposableAuraVault.sol";
import "../../../contracts/vaults/balancer/mixins/AuraStakingMixin.sol";
import "../../../interfaces/balancer/IBalancerPool.sol";
import "../../../contracts/trading/adapters/BalancerV2Adapter.sol";
import "../BalancerAttacker.sol";

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
        permissions[2] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
    }

    function setUp() public override virtual {
        // BAL on Arbitrum
        rewardTokens.push(IERC20(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8));
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

    function test_RevertIf_ReadOnlyReentrancyAttack() public {
        uint256 maturity = maturities[0];
        uint16 decimals = isETH ? 18 : primaryBorrowToken.decimals();

        BalancerAttacker balancerAttacker = new BalancerAttacker(
            NOTIONAL,
            address(vault),
            maxDeposit / 100,
            maturity,
            address(primaryBorrowToken),
            getRedeemParams(1, maturity),
            getDepositParams(0, 0),
            WHALE
        );
        balancerAttacker.prepareForAttack();

        address account = address(balancerAttacker);
        uint256 deposit = 1 * (10 ** decimals);

        (address[] memory tokens, ,) = IBalancerVault(Deployments.BALANCER_VAULT)
            .getPoolTokens(balancerPoolId);

        uint256[] memory amounts = new uint256[](tokens.length);
        address borrowToken =
            address(primaryBorrowToken) == address(0) ? address(Deployments.WETH) : address(primaryBorrowToken);
        IAsset[] memory assets = new IAsset[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            assets[i] = IAsset(tokens[i]);
            if (tokens[i] == borrowToken) {
                amounts[i] = deposit;
                if (isETH) assets[i] = IAsset(address(0));
            }
        }

        uint256[] memory amountsWithoutBpt = new uint256[](tokens.length - 1);
        uint256 j;
        for (uint256 i; i < amounts.length; i++) {
            if (tokens[i] != address(poolToken)) {
                amountsWithoutBpt[j] = amounts[i];
                j++;
            }
        }

        bytes memory customData = abi.encode(
            IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
            amountsWithoutBpt,
            0
        );

        uint256 value;
        if (isETH) {
            deal(account, deposit);
            value = deposit;
        } else {
            if (WHALE != address(0)) {
                // USDC does not work with `deal` so transfer from a whale account instead.
                vm.prank(WHALE);
                primaryBorrowToken.transfer(address(account), deposit);
            } else {
                deal(address(primaryBorrowToken), address(account), deposit, true);
            }
            vm.prank(account);
            primaryBorrowToken.approve(address(Deployments.BALANCER_VAULT), deposit);
        }

        deal(account, 2 ether);
        vm.prank(account);
        // send excess amount of eth so we can execute attack when balancer vault
        // returns excess value
        Deployments.BALANCER_VAULT.joinPool{value: value + 0.5 ether}(
            balancerPoolId,
            account, // sender
            account, // reciever
            IBalancerVault.JoinPoolRequest(
                assets,
                amounts,
                customData,
                false // Don't use internal balances
            )
        );
        // check BalancerAttacker was actually called
        assertTrue(balancerAttacker.called());
    }
}
