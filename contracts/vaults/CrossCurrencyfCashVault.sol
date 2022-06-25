// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.8.11;
pragma abicoder v2;

import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {IWrappedfCashFactory} from "../../../interfaces/notional/IWrappedfCashFactory.sol";
import {WETH9} from "../../../interfaces/WETH9.sol";
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
import {ITradingModule, DexId, TradeType, Trade} from "../../interfaces/trading/ITradingModule.sol";
import {TradeHandler} from "../trading/TradeHandler.sol";

/**
 * @notice This vault borrows in one currency, trades it to a different currency
 * and lends on Notional in that currency. It will be paired with another vault
 * that lends and borrows in the opposite direction.
 */
contract CrossCurrencyfCashVault is BaseStrategyVault {
    using SafeInt256 for uint256;

    uint16 public LEND_CURRENCY_ID;
    ERC20 public LEND_UNDERLYING_TOKEN;
    // NOTE: 10 bytes left in first storage slot here

    constructor(NotionalProxy notional_, ITradingModule tradingModule_)
        BaseStrategyVault(notional_, tradingModule_) {}

    function initialize(
        string memory name_,
        uint16 borrowCurrencyId_,
        uint16 lendCurrencyId_
    ) external initializer {
        __INIT_VAULT(name_, borrowCurrencyId_);

        LEND_CURRENCY_ID = lendCurrencyId_;
        (
            Token memory assetToken,
            Token memory underlyingToken,
            /* ETHRate memory ethRate */,
            /* AssetRateParameters memory assetRate */
        ) = NOTIONAL.getCurrencyAndRates(lendCurrencyId_);

        ERC20 tokenAddress = assetToken.tokenType == TokenType.NonMintable ?
            ERC20(assetToken.tokenAddress) : ERC20(underlyingToken.tokenAddress);
        LEND_UNDERLYING_TOKEN = tokenAddress;
    }

    /**
     * @notice During settlement all of the fCash balance in the lend currency will be redeemed to the
     * underlying token and traded back to the borrow currency. All of the borrow currency will be deposited
     * into the Notional contract as asset tokens and held for accounts to withdraw. Settlement can only
     * be called after maturity.
     * @param maturity the maturity to settle
     * @param settlementTrade details for the settlement trade...
     */
    function settleVault(uint256 maturity, bytes calldata settlementTrade) external {
        require(maturity <= block.timestamp, "Cannot Settle");
        VaultState memory vaultState = NOTIONAL.getVaultState(address(this), maturity);
        require(vaultState.totalStrategyTokens >= 0);

        (
            int256 assetCashRequiredToSettle,
            int256 underlyingCashRequiredToSettle
        ) = NOTIONAL.redeemStrategyTokensToCash(maturity, vaultState.totalStrategyTokens, settlementTrade);
    }

    /**
     * @notice Converts the amount of fCash the vault holds into underlying denomination for the
     * borrow currency.
     * @param strategyTokens each strategy token is equivalent to 1 unit of fCash
     * @param maturity the maturity of the fCash
     * @return underlyingValue the value of the lent fCash in terms of the borrowed currency
     */
    function convertStrategyToUnderlying(
        address /* account */,
        uint256 strategyTokens,
        uint256 maturity
    ) public override view returns (int256 underlyingValue) {
        // This is the non-risk adjusted oracle price for fCash
        int256 pvInternal = NOTIONAL.getPresentfCashValue(
            LEND_CURRENCY_ID, maturity, strategyTokens.toInt(), block.timestamp, false
        );

        ERC20 underlyingToken = _underlyingToken();
        (int256 rate, int256 rateDecimals) = TRADING_MODULE.getOraclePrice(
            address(LEND_UNDERLYING_TOKEN), address(underlyingToken)
        );
        int256 borrowTokenDecimals = int256(10**underlyingToken.decimals());

        // Convert this back to the borrow currency, external precision
        // (pv (8 decimals) * borrowTokenDecimals * rate) / (rateDecimals * 8 decimals)
        return (pvInternal * borrowTokenDecimals * rate) /
            (rateDecimals * int256(Constants.INTERNAL_TOKEN_PRECISION));
    }

    /**
     * @notice Will receive a deposit from Notional in underlying tokens of the borrowed currency.
     * Needs to first trade that deposit into the lend currency and then lend it to fCash on the
     * corresponding maturity.
     * @param depositUnderlyingExternal amount of tokens deposited in the borrow currency
     * @param maturity the maturity that was borrowed at, will also be the maturity that is lent to
     * @param data minPurchaseAmount, minLendRate and target dex for trading borrowed currency to lend currency
     * @return lendfCashMinted the amount of strategy tokens (fCash lent) generated
     */
    function _depositFromNotional(
        address /* account */,
        uint256 depositUnderlyingExternal,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 lendfCashMinted) {
        (uint256 minPurchaseAmount, uint32 minLendRate, uint16 dexId) = abi.decode(data, (uint256, uint32, uint16));
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(_underlyingToken()),
            buyToken: address(LEND_UNDERLYING_TOKEN),
            amount: depositUnderlyingExternal,
            limit: minPurchaseAmount,
            deadline: block.timestamp,
            exchangeData: "" // TODO, implement this
        });

        (/* */, uint256 lendUnderlyingTokens) = TradeHandler._execute(trade, TRADING_MODULE, dexId);

        // Now we lend the underlying amount
        (uint256 fCashAmount, /* */, bytes32 encodedTrade) = NOTIONAL.getfCashLendFromDeposit(
            LEND_CURRENCY_ID,
            lendUnderlyingTokens, // TODO: may need to buffer this down a bit
            maturity,
            minLendRate,
            block.timestamp,
            true // useUnderlying is true
        );

        BatchLend[] memory action = new BatchLend[](1);
        action[0].currencyId = LEND_CURRENCY_ID;
        action[0].depositUnderlying = true;
        action[0].trades = new bytes32[](1);
        action[0].trades[0] = encodedTrade;
        NOTIONAL.batchLend(address(this), action);

        // fCash is the strategy token in this case, batchLend will always mint exactly fCashAmount
        return fCashAmount;
    }

    /**
     * @notice Withdraws lent fCash from Notional (by selling it prior to maturity or withdrawing post maturity),
     * and trades it all back to the borrowed currency.
     * @param account the account that is doing the redemption
     * @param strategyTokens the amount of fCash to redeem
     * @param maturity the maturity of the fCash
     * @param data calldata that sets trading limits
     */
    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 borrowedCurrencyAmount) {
        uint256 balanceBefore = LEND_UNDERLYING_TOKEN.balanceOf(address(this));
        (uint256 minPurchaseAmount, uint32 maxBorrowRate, uint16 dexId) = abi.decode(data, (uint256, uint32, uint16));

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
                maxBorrowRate
            );
            NOTIONAL.batchBalanceAndTradeAction(address(this), action);
        }

        uint256 balanceAfter = LEND_UNDERLYING_TOKEN.balanceOf(address(this));
        
        // Trade out
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(LEND_UNDERLYING_TOKEN),
            buyToken: address(_underlyingToken()),
            amount: balanceAfter - balanceBefore,
            limit: minPurchaseAmount,
            deadline: block.timestamp,
            exchangeData: "" // TODO, implement this
        });

        (/* */, borrowedCurrencyAmount) = TradeHandler._execute(trade, TRADING_MODULE, dexId);
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