// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "../../proxy/AccessControlUpgradeable.sol";

import {Token, TokenType} from "@contracts/global/Types.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {Constants} from "@contracts/global/Constants.sol";
import {IStrategyVault} from "@interfaces/notional/IStrategyVault.sol";
import {NotionalProxy} from "@interfaces/notional/NotionalProxy.sol";
import {ITradingModule, Trade} from "@interfaces/trading/ITradingModule.sol";
import {IERC20} from "@interfaces/IERC20.sol";
import {TokenUtils} from "@contracts/utils/TokenUtils.sol";
import {TradeHandler} from "../../trading/TradeHandler.sol";
import {nProxy} from "../../proxy/nProxy.sol";

abstract contract BaseStrategyVault is Initializable, IStrategyVault, AccessControlUpgradeable {
    using TokenUtils for IERC20;
    using TradeHandler for Trade;

    bytes32 internal constant EMERGENCY_EXIT_ROLE = keccak256("EMERGENCY_EXIT_ROLE");
    bytes32 internal constant REWARD_REINVESTMENT_ROLE = keccak256("REWARD_REINVESTMENT_ROLE");
    bytes32 internal constant STATIC_SLIPPAGE_TRADING_ROLE = keccak256("STATIC_SLIPPAGE_TRADING_ROLE");

    /// @notice Hardcoded on the implementation contract during deployment
    NotionalProxy internal immutable NOTIONAL;
    ITradingModule internal immutable TRADING_MODULE;
    uint8 constant internal INTERNAL_TOKEN_DECIMALS = 8;

    // Borrowing Currency ID the vault is configured with
    uint16 private _BORROW_CURRENCY_ID;
    // True if the underlying is ETH
    bool private _UNDERLYING_IS_ETH;
    // Address of the underlying token
    IERC20 private _UNDERLYING_TOKEN;
    // NOTE: end of first storage slot here

    // Name of the vault
    string private _NAME;


    /**************************************************************************/
    /* Global Modifiers, Constructor and Initializer                          */
    /**************************************************************************/
    modifier onlyNotional() {
        require(msg.sender == address(NOTIONAL), "Unauthorized");
        _;
    }

    modifier onlyNotionalOwner() {
        require(msg.sender == address(NOTIONAL.owner()), "Unauthorized");
        _;
    }
    
    /// @notice Set the NOTIONAL address on deployment
    constructor(NotionalProxy notional_, ITradingModule tradingModule_) initializer {
        // Make sure we are using the correct Deployments lib
        require(Deployments.CHAIN_ID == block.chainid);

        NOTIONAL = notional_;
        TRADING_MODULE = tradingModule_;
    }

    /// @notice Override this method and revert if the contract should not receive ETH.
    /// Upgradeable proxies must have this implemented on the proxy for transfer calls
    /// succeed (use nProxy for this).
    receive() external virtual payable {
        // Allow ETH transfers to succeed
    }

    /// @notice All strategy vaults MUST implement 8 decimal precision
    function decimals() public override pure returns (uint8) {
        return INTERNAL_TOKEN_DECIMALS;
    }

    function name() external override view returns (string memory) {
        return _NAME;
    }

    function strategy() external virtual view returns (bytes4);

    function _borrowCurrencyId() internal view returns (uint16) {
        return _BORROW_CURRENCY_ID;
    }

    function _underlyingToken() internal view returns (IERC20) {
        return _UNDERLYING_TOKEN;
    }

    function _isUnderlyingETH() internal view returns (bool) {
        return _UNDERLYING_IS_ETH;
    }

    /// @notice Can only be called once during initialization
    function __INIT_VAULT(
        string memory name_,
        uint16 borrowCurrencyId_
    ) internal onlyInitializing {
        _NAME = name_;
        _BORROW_CURRENCY_ID = borrowCurrencyId_;

        address underlyingAddress = _getNotionalUnderlyingToken(borrowCurrencyId_);
        _UNDERLYING_TOKEN = IERC20(underlyingAddress);
        _UNDERLYING_IS_ETH = underlyingAddress == address(0);
        _setupRole(DEFAULT_ADMIN_ROLE, NOTIONAL.owner());
    }

    function _getNotionalUnderlyingToken(uint16 currencyId) internal view returns (address) {
        (/* */, Token memory underlyingToken) = NOTIONAL.getCurrency(currencyId);
        return underlyingToken.tokenAddress;
    }

    /// @notice Can be used to delegate call to the TradingModule's implementation in order to execute
    /// a trade.
    function _executeTrade(
        uint16 dexId,
        Trade memory trade
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        return trade._executeTrade(dexId);
    }

    /**************************************************************************/
    /* Virtual Methods Requiring Implementation                               */
    /**************************************************************************/
    function convertStrategyToUnderlying(
        address account,
        uint256 vaultShares,
        uint256 maturity
    ) public view virtual returns (int256 underlyingValue);

    function getExchangeRate(uint256 maturity) external virtual view returns (int256);
    
    // Vaults need to implement these two methods
    function _depositFromNotional(
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal virtual returns (uint256 vaultSharesMinted);

    function _redeemFromNotional(
        address account,
        uint256 vaultShares,
        uint256 maturity,
        bytes calldata data
    ) internal virtual returns (uint256 tokensFromRedeem);

    function _convertVaultSharesToPrimeMaturity(
        address /* account */,
        uint256 /* vaultShares */,
        uint256 /* maturity */
    ) internal virtual returns (uint256 /* primeVaultShares */) {
        revert();
    }

    function _checkReentrancyContext() internal virtual;

    /**************************************************************************/
    /* Default External Method Implementations                                */
    /**************************************************************************/
    function depositFromNotional(
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) external payable onlyNotional returns (uint256 vaultSharesMinted) {
        return _depositFromNotional(account, deposit, maturity, data);
    }

    function redeemFromNotional(
        address account,
        address receiver,
        uint256 vaultShares,
        uint256 maturity,
        uint256 underlyingToRepayDebt,
        bytes calldata data
    ) external onlyNotional returns (uint256 transferToReceiver) {
        uint256 borrowedCurrencyAmount = _redeemFromNotional(account, vaultShares, maturity, data);

        uint256 transferToNotional;
        if (account == address(this) || borrowedCurrencyAmount <= underlyingToRepayDebt) {
            // It may be the case that insufficient tokens were redeemed to repay the debt. If this
            // happens the Notional will attempt to recover the shortfall from the account directly.
            // This can happen if an account wants to reduce their leverage by paying off debt but
            // does not want to sell strategy tokens to do so.
            // The other situation would be that the vault is calling redemption to deleverage or
            // settle. In that case all tokens go back to Notional.
            transferToNotional = borrowedCurrencyAmount;
        } else {
            transferToNotional = underlyingToRepayDebt;
            unchecked { transferToReceiver = borrowedCurrencyAmount - underlyingToRepayDebt; }
        }

        if (_UNDERLYING_IS_ETH) {
            if (transferToReceiver > 0) payable(receiver).transfer(transferToReceiver);
            if (transferToNotional > 0) payable(address(NOTIONAL)).transfer(transferToNotional);
        } else {
            if (transferToReceiver > 0) _UNDERLYING_TOKEN.checkTransfer(receiver, transferToReceiver);
            if (transferToNotional > 0) _UNDERLYING_TOKEN.checkTransfer(address(NOTIONAL), transferToNotional);
        }
    }

    function convertVaultSharesToPrimeMaturity(
        address account,
        uint256 vaultShares,
        uint256 maturity
    ) external onlyNotional returns (uint256 primeVaultShares) { 
        require(maturity != Constants.PRIME_CASH_VAULT_MATURITY);
        return _convertVaultSharesToPrimeMaturity(account, vaultShares, maturity);
    }

    function deleverageAccount(
        address account,
        address vault,
        address liquidator,
        uint16 currencyIndex,
        int256 depositUnderlyingInternal
    ) external payable virtual returns (uint256 vaultSharesFromLiquidation, int256 depositAmountPrimeCash) {
        require(msg.sender == liquidator);
        _checkReentrancyContext();
        return NOTIONAL.deleverageAccount{value: msg.value}(
            account, vault, liquidator, currencyIndex, depositUnderlyingInternal
        );
    }

    function liquidateVaultCashBalance(
        address account,
        address vault,
        address liquidator,
        uint256 currencyIndex,
        int256 fCashDeposit
    ) external returns (int256 cashToLiquidator) {
        require(msg.sender == liquidator);
        return NOTIONAL.liquidateVaultCashBalance(
            account, vault, liquidator, currencyIndex, fCashDeposit
        );
    }

    function _canUseStaticSlippage() internal view returns (bool) {
        return hasRole(STATIC_SLIPPAGE_TRADING_ROLE, msg.sender);
    }

    // Storage gap for future potential upgrades
    uint256[45] private __gap;
}