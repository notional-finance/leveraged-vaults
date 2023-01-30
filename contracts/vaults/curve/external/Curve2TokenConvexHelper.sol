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
import {StrategyUtils} from "../../common/internal/strategy/StrategyUtils.sol";
import {VaultStorage} from "../../common/VaultStorage.sol";
import {Curve2TokenPoolUtils} from "../internal/pool/Curve2TokenPoolUtils.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";

library Curve2TokenConvexHelper {
    using Curve2TokenPoolUtils for Curve2TokenPoolContext;

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

    }

    function settleVaultEmergency(
        Curve2TokenConvexStrategyContext calldata context, 
        uint256 maturity, 
        bytes calldata data
    ) external {
    
    }

    function reinvestReward(
        Curve2TokenConvexStrategyContext calldata context,
        ReinvestRewardParams calldata params
    ) external {

    }
}
