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
import { PendlePTEtherFiVault } from "@contracts/vaults/staking/PendlePTEtherFiVault.sol";

contract Test_PendlePT_weETH_ETH is BasePendleTest {
    function setUp() public override {
        FORK_BLOCK = 20092864;
        harness = new Harness_PendlePT_weETH_ETH();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.1e18;
        maxDeposit = 10e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;
        maxRelExitValuation_WithdrawRequest_Fixed = 0.03e18;
        maxRelExitValuation_WithdrawRequest_Variable = 0.005e18;
        deleverageCollateralDecreaseRatio = 920;
        defaultLiquidationDiscount = 955;
        withdrawLiquidationDiscount = 945;

        super.setUp();
    }

    
    function finalizeWithdrawRequest(address account) internal override {
        WithdrawRequest memory w = v().getWithdrawRequest(account);

        vm.prank(0x0EF8fa4760Db8f5Cd4d993f3e3416f30f942D705); // etherFi: admin
        WithdrawRequestNFT.finalizeRequests(w.requestId);
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


contract Harness_PendlePT_weETH_ETH is PendleStakingHarness {

    function getVaultName() public pure override returns (string memory) {
        return 'Pendle:PT weETH 27JUN2024:[ETH]';
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

        

        token[0] = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
        permissions[0] = ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: 1 << 2, tradeTypeFlags: 5 }
        );
        
    }

    function deployImplementation() internal override returns (address impl) {
        
        return address(new PendlePTEtherFiVault(marketAddress, ptAddress));
        
    }

    constructor() {
        marketAddress = 0xF32e58F92e60f4b0A37A69b95d642A471365EAe8;
        ptAddress = 0xc69Ad9baB1dEE23F4605a82b3354F8E40d1E5966;
        twapDuration = 15 minutes; // recommended 15 - 30 min
        useSyOracleRate = true;
        baseToUSDOracle = 0xE47F6c47DE1F1D93d8da32309D4dB90acDadeEaE;
        

        UniV3Adapter.UniV3SingleData memory d;
        d.fee = 500;
        bytes memory exchangeData = abi.encode(d);
        uint8 primaryDexId = 2;

        setMetadata(StakingMetadata(1, primaryDexId, exchangeData, true));
    }

}