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
import {IPOracle, IPRouter} from "@interfaces/pendle/IPendle.sol";

library Deployments {
    uint256 internal constant CHAIN_ID = Constants.CHAIN_ID_ARBITRUM;
    NotionalProxy internal constant NOTIONAL = NotionalProxy(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    address internal constant ETH_ADDRESS = address(0);
    WETH9 internal constant WETH =
        WETH9(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IBalancerVault internal constant BALANCER_VAULT =
        IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    UniV3ISwapRouter internal constant UNIV3_ROUTER = UniV3ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address internal constant CAMELOT_V3_ROUTER = 0x1F721E2E82F6676FCE4eA07A5958cF098D339e18;
    address internal constant ZERO_EX = 0x0000000000001fF3684f28c67538d4D072C22734;
    IUniV2Router2 internal constant UNIV2_ROUTER = IUniV2Router2(address(0));
    ICurveRouterV2 public constant CURVE_ROUTER_V2 = ICurveRouterV2(0x4c2Af2Df2a7E567B5155879720619EA06C5BB15D);
    // Curve meta registry is not deployed on arbitrum
    ICurveMetaRegistry public constant CURVE_META_REGISTRY = ICurveMetaRegistry(address(0));

    address internal constant ALT_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address internal constant CURVE_V1_HANDLER = address(0);
    address internal constant CURVE_V2_HANDLER = address(0);
    address internal constant CURVE_MINTER = 0xabC000d88f23Bb45525E447528DBF656A9D55bf5;
    ITradingModule internal constant TRADING_MODULE = ITradingModule(0xBf6B9c5608D520469d8c4BD1E24F850497AF0Bb8);
    address internal constant TREASURY_MANAGER = 0x53144559C0d4a3304e2DD9dAfBD685247429216d;
    address internal constant EMERGENCY_EXIT_MANAGER = 0x4FfAe2085c2f5Ff70532A1BDe1bcfF1CF11755Fe;
    address internal constant BALANCER_SPOT_PRICE = 0x904d881ceC1b8bc3f3Ff32cCf9533c1843706E9e;
    IWrappedfCashFactory internal constant WRAPPED_FCASH_FACTORY = IWrappedfCashFactory(0x5D051DeB5db151C2172dCdCCD42e6A2953E27261);

    // Chainlink L2 Sequencer Uptime: https://docs.chain.link/data-feeds/l2-sequencer-feeds/
    AggregatorV2V3Interface internal constant SEQUENCER_UPTIME_ORACLE = AggregatorV2V3Interface(0xFdB631F5EE196F0ed6FAa767959853A9F217697D);
    address internal constant VAULT_REWARDER_LIB = 0x3965D75Bfe40435246c22F75db2e170210b8bC68;

    IPOracle internal constant PENDLE_ORACLE = IPOracle(0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2);
    IPRouter internal constant PENDLE_ROUTER = IPRouter(0x888888888889758F76e7103c6CbF23ABbF58F946);
    address internal constant FLASH_LENDER_AAVE = 0x9D4D2C08b29A2Db1c614483cd8971734BFDCC9F2;
}