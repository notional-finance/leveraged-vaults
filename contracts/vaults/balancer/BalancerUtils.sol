// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    PoolContext, 
    OracleContext, 
    WeightedOracleContext, 
    TwoTokenPoolContext,
    AuraStakingContext,
    PoolParams
} from "./BalancerVaultTypes.sol";
import {IPriceOracle} from "../../../interfaces/balancer/IPriceOracle.sol";
import {IBalancerVault, IAsset} from "../../../interfaces/balancer/IBalancerVault.sol";
import {ITradingModule} from "../../../interfaces/trading/ITradingModule.sol";
import {Constants} from "../../global/Constants.sol";
import {WETH9} from "../../../interfaces/WETH9.sol";
import {TokenUtils, IERC20} from "../../utils/TokenUtils.sol";

library BalancerUtils {
    using TokenUtils for IERC20;

    WETH9 internal constant WETH =
        WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IBalancerVault internal constant BALANCER_VAULT =
        IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    uint256 internal constant BALANCER_PRECISION = 1e18;
    uint256 internal constant BALANCER_PRECISION_SQUARED = 1e36;
    uint256 internal constant BALANCER_ORACLE_WEIGHT_PRECISION = 1e8;

    error InvalidTokenIndex(uint256 tokenIndex);

    /// @notice Special handling for ETH because UNDERLYING_TOKEN == address(0)
    /// and Balancer uses WETH
    function getTokenAddress(address token) internal pure returns (address) {
        return token == Constants.ETH_ADDRESS ? address(WETH) : address(token);
    }

    function _getTimeWeightedOraclePrice(
        address pool,
        IPriceOracle.Variable variable,
        uint256 secs
    ) internal view returns (uint256) {
        IPriceOracle.OracleAverageQuery[]
            memory queries = new IPriceOracle.OracleAverageQuery[](1);

        queries[0].variable = variable;
        queries[0].secs = secs;
        queries[0].ago = 0; // now

        // Gets the balancer time weighted average price denominated in the first token
        return IPriceOracle(pool).getTimeWeightedAverage(queries)[0];
    }

    /// @notice Normalizes balances to 1e18 (used by Balancer price oracle functions)
    function _normalizeBalances(
        uint256 primaryBalance,
        uint8 primaryDecimals,
        uint256 secondaryBalance,
        uint8 secondaryDecimals
    ) internal pure returns (uint256 normalizedPrimary, uint256 normalizedSecondary) {
        if (primaryDecimals == 18) {
            normalizedPrimary = primaryBalance;
        } else {
            uint256 decimalAdjust;
            unchecked { 
                decimalAdjust = 10**(18 - primaryDecimals);
            }
            normalizedPrimary = primaryBalance * decimalAdjust;
        }

        if (secondaryDecimals == 18) {
            normalizedSecondary = secondaryBalance;
        } else {
            uint256 decimalAdjust;
            unchecked { 
                decimalAdjust = 10**(18 - secondaryDecimals);
            }
            normalizedSecondary = secondaryBalance * decimalAdjust;
        }
    }

    /// @notice Gets the time-weighted primary token balance for a given bptAmount
    /// @dev Balancer pool needs to be fully initialized with at least 1024 trades
    /// @param oracleContext oracle context variables
    /// @param poolContext pool context variables
    /// @param bptAmount amount of balancer pool lp tokens
    /// @return primaryAmount primary token balance
    function getTimeWeightedPrimaryBalance(
        WeightedOracleContext memory oracleContext,
        TwoTokenPoolContext memory poolContext,
        uint256 bptAmount
    ) 
        internal view returns (uint256 primaryAmount) {
        // Gets the BPT token price denominated in token index = 0
        uint256 bptPrice = _getTimeWeightedOraclePrice(
            address(poolContext.baseContext.pool),
            IPriceOracle.Variable.BPT_PRICE,
            oracleContext.baseContext.oracleWindowInSeconds
        );

        // Gets the pair price
        uint256 pairPrice = _getTimeWeightedOraclePrice(
            address(poolContext.baseContext.pool),
            IPriceOracle.Variable.PAIR_PRICE,
            oracleContext.baseContext.oracleWindowInSeconds
        );

        uint256 primaryPrecision = 10 ** poolContext.primaryDecimals;

        if (poolContext.primaryIndex == 0) {
            // Since bptPrice is always denominated in the first token, we can just multiply by
            // the amount in this case. Both bptPrice and bptAmount are in 1e18 but we need to scale
            // this back to the primary token's native precision.
            // underlyingValue = (bptPrice * bptAmount * primaryPrecision) / (1e18 * 1e18)
            primaryAmount = (bptPrice * bptAmount * primaryPrecision) / BALANCER_PRECISION_SQUARED;
        } else {
            // The second token in the BPT pool is the price that we want to get. In this case, we need to
            // convert secondaryTokenValue to underlyingValue using the pairPrice.
            // Both bptPrice and bptAmount are in 1e18
            uint256 secondaryAmount = (bptPrice * bptAmount) / BALANCER_PRECISION;

            // PairPrice = (SecondaryAmount / SecondaryWeight) / (PrimaryAmount / PrimaryWeight)
            // PairPrice = (SecondaryAmount * PrimaryWeight) / (PrimaryAmount * SecondaryWeight)
            // PrimaryAmount = (SecondaryAmount * PrimaryWeight) / (SecondaryWeight * PairPrice)

            // And then normalizing to primary token precision we add:
            // PrimaryAmount = (SecondaryAmount * PrimaryWeight * primaryPrecision) /
            //          (SecondaryWeight * PairPrice)
            primaryAmount = (secondaryAmount * oracleContext.primaryWeight * primaryPrecision) /
                (oracleContext.secondaryWeight * pairPrice);
        }
    }

    /// @notice Gets the oracle price pair price between two tokens using a weighted
    /// average between a chainlink oracle and the balancer TWAP oracle.
    /// @param oracleContext oracle context variables
    /// @param poolContext oracle context variables
    /// @param tradingModule address of the trading module
    /// @return oraclePairPrice oracle price for the pair in 18 decimals
    function getOraclePairPrice(
        OracleContext memory oracleContext, 
        TwoTokenPoolContext memory poolContext,
        ITradingModule tradingModule
    )
        internal view returns (uint256 oraclePairPrice) {
        // NOTE: this balancer price is denominated in 18 decimal places
        uint256 balancerWeightedPrice;
        if (oracleContext.balancerOracleWeight > 0) {
            uint256 balancerPrice = _getTimeWeightedOraclePrice(
                address(poolContext.baseContext.pool),
                IPriceOracle.Variable.PAIR_PRICE,
                oracleContext.oracleWindowInSeconds
            );

            if (poolContext.primaryIndex == 1) {
                // If the primary index is the second token, we need to invert
                // the balancer price.
                balancerPrice = BALANCER_PRECISION_SQUARED / balancerPrice;
            }

            balancerWeightedPrice = balancerPrice * oracleContext.balancerOracleWeight;
        }

        uint256 chainlinkWeightedPrice;
        if (oracleContext.balancerOracleWeight < BALANCER_ORACLE_WEIGHT_PRECISION) {
            (int256 rate, int256 decimals) = tradingModule.getOraclePrice(
                poolContext.primaryToken, poolContext.secondaryToken
            );
            require(rate > 0);
            require(decimals >= 0);

            if (uint256(decimals) != BALANCER_PRECISION) {
                rate = (rate * int256(BALANCER_PRECISION)) / decimals;
            }

            // No overflow in rate conversion, checked above
            chainlinkWeightedPrice = 
                uint256(rate) * (BALANCER_ORACLE_WEIGHT_PRECISION - oracleContext.balancerOracleWeight);
        }

        oraclePairPrice = (balancerWeightedPrice + chainlinkWeightedPrice) / BALANCER_ORACLE_WEIGHT_PRECISION;
    }

    /// @notice Returns the optimal amount to borrow for the secondary token
    /// @param oracleContext oracle context variables
    /// @param poolContext oracle context variables
    /// @return secondaryAmount optimal amount of the secondary token to join the pool
    function getOptimalSecondaryBorrowAmount(
        WeightedOracleContext memory oracleContext,
        TwoTokenPoolContext memory poolContext,
        uint256 primaryAmount
    ) 
        internal view returns (uint256 secondaryAmount) {
        // Use the oracle price here rather than the spot price to prevent flash loan
        // manipulation (would force the user to join at a disadvantageous price). If
        // the pool is being manipulated away from the oracle price and this generates
        // excess slippage when joining, the user must specify a minBPT amount that will
        // cause the transaction to revert.
        uint256 pairPrice = _getTimeWeightedOraclePrice(
            address(poolContext.baseContext.pool),
            IPriceOracle.Variable.PAIR_PRICE,
            oracleContext.baseContext.oracleWindowInSeconds
        );

        if (poolContext.primaryIndex == 0) {
            // If the primary index is the first token, invert the pair price
            pairPrice = BALANCER_PRECISION_SQUARED / pairPrice;
        }

        uint256 primaryPrecision = 10 ** poolContext.primaryDecimals;
        uint256 secondaryPrecision = 10 ** poolContext.secondaryDecimals;

        // PrimaryAmount = (SecondaryAmount * PrimaryWeight) / (SecondaryWeight * PairPrice)
        // SecondaryAmount = (PrimaryAmount * SecondaryWeight * PairPrice) / PrimaryWeight
        // Also, we want to normalize to secondary token precision
        // SecondaryAmount = (PrimaryAmount * SecondaryWeight * PairPrice * SecondaryPrecision) /
        //    (PrimaryWeight * PrimaryPrecision * BalancerPrecision[for PairPrice])
        secondaryAmount = 
            (primaryAmount * oracleContext.secondaryWeight * pairPrice * secondaryPrecision) / 
            (oracleContext.primaryWeight * primaryPrecision * BALANCER_PRECISION);
    }


    /// @notice Joins a balancer pool using exact tokens in
    function joinPoolExactTokensIn(
        PoolContext memory context,
        PoolParams memory params,
        uint256 minBPT
    ) internal returns (uint256 bptAmount) {
        // Join pool
        bptAmount = IERC20(address(context.pool)).balanceOf(address(this));
        BALANCER_VAULT.joinPool{value: params.msgValue}(
            context.poolId,
            address(this),
            address(this),
            IBalancerVault.JoinPoolRequest(
                params.assets,
                params.amounts,
                abi.encode(
                    IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                    params.amounts,
                    minBPT // Apply minBPT to prevent front running
                ),
                false // Don't use internal balances
            )
        );
        bptAmount = IERC20(address(context.pool)).balanceOf(address(this)) - bptAmount;
    }

    /// @notice Exits a balancer pool using exact BPT in
    function _exitPoolExactBPTIn(
        PoolContext memory context,
        PoolParams memory params,
        uint256 bptExitAmount
    ) internal returns (uint256[] memory exitBalances) {
        exitBalances = new uint256[](params.assets.length);

        for (uint256 i; i < params.assets.length; i++) {
            exitBalances[i] = TokenUtils.tokenBalance(address(params.assets[i]));
        }

        BALANCER_VAULT.exitPool(
            context.poolId,
            address(this),
            payable(address(this)), // Vault will receive the underlying assets
            IBalancerVault.ExitPoolRequest(
                params.assets,
                params.amounts,
                abi.encode(
                    IBalancerVault.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT,
                    bptExitAmount
                ),
                false // Don't use internal balances
            )
        );

        for (uint256 i; i < params.assets.length; i++) {
            exitBalances[i] = TokenUtils.tokenBalance(address(params.assets[i])) - exitBalances[i];
        }
    }

    function approveBalancerTokens(
        TwoTokenPoolContext memory poolContext,
        AuraStakingContext memory stakingContext
    ) internal {
        IERC20(poolContext.primaryToken).checkApprove(address(BALANCER_VAULT), type(uint256).max);
        IERC20(poolContext.secondaryToken).checkApprove(address(BALANCER_VAULT), type(uint256).max);
        // Allow AURA_BOOSTER to pull BALANCER_POOL_TOKEN
        IERC20(address(poolContext.baseContext.pool))
            .checkApprove(address(stakingContext.auraBooster), type(uint256).max);
    }
}
