// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../BaseWeightedPool.sol";

abstract contract RDNT_WETH is BaseWeightedPool {

    function initVariables() override internal {
        rewardPool = IERC20(0xa17492d89cB2D0bE1dDbd0008F8585EDc5B0ACf3);
        settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 200
        });
    }

    function setUp() public override virtual {
        initVariables();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.001e18;
        maxDeposit = 50e18;
        maxRelEntryValuation = 75 * BASIS_POINT;
        maxRelExitValuation = 75 * BASIS_POINT;
        super.setUp();

        // Lists RDNT Oracle
        vm.prank(NOTIONAL.owner());
        TRADING_MODULE.setPriceOracle(
            0x3082CC23568eA640225c2467653dB90e9250AaA0,
            AggregatorV2V3Interface(0x20d0Fcab0ECFD078B036b6CAf1FaC69A6453b352)
        );
    }
}

contract Test_RDNT is RDNT_WETH {
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Aura:[RDNT]/WETH';
    }

    function setUp() public override { primaryBorrowCurrency = RDNT; super.setUp(); }
}
