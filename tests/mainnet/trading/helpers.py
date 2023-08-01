import eth_abi
from brownie.convert import to_bytes
from brownie.network.state import Chain
from scripts.common import TRADE_TYPE

chain = Chain()

def balancer_trade_exact_in_single(sellToken, buyToken, amount, limit, poolId):
    deadline = chain.time() + 20000
    return [
        TRADE_TYPE["EXACT_IN_SINGLE"], 
        sellToken, 
        buyToken, 
        amount, 
        limit, 
        deadline, 
        eth_abi.encode_abi(
            ["(bytes32)"],
            [[to_bytes(poolId, "bytes32")]]
        )
    ]

def balancer_trade_exact_in_batch(sellToken, buyToken, amount, swaps, assets, limits):
    deadline = chain.time() + 20000
    return [
        TRADE_TYPE["EXACT_IN_BATCH"], 
        sellToken, 
        buyToken, 
        amount, 
        0, 
        deadline, 
        eth_abi.encode_abi(
            ['((bytes32,uint256,uint256,uint256,bytes)[],address[],int256[])'],
            [[swaps, assets, limits]]
        )
    ]    
