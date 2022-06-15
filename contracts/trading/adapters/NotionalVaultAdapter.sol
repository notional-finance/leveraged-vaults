// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;
pragma abicoder v2;

import "../../../interfaces/trading/IExchangeAdapter.sol";
import "../../../interfaces/trading/IVaultExchange.sol";

contract NotionalVaultAdapter is IExchangeAdapter {
    struct NotionalVaultData {
        address vault;
    }

    constructor() {}

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
        NotionalVaultData memory data = abi.decode(
            trade.exchangeData,
            (NotionalVaultData)
        );
        return (
            data.vault,
            0,
            abi.encodeWithSelector(
                IVaultExchange.exchange.selector,
                VaultExchange(
                    trade.tradeType,
                    trade.sellToken,
                    trade.buyToken,
                    trade.amount,
                    trade.limit
                )
            )
        );
    }

    function getSpender(Trade calldata trade)
        external
        view
        override
        returns (address)
    {
        NotionalVaultData memory data = abi.decode(
            trade.exchangeData,
            (NotionalVaultData)
        );
        return data.vault;
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
