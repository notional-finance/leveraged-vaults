// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;

import "../../interfaces/balancer/IPriceOracle.sol";
import {IBalancerVault, IAsset} from "../../interfaces/balancer/IBalancerVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WETH9} from "../../interfaces/WETH9.sol";

// @audit since this is actually balancer specific, maybe we should make a sub folder in vaults/Balancer
// and just put this in there instead?
library BalancerUtils {
    // @audit this is declared as well in Balancer2TokenVault, perhaps just remove one.
    WETH9 public constant WETH =
        WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IBalancerVault public constant BALANCER_VAULT =
        IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    address internal constant ETH_ADDRESS = address(0);
    uint256 public constant BALANCER_PRECISION = 1e18;

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

        // @audit is this comment correct? isn't the price denominated in the first token?
        // Gets the balancer time weighted average price denominated in ETH
        return IPriceOracle(pool).getTimeWeightedAverage(queries)[0];
    }

    // @audit this is marked external which means Balancer2TokenVault will use a significant
    // amount of gas to call this method, maybe just inline it into the constructor
    function getPoolAddress(bytes32 poolId)
        external
        view
        returns (address)
    {
        // Balancer will revert if pool is not found
        // prettier-ignore
        (address poolAddress, /* */) = BALANCER_VAULT.getPool(poolId);
        return poolAddress;
    }

    // @audit this method is never called FYI, it is called directly in the constructor
    function getTokenAddress(
        bytes32 poolId,
        uint256 tokenIndex
    ) external view returns (IERC20) {
        // prettier-ignore
        (address[] memory tokens, /* */, /* */) = BALANCER_VAULT.getPoolTokens(poolId);
        return IERC20(tokens[tokenIndex]);
    }

    /// @notice Gets the current spot price with a given token index
    /// @param tokenIndex 0 = PRIMARY_TOKEN, 1 = SECONDARY_TOKEN
    /// @return spotPrice token spot price
    function getSpotPrice(
        bytes32 poolId,
        uint256 tokenIndex,
        uint8 primaryIndex,
        uint256 primaryWeight,
        uint256 secondaryWeight,
        uint256 primaryDecimals,
        uint256 secondaryDecimals
    ) external view returns (uint256) {
        // @audit can this method be replaced with this method call instead?
        // https://dev.balancer.fi/references/contracts/apis/pools/weightedpool2tokens#getlatest

        // prettier-ignore
        (
            /* address[] memory tokens */,
            uint256[] memory balances,
            /* uint256 lastChangeBlock */
        ) = BALANCER_VAULT.getPoolTokens(poolId);

        // Make everything 1e18
        // @audit check if the decimals != 18 to save some gas since 18 is so common, also this is an edge case but if
        // your decimals are greater than 18 this will underflow (probably will never happen)
        uint256 primaryBalance = balances[primaryIndex] *
            10**(18 - primaryDecimals);
        uint256 secondaryBalance = balances[1 - primaryIndex] *
            10**(18 - secondaryDecimals);

        // First we multiply everything by 1e18 for the weight division (weights are in 1e18),
        // then we multiply the numerator by 1e18 to to preserve enough precision for the division
        if (tokenIndex == primaryIndex) {
            // @audit rearrange this so that multiplication always comes before division
            // PrimarySpotPrice = (SecondaryBalance / SecondaryWeight * 1e18) / (PrimaryBalance / PrimaryWeight)
            return
                (((secondaryBalance * 1e18) / secondaryWeight) * 1e18) /
                ((primaryBalance * 1e18) / primaryWeight);
        } else if (tokenIndex == (1 - primaryIndex)) {
            // @audit rearrange this so that multiplication always comes before division
            // SecondarySpotPrice = (PrimaryBalance / PrimaryWeight * 1e18) / (SecondaryBalance / SecondaryWeight)
            return
                (((primaryBalance * 1e18) / primaryWeight) * 1e18) /
                ((secondaryBalance * 1e18) / secondaryWeight);
        }

        // @audit move the revert to the top of the method, then you can get rid of the else if above since you will
        // know that tokenIndex is always 1 or 0
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
        // @audit mark unchecked { 1 - primaryIndex } to reduce bytecode size, checked
        // arithmetic is costs 15x gas versus unchecked
        assets[1 - primaryIndex] = IAsset(secondaryAddress);

        amounts = new uint256[](2);
        amounts[primaryIndex] = primaryAmount;
        amounts[1 - primaryIndex] = secondaryAmount;
    }

    // @audit this should be renamed joinPoolExactTokensIn since there are other join methods we may
    // use in the future
    function joinPool(
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

        // @audit use a named constant for address(0)
        uint256 msgValue = assets[primaryIndex] == IAsset(address(0))
            ? maxAmountsIn[primaryIndex]
            : 0;

        // Join pool
        BALANCER_VAULT.joinPool{value: msgValue}(
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

    // @audit this should be renamed exitPoolExactBPTIn since there are other exit methods we may use in the future
    function exitPool(
        bytes32 poolId,
        address primaryAddress,
        uint256 minPrimaryAmount,
        address secondaryAddress,
        uint256 minSecondaryAmount,
        uint8 primaryIndex,
        uint256 bptExitAmount,
        bool withdrawFromWETH // @audit would this be more clear if it was redeemToETH
    ) external {
        // prettier-ignore
        (
            IAsset[] memory assets,
            uint256[] memory minAmountsOut
        ) = _getPoolParams(
            primaryAddress == ETH_ADDRESS ? (withdrawFromWETH ? ETH_ADDRESS : address(WETH)) : primaryAddress,
            minPrimaryAmount,
            secondaryAddress,
            minSecondaryAmount,
            primaryIndex
        );

        BALANCER_VAULT.exitPool(
            poolId,
            address(this),
            payable(address(this)), // Vault will receive the underlying assets
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
