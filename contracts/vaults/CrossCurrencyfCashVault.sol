// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.8.11;
pragma abicoder v2;

import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {IWrappedfCashFactory} from "../../../interfaces/notional/IWrappedfCashFactory.sol";
import {IWrappedfCashComplete as IWrappedfCash} from "../../../interfaces/notional/IWrappedfCash.sol";
import {BaseStrategyVault} from "./BaseStrategyVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    BalanceActionWithTrades,
    DepositActionType,
    TradeActionType,
    BatchLend,
    Token,
    TokenType,
    VaultState
} from "../global/Types.sol";
import {Constants} from "../global/Constants.sol";
import {DateTime} from "../global/DateTime.sol";
import {SafeInt256} from "../global/SafeInt256.sol";
import {ITradingModule} from "../../interfaces/trading/ITradingModule.sol";
import {TradeHandler} from "@notional-trading-module/contracts/TradeHandler.sol";

/**
 * @notice This vault borrows in one currency, trades it to a different currency
 * and lends on Notional in that currency. It will be paired with another vault
 * that lends and borrows in the opposite direction.
 */
contract CrossCurrencyfCashVault is BaseStrategyVault {
    using SafeInt256 for uint256;

    uint16 public immutable LEND_CURRENCY_ID;
    ERC20 public immutable LEND_UNDERLYING_TOKEN;
    ITradingModule public immutable TRADING_MODULE;

    constructor(
        string memory name_,
        address notional_,
        ITradingModule tradingModule_,
        uint16 borrowCurrencyId_,
        uint16 lendCurrencyId_
    ) BaseStrategyVault(name_, notional_, borrowCurrencyId_, true, true) {
        LEND_CURRENCY_ID = lendCurrencyId_;
        TRADING_MODULE = tradingModule_;

        (
            Token memory assetToken,
            Token memory underlyingToken,
            /* ETHRate memory ethRate */,
            /* AssetRateParameters memory assetRate */
        ) = NotionalProxy(notional_).getCurrencyAndRates(lendCurrencyId_);

        ERC20 tokenAddress = assetToken.tokenType == TokenType.NonMintable ?
            ERC20(assetToken.tokenAddress) : ERC20(underlyingToken.tokenAddress);
        LEND_UNDERLYING_TOKEN = tokenAddress;
    }

    /**
     * @notice During settlement all of the fCash balance in the lend currency will be redeemed to the
     * underlying token and traded back to the borrow currency. All of the borrow currency will be deposited
     * into the Notional contract as asset tokens and held for accounts to withdraw. Settlement can only
     * be called after maturity.
     */
    function settleVault(uint256 maturity, bytes calldata settlementTrade) external {
        require(maturity <= block.timestamp, "Cannot Settle");
        VaultState memory vaultState = NOTIONAL.getVaultState(address(this), maturity);

        (
            int256 assetCashRequiredToSettle,
            int256 underlyingCashRequiredToSettle
        ) = NOTIONAL.redeemStrategyTokensToCash(maturity, vaultState.totalStrategyTokens, settlementTrade);
    }

    /**
     * @notice Converts the amount of fCash the vault holds into underlying denomination for the
     * borrow currency.
     */
    function convertStrategyToUnderlying(
        uint256 strategyTokens,
        uint256 maturity
    ) public override view returns (uint256 underlyingValue) {
        // This is the non-risk adjusted oracle price for fCash
        int256 _presentValueUnderlyingInternal = NOTIONAL.getPresentfCashValue(
            LEND_CURRENCY_ID, maturity, strategyTokens.toInt(), block.timestamp, false
        );
        require(_presentValueUnderlyingInternal > 0);
        uint256 pvInternal = uint256(_presentValueUnderlyingInternal);

        (uint256 rate, uint256 rateDecimals) = TRADING_MODULE.getOraclePrice(
            address(LEND_UNDERLYING_TOKEN), address(UNDERLYING_TOKEN)
        );
        uint256 borrowTokenDecimals = 10**UNDERLYING_TOKEN.decimals();

        // Convert this back to the borrow currency, external precision
        // (pv (8 decimals) * borrowTokenDecimals * rate) / (rateDecimals * 8 decimals)
        return (pvInternal * borrowTokenDecimals * rate) /
            (rateDecimals * uint256(Constants.INTERNAL_TOKEN_PRECISION));
    }

    /**
     * @notice Will receive a deposit from Notional in underlying tokens of the borrowed currency.
     * Needs to first trade that deposit into the lend currency and then lend it to fCash on the
     * corresponding maturity.
     */
    function _depositFromNotional(
        address /* account */,
        uint256 borrowedUnderlyingExternal,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 lendfCashMinted) {
        // We have `deposit` amount of borrowed underlying tokens. Now we execute a trade
        // to receive some amount of lending tokens
        uint256 lendUnderlyingTokens;
        // This should trade exactIn = deposit
        // TradeHandler._executeTrade(trade, deposit);

        // Now we lend the underlying amount
        (uint256 fCashAmount, /* */, bytes32 encodedTrade) = NOTIONAL.getfCashLendFromDeposit(
            LEND_CURRENCY_ID,
            lendUnderlyingTokens, // TODO: may need to buffer this down a bit
            maturity,
            0, // TODO: minLendRate,
            block.timestamp,
            true // useUnderlying is true
        );

        BatchLend[] memory action = new BatchLend[](1);
        action[0].currencyId = LEND_CURRENCY_ID;
        action[0].depositUnderlying = true;
        action[0].trades = new bytes32[](1);
        action[0].trades[0] = encodedTrade;
        NOTIONAL.batchLend(address(this), action);

        // fCash is the strategy token in this case
        return fCashAmount;
    }

    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 tokensFromRedeem) {
        uint256 balanceBefore = LEND_UNDERLYING_TOKEN.balanceOf(address(this));

        if (block.timestamp <= maturity) {
            // Only allow the vault to redeem past maturity to settle all positions
            require(account == address(this));
            NOTIONAL.settleAccount(address(this));
            (int256 cashBalance, /* */, /* */) = NOTIONAL.getAccountBalance(LEND_CURRENCY_ID, address(this));

            // It should never be possible that this contract has a negative cash balance
            require(0 <= cashBalance && cashBalance <= int256(uint256(type(uint88).max)));

            // Withdraws all cash to underlying
            NOTIONAL.withdraw(LEND_CURRENCY_ID, uint88(uint256(cashBalance)), true);
        } else {
            // Sells fCash on Notional AMM (via borrowing)
            BalanceActionWithTrades[] memory action = _encodeBorrowTrade(
                maturity,
                strategyTokens,
                0 // maxImpliedRate
            );
            NOTIONAL.batchBalanceAndTradeAction(address(this), action);
        }

        uint256 balanceAfter = LEND_UNDERLYING_TOKEN.balanceOf(address(this));
        // tokensFromRedeem = _execute0xTrade(trade, deposit);
    }

    function _encodeBorrowTrade(
        uint256 maturity,
        uint256 fCashAmount,
        uint32 maxImpliedRate
    ) private view returns (BalanceActionWithTrades[] memory action) {
        (uint256 marketIndex, bool isIdiosyncratic) = DateTime.getMarketIndex(
            Constants.MAX_TRADED_MARKET_INDEX,
            maturity,
            block.timestamp
        );
        require(!isIdiosyncratic);
        require(fCashAmount <= uint256(type(uint88).max));

        action = new BalanceActionWithTrades[](1);
        action[0].actionType = DepositActionType.None;
        action[0].currencyId = LEND_CURRENCY_ID;
        action[0].withdrawEntireCashBalance = true;
        action[0].redeemToUnderlying = true;
        action[0].trades = new bytes32[](1);
        action[0].trades[0] = bytes32(
            (uint256(uint8(TradeActionType.Borrow)) << 248) |
            (uint256(marketIndex) << 240) |
            (uint256(fCashAmount) << 152) |
            (uint256(maxImpliedRate) << 120)
        );
    }
}