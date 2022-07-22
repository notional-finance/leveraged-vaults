// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {LibBalancerStorage} from "./LibBalancerStorage.sol";
import {
    StrategyVaultSettings, 
    StrategyVaultState, 
    SettlementState,
    StrategyContext
} from "../BalancerVaultTypes.sol";
import {BalancerUtils} from "../BalancerUtils.sol";
import {Constants} from "../../../global/Constants.sol";
import {VaultState} from "../../../global/Types.sol";

library VaultUtils {
    function _getStrategyVaultSettings() internal view returns (StrategyVaultSettings memory) {
        mapping(uint256 => StrategyVaultSettings) storage store = LibBalancerStorage.getStrategyVaultSettings();
        return store[0];
    }

    function _validateStrategyVaultSettings(
        StrategyVaultSettings memory settings, 
        uint32 maxOracleQueryWindow
    ) internal pure {
        require(settings.oracleWindowInSeconds <= maxOracleQueryWindow);
        require(settings.settlementCoolDownInMinutes <= Constants.MAX_SETTLEMENT_COOLDOWN_IN_MINUTES);
        require(settings.postMaturitySettlementCoolDownInMinutes <= Constants.MAX_SETTLEMENT_COOLDOWN_IN_MINUTES);
        require(settings.balancerOracleWeight <= Constants.VAULT_PERCENT_BASIS);
        require(settings.maxBalancerPoolShare <= Constants.VAULT_PERCENT_BASIS);
        require(settings.settlementSlippageLimitPercent <= Constants.VAULT_PERCENT_BASIS);
        require(settings.postMaturitySettlementSlippageLimitPercent <= Constants.VAULT_PERCENT_BASIS);
        require(settings.feePercentage <= Constants.VAULT_PERCENT_BASIS);
    }

    function _setStrategyVaultSettings(StrategyVaultSettings memory settings) internal {
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

    function _getSettlementState(uint256 maturity) internal view returns (SettlementState memory) {
        mapping(uint256 => SettlementState) storage store = LibBalancerStorage.getSettlementState();
        return store[maturity];
    }

    function _setSettlementState(uint256 maturity, SettlementState memory state) internal {
        mapping(uint256 => SettlementState) storage store = LibBalancerStorage.getSettlementState();
        store[maturity] = state;
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
        return (totalBPTSupply * strategyVaultSettings.maxBalancerPoolShare) / Constants.VAULT_PERCENT_BASIS;
    }

    function _totalSupplyInMaturity(uint256 maturity) internal view returns (uint256) {
        VaultState memory vaultState = Constants.NOTIONAL.getVaultState(address(this), maturity);
        return vaultState.totalStrategyTokens;
    }

    function _calculateStrategyTokensMinted(
        StrategyContext memory context, 
        uint256 maturity,
        uint256 bptMinted
    ) internal view returns (uint256 strategyTokensMinted) {
        uint256 totalSupplyInMaturity = _totalSupplyInMaturity(maturity);
        uint256 bptHeldInMaturity = _getBPTHeldInMaturity(
            context.vaultState,
            totalSupplyInMaturity,
            context.totalBPTHeld
        );

        // Calculate strategy token share for this account
        if (context.vaultState.totalStrategyTokenGlobal == 0) {
            // Strategy tokens are in 8 decimal precision, BPT is in 18. Scale the minted amount down.
            strategyTokensMinted =
                (bptMinted * uint256(Constants.INTERNAL_TOKEN_PRECISION)) /
                BalancerUtils.BALANCER_PRECISION;
        } else {
            // BPT held in maturity is calculated before the new BPT tokens are minted, so this calculation
            // is the tokens minted that will give the account a corresponding share of the new bpt balance held.
            // The precision here will be the same as strategy token supply.
            strategyTokensMinted = (bptMinted * totalSupplyInMaturity) / bptHeldInMaturity;
        }
    }
}
