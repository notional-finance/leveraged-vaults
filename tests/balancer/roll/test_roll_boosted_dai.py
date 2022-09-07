from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.helpers import check_invariant, enterMaturity
from scripts.common import get_deposit_params

chain = Chain()

def test_single_account_next_maturity_success(StratBoostedPoolDAIPrimary):
    (env, vault) = StratBoostedPoolDAIPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e18
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    maturity1 = enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"])
    maturity2 = env.notional.getActiveMarkets(2)[1][1]
    env.notional.rollVaultPosition(
        env.whales["DAI_EOA"],
        vault.address,
        primaryBorrowAmount * 1.1,
        maturity2,
        0,
        0,
        get_deposit_params(),
        {"from": env.whales["DAI_EOA"]}
    )
    check_invariant(env, vault, [env.whales["DAI_EOA"]], [maturity1, maturity2])