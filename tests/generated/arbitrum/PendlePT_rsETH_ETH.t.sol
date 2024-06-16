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
import { PendlePTGeneric } from "@contracts/vaults/staking/PendlePTGeneric.sol";

contract Test_PendlePT_rsETH_ETH is BasePendleTest {
    function setUp() public override {
        FORK_BLOCK = 222513382;
        harness = new Harness_PendlePT_rsETH_ETH();

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
    }

    
    function finalizeWithdrawRequest(address account) internal override {}
    

    function getDepositParams(
        uint256 /* depositAmount */,
        uint256 /* maturity */
    ) internal view override returns (bytes memory) {
        StakingMetadata memory m = BaseStakingHarness(address(harness)).getMetadata();

        PendleDepositParams memory d = PendleDepositParams({
            dexId: m.primaryDexId,
            minPurchaseAmount: 0,
            exchangeData: m.exchangeData,
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
        return 'Pendle:PT rsETH 25SEP2024:[ETH]';
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
        oracle[1] = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](2);
        permissions = new ITradingModule.TokenPermissions[](2);

        

        token[0] = 0x4186BFC76E2E237523CBC30FD220FE055156b41F;
        permissions[0] = ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: 1 << 2, tradeTypeFlags: 5 }
        );
        token[1] = 0x0000000000000000000000000000000000000000;
        permissions[1] = ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: 1 << 2, tradeTypeFlags: 5 }
        );
        
    }

    function deployImplementation() internal override returns (address impl) {
        
        return address(new PendlePTGeneric(
            marketAddress, tokenInSy, tokenOutSy, borrowToken, ptAddress, redemptionToken
        ));
        
    }

    constructor() {
        marketAddress = 0xED99fC8bdB8E9e7B8240f62f69609a125A0Fbf14;
        ptAddress = 0x30c98c0139B62290E26aC2a2158AC341Dcaf1333;
        twapDuration = 15 minutes; // recommended 15 - 30 min
        useSyOracleRate = true;
        baseToUSDOracle = 0x02551ded3F5B25f60Ea67f258D907eD051E042b2;
        
        tokenInSy = 0x4186BFC76E2E237523CBC30FD220FE055156b41F;
        borrowToken = 0x0000000000000000000000000000000000000000;
        tokenOutSy = 0x4186BFC76E2E237523CBC30FD220FE055156b41F;
        redemptionToken = 0x4186BFC76E2E237523CBC30FD220FE055156b41F;
        

        UniV3Adapter.UniV3SingleData memory d;
        d.fee = 100;
        bytes memory exchangeData = abi.encode(d);
        uint8 primaryDexId = 2;

        setMetadata(StakingMetadata(1, primaryDexId, exchangeData, false));
    }

}