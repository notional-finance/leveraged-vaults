// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Deployments} from "@deployments/Deployments.sol";
import {Trade, TradeType, InvalidTrade} from "@interfaces/trading/ITradingModule.sol";
import {ICurveRouterV2} from "@interfaces/curve/ICurveRouterV2.sol";
import {ICurvePool} from "@interfaces/curve/ICurvePool.sol";

library CurveV2Adapter {
    uint256 internal constant ROUTE_LEN = 9;

    struct CurveV2SingleData {
        // Address of the pool to use for the swap
        address pool;
        int128 fromIndex;
        int128 toIndex;
    }

    struct CurveV2BatchData { 
        // Array of [initial token, pool, token, pool, token, ...]
        // The array is iterated until a pool address of 0x00, then the last
        // given token is transferred to `_receiver`
        address[ROUTE_LEN] route;
        // Multidimensional array of [i, j, swap type] where i and j are the correct
        // values for the n'th pool in `_route`. The swap type should be
        // 1 for a stableswap `exchange`,
        // 2 for stableswap `exchange_underlying`,
        // 3 for a cryptoswap `exchange`,
        // 4 for a cryptoswap `exchange_underlying`,
        // 5 for factory metapools with lending base pool `exchange_underlying`,
        // 6 for factory crypto-meta pools underlying exchange (`exchange` method in zap),
        // 7-11 for wrapped coin (underlying for lending or fake pool) -> LP token "exchange" (actually `add_liquidity`),
        // 12-14 for LP token -> wrapped coin (underlying for lending pool) "exchange" (actually `remove_liquidity_one_coin`)
        // 15 for WETH -> ETH "exchange" (actually deposit/withdraw)
        uint256[3][4] swapParams;
    }

    function _getTokenAddress(address token) internal pure returns (address) {
        return token == Deployments.ETH_ADDRESS ? Deployments.ALT_ETH_ADDRESS : token;
    }

    function getExecutionData(address from, Trade memory trade)
        internal pure returns (
            address spender,
            address target,
            uint256 msgValue,
            bytes memory executionCallData
        )
    {
        if (trade.sellToken == Deployments.ETH_ADDRESS) {
            msgValue = trade.amount;
        }

        if (trade.tradeType == TradeType.EXACT_IN_SINGLE) {
            CurveV2SingleData memory data = abi.decode(trade.exchangeData, (CurveV2SingleData));
            target = data.pool;

            executionCallData = abi.encodeWithSelector(
                ICurvePool.exchange.selector,
                data.fromIndex, data.toIndex,
                trade.amount,
                trade.limit
            );
        } else if (trade.tradeType == TradeType.EXACT_IN_BATCH) {
            CurveV2BatchData memory data = abi.decode(trade.exchangeData, (CurveV2BatchData));
            target = address(Deployments.CURVE_ROUTER_V2);

            // Validate exchange data
            require(data.route[0] == _getTokenAddress(trade.sellToken));
            bool ended = false;
            for (uint256 i = 1; i < ROUTE_LEN; i++) {
                // Route ends with address(0)
                if (ended) {
                    require(data.route[i] == address(0));
                } else {
                    if (data.route[i] == address(0)) {
                        require(data.route[i - 1] == _getTokenAddress(trade.buyToken));
                        ended = true;
                    }
                }
            }

            // Array of pools for swaps via zap contracts. This parameter is only needed for
            // Polygon meta-factories underlying swaps.
            address[4] memory pools;
            executionCallData = abi.encodeWithSelector(
                ICurveRouterV2.exchange_multiple.selector,
                data.route,
                data.swapParams,
                trade.amount,
                trade.limit,
                pools,
                from
            );
        } else {
            // EXACT_OUT_SINGLE and EXACT_OUT_BATCH are not supported by Curve
            revert InvalidTrade();
        }

        spender = target;
    }
}