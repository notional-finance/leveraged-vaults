// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {Constants} from "../../global/Constants.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {BaseStrategyVault} from "../BaseStrategyVault.sol";

import {
    DeploymentParams,
    InitParams,
    StrategyVaultSettings,
    StrategyVaultState
} from "./BalancerVaultTypes.sol";
import {Token} from "../../global/Types.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";
import {IBalancerPool} from "../../../interfaces/balancer/IBalancerPool.sol";
import {IBoostController} from "../../../interfaces/notional/IBoostController.sol";
import {ILiquidityGauge} from "../../../interfaces/balancer/ILiquidityGauge.sol";
import {IVeBalDelegator} from "../../../interfaces/notional/IVeBalDelegator.sol";
import {IBalancerMinter} from "../../../interfaces/balancer/IBalancerMinter.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";

abstract contract BalancerVaultStorage is BaseStrategyVault {
    error InvalidPrimaryToken(address token);
    error InvalidSecondaryToken(address token);

    /** Immutables */
    uint16 internal immutable SECONDARY_BORROW_CURRENCY_ID;
    bytes32 internal immutable BALANCER_POOL_ID;
    IBalancerPool internal immutable BALANCER_POOL_TOKEN;
    IERC20 internal immutable SECONDARY_TOKEN;
    IBoostController internal immutable BOOST_CONTROLLER;
    ILiquidityGauge internal immutable LIQUIDITY_GAUGE;
    IVeBalDelegator internal immutable VEBAL_DELEGATOR;
    IERC20 internal immutable BAL_TOKEN;
    uint8 internal immutable PRIMARY_INDEX;
    uint32 internal immutable SETTLEMENT_PERIOD_IN_SECONDS;
    uint256 internal immutable PRIMARY_WEIGHT;
    uint256 internal immutable SECONDARY_WEIGHT;
    uint8 internal immutable PRIMARY_DECIMALS;
    uint8 internal immutable SECONDARY_DECIMALS;

    StrategyVaultSettings internal vaultSettings;

    StrategyVaultState internal vaultState;

    /// @notice Keeps track of the primary settlement balance maturity => balance
    mapping(uint256 => uint256) internal primarySettlementBalance;

    /// @notice Keeps track of the secondary settlement balance maturity => balance
    mapping(uint256 => uint256) internal secondarySettlementBalance;

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

        BOOST_CONTROLLER = params.boostController;
        LIQUIDITY_GAUGE = params.liquidityGauge;
        VEBAL_DELEGATOR = IVeBalDelegator(BOOST_CONTROLLER.VEBAL_DELEGATOR());
        BAL_TOKEN = IERC20(
            IBalancerMinter(VEBAL_DELEGATOR.BALANCER_MINTER())
                .getBalancerToken()
        );
        SETTLEMENT_PERIOD_IN_SECONDS = params.settlementPeriodInSeconds;
    }

    // Storage gap for future potential upgrades
    uint256[100] private __gap;
}