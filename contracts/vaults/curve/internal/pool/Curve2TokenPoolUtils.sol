// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {TypeConvert} from "../../../../global/TypeConvert.sol";
import {StrategyContext, TwoTokenPoolContext} from "../../../common/VaultTypes.sol";
import {Curve2TokenPoolContext} from "../../CurveVaultTypes.sol";
import {TwoTokenPoolUtils} from "../../../common/internal/pool/TwoTokenPoolUtils.sol";
import {StrategyUtils} from "../../../common/internal/strategy/StrategyUtils.sol";

library Curve2TokenPoolUtils {
    using StrategyUtils for StrategyContext;
    using Curve2TokenPoolUtils for Curve2TokenPoolContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using TypeConvert for uint256;

    function _getSpotPrice(
        Curve2TokenPoolContext memory poolContext, 
        uint256 tokenIndex
    ) internal view returns (uint256 spotPrice) {
        require(tokenIndex < 2);
        if (tokenIndex == 0) {
            spotPrice = poolContext.curvePool.get_dy(
                int8(poolContext.basePool.primaryIndex), 
                int8(poolContext.basePool.secondaryIndex), 
                10**poolContext.basePool.primaryDecimals
            );
        } else {
            spotPrice = poolContext.curvePool.get_dy(
                int8(poolContext.basePool.secondaryIndex),
                int8(poolContext.basePool.primaryIndex), 
                10**poolContext.basePool.secondaryDecimals
            );
        }
    }

    /// @notice Gets the time-weighted primary token balance for a given poolClaim Amount
    /// @dev Balancer pool needs to be fully initialized with at least 1024 trades
    /// @param poolContext pool context variables
    /// @param strategyContext strategy context variables
    /// @param poolClaim amount of balancer pool lp tokens
    /// @return primaryAmount primary token balance
    function _getTimeWeightedPrimaryBalance(
        Curve2TokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        uint256 poolClaim
    ) internal view returns (uint256 primaryAmount) {
        uint256 oraclePairPrice = poolContext.basePool._getOraclePairPrice(strategyContext);
        
        // tokenIndex == 0 because _getOraclePairPrice always returns the price in terms of
        // the primary currency
        uint256 spotPrice = _getSpotPrice(poolContext, 0);

        primaryAmount = poolContext.basePool._getTimeWeightedPrimaryBalance({
            strategyContext: strategyContext,
            poolClaim: poolClaim,
            oraclePrice: oraclePairPrice,
            spotPrice: spotPrice
        });
    }

    /// @notice We value strategy tokens in terms of the primary balance. The time weighted
    /// primary balance is used in order to prevent pool manipulation.
    /// @param poolContext pool context variables
    /// @param strategyContext strategy context variables
    /// @param strategyTokenAmount amount of strategy tokens
    /// @return underlyingValue underlying value of strategy tokens
    function _convertStrategyToUnderlying(
        Curve2TokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        uint256 strategyTokenAmount
    ) internal view returns (int256 underlyingValue) {
        
        uint256 poolClaim 
            = strategyContext._convertStrategyTokensToPoolClaim(strategyTokenAmount);

        underlyingValue 
            = poolContext._getTimeWeightedPrimaryBalance(strategyContext, poolClaim).toInt();
    }   
}