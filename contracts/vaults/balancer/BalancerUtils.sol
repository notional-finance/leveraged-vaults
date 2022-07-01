// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {PoolContext, BoostContext} from "./BalancerVaultTypes.sol";
import {IPriceOracle} from "../../../../interfaces/balancer/IPriceOracle.sol";
import {IBalancerVault, IAsset} from "../../../../interfaces/balancer/IBalancerVault.sol";
import {ITradingModule} from "../../../../interfaces/trading/ITradingModule.sol";
import {Constants} from "../../global/Constants.sol";
import {WETH9} from "../../../../interfaces/WETH9.sol";
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
    function getTokenAddress(address token) internal view returns (address) {
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
    ) internal view returns (uint256 normalizedPrimary, uint256 normalizedSecondary) {
        if (primaryDecimals != 18) {
            uint256 decimalAdjust;
            unchecked { 
                decimalAdjust = 10**(18 - primaryDecimals);
            }
            normalizedPrimary = primaryBalance * decimalAdjust;
        }

        if (secondaryDecimals != 18) {
            uint256 decimalAdjust;
            unchecked { 
                decimalAdjust = 10**(18 - secondaryDecimals);
            }
            normalizedSecondary = secondaryBalance * decimalAdjust;
        }
    }

    /// @notice Gets the current spot price with a given token index, this is used to check against
    /// the oracle pair price to prevent front running
    /// @param poolId id of the balancer pool
    /// @param tokenIndex index of the token to receive the spot price in
    /// @param primaryIndex primary token index
    /// @param primaryWeight primary token weight
    /// @param secondaryWeight secondary token weight
    /// @param primaryDecimals primary token native decimals
    /// @param secondaryDecimals secondary token native decimals
    /// @return spotPrice token spot price
    function getSpotPrice(
        bytes32 poolId,
        uint256 tokenIndex,
        uint8 primaryIndex,
        uint256 primaryWeight,
        uint256 secondaryWeight,
        uint8 primaryDecimals,
        uint8 secondaryDecimals
    ) internal view returns (uint256 spotPrice) {
        // Prevents overflows, we don't expect tokens to be greater than 18 decimals, don't use
        // equal sign for minor gas optimization
        require(primaryDecimals < 19);
        require(secondaryDecimals < 19);
        require(tokenIndex < 2);

        // prettier-ignore
        (/* */, uint256[] memory balances, /* */) = BALANCER_VAULT.getPoolTokens(poolId);

        uint8 secondaryIndex;
        unchecked {
            secondaryIndex = 1 - primaryIndex;
        }

        // Normalize balances to 18 decimal places
        (balances[primaryIndex], balances[secondaryIndex]) = _normalizeBalances(
            balances[primaryIndex], primaryDecimals, balances[secondaryIndex], secondaryDecimals
        );

        // Target token balance is the balance of the token we want the spot price in 
        uint256 targetTokenBalance = balances[tokenIndex];
        // Denominator balance is the balance of the other token
        uint256 otherBalance = balances[1 - tokenIndex];
        // Assign the weights based on the token index
        (uint256 targetTokenWeight, uint256 otherWeight) = tokenIndex == primaryIndex ?
            (primaryWeight, secondaryWeight) :
            (secondaryWeight, primaryWeight);

        // SpotPrice = (otherBalance * targetWeight * 1e18) / (targetBalance * otherWeight)
        spotPrice = (otherBalance * targetTokenWeight * BALANCER_PRECISION) / (targetTokenBalance * otherWeight);
    }

    /// @notice Gets the time-weighted primary token balance for a given bptAmount
    /// @dev Balancer pool needs to be fully initialized with at least 1024 trades
    /// @param pool address of the balancer pool
    /// @param oracleWindowInSeconds window of time for the balancer oracle to scan over
    /// @param primaryIndex the index of the primary token in the balancer pool
    /// @param primaryWeight weight of the primary token
    /// @param secondaryWeight weight of the secondary token
    /// @param primaryDecimals decimal places of the primary token
    /// @param bptAmount amount of balancer pool lp tokens
    /// @return primaryAmount primary token balance
    function getTimeWeightedPrimaryBalance(
        address pool,
        uint256 oracleWindowInSeconds,
        uint8 primaryIndex,
        uint256 primaryWeight,
        uint256 secondaryWeight,
        uint8 primaryDecimals,
        uint256 bptAmount
    ) internal view returns (uint256 primaryAmount) {
        // Gets the BPT token price denominated in token index = 0
        uint256 bptPrice = _getTimeWeightedOraclePrice(
            pool,
            IPriceOracle.Variable.BPT_PRICE,
            oracleWindowInSeconds
        );

        // Gets the pair price
        uint256 pairPrice = _getTimeWeightedOraclePrice(
            pool,
            IPriceOracle.Variable.PAIR_PRICE,
            oracleWindowInSeconds
        );

        uint256 primaryPrecision = 10 ** primaryDecimals;

        if (primaryIndex == 0) {
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
            //          (SecondaryWeight * PairPrice * BalancerPrecision)
            primaryAmount = (secondaryAmount * primaryWeight * primaryPrecision) /
                (secondaryWeight * pairPrice * BALANCER_PRECISION);
        }
    }

    /// @notice Gets the oracle price pair price between two tokens using a weighted
    /// average between a chainlink oracle and the balancer TWAP oracle.
    /// @param pool address of the balancer pool
    /// @param primaryIndex the index of the primary token in the balancer pool
    /// @param balancerOracleWindowInSeconds window of time for the balancer oracle to scan over
    /// @param balancerOracleWeight share of the weighted average to the balancer oracle
    /// @param baseToken base token for the chainlink oracle
    /// @param quoteToken quote token for the chainlink oracle
    /// @param tradingModule address of the trading module
    /// @return oraclePairPrice oracle price for the pair in 18 decimals
    function getOraclePairPrice(
        address pool,
        uint8 primaryIndex,
        uint256 balancerOracleWindowInSeconds,
        uint256 balancerOracleWeight,
        address baseToken,
        address quoteToken,
        ITradingModule tradingModule
    ) internal view returns (uint256 oraclePairPrice) {
        // NOTE: this balancer price is denominated in 18 decimal places
        uint256 balancerWeightedPrice;
        if (balancerOracleWeight > 0) {
            uint256 balancerPrice = _getTimeWeightedOraclePrice(
                pool,
                IPriceOracle.Variable.PAIR_PRICE,
                balancerOracleWindowInSeconds
            );

            if (primaryIndex == 1) {
                // If the primary index is the second token, we need to invert
                // the balancer price.
                balancerPrice = BALANCER_PRECISION_SQUARED / balancerPrice;
            }

            balancerWeightedPrice = balancerPrice * balancerOracleWeight;
        }

        uint256 chainlinkWeightedPrice;
        if (balancerOracleWeight < BALANCER_ORACLE_WEIGHT_PRECISION) {
            (int256 rate, int256 decimals) = tradingModule.getOraclePrice(baseToken, quoteToken);
            require(rate > 0);
            require(decimals >= 0);

            if (uint256(decimals) != BALANCER_PRECISION) {
                rate = (rate * int256(BALANCER_PRECISION)) / decimals;
            }

            // No overflow in rate conversion, checked above
            chainlinkWeightedPrice = uint256(rate) * (BALANCER_ORACLE_WEIGHT_PRECISION - balancerOracleWeight);
        }

        oraclePairPrice = (balancerWeightedPrice + chainlinkWeightedPrice) / BALANCER_ORACLE_WEIGHT_PRECISION;
    }

    /// @notice Returns the optimal amount to borrow for the secondary token
    /// @param pool address of the balancer pool
    /// @param oracleWindowInSeconds window of time for the balancer oracle to scan over
    /// @param primaryIndex the index of the primary token in the balancer pool
    /// @param primaryWeight weight of the primary token
    /// @param secondaryWeight weight of the secondary token
    /// @param primaryDecimals decimal places of the primary token (denomination of primaryAmount)
    /// @param secondaryDecimals decimal places of the secondary token
    /// @param primaryAmount amount being deposited into the primary token
    /// @return secondaryAmount optimal amount of the secondary token to join the pool
    function getOptimalSecondaryBorrowAmount(
        address pool,
        uint256 oracleWindowInSeconds,
        uint8 primaryIndex,
        uint256 primaryWeight,
        uint256 secondaryWeight,
        uint8 primaryDecimals,
        uint8 secondaryDecimals,
        uint256 primaryAmount
    ) internal view returns (uint256 secondaryAmount) {
        // Use the oracle price here rather than the spot price to prevent flash loan
        // manipulation (would force the user to join at a disadvantageous price). If
        // the pool is being manipulated away from the oracle price and this generates
        // excess slippage when joining, the user must specify a minBPT amount that will
        // cause the transaction to revert.
        uint256 pairPrice = _getTimeWeightedOraclePrice(
            pool,
            IPriceOracle.Variable.PAIR_PRICE,
            oracleWindowInSeconds
        );

        if (primaryIndex == 1) {
            // If the primary index is the second token, invert the pair price
            pairPrice = BALANCER_PRECISION_SQUARED / pairPrice;
        }

        uint256 primaryPrecision = 10 ** primaryDecimals;
        uint256 secondaryPrecision = 10 ** secondaryDecimals;
        // PrimaryAmount = (SecondaryAmount * PrimaryWeight) / (SecondaryWeight * PairPrice)
        // SecondaryAmount = (PrimaryAmount * SecondaryWeight * PairPrice) / PrimaryWeight
        // Also, we want to normalize to secondary token precision
        // SecondaryAmount = (PrimaryAmount * SecondaryWeight * PairPrice * SecondaryPrecision) /
        //    (PrimaryWeight * PrimaryPrecision * BalancerPrecision[for PairPrice])
        secondaryAmount = (primaryAmount * secondaryWeight * pairPrice * secondaryPrecision) / 
            (primaryWeight * primaryPrecision * BALANCER_PRECISION);
    }


    /// @notice Returns parameters for joining and exiting pool
    function _getPoolParams(
        address primaryAddress,
        uint256 primaryAmount,
        address secondaryAddress,
        uint256 secondaryAmount,
        uint8 primaryIndex
    ) private view returns (IAsset[] memory assets, uint256[] memory amounts) {
        assets = new IAsset[](2);
        assets[primaryIndex] = IAsset(primaryAddress);
        uint8 secondaryIndex;
        unchecked { secondaryIndex = 1 - primaryIndex; }
        assets[secondaryIndex] = IAsset(secondaryAddress);

        amounts = new uint256[](2);
        amounts[primaryIndex] = primaryAmount;
        amounts[secondaryIndex] = secondaryAmount;
    }

    /// @notice Joins a balancer pool using exact tokens in
    function joinPoolExactTokensIn(
        PoolContext memory context,
        uint256 maxPrimaryAmount,
        uint256 maxSecondaryAmount,
        uint256 minBPT
    ) internal {
        // prettier-ignore
        (
            IAsset[] memory assets,
            uint256[] memory maxAmountsIn
        ) = _getPoolParams(
            context.primaryToken,
            maxPrimaryAmount,
            context.secondaryToken,
            maxSecondaryAmount,
            context.primaryIndex
        );

        uint256 msgValue;
        if (assets[context.primaryIndex] == IAsset(Constants.ETH_ADDRESS)) msgValue = maxAmountsIn[context.primaryIndex];

        // Join pool
        BALANCER_VAULT.joinPool{value: msgValue}(
            context.poolId,
            address(this),
            address(this),
            IBalancerVault.JoinPoolRequest(
                assets,
                maxAmountsIn,
                abi.encode(
                    IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                    maxAmountsIn,
                    minBPT // Apply minBPT to prevent front running
                ),
                false // Don't use internal balances
            )
        );
    }

    /// @notice Exits a balancer pool using exact BPT in
    function exitPoolExactBPTIn(
        PoolContext memory context,
        uint256 minPrimaryAmount,
        uint256 minSecondaryAmount,
        uint256 bptExitAmount
    ) internal {
        // prettier-ignore
        (
            IAsset[] memory assets,
            uint256[] memory minAmountsOut
        ) = _getPoolParams(
            context.primaryToken,
            minPrimaryAmount,
            context.secondaryToken,
            minSecondaryAmount,
            context.primaryIndex
        );

        BALANCER_VAULT.exitPool(
            context.poolId,
            address(this),
            payable(address(this)), // Vault will receive the underlying assets
            IBalancerVault.ExitPoolRequest(
                assets,
                minAmountsOut,
                abi.encode(
                    IBalancerVault.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT,
                    bptExitAmount
                ),
                false // Don't use internal balances
            )
        );
    }

    function _unstakeAndExitPoolExactBPTIn(
        PoolContext memory poolContext,
        BoostContext memory boostContext,
        uint256 bptClaim,
        uint256 minPrimary,
        uint256 minSecondary
    ) internal returns (uint256 primaryBalance, uint256 secondaryBalance) {
        // Withdraw BPT tokens back to the vault for redemption
        boostContext.boostController.withdrawToken(address(boostContext.liquidityGauge), bptClaim);
        boostContext.liquidityGauge.withdraw(bptClaim, false);

        uint256 primaryBefore = TokenUtils.tokenBalance(poolContext.primaryToken);
        uint256 secondaryBefore = TokenUtils.tokenBalance(poolContext.secondaryToken);

        exitPoolExactBPTIn({
            context: poolContext,
            minPrimaryAmount: minPrimary,
            minSecondaryAmount: minSecondary,
            bptExitAmount: bptClaim
        });

        primaryBalance = TokenUtils.tokenBalance(poolContext.primaryToken) - primaryBefore;
        secondaryBalance = TokenUtils.tokenBalance(address(poolContext.secondaryToken)) - secondaryBefore;
    }

    function approveBalancerTokens(
        address balancerVault,
        IERC20 underlyingToken,
        IERC20 secondaryToken,
        IERC20 balancerPool,
        IERC20 liquidityGauge,
        address vebalDelegator
    ) internal {
        underlyingToken.checkApprove(balancerVault, type(uint256).max);
        secondaryToken.checkApprove(balancerVault, type(uint256).max);
        // Allow LIQUIDITY_GAUGE to pull BALANCER_POOL_TOKEN
        balancerPool.checkApprove(address(liquidityGauge), type(uint256).max);
        // Allow VEBAL_DELEGATOR to pull LIQUIDITY_GAUGE tokens
        liquidityGauge.checkApprove(vebalDelegator, type(uint256).max);
    }
}
