// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;

import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {IWstETH} from "../../interfaces/IWstETH.sol";
import {IBalancerVault, IAsset} from "../../interfaces/balancer/IBalancerVault.sol";
import {WETH9} from "../../interfaces/WETH9.sol";

/// @title Hardcoded Deployment Addresses for ETH Mainnet
library Deployments {
    NotionalProxy internal constant NOTIONAL = NotionalProxy(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    IWstETH internal constant WRAPPED_STETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    address internal constant ETH_ADDRESS = address(0);
    WETH9 internal constant WETH =
        WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IBalancerVault internal constant BALANCER_VAULT =
        IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
}