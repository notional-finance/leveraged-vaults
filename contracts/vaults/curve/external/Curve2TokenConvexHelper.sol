// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {
    Curve2TokenConvexStrategyContext,
    Curve2TokenPoolContext,
    DepositParams,
    TwoTokenRedeemParams,
    ReinvestRewardParams
} from "../CurveVaultTypes.sol";
import {
    StrategyContext,
    StrategyVaultSettings,
    StrategyVaultState,
    TwoTokenPoolContext
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
}
