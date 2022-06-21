// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;

import "../../interfaces/balancer/IPriceOracle.sol";
import {IBalancerVault} from "../../interfaces/balancer/IBalancerVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library BalancerUtils {
    
    error InvalidTokenIndex(uint256 tokenIndex);

    function getTimeWeightedOraclePrice(
        address pool,
        IPriceOracle.Variable variable,
        uint256 secs
    ) external view returns (uint256) {
        IPriceOracle.OracleAverageQuery[]
            memory queries = new IPriceOracle.OracleAverageQuery[](1);

        queries[0].variable = variable;
        queries[0].secs = secs;
        queries[0].ago = 0; // now

        // Gets the balancer time weighted average price denominated in ETH
        return IPriceOracle(pool).getTimeWeightedAverage(queries)[0];
    }

    function getPoolAddress(IBalancerVault vault, bytes32 poolId)
        external
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
    ) external view returns (IERC20) {
        // prettier-ignore
        (address[] memory tokens, /* */, /* */) = vault.getPoolTokens(poolId);
        return IERC20(tokens[tokenIndex]);
    }

    /// @notice Gets the current spot price with a given token index
    /// @param tokenIndex 0 = PRIMARY_TOKEN, 1 = SECONDARY_TOKEN
    /// @return spotPrice token spot price
    function getSpotPrice(
        IBalancerVault vault,
        bytes32 poolId,
        uint256 tokenIndex,
        uint256 primaryIndex,
        uint256 primaryWeight,
        uint256 secondaryWeight,
        uint256 primaryDecimals,
        uint256 secondaryDecimals
    ) external view returns (uint256) {
        // prettier-ignore
        (
            /* address[] memory tokens */,
            uint256[] memory balances,
            /* uint256 lastChangeBlock */
        ) = vault.getPoolTokens(poolId);

        // Make everything 1e18
        uint256 primaryBalance = balances[primaryIndex] *
            10**(18 - primaryDecimals);
        uint256 secondaryBalance = balances[1 - primaryIndex] *
            10**(18 - secondaryDecimals);

        // First we multiply everything by 1e18 for the weight division (weights are in 1e18),
        // then we multiply the numerator by 1e18 to to preserve enough precision for the division
        if (tokenIndex == primaryIndex) {
            // PrimarySpotPrice = (SecondaryBalance / SecondaryWeight * 1e18) / (PrimaryBalance / PrimaryWeight)
            return
                (((secondaryBalance * 1e18) / secondaryWeight) * 1e18) /
                ((primaryBalance * 1e18) / primaryWeight);
        } else if (tokenIndex == (1 - primaryIndex)) {
            // SecondarySpotPrice = (PrimaryBalance / PrimaryWeight * 1e18) / (SecondaryBalance / SecondaryWeight)
            return
                (((primaryBalance * 1e18) / primaryWeight) * 1e18) /
                ((secondaryBalance * 1e18) / secondaryWeight);
        }

        revert InvalidTokenIndex(tokenIndex);
    }
}
