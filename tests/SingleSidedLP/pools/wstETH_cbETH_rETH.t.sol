// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../BaseComposablePool.sol";

abstract contract wstETH_cbETH_rETH is BaseComposablePool {
    function getRequiredOracles() internal override view virtual returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](3);
        oracle = new address[](3);

        // wstETH
        token[0] = 0x5979D7b546E38E414F7E9822514be443A4800529;
        // Notional Chainlink wstETH/USD (via stETH/wstETH exchange rate)
        oracle[0] = 0x29aFB1043eD699A89ca0F0942ED6F6f65E794A3d;

        // cbETH
        token[1] = 0x1DEBd73E752bEaF79865Fd6446b0c970EaE7732f;
        // Notional Chainlink cbETH/USD
        oracle[1] = 0x4763672dEa3bF087929d5537B6BAfeB8e6938F46;

        // rETH
        token[2] = 0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8;
        // Notional Chainlink rETH/USD
        oracle[2] = 0x40cf45dBD4813be545CF3E103eF7ef531eac7283;
    }

    function initVariables() override internal {
        rewardPool = IERC20(0x8cA64Bd82AbFE138E195ce5Cb7268CA285D42245);
        settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 0.2e4,
            oraclePriceDeviationLimitPercent: 0.01e4
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

contract Test_wstETH is wstETH_cbETH_rETH {
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Aura:[wstETH]/cbETH/rETH';
    }

    function getDeploymentConfig() internal view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 10;
        params.liquidationRate = 102;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 1_000;
        params.maxRequiredAccountCollateralRatioBPS = 10_000;
        params.maxDeleverageCollateralRatioBPS = 1_700;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 0.1e8;
        maxPrimaryBorrow = 2e8;
    }

    function setUp() public override { 
        EXISTING_DEPLOYMENT=0x37dD23Ab1885982F789A2D6400B583B8aE09223d;
        primaryBorrowCurrency = WSTETH;
        super.setUp();
    }

    function test_RevertIf_ReinvestRewardNoVaultShares() public {
        address account = makeAddr("account");
        address reward = makeAddr("reward");
        uint256 maturity = maturities[0];
        uint256 vaultShares = enterVaultBypass(account, maxDeposit, maturity, getDepositParams(0, 0));

        bytes32 role = REWARD_REINVESTMENT_ROLE;
        vm.prank(NOTIONAL.owner());
        v().grantRole(role, reward);

        skip(3600);
        assertEq(rewardToken.balanceOf(address(vault)), 0);
        vm.prank(reward);
        v().claimRewardTokens();
        uint256 rewardBalance = rewardToken.balanceOf(address(vault));
        assertGe(rewardBalance, 0);

        exitVaultBypass(account, vaultShares, maturity, getRedeemParams(0, 0));

        uint256 totalVaultShares = v().getStrategyVaultInfo().totalVaultShares;
        assertEq(totalVaultShares, 0);

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
        
        // Cannot reinvest if vault shares is zero
        vm.prank(reward);
        vm.expectRevert();
        v().reinvestReward(t, 0);
    }

    // Only run one sell token reinvestment test since it requires a bunch of trade setup
    function test_RewardReinvestmentSellTokens() public {
        address account = makeAddr("account");
        address reward = makeAddr("reward");
        uint256 maturity = maturities[0];
        enterVaultBypass(account, maxDeposit, maturity, getDepositParams(0, 0));

        vm.prank(NOTIONAL.owner());
        v().grantRole(REWARD_REINVESTMENT_ROLE, reward);

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
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Aura:wstETH/[cbETH]/rETH';
    }

    function setUp() public override { primaryBorrowCurrency = CBETH; super.setUp(); }
}

contract Test_rETH is wstETH_cbETH_rETH {
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Aura:wstETH/cbETH/[rETH]';
    }

    function setUp() public override {
        primaryBorrowCurrency = RETH; 
        super.setUp();

        maxRelEntryValuation = 75 * BASIS_POINT;
        maxRelExitValuation = 100 * BASIS_POINT;
    }
}