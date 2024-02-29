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

contract Test_SingleSidedLP_Aura_xwstETH_cbETH_rETH is BaseComposablePool {
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Aura:[wstETH]/cbETH/rETH';
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

        // wstETH
        token[1] = 0x5979D7b546E38E414F7E9822514be443A4800529;
        oracle[1] = 0x29aFB1043eD699A89ca0F0942ED6F6f65E794A3d;
        // cbETH
        token[2] = 0x1DEBd73E752bEaF79865Fd6446b0c970EaE7732f;
        oracle[2] = 0x4763672dEa3bF087929d5537B6BAfeB8e6938F46;
        // rETH
        token[3] = 0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8;
        oracle[3] = 0x40cf45dBD4813be545CF3E103eF7ef531eac7283;
        
    }

    function initVariables() override internal {
        rewardPool = IERC20(0x8cA64Bd82AbFE138E195ce5Cb7268CA285D42245);
        
        settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 100
        });
    }

    function setUp() public override virtual {
        EXISTING_DEPLOYMENT = 0x37dD23Ab1885982F789A2D6400B583B8aE09223d;
        primaryBorrowCurrency = WSTETH;
        initVariables();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.001e18;
        maxDeposit = 50e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;
        super.setUp();
    }
}