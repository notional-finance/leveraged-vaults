// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "../interfaces/WETH9.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/notional/NotionalProxy.sol";
import "../interfaces/trading/ITradingModule.sol";

abstract contract BaseAcceptanceTest is Test {
    WETH9 constant WETH = WETH9(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    NotionalProxy constant NOTIONAL = NotionalProxy(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    ITradingModule constant TRADING_MODULE = ITradingModule(0xBf6B9c5608D520469d8c4BD1E24F850497AF0Bb8);

    string RPC_URL = vm.envString("ARBITRUM_RPC_URL");
    uint256 FORK_BLOCK = 133312145
    IStrategyVault vault;
    VaultConfigParams config;
    uint256[] memory maturities;
    IERC20 primaryBorrowToken;
    bool isETH;

    function setUp() public {
        vm.createSelectFork(RPC_URL, FORK_BLOCK);
        vault = deployVault();

        vm.prank(NOTIONAL.owner());
        config = getVaultConfig();
        NOTIONAL.updateVault(vault, config, getMaxPrimaryBorrow());

        MarketParameters[] memory m = NOTIONAL.getActiveMarkets(config.borrowCurrencyId)
        maturities = new uint256[](m.length + 1);
        maturities[0] = PRIME_CASH_VAULT_MATURITY;
        for (uint256 i; i < m.length; i++) maturities[i + 1] = m[i].maturity;

        (/* */, Token memory underlyingToken) = NOTIONAL.getCurrency(vaultConfig.primaryBorrowCurrency);
        primaryBorrowToken = IERC20(underlyingToken.tokenAddress);
        isETH = underlyingToken.tokenType == TokenType.Ether;
    }

    function deployVault() internal virtual return (IStrategyVault);
    function getVaultConfig() internal virtual return (VaultConfigParams memory);

    // NOTE: no need to override this unless there is some specific test.
    function getMaxPrimaryBorrow() internal virtual return (uint80) { return type(uint80).max; };

    // function getDepositParams() internal virtual return (bytes memory);
    // function getRedeemParams() internal virtual return (bytes memory);
    // function checkInvariants() internal virtual;

    // function enterVault(
    //     address account
    //     uint256 depositAmount,
    //     uint256 maturity
    // ) internal virtual returns (uint256 vaultShares) {
    //     vm.prank(NOTIONAL);
    //     deal(primaryBorrowToken, vault, depositAmount, true);
    //     return vault.depositFromNotional(account, depositAmount, maturity, getDepositParams());
    // }

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
