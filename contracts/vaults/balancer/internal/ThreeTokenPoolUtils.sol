// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {ThreeTokenPoolContext, TwoTokenPoolContext, PoolParams} from "../BalancerVaultTypes.sol";
import {Constants} from "../../../global/Constants.sol";
import {IAsset} from "../../../../interfaces/balancer/IBalancerVault.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {ITradingModule} from "../../../../interfaces/trading/ITradingModule.sol";
import {IPriceOracle} from "../../../../interfaces/balancer/IPriceOracle.sol";
import {TokenUtils, IERC20} from "../../../utils/TokenUtils.sol";
import {TwoTokenPoolUtils} from "./TwoTokenPoolUtils.sol";

library ThreeTokenPoolUtils {
    using TokenUtils for IERC20;
    using TwoTokenPoolUtils for TwoTokenPoolContext;

    /// @notice Returns parameters for joining and exiting Balancer pools
    function _getPoolParams(
        ThreeTokenPoolContext memory context,
        uint256 primaryAmount,
        uint256 secondaryAmount,
        uint256 tertiaryAmount,
        bool isJoin
    ) internal pure returns (PoolParams memory) {
        IAsset[] memory assets = new IAsset[](3);
        assets[context.basePool.primaryIndex] = IAsset(context.basePool.primaryToken);
        assets[context.basePool.secondaryIndex] = IAsset(context.basePool.secondaryToken);
        assets[context.tertiaryIndex] = IAsset(context.tertiaryToken);

        uint256[] memory amounts = new uint256[](3);
        amounts[context.basePool.primaryIndex] = primaryAmount;
        amounts[context.basePool.secondaryIndex] = secondaryAmount;
        amounts[context.tertiaryIndex] = tertiaryAmount;

        uint256 msgValue;
        if (isJoin && assets[context.basePool.primaryIndex] == IAsset(Constants.ETH_ADDRESS)) {
            msgValue = amounts[context.basePool.primaryIndex];
        }

        return PoolParams(assets, amounts, msgValue);
    }

    function _approveBalancerTokens(ThreeTokenPoolContext memory poolContext, address bptSpender) internal {
        poolContext.basePool._approveBalancerTokens(bptSpender);
        IERC20(poolContext.tertiaryToken).checkApprove(address(BalancerUtils.BALANCER_VAULT), type(uint256).max);
    }
}
