// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;
pragma abicoder v2;

import "../../../interfaces/trading/IExchangeAdapter.sol";
import "../../../interfaces/balancer/IBalancerVault.sol";

contract BalancerV2Adapter is IExchangeAdapter {
    address internal constant ETH_ADDRESS = address(0);
    IBalancerVault public immutable VAULT;

    struct SingleSwapData {
        bytes32 poolId;
    }

    struct BatchSwapData {
        IBalancerVault.BatchSwapStep[] swaps;
        IAsset[] assets;
        int256[] limits;
    }

    constructor(IBalancerVault _vault) {
        VAULT = _vault;
    }

    function _single(IBalancerVault.SwapKind kind, address payable from, Trade memory trade)
        internal
        view
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        SingleSwapData memory data = abi.decode(
            trade.exchangeData,
            (SingleSwapData)
        );

        return (
            address(VAULT),
            trade.sellToken == ETH_ADDRESS ? trade.amount : 0,
            abi.encodeWithSelector(
                IBalancerVault.swap.selector,
                IBalancerVault.SingleSwap(
                    data.poolId,
                    kind,
                    IAsset(trade.sellToken),
                    IAsset(trade.buyToken),
                    trade.amount,
                    new bytes(0)
                ),
                IBalancerVault.FundManagement(
                    from,
                    false,
                    from,
                    false
                ),
                trade.limit,
                trade.deadline
            )
        );
    }

    function _batch(IBalancerVault.SwapKind kind, address payable from, Trade memory trade)
        internal
        view
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        BatchSwapData memory data = abi.decode(
            trade.exchangeData,
            (BatchSwapData)
        );

        return (
            address(VAULT),
            trade.sellToken == ETH_ADDRESS ? trade.amount : 0,
            abi.encodeWithSelector(
                IBalancerVault.batchSwap.selector,
                kind,
                data.swaps,
                data.assets,
                IBalancerVault.FundManagement(
                    from,
                    false,
                    from,
                    false
                ),
                data.limits,
                trade.deadline
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
        if (TradeType(trade.tradeType) == TradeType.EXACT_IN_SINGLE) {
            return _single(IBalancerVault.SwapKind.GIVEN_IN, from, trade);
        } else if (TradeType(trade.tradeType) == TradeType.EXACT_OUT_SINGLE) {
            return _single(IBalancerVault.SwapKind.GIVEN_OUT, from, trade);
        } else if (TradeType(trade.tradeType) == TradeType.EXACT_IN_BATCH) {
            return _batch(IBalancerVault.SwapKind.GIVEN_IN, from, trade);
        } else if (TradeType(trade.tradeType) == TradeType.EXACT_OUT_BATCH) {
            return _batch(IBalancerVault.SwapKind.GIVEN_OUT, from, trade);
        }

        revert("invalid trade");
    }

    function getSpender(Trade calldata trade)
        external
        view
        override
        returns (address)
    {
        if (trade.sellToken == ETH_ADDRESS) return address(0);
        return address(VAULT);
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
