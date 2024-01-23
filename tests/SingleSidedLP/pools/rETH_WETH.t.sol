// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../BaseComposablePool.sol";

abstract contract rETH_WETH is BaseComposablePool {
    function getRequiredOracles() internal override view virtual returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // rETH
        token[0] = 0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8;
        // Notional Chainlink rETH/USD
        oracle[0] = 0x01713633a1b85a4a3d2f9430C68Bd4392c4a90eA;

        // WETH
        token[1] = 0x0000000000000000000000000000000000000000;
        // Chainlink WETH/USD
        oracle[1] = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    }

    function initVariables() override internal {
        rewardPool = IERC20(0x129A44AC6ff0f965C907579F96F2eD682E52c84A);
        settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 100
        });
    }

    function setUp() public override virtual {
        initVariables();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.001e18;
        maxDeposit = 1e18;
        maxRelEntryValuation = 75 * BASIS_POINT;
        maxRelExitValuation = 75 * BASIS_POINT;
        super.setUp();
    }
}

contract Test_rETH is rETH_WETH {
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Aura:[rETH]/WETH';
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
        params.maxRequiredAccountCollateralRatioBPS = 10_000;
        params.maxDeleverageCollateralRatioBPS = 1500;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 2e8;
        maxPrimaryBorrow = 100e8;
    }

    function setUp() public override { 
        EXISTING_DEPLOYMENT = 0x3Df035433cFACE65b6D68b77CC916085d020C8B8;
        primaryBorrowCurrency = RETH;
        super.setUp();
    }
}