// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {IEulerDToken} from "../../interfaces/euler/IEulerDToken.sol";
import {IEulerMarkets} from "../../interfaces/euler/IEulerMarkets.sol";
import {IEulerFlashLoanReceiver} from "../../interfaces/euler/IEulerFlashLoanReceiver.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {FlashLiquidatorBase} from "./FlashLiquidatorBase.sol";

contract EulerFlashLiquidator is IEulerFlashLoanReceiver, FlashLiquidatorBase {

    IEulerMarkets public immutable MARKETS;

    constructor(NotionalProxy notional_, address euler_, IEulerMarkets markets_) 
        FlashLiquidatorBase(notional_, euler_) {
        MARKETS = markets_;
    }

    function _flashLiquidate(
        address asset,
        uint256 amount,
        bool withdraw,
        LiquidationParams calldata params
    ) internal override {
        IEulerDToken dToken = IEulerDToken(MARKETS.underlyingToDToken(asset));
        dToken.flashLoan(amount, abi.encode(asset, amount, withdraw, params));
    }

    function onFlashLoan(bytes memory data) external override {
        super.handleLiquidation(0, true, data); // fee = 0, repay = true for Euler
    }
}
