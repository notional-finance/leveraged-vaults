// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    Weighted2TokenAuraStrategyContext,
    DepositParams,
    RedeemParams,
    StrategyContext,
    WeightedOracleContext,
    SecondaryTradeParams
} from "../BalancerVaultTypes.sol";
import {TwoTokenAuraStrategyUtils} from "../internal/TwoTokenAuraStrategyUtils.sol";
import {Weighted2TokenOracleMath} from "../internal/Weighted2TokenOracleMath.sol";
import {SecondaryBorrowUtils} from "../internal/SecondaryBorrowUtils.sol";

library Weighted2TokenAuraVaultHelper {
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using Weighted2TokenOracleMath for WeightedOracleContext;

    function _depositFromNotional(
        Weighted2TokenAuraStrategyContext memory context,
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) external returns (uint256 strategyTokensMinted) {
        DepositParams memory params = abi.decode(data, (DepositParams));

        // First borrow any secondary tokens (if required)
        uint256 borrowedSecondaryAmount = _borrowSecondaryCurrency(
            context, account, maturity, deposit, params
        );

        strategyTokensMinted = context.baseContext._deposit({
            stakingContext: context.stakingContext, 
            poolContext: context.poolContext,
            deposit: deposit,
            maturity: maturity,
            borrowedSecondaryAmount: borrowedSecondaryAmount,
            params: params
        });
    }

    function _borrowSecondaryCurrency(
        Weighted2TokenAuraStrategyContext memory context,
        address account,
        uint256 maturity,
        uint256 primaryAmount,
        DepositParams memory params
    ) private returns (uint256 borrowedSecondaryAmount) {
        // If secondary currency is not specified then return
        if (context.baseContext.secondaryBorrowCurrencyId == 0) return 0;

        uint256 optimalSecondaryAmount = context.oracleContext._getOptimalSecondaryBorrowAmount(
            context.poolContext, primaryAmount
        );

        return SecondaryBorrowUtils._borrowSecondaryCurrency(
            account, maturity, optimalSecondaryAmount, params
        );
    }

    function _redeemFromNotional(
        Weighted2TokenAuraStrategyContext memory context,
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) external returns (uint256 finalPrimaryBalance) {      
        RedeemParams memory params = abi.decode(data, (RedeemParams));
        finalPrimaryBalance = context.baseContext._redeem({
            oracleContext: context.oracleContext.baseContext,
            stakingContext: context.stakingContext,
            poolContext: context.poolContext,
            account: account,
            strategyTokens: strategyTokens,
            maturity: maturity,
            params: params
        });
    }
}
