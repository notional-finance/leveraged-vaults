// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.8.11;
pragma abicoder v2;

import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {IWrappedfCashFactory} from "../../../interfaces/notional/IWrappedfCashFactory.sol";
import {IWrappedfCash} from "../../../interfaces/notional/IWrappedfCash.sol";
import {BaseStrategyVault} from "./BaseStrategyVault.sol";
import {Token} from "../global/Types.sol";

/**
 * @notice This vault borrows in one currency, trades it to a different currency
 * and lends on Notional in that currency. It will be paired with another vault
 * that lends and borrows in the opposite direction.
 */
contract CrossCurrencyfCashVault is BaseStrategyVault {

    uint16 internal immutable LEND_CURRENCY_ID;
    IWrappedfCashFactory internal immutable WRAPPED_FCASH_FACTORY;

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
        // (Token memory assetToken, Token memory underlyingToken) = _setAssetTokenApprovals(
        //     lendCurrencyId_,
        //     true,
        //     NotionalProxy(notional_)
        // );
    }

    /**
     * @notice Returns the fCash wrapper address for the LEND_CURRENCY_ID and maturity
     */
    function getfCashWrapperAddress(uint40 maturity) public view returns (IWrappedfCash wrapper) {
        return IWrappedfCash(WRAPPED_FCASH_FACTORY.computeAddress(LEND_CURRENCY_ID, maturity));
    }

    /**
     * @notice During settlement all of the fCash balance in the lend currency will be redeemed to the
     * underlying token and traded back to the borrow currency. All of the borrow currency will be deposited
     * into the Notional contract as asset tokens and held for accounts to withdraw. Settlement can only
     * be called after maturity.
     */
    function settleVault(uint256 maturity, bytes calldata settlementTrade) external view returns (bool) {
        // Redeem the entire fCash balance to cash into the debt currency
        // uint256 fCashBalance = IWrappedfCash(maturity).balanceOf(address(this));
        // NotionalV2.redeemStrategyTokensToCash(maturity, fCashBalance, settlementTrade);
    }

    function canSettleMaturity(uint256 maturity) external override view returns (bool) {
        // We can settle once all of the wrapped fcash is redeemed
        // return IWrappedfCash(maturity).balanceOf(address(this)) == 0;
    }

    function convertStrategyToUnderlying(uint256 strategyTokens) public override view returns (uint256 underlyingValue) {
        // Use the fCash wrapper here
        // return IfCashWrapper.convertToAssets(strategyTokens);
    }

    function isInSettlement() external override view returns (bool) {
        // Settlement occurs when the fCash is matured up until the point where
        // the vault isFullySettled unless we allow rolling prior to this...
        // NotionalV2.getVaultState();
    }

    function _depositFromNotional(
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {
        // // We have `deposit` amount of borrowed underlying tokens. Now we execute a trade
        // // to receive some amount of lending tokens
        // uint256 lendUnderlyingTokens;
        // // This should trade exactIn = deposit
        // // _execute0xTrade(trade, deposit);

        // // Now we lend the underlying amount
        // // TODO: get the maturity from Notional
        // (uint256 fCashAmount, /* */, bytes32 encodedTrade) = NotionalV2.getfCashLendFromDeposit(
        //     LEND_CURRENCY_ID,
        //     lendUnderlyingTokens, // may need to buffer this down a bit
        //     maturity,
        //     minLendRate,
        //     block.timestamp,
        //     true
        // );
        // BatchLend[] action = new BatchLend[](1);
        // action[0].currencyId = LEND_CURRENCY_ID;
        // action[0].depositUnderlying = true;
        // action[0].trades = new bytes32[](1);
        // action[0].trades[0] = encodedTrade;

        // // If this is ETH we need to do some special handling
        // // TODO: switch this to use the fCash wrapper....via ERC1155
        // // TODO: this will trigger re-entrancy
        // NotionalV2.batchLend(address(this), action);

        // // fCash is the strategy token in this case
        // return fCashAmount;
    }

    function _redeemFromNotional(
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 tokensFromRedeem) {
        // IWrappedfCash(fCashWrapper).redeemToUnderlying(strategyTokens, address(this), maxImpliedRate);

        // This will trade underlying for borrowed currency id using exact in based on
        // what we redeemed above
        // tokensFromRedeem = _execute0xTrade(trade, deposit);
    }
}