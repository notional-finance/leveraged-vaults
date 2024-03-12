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

contract Test_SingleSidedLP_Convex_pyUSD_xUSDC is BaseCurve2Token {
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Convex:pyUSD/[USDC]';
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

        // USDC
        token[0] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        oracle[0] = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
        // pyUSD
        token[1] = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;
        oracle[1] = 0x8f1dF6D7F2db73eECE86a18b4381F4707b918FB1;
        
    }

    function initVariables() override internal {
        rewardPool = IERC20(0xc583e81bB36A1F620A804D8AF642B63b0ceEb5c0);
        
        poolToken = IERC20(0x383E6b4437b59fff47B619CBA855CA29342A8559);
        lpToken = 0x383E6b4437b59fff47B619CBA855CA29342A8559;
        
        settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 100
        });

        // CRV
        rewardTokens.push(IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52));
        // CVX
        rewardTokens.push(IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B));
        // pyUSD
        rewardTokens.push(IERC20(0x6c3ea9036406852006290770BEdFcAbA0e23A0e8));
        
    }

    function setUp() public override virtual {
        WHALE = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
        primaryBorrowCurrency = USDC;
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