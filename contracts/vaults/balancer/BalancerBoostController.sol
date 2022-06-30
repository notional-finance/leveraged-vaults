// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {IVeBalDelegator} from "../../../interfaces/notional/IVeBalDelegator.sol";
import {IBoostController} from "../../../interfaces/notional/IBoostController.sol";
import {IVaultController, VaultConfig} from "../../../interfaces/notional/IVaultController.sol";

contract BalancerBoostController is IBoostController {
    IVeBalDelegator public immutable VEBAL_DELEGATOR;
    IVaultController public immutable VAULT_CONTROLLER;

    error StrategyVaultRequired(address sender);

    constructor(IVeBalDelegator vebalDelegator_, IVaultController vaultController_) {
        // @audit is this the same veBAL delegator as here? or is it something different?
        // I don't see the methods listed here in that PR
        // https://github.com/notional-finance/staked-note/pull/21/files#diff-0ac5df9ed70c320524413853cca5d63fd6a06fe31ea3244cb0cc3a62c864fe7b
        VEBAL_DELEGATOR = vebalDelegator_;
        VAULT_CONTROLLER = vaultController_;
    }

    // @audit would it be safer to just manually whitelist each token / vault pair into
    // the delegator rather than allow any strategy vault to do this?
    modifier onlyStrategyVault() {
        VaultConfig memory vaultConfig = VAULT_CONTROLLER.getVaultConfig(
            msg.sender
        );
        // @audit this won't work because vaultConfig.vault will just return msg.sender,
        // you would have to check that vaultConfig.flags != 0 (meaning it is enabled)
        if (vaultConfig.vault != msg.sender)
            revert StrategyVaultRequired(msg.sender);
        _;
    }

    function depositToken(address token, uint256 amount)
        external
        override
        onlyStrategyVault
    {
        VEBAL_DELEGATOR.depositToken(token, msg.sender, amount);
    }

    function withdrawToken(address token, uint256 amount)
        external
        override
        onlyStrategyVault
    {
        VEBAL_DELEGATOR.withdrawToken(token, msg.sender, amount);
    }

    function claimBAL(address liquidityGauge)
        external
        onlyStrategyVault
        returns (uint256 claimAmount)
    {
        return VEBAL_DELEGATOR.claimBAL(liquidityGauge, msg.sender);
    }

    function claimGaugeTokens(address liquidityGauge)
        external
        onlyStrategyVault
        returns (address[] memory tokens, uint256[] memory balancesTransferred)
    {
        return VEBAL_DELEGATOR.claimGaugeTokens(liquidityGauge, msg.sender);
    }
}
