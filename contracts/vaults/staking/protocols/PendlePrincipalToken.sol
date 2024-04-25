// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {Constants} from "@contracts/global/Constants.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {TypeConvert} from "@contracts/global/TypeConvert.sol";
import { 
    BaseStakingVault,
    WithdrawRequest,
    RedeemParams
} from "../BaseStakingVault.sol";
import {IERC20, TokenUtils} from "@contracts/utils/TokenUtils.sol";
import {
    ITradingModule,
    Trade,
    TradeType
} from "@interfaces/trading/ITradingModule.sol";
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

abstract contract PendlePrincipalToken is BaseStakingVault {
    using TokenUtils for IERC20;
    using TypeConvert for uint256;

    IPRouter immutable ROUTER = IPRouter(0x00000000005BBB0EF59571E58418F9a4357b68A0);
    address immutable TOKEN_IN_SY;
    address immutable TOKEN_OUT_SY;
    IStandardizedYield immutable SY;
    IPPrincipalToken immutable PT;
    IPYieldToken immutable YT;
    uint256 immutable PT_PRECISION;
    IPMarket immutable MARKET;

    constructor(
        address market,
        address tokenInSY,
        address tokenOutSY,
        address borrowToken,
        address ptToken,
        address redemptionToken
    ) BaseStakingVault(
        Deployments.NOTIONAL,
        Deployments.TRADING_MODULE,
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

        // PT decimals vary with the underlying SY precision
        PT_PRECISION = 10 ** PT.decimals();
    }

    function _stakeTokens(
        address /* account */,
        uint256 depositUnderlyingExternal,
        uint256 /* maturity */,
        bytes calldata data
    ) internal override returns (uint256 vaultShares) {
        require(!PT.isExpired());

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

        IPRouter.SwapData memory EMPTY_SWAP;
        IPRouter.LimitOrderData memory EMPTY_LIMIT;

        IERC20(TOKEN_IN_SY).checkApprove(address(ROUTER), depositUnderlyingExternal);
        uint256 msgValue = TOKEN_IN_SY == Constants.ETH_ADDRESS ? depositUnderlyingExternal : 0;
        (uint256 ptReceived, /* */, /* */) = ROUTER.swapExactTokenForPt{value: msgValue}(
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

        return ptReceived * uint256(Constants.INTERNAL_TOKEN_PRECISION) / PT_PRECISION;
    }

    function _redeemPT(uint256 vaultShares) internal returns (uint256 netTokenOut) {
        uint256 netPtIn = vaultShares * PT_PRECISION / uint256(Constants.INTERNAL_TOKEN_PRECISION);
        uint256 netSyOut;
        if (PT.isExpired()) {
            PT.transfer(address(YT), netPtIn);
            netSyOut = YT.redeemPY(address(SY));
        } else {
            // safeTransfer not required
            PT.transfer(address(MARKET), netPtIn);
            (netSyOut, ) = MARKET.swapExactPtForSy(
                address(SY), // better gas optimization to transfer SY directly to itself and burn
                netPtIn,
                ""
            );
        }

        netTokenOut = SY.redeem(address(this), netSyOut, TOKEN_OUT_SY, 0, true);
    }

    function _executeInstantRedemption(
        address /* account */,
        uint256 vaultShares,
        uint256 /* maturity */,
        RedeemParams memory params
    ) internal override returns (uint256 borrowedCurrencyAmount) {
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
            borrowedCurrencyAmount = netTokenOut;
        }
    }

    function _checkReentrancyContext() internal override {
        // NO-OP
    }
}
