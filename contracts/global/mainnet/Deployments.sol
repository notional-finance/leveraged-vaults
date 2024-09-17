// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;

import {Constants} from "../Constants.sol";
import {NotionalProxy} from "@interfaces/notional/NotionalProxy.sol";
import {IWstETH} from "@interfaces/IWstETH.sol";
import {IBalancerVault, IAsset} from "@interfaces/balancer/IBalancerVault.sol";
import {WETH9} from "@interfaces/WETH9.sol";
import {ISwapRouter as UniV3ISwapRouter} from "@interfaces/uniswap/v3/ISwapRouter.sol";
import {IUniV2Router2} from "@interfaces/uniswap/v2/IUniV2Router2.sol";
import {ICurveRouter} from "@interfaces/curve/ICurveRouter.sol";
import {ICurveRegistry} from "@interfaces/curve/ICurveRegistry.sol";
import {ICurveMetaRegistry} from "@interfaces/curve/ICurveMetaRegistry.sol";
import {ICurveRouterV2} from "@interfaces/curve/ICurveRouterV2.sol";
import {ITradingModule} from "@interfaces/trading/ITradingModule.sol";
import {IWrappedfCashFactory} from "@interfaces/notional/IWrappedfCashFactory.sol";
import {AggregatorV2V3Interface} from "@interfaces/chainlink/AggregatorV2V3Interface.sol";
import {IPRouter, IPOracle} from "@interfaces/pendle/IPendle.sol";

/// @title Hardcoded Deployment Addresses for Mainnet
library Deployments {
    uint256 internal constant CHAIN_ID = Constants.CHAIN_ID_MAINNET;
    NotionalProxy internal constant NOTIONAL = NotionalProxy(0x6e7058c91F85E0F6db4fc9da2CA41241f5e4263f);
    address internal constant ETH_ADDRESS = address(0);
    WETH9 internal constant WETH = WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IBalancerVault internal constant BALANCER_VAULT =
        IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    UniV3ISwapRouter internal constant UNIV3_ROUTER = UniV3ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address internal constant CAMELOT_V3_ROUTER = address(0);
    address internal constant ZERO_EX = 0x0000000000001fF3684f28c67538d4D072C22734;
    IUniV2Router2 internal constant UNIV2_ROUTER = IUniV2Router2(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address internal constant ALT_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    ICurveRouterV2 public constant CURVE_ROUTER_V2 = ICurveRouterV2(0xF0d4c12A5768D806021F80a262B4d39d26C58b8D);
    ICurveMetaRegistry public constant CURVE_META_REGISTRY = ICurveMetaRegistry(0xF98B45FA17DE75FB1aD0e7aFD971b0ca00e379fC);
    address internal constant CURVE_V1_HANDLER = 0x46a8a9CF4Fc8e99EC3A14558ACABC1D93A27de68;
    address internal constant CURVE_V2_HANDLER = 0xC4F389020002396143B863F6325aA6ae481D19CE;
    address internal constant CURVE_MINTER = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;

    ITradingModule internal constant TRADING_MODULE = ITradingModule(0x594734c7e06C3D483466ADBCe401C6Bd269746C8);
    address internal constant TREASURY_MANAGER = 0x53144559C0d4a3304e2DD9dAfBD685247429216d;
    // Notional Inc
    address internal constant EMERGENCY_EXIT_MANAGER = 0xD9D5a9dc6a952b7aD6B05a983b399537B7c0Ee88;
    address internal constant BALANCER_SPOT_PRICE = 0xA153B3E85833F8a323E60Dcdc08F6286eae28728;
    IWrappedfCashFactory internal constant WRAPPED_FCASH_FACTORY = IWrappedfCashFactory(address(0));

    address internal constant VAULT_REWARDER_LIB = 0x96B1ebF4877136aF2f935395c3C4B179D66c4974;

    // Chainlink L2 Sequencer Uptime: https://docs.chain.link/data-feeds/l2-sequencer-feeds/
    AggregatorV2V3Interface internal constant SEQUENCER_UPTIME_ORACLE = AggregatorV2V3Interface(address(0));

    // Pendle Oracle
    IPOracle internal constant PENDLE_ORACLE = IPOracle(0x66a1096C6366b2529274dF4f5D8247827fe4CEA8);
    IPRouter internal constant PENDLE_ROUTER = IPRouter(0x00000000005BBB0EF59571E58418F9a4357b68A0);
    address internal constant FLASH_LENDER_AAVE = 0x0c86c636ed5593705b5675d370c831972C787841;
}