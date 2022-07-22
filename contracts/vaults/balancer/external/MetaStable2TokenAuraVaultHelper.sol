// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    MetaStable2TokenAuraStrategyContext,
    DepositParams,
    StrategyContext,
    StableOracleContext
} from "../BalancerVaultTypes.sol";
import {Constants} from "../../../global/Constants.sol";
import {VaultUtils} from "../internal/VaultUtils.sol";
import {IAsset} from "../../../../interfaces/balancer/IBalancerVault.sol";
import {TwoTokenAuraStrategyUtils} from "../internal/TwoTokenAuraStrategyUtils.sol";
import {Stable2TokenOracleMath} from "../internal/Stable2TokenOracleMath.sol";
import {SecondaryBorrowUtils} from "../internal/SecondaryBorrowUtils.sol";

library MetaStable2TokenAuraVaultHelper {
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using Stable2TokenOracleMath for StableOracleContext;

    function _depositFromNotional(
        MetaStable2TokenAuraStrategyContext memory context,
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) external returns (uint256 strategyTokensMinted) {
        DepositParams memory params = abi.decode(data, (DepositParams));
        StrategyContext memory strategyContext = context.baseContext;

        // First borrow any secondary tokens (if required)
        uint256 borrowedSecondaryAmount = _borrowSecondaryCurrency(
            context, account, maturity, deposit, params
        );

        uint256 bptMinted = strategyContext._joinPoolAndStake({
            stakingContext: context.stakingContext,
            poolContext: context.poolContext,
            primaryAmount: deposit,
            secondaryAmount: borrowedSecondaryAmount,
            minBPT: params.minBPT
        });

        strategyTokensMinted = strategyContext._convertBPTClaimToStrategyTokens(bptMinted, maturity);
        require(strategyTokensMinted <= type(uint80).max); /// @dev strategyTokensMinted overflow

        // Update global supply count
        context.baseContext.vaultState.totalStrategyTokenGlobal += uint80(strategyTokensMinted);
        VaultUtils._setStrategyVaultState(context.baseContext.vaultState); 
    }

    function _borrowSecondaryCurrency(
        MetaStable2TokenAuraStrategyContext memory context,
        address account,
        uint256 maturity,
        uint256 primaryAmount,
        DepositParams memory params
    ) private returns (uint256) {
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
        MetaStable2TokenAuraStrategyContext memory context,
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) external returns (uint256 finalPrimaryBalance) {
    
    }
}
