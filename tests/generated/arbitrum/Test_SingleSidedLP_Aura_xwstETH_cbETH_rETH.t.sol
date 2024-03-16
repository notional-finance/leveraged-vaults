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

contract Test_SingleSidedLP_Aura_xwstETH_cbETH_rETH is 
ComposablePoolHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Aura:[wstETH]/cbETH/rETH';
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 10;
        params.liquidationRate = 102;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 1000;
        params.maxRequiredAccountCollateralRatioBPS = 10000;
        params.maxDeleverageCollateralRatioBPS = 1700;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 0.001e8;
        maxPrimaryBorrow = 100e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](3);
        oracle = new address[](3);

        // wstETH
        token[0] = 0x5979D7b546E38E414F7E9822514be443A4800529;
        oracle[0] = 0x29aFB1043eD699A89ca0F0942ED6F6f65E794A3d;
        // cbETH
        token[1] = 0x1DEBd73E752bEaF79865Fd6446b0c970EaE7732f;
        oracle[1] = 0x4763672dEa3bF087929d5537B6BAfeB8e6938F46;
        // rETH
        token[2] = 0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8;
        oracle[2] = 0x40cf45dBD4813be545CF3E103eF7ef531eac7283;
        
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
        EXISTING_DEPLOYMENT = 0x37dD23Ab1885982F789A2D6400B583B8aE09223d;
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 5;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 100
        });
        _m.rewardPool = IERC20(0x8cA64Bd82AbFE138E195ce5Cb7268CA285D42245);

        

        _m.rewardTokens = new IERC20[](2);
        // AURA
        _m.rewardTokens[0] = IERC20(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
        // BAL
        _m.rewardTokens[1] = IERC20(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
        
    }
}



/*
        # TODO: this is only for tests...
        # // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.001e18;
        maxDeposit = 50e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;
        super.setUp();
*/