// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {
    UnderlyingPoolContext,
    AuraVaultDeploymentParams,
    BalancerComposablePoolContext,
    BalancerComposableAuraStrategyContext,
    AuraStakingContext
} from "../BalancerVaultTypes.sol";

library ComposableAuraHelper {

    function deposit(
        BalancerComposableAuraStrategyContext memory context,
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
}
