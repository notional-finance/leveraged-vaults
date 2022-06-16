// SPDX-License-Identifier: GPL-v3
pragma solidity >=0.7.6;

interface IVeBalDelegator {
    function BALANCER_MINTER() external view returns (address);

    function depositToken(
        address token,
        address from,
        uint256 amount
    ) external;

    function withdrawToken(
        address token,
        address to,
        uint256 amount
    ) external;

    function getTokenBalance(address token, address from)
        external
        view
        returns (uint256);

    function claimBAL(address liquidityGauge, address to)
        external
        returns (uint256 claimAmount);

    function claimGaugeTokens(address liquidityGauge, address to)
        external
        returns (address[] memory tokens, uint256[] memory balancesTransferred);

    function getGaugeRewardTokens(address liquidityGauge)
        external
        view
        returns (address[] memory tokens);
}
