// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {Constants} from "@contracts/global/Constants.sol";
import {Deployments} from "@deployments/Deployments.sol";
import { 
    BaseStakingVault,
    WithdrawRequest,
    RedeemParams
} from "../BaseStakingVault.sol";
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

struct DepositParams {
    uint16 dexId;
    uint256 minPurchaseAmount;
    uint32 deadline;
    bytes exchangeData;
    uint256 minPtOut;
    IPRouter.ApproxParams approxParams;
}

abstract contract PendlePrincipalToken is BaseStakingVault {
    IPOracle immutable ORACLE = IPOracle(0x66a1096C6366b2529274dF4f5D8247827fe4CEA8);
    IPRouter immutable ROUTER = IPRouter(0x00000000005BBB0EF59571E58418F9a4357b68A0);
    // // TODO: can use this to get estimations for trading amounts and bypass their SDK
    // IPStaticRouter immutable STATIC_ROUTER = IPStaticRouter(0x263833d47eA3fA4a30f269323aba6a107f9eB14C);
    address immutable TOKEN_IN_SY;
    address immutable TOKEN_OUT_SY;
    IStandardizedYield immutable SY;
    IPPrincipalToken immutable PT;
    IPYieldToken immutable YT;
    uint256 PT_PRECISION;
    IPMarket immutable MARKET;
    uint32 immutable TWAP_DURATION;
    bool immutable USE_SY_ORACLE_RATE;

    constructor(
        address market,
        address tokenInSY,
        address tokenOutSY,
        address borrowToken,
        uint32 twapDuration,
        bool useSyOracleRate,
        address ptToken
    ) BaseStakingVault(
        Deployments.NOTIONAL,
        Deployments.TRADING_MODULE,
        ptToken,
        borrowToken
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

        TWAP_DURATION = twapDuration;
        USE_SY_ORACLE_RATE = useSyOracleRate;
        (
            bool increaseCardinalityRequired,
            /* */,
            bool oldestObservationSatisfied
        ) = ORACLE.getOracleState(market, twapDuration);
        require(!increaseCardinalityRequired && oldestObservationSatisfied, "Oracle Init");
    }

    function getExchangeRate(uint256 maturity) public view override returns (int256) {
        uint256 ptRate = USE_SY_ORACLE_RATE ? 
            ORACLE.getPtToSyRate(address(MARKET), TWAP_DURATION) :
            ORACLE.getPtToAssetRate(address(MARKET), TWAP_DURATION);

        // TODO: may need to also get the rate from the sy or asset token
        // back to the borrowed currency....
        int256 stakeAssetPrice = super.getExchangeRate(maturity);

        // TODO: add safeint here...
        return int256(ptRate) * stakeAssetPrice / int256(EXCHANGE_RATE_PRECISION);
    }

    function _stakeTokens(
        address /* account */,
        uint256 depositUnderlyingExternal,
        uint256 /* maturity */,
        bytes calldata data
    ) internal override returns (uint256 vaultShares) {
        require(!PT.isExpired());

        DepositParams memory params = abi.decode(data, (DepositParams));
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
        (uint256 ptReceived, /* */, /* */) = ROUTER.swapExactTokenForPt(
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
        bytes calldata data
    ) internal override returns (uint256 borrowedCurrencyAmount) {
        uint256 netTokenOut = _redeemPT(vaultShares);

        if (TOKEN_OUT_SY != BORROW_TOKEN) {
            RedeemParams memory params = abi.decode(data, (RedeemParams));

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
