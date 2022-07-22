// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {TwoTokenPoolContext, PoolParams} from "../BalancerVaultTypes.sol";
import {Constants} from "../../../global/Constants.sol";
import {IAsset} from "../../../../interfaces/balancer/IBalancerVault.sol";

library TwoTokenPoolUtils {
    /// @notice Returns parameters for joining and exiting pool
    function _getPoolParams(
        TwoTokenPoolContext memory context,
        uint256 primaryAmount,
        uint256 secondaryAmount,
        bool isJoin
    ) internal pure returns (PoolParams memory) {
        IAsset[] memory assets = new IAsset[](2);
        assets[context.primaryIndex] = IAsset(context.primaryToken);
        uint8 secondaryIndex;
        unchecked { secondaryIndex = 1 - context.primaryIndex; }
        assets[secondaryIndex] = IAsset(context.secondaryToken);

        uint256[] memory amounts = new uint256[](2);
        amounts[context.primaryIndex] = primaryAmount;
        amounts[secondaryIndex] = secondaryAmount;

        uint256 msgValue;
        if (isJoin && assets[context.primaryIndex] == IAsset(Constants.ETH_ADDRESS)) {
            msgValue = amounts[context.primaryIndex];
        }

        return PoolParams(assets, amounts, msgValue);
    }
}
