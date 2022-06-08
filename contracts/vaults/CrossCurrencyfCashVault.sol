// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.8.11;
pragma abicoder v2;

import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {IWrappedfCashFactory} from "../../../interfaces/notional/IWrappedfCashFactory.sol";
import {IWrappedfCashComplete as IWrappedfCash} from "../../../interfaces/notional/IWrappedfCash.sol";
import {BaseStrategyVault} from "./BaseStrategyVault.sol";
import {BatchLend, Token, VaultState, ETHRateStorage, AggregatorV2V3Interface} from "../global/Types.sol";
import {Constants} from "../global/Constants.sol";

/**
 * @notice This vault borrows in one currency, trades it to a different currency
 * and lends on Notional in that currency. It will be paired with another vault
 * that lends and borrows in the opposite direction.
 */
contract CrossCurrencyfCashVault is BaseStrategyVault {
    uint16 public immutable LEND_CURRENCY_ID;

    uint8 borrowRateDecimalPlaces;
    bool borrowRateMustInvert;
    uint8 lendRateDecimalPlaces;
    bool lendRateMustInvert;

    AggregatorV2V3Interface borrowRateOracle;
    // --- 6 bytes here before next slot

    AggregatorV2V3Interface lendRateOracle;
    
    IWrappedfCashFactory internal immutable WRAPPED_FCASH_FACTORY;

    /// @notice Emitted when a vault is settled
    /// @param assetTokenProfits total amount of profit to vault account holders, if this is negative
    /// than there is a shortfall that must be covered by the protocol
    /// @param underlyingTokenProfits same as assetTokenProfits but denominated in underlying
    event VaultSettled(uint256 maturity, int256 assetTokenProfits, int256 underlyingTokenProfits);

    constructor(
        string memory name_,
        string memory symbol_,
        address notional_,
        IWrappedfCashFactory wrappedfCashFactory_,
        uint16 borrowCurrencyId_,
        uint16 lendCurrencyId_
    ) BaseStrategyVault(name_, symbol_, notional_, borrowCurrencyId_, true, true) {
        LEND_CURRENCY_ID = lendCurrencyId_;
        WRAPPED_FCASH_FACTORY = wrappedfCashFactory_;

        // Sets the exchange rate storage
        (ETHRateStorage memory lendRateStorage, /* */) = NOTIONAL.getRateStorage(lendCurrencyId_);
        lendRateDecimalPlaces = lendRateStorage.rateDecimalPlaces;
        lendRateMustInvert = lendRateStorage.mustInvert;
        lendRateOracle = lendRateStorage.rateOracle;

        (ETHRateStorage memory borrowRateStorage, /* */) = NOTIONAL.getRateStorage(borrowCurrencyId_);
        borrowRateDecimalPlaces = borrowRateStorage.rateDecimalPlaces;
        borrowRateMustInvert = borrowRateStorage.mustInvert;
        borrowRateOracle = borrowRateStorage.rateOracle;
    }

    function getConfigFlags() external view returns (uint16 flags) {
        // Returns the configuration flags for the vault
    }

    /**
     * @notice Returns the fCash wrapper address for the LEND_CURRENCY_ID and maturity
     */
    function getfCashWrapper(uint256 maturity) public view returns (IWrappedfCash wrapper) {
        require(maturity <= type(uint40).max);
        return IWrappedfCash(WRAPPED_FCASH_FACTORY.computeAddress(LEND_CURRENCY_ID, uint40(maturity)));
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
        // We don't want to redeem the fCash balance until we know for sure that all accounts
        // requiring settlement have been properly handled. This would mess up the accounting
        // for pooled settlement.
        require(vaultState.accountsRequiringSettlement == 0);

        // Redeem the entire fCash balance to cash into the debt currency
        uint256 fCashBalance = getfCashWrapper(maturity).balanceOf(address(this));
        (
            int256 assetCashRequiredToSettle,
            int256 underlyingCashRequiredToSettle
        ) = NOTIONAL.redeemStrategyTokensToCash(maturity, fCashBalance, settlementTrade);

        // Profits are the surplus in cash after the tokens have been settled, this is the negation of
        // what is returned from the method above
        emit VaultSettled(maturity, -1 * assetCashRequiredToSettle, -1 * underlyingCashRequiredToSettle);
    }


    /**
     * @notice Called by Notional to check if the strategy tokens have been redeemed to the borrow
     * currency so that it can proceed with settling out the vault on its side. We return true anytime
     * after maturity so that individual account settlement can proceed.
     */
    function canSettleMaturity(uint256 maturity) external override view returns (bool) {
        // TODO: are these necessary or not?
        return maturity <= block.timestamp;
    }

    /**
     * @notice Called by Notional to check if a vault can be entered or not
     */
    function isInSettlement(uint256 maturity) external override view returns (bool) {
        // TODO: are these necessary or not?
        return maturity <= block.timestamp;
    }

    function getLendToBorrowExchangeRate() public view returns (uint256 exchangeRate, uint256 exchangeRatePrecision) {
        // TODO: should this come off of the trading adapter or some other centralized oracle service?
        // TODO: we know that both currencies are on Notional so we could do the math here...
    }

    /**
     * @notice Converts the amount of fCash the vault holds into underlying denomination for the
     * borrow currency.
     */
    function convertStrategyToUnderlying(
        uint256 strategyTokens,
        uint256 maturity
    ) public override view returns (uint256 underlyingValue) {
        uint256 lendPresentValueUnderlyingExternal = getfCashWrapper(maturity).convertToAssets(strategyTokens);
        (uint256 exchangeRate, uint256 exchangeRatePrecision) = getLendToBorrowExchangeRate();
        return (lendPresentValueUnderlyingExternal * exchangeRate) / exchangeRatePrecision;
    }

    /**
     * @notice Will receive a deposit from Notional in underlying tokens of the borrowed currency.
     * Needs to first trade that deposit into the lend currency and then lend it to fCash on the
     * corresponding maturity.
     */
    function _depositFromNotional(
        uint256 borrowedUnderlyingExternal,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 lendfCashMinted) {
        // We have `deposit` amount of borrowed underlying tokens. Now we execute a trade
        // to receive some amount of lending tokens
        uint256 lendUnderlyingTokens;
        // // This should trade exactIn = deposit
        // // _execute0xTrade(trade, deposit);

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
        bytes memory batchLendCallData = abi.encodeWithSelector(NotionalProxy.batchLend.selector, address(this), action);

        uint256 fCashId = uint256(
            (bytes32(uint256(LEND_CURRENCY_ID)) << 48) |
            (bytes32(uint256(uint40(maturity))) << 8) |
            bytes32(uint256(uint8(Constants.FCASH_ASSET_TYPE)))
        );

        // This is a more efficient way to mint fCash wrapped tokens (397103 gas)
        NOTIONAL.safeTransferFrom(
            address(this),
            address(getfCashWrapper(maturity)),
            fCashId,
            fCashAmount,
            batchLendCallData
        );

        // fCash is the strategy token in this case
        return fCashAmount;
    }

    function _redeemFromNotional(
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 tokensFromRedeem) {
        uint32 maxImpliedRate; // TODO: implement
        uint256 balanceBefore = UNDERLYING_TOKEN.balanceOf(address(this));
        getfCashWrapper(maturity).redeemToUnderlying(strategyTokens, address(this), maxImpliedRate);
        uint256 balanceAfter = UNDERLYING_TOKEN.balanceOf(address(this));
        uint256 tokensRedeemed = balanceAfter - balanceBefore;

        // This will trade underlying for borrowed currency id using exact in based on
        // what we redeemed above
        // tokensFromRedeem = _execute0xTrade(trade, deposit);
    }
}