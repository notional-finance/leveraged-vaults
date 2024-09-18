// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Aura_xUSDC_DAI_USDT_USDC_e is VaultRewarderTests {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Aura_xUSDC_DAI_USDT_USDC_e();

        WHALE = 0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D;
        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1e6;
        maxDeposit = 50_000e6;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 15 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_SingleSidedLP_Aura_xUSDC_DAI_USDT_USDC_e is 
ComposablePoolHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Aura:[USDC]/DAI/USDT/USDC.e';
    }

    function getDeploymentConfig() public view override returns (
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
        params.minAccountBorrowSize = 5_000e8;
        maxPrimaryBorrow = 300_000e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](4);
        oracle = new address[](4);

        // USDC
        token[0] = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        oracle[0] = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
        // DAI
        token[1] = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
        oracle[1] = 0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB;
        // USDT
        token[2] = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        oracle[2] = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;
        // USDC_e
        token[3] = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
        oracle[3] = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
        
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
        EXISTING_DEPLOYMENT = 0x8Ae7A8789A81A43566d0ee70264252c0DB826940;
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 3;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 5000,
            oraclePriceDeviationLimitPercent: 100,
            numRewardTokens: 0,
            forceClaimAfter: 1 days
        });
        _m.rewardPool = IERC20(0x416C7Ad55080aB8e294beAd9B8857266E3B3F28E);

        

        _m.rewardTokens = new IERC20[](2);
        // AURA
        _m.rewardTokens[0] = IERC20(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
        // BAL
        _m.rewardTokens[1] = IERC20(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Aura_xUSDC_DAI_USDT_USDC_e is Harness_SingleSidedLP_Aura_xUSDC_DAI_USDT_USDC_e, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Aura_xUSDC_DAI_USDT_USDC_e();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}