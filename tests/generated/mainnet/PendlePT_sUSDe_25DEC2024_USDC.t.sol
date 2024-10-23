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
import { PendlePTStakedUSDeVault } from "@contracts/vaults/staking/PendlePTStakedUSDeVault.sol";



contract Test_PendlePT_sUSDe_25DEC2024_USDC is BasePendleTest {
    function setUp() public override {
        FORK_BLOCK = 21023919;
        WHALE = 0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf;
        harness = new Harness_PendlePT_sUSDe_25DEC2024_USDC();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.1e6;
        maxDeposit = 100_000e6;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;
        maxRelExitValuation_WithdrawRequest_Fixed = 0.03e18;
        maxRelExitValuation_WithdrawRequest_Variable = 0.01e18;
        deleverageCollateralDecreaseRatio = 925;
        defaultLiquidationDiscount = 955;
        withdrawLiquidationDiscount = 945;
        splitWithdrawPriceDecrease = 610;

        super.setUp();
    }

    
    function finalizeWithdrawRequest(address account) internal override {
        WithdrawRequest memory w = v().getWithdrawRequest(account);
        IsUSDe.UserCooldown memory wCooldown = sUSDe.cooldowns(address(uint160(w.requestId)));

        setMaxOracleFreshness();
        vm.warp(wCooldown.cooldownEnd);
    }
    

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

        r.minPurchaseAmount = 0;
        r.dexId = 7; // CurveV2
        // For CurveV2 we need to swap the in and out indexes on exit
        CurveV2Adapter.CurveV2SingleData memory d;
        d.pool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
        d.fromIndex = 0; // DAI
        d.toIndex = 1; // USDC
        r.exchangeData = abi.encode(d);

        return abi.encode(r);
    }

    function getRedeemParamsWithdrawRequest(
        uint256 /* vaultShares */,
        uint256 /* maturity */
    ) internal view virtual override returns (bytes memory) {
        RedeemParams memory r;
        // On withdraw request, we need to swap USDe to USDC

        r.minPurchaseAmount = 0;
        r.dexId = 7; // CurveV2
        // For CurveV2 we need to swap the in and out indexes on exit
        CurveV2Adapter.CurveV2SingleData memory d;
        d.pool = 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72;
        d.fromIndex = 0; // USDe
        d.toIndex = 1; // USDC
        r.exchangeData = abi.encode(d);

        return abi.encode(r);
    }
    }


contract Harness_PendlePT_sUSDe_25DEC2024_USDC is PendleStakingHarness {

    function getVaultName() public pure override returns (string memory) {
        return 'Pendle:PT sUSDe 25DEC2024:[USDC]';
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
        token[1] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        oracle[1] = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
        // sUSDe
        token[2] = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
        oracle[2] = 0xFF3BC18cCBd5999CE63E788A1c250a88626aD099;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](4);
        permissions = new ITradingModule.TokenPermissions[](4);

        

        token[0] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        permissions[0] = ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: 1 << 7, tradeTypeFlags: 5 }
        );
        token[1] = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        permissions[1] = ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: 1 << 7, tradeTypeFlags: 5 }
        );
        token[2] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        permissions[2] = ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: 1 << 7, tradeTypeFlags: 5 }
        );
        token[3] = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
        permissions[3] = ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: 1 << 7, tradeTypeFlags: 5 }
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
        
        return address(new PendlePTStakedUSDeVault(marketAddress, ptAddress, borrowToken));
        
    }

    
    function withdrawToken(address vault) public view override returns (address) {
        // USDe is the withdraw token
        return 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    }
    

    constructor() {
        marketAddress = 0xa0ab94DeBB3cC9A7eA77f3205ba4AB23276feD08;
        ptAddress = 0xEe9085fC268F6727d5D4293dBABccF901ffDCC29;
        twapDuration = 15 minutes; // recommended 15 - 30 min
        useSyOracleRate = true;
        baseToUSDOracle = 0xFF3BC18cCBd5999CE63E788A1c250a88626aD099;
        borrowToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        tokenOutSy = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
        

        CurveV2Adapter.CurveV2SingleData memory d;
        d.pool = 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72;
        d.fromIndex = 1;
        d.toIndex = 0;
        bytes memory exchangeData = abi.encode(d);
        uint8 primaryDexId = 7;

        setMetadata(StakingMetadata(3, primaryDexId, exchangeData, true));
    }

}

contract Deploy_PendlePT_sUSDe_25DEC2024_USDC is Harness_PendlePT_sUSDe_25DEC2024_USDC, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_PendlePT_sUSDe_25DEC2024_USDC();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}