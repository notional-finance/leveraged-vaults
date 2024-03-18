// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {NotionalProxy} from "@interfaces/notional/NotionalProxy.sol";
import {IWrappedfCashFactory} from "@interfaces/notional/IWrappedfCashFactory.sol";
import {IWrappedfCashComplete as IWrappedfCash} from "@interfaces/notional/IWrappedfCash.sol";
import {WETH9} from "@interfaces/WETH9.sol";

import {BaseStrategyVault} from "@contracts/vaults/common/BaseStrategyVault.sol";
import {IERC20, TokenUtils} from "@contracts/utils/TokenUtils.sol";
import {TypeConvert} from "@contracts/global/TypeConvert.sol";
import {Token, TokenType} from "@contracts/global/Types.sol";
import {Constants} from "@contracts/global/Constants.sol";
import {ITradingModule, DexId, TradeType, Trade} from "@interfaces/trading/ITradingModule.sol";

/**
 * @notice This vault borrows in one currency, trades it to a different currency
 * and lends on Notional in that currency.
 */
contract CrossCurrencyVault is BaseStrategyVault {
    using TokenUtils for IERC20;
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
        (/* */, Token memory underlyingToken) = NOTIONAL.getCurrency(lendCurrencyId_);

        LEND_ETH = underlyingToken.tokenType == TokenType.Ether;
        IERC20 tokenAddress = IERC20(underlyingToken.tokenAddress);
        LEND_UNDERLYING_TOKEN = tokenAddress;
        LEND_DECIMALS = TokenUtils.getDecimals(address(tokenAddress));
        BORROW_DECIMALS = TokenUtils.getDecimals(address(_underlyingToken()));
    }

    /// @notice Returns the wrapped fCash address which is created using CREATE2. It may be the case that
    /// the wrapped fCash contract for a given maturity has not yet been deployed which would cause the
    /// initial deposit for a maturity to revert in this contract. However, deployment of wrapped fCash
    /// contracts is permissionless so likely some bot will be used to ensure the wrappers are deployed
    /// before they are used.
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
            // For Prime Cash the vaultShares will represent a pCash balance and we convert that
            // to underlying value via Notional.
            pvExternalUnderlying = NOTIONAL.convertCashBalanceToExternal(
                LEND_CURRENCY_ID,
                vaultShares.toInt(),
                true
            );
        } else {
            // For fCash we use the fCash wrapper to convert the fCash balance to PV. The fCash
            // wrapper uses an internal Notional TWAP oracle to get the present value, this is
            // the same TWAP oracle that is used in Notional to calculate regular portfolio
            // collateralization.
            pvExternalUnderlying = getWrappedFCashAddress(maturity).convertToAssets(vaultShares).toInt();
        }

        // Returns the oracle price between the lend and borrow tokens.
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

    /// @notice Returns the current value of 1 vault share at the given maturity, used for the
    /// user interface to collect historical values.
    function getExchangeRate(uint256 maturity) public view override returns (int256) {
        // This will revert for fCash maturities if the wrapper is not deployed but for simplicity in the
        // implementation we will accept that this is ok. This method is used for the UI and in practice the
        // historical fCash prices are accessible via other means.
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
        if (depositUnderlyingExternal == 0) return 0;

        IERC20 lendToken = LEND_UNDERLYING_TOKEN;
        DepositParams memory params = abi.decode(data, (DepositParams));
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(_underlyingToken()),
            buyToken: address(lendToken),
            amount: depositUnderlyingExternal,
            limit: params.minPurchaseAmount,
            deadline: block.timestamp,
            exchangeData: params.exchangeData
        });

        // Executes a trade on the given Dex, the vault must have permissions set for
        // each dex and token it wants to sell. Each vault will only have permissions to
        // buy and sell the lend and borrow underlying tokens via specific dexes.
        (/* */, uint256 lendUnderlyingTokens) = _executeTrade(params.dexId, trade);
        bool isETH = LEND_ETH;

        if (maturity == Constants.PRIME_CASH_VAULT_MATURITY) {
            // Lend variable
            vaultShares = _depositToPrimeCash(isETH, lendUnderlyingTokens);
        } else {
            // Lending fixed, the fCash wrapper uses WETH instead of ETH.
            IWrappedfCash wfCash = getWrappedFCashAddress(maturity);
            if (isETH) {
                WETH.deposit{value: lendUnderlyingTokens}();
                IERC20(address(WETH)).approve(address(wfCash), lendUnderlyingTokens);
            } else {
                lendToken.checkApprove(address(wfCash), lendUnderlyingTokens);
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
        if (vaultShares == 0) return 0;
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        address lendToken = address(LEND_UNDERLYING_TOKEN);
        bool isETH = LEND_ETH;

        uint256 balanceBefore = TokenUtils.tokenBalance(lendToken);
        if (maturity == Constants.PRIME_CASH_VAULT_MATURITY) {
            // It should never be possible that this contract has a negative cash balance
            require(vaultShares <= type(uint88).max);

            // Withdraws vault shares to underlying, will revert if the vault shares is
            // greater than the 
            NOTIONAL.withdraw(LEND_CURRENCY_ID, uint88(vaultShares), true);
        } else {
            _redeemfCash(isETH, maturity, vaultShares);
        }
        uint256 balanceAfter = TokenUtils.tokenBalance(lendToken);
        
        // Trade back to borrow currency for repayment
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: lendToken,
            buyToken: address(_underlyingToken()),
            amount: balanceAfter - balanceBefore,
            // minPurchaseAmount sets a slippage limit on both the fCash and the trade
            // from the lend currency back to the borrowed currency.
            limit: params.minPurchaseAmount,
            deadline: block.timestamp,
            exchangeData: params.exchangeData
        });

        (/* */, borrowedCurrencyAmount) = _executeTrade(params.dexId, trade);
    }

    /// @notice Called by Notional during settlement for an account. The account will withdraw settled fCash
    /// to underlying from the fCash wrapper and deposit back into Notional as Prime Cash. Vault shares in
    /// the prime cash maturity are 1-1 with prime cash units.
    /// @notice vaultShares the amount of fCash vault shares the account holds at maturity
    /// @notice maturity the fCash maturity that is being settled
    /// @return primeVaultShares the amount of prime cash deposited for this account
    function _convertVaultSharesToPrimeMaturity(
        address /* account */,
        uint256 vaultShares,
        uint256 maturity
    ) internal override returns (uint256 primeVaultShares) { 
        bool isETH = LEND_ETH;
        address lendToken = address(LEND_UNDERLYING_TOKEN);

        uint256 balanceBefore = TokenUtils.tokenBalance(lendToken);
        _redeemfCash(isETH, maturity, vaultShares);
        uint256 balanceAfter = TokenUtils.tokenBalance(lendToken);

        primeVaultShares = _depositToPrimeCash(isETH, balanceAfter - balanceBefore);
    }

    /// @notice Redeems fCash from the wrapper. If it is prior to maturity, the wrapper will sell the fCash
    /// on Notional. Post maturity, the fCash wrapper will return the matured balance.
    function _redeemfCash(bool isETH, uint256 maturity, uint256 vaultShares) private {
        IWrappedfCash wfCash = getWrappedFCashAddress(maturity);
        uint256 assets = wfCash.redeem(vaultShares, address(this), address(this));

        if (isETH) WETH.withdraw(assets);
    }

    /// @notice Deposits some balance of tokens onto Notional to be lent as prime cash.
    function _depositToPrimeCash(bool isETH, uint256 lendUnderlyingTokens) private returns (uint256) {
        // Lending variable
        if (!isETH) LEND_UNDERLYING_TOKEN.approve(address(NOTIONAL), lendUnderlyingTokens);
        return NOTIONAL.depositUnderlyingToken{value: isETH ? lendUnderlyingTokens : 0}(
            address(this),
            LEND_CURRENCY_ID,
            lendUnderlyingTokens
        );
    }

    /// @notice No read only re-entrancy is possible for liquidations in Notional. This is because it only
    /// uses .transfer() so there is no loss of control during ETH transfers. Also, the TWAP oracle used to
    /// value fCash does not change within a single block. Prime Cash values also cannot be manipulated via
    /// donation because Notional maintains its own internal accounting of the balance for each token.
    function _checkReentrancyContext() internal override {}
}