// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;

import {IPriceOracle} from "../../../interfaces/balancer/IPriceOracle.sol";
import {IBalancerVault, IAsset} from "../../../interfaces/balancer/IBalancerVault.sol";
import {ITradingModule} from "../../../interfaces/trading/ITradingModule.sol";
import {Constants} from "../global/Constants.sol";
import {WETH9} from "../../../interfaces/WETH9.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TokenUtils} from "./TokenUtils.sol";

library BalancerUtils {
    using TokenUtils for IERC20;

    WETH9 public constant WETH =
        WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IBalancerVault public constant BALANCER_VAULT =
        IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    uint256 internal constant BALANCER_PRECISION = 1e18;
    uint256 internal constant BALANCER_PRECISION_SQUARED = 1e36;

    error InvalidTokenIndex(uint256 tokenIndex);

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

        // @audit is this comment correct? isn't the price denominated in the first token?
        // Gets the balancer time weighted average price denominated in ETH
        return IPriceOracle(pool).getTimeWeightedAverage(queries)[0];
    }

    /// @notice Gets the current spot price with a given token index
    /// @param tokenIndex 0 = PRIMARY_TOKEN, 1 = SECONDARY_TOKEN
    /// @return spotPrice token spot price
    function getSpotPrice(
        bytes32 poolId,
        uint256 tokenIndex,
        uint8 primaryIndex,
        uint256 primaryWeight,
        uint256 secondaryWeight,
        uint8 primaryDecimals,
        uint8 secondaryDecimals
    ) external view returns (uint256) {
        // @audit can this method be replaced with this method call instead?
        // https://dev.balancer.fi/references/contracts/apis/pools/weightedpool2tokens#getlatest

        // prettier-ignore
        (
            /* address[] memory tokens */,
            uint256[] memory balances,
            /* uint256 lastChangeBlock */
        ) = BALANCER_VAULT.getPoolTokens(poolId);

        // Make everything 1e18
        // @audit check if the decimals != 18 to save some gas since 18 is so common, also this is an edge case but if
        // your decimals are greater than 18 this will underflow (probably will never happen)
        uint256 primaryBalance = balances[primaryIndex] *
            10**(18 - primaryDecimals);
        uint256 secondaryBalance = balances[1 - primaryIndex] *
            10**(18 - secondaryDecimals);

        // First we multiply everything by 1e18 for the weight division (weights are in 1e18),
        // then we multiply the numerator by 1e18 to to preserve enough precision for the division
        if (tokenIndex == primaryIndex) {
            // @audit rearrange this so that multiplication always comes before division
            // PrimarySpotPrice = (SecondaryBalance / SecondaryWeight * 1e18) / (PrimaryBalance / PrimaryWeight)
            return
                (((secondaryBalance * 1e18) / secondaryWeight) * 1e18) /
                ((primaryBalance * 1e18) / primaryWeight);
        } else if (tokenIndex == (1 - primaryIndex)) {
            // @audit rearrange this so that multiplication always comes before division
            // SecondarySpotPrice = (PrimaryBalance / PrimaryWeight * 1e18) / (SecondaryBalance / SecondaryWeight)
            return
                (((primaryBalance * 1e18) / primaryWeight) * 1e18) /
                ((secondaryBalance * 1e18) / secondaryWeight);
        }

        // @audit move the revert to the top of the method, then you can get rid of the else if above since you will
        // know that tokenIndex is always 1 or 0
        revert InvalidTokenIndex(tokenIndex);
    }

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

    function joinPoolExactTokensIn(
        bytes32 poolId,
        address primaryAddress,
        uint256 maxPrimaryAmount,
        address secondaryAddress,
        uint256 maxSecondaryAmount,
        uint8 primaryIndex,
        uint256 minBPT
    ) internal {
        // prettier-ignore
        (
            IAsset[] memory assets,
            uint256[] memory maxAmountsIn
        ) = _getPoolParams(
            primaryAddress,
            maxPrimaryAmount,
            secondaryAddress,
            maxSecondaryAmount,
            primaryIndex
        );

        uint256 msgValue;
        if (assets[primaryIndex] == IAsset(Constants.ETH_ADDRESS)) msgValue = maxAmountsIn[primaryIndex];

        // Join pool
        BALANCER_VAULT.joinPool{value: msgValue}(
            poolId,
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

    function exitPoolExactBPTIn(
        bytes32 poolId,
        address primaryAddress,
        uint256 minPrimaryAmount,
        address secondaryAddress,
        uint256 minSecondaryAmount,
        uint8 primaryIndex,
        uint256 bptExitAmount
    ) internal {
        // prettier-ignore
        (
            IAsset[] memory assets,
            uint256[] memory minAmountsOut
        ) = _getPoolParams(
            primaryAddress,
            minPrimaryAmount,
            secondaryAddress,
            minSecondaryAmount,
            primaryIndex
        );

        BALANCER_VAULT.exitPool(
            poolId,
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

    /// @notice Gets the time-weighted primary token balance for a given bptAmount
    /// @dev Balancer pool needs to be fully initialized with at least 1024 trades
    /// @param bptAmount BPT amount
    /// @return primaryAmount primary token balance
    /// @return pairPrice price of the token pair denominated in the first token
    function getTimeWeightedPrimaryBalance(
        address pool,
        uint256 oracleWindowInSeconds,
        uint8 primaryIndex,
        uint256 primaryWeight,
        uint256 secondaryWeight,
        uint8 primaryDecimals,
        uint256 bptAmount
    ) external view returns (uint256 primaryAmount, uint256 pairPrice) {
        // Gets the BPT token price
        uint256 bptPrice = _getTimeWeightedOraclePrice(
            pool,
            IPriceOracle.Variable.BPT_PRICE,
            oracleWindowInSeconds
        );

        // Gets the pair price
        pairPrice = _getTimeWeightedOraclePrice(
            pool,
            IPriceOracle.Variable.PAIR_PRICE,
            oracleWindowInSeconds
        );

        uint256 primaryPrecision = 10 ** primaryDecimals;

        if (primaryIndex == 0) {
            // The first token in the BPT pool is the primary token.
            // Since bptPrice is always denominated in the first token,
            // Both bptPrice and bptAmount are in 1e18
            // underlyingValue = bptPrice * bptAmount / 1e18
            primaryAmount = (bptPrice * bptAmount * primaryPrecision) / BALANCER_PRECISION_SQUARED;
        } else {
            // The second token in the BPT pool is the primary token.
            // In this case, we need to convert secondaryTokenValue
            // to underlyingValue using the pairPrice.
            // Both bptPrice and bptAmount are in 1e18
            uint256 secondaryAmount = (bptPrice * bptAmount) / BALANCER_PRECISION;

            // PairPrice =  (SecondaryAmount / SecondaryWeight) / (PrimaryAmount / PrimaryWeight)
            // (SecondaryAmount / SecondaryWeight) / PairPrice = (PrimaryAmount / PrimaryWeight)
            // PrimaryAmount = (SecondaryAmount / SecondaryWeight) / PairPrice * PrimaryWeight

            // @audit this can be further simplified to, use this formula instead because it uses
            // less division between steps and therefore will result in less precision loss.
            // PrimaryAmount = (SecondaryAmount * PrimaryWeight) / (SecondaryWeight * PairPrice)

            primaryAmount = (secondaryAmount * primaryWeight * primaryPrecision) /
                (secondaryWeight * pairPrice * BALANCER_PRECISION);
        }
    }

    function _getPairPrice(
        address pool,
        bytes32 poolId,
        address tradingModule,
        uint256 oracleWindowInSeconds,
        uint256 balancerOracleWeight
    ) internal view returns (uint256) {
        // @audit this should only be called if balancerOracleWeight > 0
        uint256 balancerPrice = _getTimeWeightedOraclePrice(
            pool,
            IPriceOracle.Variable.PAIR_PRICE,
            oracleWindowInSeconds
        );

        // prettier-ignore
        (
            address[] memory tokens,
            /* uint256[] memory balances */,
            /* uint256 lastChangeBlock */
        ) = BalancerUtils.BALANCER_VAULT.getPoolTokens(poolId);

        // @audit this should only be called if balancerOracleWeight < 1e8
        (int256 chainlinkPrice, int256 decimals) = ITradingModule(tradingModule)
            .getOraclePrice(tokens[1], tokens[0]);

        // @audit zero may be a valid price
        require(chainlinkPrice >= 0); /// @dev Chainlink rate error
        require(decimals >= 0); /// @dev Chainlink decimals error

        // Normalize price to 18 decimals
        // @audit this should only be done if decimals != 1e18
        chainlinkPrice = (chainlinkPrice * 1e18) / decimals;

        // @audit 1e8 should be a constant with a defined name here
        // @audit for readability these should be split into two named variables
        return
            (balancerPrice * balancerOracleWeight) /
            1e8 +
            (uint256(chainlinkPrice) * (1e8 - balancerOracleWeight)) /
            1e8;
    }

    function getOptimalSecondaryBorrowAmount(
        address pool,
        uint256 oracleWindowInSeconds,
        uint8 primaryIndex,
        uint256 primaryWeight,
        uint256 secondaryWeight,
        uint8 primaryDecimals,
        uint8 secondaryDecimals,
        uint256 primaryAmount
    ) external view returns (uint256 secondaryAmount) {
        // Gets the PAIR price
        uint256 pairPrice = _getTimeWeightedOraclePrice(
            pool,
            IPriceOracle.Variable.PAIR_PRICE,
            oracleWindowInSeconds
        );

        // @audit these two formulas can be further simplified to the following which uses
        // less division between steps and therefore will result in less precision loss.
        // PrimaryAmount = (SecondaryAmount * PrimaryWeight) / (SecondaryWeight * PairPrice)
        // SecondaryAmount = (PrimaryAmount * SecondaryWeight * PairPrice) / PrimaryWeight

        // Calculate weighted primary amount
        primaryAmount = ((primaryAmount * 1e18) / primaryWeight);

        // Calculate price adjusted primary amount, price is always in 1e18
        // Since price is always expressed as the price of the second token in units of the
        // first token, we need to invert the math if the second token is the primary token
        if (primaryIndex == 0) {
            // PairPrice = (PrimaryAmount / PrimaryWeight) / (SecondaryAmount / SecondaryWeight)
            // SecondaryAmount = (PrimaryAmount / PrimaryWeight) / PairPrice * SecondaryWeight
            primaryAmount = ((primaryAmount * 1e18) / pairPrice);
        } else {
            // PairPrice = (SecondaryAmount / SecondaryWeight) / (PrimaryAmount / PrimaryWeight)
            // SecondaryAmount = (PrimaryAmount / PrimaryWeight) * PairPrice * SecondaryWeight
            primaryAmount = ((primaryAmount * pairPrice) / 1e18);
        }

        // Calculate secondary amount (precision is still 1e18)
        secondaryAmount = (primaryAmount * secondaryWeight) / 1e18;

        // Normalize precision to secondary precision
        secondaryAmount =
            (secondaryAmount * 10**secondaryDecimals) /
            10**primaryDecimals;
    }

    function approveBalancerTokens(
        address balancerVault,
        IERC20 underlyingToken,
        IERC20 secondaryToken,
        IERC20 balancerPool,
        IERC20 liquidityGauge,
        address vebalDelegator
    ) external {
        underlyingToken.checkApprove(balancerVault, type(uint256).max);
        secondaryToken.checkApprove(balancerVault, type(uint256).max);
        // Allow LIQUIDITY_GAUGE to pull BALANCER_POOL_TOKEN
        balancerPool.checkApprove(address(liquidityGauge), type(uint256).max);
        // Allow VEBAL_DELEGATOR to pull LIQUIDITY_GAUGE tokens
        liquidityGauge.checkApprove(vebalDelegator, type(uint256).max);
    }
}
