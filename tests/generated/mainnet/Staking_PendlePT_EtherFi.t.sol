// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../Staking/harness/index.sol";
import {WithdrawRequestNFT} from "@contracts/vaults/staking/protocols/EtherFi.sol";
import {
    PendleDepositParams,
    IPRouter,
    IPMarket
} from "@contracts/vaults/staking/protocols/PendlePrincipalToken.sol";
import {PendlePTOracle} from "@contracts/oracles/PendlePTOracle.sol";
import "@interfaces/chainlink/AggregatorV2V3Interface.sol";

contract Test_Staking_PendlePT_EtherFi is BaseStakingTest {
    uint256 expires;

    function setUp() public override {
        harness = new Harness_Staking_PendlePT_EtherFi();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.1e18;
        maxDeposit = 10e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;
        maxRelExitValuation_WithdrawRequest_Fixed = 0.03e18;
        maxRelExitValuation_WithdrawRequest_Variable = 0.005e18;
        deleverageCollateralDecreaseRatio = 925;
        defaultLiquidationDiscount = 955;
        withdrawLiquidationDiscount = 945;

        super.setUp();
        expires = IPMarket(PendleStakingHarness(address(harness)).marketAddress()).expiry();
    }

    function finalizeWithdrawRequest(address account) internal override {
        (WithdrawRequest memory f, WithdrawRequest memory w) = v().getWithdrawRequests(account);
        uint256 maxRequestId = f.requestId > w.requestId ? f.requestId : w.requestId;

        vm.prank(0x0EF8fa4760Db8f5Cd4d993f3e3416f30f942D705); // etherFi: admin
        WithdrawRequestNFT.finalizeRequests(maxRequestId);
    }

    function getDepositParams(
        uint256 /* depositAmount */,
        uint256 /* maturity */
    ) internal pure override returns (bytes memory) {
        PendleDepositParams memory d = PendleDepositParams({
            // No initial trading required for this vault
            dexId: 0,
            minPurchaseAmount: 0,
            exchangeData: "",
            minPtOut: 0,
            approxParams: IPRouter.ApproxParams({
                guessMin: 0,
                guessMax: type(uint256).max,
                guessOffchain: 0,
                maxIteration: 256,
                eps: 1e15 // recommended setting (0.1%)
            })
        });

        return abi.encode(d);
    }

    function test_RevertIf_accountEntry_postExpiry(uint8 maturityIndex) public {
        vm.warp(expires);
        address account = makeAddr("account");
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        uint256 maturity = maturities[maturityIndex];
        
        Deployments.NOTIONAL.initializeMarkets(harness.getTestVaultConfig().borrowCurrencyId, false);
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
        Deployments.NOTIONAL.initializeMarkets(harness.getTestVaultConfig().borrowCurrencyId, false);
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
    ) public {
        depositAmount = uint256(bound(depositAmount, minDeposit, maxDeposit));
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];

        uint256 vaultShares = enterVault(
            account, depositAmount, maturity, getDepositParams(depositAmount, maturity)
        );

        vm.warp(expires + 3600);
        Deployments.NOTIONAL.initializeMarkets(harness.getTestVaultConfig().borrowCurrencyId, false);
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
            v().initiateWithdraw(vaultShares);
        }
        finalizeWithdrawRequest(account);

        uint256 underlyingToReceiver = exitVault(
            account, vaultShares, maturity, getRedeemParams(true)
        );

        assertRelDiff(
            uint256(depositAmount),
            underlyingToReceiver,
            maxRelExitValuation,
            "Valuation and Deposit"
        );
    }

    function test_exitVault_hasWithdrawRequest_tradeShares_postExpiry(
        uint8 maturityIndex, uint256 depositAmount
    ) public {
        depositAmount = uint256(bound(depositAmount, minDeposit, maxDeposit));
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];

        uint256 vaultShares = enterVault(
            account, depositAmount, maturity, getDepositParams(depositAmount, maturity)
        );

        setMaxOracleFreshness();
        vm.warp(expires + 3600);
        Deployments.NOTIONAL.initializeMarkets(harness.getTestVaultConfig().borrowCurrencyId, false);
        if (maturity < block.timestamp) {
            // Push the vault shares to prime
            totalVaultShares[maturity] -= vaultShares;
            maturity = maturities[0];
            totalVaultShares[maturity] += vaultShares;
        }

        vm.prank(account);
        v().initiateWithdraw(vaultShares / 2);

        expectRevert_exitVault(
            account, vaultShares, maturity, getRedeemParams(depositAmount, maturity),
            "Insufficient Shares"
        );

        uint256 lendAmount = uint256(
            Deployments.NOTIONAL.getVaultAccount(account, address(vault)).accountDebtUnderlying * -1
        ) * 40 / 100;

        uint256 underlyingToReceiver = exitVault(
            account,
            vaultShares / 2, // Exits the other half of the shares
            maturity,
            lendAmount,
            getRedeemParams(depositAmount, maturity)
        );

        assertRelDiff(
            uint256(depositAmount),
            underlyingToReceiver,
            maxRelExitValuation,
            "Valuation and Deposit"
        );
    }
}

contract Harness_Staking_PendlePT_EtherFi is PendleStakingHarness {

    function getVaultName() public pure override returns (string memory) {
        return 'Pendle:PT ether.fi weETH 27JUN2024:[ETH]';
    }

    function getRequiredOracles() public override view returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // Custom PT Oracle
        token[0] = ptAddress;
        oracle[0] = ptOracle;

        // ETH
        token[1] = 0x0000000000000000000000000000000000000000;
        oracle[1] = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](1);
        permissions = new ITradingModule.TokenPermissions[](1);
        // weETH
        token[0] = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
        permissions[0] = ITradingModule.TokenPermissions(
            // UniswapV3, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 4, tradeTypeFlags: 5 }
        );
    }

    constructor() {
        marketAddress = 0xF32e58F92e60f4b0A37A69b95d642A471365EAe8;
        ptAddress = 0xc69Ad9baB1dEE23F4605a82b3354F8E40d1E5966;
        twapDuration = 15 minutes; // recommended 15 - 30 min
        useSyOracleRate = true; // returns the weETH price
        baseToUSDOracle = 0xE47F6c47DE1F1D93d8da32309D4dB90acDadeEaE;
    }

}
