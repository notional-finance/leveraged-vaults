// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    Weighted2TokenAuraStrategyContext,
    DepositParams,
    StrategyContext
} from "../BalancerVaultTypes.sol";
import {TwoTokenAuraStrategyUtils} from "../internal/TwoTokenAuraStrategyUtils.sol";
import {Weighted2TokenOracleMath} from "../internal/Weighted2TokenOracleMath.sol";
import {SecondaryBorrowUtils} from "../internal/SecondaryBorrowUtils.sol";
import {VaultUtils} from "../internal/VaultUtils.sol";

library Weighted2TokenAuraVaultHelper {
    using TwoTokenAuraStrategyUtils for StrategyContext;

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

        uint256 bptMinted = context.baseContext._joinPoolAndStake({
            stakingContext: context.stakingContext,
            poolContext: context.poolContext,
            primaryAmount: deposit,
            secondaryAmount: borrowedSecondaryAmount,
            minBPT: params.minBPT
        });

        strategyTokensMinted = VaultUtils._calculateStrategyTokensMinted(
            context.baseContext, maturity, bptMinted
        );

        require(strategyTokensMinted <= type(uint80).max); /// @dev strategyTokensMinted overflow

        // Update global supply count
        context.baseContext.vaultState.totalStrategyTokenGlobal += uint80(strategyTokensMinted);
        VaultUtils._setStrategyVaultState(context.baseContext.vaultState); 
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

        uint256 optimalSecondaryAmount = Weighted2TokenOracleMath.getOptimalSecondaryBorrowAmount(
            context.oracleContext, context.poolContext, primaryAmount
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
    
    }
}
