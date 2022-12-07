// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    ThreeTokenPoolContext,
    TwoTokenPoolContext,
    BoostedOracleContext,
    UnderlyingPoolContext,
    AuraStakingContext,
    StrategyContext,
    StrategyVaultSettings,
    StrategyVaultState
} from "../../BalancerVaultTypes.sol";
import {TypeConvert} from "../../../../global/TypeConvert.sol";
import {BalancerConstants} from "../BalancerConstants.sol";
import {Deployments} from "../../../../global/Deployments.sol";
import {Errors} from "../../../../global/Errors.sol";
import {BalancerUtils} from "../pool/BalancerUtils.sol";
import {Boosted3TokenPoolUtils} from "../pool/Boosted3TokenPoolUtils.sol";
import {StableMath} from "../math/StableMath.sol";
import {LinearMath} from "../math/LinearMath.sol";
import {AuraStakingUtils} from "../staking/AuraStakingUtils.sol";
import {StrategyUtils} from "../strategy/StrategyUtils.sol";
import {BalancerVaultStorage} from "../BalancerVaultStorage.sol";
import {ITradingModule} from "../../../../../interfaces/trading/ITradingModule.sol";
import {ILinearPool} from "../../../../../interfaces/balancer/IBalancerPool.sol";
import {TokenUtils, IERC20} from "../../../../utils/TokenUtils.sol";
import {TwoTokenPoolUtils} from "./TwoTokenPoolUtils.sol";
import {FixedPoint} from "../math/FixedPoint.sol";

