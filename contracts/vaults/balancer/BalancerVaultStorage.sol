// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {Constants} from "../../global/Constants.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {BaseStrategyVault} from "../BaseStrategyVault.sol";

import {
    DeploymentParams,
    InitParams,
    StrategyVaultSettings,
    StrategyVaultState,
    SettlementState
} from "./BalancerVaultTypes.sol";
import {Token} from "../../global/Types.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";
import {IBalancerPool} from "../../../interfaces/balancer/IBalancerPool.sol";
import {IAuraBooster} from "../../../interfaces/aura/IAuraBooster.sol";
import {IAuraRewardPool} from "../../../interfaces/aura/IAuraRewardPool.sol";
import {IAuraStakingProxy} from "../../../interfaces/aura/IAuraStakingProxy.sol";
import {ILiquidityGauge} from "../../../interfaces/balancer/ILiquidityGauge.sol";
import {IBalancerMinter} from "../../../interfaces/balancer/IBalancerMinter.sol";
import {IPriceOracle} from "../../../interfaces/balancer/IPriceOracle.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";

abstract contract BalancerVaultStorage is BaseStrategyVault {
    error InvalidPrimaryToken(address token);
    error InvalidSecondaryToken(address token);

    /** Immutables */
    uint16 internal immutable SECONDARY_BORROW_CURRENCY_ID;
    bytes32 internal immutable BALANCER_POOL_ID;
    IBalancerPool internal immutable BALANCER_POOL_TOKEN;
    IERC20 internal immutable SECONDARY_TOKEN;
    ILiquidityGauge internal immutable LIQUIDITY_GAUGE;
    IAuraBooster internal immutable AURA_BOOSTER;
    IAuraRewardPool internal immutable AURA_REWARD_POOL;
    uint256 internal immutable AURA_POOL_ID;
    IERC20 internal immutable BAL_TOKEN;
    IERC20 internal immutable AURA_TOKEN;
    uint8 internal immutable PRIMARY_INDEX;
    uint32 internal immutable SETTLEMENT_PERIOD_IN_SECONDS;
    uint256 internal immutable PRIMARY_WEIGHT;
    uint256 internal immutable SECONDARY_WEIGHT;
    uint8 internal immutable PRIMARY_DECIMALS;
    uint8 internal immutable SECONDARY_DECIMALS;
    uint256 internal immutable MAX_ORACLE_QUERY_WINDOW;
    address internal immutable FEE_RECEIVER;

    StrategyVaultSettings internal strategyVaultSettings;

    StrategyVaultState internal strategyVaultState;

    /// @notice Keeps track of settlement data per maturity
    mapping(uint256 => SettlementState) internal settlementState;

    constructor(NotionalProxy notional_, DeploymentParams memory params) 
        BaseStrategyVault(notional_, params.tradingModule)
    {
        address primaryBorrowToken = BalancerUtils.getTokenAddress(address(_underlyingToken()));

        SECONDARY_BORROW_CURRENCY_ID = params.secondaryBorrowCurrencyId;
        BALANCER_POOL_ID = params.balancerPoolId;
        {
            (address pool, /* */) = BalancerUtils.BALANCER_VAULT.getPool(params.balancerPoolId);
            BALANCER_POOL_TOKEN = IBalancerPool(pool);

            // The oracle is required for the vault to behave properly
            (/* */, /* */, /* */, /* */, bool oracleEnabled, /* */) = BALANCER_POOL_TOKEN.getMiscData();
            require(oracleEnabled);
        }

        // prettier-ignore
        (
            address[] memory tokens,
            /* uint256[] memory balances */,
            /* uint256 lastChangeBlock */
        ) = BalancerUtils.BALANCER_VAULT.getPoolTokens(BALANCER_POOL_ID);

        // Balancer tokens are sorted by address, so we need to figure out
        // the correct index for the primary token
        PRIMARY_INDEX = tokens[0] == primaryBorrowToken ? 0 : 1;
        uint8 secondaryIndex;
        unchecked {
            secondaryIndex = 1 - PRIMARY_INDEX;
        }

        // Since this is always a 2-token vault, SECONDARY_INDEX = 1-PRIMARY_INDEX
        SECONDARY_TOKEN = SECONDARY_BORROW_CURRENCY_ID > 0
            ? IERC20(_getNotionalUnderlyingToken(SECONDARY_BORROW_CURRENCY_ID))
            : IERC20(tokens[secondaryIndex]);

        // Make sure the deployment parameters are correct
        if (tokens[PRIMARY_INDEX] != primaryBorrowToken) {
            revert InvalidPrimaryToken(tokens[PRIMARY_INDEX]);
        }

        if (tokens[secondaryIndex] !=
            BalancerUtils.getTokenAddress(address(SECONDARY_TOKEN))
        ) revert InvalidSecondaryToken(tokens[secondaryIndex]);

        // If the underlying is ETH, primaryBorrowToken will be rewritten as WETH
        uint256 primaryDecimals = IERC20(primaryBorrowToken).decimals();
        // Do not allow decimal places greater than 18
        require(primaryDecimals <= 18);
        PRIMARY_DECIMALS = uint8(primaryDecimals);

        uint256 secondaryDecimals = address(SECONDARY_TOKEN) ==
            Constants.ETH_ADDRESS
            ? 18
            : SECONDARY_TOKEN.decimals();
        require(primaryDecimals <= 18);
        SECONDARY_DECIMALS = uint8(secondaryDecimals);

        uint256[] memory weights = BALANCER_POOL_TOKEN.getNormalizedWeights();

        PRIMARY_WEIGHT = weights[PRIMARY_INDEX];
        SECONDARY_WEIGHT = weights[secondaryIndex];

        LIQUIDITY_GAUGE = params.liquidityGauge;
        AURA_REWARD_POOL = params.auraRewardPool;
        AURA_BOOSTER = IAuraBooster(AURA_REWARD_POOL.operator());
        AURA_POOL_ID = AURA_REWARD_POOL.pid();

        IAuraStakingProxy stakingProxy = IAuraStakingProxy(AURA_BOOSTER.stakerRewards());
        BAL_TOKEN = IERC20(stakingProxy.crv());
        AURA_TOKEN = IERC20(stakingProxy.cvx());

        SETTLEMENT_PERIOD_IN_SECONDS = params.settlementPeriodInSeconds;
        FEE_RECEIVER = params.feeReceiver;

        MAX_ORACLE_QUERY_WINDOW = IPriceOracle(address(BALANCER_POOL_TOKEN)).getLargestSafeQueryWindow();
        require(MAX_ORACLE_QUERY_WINDOW <= type(uint32).max); /// @dev largestQueryWindow overflow
    }

    // Storage gap for future potential upgrades
    uint256[100] private __gap;
}