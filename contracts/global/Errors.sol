// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;

library Errors {
    error InvalidSpotPrice(uint256 oraclePrice, uint256 spotPrice);
}