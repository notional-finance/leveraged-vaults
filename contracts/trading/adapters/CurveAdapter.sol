// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;


import "../../global/Constants.sol";
import "../../../interfaces/trading/ITradingModule.sol";
import "../../../interfaces/WETH9.sol";
import "../../../interfaces/curve/ICurvePool.sol";
import "../../../interfaces/curve/ICurveRouter.sol";
import "../../../interfaces/curve/ICurveRegistry.sol";
import "../../../interfaces/curve/ICurveRegistryProvider.sol";

library CurveAdapter {
    int128 internal constant MAX_TOKENS = 4;
    address internal constant CURVE_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    ICurveRegistry public constant REGISTRY = ICurveRegistry(0x0000000022D53366457F9d5E68Ec105046FC4383);
    ICurveRouter public constant ROUTER = ICurveRouter(0xfA9a30350048B2BF66865ee20363067c66f67e58);
    WETH9 public constant WETH = WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    struct CurveBatchData { 
        address[6] route;
        uint256[8] indices;
    }

    function _getTokenAddress(address token) internal view returns (address) {
        return (token == Constants.ETH_ADDRESS || token == address(WETH)) ? CURVE_ETH_ADDRESS : token;
    }

    function _exactInBatch(Trade memory trade) internal view returns (bytes memory executionCallData) {
        CurveBatchData memory data = abi.decode(trade.exchangeData, (CurveBatchData));

        return abi.encodeWithSelector(
            ICurveRouter.exchange.selector,
            trade.amount,
            data.route,
            data.indices,
            trade.limit
        );
    }

    function _exactInSingle(Trade memory trade)
        internal view returns (address target, bytes memory executionCallData)
    {
        address sellToken = _getTokenAddress(trade.sellToken);
        address buyToken = _getTokenAddress(trade.buyToken);
        ICurvePool pool = ICurvePool(REGISTRY.find_pool_for_coins(sellToken, buyToken));

        if (address(pool) == address(0)) revert InvalidTrade();

        int128 i = -1;
        int128 j = -1;
        for (int128 c = 0; c < MAX_TOKENS; i++) {
            address coin = pool.coins(uint256(int256(c)));
            if (coin == sellToken) i = c;
            if (coin == buyToken) j = c;
            if (i > -1 && j > -1) break;
        }

        if (i == -1 || j == -1) revert InvalidTrade();

        return (
            address(pool),
            abi.encodeWithSelector(
                ICurvePool.exchange.selector,
                i,
                j,
                trade.amount,
                trade.limit
            )
        );
    }

    function getExecutionData(address from, Trade calldata trade)
        internal view returns (
            address spender,
            address target,
            uint256 msgValue,
            bytes memory executionCallData
        )
    {
        if (trade.tradeType == TradeType.EXACT_IN_SINGLE) {
            (target, executionCallData) = _exactInSingle(trade);
        } else if (trade.tradeType == TradeType.EXACT_IN_BATCH) {
            target = address(ROUTER);
            executionCallData = _exactInBatch(trade);
        } else {
            // EXACT_OUT_SINGLE and EXACT_OUT_BATCH are not supported by Curve
            revert InvalidTrade();
        }

        if (trade.sellToken == address(WETH)) {
            // Curve does not support WETH as an input
            spender = address(0);
            msgValue = trade.amount;
        } else {
            spender = target;
        }
    }
}
