// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.8.11;

import {IVeBalDelegator} from "../../interfaces/notional/IVeBalDelegator.sol";
import {IBoostController} from "../../interfaces/notional/IBoostController.sol";
import {IVaultController, VaultConfig} from "../../interfaces/notional/IVaultController.sol";

contract BalancerBoostController is IBoostController {
    IVeBalDelegator public immutable VEBAL_DELEGATOR;
    IVaultController public immutable VAULT_CONTROLLER;

    error StrategyVaultRequired(address sender);

    constructor(
        IVeBalDelegator vebalDelegator_,
        IVaultController vaultController_
    ) {
        VEBAL_DELEGATOR = vebalDelegator_;
        VAULT_CONTROLLER = vaultController_;
    }

    modifier onlyStrategyVault() {
        VaultConfig memory vaultConfig = VAULT_CONTROLLER.getVaultConfig(
            msg.sender
        );
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
