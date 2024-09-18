// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Aura_rETH_xWETH is VaultRewarderTests {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Aura_rETH_xWETH();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.01e18;
        maxDeposit = 1e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_SingleSidedLP_Aura_rETH_xWETH is 
ComposablePoolHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Aura:rETH/[WETH]';
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 10;
        params.liquidationRate = 102;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 1400;
        params.maxRequiredAccountCollateralRatioBPS = 10000;
        params.maxDeleverageCollateralRatioBPS = 2600;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 0.1e8;
        maxPrimaryBorrow = 1e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // rETH
        token[0] = 0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8;
        oracle[0] = 0x40cf45dBD4813be545CF3E103eF7ef531eac7283;
        // ETH
        token[1] = 0x0000000000000000000000000000000000000000;
        oracle[1] = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
        
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
        EXISTING_DEPLOYMENT = 0xA0d61c08e642103158Fc6a1495E7Ff82bAF25857;
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 1;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 3000,
            oraclePriceDeviationLimitPercent: 0.01e4,
            numRewardTokens: 0,
            forceClaimAfter: 1 days
        });
        _m.rewardPool = IERC20(0x17F061160A167d4303d5a6D32C2AC693AC87375b);

        

        _m.rewardTokens = new IERC20[](2);
        // AURA
        _m.rewardTokens[0] = IERC20(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
        // BAL
        _m.rewardTokens[1] = IERC20(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Aura_rETH_xWETH is Harness_SingleSidedLP_Aura_rETH_xWETH, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Aura_rETH_xWETH();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}