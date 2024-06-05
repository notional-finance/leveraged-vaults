// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../Staking/harness/index.sol";
import {
    PendleDepositParams,
    IPRouter,
    IPMarket
} from "@contracts/vaults/staking/protocols/PendlePrincipalToken.sol";
import {PendlePTOracle} from "@contracts/oracles/PendlePTOracle.sol";
import "@interfaces/chainlink/AggregatorV2V3Interface.sol";
import {WithdrawManager, stETH, LidoWithdraw} from "@contracts/vaults/staking/protocols/Kelp.sol";
import {PendlePTKelpVault} from "@contracts/vaults/staking/PendlePTKelpVault.sol";

interface ILRTOracle {
    // methods
    function getAssetPrice(address asset) external view returns (uint256);
    function assetPriceOracle(address asset) external view returns (address);
    function rsETHPrice() external view returns (uint256);
}

ILRTOracle constant lrtOracle = ILRTOracle(0x349A73444b1a310BAe67ef67973022020d70020d);
address constant unstakingVault = 0xc66830E2667bc740c0BED9A71F18B14B8c8184bA;

contract Test_Staking_PendlePT_Kelp is BaseStakingTest {
    uint256 expires;

    function setUp() public override {
        FORK_BLOCK = 20019099;
        harness = new Harness_Staking_PendlePT_Kelp();

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
        // finalize withdraw request on Kelp
        address stETHWhale = 0x804a7934bD8Cd166D35D8Fb5A1eb1035C8ee05ce;
        vm.prank(stETHWhale);
        IERC20(stETH).transfer(unstakingVault, 10_000e18);
        vm.startPrank(0xCbcdd778AA25476F203814214dD3E9b9c46829A1); // kelp: operator
        WithdrawManager.unlockQueue(
            address(stETH),
            type(uint256).max,
            lrtOracle.getAssetPrice(address(stETH)),
            lrtOracle.rsETHPrice()
        );
        vm.stopPrank();
        vm.roll(block.number + WithdrawManager.withdrawalDelayBlocks());

        // trigger withdraw from Kelp nad unstake from LIDO
        WithdrawRequest memory w = v().getWithdrawRequest(account);
        PendlePTKelpVault(payable(address(vault))).triggerExtraStep(w.requestId);

        // finalize withdraw request on LIDO
        address lidoAdmin = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        deal(lidoAdmin, 1000e18);
        vm.startPrank(lidoAdmin);
        LidoWithdraw.finalize{value: 1000e18}(LidoWithdraw.getLastRequestId(), 1.1687147788880494e27);
        vm.stopPrank();
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

        setMaxOracleFreshness();
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
            v().initiateWithdraw();
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

contract Harness_Staking_PendlePT_Kelp is PendleKelpHarness {
    function getVaultName() public pure override returns (string memory) {
        return 'Pendle:PT Kelp rsETH 27JUN2024:[ETH]';
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
        // rsETH
        token[0] = 0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7;
        permissions[0] = ITradingModule.TokenPermissions(
            // UniswapV3, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 4, tradeTypeFlags: 5 }
        );
    }

    constructor() {
        marketAddress = 0x4f43c77872Db6BA177c270986CD30c3381AF37Ee;
        ptAddress = 0xB05cABCd99cf9a73b19805edefC5f67CA5d1895E;
        twapDuration = 15 minutes; // recommended 15 - 30 min
        useSyOracleRate = true;
        baseToUSDOracle = 0xE47F6c47DE1F1D93d8da32309D4dB90acDadeEaE;
    }

}