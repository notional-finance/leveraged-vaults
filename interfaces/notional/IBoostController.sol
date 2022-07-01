// SPDX-License-Identifier: GPL-v3
pragma solidity >=0.7.6;

import "./IVeBalDelegator.sol";
import {ILiquidityGauge} from "../balancer/ILiquidityGauge.sol";

interface IBoostController {
    function VEBAL_DELEGATOR() external view returns (IVeBalDelegator);

    function depositToken(address token, uint256 amount) external;

    function withdrawToken(address token, uint256 amount) external;

    function claimBAL(ILiquidityGauge liquidityGauge)
        external
        returns (uint256 claimAmount);

    function claimGaugeTokens(ILiquidityGauge liquidityGauge)
        external
        returns (address[] memory tokens, uint256[] memory balancesTransferred);
}
