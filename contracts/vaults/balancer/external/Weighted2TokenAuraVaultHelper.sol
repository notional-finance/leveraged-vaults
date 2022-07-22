// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    Weighted2TokenAuraStrategyContext,
    DepositParams
} from "../BalancerVaultTypes.sol";

library Weighted2TokenAuraVaultHelper {
    function _depositFromNotional(
        Weighted2TokenAuraStrategyContext memory context,
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) external returns (uint256 strategyTokensMinted) {
    /*    DepositParams memory params = abi.decode(data, (DepositParams));

        // prettier-ignore
        (
            uint256 bptHeldInMaturity,
            uint256 totalStrategyTokenSupplyInMaturity
        ) = _getBPTHeldInMaturity(maturity);

        // First borrow any secondary tokens (if required)
        uint256 borrowedSecondaryAmount = _borrowSecondaryCurrency(
            account,
            maturity,
            deposit,
            params
        );

        // prettier-ignore
        (
            IAsset[] memory assets,
            uint256[] memory maxAmountsIn,
            uint256 msgValue,
        ) = TwoTokenPoolUtils._getPoolParams(
            context.poolContext, 
            primaryAmount, 
            borrowedSecondaryAmount, 
            true // isJoin
        );

        // Join the balancer pool and stake the tokens for boosting
        uint256 bptMinted = _joinPoolAndStake({
            stakingContext: context.stakingContext,
            poolContext: context.poolContext,
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            msgValue: msgValue,
            minBPT: params.minBPT
        });

        StrategyVaultState memory strategyVaultState = VaultUtils._getStrategyVaultState();

        // Calculate strategy token share for this account
        if (strategyVaultState.totalStrategyTokenGlobal == 0) {
            // Strategy tokens are in 8 decimal precision, BPT is in 18. Scale the minted amount down.
            strategyTokensMinted =
                (bptMinted * uint256(Constants.INTERNAL_TOKEN_PRECISION)) /
                BalancerUtils.BALANCER_PRECISION;
        } else {
            // BPT held in maturity is calculated before the new BPT tokens are minted, so this calculation
            // is the tokens minted that will give the account a corresponding share of the new bpt balance held.
            // The precision here will be the same as strategy token supply.
            strategyTokensMinted =
                (bptMinted * totalStrategyTokenSupplyInMaturity) /
                bptHeldInMaturity;
        }

        require(strategyTokensMinted <= type(uint80).max); /// @dev strategyTokensMinted overflow

        // Update global supply count
        strategyVaultState.totalStrategyTokenGlobal += uint80(strategyTokensMinted);
        VaultUtils._setStrategyVaultState(strategyVaultState);     */
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
