// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../Staking/harness/index.sol";
import {WithdrawRequestNFT} from "@contracts/vaults/staking/protocols/EtherFi.sol";
import {WithdrawManager} from "@contracts/vaults/staking/protocols/Kelp.sol";
import {
    PendleDepositParams,
    IPRouter,
    IPMarket
} from "@contracts/vaults/staking/protocols/PendlePrincipalToken.sol";
import {PendlePTOracle} from "@contracts/oracles/PendlePTOracle.sol";
import "@interfaces/chainlink/AggregatorV2V3Interface.sol";
import { PendlePTKelpVault } from "@contracts/vaults/staking/PendlePTKelpVault.sol";


interface ILRTOracle {
    // methods
    function getAssetPrice(address asset) external view returns (uint256);
    function assetPriceOracle(address asset) external view returns (address);
    function rsETHPrice() external view returns (uint256);
}

ILRTOracle constant lrtOracle = ILRTOracle(0x349A73444b1a310BAe67ef67973022020d70020d);
address constant unstakingVault = 0xc66830E2667bc740c0BED9A71F18B14B8c8184bA;


contract Test_PendlePT_rsETH_ETH is BasePendleTest {
    function setUp() public override {
        FORK_BLOCK = 20492805;
        harness = new Harness_PendlePT_rsETH_ETH();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.1e18;
        maxDeposit = 10e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;
        maxRelExitValuation_WithdrawRequest_Fixed = 0.03e18;
        maxRelExitValuation_WithdrawRequest_Variable = 0.005e18;
        deleverageCollateralDecreaseRatio = 930;
        defaultLiquidationDiscount = 955;
        withdrawLiquidationDiscount = 945;
        borrowTokenPriceIncrease = 1500;
        splitWithdrawPriceDecrease = 450;

        super.setUp();
    }

    
    function finalizeWithdrawRequest(address account) internal override {
        // finalize withdraw request on Kelp
        vm.deal(address(unstakingVault), 10_000e18);
        vm.startPrank(0xCbcdd778AA25476F203814214dD3E9b9c46829A1); // kelp: operator
        WithdrawManager.unlockQueue(
            Deployments.ALT_ETH_ADDRESS,
            type(uint256).max,
            lrtOracle.getAssetPrice(Deployments.ALT_ETH_ADDRESS),
            lrtOracle.rsETHPrice()
        );
        vm.stopPrank();
        vm.roll(block.number + WithdrawManager.withdrawalDelayBlocks());
    }
    

    function getDepositParams(
        uint256 /* depositAmount */,
        uint256 /* maturity */
    ) internal view override returns (bytes memory) {
        StakingMetadata memory m = BaseStakingHarness(address(harness)).getMetadata();

        PendleDepositParams memory d = PendleDepositParams({
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

}


contract Harness_PendlePT_rsETH_ETH is PendleStakingHarness {

    function getVaultName() public pure override returns (string memory) {
        return 'Pendle:PT rsETH 26SEP2024:[ETH]';
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

        

        token[0] = 0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7;
        permissions[0] = ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: 1 << 2, tradeTypeFlags: 5 }
        );
        
    }

    function deployImplementation() internal override returns (address impl) {
        
        return address(new PendlePTKelpVault(marketAddress, ptAddress));
        
    }

    constructor() {
        marketAddress = 0x6b4740722e46048874d84306B2877600ABCea3Ae;
        ptAddress = 0x7bAf258049cc8B9A78097723dc19a8b103D4098F;
        twapDuration = 15 minutes; // recommended 15 - 30 min
        useSyOracleRate = true;
        baseToUSDOracle = 0xb676EA4e0A54ffD579efFc1f1317C70d671f2028;
        

        UniV3Adapter.UniV3SingleData memory d;
        d.fee = 500;
        bytes memory exchangeData = abi.encode(d);
        uint8 primaryDexId = 2;

        setMetadata(StakingMetadata(1, primaryDexId, exchangeData, true));
    }

}