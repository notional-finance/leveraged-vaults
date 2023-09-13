// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {BaseStrategyVault} from "../BaseStrategyVault.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {ITradingModule} from "../../../interfaces/trading/ITradingModule.sol";
import {Errors} from "../../global/Errors.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {VaultEvents} from "./VaultEvents.sol";
import {StrategyVaultState} from "./VaultTypes.sol";
import {VaultStorage} from "./VaultStorage.sol";
import {VaultConstants} from "./VaultConstants.sol";

abstract contract VaultBase is BaseStrategyVault, UUPSUpgradeable {

    /** Immutables */
    uint32 internal immutable SETTLEMENT_PERIOD_IN_SECONDS;

    constructor(NotionalProxy notional_, ITradingModule tradingModule_, uint32 settlementPeriodInSeconds_) 
        BaseStrategyVault(notional_, tradingModule_)
    {
        SETTLEMENT_PERIOD_IN_SECONDS = settlementPeriodInSeconds_;
    }

    modifier whenNotLocked() {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
        if (_hasFlag(state.flags, VaultConstants.FLAG_LOCKED)) {
            revert Errors.VaultLocked();
        }
        _;
    }

    modifier whenLocked() {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
        if (!_hasFlag(state.flags, VaultConstants.FLAG_LOCKED)) {
            revert Errors.VaultNotLocked();
        }
        _;
    }

    function _revertInSettlementWindow(uint256 maturity) internal view {
        if (maturity - SETTLEMENT_PERIOD_IN_SECONDS <= block.timestamp) {
            revert();
        }
    }

    function _hasFlag(uint32 flags, uint32 flagID) private pure returns (bool) {
        return (flags & flagID) == flagID;
    }

    function _lockVault() internal {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
        state.flags = state.flags | VaultConstants.FLAG_LOCKED;
        VaultStorage.setStrategyVaultState(state);
        emit VaultEvents.VaultLocked();
    }

    function _unlockVault() internal {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
        state.flags = state.flags & ~VaultConstants.FLAG_LOCKED;
        VaultStorage.setStrategyVaultState(state);
        emit VaultEvents.VaultUnlocked();
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal override onlyNotionalOwner {}
    
    // Storage gap for future potential upgrades
    uint256[100] private __gap;
}