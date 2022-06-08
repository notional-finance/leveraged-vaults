pragma solidity =0.8.11;

interface IBoostController {
    function depositToken(address token, uint256 amount) external;

    function withdrawToken(address token, uint256 amount) external;

    function claimRewards(address liquidityGauge) external;
}
