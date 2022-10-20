// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {BaseStrategyVault} from "../BaseStrategyVault.sol";
import {DeploymentParams} from "./BalancerVaultTypes.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";

abstract contract BalancerStrategyBase is BaseStrategyVault, UUPSUpgradeable, AccessControlUpgradeable {

    bytes32 public constant NORMAL_SETTLEMENT_ROLE = keccak256("NORMAL_SETTLEMENT_ROLE");
    bytes32 public constant EMERGENCY_SETTLEMENT_ROLE = keccak256("EMERGENCY_SETTLEMENT_ROLE");
    bytes32 public constant POST_MATURITY_SETTLEMENT_ROLE = keccak256("POST_MATURITY_SETTLEMENT_ROLE");
    bytes32 public constant REWARD_REINVESTMENT_ROLE = keccak256("REWARD_REINVESTMENT_ROLE");

    /** Immutables */
    uint32 internal immutable SETTLEMENT_PERIOD_IN_SECONDS;

    constructor(NotionalProxy notional_, DeploymentParams memory params) 
        BaseStrategyVault(notional_, params.tradingModule)
    {
        SETTLEMENT_PERIOD_IN_SECONDS = params.settlementPeriodInSeconds;
    }

    /// @notice Can only be called once during initialization
    function __INIT_BALANCER_VAULT(
        string memory name_,
        uint16 borrowCurrencyId_
    ) internal onlyInitializing {
        __INIT_VAULT(name_, borrowCurrencyId_);
        _setupRole(DEFAULT_ADMIN_ROLE, NOTIONAL.owner());
    }

    function _revertInSettlementWindow(uint256 maturity) internal view {
        if (maturity - SETTLEMENT_PERIOD_IN_SECONDS <= block.timestamp) {
            revert();
        }
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal override onlyNotionalOwner {}
    
    // Storage gap for future potential upgrades
    uint256[100] private __gap;
}