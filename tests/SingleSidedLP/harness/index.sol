// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {
    SingleSidedLPMetadata,
    ComposablePoolHarness,
    StrategyVaultSettings,
    VaultConfigParams,
    IERC20
} from "./ComposablePoolHarness.sol";
import { DeployProxyVault} from "../../../scripts/deploy/DeployProxyVault.sol";
import { BaseSingleSidedLPVault } from "../BaseSingleSidedLPVault.sol";
import { VaultRewarderTests } from "../VaultRewarderTests.sol";
import { Curve2TokenHarness, CurveInterface } from "./Curve2TokenHarness.sol";
import { Curve2TokenConvexHarness } from "./Curve2TokenConvexHarness.sol";
import { WeightedPoolHarness } from "./WeightedPoolHarness.sol";
import { WrappedComposablePoolHarness } from "./WrappedComposablePoolHarness.sol";
import { ITradingModule } from "@interfaces/trading/ITradingModule.sol";
import { StrategyVaultHarness } from "../../../tests/StrategyVaultHarness.sol";