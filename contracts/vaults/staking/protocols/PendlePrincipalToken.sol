// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import "forge-std/console.sol";
import {Constants} from "@contracts/global/Constants.sol";
import {VaultStorage} from "@contracts/vaults/common/VaultStorage.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {TypeConvert} from "@contracts/global/TypeConvert.sol";
import {BaseStakingVault, WithdrawRequest, RedeemParams} from "../BaseStakingVault.sol";
import {IERC20, TokenUtils} from "@contracts/utils/TokenUtils.sol";
import { ITradingModule, Trade, TradeType } from "@interfaces/trading/ITradingModule.sol";
import {
    IPOracle,
    IPRouter,
    IPMarket,
    IStandardizedYield,
    IPYieldToken,
    IPPrincipalToken
} from "@interfaces/pendle/IPendle.sol";

struct PendleDepositParams {
    uint16 dexId;
    uint256 minPurchaseAmount;
    bytes exchangeData;
    uint256 minPtOut;
    IPRouter.ApproxParams approxParams;
}

/** Base implementation for Pendle PT vaults */
abstract contract PendlePrincipalToken is BaseStakingVault {
    using TokenUtils for IERC20;
    using TypeConvert for uint256;

    IPMarket public immutable MARKET;
    address public immutable TOKEN_OUT_SY;

    address public immutable TOKEN_IN_SY;
    IStandardizedYield immutable SY;
    IPPrincipalToken immutable PT;
    IPYieldToken immutable YT;

    constructor(
        address market,
        address tokenInSY,
        address tokenOutSY,
        address borrowToken,
        address ptToken,
        address redemptionToken
    ) BaseStakingVault(
        ptToken,
        borrowToken,
        redemptionToken
    ) {
        MARKET = IPMarket(market);
        (address sy, address pt, address yt) = MARKET.readTokens();
        SY = IStandardizedYield(sy);
        PT = IPPrincipalToken(pt);
        YT = IPYieldToken(yt);
        require(address(PT) == ptToken);
        require(SY.isValidTokenIn(tokenInSY));
        // This may not be the same as valid token in, for LRT you can
        // put ETH in but you would only get weETH or eETH out
        require(SY.isValidTokenOut(tokenOutSY));

        TOKEN_IN_SY = tokenInSY;
        TOKEN_OUT_SY = tokenOutSY;
    }

    function _stakeTokens(
        address /* account */,
        uint256 depositUnderlyingExternal,
        uint256 /* maturity */,
        bytes calldata data
    ) internal override returns (uint256 vaultShares) {
        require(!PT.isExpired(), "Expired");
        PendleDepositParams memory params = abi.decode(data, (PendleDepositParams));
        uint256 tokenInAmount;

        if (TOKEN_IN_SY != BORROW_TOKEN) {
            Trade memory trade = Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: BORROW_TOKEN,
                buyToken: TOKEN_IN_SY,
                amount: depositUnderlyingExternal,
                limit: params.minPurchaseAmount,
                deadline: block.timestamp,
                exchangeData: params.exchangeData
            });

            // Executes a trade on the given Dex, the vault must have permissions set for
            // each dex and token it wants to sell.
            (/* */, tokenInAmount) = _executeTrade(params.dexId, trade);
        } else {
            tokenInAmount = depositUnderlyingExternal;
        }
        console.log('usdcIn', depositUnderlyingExternal);
        console.log('usdeOut', tokenInAmount);

        IPRouter.SwapData memory EMPTY_SWAP;
        IPRouter.LimitOrderData memory EMPTY_LIMIT;

        IERC20(TOKEN_IN_SY).checkApprove(address(Deployments.PENDLE_ROUTER), tokenInAmount);
        uint256 msgValue = TOKEN_IN_SY == Constants.ETH_ADDRESS ? tokenInAmount : 0;
        (uint256 ptReceived, /* */, /* */) = Deployments.PENDLE_ROUTER.swapExactTokenForPt{value: msgValue}(
            address(this),
            address(MARKET),
            params.minPtOut,
            params.approxParams,
            // When tokenIn == tokenMintSy then the swap router can be set to
            // empty data. This means that the vault must hold the underlying sy
            // token when we begin the execution.
            IPRouter.TokenInput({
                tokenIn: TOKEN_IN_SY,
                netTokenIn: tokenInAmount,
                tokenMintSy: TOKEN_IN_SY,
                pendleSwap: address(0),
                swapData: EMPTY_SWAP
            }),
            EMPTY_LIMIT
        );
        console.log('ptReceived', ptReceived);
        return ptReceived * uint256(Constants.INTERNAL_TOKEN_PRECISION) / STAKING_PRECISION;
    }

    /// @notice Handles PT redemption whether it is expired or not
    function _redeemPT(uint256 vaultShares) internal returns (uint256 netTokenOut) {
        uint256 netPtIn = getStakingTokensForVaultShare(vaultShares);
        uint256 netSyOut;
        console.log('netPtIn', netPtIn);
        // PT tokens are known to be ERC20 compatible
        if (PT.isExpired()) {
            PT.transfer(address(YT), netPtIn);
            netSyOut = YT.redeemPY(address(SY));
        } else {
            PT.transfer(address(MARKET), netPtIn);
            (netSyOut, ) = MARKET.swapExactPtForSy(address(SY), netPtIn, "");
        }
        console.log('syOut', netSyOut);
        netTokenOut = SY.redeem(address(this), netSyOut, TOKEN_OUT_SY, 0, true);
        console.log('sUSDeOut', netTokenOut);
    }

    function _executeInstantRedemption(
        address /* account */,
        uint256 vaultShares,
        uint256 /* maturity */,
        RedeemParams memory params
    ) internal override virtual returns (uint256 borrowedCurrencyAmount) {
        uint256 netTokenOut = _redeemPT(vaultShares);

        if (TOKEN_OUT_SY != BORROW_TOKEN) {
            Trade memory trade = Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: TOKEN_OUT_SY,
                buyToken: BORROW_TOKEN,
                amount: netTokenOut,
                limit: params.minPurchaseAmount,
                deadline: block.timestamp,
                exchangeData: params.exchangeData
            });

            // Executes a trade on the given Dex, the vault must have permissions set for
            // each dex and token it wants to sell.
            (/* */, borrowedCurrencyAmount) = _executeTrade(params.dexId, trade);
        } else {
            require(params.minPurchaseAmount <= netTokenOut, "Slippage");
            borrowedCurrencyAmount = netTokenOut;
        }
        console.log('usdcOut', borrowedCurrencyAmount);
    }

    function _initiateSYWithdraw(
        address account, uint256 vaultSharesToRedeem, bool isForced
    ) internal virtual returns (uint256 requestId);

    function _initiateWithdrawImpl(
        address account, uint256 vaultSharesToRedeem, bool isForced, bytes calldata data
    ) internal override returns (uint256 requestId) {
        // When doing a direct withdraw for PTs, we first redeem or trade out of the PT
        // and then initiate a withdraw on the TOKEN_OUT_SY. Since the vault shares are
        // stored in PT terms, we pass tokenOutSy terms (i.e. weETH or sUSDe) to the withdraw
        // implementation.
        uint256 minTokenOutSy;
        if (data.length > 0) (minTokenOutSy) = abi.decode(data, (uint256));
        uint256 tokenOutSy = _redeemPT(vaultSharesToRedeem);
        require(minTokenOutSy <= tokenOutSy, "Slippage");

        requestId = _initiateSYWithdraw(account, tokenOutSy, isForced);
        // Store the tokenOutSy here for later when we do a valuation check against the position
        VaultStorage.getWithdrawRequestData()[requestId] = abi.encode(tokenOutSy);
    }

    function getTokenOutSYForWithdrawRequest(uint256 requestId) public view returns (uint256) {
        return abi.decode(VaultStorage.getWithdrawRequestData()[requestId], (uint256));
    }

    function _checkReentrancyContext() internal override {
        // NO-OP
    }
}
