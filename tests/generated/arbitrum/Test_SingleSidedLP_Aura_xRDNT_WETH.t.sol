// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {
    BaseComposablePool,
    StrategyVaultSettings,
    VaultConfigParams,
    IERC20
} from "../../SingleSidedLP/pools/BaseComposablePool.sol";
import { BaseCurve2Token, CurveInterface } from "../../SingleSidedLP/pools/BaseCurve2Token.sol";
import { BaseWeightedPool } from "../../SingleSidedLP/pools/BaseWeightedPool.sol";

contract Test_SingleSidedLP_Aura_xRDNT_WETH is BaseWeightedPool {
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Aura:[RDNT]/WETH';
    }

    function getDeploymentConfig() internal view override returns (
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
        params.minAccountBorrowSize = 1e8;
        maxPrimaryBorrow = 100e8;
    }

    function getRequiredOracles() internal override view virtual returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // RDNT
        token[0] = 0x3082CC23568eA640225c2467653dB90e9250AaA0;
        oracle[0] = 0x20d0Fcab0ECFD078B036b6CAf1FaC69A6453b352;
        // ETH
        token[1] = 0x0000000000000000000000000000000000000000;
        oracle[1] = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
        
    }

    function initVariables() override internal {
        rewardPool = IERC20(0xa17492d89cB2D0bE1dDbd0008F8585EDc5B0ACf3);
        
        settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 200
        });

        // AURA
        rewardTokens.push(IERC20(0x1509706a6c66CA549ff0cB464de88231DDBe213B));
        // BAL
        rewardTokens.push(IERC20(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8));
        
    }

    function setUp() public override virtual {
        primaryBorrowCurrency = RDNT;
        initVariables();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.001e18;
        maxDeposit = 50e18;
        maxRelEntryValuation = 75 * BASIS_POINT;
        maxRelExitValuation = 75 * BASIS_POINT;
        super.setUp();
    }
}