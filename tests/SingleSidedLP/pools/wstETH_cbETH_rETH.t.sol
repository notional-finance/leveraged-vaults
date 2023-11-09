// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../BaseComposablePool.sol";

abstract contract wstETH_cbETH_rETH is BaseComposablePool {
    function setUp() public override virtual {
        rewardPool = IERC20(0x8cA64Bd82AbFE138E195ce5Cb7268CA285D42245);
        settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 100
        });

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.001e18;
        maxDeposit = 1e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;
        super.setUp();
    }
}

contract Test_wstETH is wstETH_cbETH_rETH {
    function setUp() public override { primaryBorrowCurrency = WSTETH; super.setUp(); }

    // Only run one sell token reinvestment test since it requires a bunch of trade setup
    function test_RewardReinvestmentSellTokens() public {
        address account = makeAddr("account");
        address reward = makeAddr("reward");
        uint256 maturity = maturities[0];
        enterVaultBypass(account, maxDeposit, maturity, getDepositParams(0, 0));

        bytes32 role = v().REWARD_REINVESTMENT_ROLE();
        vm.prank(NOTIONAL.owner());
        v().grantRole(role, reward);

        skip(3600);
        assertEq(rewardToken.balanceOf(address(vault)), 0);
        vm.prank(reward);
        v().claimRewardTokens();
        uint256 rewardBalance = rewardToken.balanceOf(address(vault));
        assertGe(rewardBalance, 0);

        uint256 primaryIndex = v().getStrategyVaultInfo().singleSidedTokenIndex;
        SingleSidedRewardTradeParams[] memory t = new SingleSidedRewardTradeParams[](numTokens);
        for (uint256 i; i < t.length; i++) {
            t[i].sellToken = address(rewardToken);
            if (i == primaryIndex) {
                t[i].buyToken = address(primaryBorrowToken);
                t[i].amount = rewardBalance;
                t[i].tradeParams.dexId = uint16(DexId.BALANCER_V2);
                t[i].tradeParams.tradeType = TradeType.EXACT_IN_SINGLE;
                t[i].tradeParams.oracleSlippagePercentOrLimit = 0;
                // This is some crazy pool with wstETH and BAL in it
                t[i].tradeParams.exchangeData = abi.encode(
                    BalancerV2Adapter.SingleSwapData(
                        0x49b2de7d214070893c038299a57bac5acb8b8a340001000000000000000004be
                    )
                );
            }
        }

        vm.prank(NOTIONAL.owner());
        TRADING_MODULE.setTokenPermissions(
            address(vault),
            address(rewardToken),
            ITradingModule.TokenPermissions({ allowSell: true, dexFlags: 16, tradeTypeFlags: 15})
        );
        
        int256 exRateBefore = v().getExchangeRate(maturity);
        vm.prank(reward);
        (address r, uint256 amountSold, uint256 poolClaim) = v().reinvestReward(t, 0);
        int256 exRateAfter = v().getExchangeRate(maturity);
        assertEq(r, address(rewardToken));
        assertGt(poolClaim, 0);
        assertEq(amountSold, rewardBalance);
        assertGt(exRateAfter, exRateBefore);
    }

}

contract Test_cbETH is wstETH_cbETH_rETH {
    function setUp() public override { primaryBorrowCurrency = CBETH; super.setUp(); }
}

contract Test_rETH is wstETH_cbETH_rETH {
    function setUp() public override {
        primaryBorrowCurrency = RETH; 
        super.setUp();

        maxRelEntryValuation = 75 * BASIS_POINT;
        maxRelExitValuation = 100 * BASIS_POINT;
    }
}