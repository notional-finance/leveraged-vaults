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



contract Test_PendlePT_pufETH_25JUN2025_ETH is BasePendleTest {
    function setUp() public override {
        FORK_BLOCK = 21989427;
        harness = new Harness_PendlePT_pufETH_25JUN2025_ETH();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.1e18;
        maxDeposit = 25e18;
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

    
    function getRedeemParams(
        uint256 /* vaultShares */,
        uint256 /* maturity */
    ) internal view virtual override returns (bytes memory) {
        RedeemParams memory r;

        StakingMetadata memory m = BaseStakingHarness(address(harness)).getMetadata();
        r.minPurchaseAmount = 0;
        r.dexId = m.primaryDexId;
        // For CurveV2 we need to swap the in and out indexes on exit
        CurveV2Adapter.CurveV2SingleData memory d;
        d.pool = 0x39F5b252dE249790fAEd0C2F05aBead56D2088e1;
        d.fromIndex = 1;
        d.toIndex = 0;
        r.exchangeData = abi.encode(d);

        return abi.encode(r);
    }
    }


contract Harness_PendlePT_pufETH_25JUN2025_ETH is PendleStakingHarness {

    function getVaultName() public pure override returns (string memory) {
        return 'Pendle:PT pufETH 25JUN2025:[ETH]';
    }

    function getRequiredOracles() public override view returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](3);
        oracle = new address[](3);

        // Custom PT Oracle
        token[0] = ptAddress;
        oracle[0] = ptOracle;

        // ETH
        token[1] = 0x0000000000000000000000000000000000000000;
        oracle[1] = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
        // pufETH
        token[2] = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
        oracle[2] = 0xa076ef6D0F2E75957015aBED2701d9CDdF28faDd;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](2);
        permissions = new ITradingModule.TokenPermissions[](2);

        

        token[0] = 0x0000000000000000000000000000000000000000;
        permissions[0] = ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: 1 << 7, tradeTypeFlags: 5 }
        );
        token[1] = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
        permissions[1] = ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: 1 << 7, tradeTypeFlags: 5 }
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
        marketAddress = 0x58612beB0e8a126735b19BB222cbC7fC2C162D2a;
        ptAddress = 0x9cFc9917C171A384c7168D3529Fc7e851a2E0d6D;
        twapDuration = 15 minutes; // recommended 15 - 30 min
        useSyOracleRate = true;
        baseToUSDOracle = 0xa076ef6D0F2E75957015aBED2701d9CDdF28faDd;
        borrowToken = 0x0000000000000000000000000000000000000000;
        tokenOutSy = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
        
        tokenInSy = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
        redemptionToken = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
        

        CurveV2Adapter.CurveV2SingleData memory d;
        d.pool = 0x39F5b252dE249790fAEd0C2F05aBead56D2088e1;
        d.fromIndex = 0;
        d.toIndex = 1;
        bytes memory exchangeData = abi.encode(d);
        uint8 primaryDexId = 7;

        setMetadata(StakingMetadata(1, primaryDexId, exchangeData, false));
    }

}

contract Deploy_PendlePT_pufETH_25JUN2025_ETH is Harness_PendlePT_pufETH_25JUN2025_ETH, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_PendlePT_pufETH_25JUN2025_ETH();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}