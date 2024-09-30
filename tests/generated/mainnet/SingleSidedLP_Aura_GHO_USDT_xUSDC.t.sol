// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Aura_GHO_USDT_xUSDC is VaultRewarderTests {
    function setUp() public override {
        FORK_BLOCK = 20864646;
        harness = new Harness_SingleSidedLP_Aura_GHO_USDT_xUSDC();

        WHALE = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1_000e6;
        maxDeposit = 50_000e6;
        maxRelEntryValuation = 75 * BASIS_POINT;
        maxRelExitValuation = 75 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_SingleSidedLP_Aura_GHO_USDT_xUSDC is 
ComposablePoolHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Aura:GHO/USDT/[USDC]';
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
        params.maxDeleverageCollateralRatioBPS = 2600;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 100_000e8;
        maxPrimaryBorrow = 750_000e8;
    }

    function getRequiredOracles() public override pure returns (
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

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](3);
        permissions = new ITradingModule.TokenPermissions[](3);

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
        // GHO
        token[2] = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
        permissions[2] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        

        
    }

    constructor() {
        EXISTING_DEPLOYMENT = 0xeEB885Af7C8075Aa3b93e2F95E1c0bD51c758F91;
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 3;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 3500,
            oraclePriceDeviationLimitPercent: 0.015e4,
            numRewardTokens: 0,
            forceClaimAfter: 1 days
        });
        _m.rewardPool = IERC20(0xBDD6984C3179B099E9D383ee2F44F3A57764BF7d);
        _m.whitelistedReward = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
        

        

        _m.rewardTokens = new IERC20[](3);
        // AURA
        _m.rewardTokens[0] = IERC20(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);
        // BAL
        _m.rewardTokens[1] = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);
        // GHO
        _m.rewardTokens[2] = IERC20(0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Aura_GHO_USDT_xUSDC is Harness_SingleSidedLP_Aura_GHO_USDT_xUSDC, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Aura_GHO_USDT_xUSDC();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}