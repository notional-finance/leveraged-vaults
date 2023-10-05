// SPDX-License-Identifier: GPL-v3
pragma solidity >=0.7.0;

import {
    OrderType, 
    DecreasePositionSwapType
} from "./GmxTypes.sol";

interface IGmxReader {

    struct Addresses {
        address account;
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address initialCollateralToken;
        address[] swapPath;
    }

    struct Numbers {
        OrderType orderType;
        DecreasePositionSwapType decreasePositionSwapType;
        uint256 sizeDeltaUsd;
        uint256 initialCollateralDeltaAmount;
        uint256 triggerPrice;
        uint256 acceptablePrice;
        uint256 executionFee;
        uint256 callbackGasLimit;
        uint256 minOutputAmount;
        uint256 updatedAtBlock;
    }

    struct Flags {
        bool isLong;
        bool shouldUnwrapNativeToken;
        bool isFrozen;
    }

    struct OrderProps {
        Addresses addresses;
        Numbers numbers;
        Flags flags;
    }

    function getOrder(address dataStore, bytes32 key) external view returns (OrderProps memory);
}