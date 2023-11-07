// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {TypeConvert} from "../../../../global/TypeConvert.sol";
import {Errors} from "../../../../global/Errors.sol";
import {Constants} from "../../../../global/Constants.sol";
import {Deployments} from "../../../../global/Deployments.sol";
import {
    StrategyContext, 
    TwoTokenPoolContext,
    StrategyVaultSettings,
    StrategyVaultState,
    DepositParams,
    RedeemParams
} from "../../../common/VaultTypes.sol";
import {CurveConstants} from "../CurveConstants.sol";
import {Curve2TokenPoolContext, ConvexStakingContext} from "../../CurveVaultTypes.sol";
import {TwoTokenPoolUtils} from "../../../common/internal/pool/TwoTokenPoolUtils.sol";
import {StrategyUtils} from "../../../common/internal/strategy/StrategyUtils.sol";
import {VaultStorage} from "../../../common/VaultStorage.sol";
import {VaultConstants} from "../../../common/VaultConstants.sol";
import {
    ICurvePool,
    ICurve2TokenPool, 
    ICurve2TokenPoolV1, 
    ICurve2TokenPoolV2
} from "../../../../../interfaces/curve/ICurvePool.sol";
import {IConvexBooster, IConvexBoosterArbitrum} from "../../../../../interfaces/convex/IConvexBooster.sol";
import {IConvexRewardPool, IConvexRewardPoolArbitrum} from "../../../../../interfaces/convex/IConvexRewardPool.sol";

library Curve2TokenPoolUtils {
    using StrategyUtils for StrategyContext;
    using Curve2TokenPoolUtils for Curve2TokenPoolContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using TypeConvert for uint256;
    using VaultStorage for StrategyVaultSettings;
    using VaultStorage for StrategyVaultState;

    function _getSpotPrice(
        Curve2TokenPoolContext memory poolContext, 
        uint256 tokenIndex
    ) internal view returns (uint256 spotPrice) {
        require(tokenIndex < 2);
        if (tokenIndex == 0) {
            spotPrice = ICurvePool(poolContext.curvePool).get_dy(
                int8(poolContext.basePool.primaryIndex), 
                int8(poolContext.basePool.secondaryIndex), 
                10**poolContext.basePool.primaryDecimals // 1 unit of primary
            );
            uint256 secondaryPrecision = 10**poolContext.basePool.secondaryDecimals;
            spotPrice = spotPrice * CurveConstants.CURVE_PRECISION / secondaryPrecision;
        } else {
            spotPrice = ICurvePool(poolContext.curvePool).get_dy(
                int8(poolContext.basePool.secondaryIndex),
                int8(poolContext.basePool.primaryIndex), 
                10**poolContext.basePool.secondaryDecimals // 1 unit of secondary
            );
            uint256 primaryPrecision = 10**poolContext.basePool.primaryDecimals;
            spotPrice = spotPrice * CurveConstants.CURVE_PRECISION / primaryPrecision;
        }
    }

    function _validateSpotPriceAndPairPrice(
        Curve2TokenPoolContext calldata poolContext,
        StrategyContext memory strategyContext,
        uint256 oraclePrice,
        uint256 primaryAmount,
        uint256 secondaryAmount
    ) internal view {
        // Oracle price is always specified in terms of primary, so tokenIndex == 0 for primary
        uint256 spotPrice = _getSpotPrice({
            poolContext: poolContext,
            tokenIndex: 0
        });

        /// @notice Check spotPrice against oracle price to make sure that 
        /// the pool is not being manipulated
        strategyContext._checkPriceLimit(oraclePrice, spotPrice);

        /**
        TODO: below here nothing is returned, the reward reinvestment is the only place this is used
        uint256 primaryPrecision = 10**poolContext.basePool.primaryDecimals;
        uint256 secondaryPrecision = 10**poolContext.basePool.secondaryDecimals;

        // Convert input amounts and pool amounts to CURVE_PRECISION (1e18)
        primaryAmount = primaryAmount * strategyContext.poolClaimPrecision / primaryPrecision;
        secondaryAmount = secondaryAmount * strategyContext.poolClaimPrecision / secondaryPrecision;

        uint256 primaryPoolBalance = poolContext.basePool.primaryBalance * CurveConstants.CURVE_PRECISION 
            / primaryPrecision;
        uint256 secondaryPoolBalance = poolContext.basePool.secondaryBalance * CurveConstants.CURVE_PRECISION 
            / secondaryPrecision;
        */
    }
    
    /// @notice We value strategy tokens in terms of the primary balance. The time weighted
    /// primary balance is used in order to prevent pool manipulation.
    /// @param poolContext pool context variables
    /// @param strategyContext strategy context variables
    /// @param vaultShareAmount amount of vault shares
    /// @return underlyingValue underlying value of strategy tokens
    function _convertStrategyToUnderlying(
        Curve2TokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        uint256 vaultShareAmount
    ) internal view returns (int256 underlyingValue) {
        
        uint256 poolClaim 
            = strategyContext._convertStrategyTokensToPoolClaim(vaultShareAmount);

        (uint256 spotPrice, uint256 oraclePrice) = _getSpotPriceAndOraclePrice(poolContext, strategyContext);

        underlyingValue 
            = poolContext.basePool._getTimeWeightedPrimaryBalance({
                strategyContext: strategyContext,
                poolClaim: poolClaim,
                oraclePrice: oraclePrice, 
                spotPrice: spotPrice
            }).toInt();
    }   

    function _getSpotPriceAndOraclePrice(
        Curve2TokenPoolContext memory poolContext,
        StrategyContext memory strategyContext
    ) internal view returns (uint256 spotPrice, uint256 oraclePrice) {
        // Oracle price is always specified in terms of primary, so tokenIndex == 0 for primary
        // Validate the spot price to make sure the pool is not being manipulated
        spotPrice = poolContext._getSpotPrice(0); // tokenIndex
        oraclePrice = poolContext.basePool._getOraclePairPrice(strategyContext);
    }
}