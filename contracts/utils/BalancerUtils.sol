// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;

import "../../interfaces/balancer/IPriceOracle.sol";
import {IBalancerVault} from "../../interfaces/balancer/IBalancerVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library BalancerUtils {
    function getTimeWeightedOraclePrice(
        address pool,
        IPriceOracle.Variable variable,
        uint256 secs
    ) internal view returns (uint256) {
        IPriceOracle.OracleAverageQuery[]
            memory queries = new IPriceOracle.OracleAverageQuery[](1);

        queries[0].variable = variable;
        queries[0].secs = secs;
        queries[0].ago = 0; // now

        // Gets the balancer time weighted average price denominated in ETH
        return IPriceOracle(pool).getTimeWeightedAverage(queries)[0];
    }

    function getPoolAddress(IBalancerVault vault, bytes32 poolId)
        internal
        view
        returns (address)
    {
        // Balancer will revert if pool is not found
        // prettier-ignore
        (address poolAddress, /* */) = vault.getPool(poolId);
        return poolAddress;
    }

    function getTokenAddress(
        IBalancerVault vault,
        bytes32 poolId,
        uint256 tokenIndex
    ) internal view returns (IERC20) {
        // prettier-ignore
        (address[] memory tokens, /* */, /* */) = vault.getPoolTokens(poolId);
        return IERC20(tokens[tokenIndex]);
    }
}
