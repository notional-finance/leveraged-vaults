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

contract Test_SingleSidedLP_Aura_GHO_USDT_xUSDC is BaseComposablePool {
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Aura:GHO/USDT/[USDC]';
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
        token = new address[](3);
        oracle = new address[](3);

        // GHO
        token[0] = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
        oracle[0] = 0x3f12643D3f6f874d39C2a4c9f2Cd6f2DbAC877FC;
        // USDT
        token[1] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        oracle[1] = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
        // USDC
        token[2] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        oracle[2] = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
        
    }

    function initVariables() override internal {
        rewardPool = IERC20(0xBDD6984C3179B099E9D383ee2F44F3A57764BF7d);
        
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
        WHALE = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
        primaryBorrowCurrency = USDC;
        initVariables();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1000e6;
        maxDeposit = 100_000e6;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;
        super.setUp();
    }
}