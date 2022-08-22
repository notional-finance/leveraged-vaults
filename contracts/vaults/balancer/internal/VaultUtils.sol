// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {LibBalancerStorage} from "./LibBalancerStorage.sol";
import {StrategyVaultSettings, StrategyVaultState} from "../BalancerVaultTypes.sol";
import {NotionalUtils} from "../../../utils/NotionalUtils.sol";
import {BalancerConstants} from "./BalancerConstants.sol";

library VaultUtils {

    function _getStrategyVaultSettings() internal view returns (StrategyVaultSettings memory) {
        mapping(uint256 => StrategyVaultSettings) storage store = LibBalancerStorage.getStrategyVaultSettings();
        return store[0];
    }

    function _setStrategyVaultSettings(
        StrategyVaultSettings memory settings, 
        uint32 maxOracleQueryWindow,
        uint16 balancerOracleWeight
    ) internal {
        require(settings.oracleWindowInSeconds <= maxOracleQueryWindow);
        require(settings.settlementCoolDownInMinutes <= BalancerConstants.MAX_SETTLEMENT_COOLDOWN_IN_MINUTES);
        require(settings.postMaturitySettlementCoolDownInMinutes <= BalancerConstants.MAX_SETTLEMENT_COOLDOWN_IN_MINUTES);
        require(settings.balancerOracleWeight <= balancerOracleWeight);
        require(settings.maxBalancerPoolShare <= BalancerConstants.VAULT_PERCENT_BASIS);
        require(settings.settlementSlippageLimitPercent <= BalancerConstants.SLIPPAGE_LIMIT_PRECISION);
        require(settings.postMaturitySettlementSlippageLimitPercent <= BalancerConstants.SLIPPAGE_LIMIT_PRECISION);
        require(settings.feePercentage <= BalancerConstants.VAULT_PERCENT_BASIS);

        mapping(uint256 => StrategyVaultSettings) storage store = LibBalancerStorage.getStrategyVaultSettings();
        store[0] = settings;
    }

    function _getStrategyVaultState() internal view returns (StrategyVaultState memory) {
        mapping(uint256 => StrategyVaultState) storage store = LibBalancerStorage.getStrategyVaultState();
        return store[0];
    }

    function _setStrategyVaultState(StrategyVaultState memory state) internal {
        mapping(uint256 => StrategyVaultState) storage store = LibBalancerStorage.getStrategyVaultState();
        store[0] = state;
    }

    function _getBPTHeldInMaturity(
        StrategyVaultState memory strategyVaultState, 
        uint256 totalSupplyInMaturity,
        uint256 totalBPTHeld
    ) internal pure returns (uint256 bptHeldInMaturity) {
        if (strategyVaultState.totalStrategyTokenGlobal == 0) return 0;
        bptHeldInMaturity =
            (totalBPTHeld * totalSupplyInMaturity) /
            strategyVaultState.totalStrategyTokenGlobal;
    }

    function _bptThreshold(StrategyVaultSettings memory strategyVaultSettings, uint256 totalBPTSupply) 
        internal pure returns (uint256) {
        return (totalBPTSupply * strategyVaultSettings.maxBalancerPoolShare) / BalancerConstants.VAULT_PERCENT_BASIS;
    }
}
