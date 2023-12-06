// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "../interfaces/WETH9.sol";
import "../interfaces/notional/NotionalProxy.sol";
import "../interfaces/notional/IStrategyVault.sol";
import "../interfaces/trading/ITradingModule.sol";
import {IERC20} from "../contracts/utils/TokenUtils.sol";
import "../contracts/global/Constants.sol";

abstract contract BaseAcceptanceTest is Test {
    WETH9 constant WETH = WETH9(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    NotionalProxy constant NOTIONAL = NotionalProxy(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    ITradingModule constant TRADING_MODULE = ITradingModule(0xBf6B9c5608D520469d8c4BD1E24F850497AF0Bb8);
    uint256 constant BASIS_POINT = 1e5;

    uint16 internal constant ENABLED                         = 1 << 0;
    uint16 internal constant ALLOW_ROLL_POSITION             = 1 << 1;
    uint16 internal constant ONLY_VAULT_ENTRY                = 1 << 2;
    uint16 internal constant ONLY_VAULT_EXIT                 = 1 << 3;
    uint16 internal constant ONLY_VAULT_ROLL                 = 1 << 4;
    uint16 internal constant ONLY_VAULT_DELEVERAGE           = 1 << 5;
    uint16 internal constant VAULT_MUST_SETTLE               = 1 << 6;
    uint16 internal constant ALLOW_REENTRANCY                = 1 << 7;
    uint16 internal constant DISABLE_DELEVERAGE              = 1 << 8;
    uint16 internal constant ENABLE_FCASH_DISCOUNT           = 1 << 9;

    uint16 constant ETH = 1;
    uint16 constant DAI = 2;
    uint16 constant USDC = 3;
    uint16 constant WBTC = 4;
    uint16 constant WSTETH = 5;
    uint16 constant FRAX = 6;
    uint16 constant RETH = 7;
    uint16 constant USDT = 8;
    uint16 constant CBETH = 9;
    uint16 constant GMX = 10;
    uint16 constant ARB = 11;
    uint16 constant RDNT = 12;

    string RPC_URL = vm.envString("RPC_URL");
    uint256 FORK_BLOCK = 147058900;
    IStrategyVault vault;
    VaultConfigParams config;
    uint256[] maturities;
    IERC20 primaryBorrowToken;
    uint256 precision;
    uint256 roundingPrecision;
    bool isETH;
    mapping(uint256 => uint256) totalVaultShares;
    uint256 totalVaultSharesAllMaturities;

    uint256 maxDeposit;
    uint256 minDeposit;
    uint256 maxRelEntryValuation;
    uint256 maxRelExitValuation;

    function setUp() public virtual {
        string memory profile = vm.envOr(string("FOUNDRY_PROFILE"), string("default"));
        if (keccak256(abi.encodePacked(profile)) != keccak256("default")) return;

        vm.createSelectFork(RPC_URL, FORK_BLOCK);

        config = getTestVaultConfig();
        MarketParameters[] memory m = NOTIONAL.getActiveMarkets(config.borrowCurrencyId);
        maturities = new uint256[](m.length + 1);
        maturities[0] = Constants.PRIME_CASH_VAULT_MATURITY;
        for (uint256 i; i < m.length; i++) maturities[i + 1] = m[i].maturity;

        vault = deployTestVault();
        vm.prank(NOTIONAL.owner());
        NOTIONAL.updateVault(address(vault), config, getMaxPrimaryBorrow());

        (/* */, Token memory underlyingToken) = NOTIONAL.getCurrency(config.borrowCurrencyId);
        primaryBorrowToken = IERC20(underlyingToken.tokenAddress);
        isETH = underlyingToken.tokenType == TokenType.Ether;
        uint16 decimals = isETH ? 18 : primaryBorrowToken.decimals();
        precision = uint256(underlyingToken.decimals);
        roundingPrecision = decimals > 8 ? 10 ** (decimals - 8) : 10 ** (8 - decimals);
    }

    function assertAbsDiff(uint256 a, uint256 b, uint256 diff, string memory m) internal {
        uint256 d = a > b ? a - b : b - a;
        assertLe(d, diff, m);
    }

    function assertRelDiff(uint256 a, uint256 b, uint256 rel, string memory m) internal {
        // Smaller number on top
        (uint256 top, uint256 bot) = a < b ? (a, b) : (b, a);
        uint256 r = (1e9 - top * 1e9 / bot);
        assertLe(r, rel, m);
    }

    function setTokenPermissions(
        address vault_,
        address token,
        ITradingModule.TokenPermissions memory permissions
    ) internal {
        vm.prank(NOTIONAL.owner());
        TRADING_MODULE.setTokenPermissions(vault_, token, permissions);
    }

    function getVaultName() internal pure virtual returns (string memory);
    function deployTestVault() internal virtual returns (IStrategyVault);
    function getTestVaultConfig() internal view virtual returns (VaultConfigParams memory);
    function getPrimaryVaultToken(uint256 /* maturity */) internal virtual returns (address) {
        return address(0);
    }
    function boundDepositAmount(uint256 depositAmount) internal view virtual returns (uint256) {
        return bound(depositAmount, minDeposit, maxDeposit);
    }


    // NOTE: no need to override this unless there is some specific test.
    function getMaxPrimaryBorrow() internal pure virtual returns (uint80) { return type(uint80).max; }
    function hook_beforeEnterVault(address account, uint256 maturity, uint256 depositAmount) internal virtual {}
    function hook_beforeExitVault(address account, uint256 maturity, uint256 depositAmount) internal virtual {}

    function getDepositParams(uint256 depositAmount, uint256 maturity) internal view virtual returns (bytes memory);
    function getRedeemParams(uint256 vaultShares, uint256 maturity) internal view virtual returns (bytes memory);
    function checkInvariants() internal virtual;

    function expectRevert_enterVaultBypass(
        address account,
        uint256 depositAmount,
        uint256 maturity,
        bytes memory data,
        bytes memory revertMsg
    ) internal virtual {
        if (isETH) {
            deal(address(vault), depositAmount);
        } else {
            deal(address(primaryBorrowToken), address(vault), depositAmount, false);
        }

        vm.prank(address(NOTIONAL));
        vm.expectRevert(revertMsg);
        vault.depositFromNotional(account, depositAmount, maturity, data);
    }

    function expectRevert_enterVaultBypass(
        address account,
        uint256 depositAmount,
        uint256 maturity,
        bytes memory data
    ) internal virtual {
        if (isETH) {
            deal(address(vault), depositAmount);
        } else {
            deal(address(primaryBorrowToken), address(vault), depositAmount, false);
        }

        vm.prank(address(NOTIONAL));
        vm.expectRevert();
        vault.depositFromNotional(account, depositAmount, maturity, data);
    }

    function expectRevert_enterVaultBypass(
        address account,
        uint256 depositAmount,
        uint256 maturity,
        bytes memory data,
        bytes4 selector
    ) internal virtual {
        if (isETH) {
            deal(address(vault), depositAmount);
        } else {
            deal(address(primaryBorrowToken), address(vault), depositAmount, false);
        }

        vm.prank(address(NOTIONAL));
        vm.expectRevert(selector);
        vault.depositFromNotional(account, depositAmount, maturity, data);
    }

    function enterVaultBypass(
        address account,
        uint256 depositAmount,
        uint256 maturity,
        bytes memory data
    ) internal virtual returns (uint256 vaultShares) {
        if (isETH) {
            deal(address(NOTIONAL), depositAmount);
        } else {
            deal(address(primaryBorrowToken), address(vault), depositAmount, false);
        }

        vm.prank(address(NOTIONAL));
        if (isETH) {
            vaultShares = vault.depositFromNotional{value: depositAmount}(account, depositAmount, maturity, data);
        } else {
            vaultShares = vault.depositFromNotional(account, depositAmount, maturity, data);
        }

        totalVaultShares[maturity] += vaultShares;
        totalVaultSharesAllMaturities += vaultShares;
    }

    function exitVaultBypass(
        address account,
        uint256 vaultShares,
        uint256 maturity,
        bytes memory data
    ) internal virtual returns (uint256 totalToReceiver) {
        vm.prank(address(NOTIONAL));
        totalToReceiver = vault.redeemFromNotional(account, account, vaultShares, maturity, 0, data);

        totalVaultShares[maturity] -= vaultShares;
        totalVaultSharesAllMaturities -= vaultShares;
    }

    function test_EnterVault(uint256 maturityIndex, uint256 depositAmount) public {
        address account = makeAddr("account");
        maturityIndex = bound(maturityIndex, 0, maturities.length - 1);
        uint256 maturity = maturities[maturityIndex];
        depositAmount = boundDepositAmount(depositAmount);

        hook_beforeEnterVault(account, maturity, depositAmount);
        uint256 vaultShares = enterVaultBypass(
            account,
            depositAmount,
            maturity,
            getDepositParams(maturity, depositAmount)
        );
        int256 valuationAfter = vault.convertStrategyToUnderlying(
            account, vaultShares, maturity
        );

        assertRelDiff(
            uint256(valuationAfter),
            depositAmount,
            maxRelEntryValuation,
            "Valuation and Deposit"
        );

        checkInvariants();
    }

    function test_ExitVault(uint256 maturityIndex, uint256 depositAmount) public {
        address account = makeAddr("account");
        maturityIndex = bound(maturityIndex, 0, maturities.length - 1);
        uint256 maturity = maturities[maturityIndex];
        depositAmount = boundDepositAmount(depositAmount);

        hook_beforeEnterVault(account, maturity, depositAmount);
        uint256 vaultShares = enterVaultBypass(
            account,
            depositAmount,
            maturity,
            getDepositParams(depositAmount, maturity)
        );

        vm.roll(5);
        vm.warp(block.timestamp + 3600);

        int256 valuationBefore = vault.convertStrategyToUnderlying(
            account, vaultShares, maturity
        );
        uint256 underlyingToReceiver = exitVaultBypass(
            account,
            vaultShares,
            maturity,
            getRedeemParams(depositAmount, maturity)
        );

        assertRelDiff(
            uint256(valuationBefore),
            underlyingToReceiver,
            maxRelExitValuation,
            "Valuation and Deposit"
        );

        checkInvariants();
    }

    function test_SettleVault() public {
        if (config.flags & VAULT_MUST_SETTLE != VAULT_MUST_SETTLE) return;
        address account = makeAddr("user");
        uint256 depositAmount = boundDepositAmount(type(uint256).max);

        // Can only use the 3 mo maturity to test this
        uint256 maturity = maturities[1];

        hook_beforeEnterVault(account, maturity, depositAmount);
        uint256 vaultShares = enterVaultBypass(
            account,
            depositAmount,
            maturity,
            getDepositParams(depositAmount, maturity)
        );

        vm.roll(5);
        vm.warp(maturity);
        for (uint16 i = 1; i <= USDT; i++) NOTIONAL.initializeMarkets(i, false);

        vm.prank(address(NOTIONAL));
        uint256 primeVaultShares = vault.convertVaultSharesToPrimeMaturity(
            account,
            vaultShares * 90 / 100,
            maturity
        );

        totalVaultShares[maturity] -= vaultShares * 90 / 100;
        totalVaultShares[Constants.PRIME_CASH_VAULT_MATURITY] += primeVaultShares;
        totalVaultSharesAllMaturities -= vaultShares * 90 / 100;
        totalVaultSharesAllMaturities += primeVaultShares;

        checkInvariants();
    }

    function test_VaultAuthentication() public {
        address account = makeAddr("account");
        vm.startPrank(makeAddr("random"));

        vm.expectRevert("Unauthorized");
        vault.depositFromNotional(account, 0.01e18, maturities[0], "");

        vm.expectRevert("Unauthorized");
        vault.redeemFromNotional(account, account, 0.01e18, maturities[0], 0, "");

        vm.expectRevert("Unauthorized");
        vault.convertVaultSharesToPrimeMaturity(account, 0.01e18, maturities[0]);
    }

    function test_DonationToVault_NoAffectValuation(uint256 maturityIndex) public {
        maturityIndex = bound(maturityIndex, 0, maturities.length - 1);
        uint256 maturity = maturities[maturityIndex];

        address vaultToken = getPrimaryVaultToken(maturity);
        if (vaultToken == address(0)) return;

        uint256 depositAmount = boundDepositAmount(type(uint256).max);
        address account = makeAddr("account");

        hook_beforeEnterVault(account, maturity, depositAmount);
        uint256 vaultShares = enterVaultBypass(
            account,
            depositAmount,
            maturity,
            getDepositParams(depositAmount, maturity)
        );

        int256 valuationBefore = vault.convertStrategyToUnderlying(
            account, vaultShares, maturity
        );

        deal(vaultToken, address(vault), 100 * 10 ** IERC20(vaultToken).decimals(), true);

        int256 valuationAfter = vault.convertStrategyToUnderlying(
            account, vaultShares, maturity
        );

        assertAbsDiff(
            uint256(valuationBefore),
            uint256(valuationAfter),
            roundingPrecision,
            "Valuation Change"
        );
    }

    function test_exchangeRateReturnsIfNoVaultShares() public {
        // Ensure that the exchange rate function always returns some
        // value even if there are no vault shares.
        require(totalVaultSharesAllMaturities == 0);
        for (uint256 i; i < maturities.length; i++) {
            int256 value = vault.getExchangeRate(maturities[i]);
            assertGt(value, 0);
        }
    }

}
