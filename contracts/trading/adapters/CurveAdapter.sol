// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../../interfaces/trading/IExchangeAdapter.sol";
import "../../../interfaces/WETH9.sol";
import "../../../interfaces/curve/ICurvePool.sol";
import "../../../interfaces/curve/ICurveRouter.sol";
import "../../../interfaces/curve/ICurveRegistry.sol";
import "../../../interfaces/curve/ICurveRegistryProvider.sol";

contract CurveAdapter is IExchangeAdapter {
    using SafeERC20 for IERC20;
    using SafeERC20 for WETH9;

    int128 public constant MAX_TOKENS = 4;
    address internal constant ETH_ADDRESS = address(0);
    address internal constant CURVE_ETH_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    ICurveRegistry public immutable REGISTRY;
    ICurveRouter public immutable ROUTER;
    WETH9 public immutable WETH;

    constructor(
        ICurveRegistryProvider _provider,
        ICurveRouter _router,
        WETH9 _weth
    ) {
        REGISTRY = ICurveRegistry(_provider.get_registry());
        ROUTER = _router;
        WETH = _weth;
    }

    function _getIndex(ICurvePool pool, address token)
        internal
        view
        returns (int128)
    {
        for (int128 i = 0; i < MAX_TOKENS; i++) {
            if (token == pool.coins(uint256(uint128(i)))) {
                return i;
            }
        }
        return -1;
    }

    function _isEthAddress(address addr) internal view returns (bool) {
        return addr == ETH_ADDRESS || addr == address(WETH);
    }

    function _getTokenAddress(address token) internal view returns (address) {
        if (_isEthAddress(token)) {
            return CURVE_ETH_ADDRESS;
        }
        return token;
    }

    function _findPool(Trade memory trade) internal view returns (address) {
        address pool = REGISTRY.find_pool_for_coins(
            _getTokenAddress(trade.sellToken),
            _getTokenAddress(trade.buyToken)
        );

        if (pool == address(0)) {
            return address(ROUTER);
        }

        return pool;
    }

    function _exchange(Trade memory trade)
        internal
        view
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        ICurvePool pool = ICurvePool(_findPool(trade));

        int128 i = _getIndex(pool, _getTokenAddress(trade.sellToken));

        require(i >= 0, "invalid sellToken");

        int128 j = _getIndex(pool, _getTokenAddress(trade.buyToken));

        require(j >= 0, "invalid buyToken");

        uint256 msgValue = trade.sellToken == address(WETH) ? trade.amount : 0;

        return (
            address(pool),
            msgValue,
            abi.encodeWithSelector(
                ICurvePool.exchange.selector,
                i,
                j,
                trade.amount,
                trade.limit
            )
        );
    }

    function getExecutionData(address payable from, Trade calldata trade)
        external
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        require(
            TradeType(trade.tradeType) == TradeType.EXACT_IN_SINGLE,
            "invalid type"
        );

        return _exchange(trade);
    }

    function getSpender(Trade calldata trade)
        external
        view
        override
        returns (address)
    {
        if (_isEthAddress(trade.sellToken)) {
            // No need to approve if the vault is sending ETH
            return address(0);
        }

        return _findPool(trade);
    }

    function getLiquidity(bytes calldata params)
        external
        view
        override
        returns (address[] memory, uint256[] memory)
    {
        address[] memory tokens = new address[](0);
        uint256[] memory balances = new uint256[](0);

        return (tokens, balances);
    }
}
