// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Aura_ezETH_xWETH is VaultRewarderTests {
    function _stringEqual(string memory a, string memory b) private pure returns(bool) {
      return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function _shouldSkip(string memory name) internal pure override returns(bool) {
        if (_stringEqual(name, "test_claimReward_ShouldNotClaimMoreThanTotalIncentives")) return true;
        if (_stringEqual(name, "test_claimReward_UpdateRewardTokenShouldBeAbleToReduceOrIncreaseEmission")) return true;
        
        return false;
    }

    function setUp() public override {
        harness = new Harness_SingleSidedLP_Aura_ezETH_xWETH();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1e18;
        maxDeposit = 5e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_SingleSidedLP_Aura_ezETH_xWETH is 
ComposablePoolHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Aura:ezETH/[WETH]';
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 20;
        params.liquidationRate = 103;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 1400;
        params.maxRequiredAccountCollateralRatioBPS = 10000;
        params.maxDeleverageCollateralRatioBPS = 2700;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 30e8;
        maxPrimaryBorrow = 250e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // ezETH
        token[0] = 0xbf5495Efe5DB9ce00f80364C8B423567e58d2110;
        oracle[0] = 0xCa140AE5a361b7434A729dCadA0ea60a50e249dd;
        // ETH
        token[1] = 0x0000000000000000000000000000000000000000;
        oracle[1] = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
        
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
        EXISTING_DEPLOYMENT = 0x914255c0c289AEa36E378EBB5e28293b5ED278Ca;
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 1;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 3000,
            oraclePriceDeviationLimitPercent: 0.015e4,
            numRewardTokens: 0,
            forceClaimAfter: 1 days
        });
        _m.rewardPool = IERC20(0x95eC73Baa0eCF8159b4EE897D973E41f51978E50);

        

        _m.rewardTokens = new IERC20[](2);
        // AURA
        _m.rewardTokens[0] = IERC20(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);
        // BAL
        _m.rewardTokens[1] = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Aura_ezETH_xWETH is Harness_SingleSidedLP_Aura_ezETH_xWETH, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Aura_ezETH_xWETH();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}