// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {
    SingleSidedLPMetadata,
    ComposablePoolHarness,
    StrategyVaultSettings,
    VaultConfigParams,
    IERC20
} from "../../SingleSidedLP/harness/ComposablePoolHarness.sol";
import { DeployProxyVault} from "../../../scripts/deploy/DeployProxyVault.sol";
import { BaseSingleSidedLPVault } from "../../SingleSidedLP/BaseSingleSidedLPVault.sol";
import { Curve2TokenHarness, CurveInterface } from "../../SingleSidedLP/harness/Curve2TokenHarness.sol";
import { WeightedPoolHarness } from "../../SingleSidedLP/harness/WeightedPoolHarness.sol";
import { ITradingModule } from "@interfaces/trading/ITradingModule.sol";

contract Test_SingleSidedLP_Aura_xrETH_WETH is BaseSingleSidedLPVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Aura_xrETH_WETH();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.001e18;
        maxDeposit = 50e18;
        maxRelEntryValuation = 75 * BASIS_POINT;
        maxRelExitValuation = 75 * BASIS_POINT;

        super.setUp();
    }
}

contract Deploy_SingleSidedLP_Aura_xrETH_WETH is DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Aura_xrETH_WETH();
    }
}

contract Harness_SingleSidedLP_Aura_xrETH_WETH is 
ComposablePoolHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Aura:[rETH]/WETH';
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
        params.minAccountBorrowSize = 2e8;
        maxPrimaryBorrow = 100e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // rETH
        token[0] = 0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8;
        oracle[0] = 0x40cf45dBD4813be545CF3E103eF7ef531eac7283;
        // ETH
        token[1] = 0x0000000000000000000000000000000000000000;
        oracle[1] = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](2);
        permissions = new ITradingModule.TokenPermissions[](2);

        // AURA
        token[0] = 0x1509706a6c66CA549ff0cB464de88231DDBe213B;
        permissions[0] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        // BAL
        token[1] = 0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8;
        permissions[1] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        
    }

    constructor() {
        EXISTING_DEPLOYMENT = 0x3Df035433cFACE65b6D68b77CC916085d020C8B8;
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 7;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 100
        });
        _m.rewardPool = IERC20(0x129A44AC6ff0f965C907579F96F2eD682E52c84A);

        

        _m.rewardTokens = new IERC20[](2);
        // AURA
        _m.rewardTokens[0] = IERC20(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
        // BAL
        _m.rewardTokens[1] = IERC20(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
        

        setMetadata(_m);
    }
}