// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IBalancerVault, IAsset} from "../../../../../interfaces/balancer/IBalancerVault.sol";
import {PoolParams} from "../../BalancerVaultTypes.sol";
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
        uint256 numAssets = params.assets.length;
        exitBalances = new uint256[](numAssets);

        for (uint256 i; i < numAssets; i++) {
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
            exitBalances[i] = TokenUtils.tokenBalance(address(params.assets[i])) - exitBalances[i];
        }
    }
}
