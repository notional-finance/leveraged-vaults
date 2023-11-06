// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IBalancerVault, IAsset} from "../../../../../interfaces/balancer/IBalancerVault.sol";
import {PoolParams, BalancerComposablePoolContext} from "../../BalancerVaultTypes.sol";
import {Deployments} from "../../../../global/Deployments.sol";
import {TokenUtils, IERC20} from "../../../../utils/TokenUtils.sol";

/**
 * Balancer utility functions
 */
library BalancerUtils {

    /// @notice Special handling for ETH because UNDERLYING_TOKEN == address(0)
    /// and Balancer uses WETH
    function getTokenAddress(address token) internal pure returns (address) {
        return token == Deployments.ETH_ADDRESS ? address(Deployments.WETH) : address(token);
    }

    function _filterBPTToken(
        uint256 bptIndex, uint256[] memory inAmounts
    ) private pure returns (uint256[] memory) {
        if (bptIndex == type(uint256).max) return inAmounts;

        uint256[] memory amountsWithoutBpt = new uint256[](inAmounts.length - 1);
        uint256 j;
        for (uint256 i; i < inAmounts.length; i++) {
            if (i == bptIndex) continue;
            amountsWithoutBpt[j++] = inAmounts[i];
        }

        return amountsWithoutBpt;
    }

    /// @notice Returns parameters for joining and exiting Balancer pools
    function _getPoolParams(
        BalancerComposablePoolContext memory context,
        uint256[] memory amounts,
        bool isJoin,
        bool isSingleSided,
        uint256 bptAmount
    ) internal pure returns (PoolParams memory) {
        address[] memory tokens = context.basePool.tokens;
        uint256 primaryIndex = context.basePool.primaryIndex;
        uint256 bptIndex = context.bptIndex;

        IAsset[] memory assets = new IAsset[](tokens.length);

        uint256 msgValue;
        for (uint256 i; i < tokens.length; i++) {
            assets[i] = IAsset(tokens[i]);
            if (isJoin && tokens[i] == Deployments.ETH_ADDRESS) {
                msgValue = amounts[i];
            }
        }

        bytes memory customData;
        if (isJoin) {
            customData = abi.encode(
                IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                _filterBPTToken(bptIndex, amounts),
                bptAmount // Apply minBPT to prevent front running
            );
        } else {
            // TODO: this needs to change for weighted pool exits...
            if (isSingleSided) {
                // See this line here:
                // https://github.com/balancer/balancer-v2-monorepo/blob/c7d4abbea39834e7778f9ff7999aaceb4e8aa048/pkg/pool-stable/contracts/ComposableStablePool.sol#L927
                // While "assets" sent to the vault include the BPT token the tokenIndex passed in by this
                // function does not include the BPT. primaryIndex in this code is inclusive of the BPT token in
                // the assets array. Therefore, if primaryIndex > bptIndex subtract one to ensure that the primaryIndex
                // does not include the BPT token here.
                customData = abi.encode(
                    IBalancerVault.ComposableExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
                    bptAmount,
                    primaryIndex < bptIndex ?  primaryIndex : primaryIndex - 1
                );
            } else {
                customData = abi.encode(
                    IBalancerVault.ComposableExitKind.EXACT_BPT_IN_FOR_ALL_TOKENS_OUT,
                    bptAmount
                );
            }
        }

        return PoolParams(assets, amounts, msgValue, customData);
    }

    /// @notice Joins a balancer pool using exact tokens in
    /// @param poolId Balancer pool ID
    /// @param poolToken Balancer pool token
    /// @param params join params
    /// @return bptAmount amount of BPT minted
    function _joinPoolExactTokensIn(bytes32 poolId, IERC20 poolToken, PoolParams memory params) 
        internal returns (uint256 bptAmount) {
        bptAmount = poolToken.balanceOf(address(this));
        Deployments.BALANCER_VAULT.joinPool{value: params.msgValue}(
            poolId,
            address(this), // sender
            address(this), //  Vault will receive the pool tokens
            IBalancerVault.JoinPoolRequest(
                params.assets,
                params.amounts,
                params.customData,
                false // Don't use internal balances
            )
        );

        // Calculate the amount of BPT minted
        bptAmount = poolToken.balanceOf(address(this)) - bptAmount;
    }

    /// @notice Exits a balancer pool using exact BPT in
    /// @param poolId Balancer pool ID
    /// @param poolToken Balancer pool token
    /// @param params Pool exit params
    /// @param exitBalances underlying token balances after the exit
    function _exitPoolExactBPTIn(bytes32 poolId, IERC20 poolToken, PoolParams memory params)
        internal returns (uint256[] memory exitBalances) {
        // For composable pools, the asset array includes the BPT token (i.e. poolToken). The balance
        // will decrease in an exit while all of the other balances increase, causing a subtraction
        // underflow in the final loop. For that reason, exit balances are not calculated of the poolToken
        // is included in the array of assets.
        uint256 numAssets = params.assets.length;
        exitBalances = new uint256[](numAssets);

        for (uint256 i; i < numAssets; i++) {
            if (address(params.assets[i]) == address(poolToken)) continue;
            exitBalances[i] = TokenUtils.tokenBalance(address(params.assets[i]));
        }

        Deployments.BALANCER_VAULT.exitPool(
            poolId,
            address(this), // sender
            payable(address(this)), // Vault will receive the underlying assets
            IBalancerVault.ExitPoolRequest(
                params.assets,
                params.amounts,
                params.customData,
                false // Don't use internal balances
            )
        );

        // Calculate the amounts of underlying tokens after the exit
        for (uint256 i; i < numAssets; i++) {
            if (address(params.assets[i]) == address(poolToken)) continue;
            uint256 balanceAfter = TokenUtils.tokenBalance(address(params.assets[i]));
            exitBalances[i] = balanceAfter - exitBalances[i];
        }
    }
}
