// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    ComposableOracleContext,
    AuraVaultDeploymentParams,
    BalancerComposablePoolContext,
    BalancerComposableAuraStrategyContext,
    AuraStakingContext
} from "../BalancerVaultTypes.sol";
import {StrategyContext, ComposablePoolContext} from "../../common/VaultTypes.sol";
import {TypeConvert} from "../../../global/TypeConvert.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";
import {ISingleSidedLPStrategyVault} from "../../../../interfaces/notional/IStrategyVault.sol";
import {IBalancerPool, IComposablePool} from "../../../../interfaces/balancer/IBalancerPool.sol";
import {Deployments} from "../../../global/Deployments.sol";
import {BalancerPoolMixin} from "./BalancerPoolMixin.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {StableMath} from "../internal/math/StableMath.sol";
import {ComposableAuraHelper} from "../external/ComposableAuraHelper.sol";

/**
 * Base class for all Balancer composable pools
 */
abstract contract BalancerComposablePoolMixin is BalancerPoolMixin, ISingleSidedLPStrategyVault {
    using TypeConvert for uint256;

    error InvalidPrimaryToken(address token);

    uint8 internal constant NOT_FOUND = type(uint8).max;
    uint256 internal constant MAX_TOKENS = 5;

    /// @notice primary token index
    uint8 internal immutable PRIMARY_INDEX;
    /// @notice pool token index
    uint8 internal immutable BPT_INDEX;
    /// @notice this implementation currently supports up to 5 tokens
    address internal immutable TOKEN_1;
    address internal immutable TOKEN_2;
    address internal immutable TOKEN_3;
    address internal immutable TOKEN_4;
    address internal immutable TOKEN_5;
    uint8 internal immutable DECIMALS_1;
    uint8 internal immutable DECIMALS_2;
    uint8 internal immutable DECIMALS_3;
    uint8 internal immutable DECIMALS_4;
    uint8 internal immutable DECIMALS_5;
    /// @notice keep track of the total number of tokens
    uint8 internal immutable NUM_TOKENS;

    constructor(NotionalProxy notional_, AuraVaultDeploymentParams memory params)
        BalancerPoolMixin(notional_, params) {
        // get primary address from currency ID
        address primaryAddress = _getNotionalUnderlyingToken(params.baseParams.primaryBorrowCurrencyId);

        // prettier-ignore
        (
            address[] memory tokens,
            /* uint256[] memory balances */,
            /* uint256 lastChangeBlock */
        ) = Deployments.BALANCER_VAULT.getPoolTokens(params.baseParams.balancerPoolId);

        require(tokens.length <= MAX_TOKENS);
        NUM_TOKENS = uint8(tokens.length);

        TOKEN_1 = NUM_TOKENS > 0 ? tokens[0] : address(0);
        TOKEN_2 = NUM_TOKENS > 1 ? tokens[1] : address(0);
        TOKEN_3 = NUM_TOKENS > 2 ? tokens[2] : address(0);
        TOKEN_4 = NUM_TOKENS > 3 ? tokens[3] : address(0);
        TOKEN_5 = NUM_TOKENS > 4 ? tokens[4] : address(0);

        uint8 primaryIndex = NOT_FOUND;
        uint8 bptIndex = NOT_FOUND;
        for (uint8 i; i < NUM_TOKENS; i++) {
            if (tokens[i] == primaryAddress) {
                primaryIndex = i; 
            } else if (tokens[i] == address(BALANCER_POOL_TOKEN)) {
                bptIndex = i;
            }
        }

        // make sure primary index and BPT index exist
        require(primaryIndex != NOT_FOUND);
        require(bptIndex != NOT_FOUND);

        PRIMARY_INDEX = primaryIndex;
        BPT_INDEX = bptIndex;

        DECIMALS_1 = _getTokenDecimals(TOKEN_1);
        DECIMALS_2 = _getTokenDecimals(TOKEN_2);
        DECIMALS_3 = _getTokenDecimals(TOKEN_3);
        DECIMALS_4 = _getTokenDecimals(TOKEN_4);
        DECIMALS_5 = _getTokenDecimals(TOKEN_5);
    }

    /// @notice gets the token decimals
    /// @param token token address
    /// @return decimals token decimals
    function _getTokenDecimals(address token) private view returns (uint8 decimals) {
        if (token == address(0)) return 0;

        decimals = (token == Deployments.ETH_ADDRESS) ? 18 : IERC20(token).decimals();
        require(decimals <= 18);
    }

    /// @notice returns the composable pool context    
    function _composablePoolContext() 
        internal view returns (BalancerComposablePoolContext memory) {
        (
            /* address[] memory tokens */,
            uint256[] memory balances,
            /* uint256 lastChangeBlock */
        ) = Deployments.BALANCER_VAULT.getPoolTokens(BALANCER_POOL_ID);

        uint256[] memory scalingFactors = IBalancerPool(address(BALANCER_POOL_TOKEN)).getScalingFactors();

        address[] memory tokens = new address[](NUM_TOKENS);
        uint8[] memory decimals = new uint8[](NUM_TOKENS);

        // Assign token addresses and decimals
        if (NUM_TOKENS > 0) (tokens[0], decimals[0]) = (TOKEN_1, DECIMALS_1);
        if (NUM_TOKENS > 1) (tokens[1], decimals[1]) = (TOKEN_2, DECIMALS_2);
        if (NUM_TOKENS > 2) (tokens[2], decimals[2]) = (TOKEN_3, DECIMALS_3);
        if (NUM_TOKENS > 3) (tokens[3], decimals[3]) = (TOKEN_4, DECIMALS_4);
        if (NUM_TOKENS > 4) (tokens[4], decimals[4]) = (TOKEN_5, DECIMALS_5);

        return BalancerComposablePoolContext({
            basePool: ComposablePoolContext({
                tokens: tokens,
                balances: balances,
                decimals: decimals,
                poolToken: BALANCER_POOL_TOKEN,
                primaryIndex: PRIMARY_INDEX
            }),
            poolId: BALANCER_POOL_ID,
            scalingFactors: scalingFactors,
            bptIndex: BPT_INDEX
        });
    }

    /// @notice returns the composable oracle context
    function _composableOracleContext() internal view returns (ComposableOracleContext memory) {
        IComposablePool pool = IComposablePool(address(BALANCER_POOL_TOKEN));

        (
            uint256 value,
            /* bool isUpdating */,
            uint256 precision
        ) = IComposablePool(address(BALANCER_POOL_TOKEN)).getAmplificationParameter();
        require(precision == StableMath._AMP_PRECISION);
        
        return ComposableOracleContext({
            ampParam: value,
            virtualSupply: pool.getActualSupply()
        });
    }

    /// @notice returns the composable pool strategy context
    function _strategyContext() internal view returns (BalancerComposableAuraStrategyContext memory) {
        return BalancerComposableAuraStrategyContext({
            poolContext: _composablePoolContext(),
            oracleContext: _composableOracleContext(),
            stakingContext: _auraStakingContext(),
            baseStrategy: _baseStrategyContext()
        });
    }

    /// @notice returns the value of 1 vault share
    /// @return exchange rate of 1 vault share
    function getExchangeRate(uint256 /* maturity */) public view override returns (int256) {
        BalancerComposableAuraStrategyContext memory context = _strategyContext();
        return ComposableAuraHelper.getExchangeRate(context);
    }

    /// @notice returns strategy vault information for the UI
    function getStrategyVaultInfo() public view override returns (SingleSidedLPStrategyVaultInfo memory) {
        StrategyContext memory context = _baseStrategyContext();
        return SingleSidedLPStrategyVaultInfo({
            pool: address(BALANCER_POOL_TOKEN),
            singleSidedTokenIndex: PRIMARY_INDEX,
            totalLPTokens: context.vaultState.totalPoolClaim,
            totalVaultShares: context.vaultState.totalVaultSharesGlobal
        });
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}
