// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;

import {ITradingModule, Trade, TradeType} from "../../interfaces/trading/ITradingModule.sol";
import {TradeHandler, DexId} from "../trading/TradeHandler.sol";
import {WETH9} from "../../interfaces/WETH9.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

library TradeHelper {
    using TradeHandler for Trade;
    using SafeERC20 for ERC20;

    uint256 internal constant SLIPPAGE_LIMIT_PRECISION = 1e8;

    function getLimitAmount(
        address tradingModule,
        uint16 tradeType,
        address sellToken,
        address buyToken,
        uint256 amount,
        uint256 slippageLimit
    ) external view returns (uint256 limitAmount) {
        // prettier-ignore
        (
            uint256 oraclePrice, 
            uint256 oracleDecimals
        ) = ITradingModule(tradingModule).getOraclePrice(
            sellToken,
            buyToken
        );

        uint256 sellTokenDecimals = 10 **
            (sellToken == address(0) ? 18 : ERC20(sellToken).decimals());
        uint256 buyTokenDecimals = 10 **
            (buyToken == address(0) ? 18 : ERC20(buyToken).decimals());

        if (TradeType(tradeType) == TradeType.EXACT_OUT_SINGLE) {
            // 0 means no slippage limit
            if (slippageLimit == 0) {
                return type(uint256).max;
            }
            // Invert oracle price
            oraclePrice = (oracleDecimals * oracleDecimals) / oraclePrice;
            // For exact out trades, limitAmount is the max amount of sellToken the DEX can
            // pull from the contract
            limitAmount =
                ((oraclePrice +
                    ((oraclePrice * slippageLimit) /
                        SLIPPAGE_LIMIT_PRECISION)) * amount) /
                oracleDecimals;

            // limitAmount is in buyToken precision after the previous calculation,
            // convert it to sellToken precision
            limitAmount = (limitAmount * sellTokenDecimals) / buyTokenDecimals;
        } else {
            // 0 means no slippage limit
            if (slippageLimit == 0) {
                return 0;
            }
            // For exact in trades, limitAmount is the min amount of buyToken the contract
            // expects from the DEX
            limitAmount =
                ((oraclePrice -
                    ((oraclePrice * slippageLimit) /
                        SLIPPAGE_LIMIT_PRECISION)) * amount) /
                oracleDecimals;

            // limitAmount is in sellToken precision after the previous calculation,
            // convert it to buyToken precision
            limitAmount = (limitAmount * buyTokenDecimals) / sellTokenDecimals;
        }
    }

    function approveTokens(
        address balancerVault,
        address underylingToken,
        address secondaryToken,
        address balancerPool,
        address liquidityGauge,
        address vebalDelegator
    ) external {
        // Allow Balancer vault to pull UNDERLYING_TOKEN
        if (address(underylingToken) != address(0)) {
            ERC20(underylingToken).safeApprove(
                balancerVault,
                type(uint256).max
            );
        }
        // Allow balancer vault to pull SECONDARY_TOKEN
        if (address(secondaryToken) != address(0)) {
            ERC20(secondaryToken).safeApprove(balancerVault, type(uint256).max);
        }
        // Allow LIQUIDITY_GAUGE to pull BALANCER_POOL_TOKEN
        ERC20(balancerPool).safeApprove(liquidityGauge, type(uint256).max);

        // Allow VEBAL_DELEGATOR to pull LIQUIDITY_GAUGE tokens
        ERC20(liquidityGauge).safeApprove(vebalDelegator, type(uint256).max);
    }
}
