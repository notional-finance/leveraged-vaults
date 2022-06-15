// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.11;

interface ICurveRegistry {
    function find_pool_for_coins(address _from, address _to)
        external
        view
        returns (address);
}
