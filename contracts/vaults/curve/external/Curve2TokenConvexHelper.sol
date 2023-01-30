// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {
    Curve2TokenConvexStrategyContext,
    Curve2TokenPoolContext
} from "../CurveVaultTypes.sol";
import {
    StrategyContext,
    StrategyVaultSettings,
    StrategyVaultState,
    TwoTokenPoolContext,
    DepositParams,
    RedeemParams,
    ReinvestRewardParams
} from "../../common/VaultTypes.sol";
import {TwoTokenPoolUtils} from "../../common/internal/pool/TwoTokenPoolUtils.sol";
import {SettlementUtils} from "../../common/internal/settlement/SettlementUtils.sol";
import {StrategyUtils} from "../../common/internal/strategy/StrategyUtils.sol";
import {VaultStorage} from "../../common/VaultStorage.sol";
import {VaultEvents} from "../../common/VaultEvents.sol";
import {Curve2TokenPoolUtils} from "../internal/pool/Curve2TokenPoolUtils.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";

library Curve2TokenConvexHelper {
    using Curve2TokenPoolUtils for Curve2TokenPoolContext;
    using StrategyUtils for StrategyContext;
    using SettlementUtils for StrategyContext;

    function deposit(
        Curve2TokenConvexStrategyContext memory context,
        uint256 deposit,
        bytes calldata data
    ) external returns (uint256 strategyTokensMinted) {
        DepositParams memory params = abi.decode(data, (DepositParams));

        strategyTokensMinted = context.poolContext._deposit({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            deposit: deposit,
            params: params
        });
    }

    function redeem(
        Curve2TokenConvexStrategyContext memory context,
        uint256 strategyTokens,
        bytes calldata data
    ) external returns (uint256 finalPrimaryBalance) {
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        finalPrimaryBalance = context.poolContext._redeem({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            strategyTokens: strategyTokens,
            params: params
        });
    }

    function settleVault(
        Curve2TokenConvexStrategyContext calldata context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        RedeemParams memory params
    ) external {
        uint256 bptToSettle = context.baseStrategy._convertStrategyTokensToPoolClaim(strategyTokensToRedeem);
        
        _executeSettlement({
            strategyContext: context.baseStrategy,
            poolContext: context.poolContext,
            maturity: maturity,
            bptToSettle: bptToSettle,
            redeemStrategyTokenAmount: strategyTokensToRedeem,
            params: params
        });

        emit VaultEvents.VaultSettlement(maturity, bptToSettle, strategyTokensToRedeem);
    }

    function settleVaultEmergency(
        Curve2TokenConvexStrategyContext calldata context, 
        uint256 maturity, 
        bytes calldata data
    ) external {
        RedeemParams memory params = SettlementUtils._decodeParamsAndValidate(
            context.baseStrategy.vaultSettings.emergencySettlementSlippageLimitPercent,
            data
        );

        uint256 bptToSettle = context.baseStrategy._getEmergencySettlementParams({
            maturity: maturity, 
            totalPoolSupply: context.poolContext.basePool.poolToken.totalSupply()
        });

        uint256 redeemStrategyTokenAmount = 
            context.baseStrategy._convertPoolClaimToStrategyTokens(bptToSettle);

        _executeSettlement({
            strategyContext: context.baseStrategy,
            poolContext: context.poolContext,
            maturity: maturity,
            bptToSettle: bptToSettle,
            redeemStrategyTokenAmount: redeemStrategyTokenAmount,
            params: params
        });

        emit VaultEvents.EmergencyVaultSettlement(maturity, bptToSettle, redeemStrategyTokenAmount);    
    }

    function _executeSettlement(
        StrategyContext calldata strategyContext,
        Curve2TokenPoolContext calldata poolContext,
        uint256 maturity,
        uint256 bptToSettle,
        uint256 redeemStrategyTokenAmount,
        RedeemParams memory params
    ) private {
    
    }

    function reinvestReward(
        Curve2TokenConvexStrategyContext calldata context,
        ReinvestRewardParams calldata params
    ) external {

    }
}
