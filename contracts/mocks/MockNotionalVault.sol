// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../trading/TradeHandler.sol";
import "../trading/VaultExchangeHandler.sol";
import "../../interfaces/trading/IVaultExchange.sol";
import "../../interfaces/trading/ITradingModule.sol";
import "../../interfaces/WETH9.sol";
import "../../interfaces/chainlink/AggregatorV2V3Interface.sol";

contract MockNotionalVault is IVaultExchange, IVaultExchangeCallback {
    using SafeERC20 for IERC20;
    using TradeHandler for Trade;
    using VaultExchangeHandler for VaultExchange;

    ITradingModule public immutable TRADING_MODULE;
    AggregatorV2V3Interface public immutable EXCHANGE_RATE;
    WETH9 public immutable WETH;
    address public immutable TOKEN_FOR_SALE;

    uint256 public availableAmount;
    address public exchangePartner;

    constructor(
        ITradingModule _tradingModule,
        AggregatorV2V3Interface _exchangeRate,
        WETH9 _weth,
        address _sellToken,
        address _exchangePartner
    ) {
        TRADING_MODULE = _tradingModule;
        EXCHANGE_RATE = _exchangeRate;
        WETH = _weth;
        TOKEN_FOR_SALE = _sellToken;
        exchangePartner = _exchangePartner;
    }

    function setAvailableAmount(uint256 _availableAmount) external {
        availableAmount = _availableAmount;
    }

    function setExchangePartner(address _exchangePartner) external {
        exchangePartner = _exchangePartner;
    }

    function executeTrade(uint16 dexId, Trade calldata trade)
        external
        override
        returns (uint256 amountSold, uint256 amountBought)
    {
        return trade.execute(TRADING_MODULE, dexId, WETH);
    }

    function exchange(VaultExchange calldata request)
        external
        override
        returns (uint256 amountSold, uint256 amountBought)
    {
        require(msg.sender == exchangePartner, "invalid caller");
        require(request.buyToken == TOKEN_FOR_SALE, "not for sale");

        // prettier-ignore
        (
            uint256 sellAmount, 
            uint256 buyAmount
        ) = request._calculateExchange(EXCHANGE_RATE);

        require(buyAmount <= availableAmount, "amount not available");

        return request._exchange(sellAmount, buyAmount);
    }

    function exchangeCallback(address token, uint256 amount) external override {
        require(msg.sender == exchangePartner, "invalid caller");
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    receive() external payable {}
}
