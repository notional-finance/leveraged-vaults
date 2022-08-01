// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;

library Events {
    event RewardReinvested(address token, uint256 primaryAmount, uint256 secondaryAmount, uint256 bptAmount);
}