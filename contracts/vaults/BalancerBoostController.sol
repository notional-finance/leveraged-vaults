// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.8.11;

import {IBoostController} from "../../interfaces/notional/IBoostController.sol";

contract BalancerBoostController is IBoostController {
    function depositToken(address token, uint256 amount) external override {}

    function withdrawToken(address token, uint256 amount) external override {}

    function claimRewards(address liquidityGauge) external override {}
}
