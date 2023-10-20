import pytest
from brownie import (
    interface,
    ZERO_ADDRESS,
    MockBalancerComposableAuraVault,
    BalancerComposableAuraVault,
    ComposableAuraHelper,
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

    impl = env.deployBalancerVault(strat, BalancerComposableAuraVault, [ComposableAuraHelper])
    vault = env.deployVaultProxy(strat, impl, BalancerComposableAuraVault)

    env.tradingModule.setTokenPermissions(
        vault.address, 
        env.tokens["wstETH"].address, 
        [True, set_dex_flags(0, BALANCER_V2=True, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.tradingModuleOwner})

    mockImpl = env.deployBalancerVault(strat, MockBalancerComposableAuraVault, [ComposableAuraHelper])
    mock = env.deployVaultProxy(strat, impl, BalancerComposableAuraVault, mockImpl)
    mock = Contract.from_abi("MockBalancerComposableAuraVault", mock.address, interface.IBalancerComposableMockVault.abi)

    env.tradingModule.setTokenPermissions(
        mock.address, 
        env.tokens["wstETH"].address, 
        [True, set_dex_flags(0, BALANCER_V2=True, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.tradingModuleOwner})
    
    return (env, vault, mock)

@pytest.fixture()
def ArbStratStablestETHETH():
    env = getEnvironment(network.show_active())
    strat = "StratStablestETHETH"

    impl = env.deployBalancerVault(strat, BalancerComposableAuraVault, [ComposableAuraHelper])
    vault = env.deployVaultProxy(strat, impl, BalancerComposableAuraVault)

    env.tradingModule.setTokenPermissions(
        vault.address, 
        ZERO_ADDRESS, 
        [True, set_dex_flags(0, BALANCER_V2=True, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.tradingModuleOwner})

    # Deploy mock contract necessary for liquidation tests
    mockImpl = env.deployBalancerVault(strat, MockBalancerComposableAuraVault, [ComposableAuraHelper])
    mock = env.deployVaultProxy(strat, impl, BalancerComposableAuraVault, mockImpl)
    mock = Contract.from_abi("MockBalancerComposableAuraVault", mock.address, interface.IBalancerComposableMockVault.abi)

    env.tradingModule.setTokenPermissions(
        mock.address, 
        ZERO_ADDRESS, 
        [True, set_dex_flags(0, BALANCER_V2=True, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.tradingModuleOwner})
    
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
