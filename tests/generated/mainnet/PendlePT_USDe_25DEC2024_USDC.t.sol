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



contract Test_PendlePT_USDe_25DEC2024_USDC is BasePendleTest {
    function setUp() public override {
        FORK_BLOCK = 21037163;
        WHALE = 0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf;
        harness = new Harness_PendlePT_USDe_25DEC2024_USDC();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.1e6;
        maxDeposit = 100_000e6;
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
        d.pool = 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72;
        d.fromIndex = 0;
        d.toIndex = 1;
        r.exchangeData = abi.encode(d);

        return abi.encode(r);
    }
    }


contract Harness_PendlePT_USDe_25DEC2024_USDC is PendleStakingHarness {

    function getVaultName() public pure override returns (string memory) {
        return 'Pendle:PT USDe 25DEC2024:[USDC]';
    }

    function getRequiredOracles() public override view returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // Custom PT Oracle
        token[0] = ptAddress;
        oracle[0] = ptOracle;

        // USDC
        token[1] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        oracle[1] = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](2);
        permissions = new ITradingModule.TokenPermissions[](2);

        

        token[0] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        permissions[0] = ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: 1 << 7, tradeTypeFlags: 5 }
        );
        token[1] = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
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
        params.minCollateralRatioBPS = 1200;
        params.maxRequiredAccountCollateralRatioBPS = 10000;
        params.maxDeleverageCollateralRatioBPS = 2000;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 60_000e8;
        maxPrimaryBorrow = 1_000_000e8;
    }

    function deployImplementation() internal override returns (address impl) {
        
        return address(new PendlePTGeneric(
            marketAddress, tokenInSy, tokenOutSy, borrowToken, ptAddress, redemptionToken
        ));
        
    }

    

    constructor() {
        EXISTING_DEPLOYMENT = 0x5fc3FC6263B16F665d78075784f5A6ABeD00e1dD;
        marketAddress = 0x8a49f2AC2730ba15AB7EA832EdaC7f6BA22289f8;
        ptAddress = 0xA8778DD6B7f1F61f2CFda5D3cB18be8F99A8dB30;
        twapDuration = 15 minutes; // recommended 15 - 30 min
        useSyOracleRate = true;
        baseToUSDOracle = 0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961;
        borrowToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        tokenOutSy = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        
        tokenInSy = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        redemptionToken = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        

        CurveV2Adapter.CurveV2SingleData memory d;
        d.pool = 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72;
        d.fromIndex = 1;
        d.toIndex = 0;
        bytes memory exchangeData = abi.encode(d);
        uint8 primaryDexId = 7;

        setMetadata(StakingMetadata(3, primaryDexId, exchangeData, false));
    }

}

contract Deploy_PendlePT_USDe_25DEC2024_USDC is Harness_PendlePT_USDe_25DEC2024_USDC, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_PendlePT_USDe_25DEC2024_USDC();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}