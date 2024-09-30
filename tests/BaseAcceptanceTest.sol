// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./StrategyVaultHarness.sol";
import "@deployments/Deployments.sol";
import "@interfaces/notional/NotionalProxy.sol";
import "@interfaces/notional/IStrategyVault.sol";
import "@interfaces/trading/ITradingModule.sol";
import {IERC20, TokenUtils} from "@contracts/utils/TokenUtils.sol";
import "@contracts/liquidator/FlashLiquidator.sol";
import "@contracts/global/Constants.sol";
import "@contracts/trading/TradingModule.sol";
import {VaultRewarderLib} from "@contracts/vaults/common/VaultRewarderLib.sol";

abstract contract BaseAcceptanceTest is Test {
    bytes32 internal constant EMERGENCY_EXIT_ROLE = keccak256("EMERGENCY_EXIT_ROLE");
    bytes32 internal constant REWARD_REINVESTMENT_ROLE = keccak256("REWARD_REINVESTMENT_ROLE");

    using TokenUtils for IERC20;
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


    string RPC_URL = vm.envString("RPC_URL");
    uint256 FORK_BLOCK = vm.envUint("FORK_BLOCK");
    IStrategyVault vault;
    StrategyVaultHarness harness;
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

    // Used for transferring tokens when `deal` does not work, like for USDC.
    address WHALE;
    bytes32 FOUNDRY_PROFILE;

    address flashLender;
    FlashLiquidator liquidator;

    function _deployVaultRewarderLib() internal {
        if (Deployments.CHAIN_ID == 42161 && 250810618 < FORK_BLOCK) return;
        if (Deployments.CHAIN_ID == 1 && 20773061 < FORK_BLOCK) return;

        // At lower fork blocks, need to deploy the new VaultRewarderLib
        deployCodeTo("VaultRewarderLib.sol", Deployments.VAULT_REWARDER_LIB);
    }

    function setUp() public virtual {
        vm.createSelectFork(RPC_URL, FORK_BLOCK);
        // NOTE: everything needs to run after create select fork
        _deployVaultRewarderLib();

        if (Deployments.CHAIN_ID == 1) {
            if (FORK_BLOCK < 20492800) vm.startPrank(0x22341fB5D92D3d801144aA5A925F401A91418A05);
            else vm.startPrank(Deployments.NOTIONAL.owner());

            address tradingModule = address(new TradingModule(Deployments.NOTIONAL, Deployments.TRADING_MODULE));
            // NOTE: fixes curve router
            UUPSUpgradeable(address(Deployments.TRADING_MODULE)).upgradeTo(tradingModule);
            vm.stopPrank();
        } else if (Deployments.CHAIN_ID == 42161) {
            vm.startPrank(Deployments.NOTIONAL.owner());
            address tradingModule = address(new TradingModule(Deployments.NOTIONAL, Deployments.TRADING_MODULE));
            // NOTE: fixes curve router
            UUPSUpgradeable(address(Deployments.TRADING_MODULE)).upgradeTo(tradingModule);
            vm.stopPrank();
        }

        config = harness.getTestVaultConfig();
        MarketParameters[] memory m = Deployments.NOTIONAL.getActiveMarkets(config.borrowCurrencyId);
        maturities = new uint256[](m.length + 1);
        maturities[0] = Constants.PRIME_CASH_VAULT_MATURITY;
        for (uint256 i; i < m.length; i++) maturities[i + 1] = m[i].maturity;

        vault = deployTestVault();

        vm.label(address(vault), "vault");
        vm.label(address(Deployments.NOTIONAL), "NOTIONAL");
        vm.prank(Deployments.NOTIONAL.owner());
        Deployments.NOTIONAL.updateVault(address(vault), config, getMaxPrimaryBorrow());

        (/* */, Token memory underlyingToken) = Deployments.NOTIONAL.getCurrency(config.borrowCurrencyId);
        primaryBorrowToken = IERC20(underlyingToken.tokenAddress);
        isETH = underlyingToken.tokenType == TokenType.Ether;
        uint16 decimals = isETH ? 18 : primaryBorrowToken.decimals();
        precision = uint256(underlyingToken.decimals);
        roundingPrecision = decimals > 8 ? 10 ** (decimals - 8) : 10 ** (8 - decimals);

        if (Deployments.CHAIN_ID == 1) {
            vm.startPrank(Deployments.NOTIONAL.owner());
        } else {
            vm.startPrank(Deployments.NOTIONAL.owner());
        }
        (
            address[] memory tokens,
            ITradingModule.TokenPermissions[] memory permissions
        ) = harness.getTradingPermissions();

        for (uint256 i; i < tokens.length; i++) {
            Deployments.TRADING_MODULE.setTokenPermissions(
                address(vault),
                tokens[i],
                permissions[i]
            );
        }
        vm.stopPrank();

        liquidator = new FlashLiquidator();
    }

    function setMaxOracleFreshness() internal {
        if (Deployments.CHAIN_ID == 1) {
            vm.prank(Deployments.NOTIONAL.owner());
        } else {
            vm.prank(Deployments.NOTIONAL.owner());
        }
        TradingModule(address(Deployments.TRADING_MODULE)).setMaxOracleFreshness(type(uint32).max);
    }

    function assertAbsDiff(uint256 a, uint256 b, uint256 diff, string memory m) internal {
        uint256 d = a > b ? a - b : b - a;
        assertLe(d, diff, m);
    }

    function assertRelDiff(uint256 a, uint256 b, uint256 rel, string memory m) internal {
        // Smaller number on top
        (uint256 top, uint256 bot) = a < b ? (a, b) : (b, a);
        uint256 r = (BASIS_POINT - top * BASIS_POINT / bot);
        assertLe(r, rel, m);
    }

    function _setOracleFreshness(uint32 freshness) internal {
        if (Deployments.CHAIN_ID == 1) {
            vm.prank(0x22341fB5D92D3d801144aA5A925F401A91418A05);
        } else {
            vm.prank(Deployments.NOTIONAL.owner());
        }
        TradingModule(address(Deployments.TRADING_MODULE)).setMaxOracleFreshness(freshness);
    }

    function setTokenPermissions(
        address vault_,
        address token,
        ITradingModule.TokenPermissions memory permissions
    ) internal {
        // mainnet trading module still didn't migrate to new NOTIONAL proxy address
        if (FOUNDRY_PROFILE == keccak256('mainnet') || Deployments.CHAIN_ID == 1) {
            vm.prank(Deployments.NOTIONAL.owner());
        } else {
            vm.prank(Deployments.NOTIONAL.owner());
        }
        Deployments.TRADING_MODULE.setTokenPermissions(vault_, token, permissions);
    }

    function deployTestVault() internal virtual returns (IStrategyVault);

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

    function setPriceOracle(address token, address oracle) public {
        if (Deployments.CHAIN_ID == 1) {
            vm.prank(Deployments.NOTIONAL.owner());
        } else {
            vm.prank(Deployments.NOTIONAL.owner());
        }
        Deployments.TRADING_MODULE.setPriceOracle(token, AggregatorV2V3Interface(oracle));
    }

    function dealTokensAndApproveNotional(uint256 depositAmount, address account) internal {
        if (isETH) {
            deal(account, depositAmount);
        } else if (WHALE != address(0)) {
            // USDC does not work with `deal` so transfer from a whale account instead.
            vm.prank(WHALE);
            primaryBorrowToken.transfer(account, depositAmount);
            vm.startPrank(account);
            primaryBorrowToken.checkApprove(address(Deployments.NOTIONAL), depositAmount);
            vm.stopPrank();
        } else {
            deal(address(primaryBorrowToken), account, depositAmount + primaryBorrowToken.balanceOf(account), true);
            vm.startPrank(account);
            primaryBorrowToken.checkApprove(address(Deployments.NOTIONAL), depositAmount);
            vm.stopPrank();
        }
    }

    function dealTokens(address to, uint256 depositAmount) internal {
        if (isETH) {
            deal(to, depositAmount);
        } else if (WHALE != address(0)) {
            // USDC does not work with `deal` so transfer from a whale account instead.
            vm.prank(WHALE);
            primaryBorrowToken.transfer(to, depositAmount);
        } else {
            deal(address(primaryBorrowToken), to, depositAmount, true);
        }
    }

    function _shouldSkip(string memory /* name */) internal virtual returns(bool) {
        return false;
    }

    function expectRevert_enterVaultBypass(
        address account,
        uint256 depositAmount,
        uint256 maturity,
        bytes memory data,
        bytes memory revertMsg
    ) internal virtual {
        dealTokens(isETH ? address(Deployments.NOTIONAL) : address(vault), depositAmount);

        vm.prank(address(Deployments.NOTIONAL));
        vm.expectRevert(revertMsg);
        if (isETH) {
            vault.depositFromNotional{value: depositAmount}(account, depositAmount, maturity, data);
        } else {
            vault.depositFromNotional(account, depositAmount, maturity, data);
        }
    }

    function expectRevert_enterVaultBypass(
        address account,
        uint256 depositAmount,
        uint256 maturity,
        bytes memory data
    ) internal virtual {
        dealTokens(isETH ? address(Deployments.NOTIONAL) : address(vault), depositAmount);

        vm.prank(address(Deployments.NOTIONAL));
        vm.expectRevert();
        if (isETH) {
            vault.depositFromNotional{value: depositAmount}(account, depositAmount, maturity, data);
        } else {
            vault.depositFromNotional(account, depositAmount, maturity, data);
        }
    }

    function expectRevert_enterVaultBypass(
        address account,
        uint256 depositAmount,
        uint256 maturity,
        bytes memory data,
        bytes4 selector
    ) internal virtual {
        dealTokens(isETH ? address(Deployments.NOTIONAL) : address(vault), depositAmount);

        vm.prank(address(Deployments.NOTIONAL));
        vm.expectRevert(selector);
        if (isETH) {
            vault.depositFromNotional{value: depositAmount}(account, depositAmount, maturity, data);
        } else {
            vault.depositFromNotional(account, depositAmount, maturity, data);
        }
    }

    function enterVaultBypass(
        address account,
        uint256 depositAmount,
        uint256 maturity,
        bytes memory data
    ) internal virtual returns (uint256 vaultShares) {
        dealTokens(isETH ? address(Deployments.NOTIONAL) : address(vault), depositAmount);

        vm.prank(address(Deployments.NOTIONAL));
        if (isETH) {
            vaultShares = vault.depositFromNotional{value: depositAmount}(account, depositAmount, maturity, data);
        } else {
            vaultShares = vault.depositFromNotional(account, depositAmount, maturity, data);
        }

        totalVaultShares[maturity] += vaultShares;
        totalVaultSharesAllMaturities += vaultShares;
    }

    function expectRevert_enterVault(
        address account,
        uint256 depositAmount,
        uint256 maturity,
        bytes memory data,
        bytes memory error
    ) internal virtual returns (uint256 vaultShares) {
        return _enterVault(account, depositAmount, maturity, data, true, error);
    }

    function enterVault(
        address account,
        uint256 depositAmount,
        uint256 maturity,
        bytes memory data
    ) internal virtual returns (uint256 vaultShares) {
        return _enterVault(account, depositAmount, maturity, data, false, "");
    }

    function _enterVault(
        address account,
        uint256 depositAmount,
        uint256 maturity,
        bytes memory data,
        bool expectRevert,
        bytes memory error
    ) private returns (uint256 vaultShares) {
        dealTokensAndApproveNotional(depositAmount, account);
        uint256 value;
        uint256 decimals;
        if (isETH) {
            value = depositAmount;
            decimals = 18;
        } else {
          decimals = primaryBorrowToken.decimals();
        }
        uint256 depositValueInternalPrecision =
            depositAmount * uint256(Constants.INTERNAL_TOKEN_PRECISION) / (10 ** decimals);
        vm.prank(account);
        if (expectRevert) vm.expectRevert(error);
        vaultShares = Deployments.NOTIONAL.enterVault{value: value}(
          account,
          address(vault),
          depositAmount,
          maturity,
          // TODO: change this to have configurable collateral ratios
          11 * depositValueInternalPrecision / 10,
          0,
          data
        );

        totalVaultShares[maturity] += vaultShares;
        totalVaultSharesAllMaturities += vaultShares;
    }

    function exitVaultBypass(
        address account,
        uint256 vaultShares,
        uint256 maturity,
        bytes memory data
    ) internal virtual returns (uint256 totalToReceiver) {
        vm.prank(address(Deployments.NOTIONAL));
        totalToReceiver = vault.redeemFromNotional(account, account, vaultShares, maturity, 0, data);

        totalVaultShares[maturity] -= vaultShares;
        totalVaultSharesAllMaturities -= vaultShares;
    }

    function expectRevert_exitVault(
        address account,
        uint256 vaultShares,
        uint256 maturity,
        bytes memory data,
        bytes memory error
    ) internal virtual returns (uint256 totalToReceiver) {
        uint256 lendAmount;
        if (maturity == type(uint40).max) {
          lendAmount = type(uint256).max;
        } else {
          lendAmount = uint256(
            Deployments.NOTIONAL.getVaultAccount(account, address(vault)).accountDebtUnderlying * -1
          );
        }
        return _exitVault(account, vaultShares, maturity, lendAmount, data, true, error);
    }

    function exitVault(
        address account,
        uint256 vaultShares,
        uint256 maturity,
        bytes memory data
    ) internal virtual returns (uint256 totalToReceiver) {
        uint256 lendAmount;
        if (maturity == type(uint40).max) {
          lendAmount = type(uint256).max;
        } else {
          lendAmount = uint256(
            Deployments.NOTIONAL.getVaultAccount(account, address(vault)).accountDebtUnderlying * -1
          );
        }
        return _exitVault(account, vaultShares, maturity, lendAmount, data, false, "");
    }

    function exitVault(
        address account,
        uint256 vaultShares,
        uint256 maturity,
        uint256 lendAmount,
        bytes memory data
    ) internal virtual returns (uint256 totalToReceiver) {
        return _exitVault(account, vaultShares, maturity, lendAmount, data, false, "");
    }

    function _exitVault(
        address account,
        uint256 vaultShares,
        uint256 maturity,
        uint256 lendAmount,
        bytes memory data,
        bool expectRevert,
        bytes memory error
    ) private returns (uint256 totalToReceiver) {
        if (expectRevert) vm.expectRevert(error);
        vm.prank(account);
        totalToReceiver = Deployments.NOTIONAL.exitVault(
          account,
          address(vault),
          account,
          vaultShares,
          lendAmount,
          0,
          data
        );
        if (!expectRevert) {
            totalVaultShares[maturity] -= vaultShares;
            totalVaultSharesAllMaturities -= vaultShares;
        }
    }

    function test_EnterVault(uint256 maturityIndex, uint256 depositAmount) public {
        address account = makeAddr("account");
        maturityIndex = bound(maturityIndex, 0, maturities.length - 1);
        uint256 maturity = maturities[maturityIndex];
        depositAmount = boundDepositAmount(depositAmount);

        hook_beforeEnterVault(account, maturity, depositAmount);
        uint256 vaultShares = enterVault(
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
        uint256 vaultShares = enterVault(
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
        uint256 underlyingToReceiver = exitVault(
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

    function test_EnterExitEnterVault(uint256 maturityIndex, uint256 depositAmount) public {
        vm.skip(_shouldSkip("test_EnterExitEnterVault"));
        address account = makeAddr("account");
        maturityIndex = bound(maturityIndex, 0, maturities.length - 1);
        uint256 maturity = maturities[maturityIndex];
        depositAmount = boundDepositAmount(depositAmount);

        hook_beforeEnterVault(account, maturity, depositAmount);
        uint256 vaultShares = enterVault(
            account,
            depositAmount,
            maturity,
            getDepositParams(depositAmount, maturity)
        );

        vm.warp(block.timestamp + 3600);

        exitVault(
            account,
            vaultShares,
            maturity,
            getRedeemParams(depositAmount, maturity)
        );


        vm.warp(block.timestamp + 3600);

        hook_beforeEnterVault(account, maturity, depositAmount);
        enterVault(
            account,
            depositAmount,
            maturity,
            getDepositParams(depositAmount, maturity)
        );
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
        for (uint16 i = 1; i <= Deployments.NOTIONAL.getMaxCurrencyId(); i++) {
            try Deployments.NOTIONAL.nTokenAddress(i) {
                Deployments.NOTIONAL.initializeMarkets(i, false);
            }  catch {}
        }

        vm.prank(address(Deployments.NOTIONAL));
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

        assertApproxEqAbs(
            uint256(valuationBefore),
            uint256(valuationAfter),
            // Slight rounding issues with cross currency vault due to clock issues perhaps
            roundingPrecision + roundingPrecision / 5,
            "Valuation Change"
        );
    }

    function test_exchangeRateReturnsIfNoVaultShares() public {
        // Ensure that the exchange rate function always returns some
        // value even if there are no vault shares.
        // NOTE: this is a NO-OP if the vault already has vault shares
        if (totalVaultSharesAllMaturities == 0) {
            for (uint256 i; i < maturities.length; i++) {
                int256 value = vault.getExchangeRate(maturities[i]);
                assertGt(value, 0);
            }
        }
    }

    /**** Liquidation Tests *****/

    function getLiquidationParams(address account) internal returns (
        FlashLiquidator.LiquidationParams memory params,
        address asset,
        int256 maxUnderlying
    ) {
        (/* */, maxUnderlying) = liquidator.getOptimalDeleveragingParams(
            account, address(vault)
        );
        VaultAccount memory va = Deployments.NOTIONAL.getVaultAccount(account, address(vault));

        (
            /* VaultAccountHealthFactors memory h */,
            /* int256[3] memory maxLiquidatorDepositUnderlying */,
            uint256[3] memory vaultSharesToLiquidator
        ) = Deployments.NOTIONAL.getVaultAccountHealthFactors(account, address(vault));

        bytes memory redeem = getRedeemParams(vaultSharesToLiquidator[0], va.maturity);
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        params = FlashLiquidator.LiquidationParams({
            liquidationType: FlashLiquidator.LiquidationType.DELEVERAGE_VAULT_ACCOUNT,
            currencyId: config.borrowCurrencyId,
            currencyIndex: 0,
            accounts: accounts,
            vault: address(vault),
            redeemData: redeem
        });

        (/* */, Token memory t) = Deployments.NOTIONAL.getCurrency(config.borrowCurrencyId);
        asset =  t.tokenAddress == address(0) ? address(Deployments.WETH) : t.tokenAddress;
    }


    function enterVaultLiquidation(address account, uint256 maturity) internal returns (uint256) {
        VaultConfig memory c = Deployments.NOTIONAL.getVaultConfig(address(vault));
        uint256 cr = uint256(c.minCollateralRatio) + 10 * maxRelEntryValuation;
        return enterVaultLiquidation(account, maturity, cr);
    }

    function enterVaultLiquidation(address account, uint256 maturity, uint256 collateralRatio) internal returns (uint256) {
        VaultConfig memory c = Deployments.NOTIONAL.getVaultConfig(address(vault));
        uint256 depositAmountExternal = uint256(c.minAccountBorrowSize) * precision / 1e8;
        return enterVaultLiquidation(account, maturity, collateralRatio, depositAmountExternal);
    }

    function enterVaultLiquidation(address account, uint256 maturity, uint256 collateralRatio, uint256 depositAmountExternal) internal returns (uint256) {
        uint256 borrowAmountExternal;
        uint256 borrowAmount;
        bytes memory depositParams;
        {
            depositParams = getDepositParams(depositAmountExternal, maturity);
            VaultConfig memory c = Deployments.NOTIONAL.getVaultConfig(address(vault));
            borrowAmountExternal = depositAmountExternal * 1e9 / collateralRatio;

            if (maturity == Constants.PRIME_CASH_VAULT_MATURITY) {
                borrowAmount = borrowAmountExternal * 1e8 / precision;
            } else {
                // Calculate the fCash amount because of slippage
                (borrowAmount, /* */, /* */) = Deployments.NOTIONAL.getfCashBorrowFromPrincipal(
                    c.borrowCurrencyId,
                    borrowAmountExternal,
                    maturity,
                    0,
                    block.timestamp,
                    true
                );
                // Add slippage into the deposit to maintain the collateral ratio
                depositAmountExternal = depositAmountExternal + (borrowAmount * precision / 1e8 - borrowAmountExternal);
            }
        }

        dealTokens(account, depositAmountExternal);
        vm.startPrank(account);
        if (!isETH) {
            primaryBorrowToken.checkApprove(address(Deployments.NOTIONAL), type(uint256).max);
        }

        uint256 vaultShares = Deployments.NOTIONAL.enterVault{value: isETH ? depositAmountExternal : 0}(
            account, address(vault), depositAmountExternal, maturity, borrowAmount, 0, depositParams
        );
        vm.stopPrank();

        return vaultShares;
    }

    function _changeCollateralRatio() internal virtual {
        VaultConfigParams memory cp = config;
        cp.minCollateralRatioBPS = cp.minCollateralRatioBPS + cp.minCollateralRatioBPS / 2;
        cp.maxDeleverageCollateralRatioBPS = cp.minCollateralRatioBPS + 500;
        vm.startPrank(Deployments.NOTIONAL.owner());
        Deployments.NOTIONAL.updateVault(address(vault), cp, getMaxPrimaryBorrow());
        vm.stopPrank();
    }

    function test_RevertIf_VaultAccountCollateralized(uint256 maturityIndex) public {
        address account = makeAddr("account");
        maturityIndex = bound(maturityIndex, 0, maturities.length - 1);
        uint256 maturity = maturities[maturityIndex];

        enterVaultLiquidation(account, maturity);
        (
            FlashLiquidator.LiquidationParams memory params,
            address asset,
            int256 maxUnderlying
        ) = getLiquidationParams(account);
        assertEq(maxUnderlying, 0, "Under Collateralized");

        vm.expectRevert();
        _flashLiquidate(
            asset,
            // This number does not really matter
            uint256(100e8) * precision / 1e8 + roundingPrecision,
            params
        );
    }

    function test_deleverageBatch(uint256 maturityIndex) public {
        address[] memory accounts = new address[](3);
        accounts[0] = makeAddr("account1");
        accounts[1] = makeAddr("account2");
        accounts[2] = makeAddr("account3");
        maturityIndex = bound(maturityIndex, 0, maturities.length - 1);
        uint256 maturity = maturities[maturityIndex];
        // All the accounts have to be in the same maturity
        enterVaultLiquidation(accounts[0], maturity);
        // Test that the liquidator will not fail if one of the accounts is empty or
        // has sufficient collateral
        enterVaultLiquidation(accounts[2], maturity);

        _changeCollateralRatio();
        (
            FlashLiquidator.LiquidationParams memory params,
            address asset,
            int256 maxUnderlying1
        ) = getLiquidationParams(accounts[0]);
        (,,int256 maxUnderlying2) = getLiquidationParams(accounts[1]);
        (,,int256 maxUnderlying3) = getLiquidationParams(accounts[2]);
        params.accounts = accounts;
        uint256 totalFlash = uint256(maxUnderlying1 + maxUnderlying2 + maxUnderlying3);

        _flashLiquidate(
            asset,
            totalFlash * precision / 1e8 + roundingPrecision,
            params
        );

        // Check that all accounts were liquidated
        int256 x;
        (/* */, x) = liquidator.getOptimalDeleveragingParams(accounts[0], address(vault));
        assertEq(x, 0);
        (/* */, x) = liquidator.getOptimalDeleveragingParams(accounts[1], address(vault));
        assertEq(x, 0);
        (/* */, x) = liquidator.getOptimalDeleveragingParams(accounts[2], address(vault));
        assertEq(x, 0);
    }

    function test_deleverageVariableFixed_cashPurchase(uint256 maturityIndex) public {
        address account = makeAddr("account");
        maturityIndex = bound(maturityIndex, 0, maturities.length - 1);
        uint256 maturity = maturities[maturityIndex];
        enterVaultLiquidation(account, maturity);

        // Increases the collateral ratio for liquidation
        _changeCollateralRatio();

        (
            FlashLiquidator.LiquidationParams memory params,
            address asset,
            int256 maxUnderlying
        ) = getLiquidationParams(account);
        assertGt(maxUnderlying, 0, "Not Under Collateralized");

        _flashLiquidate(
            asset,
            uint256(maxUnderlying) * precision / 1e8 + 2 * roundingPrecision,
            params
        );
        VaultAccount memory va = Deployments.NOTIONAL.getVaultAccount(account, address(vault));

        // Assert liquidation was a success
        (/* */, maxUnderlying) = liquidator.getOptimalDeleveragingParams(
            account, address(vault)
        );
        assertEq(maxUnderlying, 0, "Zero Deposit");
        if (maturityIndex == 0) {
            assertEq(va.tempCashBalance, 0, "Cash Balance");
        } else {
            assertGt(va.tempCashBalance, 0, "Cash Balance");
        }

        // On lower precisions the minimum required cash balance is higher or else the liquidation
        // will not generate enough profit to repay the flash loan
        int256 minTempCashBalance = precision < 1e18 ? int256(125e5) : int256(100e5);
        if (minTempCashBalance < va.tempCashBalance) {
            va = Deployments.NOTIONAL.getVaultAccount(account, address(vault));
            params.liquidationType = FlashLiquidator.LiquidationType.LIQUIDATE_CASH_BALANCE;
            params.redeemData = "";

            (int256 fCashDeposit, /* */) = Deployments.NOTIONAL.getfCashRequiredToLiquidateCash(
                params.currencyId, va.maturity, va.tempCashBalance
            );
            int256 maxFCashDeposit = -1 * va.accountDebtUnderlying;
            fCashDeposit = maxFCashDeposit < fCashDeposit ?  maxFCashDeposit : fCashDeposit;

            _flashLiquidate(
                asset,
                uint256(fCashDeposit) * precision / 1e8 + roundingPrecision,
                params
            );

            VaultAccount memory vaAfter = Deployments.NOTIONAL.getVaultAccount(account, address(vault));
            assertGt(vaAfter.accountDebtUnderlying, va.accountDebtUnderlying, "Debt Decrease");
            assertLt(vaAfter.tempCashBalance, minTempCashBalance, "Cash Balance");
        }
    }

    function _flashLiquidate(address asset, uint256 amount, FlashLiquidator.LiquidationParams memory params) private {
        address lender = flashLender == address(0) ? Deployments.FLASH_LENDER_AAVE : flashLender;
        if (asset == 0xdAC17F958D2ee523a2206206994597C13D831ec7 && block.chainid == 1) {
            // USDT approvals are broken on mainnet for the Aave flash lender
            lender = 0x9E092cb431e5F1aa70e47e052773711d2Ba4917E;
        }
        liquidator.flashLiquidate(
            lender,
            asset,
            amount,
            params
        );
    }

    function test_deleverageVariableBorrow_accruedFees() public {
        // ezETH fails when we warp ahead because it has an internal oracle timeout check
        if (keccak256(abi.encodePacked(vault.name())) == keccak256(abi.encodePacked("SingleSidedLP:Aura:ezETH/[WETH]"))) return;
        address account = makeAddr("account");
        enterVaultLiquidation(account, maturities[0]);

        // Increases the collateral ratio for liquidation
        _changeCollateralRatio();

        skip(30 days);
        setMaxOracleFreshness();

        (
            FlashLiquidator.LiquidationParams memory params,
            address asset,
            int256 maxUnderlying
        ) = getLiquidationParams(account);
        assertGt(maxUnderlying, 0, "Not Under Collateralized");

        _flashLiquidate(
            asset,
            uint256(maxUnderlying) * precision / 1e8 + roundingPrecision,
            params
        );
        VaultAccount memory va = Deployments.NOTIONAL.getVaultAccount(account, address(vault));

        // Assert liquidation was a success
        (/* */, maxUnderlying) = liquidator.getOptimalDeleveragingParams(
            account, address(vault)
        );
        assertEq(maxUnderlying, 0, "Zero Deposit");
        assertEq(va.tempCashBalance, 0, "Cash Balance");
    }

}