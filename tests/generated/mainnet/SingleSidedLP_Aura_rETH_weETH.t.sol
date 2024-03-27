// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Aura_rETH_weETH is BaseSingleSidedLPVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Aura_rETH_weETH();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1e18;
        maxDeposit = 100e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_SingleSidedLP_Aura_rETH_weETH is 
ComposablePoolHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Aura:rETH/weETH';
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
        params.minAccountBorrowSize = 1e8;
        maxPrimaryBorrow = 5000e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // rETH
        token[0] = 0xae78736Cd615f374D3085123A210448E74Fc6393;
        oracle[0] = 0xA7D273951861CF07Df8B0A1C3c934FD41bA9E8Eb;
        // weETH
        token[1] = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
        oracle[1] = 0xdDb6F90fFb4d3257dd666b69178e5B3c5Bf41136;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](2);
        permissions = new ITradingModule.TokenPermissions[](2);

        // AURA
        token[0] = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;
        permissions[0] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        // BAL
        token[1] = 0xba100000625a3754423978a60c9317c58a424e3D;
        permissions[1] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        

        
    }

    constructor() {
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 7;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 0.015e4
        });
        _m.rewardPool = IERC20(0x07A319A023859BbD49CC9C38ee891c3EA9283Cc5);

        

        _m.rewardTokens = new IERC20[](2);
        // AURA
        _m.rewardTokens[0] = IERC20(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);
        // BAL
        _m.rewardTokens[1] = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Aura_rETH_weETH is Harness_SingleSidedLP_Aura_rETH_weETH, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Aura_rETH_weETH();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}