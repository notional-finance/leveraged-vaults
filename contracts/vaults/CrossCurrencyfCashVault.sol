// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {IWrappedfCashFactory} from "../../interfaces/notional/IWrappedfCashFactory.sol";
import {WETH9} from "../../interfaces/WETH9.sol";
import {IWrappedfCashComplete as IWrappedfCash} from "../../interfaces/notional/IWrappedfCash.sol";
import {BaseStrategyVault} from "./BaseStrategyVault.sol";
import {IERC20} from "../utils/TokenUtils.sol";
import {
    AccountContext,
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
import {TypeConvert} from "../global/TypeConvert.sol";
import {ITradingModule, DexId, TradeType, Trade} from "../../interfaces/trading/ITradingModule.sol";
import {TradeHandler} from "../trading/TradeHandler.sol";

/**
 * @notice This vault borrows in one currency, trades it to a different currency
 * and lends on Notional in that currency. It will be paired with another vault
 * that lends and borrows in the opposite direction.
 */
contract CrossCurrencyfCashVault is BaseStrategyVault {
    using TypeConvert for uint256;
    using TypeConvert for int256;

    uint256 public constant SETTLEMENT_SLIPPAGE_PRECISION = 1e18;

    struct DepositParams {
        // Minimum purchase amount of the lend underlying token, this is
        // based on the deposit + borrowed amount and must be set to a non-zero
        // value to establish a slippage limit.
        uint256 minPurchaseAmount;
        // Minimum annualized lending rate, can be set to zero for no slippage limit
        uint32 minLendRate;
        // ID of the desired DEX to trade on, _depositFromNotional will always trade
        // using an EXACT_IN_SINGLE trade which is supported by all DEXes
        uint16 dexId;
        // Exchange data depending on the selected dexId
        bytes exchangeData;
    }

    struct RedeemParams {
        // Minimum purchase amount of the borrow underlying token, this is
        // based on the amount of lend underlying received and must be set to a non-zero
        // value to establish a slippage limit.
        uint256 minPurchaseAmount;
        // Maximum annualized borrow rate, can be set to zero for no slippage limit
        uint32 maxBorrowRate;
        // ID of the desired DEX to trade on, _depositFromNotional will always trade
        // using an EXACT_IN_SINGLE trade which is supported by all DEXes
        uint16 dexId;
        // Exchange data depending on the selected dexId
        bytes exchangeData;
    }

    uint16 public LEND_CURRENCY_ID;
    IERC20 public LEND_UNDERLYING_TOKEN;
    /// @notice a maximum slippage limit in 1e18 precision, uint64 is sufficient to hold the maximum value which
    /// is 1e18
    uint64 public settlementSlippageLimit;
    // NOTE: 2 bytes left in first storage slot here

    constructor(NotionalProxy notional_, ITradingModule tradingModule_)
        BaseStrategyVault(notional_, tradingModule_) {}

    function strategy() external override view returns (bytes4) {
        return bytes4(keccak256("CrossCurrencyfCash"));
    }
    function initialize(
        string memory name_,
        uint16 borrowCurrencyId_,
        uint16 lendCurrencyId_,
        uint64 settlementSlippageLimit_
    ) external initializer {
        __INIT_VAULT(name_, borrowCurrencyId_);

        LEND_CURRENCY_ID = lendCurrencyId_;
        (
            Token memory assetToken,
            Token memory underlyingToken,
            /* ETHRate memory ethRate */,
            /* AssetRateParameters memory assetRate */
        ) = NOTIONAL.getCurrencyAndRates(lendCurrencyId_);

        IERC20 tokenAddress = assetToken.tokenType == TokenType.NonMintable ?
            IERC20(assetToken.tokenAddress) : IERC20(underlyingToken.tokenAddress);
        LEND_UNDERLYING_TOKEN = tokenAddress;

        // Allow Notional to pull the lend underlying currency
        tokenAddress.approve(address(NOTIONAL), type(uint256).max);

        // This value cannot be greater than 1e18
        require(settlementSlippageLimit_ < SETTLEMENT_SLIPPAGE_PRECISION);
        settlementSlippageLimit = settlementSlippageLimit_;
    }

    function updateSettlementSlippageLimit(uint64 newSlippageLimit) external {
        require(msg.sender == NOTIONAL.owner());
        require(newSlippageLimit < SETTLEMENT_SLIPPAGE_PRECISION);
        settlementSlippageLimit = newSlippageLimit;
    }

    /**
     * @notice During settlement all of the fCash balance in the lend currency will be redeemed to the
     * underlying token and traded back to the borrow currency. All of the borrow currency will be deposited
     * into the Notional contract as asset tokens and held for accounts to withdraw. Settlement can only
     * be called after maturity.
     * @param maturity the maturity to settle
     * @param settlementTrade details for the settlement trade
     */
    function settleVault(uint256 maturity, uint256 strategyTokens, bytes calldata settlementTrade) external {
        require(maturity <= block.timestamp, "Cannot Settle");
        VaultState memory vaultState = NOTIONAL.getVaultState(address(this), maturity);
        require(vaultState.isSettled == false);
        require(vaultState.totalStrategyTokens >= strategyTokens);

        RedeemParams memory params = abi.decode(settlementTrade, (RedeemParams));
    
        // The only way for underlying value to be negative would be if the vault has somehow ended up with a borrowing
        // position in the lend underlying currency. This is explicitly prevented during redemption.
        uint256 underlyingValue = convertStrategyToUnderlying(
            address(0), vaultState.totalStrategyTokens, maturity
        ).toUint();

        // Authenticate the minimum purchase amount, all tokens will be sold given this slippage limit.
        uint256 minAllowedPurchaseAmount = (underlyingValue * settlementSlippageLimit) / SETTLEMENT_SLIPPAGE_PRECISION;
        require(params.minPurchaseAmount >= minAllowedPurchaseAmount, "Purchase Limit");

        NOTIONAL.redeemStrategyTokensToCash(maturity, strategyTokens, settlementTrade);

        // If there are no more strategy tokens left, then mark the vault as settled
        vaultState = NOTIONAL.getVaultState(address(this), maturity);
        if (vaultState.totalStrategyTokens == 0) {
            NOTIONAL.settleVault(address(this), maturity);
        }
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
        int256 pvInternal;
        if (maturity <= block.timestamp) {
            // After maturity, strategy tokens no longer have a present value
            pvInternal = strategyTokens.toInt();
        } else {
            // This is the non-risk adjusted oracle price for fCash, present value is used in case
            // liquidation is required. The liquidator may need to exit the fCash position in order
            // to repay a flash loan.
            pvInternal = NOTIONAL.getPresentfCashValue(
                LEND_CURRENCY_ID, maturity, strategyTokens.toInt(), block.timestamp, false
            );
        }

        IERC20 underlyingToken = _underlyingToken();
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
     * @param data DepositParams
     * @return lendfCashMinted the amount of strategy tokens (fCash lent) generated
     */
    function _depositFromNotional(
        address /* account */,
        uint256 depositUnderlyingExternal,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 lendfCashMinted) {
        DepositParams memory params = abi.decode(data, (DepositParams));
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(_underlyingToken()),
            buyToken: address(LEND_UNDERLYING_TOKEN),
            amount: depositUnderlyingExternal,
            limit: params.minPurchaseAmount,
            deadline: block.timestamp,
            exchangeData: params.exchangeData
        });

        (/* */, uint256 lendUnderlyingTokens) = _executeTrade(params.dexId, trade);

        // Now we lend the underlying amount
        (uint256 fCashAmount, /* */, bytes32 encodedTrade) = NOTIONAL.getfCashLendFromDeposit(
            LEND_CURRENCY_ID,
            lendUnderlyingTokens,
            maturity,
            params.minLendRate,
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
     * @param data RedeemParams
     * @return borrowedCurrencyAmount the amount of borrowed currency raised by the redemption
     */
    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 borrowedCurrencyAmount) {
        uint256 balanceBefore = LEND_UNDERLYING_TOKEN.balanceOf(address(this));
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        if (maturity <= block.timestamp) {
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
                params.maxBorrowRate
            );
            NOTIONAL.batchBalanceAndTradeAction(address(this), action);

            // Check that we have not somehow borrowed into a negative fCash position, vault borrows
            // are not included in account context
            AccountContext memory accountContext = NOTIONAL.getAccountContext(address(this));
            require(accountContext.hasDebt == 0x00);
        }

        uint256 balanceAfter = LEND_UNDERLYING_TOKEN.balanceOf(address(this));
        
        // Trade back to borrow currency for repayment
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(LEND_UNDERLYING_TOKEN),
            buyToken: address(_underlyingToken()),
            amount: balanceAfter - balanceBefore,
            limit: params.minPurchaseAmount,
            deadline: block.timestamp,
            exchangeData: params.exchangeData
        });

        (/* */, borrowedCurrencyAmount) = _executeTrade(params.dexId, trade);
    }

    function _checkReentrancyContext() internal override {} 

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