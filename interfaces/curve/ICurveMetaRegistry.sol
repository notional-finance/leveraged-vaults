// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

interface ICurveMetaRegistry {
    function get_registry_handlers_from_pool(address _pool)
        external
        view
        returns (address[10] memory);
}
