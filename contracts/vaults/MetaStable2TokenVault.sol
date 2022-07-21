// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Constants} from "../global/Constants.sol";
import {
    DeploymentParams, 
    InitParams, 
    StrategyVaultSettings,
    StrategyVaultState,
    PoolContext,
    MetaStable2TokenAuraStrategyContext
} from "./balancer/BalancerVaultTypes.sol";
import {BaseVaultStorage} from "./balancer/BaseVaultStorage.sol";
import {MetaStable2TokenVaultMixin} from "./balancer/mixins/MetaStable2TokenVaultMixin.sol";
import {AuraStakingMixin} from "./balancer/mixins/AuraStakingMixin.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {BalancerUtils} from "./balancer/BalancerUtils.sol";
import {VaultUtils} from "./balancer/internal/VaultUtils.sol";
import {LibBalancerStorage} from "./balancer/internal/LibBalancerStorage.sol";

contract MetaStable2TokenVault is
    UUPSUpgradeable, 
    Initializable,
    BaseVaultStorage,
    MetaStable2TokenVaultMixin,
    AuraStakingMixin
{
    event StrategyVaultSettingsUpdated(StrategyVaultSettings settings);

    constructor(NotionalProxy notional_, DeploymentParams memory params)
        BaseVaultStorage(notional_, params) 
        MetaStable2TokenVaultMixin(
            address(_underlyingToken()), 
            params.balancerPoolId,
            params.secondaryBorrowCurrencyId
        )
        AuraStakingMixin(params.liquidityGauge, params.auraRewardPool)
    {}

    function initialize(InitParams calldata params)
        external
        initializer
        onlyNotionalOwner
    {
        __INIT_VAULT(params.name, params.borrowCurrencyId);
        _setStrategyVaultSettings(params.settings);

        BalancerUtils.approveBalancerTokens(_twoTokenPoolContext(), _auraStakingContext());
    }

    function _setStrategyVaultSettings(StrategyVaultSettings memory settings) private {
        VaultUtils._validateStrategyVaultSettings(settings, uint32(MAX_ORACLE_QUERY_WINDOW));
        VaultUtils._setStrategyVaultSettings(settings);
        emit StrategyVaultSettingsUpdated(settings);
    }

    function _strategyContext() internal view returns (MetaStable2TokenAuraStrategyContext memory) {
        return MetaStable2TokenAuraStrategyContext({
            poolContext: _twoTokenPoolContext(),
            oracleContext: _stableOracleContext(),
            stakingContext: _auraStakingContext()
        });
    }

    function _depositFromNotional(
        address account,
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
    ) public view override returns (int256 underlyingValue) {
    }

    function getStrategyVaultState() external view returns (StrategyVaultState memory) {
        return VaultUtils._getStrategyVaultState();
    }

    function getStrategyVaultSettings() external view returns (StrategyVaultSettings memory) {
        return VaultUtils._getStrategyVaultSettings();
    }

    /// @notice Updates the vault settings
    /// @param settings vault settings
    function setStrategyVaultSettings(StrategyVaultSettings calldata settings)
        external
        onlyNotionalOwner
    {
        _setStrategyVaultSettings(settings);
    }

    function getStrategyContext() external view returns (MetaStable2TokenAuraStrategyContext memory) {
        return _strategyContext();
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal override onlyNotionalOwner {}
}
