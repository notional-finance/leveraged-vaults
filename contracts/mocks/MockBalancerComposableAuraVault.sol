// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {
    AuraVaultDeploymentParams, 
    BalancerComposableAuraStrategyContext
} from "../vaults/balancer/BalancerVaultTypes.sol";
import {BalancerComposablePoolMixin} from "../vaults/balancer/mixins/BalancerComposablePoolMixin.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {BalancerComposablePoolUtils} from "../vaults/balancer/internal/pool/BalancerComposablePoolUtils.sol";

contract MockBalancerComposableAuraVault is BalancerComposablePoolMixin {

    constructor(
        NotionalProxy notional_, 
        AuraVaultDeploymentParams memory params
    ) BalancerComposablePoolMixin(notional_, params) { }

    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("BalancerComposableAuraVault"));
    }

    function _depositFromNotional(
        address /* account */,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 vaultSharesMinted) {}

    function _redeemFromNotional(
        address account,
        uint256 vaultShares,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 finalPrimaryBalance) {}

    function convertStrategyToUnderlying(
        address /* account */,
        uint256 vaultShares,
        uint256 /* maturity */
    ) public view override returns (int256 underlyingValue) {
        BalancerComposableAuraStrategyContext memory context = _strategyContext();
        underlyingValue = BalancerComposablePoolUtils._convertStrategyToUnderlying({
            poolContext: context.poolContext,
            strategyContext: context.baseStrategy,
            oracleContext: context.oracleContext,
            vaultShareAmount: vaultShares
        });
    }

    function joinPoolAndStake(uint256[] calldata amounts, uint256 minBPT) 
        external returns (uint256) {
        BalancerComposableAuraStrategyContext memory context = _strategyContext();
        return BalancerComposablePoolUtils._joinPoolAndStake(
            context.poolContext, context.oracleContext, context.baseStrategy, context.stakingContext, amounts, minBPT
        );
    }

    function getTimeWeightedPrimaryBalance(uint256 bptAmount) external view returns (uint256) {
        BalancerComposableAuraStrategyContext memory context = _strategyContext();
        return BalancerComposablePoolUtils._getTimeWeightedPrimaryBalance(
            context.poolContext, context.oracleContext, context.baseStrategy, bptAmount, false
        );
    }

    function emergencyExit(uint256 /* claimToExit */, bytes calldata /* data */) override external {}
    function restoreVault(uint256 /* minPoolClaim */, bytes calldata /* data */) override external {}
}