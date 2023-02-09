// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    Balancer2TokenPoolContext,
    Balancer3TokenPoolContext,
    BoostedOracleContext,
    AuraStakingContext,
    UnderlyingPoolContext
} from "../../BalancerVaultTypes.sol";
import {
    StrategyContext,
    StrategyVaultSettings,
    StrategyVaultState,
    TwoTokenPoolContext,
    ThreeTokenPoolContext
} from "../../../common/VaultTypes.sol";
import {TypeConvert} from "../../../../global/TypeConvert.sol";
import {VaultConstants} from "../../../common/VaultConstants.sol";
import {BalancerConstants} from "../BalancerConstants.sol";
import {Deployments} from "../../../../global/Deployments.sol";
import {Errors} from "../../../../global/Errors.sol";
import {BalancerUtils} from "../pool/BalancerUtils.sol";
import {StableMath} from "../math/StableMath.sol";
import {LinearMath} from "../math/LinearMath.sol";
import {StrategyUtils} from "../../../common/internal/strategy/StrategyUtils.sol";
import {VaultStorage} from "../../../common/VaultStorage.sol";
import {ITradingModule} from "../../../../../interfaces/trading/ITradingModule.sol";
import {IBoostedPool, ILinearPool} from "../../../../../interfaces/balancer/IBalancerPool.sol";
import {TokenUtils, IERC20} from "../../../../utils/TokenUtils.sol";
import {Balancer2TokenPoolUtils} from "./Balancer2TokenPoolUtils.sol";
import {FixedPoint} from "../math/FixedPoint.sol";

