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

contract Test_SingleSidedLP_Aura_osETH_xWETH is BaseComposablePool {
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Aura:osETH/[WETH]';
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

        // osETH
        token[0] = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;
        oracle[0] = 0x3d3d7d124B0B80674730e0D31004790559209DEb;
        // ETH
        token[1] = 0x0000000000000000000000000000000000000000;
        oracle[1] = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
        
    }

    function initVariables() override internal {
        rewardPool = IERC20(0x5F032f15B4e910252EDaDdB899f7201E89C8cD6b);
        
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
        // SWISE
        rewardTokens.push(IERC20(0x48C3399719B582dD63eB5AADf12A40B4C3f52FA2));
        
    }

    function setUp() public override virtual {
        primaryBorrowCurrency = ETH;
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