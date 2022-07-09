// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {IVeBalDelegator} from "../../../interfaces/notional/IVeBalDelegator.sol";
import {IBoostController} from "../../../interfaces/notional/IBoostController.sol";
import {ILiquidityGauge} from "../../../interfaces/balancer/ILiquidityGauge.sol";
import {IVaultController, VaultConfig} from "../../../interfaces/notional/IVaultController.sol";

contract BalancerBoostController is IBoostController {
    IVeBalDelegator public immutable VEBAL_DELEGATOR;
    NotionalProxy public immutable NOTIONAL;

    /// @notice Emitted when a vault is whitelisted for a particular balancer liquidity token
    event VaultWhitelistedForToken(address indexed token, address indexed vault);

    /// @notice a mapping from balancer liquidity token to the vault that is allowed
    /// to deposit and withdraw that token. Only one vault is allowed to deposit and
    /// withdraw a balancer liquidity token at any time.
    mapping(address => address) public tokenWhitelist;

    constructor(
        NotionalProxy notional_,
        IVeBalDelegator vebalDelegator_
    ) {
        VEBAL_DELEGATOR = vebalDelegator_;
        NOTIONAL = notional_;
    }

    modifier onlyNotionalOwner() {
        require(msg.sender == address(NOTIONAL.owner()));
        _;
    }

    modifier onlyWhitelisted(address token) {
        require(tokenWhitelist[token] == msg.sender, "Unauthorized");
        _;
    }

    /// @notice Allows the Notional owner to authorize vaults to deposit and withdraw listed
    /// tokens from the veBAL delegator contract
    function setWhitelistForToken(address token, address vault) external onlyNotionalOwner {
        tokenWhitelist[token] = vault;
        emit VaultWhitelistedForToken(token, vault);
    }

    function depositToken(address token, uint256 amount) external override onlyWhitelisted(token) {
        VEBAL_DELEGATOR.depositToken(token, msg.sender, amount);
    }

    function withdrawToken(address token, uint256 amount) external override onlyWhitelisted(token) {
        VEBAL_DELEGATOR.withdrawToken(token, msg.sender, amount);
    }

    function claimBAL(ILiquidityGauge liquidityGauge) external returns (uint256 claimAmount) {
        require(tokenWhitelist[liquidityGauge.lp_token()] == msg.sender, "Unauthorized");
        return VEBAL_DELEGATOR.claimBAL(address(liquidityGauge), msg.sender);
    }

    function claimGaugeTokens(ILiquidityGauge liquidityGauge) external returns (
        address[] memory tokens,
        uint256[] memory balancesTransferred
    ) {
        require(tokenWhitelist[liquidityGauge.lp_token()] == msg.sender, "Unauthorized");
        return VEBAL_DELEGATOR.claimGaugeTokens(address(liquidityGauge), msg.sender);
    }
}
