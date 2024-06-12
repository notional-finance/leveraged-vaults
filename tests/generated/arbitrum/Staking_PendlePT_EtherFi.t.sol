// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../Staking/harness/index.sol";
import {
    PendleDepositParams,
    IPRouter,
    IPMarket
} from "@contracts/vaults/staking/protocols/PendlePrincipalToken.sol";
import {PendlePTVault} from "@contracts/vaults/staking/PendlePTVault.sol";
import {PendlePTOracle} from "@contracts/oracles/PendlePTOracle.sol";
import "@interfaces/chainlink/AggregatorV2V3Interface.sol";

contract Test_Staking_PendlePT_EtherFi is BaseStakingTest {
    uint256 expires;

    function setUp() public override {
        console.log("START");
        harness = new Harness_Staking_PendlePT_Generic();
        console.log("START");

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

        console.log("START");
        super.setUp();
        console.log("GOT HERE");
        expires = IPMarket(PendleStakingHarness(address(harness)).marketAddress()).expiry();
    }

    function finalizeWithdrawRequest(address account) internal override {
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
}


contract Harness_Staking_PendlePT_Generic is PendleStakingHarness {

    function getVaultName() public pure override returns (string memory) {
        return 'Pendle:PT ezETH 26JUN2024:[ETH]';
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
        token = new address[](1);
        permissions = new ITradingModule.TokenPermissions[](1);
        // ezETH
        token[0] = 0x2416092f143378750bb29b79eD961ab195CcEea5;
        permissions[0] = ITradingModule.TokenPermissions(
            // UniswapV3, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 4, tradeTypeFlags: 5 }
        );
    }

    function deployImplementation() internal override returns (address impl) {
        return address(new PendlePTVault(
            marketAddress,
            tokenInSy,
            tokenOutSy,
            borrowToken,
            ptAddress,
            redemptionToken
        ));
    }

    constructor() {
        marketAddress = 0x5E03C94Fc5Fb2E21882000A96Df0b63d2c4312e2;
        ptAddress = 0x8EA5040d423410f1fdc363379Af88e1DB5eA1C34;
        twapDuration = 15 minutes; // recommended 15 - 30 min
        useSyOracleRate = true; // returns the weETH price
        baseToUSDOracle = 0x58784379C844a00d4f572917D43f991c971F96ca;
        tokenInSy = 0x2416092f143378750bb29b79eD961ab195CcEea5;
        borrowToken = 0x0000000000000000000000000000000000000000;
        tokenOutSy = 0x2416092f143378750bb29b79eD961ab195CcEea5;
        redemptionToken = tokenOutSy;

        UniV3Adapter.UniV3SingleData memory u;
        u.fee = 500; // 0.05 %
        bytes memory exchangeData = abi.encode(u);
        uint8 primaryDexId = uint8(DexId.UNISWAP_V3);

        setMetadata(StakingMetadata(1, primaryDexId, exchangeData, false));
    }
}
