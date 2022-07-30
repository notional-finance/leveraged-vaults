// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    Boosted3TokenAuraStrategyContext,
    DepositParams,
    RedeemParams,
    PoolParams,
    StrategyContext,
    ThreeTokenPoolContext,
    TwoTokenPoolContext,
    PoolContext
} from "../BalancerVaultTypes.sol";
import {Constants} from "../../../global/Constants.sol";
import {TokenUtils, IERC20} from "../../../utils/TokenUtils.sol";
import {Boosted3TokenAuraStrategyUtils} from "../internal/Boosted3TokenAuraStrategyUtils.sol";
import {BalancerUtils} from "../internal/BalancerUtils.sol";
import {Boosted3TokenPoolUtils} from "../internal/Boosted3TokenPoolUtils.sol";
import {IBoostedPool} from "../../../../interfaces/balancer/IBalancerPool.sol";
import {IBalancerVault, IAsset} from "../../../../interfaces/balancer/IBalancerVault.sol";

library Boosted3TokenAuraVaultHelper {
    using Boosted3TokenAuraStrategyUtils for StrategyContext;
    using Boosted3TokenPoolUtils for ThreeTokenPoolContext;
    using TokenUtils for IERC20;

    function depositFromNotional(
        Boosted3TokenAuraStrategyContext memory context,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) external returns (uint256 strategyTokensMinted) {
        DepositParams memory params = abi.decode(data, (DepositParams));

        strategyTokensMinted = context.baseStrategy._deposit({
            stakingContext: context.stakingContext, 
            poolContext: context.poolContext,
            deposit: deposit,
            maturity: maturity,
            minBPT: params.minBPT
        });
    }

    function redeemFromNotional(
        Boosted3TokenAuraStrategyContext memory context,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) external returns (uint256 finalPrimaryBalance) {
        RedeemParams memory params = abi.decode(data, (RedeemParams));
        finalPrimaryBalance = context.baseStrategy._redeem({
            stakingContext: context.stakingContext,
            poolContext: context.poolContext,
            strategyTokens: strategyTokens,
            maturity: maturity,
            minPrimary: params.minPrimary
        });
    }
}
