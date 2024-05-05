// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {IERC4626} from "@interfaces/IERC4626.sol";
import {IERC20} from "@interfaces/IERC20.sol";

interface IsUSDe is IERC4626, IERC20 {
    struct UserCooldown {
        uint104 cooldownEnd;
        uint152 underlyingAmount;
    }

    function cooldownDuration() external view returns (uint24);
    function cooldowns(address account) external view returns (UserCooldown memory);
    function cooldownShares(uint256 shares) external returns (uint256 assets);
    function unstake(address receiver) external;
}