library Balancer3TokenBoostedPoolUtils {
    using TypeConvert for uint256;
    using FixedPoint for uint256;
    using TypeConvert for int256;
    using TokenUtils for IERC20;
    using Balancer2TokenPoolUtils for Balancer2TokenPoolContext;
    using Balancer2TokenPoolUtils for TwoTokenPoolContext;
    using Balancer3TokenBoostedPoolUtils for Balancer3TokenPoolContext;
    using StrategyUtils for StrategyContext;
    using VaultStorage for StrategyVaultSettings;
    using VaultStorage for StrategyVaultState;

    function _getScaleFactor(
        Balancer3TokenPoolContext memory poolContext,
        uint8 tokenIndex
    ) private pure returns(uint256 scaleFactor) {
        if (tokenIndex == 0) {
            scaleFactor = poolContext.primaryScaleFactor;
        } else if (tokenIndex == 1) {
            scaleFactor = poolContext.secondaryScaleFactor;
        } else if (tokenIndex == 2) {
            scaleFactor = poolContext.tertiaryScaleFactor;
        }
    }

    function _getPrecision(
        ThreeTokenPoolContext memory poolContext,
        uint8 tokenIndex
    ) private pure returns(uint256 precision) {
        if (tokenIndex == 0) {
            precision = 10**poolContext.basePool.primaryDecimals;
        } else if (tokenIndex == 1) {
            precision = 10**poolContext.basePool.secondaryDecimals;
        } else if (tokenIndex == 2) {
            precision = 10**poolContext.tertiaryDecimals;
        }
    }

    /// @notice Spot price is always expressed in terms of the primary currency
    function _getSpotPrice(
        Balancer3TokenPoolContext memory poolContext, 
        BoostedOracleContext memory oracleContext,
        uint8 tokenIndex
    ) internal pure returns (uint256 spotPrice) {
        require(tokenIndex < 3);  /// @dev invalid token index

        // Exchange rate of primary currency = 1
        if (tokenIndex == 0) {
            return BalancerConstants.BALANCER_PRECISION;
        }

        uint256[] memory balances = _getScaledBalances(poolContext);
        uint256 invariant = StableMath._calculateInvariant(
            oracleContext.ampParam, balances, true // roundUp = true
        );
        spotPrice = _getSpotPriceWithInvariant({
            poolContext: poolContext,
            oracleContext: oracleContext,
            balances: balances, 
            invariant: invariant,
            tokenIndex: tokenIndex
        });
    }

    function _getUnderlyingBPTOut(
        UnderlyingPoolContext memory pool,
        uint256 mainIn
    ) private pure returns (uint256) {
        uint256 scaledMainBalance = pool.mainBalance * pool.mainScaleFactor /
            BalancerConstants.BALANCER_PRECISION;
        uint256 scaledWrappedBalance = pool.wrappedBalance * pool.wrappedScaleFactor /
            BalancerConstants.BALANCER_PRECISION;

        // Convert from linear pool BPT to primary Amount
        return LinearMath._calcBptOutPerMainIn({
            mainIn: mainIn,
            mainBalance: scaledMainBalance,
            wrappedBalance: scaledWrappedBalance,
            bptSupply: pool.virtualSupply,
            params: LinearMath.Params({
                fee: pool.fee,
                lowerTarget: pool.lowerTarget,
                upperTarget: pool.upperTarget
            }) 
        });
    }

    function _getUnderlyingMainOut(
        UnderlyingPoolContext memory pool,
        uint256 bptIn
    ) private pure returns (uint256) {
        uint256 scaledMainBalance = pool.mainBalance * pool.mainScaleFactor /
            BalancerConstants.BALANCER_PRECISION;
        uint256 scaledWrappedBalance = pool.wrappedBalance * pool.wrappedScaleFactor /
            BalancerConstants.BALANCER_PRECISION;

        // Convert from linear pool BPT to primary Amount
        return LinearMath._calcMainOutPerBptIn({
            bptIn: bptIn,
            mainBalance: scaledMainBalance,
            wrappedBalance: scaledWrappedBalance,
            bptSupply: pool.virtualSupply,
            params: LinearMath.Params({
                fee: pool.fee,
                lowerTarget: pool.lowerTarget,
                upperTarget: pool.upperTarget
            }) 
        });
    }

    /// @notice Spot price is always expressed in terms of the primary currency
    function _getSpotPriceWithInvariant(
        Balancer3TokenPoolContext memory poolContext, 
        BoostedOracleContext memory oracleContext,
        uint256[] memory balances,
        uint256 invariant,
        uint8 tokenIndex
    ) private pure returns (uint256 spotPrice) {
        // Trade 1 unit of tokenIn for tokenOut to get the spot price
        // AmountIn needs to be in underlying precision because mainScaleFactor
        // will convert it to 1e18
        uint256 amountIn = _getPrecision(poolContext.basePool, tokenIndex);

        UnderlyingPoolContext memory inPool = oracleContext.underlyingPools[tokenIndex];
        amountIn = amountIn * inPool.mainScaleFactor / BalancerConstants.BALANCER_PRECISION;
        uint256 linearBPTIn = _getUnderlyingBPTOut(inPool, amountIn);

        linearBPTIn = linearBPTIn * _getScaleFactor(poolContext, tokenIndex) / BalancerConstants.BALANCER_PRECISION;

        uint256 linearBPTOut = StableMath._calcOutGivenIn({
            amplificationParameter: oracleContext.ampParam,
            balances: balances,
            tokenIndexIn: tokenIndex,
            tokenIndexOut: 0, // Primary index
            tokenAmountIn: linearBPTIn,
            invariant: invariant
        });

        linearBPTOut = linearBPTOut * BalancerConstants.BALANCER_PRECISION / _getScaleFactor(poolContext, 0);

        UnderlyingPoolContext memory outPool = oracleContext.underlyingPools[0];
        spotPrice = _getUnderlyingMainOut(outPool, linearBPTOut);
        spotPrice = spotPrice * BalancerConstants.BALANCER_PRECISION / outPool.mainScaleFactor;

        // Convert precision back to 1e18 after downscaling by mainScaleFactor
        // primary currency = index 0
        spotPrice = spotPrice * BalancerConstants.BALANCER_PRECISION / _getPrecision(poolContext.basePool, 0);
    }

    function _validateSpotPrice(
        Balancer3TokenPoolContext memory poolContext, 
        BoostedOracleContext memory oracleContext,
        StrategyContext memory context,
        address tokenIn,
        address tokenOut,
        uint8 tokenIndex,
        uint256[] memory balances,
        uint256 invariant
    ) private view {
        (int256 answer, int256 decimals) = context.tradingModule.getOraclePrice(tokenOut, tokenIn);
        require(decimals == int256(BalancerConstants.BALANCER_PRECISION));
        
        uint256 spotPrice = _getSpotPriceWithInvariant({
            poolContext: poolContext,
            oracleContext: oracleContext,
            balances: balances, 
            invariant: invariant,
            tokenIndex: tokenIndex
        });

        uint256 oraclePrice = answer.toUint();
        uint256 lowerLimit = (oraclePrice * 
            (VaultConstants.VAULT_PERCENT_BASIS - context.vaultSettings.oraclePriceDeviationLimitPercent)) / 
            VaultConstants.VAULT_PERCENT_BASIS;
        uint256 upperLimit = (oraclePrice * 
            (VaultConstants.VAULT_PERCENT_BASIS + context.vaultSettings.oraclePriceDeviationLimitPercent)) / 
            VaultConstants.VAULT_PERCENT_BASIS;

        // Check spot price against oracle price to make sure it hasn't been manipulated
        if (spotPrice < lowerLimit || upperLimit < spotPrice) {
            revert Errors.InvalidPrice(oraclePrice, spotPrice);
        }
    }

    function _validateTokenPrices(
        Balancer3TokenPoolContext memory poolContext, 
        BoostedOracleContext memory oracleContext,
        StrategyContext memory strategyContext,
        uint256[] memory balances,
        uint256 invariant
    ) private view {
        address primaryUnderlying = ILinearPool(address(poolContext.basePool.basePool.primaryToken)).getMainToken();
        address secondaryUnderlying = ILinearPool(address(poolContext.basePool.basePool.secondaryToken)).getMainToken();
        address tertiaryUnderlying = ILinearPool(address(poolContext.basePool.tertiaryToken)).getMainToken();

        _validateSpotPrice({
            poolContext: poolContext,
            oracleContext: oracleContext,
            context: strategyContext,
            tokenIn: primaryUnderlying,
            tokenOut: secondaryUnderlying,
            tokenIndex: 1, // secondary index
            balances: balances,
            invariant: invariant
        });

        _validateSpotPrice({
            poolContext: poolContext,
            oracleContext: oracleContext,
            context: strategyContext,
            tokenIn: primaryUnderlying,
            tokenOut: tertiaryUnderlying,
            tokenIndex: 2, // tertiary index
            balances: balances,
            invariant: invariant
        });
    }

    function _getScaledBalances(Balancer3TokenPoolContext memory poolContext) 
        private pure returns (uint256[] memory amountsWithoutBpt) {
        amountsWithoutBpt = new uint256[](3);
        amountsWithoutBpt[0] = poolContext.basePool.basePool.primaryBalance * poolContext.primaryScaleFactor 
            / BalancerConstants.BALANCER_PRECISION;
        amountsWithoutBpt[1] = poolContext.basePool.basePool.secondaryBalance * poolContext.secondaryScaleFactor
            / BalancerConstants.BALANCER_PRECISION;
        amountsWithoutBpt[2] = poolContext.basePool.tertiaryBalance * poolContext.tertiaryScaleFactor
            / BalancerConstants.BALANCER_PRECISION;        
    }

    function _getValidatedPoolData(
        Balancer3TokenPoolContext memory poolContext,
        BoostedOracleContext memory oracleContext,
        StrategyContext memory strategyContext
    ) internal view returns (uint256[] memory balances, uint256 invariant) {
        balances = _getScaledBalances(poolContext);

        // Get the current and new invariants. Since we need a bigger new invariant, we round the current one up.
        invariant = StableMath._calculateInvariant(
            oracleContext.ampParam, balances, false // roundUp = false
        );

        // validate spot prices against oracle prices
        _validateTokenPrices({
            poolContext: poolContext,
            oracleContext: oracleContext,
            strategyContext: strategyContext,
            balances: balances,
            invariant: invariant
        });
    }

    /// @notice Gets the time-weighted primary token balance for a given bptAmount
    /// @dev Boosted pool can't use the Balancer oracle, using Chainlink instead
    /// @param poolContext pool context variables
    /// @param oracleContext oracle context variables
    /// @param bptAmount amount of balancer pool lp tokens
    /// @return primaryAmount primary token balance
    function _getTimeWeightedPrimaryBalance(
        Balancer3TokenPoolContext memory poolContext,
        BoostedOracleContext memory oracleContext,
        StrategyContext memory strategyContext,
        uint256 bptAmount
    ) internal view returns (uint256 primaryAmount) {
        (
           uint256[] memory balances, 
           uint256 invariant
        ) = _getValidatedPoolData(poolContext, oracleContext, strategyContext);

        // NOTE: For Boosted 3 token pools, the LP token (BPT) is just another
        // token in the pool. So, we first use _calcTokenOutGivenExactBptIn
        // to calculate the value of 1 BPT. Then, we scale it to the BPT
        // amount to get the value in terms of the primary currency.
        // Use virtual total supply and zero swap fees for joins
        uint256 linearBPTAmount = StableMath._calcTokenOutGivenExactBptIn({
            amp: oracleContext.ampParam, 
            balances: balances, 
            tokenIndex: 0, // Primary index
            bptAmountIn: BalancerConstants.BALANCER_PRECISION, // 1 BPT 
            bptTotalSupply: oracleContext.virtualSupply, 
            swapFeePercentage: oracleContext.swapFeePercentage, 
            currentInvariant: invariant
        });

        // Downscale BPT out
        linearBPTAmount = linearBPTAmount * BalancerConstants.BALANCER_PRECISION / poolContext.primaryScaleFactor;

        // Primary underlying pool = index 0
        primaryAmount = _getUnderlyingMainOut(oracleContext.underlyingPools[0], linearBPTAmount);

        uint256 primaryPrecision = 10 ** poolContext.basePool.basePool.primaryDecimals;
        primaryAmount = (primaryAmount * bptAmount * primaryPrecision) / BalancerConstants.BALANCER_PRECISION_SQUARED;
    }

    function _approveBalancerTokens(ThreeTokenPoolContext memory poolContext, address bptSpender) internal {
        poolContext.basePool._approveBalancerTokens(bptSpender);

        IERC20(poolContext.tertiaryToken).checkApprove(address(Deployments.BALANCER_VAULT), type(uint256).max);

        // For boosted pools, the tokens inside pool context are AaveLinearPool tokens.
        // So, we need to approve the _underlyingToken (primary borrow currency) for trading.
        ILinearPool underlyingPool = ILinearPool(poolContext.basePool.primaryToken);
        address primaryUnderlyingAddress = BalancerUtils.getTokenAddress(underlyingPool.getMainToken());
        IERC20(primaryUnderlyingAddress).checkApprove(address(Deployments.BALANCER_VAULT), type(uint256).max);
    }

    function _joinPoolExactTokensIn(Balancer3TokenPoolContext memory context, uint256 primaryAmount, uint256 minBPT)
        private returns (uint256 bptAmount) {
        ILinearPool underlyingPool = ILinearPool(address(context.basePool.basePool.primaryToken));

        // Swap underlyingToken for LinearPool BPT
        uint256 linearPoolBPT = BalancerUtils._swapGivenIn({
            poolId: underlyingPool.getPoolId(),
            tokenIn: underlyingPool.getMainToken(),
            tokenOut: address(underlyingPool),
            amountIn: primaryAmount,
            limit: 0 // slippage checked on the second swap
        });

        // Swap LinearPool BPT for Boosted BPT
        bptAmount = BalancerUtils._swapGivenIn({
            poolId: context.poolId,
            tokenIn: address(underlyingPool),
            tokenOut: address(context.basePool.basePool.poolToken), // Boosted pool
            amountIn: linearPoolBPT,
            limit: minBPT
        });
    }

    function _exitPoolExactBPTIn(Balancer3TokenPoolContext memory context, uint256 bptExitAmount, uint256 minPrimary)
        private returns (uint256 primaryBalance) {
        ILinearPool underlyingPool = ILinearPool(address(context.basePool.basePool.primaryToken));

        // Swap Boosted BPT for LinearPool BPT
        uint256 linearPoolBPT = BalancerUtils._swapGivenIn({
            poolId: context.poolId,
            tokenIn: address(context.basePool.basePool.poolToken), // Boosted pool
            tokenOut: address(underlyingPool),
            amountIn: bptExitAmount,
            limit: 0 // slippage checked on the second swap
        });

        // Swap LinearPool BPT for underlyingToken
        primaryBalance = BalancerUtils._swapGivenIn({
            poolId: underlyingPool.getPoolId(),
            tokenIn: address(underlyingPool),
            tokenOut: underlyingPool.getMainToken(),
            amountIn: linearPoolBPT,
            limit: minPrimary
        }); 
    }

    function _deposit(
        Balancer3TokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        BoostedOracleContext memory oracleContext,
        uint256 deposit,
        uint256 minBPT
    ) internal returns (uint256 strategyTokensMinted) {
        uint256 bptMinted = poolContext._joinPoolAndStake({
            strategyContext: strategyContext,
            stakingContext: stakingContext,
            oracleContext: oracleContext,
            deposit: deposit,
            minBPT: minBPT
        });

        strategyTokensMinted = strategyContext._mintStrategyTokens(bptMinted);
    }

    function _redeem(
        Balancer3TokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        uint256 strategyTokens,
        uint256 minPrimary
    ) internal returns (uint256 finalPrimaryBalance) {
        uint256 bptClaim = strategyContext._redeemStrategyTokens(strategyTokens);

        finalPrimaryBalance = _unstakeAndExitPool({
            stakingContext: stakingContext,
            poolContext: poolContext,
            bptClaim: bptClaim,
            minPrimary: minPrimary
        });
    }

    function _joinPoolAndStake(
        Balancer3TokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        BoostedOracleContext memory oracleContext,
        uint256 deposit,
        uint256 minBPT
    ) internal returns (uint256 bptMinted) {
        bptMinted = _joinPoolExactTokensIn(poolContext, deposit, minBPT);

        // Check BPT threshold to make sure our share of the pool is
        // below maxPoolShare
        uint256 bptThreshold = strategyContext.vaultSettings._poolClaimThreshold(
            oracleContext.virtualSupply
        );
        uint256 bptHeldAfterJoin = strategyContext.vaultState.totalPoolClaim + bptMinted;
        if (bptHeldAfterJoin > bptThreshold)
            revert Errors.PoolShareTooHigh(bptHeldAfterJoin, bptThreshold);

        // Transfer token to Aura protocol for boosted staking
        bool success = stakingContext.booster.deposit(stakingContext.poolId, bptMinted, true); // stake = true
        if (!success) revert Errors.StakeFailed();
    }

    function _unstakeAndExitPool(
        Balancer3TokenPoolContext memory poolContext,
        AuraStakingContext memory stakingContext,
        uint256 bptClaim,
        uint256 minPrimary
    ) internal returns (uint256 primaryBalance) {
        // Withdraw BPT tokens back to the vault for redemption
        bool success = stakingContext.rewardPool.withdrawAndUnwrap(bptClaim, false); // claimRewards = false
        if (!success) revert Errors.UnstakeFailed();

        primaryBalance = _exitPoolExactBPTIn(poolContext, bptClaim, minPrimary); 
    }

    /// @notice We value strategy tokens in terms of the primary balance. The time weighted
    /// primary balance is used in order to prevent pool manipulation.
    /// @param poolContext pool context variables
    /// @param oracleContext oracle context variables
    /// @param strategyTokenAmount amount of strategy tokens
    /// @return underlyingValue underlying value of strategy tokens
    function _convertStrategyToUnderlying(
        Balancer3TokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        BoostedOracleContext memory oracleContext,
        uint256 strategyTokenAmount
    ) internal view returns (int256 underlyingValue) {
        uint256 bptClaim = strategyContext._convertStrategyTokensToPoolClaim(strategyTokenAmount);
        
        underlyingValue = poolContext._getTimeWeightedPrimaryBalance(
            oracleContext, strategyContext, bptClaim
        ).toInt();
    }
}
