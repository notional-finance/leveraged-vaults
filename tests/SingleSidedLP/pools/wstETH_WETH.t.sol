// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../BaseComposablePool.sol";

abstract contract wstETH_WETH is BaseComposablePool {
    function initVariables() override internal {
        rewardPool = IERC20(0xa7BdaD177D474f946f3cDEB4bcea9d24Cf017471);
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

    function setUp() public override { primaryBorrowCurrency = ETH; super.setUp(); }
}