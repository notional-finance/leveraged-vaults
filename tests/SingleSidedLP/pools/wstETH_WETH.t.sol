// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../BaseComposablePool.sol";

abstract contract wstETH_WETH is BaseComposablePool {
    function getRequiredOracles() internal override view virtual returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // wstETH
        token[0] = 0x5979D7b546E38E414F7E9822514be443A4800529;
        // Notional Chainlink wstETH/USD
        oracle[0] = 0x29aFB1043eD699A89ca0F0942ED6F6f65E794A3d;

        // WETH
        token[1] = 0x0000000000000000000000000000000000000000;
        // Chainlink WETH/USD
        oracle[1] = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    }

    function initVariables() override internal {
        rewardPool = IERC20(0xa7BdaD177D474f946f3cDEB4bcea9d24Cf017471);
        settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 3000,
            oraclePriceDeviationLimitPercent: 100
        });
    }

    function setUp() public override virtual {
        initVariables();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1000e8;
        maxDeposit = 1e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;
        super.setUp();
    }
}

contract Test_wstETH is wstETH_WETH {
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Aura:[wstETH]/WETH';
    }

    function setUp() public override { primaryBorrowCurrency = WSTETH; super.setUp(); }

    function test_TradeBeforeRestore() public {
        (uint256[] memory exitBalances, /* */, /* */) = setup_EmergencyExit();
        // Token 0 = wstETH
        // Token 1 = WETH
        (IERC20[] memory tokens, /* */) = v().TOKENS();

        SingleSidedRewardTradeParams[] memory t = new SingleSidedRewardTradeParams[](2);
        t[0].sellToken = address(tokens[0]);
        t[0].buyToken = address(tokens[0]);
        t[0].amount = 0;
        t[0].tradeParams.dexId = uint16(DexId.BALANCER_V2);
        t[0].tradeParams.tradeType = TradeType.EXACT_IN_SINGLE;
        t[0].tradeParams.oracleSlippagePercentOrLimit = 0;
        t[0].tradeParams.exchangeData = abi.encode(
            BalancerV2Adapter.SingleSwapData(balancerPoolId)
        );

        t[1].sellToken = address(tokens[0]);
        t[1].buyToken = address(tokens[1]);
        t[1].amount = exitBalances[0] / 2;
        t[1].tradeParams.dexId = uint16(DexId.BALANCER_V2);
        t[1].tradeParams.tradeType = TradeType.EXACT_IN_SINGLE;
        t[1].tradeParams.oracleSlippagePercentOrLimit = 0;
        t[1].tradeParams.exchangeData = abi.encode(
            BalancerV2Adapter.SingleSwapData(balancerPoolId)
        );

        vm.prank(NOTIONAL.owner());
        TRADING_MODULE.setTokenPermissions(
            address(vault),
            address(tokens[0]),
            ITradingModule.TokenPermissions({ allowSell: true, dexFlags: 16, tradeTypeFlags: 15})
        );

        vm.prank(NOTIONAL.owner());
        v().tradeTokensBeforeRestore(t);
        assertGt(exitBalances[0], tokens[0].balanceOf(address(vault)));
        assertLt(exitBalances[1], address(vault).balance);
    }
}

contract Test_WETH is wstETH_WETH {
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Aura:wstETH/[WETH]';
    }

    function getDeploymentConfig() internal view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 10;
        params.liquidationRate = 102;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 500;
        params.maxRequiredAccountCollateralRatioBPS = 10_000;
        params.maxDeleverageCollateralRatioBPS = 800;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 0.1e8;
        maxPrimaryBorrow = 1e8;
    }

    function setUp() public override { 
        EXISTING_DEPLOYMENT = 0x0E8C1A069f40D0E8Fa861239D3e62003cBF3dCB2;
        primaryBorrowCurrency = ETH;
        super.setUp();
    }
}