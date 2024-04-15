// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Aura_ezETH_xwstETH is BaseSingleSidedLPVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Aura_ezETH_xwstETH();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1e18;
        maxDeposit = 25e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_SingleSidedLP_Aura_ezETH_xwstETH is 
ComposablePoolHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Aura:ezETH/[wstETH]';
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 20;
        params.liquidationRate = 103;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 500;
        params.maxRequiredAccountCollateralRatioBPS = 10000;
        params.maxDeleverageCollateralRatioBPS = 800;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 0.1e8;
        maxPrimaryBorrow = 1e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // ezETH
        token[0] = 0x2416092f143378750bb29b79eD961ab195CcEea5;
        oracle[0] = 0x58784379C844a00d4f572917D43f991c971F96ca;
        // wstETH
        token[1] = 0x5979D7b546E38E414F7E9822514be443A4800529;
        oracle[1] = 0x29aFB1043eD699A89ca0F0942ED6F6f65E794A3d;
        
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
        EXISTING_DEPLOYMENT = 0xD7c3Dc1C36d19cF4e8cea4eA143a2f4458Dd1937;
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 5;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 3000,
            oraclePriceDeviationLimitPercent: 0.015e4
        });
        _m.rewardPool = IERC20(0xC3c454095A988013C4D1a9166C345f7280332E1A);

        

        _m.rewardTokens = new IERC20[](2);
        // AURA
        _m.rewardTokens[0] = IERC20(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
        // BAL
        _m.rewardTokens[1] = IERC20(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Aura_ezETH_xwstETH is Harness_SingleSidedLP_Aura_ezETH_xwstETH, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Aura_ezETH_xwstETH();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}