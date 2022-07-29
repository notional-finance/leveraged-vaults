// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    Boosted3TokenAuraStrategyContext,
    DepositParams,
    RedeemParams,
    PoolParams,
    StrategyContext,
    ThreeTokenPoolContext,
    TwoTokenPoolContext,
    PoolContext
} from "../BalancerVaultTypes.sol";
import {Constants} from "../../../global/Constants.sol";
import {TokenUtils, IERC20} from "../../../utils/TokenUtils.sol";
import {ThreeTokenAuraStrategyUtils} from "../internal/ThreeTokenAuraStrategyUtils.sol";
import {BalancerUtils} from "../internal/BalancerUtils.sol";
import {ThreeTokenPoolUtils} from "../internal/ThreeTokenPoolUtils.sol";
import {IBoostedPool} from "../../../../interfaces/balancer/IBalancerPool.sol";

library Boosted3TokenAuraVaultHelper {
    using ThreeTokenAuraStrategyUtils for StrategyContext;
    using ThreeTokenPoolUtils for ThreeTokenPoolContext;
    using TokenUtils for IERC20;

    function _underlyingPoolContext(IBoostedPool pool) 
        private view returns (ThreeTokenPoolContext memory underlyingPoolContext, uint8 underlyingPrimaryIndex) {
        bytes32 poolId = pool.getPoolId();
        address underlyingToken = pool.getMainToken();

        // prettier-ignore
        (
            address[] memory tokens,
            uint256[] memory balances,
            /* uint256 lastChangeBlock */
        ) = BalancerUtils.BALANCER_VAULT.getPoolTokens(poolId);
        
        underlyingPoolContext = ThreeTokenPoolContext({
            tertiaryToken: address(tokens[2]),
            tertiaryIndex: 2,
            tertiaryDecimals: IERC20(tokens[2]).uint8Decimals(),
            tertiaryBalance: balances[2],
            basePool: TwoTokenPoolContext({
                primaryToken: address(tokens[0]),
                secondaryToken: address(tokens[1]),
                primaryIndex: 0,
                secondaryIndex: 1,
                primaryDecimals: IERC20(tokens[0]).uint8Decimals(),
                secondaryDecimals: IERC20(tokens[1]).uint8Decimals(),
                primaryBalance: balances[0],
                secondaryBalance: balances[1],
                basePool: PoolContext(IERC20(address(pool)), poolId)
            })
        });
        if (tokens[0] == underlyingToken) {
            underlyingPrimaryIndex = 0;
        } else if (tokens[1] == underlyingToken) {
            underlyingPrimaryIndex = 1;
        } else if (tokens[2] == underlyingToken) {
            underlyingPrimaryIndex = 2;
        } else {
            revert();
        }
    }

    function _joinUnderlyingPool(
        TwoTokenPoolContext memory context, 
        uint256 deposit, 
        uint256 minBPT
    ) private returns (uint256 bptAmount) {
        IBoostedPool pool = IBoostedPool(address(context.primaryToken));

        (
            ThreeTokenPoolContext memory underlyingPoolContext,
            uint8 underlyingPrimaryIndex
        ) = _underlyingPoolContext(pool);

        PoolParams memory poolParams = underlyingPoolContext._getSingleSidedPoolParams(
            deposit, underlyingPrimaryIndex, true /* isJoin */
        );

        // Join the underlying boosted pool
        bptAmount = BalancerUtils.joinPoolExactTokensIn({
            context: context.basePool,
            params: poolParams,
            minBPT: minBPT
        });
    }

    function _depositFromNotional(
        Boosted3TokenAuraStrategyContext memory context,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) external returns (uint256 strategyTokensMinted) {
        DepositParams memory params = abi.decode(data, (DepositParams));

        uint256 bptAmount = _joinUnderlyingPool(
            context.poolContext.basePool,
            deposit,
            params.minBPT
        );

        // Join the 3 token boosted pool with the underlying bptAmount
        strategyTokensMinted = context.baseStrategy._deposit({
            stakingContext: context.stakingContext, 
            poolContext: context.poolContext,
            deposit: bptAmount,
            maturity: maturity,
            params: params
        });
    }

    function _redeemFromNotional(
        Boosted3TokenAuraStrategyContext memory context,
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) external returns (uint256 finalPrimaryBalance) {
        RedeemParams memory params = abi.decode(data, (RedeemParams));
        finalPrimaryBalance = context.baseStrategy._redeem({
            stakingContext: context.stakingContext,
            poolContext: context.poolContext,
            account: account,
            strategyTokens: strategyTokens,
            maturity: maturity,
            params: params
        });
    }
}
