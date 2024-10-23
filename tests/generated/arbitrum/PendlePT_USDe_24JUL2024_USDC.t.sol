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



contract Test_PendlePT_USDe_24JUL2024_USDC is BasePendleTest {
    function setUp() public override {
        FORK_BLOCK = 222513382;
        WHALE = 0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D;
        harness = new Harness_PendlePT_USDe_24JUL2024_USDC();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.1e6;
        maxDeposit = 5_000e6;
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


contract Harness_PendlePT_USDe_24JUL2024_USDC is PendleStakingHarness {

    function getVaultName() public pure override returns (string memory) {
        return 'Pendle:PT USDe 24JUL2024:[USDC]';
    }

    function getRequiredOracles() public override view returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](3);
        oracle = new address[](3);

        // Custom PT Oracle
        token[0] = ptAddress;
        oracle[0] = ptOracle;

        // USDC
        token[1] = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        oracle[1] = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
        // USDe
        token[2] = 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34;
        oracle[2] = 0x88AC7Bca36567525A866138F03a6F6844868E0Bc;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](2);
        permissions = new ITradingModule.TokenPermissions[](2);

        

        token[0] = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        permissions[0] = ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: 1 << 8, tradeTypeFlags: 5 }
        );
        token[1] = 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34;
        permissions[1] = ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: 1 << 8, tradeTypeFlags: 5 }
        );
        
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 10;
        params.liquidationRate = 102;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 800;
        params.maxRequiredAccountCollateralRatioBPS = 10000;
        params.maxDeleverageCollateralRatioBPS = 1500;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 0.001e8;
        maxPrimaryBorrow = 100e8;
    }

    function deployImplementation() internal override returns (address impl) {
        
        return address(new PendlePTGeneric(
            marketAddress, tokenInSy, tokenOutSy, borrowToken, ptAddress, redemptionToken
        ));
        
    }

    

    constructor() {
        marketAddress = 0x2Dfaf9a5E4F293BceedE49f2dBa29aACDD88E0C4;
        ptAddress = 0xad853EB4fB3Fe4a66CdFCD7b75922a0494955292;
        twapDuration = 15 minutes; // recommended 15 - 30 min
        useSyOracleRate = true;
        baseToUSDOracle = 0x88AC7Bca36567525A866138F03a6F6844868E0Bc;
        borrowToken = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        tokenOutSy = 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34;
        
        tokenInSy = 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34;
        redemptionToken = 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34;
        

        bytes memory d = "";
        bytes memory exchangeData = abi.encode(d);
        uint8 primaryDexId = 8;

        setMetadata(StakingMetadata(3, primaryDexId, exchangeData, false));
    }

}

contract Deploy_PendlePT_USDe_24JUL2024_USDC is Harness_PendlePT_USDe_24JUL2024_USDC, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_PendlePT_USDe_24JUL2024_USDC();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}