// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Aura_wstETH_xWETH is VaultRewarderTests {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Aura_wstETH_xWETH();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.01e18;
        maxDeposit = 1e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_SingleSidedLP_Aura_wstETH_xWETH is 
ComposablePoolHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Aura:wstETH/[WETH]';
    }

    function getDeploymentConfig() public view override returns (
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

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // wstETH
        token[0] = 0x5979D7b546E38E414F7E9822514be443A4800529;
        oracle[0] = 0x29aFB1043eD699A89ca0F0942ED6F6f65E794A3d;
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
        EXISTING_DEPLOYMENT = 0x0E8C1A069f40D0E8Fa861239D3e62003cBF3dCB2;
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 1;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 3000,
            oraclePriceDeviationLimitPercent: 100,
            numRewardTokens: 0,
            forceClaimAfter: 1 days
        });
        _m.rewardPool = IERC20(0xa7BdaD177D474f946f3cDEB4bcea9d24Cf017471);

        

        _m.rewardTokens = new IERC20[](2);
        // AURA
        _m.rewardTokens[0] = IERC20(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
        // BAL
        _m.rewardTokens[1] = IERC20(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Aura_wstETH_xWETH is Harness_SingleSidedLP_Aura_wstETH_xWETH, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Aura_wstETH_xWETH();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}