// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;

import {StrategyVaultSettings} from "./CurveVaultTypes.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";

library CurveEvents {
    event StrategyVaultSettingsUpdated(StrategyVaultSettings settings);
}