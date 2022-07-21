// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Constants} from "../global/Constants.sol";
import {
    DeploymentParams, 
    InitParams, 
    StrategyVaultSettings, 
    PoolContext
} from "./balancer/BalancerVaultTypes.sol";
import {BaseVaultStorage} from "./balancer/BaseVaultStorage.sol";
import {MetaStableVaultMixin} from "./balancer/mixins/MetaStableVaultMixin.sol";
import {AuraStakingMixin} from "./balancer/mixins/AuraStakingMixin.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {BalancerUtils} from "./balancer/BalancerUtils.sol";
import {LibBalancerStorage} from "./balancer/internal/LibBalancerStorage.sol";

contract MetaStable2TokenVault is
    UUPSUpgradeable, 
    Initializable,
    BaseVaultStorage,
    MetaStableVaultMixin,
    AuraStakingMixin
{
    /** Events */
    event StrategyVaultSettingsUpdated(StrategyVaultSettings settings);

    constructor(NotionalProxy notional_, DeploymentParams memory params)
        BaseVaultStorage(notional_, params) 
        MetaStableVaultMixin(address(BALANCER_POOL_TOKEN))
        AuraStakingMixin(params.liquidityGauge, params.auraRewardPool)
    {}

    function initialize(InitParams calldata params)
        external
        initializer
        onlyNotionalOwner
    {
        __INIT_VAULT(params.name, params.borrowCurrencyId);
        _setStrategyVaultSettings(params.settings);

        BalancerUtils.approveBalancerTokens(_poolContext());
    }

    function _setStrategyVaultSettings(StrategyVaultSettings memory settings) private {

        require(settings.oracleWindowInSeconds <= uint32(MAX_ORACLE_QUERY_WINDOW));
        require(settings.settlementCoolDownInMinutes <= Constants.MAX_SETTLEMENT_COOLDOWN_IN_MINUTES);
        require(settings.postMaturitySettlementCoolDownInMinutes <= Constants.MAX_SETTLEMENT_COOLDOWN_IN_MINUTES);
        require(settings.balancerOracleWeight <= Constants.VAULT_PERCENT_BASIS);
        require(settings.maxBalancerPoolShare <= Constants.VAULT_PERCENT_BASIS);
        require(settings.settlementSlippageLimitPercent <= Constants.VAULT_PERCENT_BASIS);
        require(settings.postMaturitySettlementSlippageLimitPercent <= Constants.VAULT_PERCENT_BASIS);
        require(settings.feePercentage <= Constants.VAULT_PERCENT_BASIS);

        mapping(uint256 => StrategyVaultSettings) storage vaultSettings 
            = LibBalancerStorage.getStrategyVaultSettings();
        vaultSettings[0] = settings;

        emit StrategyVaultSettingsUpdated(settings);
    }

    function _poolContext() internal view returns (PoolContext memory) {
        return PoolContext({
            pool: BALANCER_POOL_TOKEN,
            poolId: BALANCER_POOL_ID,
            primaryToken: address(_underlyingToken()),
            secondaryToken: address(SECONDARY_TOKEN),
            primaryIndex: PRIMARY_INDEX,
            primaryDecimals: PRIMARY_DECIMALS,
            secondaryDecimals: SECONDARY_DECIMALS,
            liquidityGauge: LIQUIDITY_GAUGE,
            auraBooster: AURA_BOOSTER,
            auraRewardPool: AURA_REWARD_POOL,
            auraPoolId: AURA_POOL_ID,
            balToken: BAL_TOKEN,
            auraToken: AURA_TOKEN
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
    
    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal override onlyNotionalOwner {}
}
