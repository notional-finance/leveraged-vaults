// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {
    SingleSidedLPMetadata,
    ComposablePoolHarness,
    StrategyVaultSettings,
    VaultConfigParams,
    IERC20
} from "../../SingleSidedLP/harness/ComposablePoolHarness.sol";
import { Curve2TokenHarness, CurveInterface } from "../../SingleSidedLP/harness/Curve2TokenHarness.sol";
import { WeightedPoolHarness } from "../../SingleSidedLP/harness/WeightedPoolHarness.sol";
import { ITradingModule } from "@interfaces/trading/ITradingModule.sol";

contract Test_SingleSidedLP_Convex_xUSDC_crvUSD is 
Curve2TokenHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Convex:[USDC]/crvUSD';
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 10;
        params.liquidationRate = 102;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 500;
        params.maxRequiredAccountCollateralRatioBPS = 10000;
        params.maxDeleverageCollateralRatioBPS = 2600;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 0.001e8;
        maxPrimaryBorrow = 100e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // USDC
        token[0] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        oracle[0] = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
        // crvUSD
        token[1] = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
        oracle[1] = 0xEEf0C605546958c1f899b6fB336C20671f9cD49F;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](2);
        permissions = new ITradingModule.TokenPermissions[](2);

        // CRV
        token[0] = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        permissions[0] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        // CVX
        token[1] = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        permissions[1] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        
    }

    constructor() {
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 3;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 100
        });
        _m.rewardPool = IERC20(0x44D8FaB7CD8b7877D5F79974c2F501aF6E65AbBA);

        
        _m.poolToken = IERC20(0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E);
        lpToken = 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E;
        curveInterface = CurveInterface.V1;
        

        _m.rewardTokens = new IERC20[](2);
        // CRV
        _m.rewardTokens[0] = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
        // CVX
        _m.rewardTokens[1] = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
        
    }
}



/*
        # TODO: this is only for tests...
        # # WHALE = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
        # // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1e6;
        maxDeposit = 90_000e6;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;
        super.setUp();
*/