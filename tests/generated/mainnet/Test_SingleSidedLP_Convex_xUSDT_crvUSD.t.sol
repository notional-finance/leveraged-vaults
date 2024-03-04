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

contract Test_SingleSidedLP_Convex_xUSDT_crvUSD is BaseCurve2Token {
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Convex:[USDT]/crvUSD';
    }

    function getDeploymentConfig() internal view override returns (
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

    function getRequiredOracles() internal override view virtual returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // USDT
        token[0] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        oracle[0] = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
        // crvUSD
        token[1] = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
        oracle[1] = 0xEEf0C605546958c1f899b6fB336C20671f9cD49F;
        
    }

    function initVariables() override internal {
        rewardPool = IERC20(0xD1DdB0a0815fD28932fBb194C84003683AF8a824);
        
        poolToken = IERC20(0x390f3595bCa2Df7d23783dFd126427CCeb997BF4);
        lpToken = 0x390f3595bCa2Df7d23783dFd126427CCeb997BF4;
        
        settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 100
        });
    }

    function setUp() public override virtual {
        primaryBorrowCurrency = USDT;
        initVariables();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1e6;
        maxDeposit = 100_000e6;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;
        super.setUp();
    }
}