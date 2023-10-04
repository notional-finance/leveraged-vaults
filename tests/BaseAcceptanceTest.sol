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

    string RPC_URL = vm.envString("RPC_URL");
    uint256 FORK_BLOCK = 137439907;
    IStrategyVault vault;
    VaultConfigParams config;
    uint256[] maturities;
    IERC20 primaryBorrowToken;
    bool isETH;

    function setUp() public virtual {
        vm.createSelectFork(RPC_URL, FORK_BLOCK);
        vault = deployVault();

        vm.prank(NOTIONAL.owner());
        config = getVaultConfig();
        NOTIONAL.updateVault(address(vault), config, getMaxPrimaryBorrow());

        MarketParameters[] memory m = NOTIONAL.getActiveMarkets(config.borrowCurrencyId);
        maturities = new uint256[](m.length + 1);
        maturities[0] = Constants.PRIME_CASH_VAULT_MATURITY;
        for (uint256 i; i < m.length; i++) maturities[i + 1] = m[i].maturity;

        (/* */, Token memory underlyingToken) = NOTIONAL.getCurrency(config.borrowCurrencyId);
        primaryBorrowToken = IERC20(underlyingToken.tokenAddress);
        isETH = underlyingToken.tokenType == TokenType.Ether;
    }

    function deployVault() internal virtual returns (IStrategyVault);
    function getVaultConfig() internal pure virtual returns (VaultConfigParams memory);

    // NOTE: no need to override this unless there is some specific test.
    function getMaxPrimaryBorrow() internal pure virtual returns (uint80) { return type(uint80).max; }

    function getDepositParams(uint256 depositAmount, uint256 maturity) internal view virtual returns (bytes memory);
    // function getRedeemParams() internal virtual returns (bytes memory);
    // function checkInvariants() internal virtual;

    function enterVaultBypass(
        address account,
        uint256 depositAmount,
        uint256 maturity
    ) internal virtual returns (uint256 vaultShares) {
        if (isETH) {
            deal(address(vault), depositAmount);
        } else {
            deal(address(primaryBorrowToken), address(vault), depositAmount, true);
        }
        vm.prank(address(NOTIONAL));
        return vault.depositFromNotional(
            account,
            depositAmount,
            maturity,
            getDepositParams(depositAmount, maturity)
        );
    }

    // function test_DonationToVault_NoAffectValuation(
    //     uint256 depositAmount,
    //     uint256 maturity
    // ) public virtual {
    //     address acct = makeAddr("account");
    //     enterVault(acct, depositAmount, maturity);
    //     uint256 valuationBefore = vault.convertStrategyToUnderlying(
    //         acct, vaultShares, maturity
    //     );

    //     deal(primaryVaultToken, vault, donationAmount, true);
    //     uint256 valuationAfter = vault.convertStrategyToUnderlying(
    //         acct, vaultShares, maturity
    //     );

    //     assertEq(valuationBefore, valuationAfter);

    //     checkInvariants();
    // }

    // function test_EnterVault(
    //     address account,
    //     uint256 depositAmount,
    //     uint256 maturity
    // ) public virtual {
    //     uint256 valuationBefore = vault.convertStrategyToUnderlying(
    //         acct, vaultShares, maturity
    //     );
    //     enterVault(account, depositAmount, maturity);
    //     uint256 valuationAfter = vault.convertStrategyToUnderlying(
    //         acct, vaultShares, maturity
    //     );
    //     assertEq(valuationBefore, valuationAfter);

    //     checkInvariants();
    // }

    // function test_ExitVault() public virtual {
    //     uint256 vaultShares = enterVault(account, depositAmount, maturity);

    //     vm.roll(5);
    //     vm.warp(3600);

    //     uint256 valuationBefore = vault.convertStrategyToUnderlying(
    //         acct, vaultShares, maturity
    //     );
    //     redeemVault(account, depositAmount, maturity);
    //     uint256 valuationAfter = vault.convertStrategyToUnderlying(
    //         acct, vaultShares, maturity
    //     );
    //     assertEq(valuationBefore, valuationAfter);

    //     checkInvariants();
    // }

    // function test_RollVault() public virtual {}
    // function test_MatureVault_Enter() public virtual {}
    // function test_MatureVault_Exit() public virtual {}
    // function test_MatureVault_Roll() public virtual {}

    // function test_EmergencyExit() public virtual {}
    // function test_RevertIf_EnterWhenLocked() public virtual {}
    // function test_RevertIf_ExitWhenLocked() public virtual {}
}
