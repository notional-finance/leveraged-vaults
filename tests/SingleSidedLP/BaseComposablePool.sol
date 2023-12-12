// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./BaseSingleSidedLPVault.sol";
import "../../contracts/vaults/BalancerComposableAuraVault.sol";
import "../../contracts/vaults/balancer/mixins/AuraStakingMixin.sol";
import "../../interfaces/balancer/IBalancerPool.sol";
import "../../contracts/trading/adapters/BalancerV2Adapter.sol";
import "./BalancerAttacker.sol";

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

    function test_RevertIf_reentrancy() public {
        uint256 maturity = maturities[0];
        uint16 decimals = isETH ? 18 : primaryBorrowToken.decimals();

        BalancerAttacker balancerAttacker = new BalancerAttacker(
            NOTIONAL,
            address(vault),
            maxDeposit / 100,
            maturity,
            address(primaryBorrowToken),
            getRedeemParams(1, maturity),
            getDepositParams(0, 0)
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
            deal(address(primaryBorrowToken), account, deposit);
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