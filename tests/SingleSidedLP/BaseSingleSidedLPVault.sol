// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../BaseAcceptanceTest.sol";
import "@contracts/vaults/common/SingleSidedLPVaultBase.sol";
import "@contracts/proxy/nProxy.sol";
import "@interfaces/notional/ISingleSidedLPStrategyVault.sol";
import "@interfaces/trading/ITradingModule.sol";
import "./BalancerAttacker.sol";

struct SingleSidedLPMetadata {
    bytes32 balancerPoolId;
    uint16 primaryBorrowCurrency;
    StrategyVaultSettings settings;
    IERC20 rewardPool;
    IERC20 poolToken;
    IERC20[] rewardTokens;
    address whitelistedReward;
}

abstract contract BaseSingleSidedLPVault is BaseAcceptanceTest {
    uint256 numTokens;
    SingleSidedLPMetadata metadata;

    function deployTestVault() internal override returns (IStrategyVault) {
        (address impl, bytes memory _metadata) = harness.deployVaultImplementation();
        metadata = abi.decode(_metadata, (SingleSidedLPMetadata));
        nProxy proxy;

        address existingDeployment = harness.EXISTING_DEPLOYMENT();
        if (existingDeployment != address(0)) {
            SingleSidedLPVaultBase b = SingleSidedLPVaultBase(payable(existingDeployment));
            ISingleSidedLPStrategyVault.SingleSidedLPStrategyVaultInfo memory beforeInfo = b.getStrategyVaultInfo();

            proxy = nProxy(payable(existingDeployment));
            vm.prank(Deployments.NOTIONAL.owner());
            UUPSUpgradeable(address(proxy)).upgradeToAndCall(
                impl,
                abi.encodeWithSelector(SingleSidedLPVaultBase.setRewardPoolStorage.selector)
            );

            ISingleSidedLPStrategyVault.SingleSidedLPStrategyVaultInfo memory afterInfo = b.getStrategyVaultInfo();
            assertEq(abi.encode(afterInfo), abi.encode(beforeInfo));

            vm.prank(Deployments.NOTIONAL.owner());
            b.setStrategyVaultSettings(metadata.settings);
        } else {
            bytes memory initData = harness.getInitializeData();

            vm.prank(Deployments.NOTIONAL.owner());
            proxy = new nProxy(address(impl), initData);
        }

        SingleSidedLPVaultBase p = SingleSidedLPVaultBase(payable(address(proxy)));
        totalVaultSharesAllMaturities = p.getStrategyVaultInfo().totalVaultShares;
        {
            (IERC20[] memory tokens, /* */) = p.TOKENS();
            numTokens = tokens.length;
        }

        (address[] memory t, address[] memory oracles) = harness.getRequiredOracles();
        for (uint256 i; i < t.length; i++) {
            (AggregatorV2V3Interface oracle, /* */) = Deployments.TRADING_MODULE.priceOracles(t[i]);
            if (address(oracle) == address(0)) {
                setPriceOracle(t[i], oracles[i]);
            } else {
                require(address(oracle) == oracles[i], "Oracle Mismatch");
            }
        }

        // NOTE: no token permissions set, single sided join by default
        return IStrategyVault(address(proxy));
    }

    function getDepositParams(
        uint256 /* depositAmount */,
        uint256 /* maturity */
    ) internal pure override returns (bytes memory) {
        DepositParams memory d;
        d.minPoolClaim = 0;

        return abi.encode(d);
    }

    function getRedeemParams(
        uint256 /* vaultShares */,
        uint256 /* maturity */
    ) internal view override returns (bytes memory) {
        RedeemParams memory d;
        d.minAmounts = new uint256[](numTokens);

        return abi.encode(d);
    }

    function v() internal view returns (SingleSidedLPVaultBase) {
        return SingleSidedLPVaultBase(payable(address(vault)));
    }

    function checkInvariants() internal override {
        ISingleSidedLPStrategyVault.SingleSidedLPStrategyVaultInfo memory s = v().getStrategyVaultInfo();

        assertEq(
            totalVaultSharesAllMaturities,
            s.totalVaultShares,
            "Total Vault Shares"
        );

        assertGe(
            s.totalLPTokens,
            s.totalVaultShares * 1e18 / 1e8,
            "Total LP Tokens"
        );
    }

    function test_RevertIf_nonOwnerMethods() public {
        vm.expectRevert("Unauthorized");
        v().setStrategyVaultSettings(StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 1,
            oraclePriceDeviationLimitPercent: 50,
            numRewardTokens: 0,
            forceClaimAfter: 1 weeks
        }));

        vm.expectRevert("Unauthorized");
        v().upgradeTo(address(0));

        vm.expectRevert("Initializable: contract is already initialized");
        StrategyVaultSettings memory s;
        v().initialize(InitParams("Vault", metadata.primaryBorrowCurrency, s));

        vm.expectRevert(Errors.VaultNotLocked.selector);
        v().tradeTokensBeforeRestore(new SingleSidedRewardTradeParams[](0));
    }

    function test_RevertIf_joinAboveMaxPoolShare() public {
        address account = makeAddr("account");
        uint256 maturity = maturities[0];

        vm.prank(Deployments.NOTIONAL.owner());
        v().setStrategyVaultSettings(StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 1,
            oraclePriceDeviationLimitPercent: 50,
            numRewardTokens: 0,
            forceClaimAfter: 1 weeks
        }));

        
        expectRevert_enterVaultBypass(
            account, 100_000 * precision, maturity, getDepositParams(0, 0)
            // NOTE: forge is not matching this selector properly
            // Errors.PoolShareTooHigh.selector
        );
    }

    function test_RevertIf_belowMinPoolClaim() public {
        address account = makeAddr("account");
        uint256 maturity = maturities[0];
        DepositParams memory d;
        d.minPoolClaim = 100_000e18;
        // No explicit revert message is set here b/c the revert should occur inside
        // the DEX
        expectRevert_enterVaultBypass(
            account, maxDeposit, maturity, abi.encode(d)
        );
    }

    function test_RevertIf_belowMinAmounts() public {
        address account = makeAddr("account");
        uint256 maturity = maturities[0];
        uint256 vaultShares = enterVault(
            account, maxDeposit, maturity, getDepositParams(0, 0)
        );

        // Fill all the redeem params with values above the deposit
        RedeemParams memory d;
        d.minAmounts = new uint256[](numTokens);
        for (uint256 i; i < d.minAmounts.length; i++) d.minAmounts[i] = maxDeposit * 2;

        vm.expectRevert();
        exitVault(account, vaultShares, maturity, abi.encode(d));
    }

    function test_RevertIf_NoAccessEmergencyExit() public {
        address account = makeAddr("account");
        address exit = makeAddr("exit");
        uint256 maturity = maturities[0];
        enterVault(account, maxDeposit, maturity, getDepositParams(0, 0));

        vm.prank(exit);
        // Access control revert on role
        vm.expectRevert();
        v().emergencyExit(0, "");
    }

    function setup_EmergencyExit() internal returns (
        uint256[] memory exitBalances,
        address exit,
        uint256 initialBalance
    ) {
        address account = makeAddr("account");
        exit = makeAddr("exit");
        uint256 maturity = maturities[0];
        enterVault(
            account, maxDeposit, maturity, getDepositParams(0, 0)
        );

        vm.prank(Deployments.NOTIONAL.owner());
        v().grantRole(EMERGENCY_EXIT_ROLE, exit);

        if (address(metadata.rewardPool) != address(0)) {
            initialBalance = metadata.rewardPool.balanceOf(address(vault));
        } else {
            initialBalance = metadata.poolToken.balanceOf(address(vault));
        }
        assertGt(initialBalance, 0);
        (IERC20[] memory tokens, /* */) = v().TOKENS();
        uint256[] memory initialBalances = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; i++) {
            if (address(tokens[i]) == address(0)) {
                initialBalances[i] = address(vault).balance;
            } else if (tokens[i] != metadata.poolToken) {
                initialBalances[i] = tokens[i].balanceOf(address(vault));
            }
        }

        vm.prank(exit);
        v().emergencyExit(0, "");

        exitBalances = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; i++) {
            if (address(tokens[i]) == address(0)) {
                exitBalances[i] = address(vault).balance;
                assertGt(exitBalances[i], initialBalances[i]);
            } else if (tokens[i] != metadata.poolToken) {
                exitBalances[i] = tokens[i].balanceOf(address(vault));
                assertGt(exitBalances[i], initialBalances[i]);
            }
        }
    }

    function test_EmergencyExit_LocksVault() public {
        address account = makeAddr("account");
        uint256 maturity = maturities[0];
        (uint256[] memory exitBalances, address exit, /* */) = setup_EmergencyExit();

        if (address(metadata.rewardPool) != address(0)) {
            assertEq(metadata.rewardPool.balanceOf(address(vault)), 0);
        }
        assertEq(metadata.poolToken.balanceOf(address(vault)), 0);
        assertEq(v().isLocked(), true);

        // Assert that these methods revert due to locking
        expectRevert_enterVaultBypass(
            account, maxDeposit, maturity, getDepositParams(0, 0),
            Errors.VaultLocked.selector
        );

        vm.expectRevert();
        // 0.01e8 is an intentionally small number here to avoid underflows in
        // the test code, we expect a revert no matter what
        exitVault(account, 0.01e8, maturity, getRedeemParams(0, 0));

        vm.expectRevert(Errors.VaultLocked.selector);
        vault.convertStrategyToUnderlying(account, 0.01e8, maturity);

        vm.expectRevert(Errors.VaultLocked.selector);
        v().reinvestReward(new SingleSidedRewardTradeParams[](0), 0);

        // This method should still work
        assertGt(vault.getExchangeRate(maturity), 0);

        // Exit does not have proper authentication
        vm.prank(exit);
        vm.expectRevert();
        v().restoreVault(0, abi.encode(exitBalances));

        // Test trade authorization
        vm.prank(exit);
        vm.expectRevert("Unauthorized");
        v().tradeTokensBeforeRestore(new SingleSidedRewardTradeParams[](0));
    }

    function test_EmergencyExit() public {
        uint256 maturity = maturities[0];
        (uint256[] memory exitBalances, /* */, uint256 initialBalance) = setup_EmergencyExit();

        // Restore the vault
        vm.prank(Deployments.NOTIONAL.owner());
        v().restoreVault(0, abi.encode(exitBalances));

        (IERC20[] memory tokens, /* */) = v().TOKENS();
        // All token balances should be cleared.
        for (uint256 i; i < tokens.length; i++) {
            if (address(tokens[i]) == address(0)) {
                assertEq(address(vault).balance, 0, "eth balance");
            } else if (tokens[i] != metadata.poolToken) {
                assertEq(tokens[i].balanceOf(address(vault)), 0, "token balance");
            }
        }

        uint256 postRestore;
        if (address(metadata.rewardPool) != address(0)) {
            postRestore = metadata.rewardPool.balanceOf(address(vault));
        } else {
            postRestore = metadata.poolToken.balanceOf(address(vault));
        }
        assertRelDiff(initialBalance, postRestore, 0.0001e9, "Restore Balance");
        assertEq(v().isLocked(), false);

        address account = makeAddr("account2");
        // All of these calls should succeed
        uint256 vaultShares = enterVault(account, maxDeposit / 2, maturity, getDepositParams(0, 0));
        vault.convertStrategyToUnderlying(account, vaultShares, maturity);
        vm.warp(block.timestamp + 2 minutes);
        // NOTE: the exitVaultBypass above causes an underflow inside exitVaultBypass
        // here because the vault shares are removed from the test accounting even though
        // the call reverts earlier.
        exitVault(account, vaultShares, maturity, getRedeemParams(0, 0));
    }

    function test_RevertIf_oracleDeviation() public {
        address account = makeAddr("account");
        address reward = makeAddr("reward");
        uint256 maturity = maturities[0];
        uint256 vaultShares = enterVault(
            account, maxDeposit, maturity, getDepositParams(0, 0)
        );

        vm.prank(Deployments.NOTIONAL.owner());
        v().setStrategyVaultSettings(StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 0,
            numRewardTokens: 0,
            forceClaimAfter: 1 weeks
        }));

        // Oracle deviation checks only occur when we do valuation, so deposit
        // and redeem will go through even though the deviation is off.
        // vm.expectRevert(Errors.InvalidPrice.selector);
        vm.expectRevert();
        vault.convertStrategyToUnderlying(account, vaultShares, maturity);
        
        vm.prank(Deployments.NOTIONAL.owner());
        v().grantRole(REWARD_REINVESTMENT_ROLE, reward);

        vm.prank(reward);
        // vm.expectRevert(Errors.InvalidPrice.selector);
        vm.expectRevert();
        v().reinvestReward(new SingleSidedRewardTradeParams[](0), 0);
    }

    function test_RevertIf_NoAccessRewardReinvestment() public {
        address account = makeAddr("account");
        address reward = makeAddr("reward");
        uint256 maturity = maturities[0];
        enterVault(account, maxDeposit, maturity, getDepositParams(0, 0));

        vm.prank(reward);
        // Access control revert on role
        vm.expectRevert();
        // v().claimRewardTokens();

        vm.prank(reward);
        vm.expectRevert();
        v().reinvestReward(new SingleSidedRewardTradeParams[](0), 0);
    }

    function test_RevertIf_RewardReinvestmentTradesPoolTokens() public {
        address account = makeAddr("account");
        address reward = makeAddr("reward");
        uint256 maturity = maturities[0];
        enterVault(account, maxDeposit, maturity, getDepositParams(0, 0));

        vm.prank(Deployments.NOTIONAL.owner());
        v().grantRole(REWARD_REINVESTMENT_ROLE, reward);
        SingleSidedRewardTradeParams[] memory t = new SingleSidedRewardTradeParams[](numTokens);
        t[0].sellToken = address(metadata.rewardPool);

        vm.prank(reward);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidRewardToken.selector, address(metadata.rewardPool))
        );
        v().reinvestReward(t, 0);
    }

    function test_cannotReinitialize() public {
        bytes memory init = harness.getInitializeData();
        vm.prank(Deployments.NOTIONAL.owner());
        vm.expectRevert("Initializable: contract is already initialized");
        (address(vault).call(init));
    }

    function test_RevertIf_ReadOnlyReentrancyAttack() public {
        if (metadata.balancerPoolId == bytes32(0)) return;
        if (v().strategy() == bytes4(keccak256("BalancerComposableWrappedTwoToken"))) return;

        uint256 maturity = maturities[0];
        uint16 decimals = isETH ? 18 : primaryBorrowToken.decimals();

        BalancerAttacker balancerAttacker = new BalancerAttacker(
            Deployments.NOTIONAL,
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
            .getPoolTokens(metadata.balancerPoolId);

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

        bool isComposable = v().strategy() == bytes4(keccak256("BalancerComposableAuraVault"));
        uint256[] memory amountsWithoutBpt = new uint256[](isComposable ? tokens.length - 1 : tokens.length);
        uint256 j;
        for (uint256 i; i < amounts.length; i++) {
            if (tokens[i] != address(metadata.poolToken)) {
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
            metadata.balancerPoolId,
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