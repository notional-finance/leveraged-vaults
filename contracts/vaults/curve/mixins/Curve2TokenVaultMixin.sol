// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    ConvexVaultDeploymentParams, 
    Curve2TokenConvexStrategyContext,
    Curve2TokenPoolContext,
    TwoTokenPoolContext
} from "../CurveVaultTypes.sol";
import {Constants} from "../../../global/Constants.sol";
import {TypeConvert} from "../../../global/TypeConvert.sol";
import {StrategyContext} from "../../common/VaultTypes.sol";
import {TwoTokenPoolUtils} from "../../common/internal/pool/TwoTokenPoolUtils.sol";
import {Curve2TokenPoolMixin} from "./Curve2TokenPoolMixin.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {ICurve2TokenPool} from "../../../../interfaces/curve/ICurvePool.sol";
import {Curve2TokenPoolUtils} from "../internal/pool/Curve2TokenPoolUtils.sol";

abstract contract Curve2TokenVaultMixin is Curve2TokenPoolMixin {
    using Curve2TokenPoolUtils for Curve2TokenPoolContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using TypeConvert for uint256;

    constructor(NotionalProxy notional_, ConvexVaultDeploymentParams memory params)
        Curve2TokenPoolMixin(notional_, params) { }

    function _checkReentrancyContext() internal override {
        // We need to set the LP token amount to 1 for Curve V2 pools to bypass
        // the underflow check
        uint256[2] memory minAmounts;
        ICurve2TokenPool(address(CURVE_POOL)).remove_liquidity(IS_CURVE_V2 ? 1 : 0, minAmounts);
    }

    function _strategyContext() internal view returns (Curve2TokenConvexStrategyContext memory) {
        return Curve2TokenConvexStrategyContext({
            baseStrategy: _baseStrategyContext(),
            poolContext: _twoTokenPoolContext(),
            stakingContext: _convexStakingContext()
        });
    }

    function getExchangeRate(uint256 maturity) public view override returns (int256) {
        Curve2TokenConvexStrategyContext memory context = _strategyContext();
        if (context.baseStrategy.vaultState.totalVaultSharesGlobal == 0) {
            (uint256 spotPrice, uint256 oraclePrice) = context.poolContext._getSpotPriceAndOraclePrice(
                context.baseStrategy
            );

            return context.poolContext.basePool._getTimeWeightedPrimaryBalance({
                strategyContext: context.baseStrategy,
                poolClaim: context.baseStrategy.poolClaimPrecision, // 1 pool token
                oraclePrice: oraclePrice, 
                spotPrice: spotPrice
            }).toInt();
        } else {
            return context.poolContext._convertStrategyToUnderlying({
                strategyContext: context.baseStrategy,
                strategyTokenAmount: uint256(Constants.INTERNAL_TOKEN_PRECISION) // 1 vault share
            });
        }
    }

    function getStrategyVaultInfo() public view override returns (SingleSidedLPStrategyVaultInfo memory) {
        StrategyContext memory context = _baseStrategyContext();
        return SingleSidedLPStrategyVaultInfo({
            pool: address(CURVE_POOL),
            singleSidedTokenIndex: PRIMARY_INDEX,
            totalLPTokens: context.vaultState.totalPoolClaim,
            totalVaultShares: context.vaultState.totalVaultSharesGlobal
        });        
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}
