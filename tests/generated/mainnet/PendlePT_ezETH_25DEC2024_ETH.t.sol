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
import "@interfaces/ethena/IsUSDe.sol";
import { PendlePTGeneric } from "@contracts/vaults/staking/PendlePTGeneric.sol";



contract Test_PendlePT_ezETH_25DEC2024_ETH is BasePendleTest {
    function setUp() public override {
        FORK_BLOCK = 21023919;
        harness = new Harness_PendlePT_ezETH_25DEC2024_ETH();

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
        splitWithdrawPriceDecrease = 610;

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


contract Harness_PendlePT_ezETH_25DEC2024_ETH is PendleStakingHarness {

    function getVaultName() public pure override returns (string memory) {
        return 'Pendle:PT ezETH 25DEC2024:[ETH]';
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
        token = new address[](2);
        permissions = new ITradingModule.TokenPermissions[](2);

        

        token[0] = 0xbf5495Efe5DB9ce00f80364C8B423567e58d2110;
        permissions[0] = ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: 1 << 4, tradeTypeFlags: 5 }
        );
        token[1] = 0x0000000000000000000000000000000000000000;
        permissions[1] = ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: 1 << 4, tradeTypeFlags: 5 }
        );
        
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 0;
        params.liquidationRate = 103;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 1100;
        params.maxRequiredAccountCollateralRatioBPS = 10000;
        params.maxDeleverageCollateralRatioBPS = 2000;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 20e8;
        maxPrimaryBorrow = 1_000e8;
    }

    function deployImplementation() internal override returns (address impl) {
        
        return address(new PendlePTGeneric(
            marketAddress, tokenInSy, tokenOutSy, borrowToken, ptAddress, redemptionToken
        ));
        
    }

    

    constructor() {
        EXISTING_DEPLOYMENT = 0xe47d1584A6dBb98Cc889BB1c9CBE5387173C282b;
        marketAddress = 0xD8F12bCDE578c653014F27379a6114F67F0e445f;
        ptAddress = 0xf7906F274c174A52d444175729E3fa98f9bde285;
        twapDuration = 15 minutes; // recommended 15 - 30 min
        useSyOracleRate = true;
        baseToUSDOracle = 0xCa140AE5a361b7434A729dCadA0ea60a50e249dd;
        borrowToken = 0x0000000000000000000000000000000000000000;
        tokenOutSy = 0xbf5495Efe5DB9ce00f80364C8B423567e58d2110;
        
        tokenInSy = 0xbf5495Efe5DB9ce00f80364C8B423567e58d2110;
        redemptionToken = 0xbf5495Efe5DB9ce00f80364C8B423567e58d2110;
        

        BalancerV2Adapter.SingleSwapData memory d;
        d.poolId = 0x596192bb6e41802428ac943d2f1476c1af25cc0e000000000000000000000659;
        bytes memory exchangeData = abi.encode(d);
        uint8 primaryDexId = 4;

        setMetadata(StakingMetadata(1, primaryDexId, exchangeData, false));
    }

}

contract Deploy_PendlePT_ezETH_25DEC2024_ETH is Harness_PendlePT_ezETH_25DEC2024_ETH, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_PendlePT_ezETH_25DEC2024_ETH();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}