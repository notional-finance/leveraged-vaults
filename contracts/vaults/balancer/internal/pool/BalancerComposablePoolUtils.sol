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
    ComposableDepositParams,
    ComposableRedeemParams
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
import {IAuraBoosterBase} from "../../../../../interfaces/aura/IAuraBooster.sol";
import {DexId} from "../../../../../interfaces/trading/ITradingModule.sol";
import {TypeConvert} from "../../../../global/TypeConvert.sol";

library BalancerComposablePoolUtils {
    using TokenUtils for IERC20;
    using TypeConvert for uint256;
    using StrategyUtils for StrategyContext;
    using VaultStorage for StrategyVaultSettings;
    using VaultStorage for StrategyVaultState;
    using ComposableOracleMath for ComposableOracleContext;

    /// @notice Returns parameters for joining and exiting Balancer pools
    /// @param bptAmount minBptAmount if isJoin is true, bptExitAmount if isJoin is false
    function _getPoolParams(
        BalancerComposablePoolContext memory context,
        uint256[] memory amounts,
        bool isJoin,
        bool isSingleSided,
        uint256 bptAmount
    ) internal pure returns (PoolParams memory) {
        IAsset[] memory assets = new IAsset[](context.basePool.tokens.length);

        uint256 msgValue;
        for (uint256 i; i < context.basePool.tokens.length; i++) {
            assets[i] = IAsset(context.basePool.tokens[i]);
            if (isJoin) {
                if (assets[i] == IAsset(Deployments.ETH_ADDRESS)) {
                    msgValue += amounts[i];
                }
            }
        }

        bytes memory customData;
        if (isJoin) {
            customData = abi.encode(
                IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                _getAmountsWithoutBpt(context, amounts),
                bptAmount // Apply minBPT to prevent front running
            );
        } else {
            if (isSingleSided) {
                // See this line here:
                // https://github.com/balancer/balancer-v2-monorepo/blob/c7d4abbea39834e7778f9ff7999aaceb4e8aa048/pkg/pool-stable/contracts/ComposableStablePool.sol#L927
                // While "assets" sent to the vault include the BPT token the tokenIndex passed in by this
                // function does not include the BPT. primaryIndex in this code is inclusive of the BPT token in
                // the assets array. Therefore, if primaryIndex > bptIndex subtract one to ensure that the primaryIndex
                // does not include the BPT token here.
                uint256 primaryIndex = context.basePool.primaryIndex;
                customData = abi.encode(
                    IBalancerVault.ComposableExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
                    bptAmount,
                    primaryIndex < context.bptIndex ?  primaryIndex : primaryIndex - 1
                );
            } else {
                customData = abi.encode(
                    IBalancerVault.ComposableExitKind.EXACT_BPT_IN_FOR_ALL_TOKENS_OUT,
                    bptAmount
                );
            }
        }

        return PoolParams(assets, amounts, msgValue, customData);
    }

    function _getAmountsWithoutBpt(BalancerComposablePoolContext memory context, uint256[] memory inAmounts) 
        private pure returns (uint256[] memory amountsWithoutBpt) {
        amountsWithoutBpt = new uint256[](inAmounts.length - 1);
        uint256 j;
        for (uint256 i; i < inAmounts.length; i++) {
            if (i == context.bptIndex) {
                continue;
            }
            amountsWithoutBpt[j++] = inAmounts[i];
        }
    }

    function _getOraclePairPrice(
        StrategyContext memory strategyContext,
        address token1,
        address token2
    ) internal view returns (uint256 oraclePairPrice) {
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

    function _approveBalancerTokens(ComposablePoolContext memory poolContext, address bptSpender) internal {
        for (uint256 i; i < poolContext.tokens.length; i++) {
            IERC20(poolContext.tokens[i]).checkApprove(address(Deployments.BALANCER_VAULT), type(uint256).max);
        }

        // Allow BPT spender to pull BALANCER_POOL_TOKEN
        poolContext.poolToken.checkApprove(bptSpender, type(uint256).max);
    }

    function _deposit(
        BalancerComposablePoolContext memory poolContext,
        ComposableOracleContext memory oracleContext,
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        uint256 deposit,
        ComposableDepositParams memory params
    ) internal returns (uint256 strategyTokensMinted) {

        uint256[] memory amounts = _handleDepositTrades(poolContext, strategyContext, deposit, params);

        uint256 bptMinted = _joinPoolAndStake({
            poolContext: poolContext,
            oracleContext: oracleContext,
            strategyContext: strategyContext,
            stakingContext: stakingContext,
            amounts: amounts,
            minBPT: params.minPoolClaim
        });

        strategyTokensMinted = strategyContext._mintStrategyTokens(bptMinted);
    }

    function _handleDepositTrades(
        BalancerComposablePoolContext memory poolContext,
        StrategyContext memory strategyContext,
        uint256 deposit,
        ComposableDepositParams memory params
    ) private returns (uint256[] memory amounts) {
        uint256 numTokens = poolContext.basePool.tokens.length;
        amounts = new uint256[](poolContext.basePool.tokens.length);

        if (params.depositTrades.length > 0) {
            uint256 tradeIndex;
            for (uint256 i; i < numTokens; i++) {
                if (i == poolContext.bptIndex || i == poolContext.basePool.primaryIndex) continue;

                uint256 sellAmount = params.depositTrades[tradeIndex].tradeAmount;

                if (sellAmount > 0) {
                    uint256 amountBought = _sellToken({
                        strategyContext: strategyContext, 
                        params: params.depositTrades[tradeIndex].tradeParams,
                        sellToken: poolContext.basePool.tokens[poolContext.basePool.primaryIndex],
                        buyToken: poolContext.basePool.tokens[i],
                        sellAmount: sellAmount
                    });

                    deposit -= sellAmount;
                    amounts[i] = amountBought;
                }

                tradeIndex++;
            }
        }

        amounts[poolContext.basePool.primaryIndex] = deposit;
    }

    function _sellToken(
        StrategyContext memory strategyContext,
        TradeParams memory params,
        address sellToken,
        address buyToken,
        uint256 sellAmount
    ) internal returns (uint256 buyAmount) {
        if (DexId(params.dexId) == DexId.ZERO_EX) {
            revert Errors.InvalidDexId(params.dexId);
        }

        ( /*uint256 amountSold */, buyAmount) = 
            strategyContext._executeTradeExactIn({
                params: params,
                sellToken: sellToken,
                buyToken: buyToken,
                amount: sellAmount,
                useDynamicSlippage: true
            });
    }

    function _convertTokensToPrimary(
        BalancerComposablePoolContext memory poolContext,
        StrategyContext memory strategyContext,
        ComposableRedeemParams memory params,
        uint256[] memory exitBalances
    ) internal returns (uint256 primaryPurchased) {
        address[] memory tokens = poolContext.basePool.tokens;
        uint256 primaryIndex = poolContext.basePool.primaryIndex;
        uint256 tradeIndex;
        for (uint256 i; i < tokens.length; i++) {
            if (i == poolContext.bptIndex) continue;

            if (i == primaryIndex) {
                primaryPurchased += exitBalances[i];
            } else {
                if (exitBalances[i] > 0) {
                    primaryPurchased += _sellToken({
                        strategyContext: strategyContext,
                        params: params.redemptionTrades[tradeIndex],
                        sellToken: tokens[i],
                        buyToken: tokens[primaryIndex],
                        sellAmount: exitBalances[i]
                    });
                }
                tradeIndex++;
            }
        }
    }

    function _redeem(
        BalancerComposablePoolContext memory poolContext,
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        uint256 vaultShares,
        ComposableRedeemParams memory params
    ) internal returns (uint256 finalPrimaryBalance) {
        uint256 bptClaim = strategyContext._redeemStrategyTokens(vaultShares);
        bool isSingleSidedExit = params.redemptionTrades.length == 0;

        // Underlying token balances from exiting the pool
        uint256[] memory exitBalances = _unstakeAndExitPool(
            poolContext, stakingContext, bptClaim, params.minAmounts, isSingleSidedExit
        );

        finalPrimaryBalance = _convertTokensToPrimary(
            poolContext, strategyContext, params, exitBalances
        );
    }

    function _joinPoolAndStake(
        BalancerComposablePoolContext memory poolContext,
        ComposableOracleContext memory oracleContext,
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        uint256[] memory amounts,
        uint256 minBPT
    ) internal returns (uint256 bptMinted) {
        // prettier-ignore
        PoolParams memory poolParams = _getPoolParams({
            context: poolContext,
            amounts: amounts,
            isJoin: true,
            isSingleSided: false,
            bptAmount: minBPT
        });

        bptMinted = BalancerUtils._joinPoolExactTokensIn({
            poolId: poolContext.poolId,
            poolToken: poolContext.basePool.poolToken,
            params: poolParams
        });

        // Check BPT threshold to make sure our share of the pool is
        // below maxPoolShare
        uint256 bptThreshold = strategyContext.vaultSettings._poolClaimThreshold(
            IComposablePool(address(poolContext.basePool.poolToken)).getActualSupply()
        );
        uint256 bptHeldAfterJoin = strategyContext.vaultState.totalPoolClaim + bptMinted;
        if (bptHeldAfterJoin > bptThreshold)
            revert Errors.PoolShareTooHigh(bptHeldAfterJoin, bptThreshold);

        // Transfer token to Aura protocol for boosted staking
        bool success = IAuraBoosterBase(stakingContext.booster).deposit(stakingContext.poolId, bptMinted, true); // stake = true
        if (!success) revert Errors.StakeFailed();
    }

    function _unstakeAndExitPool(
        BalancerComposablePoolContext memory poolContext,
        AuraStakingContext memory stakingContext,
        uint256 bptClaim,
        uint256[] memory minAmounts,
        bool isSingleSidedExit
    ) internal returns (uint256[] memory exitBalances) {
        // Withdraw BPT tokens back to the vault for redemption
        bool success = stakingContext.rewardPool.withdrawAndUnwrap(bptClaim, false); // claimRewards = false
        if (!success) revert Errors.UnstakeFailed();

        return _exitPool(poolContext, bptClaim, minAmounts, isSingleSidedExit);
    }

    function _exitPool(
        BalancerComposablePoolContext memory poolContext,
        uint256 bptClaim,
        uint256[] memory minAmounts,
        bool isSingleSidedExit
    ) private returns (uint256[] memory) {
        return BalancerUtils._exitPoolExactBPTIn({
            poolId: poolContext.poolId,
            poolToken: poolContext.basePool.poolToken,
            params: _getPoolParams({
                context: poolContext,
                amounts: minAmounts,
                isJoin: false,
                isSingleSided: isSingleSidedExit,
                bptAmount: bptClaim
            })
        });
    }

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
        uint256 bptClaim 
            = strategyContext._convertStrategyTokensToPoolClaim(vaultShareAmount);

        underlyingValue 
            = _getTimeWeightedPrimaryBalance(
                poolContext, oracleContext, strategyContext, bptClaim, false // validateOnly = false
            ).toInt();
    }

    /// @notice calculates the expected primary and secondary amounts based on
    /// the given spot price and oracle price
    function _getMinExitAmounts(
        BalancerComposablePoolContext memory poolContext,
        ComposableOracleContext memory oracleContext,
        StrategyContext memory strategyContext,
        uint256 poolClaim
    ) internal view returns (uint256[] memory minAmounts) {

        // min amounts are calculated based on the share of the Balancer pool with a small discount applied
        uint256 numTokens = poolContext.basePool.tokens.length;
        minAmounts = new uint256[](numTokens);

        for (uint256 i; i < numTokens; i++) {
            if (i == poolContext.bptIndex) continue;
            uint256 j = i + 1;
            if (j == poolContext.bptIndex) j++;
            if (j < numTokens) {
                _checkPriceLimit(poolContext, oracleContext, strategyContext, i, j);
            }

            minAmounts[i] = (poolContext.basePool.balances[i] * poolClaim * 
                strategyContext.vaultSettings.poolSlippageLimitPercent) / 
                (oracleContext.virtualSupply * uint256(VaultConstants.VAULT_PERCENT_BASIS));
        }
    }
}
