// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "./GnosisHelper.s.sol";
import "@contracts/global/Deployments.sol";
import "@contracts/global/Types.sol";
import "@contracts/trading/TradingModule.sol";
import "@contracts/proxy/nProxy.sol";
import "@interfaces/notional/IVaultController.sol";

abstract contract DeployProxyVault is Script, GnosisHelper {
    address EXISTING_DEPLOYMENT;

    function initVariables() internal virtual;
    function deployVaultImplementation() internal virtual returns (address impl);
    function getInitializeData() internal view virtual returns (bytes memory initData);
    function getDeploymentConfig() internal view virtual returns (VaultConfigParams memory, uint80 maxPrimaryBorrow) {}

    function deployProxy(address impl) internal returns (address) {
        vm.startBroadcast();
        address proxy = address(new nProxy(impl, ""));
        vm.stopBroadcast();

        return proxy;
    }

    function run() public {
        require(block.chainid == Deployments.CHAIN_ID, "Invalid Chain");
        bool upgradeVault = vm.envBool("UPGRADE_VAULT");
        bool updateConfig = vm.envBool("UPDATE_CONFIG");

        if (EXISTING_DEPLOYMENT == address(0)) {
            // Create a new deployment if value is not set
            console.log("Creating a new vault deployment");
            MethodCall[] memory init = new MethodCall[](1);
            address impl = deployVaultImplementation();
            address proxy = deployProxy(impl);
            init[0].to = proxy;
            init[0].callData = getInitializeData();

            // Outputs the initialization code that needs to be run by the owner
            generateBatch(
                string(abi.encodePacked("./scripts/deploy/", vm.toString(proxy),"/initVault.json")),
                init
            );

            // TODO: need to list oracles and set token permissions
        }
        
        if (upgradeVault) {
            address impl = deployVaultImplementation();

            MethodCall[] memory upgrade = new MethodCall[](1);
            upgrade[0].to = EXISTING_DEPLOYMENT;
            upgrade[0].callData = abi.encodeWithSelector(UUPSUpgradeable.upgradeTo.selector, impl);

            // Outputs the upgrade code that needs to be run by the owner
            generateBatch(
                string(abi.encodePacked("./scripts/deploy/", vm.toString(EXISTING_DEPLOYMENT),"/upgradeVault.json")),
                upgrade
            );
        }

        if (updateConfig) {
            MethodCall[] memory update = new MethodCall[](1);
            update[0].to = address(Deployments.NOTIONAL);
            (VaultConfigParams memory p, uint80 maxBorrow) = getDeploymentConfig();
            update[0].callData = abi.encodeWithSelector(
                IVaultAction.updateVault.selector,
                EXISTING_DEPLOYMENT, p, maxBorrow
            );

            // Outputs the upgrade code that needs to be run by the owner
            generateBatch(
                string(abi.encodePacked("./scripts/deploy/", vm.toString(EXISTING_DEPLOYMENT),"/updateConfig.json")),
                update
            );
        }
    }

}