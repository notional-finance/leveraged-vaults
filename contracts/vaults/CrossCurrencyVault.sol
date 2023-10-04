// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {IWrappedfCashFactory} from "../../interfaces/notional/IWrappedfCashFactory.sol";
import {IWrappedfCashComplete as IWrappedfCash} from "../../interfaces/notional/IWrappedfCash.sol";
import {ICrossCurrencyVault} from "../../interfaces/notional/IStrategyVault.sol";
import {WETH9} from "../../interfaces/WETH9.sol";

import {BaseStrategyVault} from "./BaseStrategyVault.sol";
import {IERC20} from "../utils/TokenUtils.sol";
import {TypeConvert} from "../global/TypeConvert.sol";
import {Token, TokenType} from "../global/Types.sol";
import {Constants} from "../global/Constants.sol";
import {ITradingModule, DexId, TradeType, Trade} from "../../interfaces/trading/ITradingModule.sol";

/**
 * @notice This vault borrows in one currency, trades it to a different currency
 * and lends on Notional in that currency. It will be paired with another vault
 * that lends and borrows in the opposite direction.
 */
contract CrossCurrencyVault is BaseStrategyVault, ICrossCurrencyVault {
    using TypeConvert for uint256;

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
    WETH9 immutable WETH;

    uint16 public LEND_CURRENCY_ID;
    IERC20 public LEND_UNDERLYING_TOKEN;
    uint8 public LEND_DECIMALS;
    uint8 public BORROW_DECIMALS;
    bool public LEND_ETH;
    // NOTE: 1 byte left in first storage slot here

    constructor(
        NotionalProxy notional_,
        ITradingModule tradingModule_,
        IWrappedfCashFactory factory,
        WETH9 weth
    ) BaseStrategyVault(notional_, tradingModule_) {
        WRAPPED_FCASH_FACTORY = factory;
        WETH = weth;
    }

    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("CrossCurrencyVault"));
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

        LEND_ETH = underlyingToken.tokenType == TokenType.Ether;
        IERC20 tokenAddress = IERC20(underlyingToken.tokenAddress);
        LEND_UNDERLYING_TOKEN = tokenAddress;
        LEND_DECIMALS = LEND_ETH ? 18 : tokenAddress.decimals();
        BORROW_DECIMALS = _isUnderlyingETH() ? 18 : _underlyingToken().decimals();
    }

    function getWrappedFCashAddress(uint256 maturity) public view returns (IWrappedfCash) {
        require(maturity < Constants.PRIME_CASH_VAULT_MATURITY);
        return IWrappedfCash(WRAPPED_FCASH_FACTORY.computeAddress(LEND_CURRENCY_ID, uint40(maturity)));
    }

    /**
     * @notice Converts the amount of fCash the vault holds into underlying denomination for the
     * borrow currency.
     * @param vaultShares each strategy token is equivalent to 1 unit of fCash or 1 unit of PrimeCash
     * @param maturity the maturity of the fCash
     * @return underlyingValue the value of the lent fCash in terms of the borrowed currency
     */
    function convertStrategyToUnderlying(
        address /* account */,
        uint256 vaultShares,
        uint256 maturity
    ) public override view returns (int256 underlyingValue) {
        int256 pvExternalUnderlying;
        if (maturity == Constants.PRIME_CASH_VAULT_MATURITY) {
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
        bool isETH = LEND_ETH;
        
        if (maturity == Constants.PRIME_CASH_VAULT_MATURITY) {
            // Lend variable
            vaultShares = _depositToPrimeCash(isETH, lendUnderlyingTokens);
        } else {
            // Lending fixed
            IWrappedfCash wfCash = getWrappedFCashAddress(maturity);
            if (isETH) {
                WETH.deposit{value: lendUnderlyingTokens}();
                IERC20(address(WETH)).approve(address(wfCash), lendUnderlyingTokens);
            } else {
                LEND_UNDERLYING_TOKEN.approve(address(wfCash), lendUnderlyingTokens);
            }
            vaultShares = wfCash.deposit(lendUnderlyingTokens, address(this));
        }

        // Slippage check against lending
        require(params.minVaultShares <= vaultShares, "Slippage: Vault Shares");
    }

    /**
     * @notice Withdraws lent fCash from Notional (by selling it prior to maturity or withdrawing post maturity),
     * and trades it all back to the borrowed currency.
     * @param vaultShares the amount of fCash to redeem
     * @param maturity the maturity of the fCash
     * @param data RedeemParams
     * @return borrowedCurrencyAmount the amount of borrowed currency raised by the redemption
     */
    function _redeemFromNotional(
        address /* account */,
        uint256 vaultShares,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 borrowedCurrencyAmount) {
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        bool isETH = LEND_ETH;
        uint256 balanceBefore = _lendUnderlyingBalance(isETH);

        if (maturity == Constants.PRIME_CASH_VAULT_MATURITY) {
            // It should never be possible that this contract has a negative cash balance
            require(vaultShares <= type(uint88).max);

            // Withdraws vault shares to underlying
            NOTIONAL.withdraw(LEND_CURRENCY_ID, uint88(vaultShares), true);
        } else {
            _redeemfCash(isETH, maturity, vaultShares);
        }

        uint256 balanceAfter = _lendUnderlyingBalance(isETH);
        
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
        address /* account */,
        uint256 vaultShares,
        uint256 maturity
    ) external override returns (uint256 primeVaultShares) { 
        require(maturity != Constants.PRIME_CASH_VAULT_MATURITY);
        bool isETH = LEND_ETH;
        uint256 balanceBefore = _lendUnderlyingBalance(isETH);
        _redeemfCash(isETH, maturity, vaultShares);
        uint256 balanceAfter = _lendUnderlyingBalance(isETH);
        primeVaultShares = _depositToPrimeCash(isETH, balanceAfter - balanceBefore);
    }

    function _lendUnderlyingBalance(bool isETH) private view returns (uint256) {
        return isETH ? address(this).balance : LEND_UNDERLYING_TOKEN.balanceOf(address(this));
    }

    function _redeemfCash(bool isETH, uint256 maturity, uint256 vaultShares) private {
        IWrappedfCash wfCash = getWrappedFCashAddress(maturity);
        uint256 assets = wfCash.redeem(vaultShares, address(this), address(this));

        if (isETH) WETH.withdraw(assets);
    }

    function _depositToPrimeCash(bool isETH, uint256 lendUnderlyingTokens) private returns (uint256) {
        // Lending variable
        if (!isETH) LEND_UNDERLYING_TOKEN.approve(address(NOTIONAL), lendUnderlyingTokens);
        return NOTIONAL.depositUnderlyingToken{value: isETH ? lendUnderlyingTokens : 0}(
            address(this),
            LEND_CURRENCY_ID,
            lendUnderlyingTokens
        );
    }

    function _checkReentrancyContext() internal override {}
}