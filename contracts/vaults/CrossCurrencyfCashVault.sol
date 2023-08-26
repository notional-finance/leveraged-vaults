// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {IWrappedfCashFactory} from "../../interfaces/notional/IWrappedfCashFactory.sol";
import {IWrappedfCashComplete as IWrappedfCash} from "../../interfaces/notional/IWrappedfCash.sol";
import {ICrossCurrencyfCashStrategyVault} from "../../interfaces/notional/IStrategyVault.sol";
import {BaseStrategyVault} from "./BaseStrategyVault.sol";
import {IERC20} from "../utils/TokenUtils.sol";
import {Token} from "../global/Types.sol";
import {Constants} from "../global/Constants.sol";
import {TypeConvert} from "../global/TypeConvert.sol";
import {ITradingModule, DexId, TradeType, Trade} from "../../interfaces/trading/ITradingModule.sol";

/**
 * @notice This vault borrows in one currency, trades it to a different currency
 * and lends on Notional in that currency. It will be paired with another vault
 * that lends and borrows in the opposite direction.
 */
contract CrossCurrencyfCashVault is BaseStrategyVault, ICrossCurrencyfCashStrategyVault {
    using TypeConvert for uint256;
    using TypeConvert for int256;

    uint256 internal constant PRIME_CASH_VAULT_MATURITY = type(uint40).max;

    struct DepositParams {
        // Minimum purchase amount of the lend underlying token, this is
        // based on the deposit + borrowed amount and must be set to a non-zero
        // value to establish a slippage limit.
        uint256 minPurchaseAmount;
        // Minimum final vault shares to receive
        uint256 minVaultShares;
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
        // ID of the desired DEX to trade on, _depositFromNotional will always trade
        // using an EXACT_IN_SINGLE trade which is supported by all DEXes
        uint16 dexId;
        // Exchange data depending on the selected dexId
        bytes exchangeData;
    }

    IWrappedfCashFactory immutable WRAPPED_FCASH_FACTORY;
    uint16 public LEND_CURRENCY_ID;
    IERC20 public LEND_UNDERLYING_TOKEN;
    uint8 public LEND_DECIMALS;
    uint8 public BORROW_DECIMALS;
    // NOTE: 2 bytes left in first storage slot here

    constructor(
        NotionalProxy notional_,
        ITradingModule tradingModule_,
        IWrappedfCashFactory factory
    ) BaseStrategyVault(notional_, tradingModule_) {
        WRAPPED_FCASH_FACTORY = factory;
    }

    function strategy() external override view returns (bytes4) {
        return bytes4(keccak256("CrossCurrencyfCash"));
    }

    function initialize(
        string memory name_,
        uint16 borrowCurrencyId_,
        uint16 lendCurrencyId_
    ) external initializer {
        __INIT_VAULT(name_, borrowCurrencyId_);

        LEND_CURRENCY_ID = lendCurrencyId_;
        (
            /* Token memory assetToken */,
            Token memory underlyingToken
        ) = NOTIONAL.getCurrency(lendCurrencyId_);

        IERC20 tokenAddress = IERC20(underlyingToken.tokenAddress);
        LEND_UNDERLYING_TOKEN = tokenAddress;
        LEND_DECIMALS = tokenAddress.decimals();
        BORROW_DECIMALS = _underlyingToken().decimals();
    }

    function getWrappedFCashAddress(uint256 maturity) public view returns (IWrappedfCash wfCash) {
        // NOTE: this will revert if the wrapper is not deployed...
        require(maturity < PRIME_CASH_VAULT_MATURITY);
        wfCash = IWrappedfCash(WRAPPED_FCASH_FACTORY.computeAddress(LEND_CURRENCY_ID, uint40(maturity)));
    }

    /**
     * @notice Converts the amount of fCash the vault holds into underlying denomination for the
     * borrow currency.
     * @param vaultShares each strategy token is equivalent to 1 unit of fCash
     * @param maturity the maturity of the fCash
     * @return underlyingValue the value of the lent fCash in terms of the borrowed currency
     */
    function convertStrategyToUnderlying(
        address /* account */,
        uint256 vaultShares,
        uint256 maturity
    ) public override view returns (int256 underlyingValue) {
        int256 pvExternalUnderlying;
        if (maturity == PRIME_CASH_VAULT_MATURITY) {
            pvExternalUnderlying = NOTIONAL.convertCashBalanceToExternal(
                LEND_CURRENCY_ID,
                vaultShares.toInt(),
                true
            );
        } else {
            pvExternalUnderlying = getWrappedFCashAddress(maturity).convertToAssets(vaultShares).toInt();
        }

        IERC20 underlyingToken = _underlyingToken();
        (int256 rate, int256 rateDecimals) = TRADING_MODULE.getOraclePrice(
            address(LEND_UNDERLYING_TOKEN), address(underlyingToken)
        );
        int256 borrowPrecision = int256(10**BORROW_DECIMALS);
        int256 lendPrecision = int256(10**LEND_DECIMALS);

        // Convert this back to the borrow currency, external precision
        // (pv (lend decimals) * borrowDecimals * rate) / (rateDecimals * lendDecimals)
        return (pvExternalUnderlying * borrowPrecision * rate) /
            (rateDecimals * lendPrecision);
    }

    function getExchangeRate(uint256 maturity) public view override returns (int256) {
        return convertStrategyToUnderlying(address(0), uint256(Constants.INTERNAL_TOKEN_PRECISION), maturity);
    }

    /**
     * @notice Will receive a deposit from Notional in underlying tokens of the borrowed currency.
     * Needs to first trade that deposit into the lend currency and then lend it to fCash on the
     * corresponding maturity.
     * @param depositUnderlyingExternal amount of tokens deposited in the borrow currency
     * @param maturity the maturity that was borrowed at, will also be the maturity that is lent to
     * @param data DepositParams
     * @return vaultShares the amount of strategy tokens (fCash lent) generated
     */
    function _depositFromNotional(
        address /* account */,
        uint256 depositUnderlyingExternal,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 vaultShares) {
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
        
        if (maturity == PRIME_CASH_VAULT_MATURITY) {
            // Lending fixed
            IWrappedfCash wfCash = getWrappedFCashAddress(maturity);
            LEND_UNDERLYING_TOKEN.approve(address(wfCash), lendUnderlyingTokens);
            vaultShares = wfCash.deposit(lendUnderlyingTokens, address(this));
        } else {
            // Lending variable
            LEND_UNDERLYING_TOKEN.approve(address(NOTIONAL), lendUnderlyingTokens);
            vaultShares = NOTIONAL.depositUnderlyingToken(
                address(this),
                LEND_CURRENCY_ID,
                lendUnderlyingTokens
            );
        }

        // Slippage check against lending
        require(params.minVaultShares <= vaultShares);
    }

    /**
     * @notice Withdraws lent fCash from Notional (by selling it prior to maturity or withdrawing post maturity),
     * and trades it all back to the borrowed currency.
     * @param account the account that is doing the redemption
     * @param vaultShares the amount of fCash to redeem
     * @param maturity the maturity of the fCash
     * @param data RedeemParams
     * @return borrowedCurrencyAmount the amount of borrowed currency raised by the redemption
     */
    function _redeemFromNotional(
        address account,
        uint256 vaultShares,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 borrowedCurrencyAmount) {
        uint256 balanceBefore = LEND_UNDERLYING_TOKEN.balanceOf(address(this));
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        if (maturity == PRIME_CASH_VAULT_MATURITY) {
            // It should never be possible that this contract has a negative cash balance
            require(vaultShares <= type(uint88).max);

            // Withdraws vault shares to underlying
            NOTIONAL.withdraw(LEND_CURRENCY_ID, uint88(vaultShares), true);
        } else {
            IWrappedfCash wfCash = getWrappedFCashAddress(maturity);
            wfCash.redeem(vaultShares, address(this), address(this));
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

    function convertVaultSharesToPrimeMaturity(
        address account,
        uint256 vaultShares,
        uint256 maturity
    ) external override returns (uint256 primeStrategyTokens) { 
        require(maturity != PRIME_CASH_VAULT_MATURITY);
        uint256 balanceBefore = LEND_UNDERLYING_TOKEN.balanceOf(address(this));

        IWrappedfCash wfCash = getWrappedFCashAddress(maturity);
        wfCash.redeem(vaultShares, address(this), address(this));

        uint256 balanceAfter = LEND_UNDERLYING_TOKEN.balanceOf(address(this));

        uint256 amount = balanceAfter - balanceBefore;
        LEND_UNDERLYING_TOKEN.approve(address(NOTIONAL), amount);
        primeStrategyTokens = NOTIONAL.depositUnderlyingToken(address(this), LEND_CURRENCY_ID, amount);
    }

    function _checkReentrancyContext() internal override {} 
}