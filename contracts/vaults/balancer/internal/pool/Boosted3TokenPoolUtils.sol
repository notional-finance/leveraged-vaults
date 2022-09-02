// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    ThreeTokenPoolContext,
    TwoTokenPoolContext,
    BoostedOracleContext,
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
import {AuraStakingUtils} from "../staking/AuraStakingUtils.sol";
import {StrategyUtils} from "../strategy/StrategyUtils.sol";
import {BalancerVaultStorage} from "../BalancerVaultStorage.sol";
import {ITradingModule} from "../../../../../interfaces/trading/ITradingModule.sol";
import {IBoostedPool} from "../../../../../interfaces/balancer/IBalancerPool.sol";
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

    function _getSpotPrice(
        uint256 ampParam,
        uint256 invariant,
        uint256[] memory balances, 
        uint8 tokenIndexIn, 
        uint8 tokenIndexOut
    ) private pure returns (uint256 spotPrice) {
        // Trade 1 unit of tokenIn for tokenOut to get the spot price
        uint256 amountIn = BalancerConstants.BALANCER_PRECISION;
        uint256 amountOut = StableMath._calcOutGivenIn({
            amplificationParameter: ampParam,
            balances: balances,
            tokenIndexIn: tokenIndexIn,
            tokenIndexOut: tokenIndexOut,
            tokenAmountIn: amountIn,
            invariant: invariant
        });
        spotPrice = amountOut;
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
        
        uint256 spotPrice = _getSpotPrice({
            ampParam: ampParam,
            invariant: invariant,
            balances: balances, 
            tokenIndexIn: tokenIndexIn, // Primary index
            tokenIndexOut: tokenIndexOut // Secondary index
        }); 

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
        address primaryUnderlying = IBoostedPool(address(poolContext.basePool.primaryToken)).getMainToken();
        address secondaryUnderlying = IBoostedPool(address(poolContext.basePool.secondaryToken)).getMainToken();
        address tertiaryUnderlying = IBoostedPool(address(poolContext.tertiaryToken)).getMainToken();

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
    ) internal pure returns (uint256 virtualSupply) {
        // The initial amount of BPT pre-minted is _MAX_TOKEN_BALANCE and it goes entirely to the pool balance in the
        // vault. So the virtualSupply (the actual supply in circulation) is defined as:
        // virtualSupply = totalSupply() - (_balances[_bptIndex] - _dueProtocolFeeBptAmount)
        //
        // However, since this Pool never mints or burns BPT outside of the initial supply (except in the event of an
        // emergency pause), we can simply use `_MAX_TOKEN_BALANCE` instead of `totalSupply()` and save
        // gas.
        virtualSupply = _MAX_TOKEN_BALANCE - oracleContext.bptBalance + oracleContext.dueProtocolFeeBptAmount;
    }

    function _getVirtualSupplyAndBalances(
        ThreeTokenPoolContext memory poolContext, 
        BoostedOracleContext memory oracleContext
    ) private pure returns (uint256 virtualSupply, uint256[] memory amountsWithoutBpt) {
        virtualSupply = _getVirtualSupply(poolContext, oracleContext);

        amountsWithoutBpt = new uint256[](3);
        amountsWithoutBpt[0] = poolContext.basePool.primaryBalance;
        amountsWithoutBpt[1] = poolContext.basePool.secondaryBalance;
        amountsWithoutBpt[2] = poolContext.tertiaryBalance;
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
        primaryAmount = StableMath._calcTokenOutGivenExactBptIn({
            amp: oracleContext.ampParam, 
            balances: balances, 
            tokenIndex: 0, 
            bptAmountIn: BalancerConstants.BALANCER_PRECISION, // 1 BPT 
            bptTotalSupply: virtualSupply, 
            swapFeePercentage: 0, 
            currentInvariant: invariant
        });

        uint256 primaryPrecision = 10 ** poolContext.basePool.primaryDecimals;
        primaryAmount = (primaryAmount * bptAmount * primaryPrecision) / BalancerConstants.BALANCER_PRECISION_SQUARED;
    }

    function _approveBalancerTokens(ThreeTokenPoolContext memory poolContext, address bptSpender) internal {
        poolContext.basePool._approveBalancerTokens(bptSpender);

        IERC20(poolContext.tertiaryToken).checkApprove(address(Deployments.BALANCER_VAULT), type(uint256).max);

        // For boosted pools, the tokens inside pool context are AaveLinearPool tokens.
        // So, we need to approve the _underlyingToken (primary borrow currency) for trading.
        IBoostedPool underlyingPool = IBoostedPool(poolContext.basePool.primaryToken);
        address primaryUnderlyingAddress = BalancerUtils.getTokenAddress(underlyingPool.getMainToken());
        IERC20(primaryUnderlyingAddress).checkApprove(address(Deployments.BALANCER_VAULT), type(uint256).max);
    }

    function _joinPoolExactTokensIn(ThreeTokenPoolContext memory context, uint256 primaryAmount, uint256 minBPT)
        private returns (uint256 bptAmount) {
        IBoostedPool underlyingPool = IBoostedPool(address(context.basePool.primaryToken));

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
        IBoostedPool underlyingPool = IBoostedPool(address(context.basePool.primaryToken));

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
        uint256 bptHeldAfterJoin = strategyContext.totalBPTHeld + bptMinted;
        if (bptHeldAfterJoin > bptThreshold)
            revert Errors.BalancerPoolShareTooHigh(bptHeldAfterJoin, bptThreshold);

        // Transfer token to Aura protocol for boosted staking
        stakingContext.auraBooster.deposit(stakingContext.auraPoolId, bptMinted, true); // stake = true
    }

    function _unstakeAndExitPool(
        ThreeTokenPoolContext memory poolContext,
        AuraStakingContext memory stakingContext,
        uint256 bptClaim,
        uint256 minPrimary
    ) internal returns (uint256 primaryBalance) {
        // Withdraw BPT tokens back to the vault for redemption
        stakingContext.auraRewardPool.withdrawAndUnwrap(bptClaim, false); // claimRewards = false

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

    function _getMinBPT(
        ThreeTokenPoolContext calldata poolContext,
        BoostedOracleContext calldata oracleContext,
        StrategyContext calldata strategyContext,
        uint256 primaryAmount
    ) internal view returns (uint256 minBPT) {
        // Calculate minBPT to minimize slippage
        (
            uint256 virtualSupply, 
            uint256[] memory balances, 
            uint256 invariant
        ) = poolContext._getValidatedPoolData(oracleContext, strategyContext);

        uint256[] memory amountsIn = new uint256[](3);
        // _getValidatedPoolData rearranges the balances so that primary is always in the
        // zero index spot
        /// @notice Balancer math functions expect all amounts to be in BALANCER_PRECISION
        uint256 primaryPrecision = 10 ** poolContext.basePool.primaryDecimals;
        amountsIn[0] = primaryAmount * BalancerConstants.BALANCER_PRECISION / primaryPrecision;

        minBPT = StableMath._calcBptOutGivenExactTokensIn({
            amp: oracleContext.ampParam,
            balances: balances,
            amountsIn: amountsIn,
            bptTotalSupply: virtualSupply,
            swapFeePercentage: 0,
            currentInvariant: invariant
        });

        uint256 swapFeePercentage = IBoostedPool(address(poolContext.basePool.basePool.pool))
            .getCachedProtocolSwapFeePercentage();

        if (swapFeePercentage > 0) {
            minBPT -= _getDueProtocolFeeByBpt(minBPT, swapFeePercentage);
        }

        minBPT = minBPT * strategyContext.vaultSettings.balancerPoolSlippageLimitPercent / 
            uint256(BalancerConstants.VAULT_PERCENT_BASIS);
    }

    function _addSwapFeeAmount(uint256 amount, uint256 protocolSwapFeePercentage) private view returns (uint256) {
        // This returns amount + fee amount, so we round up (favoring a higher fee amount).
        return amount.divUp(FixedPoint.ONE.sub(protocolSwapFeePercentage));
    }

    function _getDueProtocolFeeByBpt(
        uint256 bptAmount,
        uint256 protocolSwapFeePercentage
    ) private view returns (uint256) {
        uint256 feeAmount = _addSwapFeeAmount(bptAmount, protocolSwapFeePercentage).sub(bptAmount);

        uint256 protocolFeeAmount = feeAmount.mulDown(protocolSwapFeePercentage);
        return protocolFeeAmount;
    }
}
