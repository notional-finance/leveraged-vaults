// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./BaseStakingTest.t.sol";
import "./harness/PendleStakingHarness.sol";
import {IPMarket} from "@interfaces/pendle/IPendle.sol";

abstract contract BasePendleTest is BaseStakingTest {
    uint256 expires;

    function setUp() public override virtual {
        super.setUp();
        expires = IPMarket(PendleStakingHarness(address(harness)).marketAddress()).expiry();
    }

    function test_PendlePTOracle_getPrice_postExpiry() public {
        vm.warp(expires);
        setMaxOracleFreshness();

        // tokenOutSy to usd rate should be the expiry price
        (int256 tokenOutSyPrice, /* */) = Deployments.TRADING_MODULE.getOraclePrice(
            PendleStakingHarness(address(harness)).borrowToken(),
            PendleStakingHarness(address(harness)).tokenOutSy()
        );
        (int256 ptExpiryPrice, /* */) = Deployments.TRADING_MODULE.getOraclePrice(
            PendleStakingHarness(address(harness)).ptAddress(),
            PendleStakingHarness(address(harness)).tokenOutSy()
        );

        assertApproxEqRel(tokenOutSyPrice, ptExpiryPrice, 0.005e18, "tokenOutSyPrice should be the expiry price");
    }

    function test_RevertIf_accountEntry_postExpiry(uint8 maturityIndex) public {
        vm.warp(expires);
        address account = makeAddr("account");
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        uint256 maturity = maturities[maturityIndex];
        
        try Deployments.NOTIONAL.initializeMarkets(harness.getTestVaultConfig().borrowCurrencyId, false) {} catch {}
        if (maturity > block.timestamp) {
            expectRevert_enterVault(
                account, minDeposit, maturity, getDepositParams(minDeposit, maturity), "Expired"
            );
        }
    }

    function test_exitVault_postExpiry(uint8 maturityIndex, uint256 depositAmount) public {
        depositAmount = uint256(bound(depositAmount, minDeposit, maxDeposit));
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];

        uint256 vaultShares = enterVault(
            account, depositAmount, maturity, getDepositParams(depositAmount, maturity)
        );

        vm.warp(expires + 3600);
        try Deployments.NOTIONAL.initializeMarkets(harness.getTestVaultConfig().borrowCurrencyId, false) {} catch {}
        if (maturity < block.timestamp) {
            // Push the vault shares to prime
            totalVaultShares[maturity] -= vaultShares;
            maturity = maturities[0];
            totalVaultShares[maturity] += vaultShares;
        }

        uint256 underlyingToReceiver = exitVault(
            account,
            vaultShares,
            maturity < block.timestamp ? maturities[0] : maturity,
            getRedeemParams(depositAmount, maturity)
        );

        assertRelDiff(
            uint256(depositAmount),
            underlyingToReceiver,
            maxRelExitValuation,
            "Valuation and Deposit"
        );
    }

    function test_exitVault_useWithdrawRequest_postExpiry(
        uint8 maturityIndex, uint256 depositAmount, bool useForce
    ) public virtual {
        vm.skip(!hasWithdrawRequests());
        depositAmount = uint256(bound(depositAmount, minDeposit, maxDeposit));
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];

        uint256 vaultShares = enterVault(
            account, depositAmount, maturity, getDepositParams(depositAmount, maturity)
        );

        setMaxOracleFreshness();
        vm.warp(expires + 3600);
        try Deployments.NOTIONAL.initializeMarkets(harness.getTestVaultConfig().borrowCurrencyId, false) {} catch {}
        if (maturity < block.timestamp) {
            // Push the vault shares to prime
            totalVaultShares[maturity] -= vaultShares;
            maturity = maturities[0];
            totalVaultShares[maturity] += vaultShares;
        }

        if (useForce) {
            _forceWithdraw(account);
        } else {
            vm.prank(account);
            v().initiateWithdraw("");
        }
        finalizeWithdrawRequest(account);

        uint256 underlyingToReceiver = exitVault(
            account, vaultShares, maturity, getRedeemParamsWithdrawRequest(vaultShares, maturity)
        );

        assertRelDiff(
            uint256(depositAmount),
            underlyingToReceiver,
            maxRelExitValuation,
            "Valuation and Deposit"
        );
    }

}