// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    BalancerComposablePoolContext, 
    ComposableOracleContext, 
    PoolParams,
    AuraStakingContext
} from "../../BalancerVaultTypes.sol";
import {
    TradeParams,
    StrategyContext,
    StrategyVaultSettings,
    StrategyVaultState,
    ComposableRewardTradeParams,
    ComposablePoolContext,
    DepositParams,
    RedeemParams
} from "../../../common/VaultTypes.sol";
import {Deployments} from "../../../../global/Deployments.sol";
import {Errors} from "../../../../global/Errors.sol";
import {IBalancerVault, IAsset} from "../../../../../interfaces/balancer/IBalancerVault.sol";
import {IComposablePool} from "../../../../../interfaces/balancer/IBalancerPool.sol";
import {TokenUtils, IERC20} from "../../../../utils/TokenUtils.sol";
import {VaultConstants} from "../../../common/VaultConstants.sol";
import {VaultStorage} from "../../../common/VaultStorage.sol";
import {StrategyUtils} from "../../../common/internal/strategy/StrategyUtils.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {ComposableOracleMath} from "../math/ComposableOracleMath.sol";
import {DexId} from "../../../../../interfaces/trading/ITradingModule.sol";
import {TypeConvert} from "../../../../global/TypeConvert.sol";

