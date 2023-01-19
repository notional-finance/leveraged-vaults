// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {StrategyVaultSettings} from "./VaultTypes.sol";

library VaultEvents {
    event StrategyVaultSettingsUpdated(StrategyVaultSettings settings);
}
