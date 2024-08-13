// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {IERC20, TokenUtils} from "@contracts/utils/TokenUtils.sol";

/**
 * @notice Used for withdraws where only one cooldown period can exist per address,
 * this contract will receive the staked token and initiate a cooldown
 */
abstract contract ClonedCoolDownHolder {
    using TokenUtils for IERC20;

    address immutable vault;

    constructor(address _vault) { vault = _vault; }

    modifier onlyVault() {
        require(msg.sender == vault);
        _;
    }

    /// @notice If anything ever goes wrong, allows the vault to recover lost tokens.
    function rescueTokens(IERC20 token, address receiver, uint256 amount) external onlyVault {
       token.checkTransfer(receiver, amount);
    }

    function startCooldown(uint256 cooldownBalance) external onlyVault { _startCooldown(cooldownBalance); }
    function stopCooldown() external onlyVault { _stopCooldown(); }
    function finalizeCooldown() external onlyVault returns (
        uint256 tokensClaimed, bool finalized
    ) { return _finalizeCooldown(); }

    function _startCooldown(uint256 cooldownBalance) internal virtual;
    function _stopCooldown() internal virtual;
    function _finalizeCooldown() internal virtual returns (
        uint256 tokensClaimed, bool finalized
    );
}
