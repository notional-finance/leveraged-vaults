from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.helpers import check_invariant, enterMaturity
from scripts.common import get_deposit_params

chain = Chain()

def test_single_account_next_maturity_success(StratBoostedPoolUSDCPrimary):
    (env, vault) = StratBoostedPoolUSDCPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e6
    env.tokens["USDC"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["USDC"]})
    maturity1 = enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["USDC"])
    maturity2 = env.notional.getActiveMarkets(2)[1][1]
    env.notional.rollVaultPosition(
        env.whales["USDC"],
        vault.address,
        primaryBorrowAmount * 1.1,
        maturity2,
        0,
        0,
        get_deposit_params(),
        {"from": env.whales["USDC"]}
    )
    check_invariant(env, vault, [env.whales["USDC"]], [maturity1, maturity2])