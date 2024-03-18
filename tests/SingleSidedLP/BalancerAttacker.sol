// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {NotionalProxy} from "@interfaces/notional/NotionalProxy.sol";
import {IStrategyVault} from "@interfaces/notional/IStrategyVault.sol";
import {VaultAccount} from "@contracts/global/Types.sol";
import {Constants} from "@contracts/global/Constants.sol";
import {IERC20} from "@interfaces/IERC20.sol";

contract BalancerAttacker is Test {
    NotionalProxy immutable NOTIONAL;

    address vault;
    uint256 depositAmountExternal;
    uint256 maturity;
    address primaryBorrowToken;
    bytes redeemParams;
    bytes depositParams;
    bool isETH;
    uint16 decimals;
    address WHALE;

    bool public called;

    constructor(
        NotionalProxy _notional,
        address _vault,
        uint256 _depositAmountExternal,
        uint256 _maturity,
        address _primaryBorrowToken,
        bytes memory _redeemParams,
        bytes memory _depositParams,
        address _WHALE
    ) {
        NOTIONAL = _notional;
        WHALE = _WHALE;
        vault = _vault;
        depositAmountExternal = _depositAmountExternal;
        maturity = _maturity;
        primaryBorrowToken = _primaryBorrowToken;
        redeemParams = _redeemParams;
        depositParams = _depositParams;

        isETH = primaryBorrowToken == address(0);

        decimals = isETH ? 18 : IERC20(primaryBorrowToken).decimals();
    }


    receive() payable external {
        called = true;
        address account = address(this);

        _enterVault({expectRevert: true});

        vm.expectRevert();
        NOTIONAL.deleverageAccount(account, vault, account, 0, 0);

        vm.expectRevert("BAL#400"); // Code: 400 - REENTRANCY
        IStrategyVault(vault).deleverageAccount(account, vault, account, 0, 0);

        VaultAccount memory vaultAccount = NOTIONAL.getVaultAccount(account, vault);
        vm.expectRevert("BAL#400"); // Code: 400 - REENTRANCY
        NOTIONAL.exitVault(account, vault, account, vaultAccount.vaultShares, type(uint256).max, 0, redeemParams);

    }

    function prepareForAttack() public {
        _enterVault(false);
        skip(1 minutes);
    }

    function _enterVault(bool expectRevert) private {
        address account = address(this);
        uint256 value;
        if (isETH) {
            deal(account, depositAmountExternal);
            value = depositAmountExternal;
        } else {
            if (WHALE != address(0)) {
                // USDC does not work with `deal` so transfer from a whale account instead.
                vm.prank(WHALE);
                IERC20(primaryBorrowToken).transfer(address(account), depositAmountExternal);
            } else {
                deal(address(primaryBorrowToken), address(account), depositAmountExternal, true);
            }
            IERC20(primaryBorrowToken).approve(address(NOTIONAL), depositAmountExternal);
        }

        uint256 depositValueInternalPrecision =
            depositAmountExternal * uint256(Constants.INTERNAL_TOKEN_PRECISION) / (10 ** decimals);

        if (expectRevert) vm.expectRevert("BAL#400"); // Code: 400 - REENTRANCY
        NOTIONAL.enterVault{value: value}({
            account: account,
            vault: address(vault),
            depositAmountExternal: depositAmountExternal,
            maturity: maturity,
            // borrow 110% of deposited value
            fCash: 11 * depositValueInternalPrecision / 10,
            maxBorrowRate: 50,
            vaultData: depositParams
        });
    }

}
