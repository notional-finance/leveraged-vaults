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

contract Test_SingleSidedLP_Aura_USDC_xDAI_USDT_USDC_e is BaseComposablePool {
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Aura:USDC/[DAI]/USDT/USDC.e';
    }

    function getDeploymentConfig() internal view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 10;
        params.liquidationRate = 102;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 1100;
        params.maxRequiredAccountCollateralRatioBPS = 10000;
        params.maxDeleverageCollateralRatioBPS = 1700;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 0.001e8;
        maxPrimaryBorrow = 100e8;
    }

    function getRequiredOracles() internal override view virtual returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](4);
        oracle = new address[](4);

        // USDC
        token[1] = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        oracle[1] = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
        // DAI
        token[2] = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
        oracle[2] = 0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB;
        // USDT
        token[3] = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        oracle[3] = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;
        // USDC_e
        token[4] = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
        oracle[4] = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
        
    }

    function initVariables() override internal {
        rewardPool = IERC20(0x416C7Ad55080aB8e294beAd9B8857266E3B3F28E);
        
        settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 100
        });
    }

    function setUp() public override virtual {
        primaryBorrowCurrency = DAI;
        initVariables();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.001e18;
        maxDeposit = 50e18;
        maxRelEntryValuation = 15 * BASIS_POINT;
        maxRelExitValuation = 15 * BASIS_POINT;
        super.setUp();
    }
}