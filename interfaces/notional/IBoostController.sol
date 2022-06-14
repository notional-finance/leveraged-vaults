// SPDX-License-Identifier: GPL-v3
pragma solidity >=0.7.6;

interface IBoostController {
    function depositToken(address token, uint256 amount) external;

    function withdrawToken(address token, uint256 amount) external;

    function claimBAL(address liquidityGauge)
        external
        returns (uint256 claimAmount);

    function claimGaugeTokens(address liquidityGauge)
        external
        returns (address[] memory tokens, uint256[] memory balancesTransferred);
}
