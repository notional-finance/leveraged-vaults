// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;

import "../../interfaces/balancer/IPriceOracle.sol";
import {IBalancerVault, IAsset} from "../../interfaces/balancer/IBalancerVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WETH9} from "../../interfaces/WETH9.sol";

library BalancerUtils {
    WETH9 public constant WETH =
        WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

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
        uint8 primaryIndex,
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

    function _getPoolParams(
        address primaryAddress,
        uint256 primaryAmount,
        address secondaryAddress,
        uint256 secondaryAmount,
        uint8 primaryIndex
    ) private view returns (IAsset[] memory assets, uint256[] memory amounts) {
        assets = new IAsset[](2);
        assets[primaryIndex] = IAsset(primaryAddress);
        assets[1 - primaryIndex] = IAsset(secondaryAddress);

        amounts = new uint256[](2);
        amounts[primaryIndex] = primaryAmount;
        amounts[1 - primaryIndex] = secondaryAmount;
    }

    function joinPool(
        address vault,
        bytes32 poolId,
        address primaryAddress,
        uint256 maxPrimaryAmount,
        address secondaryAddress,
        uint256 maxSecondaryAmount,
        uint8 primaryIndex,
        uint256 minBPT
    ) external {
        // prettier-ignore
        (
            IAsset[] memory assets,
            uint256[] memory maxAmountsIn
        ) = _getPoolParams(
            primaryAddress,
            maxPrimaryAmount,
            secondaryAddress,
            maxSecondaryAmount,
            primaryIndex
        );

        uint256 msgValue = assets[primaryIndex] == IAsset(address(0))
            ? maxAmountsIn[primaryIndex]
            : 0;

        // Join pool
        IBalancerVault(vault).joinPool{value: msgValue}(
            poolId,
            address(this),
            address(this),
            IBalancerVault.JoinPoolRequest(
                assets,
                maxAmountsIn,
                abi.encode(
                    IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                    maxAmountsIn,
                    minBPT // Apply minBPT to prevent front running
                ),
                false // Don't use internal balances
            )
        );
    }

    function exitPool(
        address vault,
        bytes32 poolId,
        address primaryAddress,
        uint256 minPrimaryAmount,
        address secondaryAddress,
        uint256 minSecondaryAmount,
        uint8 primaryIndex,
        uint256 bptExitAmount,
        bool withdrawFromWETH
    ) external {
        // prettier-ignore
        (
            IAsset[] memory assets,
            uint256[] memory minAmountsOut
        ) = _getPoolParams(
            withdrawFromWETH ? address(0) : address(WETH),
            minPrimaryAmount,
            secondaryAddress,
            minSecondaryAmount,
            primaryIndex
        );

        IBalancerVault(vault).exitPool(
            poolId,
            address(this),
            payable(msg.sender), // Owner will receive the underlying assets
            IBalancerVault.ExitPoolRequest(
                assets,
                minAmountsOut,
                abi.encode(
                    IBalancerVault.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT,
                    bptExitAmount
                ),
                false // Don't use internal balances
            )
        );
    }
}
