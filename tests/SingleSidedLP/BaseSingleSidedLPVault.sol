// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../BaseAcceptanceTest.sol";
import "../../scripts/deploy/DeployProxyVault.sol";
import "../../contracts/vaults/common/SingleSidedLPVaultBase.sol";
import "../../contracts/proxy/nProxy.sol";
import "../../interfaces/notional/ISingleSidedLPStrategyVault.sol";
import "../../interfaces/trading/ITradingModule.sol";

abstract contract BaseSingleSidedLPVault is DeployProxyVault, BaseAcceptanceTest {
    bytes32 internal constant EMERGENCY_EXIT_ROLE = keccak256("EMERGENCY_EXIT_ROLE");
    bytes32 internal constant REWARD_REINVESTMENT_ROLE = keccak256("REWARD_REINVESTMENT_ROLE");

    uint16 primaryBorrowCurrency;
    StrategyVaultSettings settings;
    uint256 numTokens;
    IERC20 rewardPool;
    IERC20 poolToken;
    IERC20 rewardToken;
    address whitelistedReward;

    function getInitializeData() internal view override returns (bytes memory initData) {
        return abi.encodeWithSelector(
            ISingleSidedLPStrategyVault.initialize.selector, InitParams({
                name: getVaultName(),
                borrowCurrencyId: primaryBorrowCurrency,
                settings: settings
            })
        );
    }

    function deployTestVault() internal override returns (IStrategyVault) {
        address impl = deployVaultImplementation();
        bytes memory initData = getInitializeData();

        (IERC20[] memory tokens, /* */) = SingleSidedLPVaultBase(payable(address(impl))).TOKENS();
        numTokens = tokens.length;

        vm.prank(NOTIONAL.owner());
        nProxy proxy = new nProxy(address(impl), initData);

        // NOTE: no token permissions set, single sided join by default
        return IStrategyVault(address(proxy));
    }

    function getTestVaultConfig() internal view override returns (VaultConfigParams memory p) {
        p.flags = ENABLED | ONLY_VAULT_DELEVERAGE | ALLOW_ROLL_POSITION;
        p.borrowCurrencyId = primaryBorrowCurrency;
        p.minAccountBorrowSize = 0.01e8;
        p.minCollateralRatioBPS = 5000;
        p.feeRate5BPS = 5;
        p.liquidationRate = 102;
        p.reserveFeeShare = 80;
        p.maxBorrowMarketIndex = 2;
        p.maxDeleverageCollateralRatioBPS = 7000;
        p.maxRequiredAccountCollateralRatioBPS = 10000;
        p.excessCashLiquidationBonus = 100;
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
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 1,
            oraclePriceDeviationLimitPercent: 50
        }));

        vm.expectRevert("Unauthorized");
        v().upgradeTo(address(0));

        vm.expectRevert("Initializable: contract is already initialized");
        StrategyVaultSettings memory s;
        v().initialize(InitParams("Vault", primaryBorrowCurrency, s));

        vm.expectRevert(Errors.VaultNotLocked.selector);
        v().tradeTokensBeforeRestore(new SingleSidedRewardTradeParams[](0));
    }

    function test_RevertIf_joinAboveMaxPoolShare() public {
        address account = makeAddr("account");
        uint256 maturity = maturities[0];

        vm.prank(NOTIONAL.owner());
        v().setStrategyVaultSettings(StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 1,
            oraclePriceDeviationLimitPercent: 50
        }));

        
        expectRevert_enterVaultBypass(
            account, 100_000e18, maturity, getDepositParams(0, 0)
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
        uint256 vaultShares = enterVaultBypass(
            account, maxDeposit, maturity, getDepositParams(0, 0)
        );

        // Fill all the redeem params with values above the deposit
        RedeemParams memory d;
        d.minAmounts = new uint256[](numTokens);
        for (uint256 i; i < d.minAmounts.length; i++) d.minAmounts[i] = maxDeposit * 2;

        vm.expectRevert();
        exitVaultBypass(account, vaultShares, maturity, abi.encode(d));
    }

    function test_RevertIf_NoAccessEmergencyExit() public {
        address account = makeAddr("account");
        address exit = makeAddr("exit");
        uint256 maturity = maturities[0];
        enterVaultBypass(account, maxDeposit, maturity, getDepositParams(0, 0));

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
        enterVaultBypass(
            account, maxDeposit, maturity, getDepositParams(0, 0)
        );

        vm.prank(NOTIONAL.owner());
        v().grantRole(EMERGENCY_EXIT_ROLE, exit);

        initialBalance = rewardPool.balanceOf(address(vault));
        assertGt(initialBalance, 0);
        (IERC20[] memory tokens, /* */) = v().TOKENS();
        for (uint256 i; i < tokens.length; i++) {
            if (address(tokens[i]) == address(0)) {
                assertEq(address(vault).balance, 0);
            } else if (tokens[i] != poolToken) {
                assertEq(tokens[i].balanceOf(address(vault)), 0);
            }
        }

        vm.prank(exit);
        v().emergencyExit(0, "");

        exitBalances = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; i++) {
            if (address(tokens[i]) == address(0)) {
                exitBalances[i] = address(vault).balance;
                assertGt(exitBalances[i], 0);
            } else if (tokens[i] != poolToken) {
                exitBalances[i] = tokens[i].balanceOf(address(vault));
                assertGt(exitBalances[i], 0);
            }
        }
    }

    function test_EmergencyExit_LocksVault() public {
        address account = makeAddr("account");
        uint256 maturity = maturities[0];
        (uint256[] memory exitBalances, address exit, /* */) = setup_EmergencyExit();

        assertEq(rewardPool.balanceOf(address(vault)), 0);
        assertEq(poolToken.balanceOf(address(vault)), 0);
        assertEq(v().isLocked(), true);

        // Assert that these methods revert due to locking
        expectRevert_enterVaultBypass(
            account, maxDeposit, maturity, getDepositParams(0, 0),
            Errors.VaultLocked.selector
        );

        vm.expectRevert(Errors.VaultLocked.selector);
        // 0.01e8 is an intentionally small number here to avoid underflows in
        // the test code, we expect a revert no matter what
        exitVaultBypass(account, 0.01e8, maturity, getRedeemParams(0, 0));

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
        address account = makeAddr("account");
        uint256 maturity = maturities[0];
        (uint256[] memory exitBalances, /* */, uint256 initialBalance) = setup_EmergencyExit();

        // Restore the vault
        vm.prank(NOTIONAL.owner());
        v().restoreVault(0, abi.encode(exitBalances));

        (IERC20[] memory tokens, /* */) = v().TOKENS();
        // All token balances should be cleared.
        for (uint256 i; i < tokens.length; i++) {
            if (address(tokens[i]) == address(0)) {
                assertEq(address(vault).balance, 0, "eth balance");
            } else if (tokens[i] != poolToken) {
                assertEq(tokens[i].balanceOf(address(vault)), 0, "token balance");
            }
        }
        uint256 postRestore = rewardPool.balanceOf(address(vault));
        assertRelDiff(initialBalance, postRestore, 0.0001e9, "Restore Balance");
        assertEq(v().isLocked(), false);

        // All of these calls should succeed
        uint256 vaultShares = enterVaultBypass(account, maxDeposit * 2, maturity, getDepositParams(0, 0));
        vault.convertStrategyToUnderlying(account, vaultShares, maturity);
        // NOTE: the exitVaultBypass above causes an underflow inside exitVaultBypass
        // here because the vault shares are removed from the test accounting even though
        // the call reverts earlier.
        exitVaultBypass(account, vaultShares, maturity, getRedeemParams(0, 0));
    }

    function test_RevertIf_oracleDeviation() public {
        address account = makeAddr("account");
        address reward = makeAddr("reward");
        uint256 maturity = maturities[0];
        uint256 vaultShares = enterVaultBypass(
            account, maxDeposit, maturity, getDepositParams(0, 0)
        );

        vm.prank(NOTIONAL.owner());
        v().setStrategyVaultSettings(StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 1
        }));

        // Oracle deviation checks only occur when we do valuation, so deposit
        // and redeem will go through even though the deviation is off.
        // vm.expectRevert(Errors.InvalidPrice.selector);
        vm.expectRevert();
        vault.convertStrategyToUnderlying(account, vaultShares, maturity);
        
        vm.prank(NOTIONAL.owner());
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
        enterVaultBypass(account, maxDeposit, maturity, getDepositParams(0, 0));

        vm.prank(reward);
        // Access control revert on role
        vm.expectRevert();
        v().claimRewardTokens();

        vm.prank(reward);
        vm.expectRevert();
        v().reinvestReward(new SingleSidedRewardTradeParams[](0), 0);
    }

    function test_RewardReinvestmentClaimTokens() public {
        address account = makeAddr("account");
        address reward = makeAddr("reward");
        uint256 maturity = maturities[0];
        enterVaultBypass(account, maxDeposit, maturity, getDepositParams(0, 0));

        vm.prank(NOTIONAL.owner());
        v().grantRole(REWARD_REINVESTMENT_ROLE, reward);

        skip(3600);
        assertEq(rewardToken.balanceOf(address(vault)), 0);
        vm.prank(reward);
        v().claimRewardTokens();
        uint256 rewardBalance = rewardToken.balanceOf(address(vault));
        assertGe(rewardBalance, 0);
    }

    function test_RevertIf_RewardReinvestmentTradesPoolTokens() public {
        address account = makeAddr("account");
        address reward = makeAddr("reward");
        uint256 maturity = maturities[0];
        enterVaultBypass(account, maxDeposit, maturity, getDepositParams(0, 0));

        vm.prank(NOTIONAL.owner());
        v().grantRole(REWARD_REINVESTMENT_ROLE, reward);
        SingleSidedRewardTradeParams[] memory t = new SingleSidedRewardTradeParams[](numTokens);
        t[0].sellToken = address(rewardPool);

        vm.prank(reward);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidRewardToken.selector, address(rewardPool))
        );
        v().reinvestReward(t, 0);
    }

    // todo: re-entrancy detection and deleverage...
}