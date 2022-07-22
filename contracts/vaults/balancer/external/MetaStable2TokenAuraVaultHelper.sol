// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    MetaStable2TokenAuraStrategyContext,
    DepositParams,
    PoolParams,
    TwoTokenPoolContext
} from "../BalancerVaultTypes.sol";
import {Constants} from "../../../global/Constants.sol";
import {VaultUtils} from "../internal/VaultUtils.sol";
import {BalancerUtils} from "../BalancerUtils.sol";
import {IAsset} from "../../../../interfaces/balancer/IBalancerVault.sol";
import {TwoTokenPoolUtils} from "../internal/TwoTokenPoolUtils.sol";
import {AuraStakingUtils} from "../internal/AuraStakingUtils.sol";

library MetaStable2TokenAuraVaultHelper {
    using TwoTokenPoolUtils for TwoTokenPoolContext;

    function _depositFromNotional(
        MetaStable2TokenAuraStrategyContext memory context,
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) external returns (uint256 strategyTokensMinted) {
        DepositParams memory params = abi.decode(data, (DepositParams));

        // First borrow any secondary tokens (if required)
        /*uint256 borrowedSecondaryAmount = _borrowSecondaryCurrency(
            account,
            maturity,
            deposit,
            params
        );*/

        uint256 bptMinted = _joinPoolAndStake(context, deposit, 0 /*borrowedSecondaryAmount*/, params.minBPT);

        uint256 totalSupplyInMaturity = VaultUtils._totalSupplyInMaturity(maturity);
        uint256 bptHeldInMaturity = VaultUtils._getBPTHeldInMaturity(
            context.baseContext.vaultState,
            totalSupplyInMaturity,
            context.baseContext.totalBPTHeld
        );

        // Calculate strategy token share for this account
        if (context.baseContext.vaultState.totalStrategyTokenGlobal == 0) {
            // Strategy tokens are in 8 decimal precision, BPT is in 18. Scale the minted amount down.
            strategyTokensMinted =
                (bptMinted * uint256(Constants.INTERNAL_TOKEN_PRECISION)) /
                BalancerUtils.BALANCER_PRECISION;
        } else {
            // BPT held in maturity is calculated before the new BPT tokens are minted, so this calculation
            // is the tokens minted that will give the account a corresponding share of the new bpt balance held.
            // The precision here will be the same as strategy token supply.
            strategyTokensMinted = (bptMinted * totalSupplyInMaturity) / bptHeldInMaturity;
        }

        require(strategyTokensMinted <= type(uint80).max); /// @dev strategyTokensMinted overflow

        // Update global supply count
        context.baseContext.vaultState.totalStrategyTokenGlobal += uint80(strategyTokensMinted);
        VaultUtils._setStrategyVaultState(context.baseContext.vaultState);    
    }

    function _joinPoolAndStake(
        MetaStable2TokenAuraStrategyContext memory context, 
        uint256 primaryAmount,
        uint256 secondaryAmount,
        uint256 minBPT
    ) private returns (uint256 bptMinted) {
        // prettier-ignore
        PoolParams memory poolParams = context.poolContext._getPoolParams( 
            primaryAmount, 
            secondaryAmount,
            true // isJoin
        );

        // Join the balancer pool and stake the tokens for boosting
        bptMinted = AuraStakingUtils._joinPoolAndStake({
            stakingContext: context.stakingContext,
            poolContext: context.poolContext.baseContext,
            poolParams: poolParams,
            totalBPTHeld: context.baseContext.totalBPTHeld,
            bptThreshold: VaultUtils._bptThreshold(
                context.baseContext.vaultSettings, 
                context.poolContext.baseContext.pool.totalSupply()
            ),
            minBPT: minBPT
        });
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
