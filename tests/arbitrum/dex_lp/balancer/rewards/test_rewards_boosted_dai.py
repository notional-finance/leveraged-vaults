
import eth_abi
from brownie import Wei, accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.arbitrum.dex_lp.acceptance import DAIPrimaryContext, claim_rewards, reinvest_reward
from scripts.common import get_univ3_batch_data, DEX_ID, TRADE_TYPE

chain = Chain()

def test_claim_rewards_success(ArbStratAaveBoostedPoolDAIPrimary):
    claim_rewards(DAIPrimaryContext(*ArbStratAaveBoostedPoolDAIPrimary), 
        10e18,
        20e8, 
        accounts[0],
        {
            "BAL": 1062263825261381,
            "AURA": 4689034697665958
        }
    )