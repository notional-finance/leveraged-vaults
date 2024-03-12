// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {
    BaseComposablePool,
    StrategyVaultSettings,
    VaultConfigParams,
    IERC20
} from "../../SingleSidedLP/pools/BaseComposablePool.sol";
import { BaseCurve2Token } from "../../SingleSidedLP/pools/BaseCurve2Token.sol";
import { BaseWeightedPool } from "../../SingleSidedLP/pools/BaseWeightedPool.sol";

contract Test_SingleSidedLP_Aura_xrETH_weETH is BaseComposablePool {
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Aura:[rETH]/weETH';
    }

    function getDeploymentConfig() internal view override returns (
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

    function getRequiredOracles() internal override view virtual returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // rETH
        token[0] = 0xae78736Cd615f374D3085123A210448E74Fc6393;
        oracle[0] = 0xA7D273951861CF07Df8B0A1C3c934FD41bA9E8Eb;
        // weETH
        token[1] = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
        oracle[1] = 0xdDb6F90fFb4d3257dd666b69178e5B3c5Bf41136;
        
    }

    function initVariables() override internal {
        rewardPool = IERC20(0x07A319A023859BbD49CC9C38ee891c3EA9283Cc5);
        
        settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 100
        });

        // AURA
        rewardTokens.push(IERC20(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF));
        // BAL
        rewardTokens.push(IERC20(0xba100000625a3754423978a60c9317c58a424e3D));
        
    }

    function setUp() public override virtual {
        primaryBorrowCurrency = RETH;
        initVariables();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1000e8;
        maxDeposit = 1e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;
        super.setUp();
    }
}