// TODO: combine this into ComposableAuraHelper
library BalancerComposablePoolUtils {
    using TokenUtils for IERC20;
    using TypeConvert for uint256;
    using StrategyUtils for StrategyContext;
    using VaultStorage for StrategyVaultSettings;
    using VaultStorage for StrategyVaultState;
    using ComposableOracleMath for ComposableOracleContext;

    function _getOraclePairPrice(
        StrategyContext memory strategyContext,
        address token1,
        address token2
    ) internal view returns (uint256 oraclePairPrice) {
        // TODO: why can't this just call TwoTokenPoolUtils?
        (int256 rate, int256 decimals) = strategyContext.tradingModule.getOraclePrice(
            token1, token2
        );
        require(rate > 0);
        require(decimals >= 0);

        if (uint256(decimals) != strategyContext.poolClaimPrecision) {
            rate = (rate * int256(strategyContext.poolClaimPrecision)) / decimals;
        }

        // No overflow in rate conversion, checked above
        oraclePairPrice = uint256(rate);
    }

    function _checkPriceLimit(
        BalancerComposablePoolContext memory poolContext, 
        ComposableOracleContext memory oracleContext,
        StrategyContext memory strategyContext,
        uint256 index1, 
        uint256 index2
    ) internal view {
        uint256 oraclePrice = _getOraclePairPrice(
            strategyContext,
            poolContext.basePool.tokens[index1],
            poolContext.basePool.tokens[index2]
        );

        // TODO: this may not work for weighted pool
        uint256 spotPrice = oracleContext._getSpotPrice(poolContext, index1, index2);

        strategyContext._checkPriceLimit(oraclePrice, spotPrice);
    }

    function _convertToPrimary(
        BalancerComposablePoolContext memory poolContext,
        StrategyContext memory strategyContext,
        ComposableOracleContext memory oracleContext,
        uint256 poolClaim,
        uint256 index
    ) internal view returns (uint256 amountInPrimary) {
        amountInPrimary = poolContext.basePool.balances[index] * poolClaim / oracleContext.virtualSupply;

        if (index != poolContext.basePool.primaryIndex) {
            // Conversion is only necessary if index != primaryIndex
            uint256 oraclePrice = _getOraclePairPrice(
                strategyContext,
                poolContext.basePool.tokens[poolContext.basePool.primaryIndex],
                poolContext.basePool.tokens[index]
            );

            // Scale secondary balance to primaryPrecision
            uint256 primaryPrecision = 10 ** poolContext.basePool.decimals[poolContext.basePool.primaryIndex];
            uint256 secondaryPrecision = 10 ** poolContext.basePool.decimals[index];
            amountInPrimary = amountInPrimary * primaryPrecision / secondaryPrecision;

            // Value the secondary balance in terms of the primary token using the oraclePairPrice
            amountInPrimary = amountInPrimary * strategyContext.poolClaimPrecision / oraclePrice;
        }
    }

    /// @notice Gets the time-weighted primary token balance for a given bptAmount
    /// @param poolContext pool context variables
    /// @param oracleContext oracle context variables
    /// @param bptAmount amount of balancer pool lp tokens
    /// @param validateOnly true if the function is only used to validate pool prices
    /// @return primaryAmount primary token balance
    function _getTimeWeightedPrimaryBalance(
        BalancerComposablePoolContext memory poolContext,
        ComposableOracleContext memory oracleContext,
        StrategyContext memory strategyContext,
        uint256 bptAmount,
        bool validateOnly
    ) internal view returns (uint256 primaryAmount) {
        uint256 numTokens = poolContext.basePool.tokens.length;

        for (uint256 i; i < numTokens; i++) {
            if (i == poolContext.bptIndex) continue;
            uint256 j = i + 1;
            if (j == poolContext.bptIndex) j++;
            if (j < numTokens) {
                _checkPriceLimit(poolContext, oracleContext, strategyContext, i, j);
            }

            if (!validateOnly) {
                primaryAmount += _convertToPrimary({
                    poolContext: poolContext, 
                    strategyContext: strategyContext,
                    oracleContext: oracleContext,
                    poolClaim: bptAmount,
                    index: i
                });
            }
        }
    }

    // function _handleDepositTrades(
    //     BalancerComposablePoolContext memory poolContext,
    //     StrategyContext memory strategyContext,
    //     uint256 deposit,
    //     DepositParams memory params
    // ) private returns (uint256[] memory amounts) {
    //     uint256 numTokens = poolContext.basePool.tokens.length;
    //     amounts = new uint256[](poolContext.basePool.tokens.length);

    //     if (params.depositTrades.length > 0) {
    //         uint256 tradeIndex;
    //         for (uint256 i; i < numTokens; i++) {
    //             if (i == poolContext.bptIndex || i == poolContext.basePool.primaryIndex) continue;

    //             uint256 sellAmount = params.depositTrades[tradeIndex].tradeAmount;

    //             if (sellAmount > 0) {
    //                 uint256 amountBought = _sellToken({
    //                     strategyContext: strategyContext, 
    //                     params: params.depositTrades[tradeIndex].tradeParams,
    //                     sellToken: poolContext.basePool.tokens[poolContext.basePool.primaryIndex],
    //                     buyToken: poolContext.basePool.tokens[i],
    //                     sellAmount: sellAmount
    //                 });

    //                 deposit -= sellAmount;
    //                 amounts[i] = amountBought;
    //             }

    //             tradeIndex++;
    //         }
    //     }

    //     amounts[poolContext.basePool.primaryIndex] = deposit;
    // }

    // function _sellToken(
    //     StrategyContext memory strategyContext,
    //     TradeParams memory params,
    //     address sellToken,
    //     address buyToken,
    //     uint256 sellAmount
    // ) internal returns (uint256 buyAmount) {
    //     if (DexId(params.dexId) == DexId.ZERO_EX) {
    //         revert Errors.InvalidDexId(params.dexId);
    //     }

    //     ( /*uint256 amountSold */, buyAmount) = 
    //         strategyContext._executeTradeExactIn({
    //             params: params,
    //             sellToken: sellToken,
    //             buyToken: buyToken,
    //             amount: sellAmount,
    //             useDynamicSlippage: true
    //         });
    // }

    // function _convertTokensToPrimary(
    //     BalancerComposablePoolContext memory poolContext,
    //     StrategyContext memory strategyContext,
    //     RedeemParams memory params,
    //     uint256[] memory exitBalances
    // ) internal returns (uint256 primaryPurchased) {
    //     address[] memory tokens = poolContext.basePool.tokens;
    //     uint256 primaryIndex = poolContext.basePool.primaryIndex;
    //     uint256 tradeIndex;
    //     for (uint256 i; i < tokens.length; i++) {
    //         if (i == poolContext.bptIndex) continue;

    //         if (i == primaryIndex) {
    //             primaryPurchased += exitBalances[i];
    //         } else {
    //             if (exitBalances[i] > 0) {
    //                 primaryPurchased += _sellToken({
    //                     strategyContext: strategyContext,
    //                     params: params.redemptionTrades[tradeIndex],
    //                     sellToken: tokens[i],
    //                     buyToken: tokens[primaryIndex],
    //                     sellAmount: exitBalances[i]
    //                 });
    //             }
    //             tradeIndex++;
    //         }
    //     }
    // }

    /// @notice We value strategy tokens in terms of the primary balance. The time weighted
    /// primary balance is used in order to prevent pool manipulation.
    /// @param poolContext pool context variables
    /// @param strategyContext strategy context variables
    /// @param oracleContext oracle context variables
    /// @param vaultShareAmount amount of strategy tokens
    /// @return underlyingValue underlying value of strategy tokens
    function _convertStrategyToUnderlying(
        BalancerComposablePoolContext memory poolContext,
        StrategyContext memory strategyContext,
        ComposableOracleContext memory oracleContext,
        uint256 vaultShareAmount
    ) internal view returns (int256 underlyingValue) {
        uint256 bptClaim = strategyContext._convertStrategyTokensToPoolClaim(vaultShareAmount);

        underlyingValue = _getTimeWeightedPrimaryBalance(
            poolContext, oracleContext, strategyContext, bptClaim, false // validateOnly = false
        ).toInt();
    }
}
