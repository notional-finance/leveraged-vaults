// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {ThreeTokenPoolContext, TwoTokenPoolContext, PoolParams} from "../BalancerVaultTypes.sol";
import {Constants} from "../../../global/Constants.sol";
import {IAsset} from "../../../../interfaces/balancer/IBalancerVault.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {ITradingModule} from "../../../../interfaces/trading/ITradingModule.sol";
import {IBoostedPool} from "../../../../interfaces/balancer/IBalancerPool.sol";
import {TokenUtils, IERC20} from "../../../utils/TokenUtils.sol";
import {TwoTokenPoolUtils} from "./TwoTokenPoolUtils.sol";

library Boosted3TokenPoolUtils {
    using TokenUtils for IERC20;
    using TwoTokenPoolUtils for TwoTokenPoolContext;

    function _approveBalancerTokens(ThreeTokenPoolContext memory poolContext, address bptSpender) internal {
        poolContext.basePool._approveBalancerTokens(bptSpender);
        IERC20(poolContext.tertiaryToken).checkApprove(address(BalancerUtils.BALANCER_VAULT), type(uint256).max);

        // For boosted pools, the tokens inside pool context are AaveLinearPool tokens.
        // So, we need to approve the _underlyingToken (primary borrow currency) for trading.
        IBoostedPool underlyingPool = IBoostedPool(poolContext.basePool.primaryToken);
        address primaryUnderlyingAddress = BalancerUtils.getTokenAddress(underlyingPool.getMainToken());
        IERC20(primaryUnderlyingAddress).checkApprove(address(BalancerUtils.BALANCER_VAULT), type(uint256).max);
    }
}
