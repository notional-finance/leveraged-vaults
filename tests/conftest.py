import pytest
from brownie import (
    interface,
    ZERO_ADDRESS,
    MetaStable2TokenAuraVault,
    MockMetaStable2TokenAuraVault,
    Boosted3TokenAuraVault,
    MockBoosted3TokenAuraVault,
    MetaStable2TokenAuraHelper,
    Boosted3TokenAuraHelper,
    Curve2TokenConvexVault,
    Curve2TokenConvexHelper,
    MockCurve2TokenConvexVault
)
from brownie.network import Chain
from brownie import network, Contract
from scripts.BalancerEnvironment import getEnvironment
from scripts.CurveEnvironment import getCurveEnvironment
from scripts.common import set_flags, set_dex_flags, set_trade_type_flags

chain = Chain()

@pytest.fixture(autouse=True)
def run_around_tests():
    chain.snapshot()
    yield
    chain.revert()

@pytest.fixture()
def ArbStratStableETHstETH():
    env = getEnvironment(network.show_active())
    strat = "StratStableETHstETH"

    impl = env.deployBalancerVault(strat, MetaStable2TokenAuraVault, [MetaStable2TokenAuraHelper])
    vault = env.deployVaultProxy(strat, impl, MetaStable2TokenAuraVault)

    env.tradingModule.setTokenPermissions(
        vault.address, 
        env.tokens["wstETH"].address, 
        [True, set_dex_flags(0, BALANCER_V2=True, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.tradingModuleOwner})

    # Deploy mock contract necessary for liquidation tests
    mockImpl = env.deployBalancerVault(strat, MockMetaStable2TokenAuraVault, [MetaStable2TokenAuraHelper])
    mock = env.deployVaultProxy(strat, impl, MetaStable2TokenAuraVault, mockImpl)
    mock = Contract.from_abi("MockMetaStable2TokenAuraVault", mock.address, interface.IBalancer2TokenMetaStableMockVault.abi)

    env.tradingModule.setTokenPermissions(
        mock.address, 
        env.tokens["wstETH"].address, 
        [True, set_dex_flags(0, BALANCER_V2=True, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.tradingModuleOwner})

    return (env, vault, mock)

@pytest.fixture()
def ArbStratAaveBoostedPoolDAIPrimary():
    env = getEnvironment(network.show_active())
    strat = "StratAaveBoostedPoolDAIPrimary"

    impl = env.deployBalancerVault(strat, Boosted3TokenAuraVault, [Boosted3TokenAuraHelper])
    vault = env.deployVaultProxy(strat, impl, Boosted3TokenAuraVault)

    # Deploy mock contract necessary for liquidation tests
    mockImpl = env.deployBalancerVault(strat, MockBoosted3TokenAuraVault, [Boosted3TokenAuraHelper])
    mock = env.deployVaultProxy(strat, impl, Boosted3TokenAuraVault, mockImpl)
    mock = Contract.from_abi("MockDAIBoostedVault", mock.address, interface.IBalancer3TokenBoostedMockVault.abi)

    return (env, vault, mock)

@pytest.fixture()
def ArbStratStablestETHETH():
    env = getEnvironment(network.show_active())
    strat = "StratStablestETHETH"

    impl = env.deployBalancerVault(strat, MetaStable2TokenAuraVault, [MetaStable2TokenAuraHelper])
    vault = env.deployVaultProxy(strat, impl, MetaStable2TokenAuraVault)

    env.tradingModule.setTokenPermissions(
        vault.address, 
        ZERO_ADDRESS, 
        [True, set_dex_flags(0, BALANCER_V2=True, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.tradingModuleOwner})

    # Deploy mock contract necessary for liquidation tests
    mockImpl = env.deployBalancerVault(strat, MockMetaStable2TokenAuraVault, [MetaStable2TokenAuraHelper])
    mock = env.deployVaultProxy(strat, impl, MetaStable2TokenAuraVault, mockImpl)
    mock = Contract.from_abi("MockMetaStable2TokenAuraVault", mock.address, interface.IBalancer2TokenMetaStableMockVault.abi)

    env.tradingModule.setTokenPermissions(
        mock.address, 
        ZERO_ADDRESS, 
        [True, set_dex_flags(0, BALANCER_V2=True, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.tradingModuleOwner})

    return (env, vault, mock)

@pytest.fixture()
def StratStableETHstETH():
    env = getEnvironment(network.show_active())
    strat = "StratStableETHstETH"
    vault = Contract.from_abi(
        "MetaStable2TokenAuraVault", 
        "0xF049B944eC83aBb50020774D48a8cf40790996e6", 
        MetaStable2TokenAuraVault.abi
    )

    impl = env.deployBalancerVault(strat, MetaStable2TokenAuraVault, [MetaStable2TokenAuraHelper])

    #impl = MetaStable2TokenAuraVault.at("0xb8871D17F7BDE7eD824533B14AA63BB9174c2711")   
    stratConfig = env.getStratConfig(strat)
    migrateData = impl.migrateAura.encode_input([
        stratConfig["maxUnderlyingSurplus"],
        stratConfig["settlementSlippageLimitPercent"], 
        stratConfig["postMaturitySettlementSlippageLimitPercent"], 
        stratConfig["emergencySettlementSlippageLimitPercent"], 
        stratConfig["maxPoolShare"],
        stratConfig["oraclePriceDeviationLimitPercent"],
        stratConfig["poolSlippageLimitPercent"]
    ])
    vault.upgradeToAndCall(impl, migrateData, {"from": env.notional.owner()})

    env.notional.updateVault(
        '0xF049B944eC83aBb50020774D48a8cf40790996e6', 
        [
            set_flags(0, ENABLED=True, ALLOW_ROLL_POSITION=True, ONLY_VAULT_DELEVERAGE=True),
            1, 100, 900, 0, 102, 80, 2, 2000, [0, 0], 10000
        ], 
        750000000000,
        {"from": env.notional.owner()}
    )

    # Deploy mock contract necessary for liquidation tests
    mockImpl = env.deployBalancerVault(strat, MockMetaStable2TokenAuraVault, [MetaStable2TokenAuraHelper])
    mock = env.deployVaultProxy(strat, impl, MetaStable2TokenAuraVault, mockImpl)
    mock = Contract.from_abi("MockMetaStable2TokenAuraVault", mock.address, interface.IBalancer2TokenMetaStableMockVault.abi)

    env.tradingModule.setTokenPermissions(
        mock.address, 
        env.tokens["wstETH"].address, 
        [True, set_dex_flags(0, BALANCER_V2=True, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})
    env.tradingModule.setTokenPermissions(
        mock.address, 
        env.tokens["stETH"].address, 
        [True, set_dex_flags(0, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})
    env.tradingModule.setTokenPermissions(
        mock.address, 
        env.tokens["WETH"].address, 
        [True, set_dex_flags(0, BALANCER_V2=True, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})
    env.tradingModule.setTokenPermissions(
        mock.address, 
        ZERO_ADDRESS, 
        [True, set_dex_flags(0, BALANCER_V2=True, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})

    env.notional.updateVault(
        mock.address, 
        [
            set_flags(0, ENABLED=True, ALLOW_ROLL_POSITION=True, ONLY_VAULT_DELEVERAGE=True),
            1, 100, 900, 0, 102, 80, 2, 2000, [0, 0], 10000
        ], 
        750000000000,
        {"from": env.notional.owner()}
    )

    return (env, vault, mock)

@pytest.fixture()
def StratAaveBoostedPoolDAIPrimary():
    env = getEnvironment(network.show_active())
    strat = "StratAaveBoostedPoolDAIPrimary"
    impl = env.deployBalancerVault(strat, Boosted3TokenAuraVault, [Boosted3TokenAuraHelper])
    vault = env.deployVaultProxy(strat, impl, Boosted3TokenAuraVault)

    env.tradingModule.setTokenPermissions(
        vault.address, 
        env.tokens["BAL"].address, 
        [True, set_dex_flags(0, UNISWAP_V3=True), set_trade_type_flags(0, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})

    mockImpl = env.deployBalancerVault(strat, MockBoosted3TokenAuraVault, [Boosted3TokenAuraHelper])
    mock = env.deployVaultProxy(strat, impl, Boosted3TokenAuraVault, mockImpl)
    mock = Contract.from_abi("MockDAIBoostedVault", mock.address, interface.IBalancer3TokenBoostedMockVault.abi)

    return (env, vault, mock)

@pytest.fixture()
def StratAaveBoostedPoolUSDCPrimary():
    env = getEnvironment(network.show_active())
    strat = "StratAaveBoostedPoolUSDCPrimary"
    impl = env.deployBalancerVault(strat, Boosted3TokenAuraVault, [Boosted3TokenAuraHelper])
    vault = env.deployVaultProxy(strat, impl, Boosted3TokenAuraVault)

    env.tradingModule.setTokenPermissions(
        vault.address, 
        env.tokens["BAL"].address, 
        [True, set_dex_flags(0, UNISWAP_V3=True), set_trade_type_flags(0, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})

    mockImpl = env.deployBalancerVault(strat, MockBoosted3TokenAuraVault, [Boosted3TokenAuraHelper])
    mock = env.deployVaultProxy(strat, impl, Boosted3TokenAuraVault, mockImpl)
    mock = Contract.from_abi("MockUSDCBoostedVault", mock.address, MockBoosted3TokenAuraVault.abi)

    return (env, vault, mock)

@pytest.fixture()
def StratEulerBoostedPoolDAIPrimary():
    env = getEnvironment(network.show_active())
    strat = "StratEulerBoostedPoolDAIPrimary"
    impl = env.deployBalancerVault(strat, Boosted3TokenAuraVault, [Boosted3TokenAuraHelper])
    vault = env.deployVaultProxy(strat, impl, Boosted3TokenAuraVault)

    env.tradingModule.setTokenPermissions(
        vault.address, 
        env.tokens["BAL"].address, 
        [True, set_dex_flags(0, UNISWAP_V3=True), set_trade_type_flags(0, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})

    mockImpl = env.deployBalancerVault(strat, MockBoosted3TokenAuraVault, [Boosted3TokenAuraHelper])
    mock = env.deployVaultProxy(strat, impl, Boosted3TokenAuraVault, mockImpl)
    mock = Contract.from_abi("MockDAIBoostedVault", mock.address, MockBoosted3TokenAuraVault.abi)

    return (env, vault, mock)

@pytest.fixture()
def StratEulerBoostedPoolUSDCPrimary():
    env = getEnvironment(network.show_active())
    strat = "StratEulerBoostedPoolUSDCPrimary"
    impl = env.deployBalancerVault(strat, Boosted3TokenAuraVault, [Boosted3TokenAuraHelper])
    vault = env.deployVaultProxy(strat, impl, Boosted3TokenAuraVault)

    env.tradingModule.setTokenPermissions(
        vault.address, 
        env.tokens["BAL"].address, 
        [True, set_dex_flags(0, UNISWAP_V3=True), set_trade_type_flags(0, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})

    mockImpl = env.deployBalancerVault(strat, MockBoosted3TokenAuraVault, [Boosted3TokenAuraHelper])
    mock = env.deployVaultProxy(strat, impl, Boosted3TokenAuraVault, mockImpl)
    mock = Contract.from_abi("MockUSDCBoostedVault", mock.address, interface.IBalancer3TokenBoostedMockVault.abi)

    return (env, vault, mock)

@pytest.fixture()
def StratCurveStableETHstETH():
    env = getCurveEnvironment(network.show_active())
    strat = "StratStableETHstETH"
    impl = env.deployVault(strat, Curve2TokenConvexVault, [Curve2TokenConvexHelper])    
    vault = env.deployVaultProxy(strat, impl, Curve2TokenConvexVault)

    env.tradingModule.setTokenPermissions(
        vault.address,
        env.tokens["CRV"].address,
        [True, set_dex_flags(0, CURVE_V2=True), set_trade_type_flags(0, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})

    # Deploy mock contract necessary for liquidation tests
    mockImpl = env.deployVault(strat, MockCurve2TokenConvexVault, [Curve2TokenConvexHelper])
    mock = env.deployVaultProxy(strat, impl, Curve2TokenConvexVault, mockImpl)
    mock = Contract.from_abi("MockCurve2TokenAuraVault", mock.address, interface.ICurve2TokenConvexMockVault.abi)
    env.tradingModule.setTokenPermissions(
        mock.address,
        env.tokens["CRV"].address,
        [True, set_dex_flags(0, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})
    env.tradingModule.setTokenPermissions(
        mock.address, 
        env.tokens["wstETH"].address, 
        [True, set_dex_flags(0, BALANCER_V2=True, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})
    env.tradingModule.setTokenPermissions(
        mock.address, 
        env.tokens["stETH"].address, 
        [True, set_dex_flags(0, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})
    env.tradingModule.setTokenPermissions(
        mock.address, 
        env.tokens["WETH"].address, 
        [True, set_dex_flags(0, BALANCER_V2=True, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})
    env.tradingModule.setTokenPermissions(
        mock.address, 
        ZERO_ADDRESS, 
        [True, set_dex_flags(0, BALANCER_V2=True, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})

    return (env, vault, mock)
