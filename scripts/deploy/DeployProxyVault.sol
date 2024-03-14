// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "./GnosisHelper.s.sol";
import "@deployments/Deployments.sol";
import "@contracts/global/Types.sol";
import "@contracts/trading/TradingModule.sol";
import "@contracts/proxy/nProxy.sol";
import "@interfaces/notional/IVaultController.sol";
import "@interfaces/trading/ITradingModule.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

abstract contract DeployProxyVault is Script, GnosisHelper {
    address EXISTING_DEPLOYMENT;

    function initVariables() internal virtual;
    function deployVaultImplementation() internal virtual returns (address impl);
    function getInitializeData() internal view virtual returns (bytes memory initData);
    function getRequiredOracles() internal view virtual returns (
        address[] memory token, address[] memory oracle
    );

    // By default, these two are left unimplemented
    function getDeploymentConfig() internal view virtual returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {}
    function getTradingPermissions() internal view virtual returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {}

    function run() public {
        require(block.chainid == Deployments.CHAIN_ID, "Invalid Chain");
        bool upgradeVault = vm.envOr("UPGRADE_VAULT", false);
        bool updateConfig = vm.envOr("UPDATE_CONFIG", false);
        address proxy = vm.envOr("PROXY", address(0));

        if (EXISTING_DEPLOYMENT == address(0)) {
            // Create a new deployment if value is not set
            console.log("Creating a new vault deployment");
            (address[] memory tkOracles, address[] memory oracles) = getRequiredOracles();
            (address[] memory tkPerms, ITradingModule.TokenPermissions[] memory permissions) = getTradingPermissions();

            uint256 totalCalls = tkPerms.length + 3;

            // Check for the required oracles, these are all token/USD oracles
            for (uint256 i; i < tkOracles.length; i++) {
                (AggregatorV2V3Interface oracle, /* */) = Deployments.TRADING_MODULE.priceOracles(tkOracles[i]);
                if (address(oracle) == address(0)) {
                    totalCalls++;
                } else {
                    require(address(oracle) == oracles[i], "Oracle Mismatch");
                }
            }

            // Broadcast the implementation if proxy is not set
            if (proxy == address(0)) {
                vm.startBroadcast();
                address impl = deployVaultImplementation();
                console.log("Implementation Address", impl);
                vm.stopBroadcast();
                return;
            }

            MethodCall[] memory init = new MethodCall[](totalCalls);
            uint256 callIndex = 0;
            {
                // Set the implementation
                init[callIndex].to = proxy;
                init[callIndex].callData = getInitializeData();
                callIndex++;

                // Grant roles for emergency exit and reward reinvestment
                init[callIndex].to = proxy;
                init[callIndex].callData = abi.encodeWithSelector(
                    AccessControlUpgradeable.grantRole.selector,
                    keccak256("REWARD_REINVESTMENT_ROLE"),
                    Deployments.TREASURY_MANAGER
                );
                callIndex++;

                init[callIndex].to = proxy;
                init[callIndex].callData = abi.encodeWithSelector(
                    AccessControlUpgradeable.grantRole.selector,
                    keccak256("EMERGENCY_EXIT_ROLE"),
                    Deployments.EMERGENCY_EXIT_MANAGER
                );
                callIndex++;
            }

            for (uint256 i; i < tkPerms.length; i++) {
                init[callIndex].to = address(Deployments.TRADING_MODULE);
                init[callIndex].callData = abi.encodeWithSelector(
                    TradingModule.setTokenPermissions.selector,
                    proxy, tkPerms[i], permissions[i]
                );
                callIndex++;
            }

            for (uint256 i; i < tkOracles.length; i++) {
                (AggregatorV2V3Interface oracle, /* */) = Deployments.TRADING_MODULE.priceOracles(tkOracles[i]);
                if (address(oracle) == address(0)) {
                    init[callIndex].to = address(Deployments.TRADING_MODULE);
                    init[callIndex].callData = abi.encodeWithSelector(
                        TradingModule.setPriceOracle.selector,
                        tkOracles[i], AggregatorV2V3Interface(oracles[i])
                    );
                    callIndex++;
                }
            }

            // Outputs the initialization code that needs to be run by the owner
            generateBatch(
                string(abi.encodePacked("./scripts/deploy/", vm.toString(proxy),".initVault.json")),
                init
            );
            EXISTING_DEPLOYMENT = proxy;
        }
        
        if (upgradeVault) {
            vm.startBroadcast();
            address impl = deployVaultImplementation();
            vm.stopBroadcast();

            MethodCall[] memory upgrade = new MethodCall[](1);
            upgrade[0].to = EXISTING_DEPLOYMENT;
            upgrade[0].callData = abi.encodeWithSelector(UUPSUpgradeable.upgradeTo.selector, impl);

            // Outputs the upgrade code that needs to be run by the owner
            generateBatch(
                string(abi.encodePacked("./scripts/deploy/", vm.toString(EXISTING_DEPLOYMENT),".upgradeVault.json")),
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
                string(abi.encodePacked("./scripts/deploy/", vm.toString(EXISTING_DEPLOYMENT),".updateConfig.json")),
                update
            );
        }
    }

}