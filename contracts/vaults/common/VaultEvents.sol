// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {StrategyVaultSettings} from "./VaultTypes.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";

library VaultEvents {
    event RewardReinvested(address token, uint256 amountSold, uint256 poolClaimAmount);
    event StrategyVaultSettingsUpdated(StrategyVaultSettings settings);
    event VaultSettlement(
        uint256 maturity,
        uint256 poolClaimToSettle,
        uint256 strategyTokensRedeemed
    );
    event EmergencyVaultSettlement(uint256 poolClaimToSettle);
    event VaultLocked();
    event VaultUnlocked();
}
