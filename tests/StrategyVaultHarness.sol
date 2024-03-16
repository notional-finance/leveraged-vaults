// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@interfaces/notional/NotionalProxy.sol";
import "@interfaces/notional/IStrategyVault.sol";
import "@interfaces/trading/ITradingModule.sol";

abstract contract StrategyVaultHarness {
    address public EXISTING_DEPLOYMENT;
    bytes public metadata;

    function setUp() public virtual;

    function setDeployment(address deployment) public {
        EXISTING_DEPLOYMENT = deployment;
    }

    function getVaultName() public pure virtual returns (string memory);
    function getTestVaultConfig() public view virtual returns (VaultConfigParams memory);

    function initVariables() public virtual;
    function deployVaultImplementation() public virtual returns (
        address impl, bytes memory _metadata
    );
    function getInitializeData() public view virtual returns (bytes memory initData);
    function getRequiredOracles() public view virtual returns (
        address[] memory token, address[] memory oracle
    );

    // By default, these two are left unimplemented
    function getDeploymentConfig() public view virtual returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {}
    function getTradingPermissions() public view virtual returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {}
}