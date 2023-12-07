// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;

import {Constants} from "./Constants.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {IWstETH} from "../../interfaces/IWstETH.sol";
import {IBalancerVault, IAsset} from "../../interfaces/balancer/IBalancerVault.sol";
import {WETH9} from "../../interfaces/WETH9.sol";
import {ISwapRouter as UniV3ISwapRouter} from "../../interfaces/uniswap/v3/ISwapRouter.sol";
import {IUniV2Router2} from "../../interfaces/uniswap/v2/IUniV2Router2.sol";
import {ICurveRouter} from "../../interfaces/curve/ICurveRouter.sol";
import {ICurveRegistry} from "../../interfaces/curve/ICurveRegistry.sol";
import {ICurveMetaRegistry} from "../../interfaces/curve/ICurveMetaRegistry.sol";
import {ICurveRouterV2} from "../../interfaces/curve/ICurveRouterV2.sol";
import {ITradingModule} from "../../interfaces/trading/ITradingModule.sol";
import {AggregatorV2V3Interface} from "../../interfaces/chainlink/AggregatorV2V3Interface.sol";

/// @title Hardcoded Deployment Addresses for Arbitrum
library Deployments {
    uint256 internal constant CHAIN_ID = Constants.CHAIN_ID_ARBITRUM;
    NotionalProxy internal constant NOTIONAL = NotionalProxy(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    IWstETH internal constant WRAPPED_STETH = IWstETH(0x5979D7b546E38E414F7E9822514be443A4800529);
    address internal constant ETH_ADDRESS = address(0);
    WETH9 internal constant WETH =
        WETH9(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IBalancerVault internal constant BALANCER_VAULT =
        IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    UniV3ISwapRouter internal constant UNIV3_ROUTER = UniV3ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address internal constant ZERO_EX = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    IUniV2Router2 internal constant UNIV2_ROUTER = IUniV2Router2(address(0));

    address internal constant ALT_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    ICurveRouterV2 public constant CURVE_ROUTER_V2 = ICurveRouterV2(0x4c2Af2Df2a7E567B5155879720619EA06C5BB15D);
    // Curve meta registry is not deployed on arbitrum
    ICurveMetaRegistry public constant CURVE_META_REGISTRY = ICurveMetaRegistry(address(0));
    address internal constant CURVE_V1_HANDLER = address(0);
    address internal constant CURVE_V2_HANDLER = address(0);
    ITradingModule internal constant TRADING_MODULE = ITradingModule(0xBf6B9c5608D520469d8c4BD1E24F850497AF0Bb8);
    address internal constant TREASURY_MANAGER = 0x53144559C0d4a3304e2DD9dAfBD685247429216d;
    address internal constant EMERGENCY_EXIT_MANAGER = 0xbf778Fc19d0B55575711B6339A3680d07352B221;
    address internal constant BALANCER_SPOT_PRICE = 0x8caE1cf20030cfA3298AC4e5E07a4fcda1912EBF;

    // Chainlink L2 Sequencer Uptime: https://docs.chain.link/data-feeds/l2-sequencer-feeds/
    AggregatorV2V3Interface internal constant SEQUENCER_UPTIME_ORACLE = AggregatorV2V3Interface(0xFdB631F5EE196F0ed6FAa767959853A9F217697D);
}

/// @title Hardcoded Deployment Addresses for Mainnet
/*library Deployments {
    uint256 internal constant CHAIN_ID = Constants.CHAIN_ID_MAINNET;
    NotionalProxy internal constant NOTIONAL = NotionalProxy(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    IWstETH internal constant WRAPPED_STETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    address internal constant ETH_ADDRESS = address(0);
    WETH9 internal constant WETH =
        WETH9(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IBalancerVault internal constant BALANCER_VAULT =
        IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    UniV3ISwapRouter internal constant UNIV3_ROUTER = UniV3ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address internal constant ZERO_EX = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    IUniV2Router2 internal constant UNIV2_ROUTER = IUniV2Router2(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address internal constant ALT_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    ICurveRouterV2 public constant CURVE_ROUTER_V2 = ICurveRouterV2(0x99a58482BD75cbab83b27EC03CA68fF489b5788f);
    ICurveMetaRegistry public constant CURVE_META_REGISTRY = ICurveMetaRegistry(0xF98B45FA17DE75FB1aD0e7aFD971b0ca00e379fC);
    address internal constant CURVE_V1_HANDLER = 0x46a8a9CF4Fc8e99EC3A14558ACABC1D93A27de68;
    address internal constant CURVE_V2_HANDLER = 0xC4F389020002396143B863F6325aA6ae481D19CE;
} */