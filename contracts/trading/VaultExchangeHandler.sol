// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;


import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../interfaces/trading/IVaultExchange.sol";
import "../../interfaces/chainlink/AggregatorV2V3Interface.sol";

library VaultExchangeHandler {
    using SafeERC20 for ERC20;
    using VaultExchangeHandler for VaultExchange;

    function _normalizePrecision(
        uint256 amount,
        uint256 decimalsIn,
        uint256 decimalsOut
    ) internal pure returns (uint256) {
        if (decimalsIn > decimalsOut) {
            amount /= 10**(decimalsIn - decimalsOut);
        } else if (decimalsIn < decimalsOut) {
            amount *= 10**(decimalsOut - decimalsIn);
        }
        return amount;
    }

    /// @notice Handles an exchange request from another Notional vault
    function _calculateExchange(
        VaultExchange memory request,
        AggregatorV2V3Interface oracle
    ) internal view returns (uint256, uint256) {
        TradeType tradeType = TradeType(request.tradeType);

        require(
            tradeType == TradeType.EXACT_IN_SINGLE ||
                tradeType == TradeType.EXACT_OUT_SINGLE,
            "invalid type"
        );

        // prettier-ignore
        (
            /* roundId */,
            int256 rate,
            /* uint256 startedAt */,
            /* updatedAt */,
            /* answeredInRound */
        ) = oracle.latestRoundData();
        require(rate > 0, "invalid rate");

        uint256 rateDecimals = oracle.decimals();
        require(rateDecimals <= 18, "invalid precision");

        uint256 sellAmount = 0;
        uint256 buyAmount = 0;
        uint256 sellDecimals = ERC20(request.sellToken).decimals();
        uint256 buyDecimals = ERC20(request.buyToken).decimals();

        if (tradeType == TradeType.EXACT_IN_SINGLE) {
            sellAmount = request.amount;
            buyAmount = _normalizePrecision(
                (sellAmount * uint256(rate)) / rateDecimals,
                sellDecimals,
                buyDecimals
            );
        } else if (tradeType == TradeType.EXACT_OUT_SINGLE) {
            sellAmount = request.amount;
            buyAmount = _normalizePrecision(
                (buyAmount * rateDecimals) / uint256(rate),
                sellDecimals,
                buyDecimals
            );
        }

        return (sellAmount, buyAmount);
    }

    function _exchange(
        VaultExchange calldata request,
        uint256 sellAmount,
        uint256 buyAmount
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        ERC20(request.buyToken).safeTransfer(msg.sender, buyAmount);
        uint256 sellAmountBefore = ERC20(request.sellToken).balanceOf(
            address(this)
        );
        IVaultExchangeCallback(msg.sender).exchangeCallback(
            request.sellToken,
            sellAmount
        );
        amountBought = buyAmount;
        amountSold =
            ERC20(request.sellToken).balanceOf(address(this)) -
            sellAmountBefore;
        require(amountSold >= sellAmount, "too little received");
    }
}
