// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;

import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {IWstETH} from "../../interfaces/IWstETH.sol";
import {IBalancerVault, IAsset} from "../../interfaces/balancer/IBalancerVault.sol";
import {WETH9} from "../../interfaces/WETH9.sol";
import {ISwapRouter as UniV3ISwapRouter} from "../../interfaces/uniswap/v3/ISwapRouter.sol";
import {IUniV2Router2} from "../../interfaces/uniswap/v2/IUniV2Router2.sol";
import {ICurveRouter} from "../../interfaces/curve/ICurveRouter.sol";
import {ICurveRegistry} from "../../interfaces/curve/ICurveRegistry.sol";

/// @title Hardcoded Deployment Addresses for ETH Mainnet
library Deployments {
    NotionalProxy internal constant NOTIONAL = NotionalProxy(0xD8229B55bD73c61D840d339491219ec6Fa667B0a);
    IWstETH internal constant WRAPPED_STETH = IWstETH(0xd2D24271030ecE6068C7E8874daF61fCC3225acB);
    address internal constant ETH_ADDRESS = address(0);
    WETH9 internal constant WETH =
        WETH9(0xdFCeA9088c8A88A76FF74892C1457C17dfeef9C1);
    IBalancerVault internal constant BALANCER_VAULT =
        IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    UniV3ISwapRouter internal constant UNIV3_ROUTER = UniV3ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address internal constant ZERO_EX = address(0);
    IUniV2Router2 internal constant UNIV2_ROUTER = IUniV2Router2(address(0));

    address internal constant ALT_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    ICurveRegistry public constant CURVE_REGISTRY = ICurveRegistry(address(0));
    ICurveRouter public constant CURVE_ROUTER = ICurveRouter(address(0));
}