library Boosted3TokenPoolUtils {
    using TypeConvert for uint256;
    using FixedPoint for uint256;
    using TypeConvert for int256;
    using TokenUtils for IERC20;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using Boosted3TokenPoolUtils for ThreeTokenPoolContext;
    using AuraStakingUtils for AuraStakingContext;
    using StrategyUtils for StrategyContext;
    using BalancerVaultStorage for StrategyVaultSettings;
    using BalancerVaultStorage for StrategyVaultState;

    // Preminted BPT is sometimes called Phantom BPT, as the preminted BPT (which is deposited in the Vault as balance of
    // the Pool) doesn't belong to any entity until transferred out of the Pool. The Pool's arithmetic behaves as if it
    // didn't exist, and the BPT total supply is not a useful value: we rely on the 'virtual supply' (how much BPT is
    // actually owned by some entity) instead.
    uint256 private constant _MAX_TOKEN_BALANCE = 2**(112) - 1;

    function _getScaleFactor(
        ThreeTokenPoolContext memory poolContext,
        uint8 tokenIndex
    ) private view returns(uint256 scaleFactor) {
        if (tokenIndex == poolContext.tertiaryIndex) {
            scaleFactor = poolContext.tertiaryScaleFactor;
        } else if (tokenIndex == poolContext.basePool.secondaryIndex) {
            scaleFactor = poolContext.basePool.secondaryScaleFactor;
        } else if (tokenIndex == poolContext.basePool.primaryIndex) {
            scaleFactor = poolContext.basePool.primaryScaleFactor;
        }
    }

    function _validateTokenIndex(ThreeTokenPoolContext memory poolContext, uint8 tokenIndex) private pure {
        if (
            tokenIndex != poolContext.basePool.primaryIndex && 
            tokenIndex != poolContext.basePool.secondaryIndex && 
            tokenIndex != poolContext.tertiaryIndex
        ) {
            revert Errors.InvalidTokenIndex(tokenIndex);
        }
    }

    function _getSpotPrice(
        ThreeTokenPoolContext memory poolContext, 
        BoostedOracleContext memory oracleContext,
        uint8 tokenIndexIn, 
        uint8 tokenIndexOut
    ) internal pure returns (uint256 spotPrice) {
        _validateTokenIndex(poolContext, tokenIndexIn);
        _validateTokenIndex(poolContext, tokenIndexOut);

        uint256[] memory balances = _getScaledBalances(poolContext);
        uint256 invariant = StableMath._calculateInvariant(
            oracleContext.ampParam, balances, true // roundUp = true
        );
        spotPrice = _getSpotPriceWithInvariant({
            poolContext: poolContext,
            oracleContext: oracleContext,
            balances: balances, 
            invariant: invariant,
            tokenIndexIn: tokenIndexIn, // Primary index
            tokenIndexOut: tokenIndexOut // Secondary index
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

    function _getSpotPriceWithInvariant(
        ThreeTokenPoolContext memory poolContext, 
        BoostedOracleContext memory oracleContext,
        uint256[] memory balances,
        uint256 invariant,
        uint8 tokenIndexIn, 
        uint8 tokenIndexOut
    ) private pure returns (uint256 spotPrice) {
        // Trade 1 unit of tokenIn for tokenOut to get the spot price
        uint256 amountIn = BalancerConstants.BALANCER_PRECISION;

        UnderlyingPoolContext memory inPool = oracleContext.underlyingPools[tokenIndexIn];
        amountIn = amountIn * inPool.mainScaleFactor / BalancerConstants.BALANCER_PRECISION;
        uint256 linearBPTIn = _getUnderlyingBPTOut(inPool, amountIn);

        uint256 linearBPTOut = StableMath._calcOutGivenIn({
            amplificationParameter: oracleContext.ampParam,
            balances: balances,
            tokenIndexIn: tokenIndexIn,
            tokenIndexOut: tokenIndexOut,
            tokenAmountIn: linearBPTIn,
            invariant: invariant
        });

        UnderlyingPoolContext memory outPool = oracleContext.underlyingPools[tokenIndexOut];

        spotPrice = _getUnderlyingMainOut(outPool, linearBPTOut);
        spotPrice = spotPrice * BalancerConstants.BALANCER_PRECISION / outPool.mainScaleFactor;
    }

    function _validateSpotPrice(
        StrategyContext memory context,
        address tokenIn,
        uint8 tokenIndexIn,
        address tokenOut,
        uint8 tokenIndexOut,
        uint256[] memory balances,
        uint256 ampParam,
        uint256 invariant
    ) private view {
        (int256 answer, int256 decimals) = context.tradingModule.getOraclePrice(tokenOut, tokenIn);
        require(decimals == int256(BalancerConstants.BALANCER_PRECISION));
        
        uint256 spotPrice = 0; /*_getSpotPriceWithInvariant({
            ampParam: ampParam,
            invariant: invariant,
            balances: balances, 
            tokenIndexIn: tokenIndexIn, // Primary index
            tokenIndexOut: tokenIndexOut // Secondary index
        }); */

        uint256 oraclePrice = answer.toUint();
        uint256 lowerLimit = (oraclePrice * 
            (BalancerConstants.VAULT_PERCENT_BASIS - context.vaultSettings.oraclePriceDeviationLimitPercent)) / 
            BalancerConstants.VAULT_PERCENT_BASIS;
        uint256 upperLimit = (oraclePrice * 
            (BalancerConstants.VAULT_PERCENT_BASIS + context.vaultSettings.oraclePriceDeviationLimitPercent)) / 
            BalancerConstants.VAULT_PERCENT_BASIS;

        // Check spot price against oracle price to make sure it hasn't been manipulated
        if (spotPrice < lowerLimit || upperLimit < spotPrice) {
            revert Errors.InvalidPrice(oraclePrice, spotPrice);
        }
    }

    function _validateTokenPrices(
        ThreeTokenPoolContext memory poolContext, 
        StrategyContext memory strategyContext,
        uint256[] memory balances,
        uint256 ampParam,
        uint256 invariant
    ) private view {
        address primaryUnderlying = ILinearPool(address(poolContext.basePool.primaryToken)).getMainToken();
        address secondaryUnderlying = ILinearPool(address(poolContext.basePool.secondaryToken)).getMainToken();
        address tertiaryUnderlying = ILinearPool(address(poolContext.tertiaryToken)).getMainToken();

        _validateSpotPrice({
            context: strategyContext,
            tokenIn: primaryUnderlying,
            tokenIndexIn: 0, // primary index
            tokenOut: secondaryUnderlying,
            tokenIndexOut: 1, // secondary index
            balances: balances,
            ampParam: ampParam,
            invariant: invariant
        });

        _validateSpotPrice({
            context: strategyContext,
            tokenIn: primaryUnderlying,
            tokenIndexIn: 0, // primary index
            tokenOut: tertiaryUnderlying,
            tokenIndexOut: 2, // secondary index
            balances: balances,
            ampParam: ampParam,
            invariant: invariant
        });
    }

    function _getVirtualSupply(
        ThreeTokenPoolContext memory poolContext, 
        BoostedOracleContext memory oracleContext
    ) internal view returns (uint256 virtualSupply) {
        // The initial amount of BPT pre-minted is _PREMINTED_TOKEN_BALANCE, and it goes entirely to the pool balance in
        // the vault. So the virtualSupply (the amount of BPT supply in circulation) is defined as:
        // virtualSupply = totalSupply() - _balances[_bptIndex]
        virtualSupply = poolContext.basePool.basePool.pool.totalSupply() - oracleContext.bptBalance;
    }

    function _getScaledBalances(ThreeTokenPoolContext memory poolContext) 
        private pure returns (uint256[] memory amountsWithoutBpt) {
        amountsWithoutBpt = new uint256[](3);
        amountsWithoutBpt[0] = poolContext.basePool.primaryBalance * poolContext.basePool.primaryScaleFactor 
            / BalancerConstants.BALANCER_PRECISION;
        amountsWithoutBpt[1] = poolContext.basePool.secondaryBalance * poolContext.basePool.secondaryScaleFactor
            / BalancerConstants.BALANCER_PRECISION;
        amountsWithoutBpt[2] = poolContext.tertiaryBalance * poolContext.tertiaryScaleFactor
            / BalancerConstants.BALANCER_PRECISION;        
    }

    function _getVirtualSupplyAndBalances(
        ThreeTokenPoolContext memory poolContext, 
        BoostedOracleContext memory oracleContext
    ) private view returns (uint256 virtualSupply, uint256[] memory amountsWithoutBpt) {
        virtualSupply = _getVirtualSupply(poolContext, oracleContext);
        amountsWithoutBpt = _getScaledBalances(poolContext);
    }

    function _getValidatedPoolData(
        ThreeTokenPoolContext memory poolContext,
        BoostedOracleContext memory oracleContext,
        StrategyContext memory strategyContext
    ) internal view returns (uint256 virtualSupply, uint256[] memory balances, uint256 invariant) {
        (virtualSupply, balances) = 
            _getVirtualSupplyAndBalances(poolContext, oracleContext);

        // Get the current and new invariants. Since we need a bigger new invariant, we round the current one up.
        invariant = StableMath._calculateInvariant(
            oracleContext.ampParam, balances, true // roundUp = true
        );

        // validate spot prices against oracle prices
        _validateTokenPrices({
            poolContext: poolContext,
            strategyContext: strategyContext,
            balances: balances,
            ampParam: oracleContext.ampParam,
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
        ThreeTokenPoolContext memory poolContext,
        BoostedOracleContext memory oracleContext,
        StrategyContext memory strategyContext,
        uint256 bptAmount
    ) internal view returns (uint256 primaryAmount) {
        (
           uint256 virtualSupply, 
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
            tokenIndex: 0, 
            bptAmountIn: BalancerConstants.BALANCER_PRECISION, // 1 BPT 
            bptTotalSupply: virtualSupply, 
            swapFeePercentage: oracleContext.swapFeePercentage, 
            currentInvariant: invariant
        });

        // Downscale BPT out
        linearBPTAmount = linearBPTAmount * BalancerConstants.BALANCER_PRECISION / poolContext.basePool.primaryScaleFactor;

        // Primary underlying pool = index 0
        primaryAmount = _getUnderlyingMainOut(oracleContext.underlyingPools[0], linearBPTAmount);

        uint256 primaryPrecision = 10 ** poolContext.basePool.primaryDecimals;
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

    function _joinPoolExactTokensIn(ThreeTokenPoolContext memory context, uint256 primaryAmount, uint256 minBPT)
        private returns (uint256 bptAmount) {
        ILinearPool underlyingPool = ILinearPool(address(context.basePool.primaryToken));

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
            poolId: context.basePool.basePool.poolId,
            tokenIn: address(underlyingPool),
            tokenOut: address(context.basePool.basePool.pool), // Boosted pool
            amountIn: linearPoolBPT,
            limit: minBPT
        });
    }

    function _exitPoolExactBPTIn(ThreeTokenPoolContext memory context, uint256 bptExitAmount, uint256 minPrimary)
        private returns (uint256 primaryBalance) {
        ILinearPool underlyingPool = ILinearPool(address(context.basePool.primaryToken));

        // Swap Boosted BPT for LinearPool BPT
        uint256 linearPoolBPT = BalancerUtils._swapGivenIn({
            poolId: context.basePool.basePool.poolId,
            tokenIn: address(context.basePool.basePool.pool), // Boosted pool
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
        ThreeTokenPoolContext memory poolContext,
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

        strategyTokensMinted = strategyContext._convertBPTClaimToStrategyTokens(bptMinted);

        strategyContext.vaultState.totalBPTHeld += bptMinted;
        // Update global supply count
        strategyContext.vaultState.totalStrategyTokenGlobal += strategyTokensMinted.toUint80();
        strategyContext.vaultState.setStrategyVaultState(); 
    }

    function _redeem(
        ThreeTokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        uint256 strategyTokens,
        uint256 minPrimary
    ) internal returns (uint256 finalPrimaryBalance) {
        uint256 bptClaim = strategyContext._convertStrategyTokensToBPTClaim(strategyTokens);

        if (bptClaim == 0) return 0;

        finalPrimaryBalance = _unstakeAndExitPool({
            stakingContext: stakingContext,
            poolContext: poolContext,
            bptClaim: bptClaim,
            minPrimary: minPrimary
        });

        strategyContext.vaultState.totalBPTHeld -= bptClaim;
        strategyContext.vaultState.totalStrategyTokenGlobal -= strategyTokens.toUint80();
        strategyContext.vaultState.setStrategyVaultState(); 
    }

    function _joinPoolAndStake(
        ThreeTokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        BoostedOracleContext memory oracleContext,
        uint256 deposit,
        uint256 minBPT
    ) internal returns (uint256 bptMinted) {
        bptMinted = _joinPoolExactTokensIn(poolContext, deposit, minBPT);

        // Check BPT threshold to make sure our share of the pool is
        // below maxBalancerPoolShare
        uint256 bptThreshold = strategyContext.vaultSettings._bptThreshold(
            poolContext._getVirtualSupply(oracleContext)
        );
        uint256 bptHeldAfterJoin = strategyContext.vaultState.totalBPTHeld + bptMinted;
        if (bptHeldAfterJoin > bptThreshold)
            revert Errors.BalancerPoolShareTooHigh(bptHeldAfterJoin, bptThreshold);

        // Transfer token to Aura protocol for boosted staking
        bool success = stakingContext.auraBooster.deposit(stakingContext.auraPoolId, bptMinted, true); // stake = true
        if (!success) revert Errors.StakeFailed();
    }

    function _unstakeAndExitPool(
        ThreeTokenPoolContext memory poolContext,
        AuraStakingContext memory stakingContext,
        uint256 bptClaim,
        uint256 minPrimary
    ) internal returns (uint256 primaryBalance) {
        // Withdraw BPT tokens back to the vault for redemption
        bool success = stakingContext.auraRewardPool.withdrawAndUnwrap(bptClaim, false); // claimRewards = false
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
        ThreeTokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        BoostedOracleContext memory oracleContext,
        uint256 strategyTokenAmount
    ) internal view returns (int256 underlyingValue) {
        uint256 bptClaim = strategyContext._convertStrategyTokensToBPTClaim(strategyTokenAmount);
        
        underlyingValue = poolContext._getTimeWeightedPrimaryBalance(
            oracleContext, strategyContext, bptClaim
        ).toInt();
    }
}
