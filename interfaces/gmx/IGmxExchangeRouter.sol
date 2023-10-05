// SPDX-License-Identifier: GPL-v3
pragma solidity >=0.7.0;

import {
    OrderType, 
    DecreasePositionSwapType
} from "./GmxTypes.sol";

interface IGmxExchangeRouter {

    struct CreateOrderParamsAddresses {
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address initialCollateralToken;
        address[] swapPath;
    }

    struct CreateOrderParamsNumbers {
        uint256 sizeDeltaUsd;
        uint256 initialCollateralDeltaAmount;
        uint256 triggerPrice;
        uint256 acceptablePrice;
        uint256 executionFee;
        uint256 callbackGasLimit;
        uint256 minOutputAmount;
    }

    struct CreateOrderParams {
        CreateOrderParamsAddresses addresses;
        CreateOrderParamsNumbers numbers;
        OrderType orderType;
        DecreasePositionSwapType decreasePositionSwapType;
        bool isLong;
        bool shouldUnwrapNativeToken;
        bytes32 referralCode;
    }

    function sendWnt(address receiver, uint256 amount) external;

    function sendTokens(
        address token,
        address receiver,
        uint256 amount
    ) external payable;

    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);

    function createOrder(CreateOrderParams calldata params) external;

    function updateOrder(
        bytes32 key,
        uint256 sizeDeltaUsd,
        uint256 acceptablePrice,
        uint256 triggerPrice,
        uint256 minOutputAmount
    ) external payable;

    function cancelOrder(bytes32 key) external payable;

    function claimFundingFees(
        address[] memory markets,
        address[] memory tokens,
        address receiver
    ) external payable;

    function dataStore() external view returns (address);

    function router() external view returns (address);
}
