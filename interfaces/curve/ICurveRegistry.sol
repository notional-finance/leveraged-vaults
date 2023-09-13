// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

interface ICurveRegistry {
    function find_pool_for_coins(address _from, address _to, uint256 i)
        external
        view
        returns (address);
}
