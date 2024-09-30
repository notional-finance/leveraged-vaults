// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@interfaces/notional/NotionalProxy.sol";
import "@interfaces/notional/IStrategyVault.sol";
import "@interfaces/trading/ITradingModule.sol";

abstract contract StrategyVaultHarness {
    address public EXISTING_DEPLOYMENT;
    bytes public metadata;

    uint16 internal constant ENABLED                         = 1 << 0;
    uint16 internal constant ALLOW_ROLL_POSITION             = 1 << 1;
    uint16 internal constant ONLY_VAULT_ENTRY                = 1 << 2;
    uint16 internal constant ONLY_VAULT_EXIT                 = 1 << 3;
    uint16 internal constant ONLY_VAULT_ROLL                 = 1 << 4;
    uint16 internal constant ONLY_VAULT_DELEVERAGE           = 1 << 5;
    uint16 internal constant VAULT_MUST_SETTLE               = 1 << 6;
    uint16 internal constant ALLOW_REENTRANCY                = 1 << 7;
    uint16 internal constant DISABLE_DELEVERAGE              = 1 << 8;
    uint16 internal constant ENABLE_FCASH_DISCOUNT           = 1 << 9;

    struct RewardSettings {
        address token;
        uint128 emissionRatePerYear;
        uint32 endTime;
    }

    function setDeployment(address deployment) public {
        EXISTING_DEPLOYMENT = deployment;
    }

    function getVaultName() public pure virtual returns (string memory);
    function getTestVaultConfig() public view virtual returns (VaultConfigParams memory);

    function deployVaultImplementation() public virtual returns (
        address impl, bytes memory _metadata
    );
    function getInitializeData() public view virtual returns (bytes memory initData);
    function getRequiredOracles() public view virtual returns (
        address[] memory token, address[] memory oracle
    );

    function getDeploymentConfig() public view virtual returns (VaultConfigParams memory params, uint80 maxPrimaryBorrow);
    function getTradingPermissions() public view virtual returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    );

    function getRewardSettings() public view virtual returns (RewardSettings[] memory rewards) {
        return rewards;
    }

    function hasRewardReinvestmentRole() public view virtual returns (bool) {
        return false;
    }
}
