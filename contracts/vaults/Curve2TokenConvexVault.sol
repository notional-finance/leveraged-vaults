// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    ConvexVaultDeploymentParams, 
    InitParams, 
    StrategyContext,
    Curve2TokenConvexStrategyContext
} from "./curve/CurveVaultTypes.sol";
import {Constants} from "../global/Constants.sol";
import {Deployments} from "../global/Deployments.sol";
import {TokenUtils, IERC20} from "../utils/TokenUtils.sol";
import {Curve2TokenVaultMixin} from "./curve/mixins/Curve2TokenVaultMixin.sol";
import {CurveVaultStorage} from "./curve/internal/CurveVaultStorage.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";

contract Curve2TokenConvexVault is Curve2TokenVaultMixin {
    using TokenUtils for IERC20;

    constructor(NotionalProxy notional_, ConvexVaultDeploymentParams memory params) Curve2TokenVaultMixin(notional_, params) {
    }

    function strategy() external override view returns (bytes4) {
        return bytes4(keccak256("Curve2TokenConvexVault"));
    }

    function initialize(InitParams calldata params)
        external
        initializer
        onlyNotionalOwner
    {
        __INIT_VAULT(params.name, params.borrowCurrencyId);
        CurveVaultStorage.setStrategyVaultSettings(params.settings);
    }

    function _depositFromNotional(
        address /* account */,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {
    }

    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 finalPrimaryBalance) {

    }   

    function convertStrategyToUnderlying(
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view virtual override returns (int256 underlyingValue) {

    } 

    function getStrategyContext() external view returns (Curve2TokenConvexStrategyContext memory) {
        return _strategyContext();
    }
}