import json
import re
import eth_abi
import requests
from brownie import network, Contract, Wei, interface
from brownie.network.state import Chain

chain = Chain()
ALT_ETH_ADDRESS = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"

DEX_ID = {
    'UNUSED': 0,
    'UNISWAP_V2': 1,
    'UNISWAP_V3': 2,
    'ZERO_EX': 3,
    'BALANCER_V2': 4,
    'CURVE': 5,
    'NOTIONAL_VAULT': 6,
    'CURVE_V2': 7
}

TRADE_TYPE = {
    'EXACT_IN_SINGLE': 0,
    'EXACT_OUT_SINGLE': 1,
    'EXACT_IN_BATCH': 2,
    'EXACT_OUT_BATCH': 3
}

def getDependencies(bytecode):
    deps = set()
    for marker in re.findall("_{1,}[^_]*_{1,}", bytecode):
        deps.add(marker)
    result = list(deps)
    return result

def deployArtifact(path, constructorArgs, deployer, name, libs=None):
    with open(path, "r") as a:
        artifact = json.load(a)

    code = artifact["bytecode"]

    # Resolve dependencies
    deps = getDependencies(code)

    for dep in deps:
        library = dep.strip("_")
        code = code.replace(dep, libs[library][-40:])

    createdContract = network.web3.eth.contract(abi=artifact["abi"], bytecode=code)
    txn = createdContract.constructor(*constructorArgs).buildTransaction(
        {"from": deployer.address, "nonce": deployer.nonce}
    )
    # This does a manual deployment of a contract
    tx_receipt = deployer.transfer(data=txn["data"])

    return Contract.from_abi(name, tx_receipt.contract_address, abi=artifact["abi"], owner=deployer)

def get_vault_config(**kwargs):
    return [
        kwargs.get("flags", 0),  # 0: flags
        kwargs.get("currencyId", 1),  # 1: currency id
        kwargs.get("minAccountBorrowSize", 100),  # 2: min account borrow size
        kwargs.get("minCollateralRatioBPS", 900),  # 3: 20% collateral ratio
        kwargs.get("feeRate5BPS", 0),  # 4: 1% fee
        kwargs.get("liquidationRate", 102),  # 5: 2% liquidation discount
        kwargs.get("reserveFeeShare", 80),  # 6: 80% reserve fee share
        kwargs.get("maxBorrowMarketIndex", 2),  # 7: 20% reserve fee share
        kwargs.get("maxDeleverageCollateralRatioBPS", 1500),  # 8: 15% max collateral ratio
        kwargs.get("secondaryBorrowCurrencies", [0, 0]),  # 9: none set
        kwargs.get("maxRequiredAccountCollateralRatio", 20000),  # 10: none set
    ]

def set_flags(flags, **kwargs):
    binList = list(format(flags, "b").rjust(16, "0"))
    if "ENABLED" in kwargs:
        binList[0] = "1"
    if "ALLOW_ROLL_POSITION" in kwargs:
        binList[1] = "1"
    if "ONLY_VAULT_ENTRY" in kwargs:
        binList[2] = "1"
    if "ONLY_VAULT_EXIT" in kwargs:
        binList[3] = "1"
    if "ONLY_VAULT_ROLL" in kwargs:
        binList[4] = "1"
    if "ONLY_VAULT_DELEVERAGE" in kwargs:
        binList[5] = "1"
    if "ONLY_VAULT_SETTLE" in kwargs:
        binList[6] = "1"
    if "TRANSFER_SHARES_ON_DELEVERAGE" in kwargs:
        binList[7] = "1"
    if "ALLOW_REENTRNACY" in kwargs:
        binList[8] = "1"
    return int("".join(reversed(binList)), 2)

def get_updated_vault_settings(settings, **kwargs):
    return [
        kwargs.get("maxUnderlyingSurplus", settings["maxUnderlyingSurplus"]), 
        kwargs.get("settlementSlippageLimitPercent", settings["settlementSlippageLimitPercent"]), 
        kwargs.get("postMaturitySettlementSlippageLimitPercent", settings["postMaturitySettlementSlippageLimitPercent"]), 
        kwargs.get("emergencySettlementSlippageLimitPercent", settings["emergencySettlementSlippageLimitPercent"]),
        kwargs.get("maxPoolShare", settings["maxPoolShare"]), 
        kwargs.get("settlementCoolDownInMinutes", settings["settlementCoolDownInMinutes"]), 
        kwargs.get("oraclePriceDeviationLimitPercent", settings["oraclePriceDeviationLimitPercent"]),
        kwargs.get("poolSlippageLimitPercent", settings["poolSlippageLimitPercent"])
    ]

def get_univ2_data(path):
    return eth_abi.encode_abi(['(address[])'], [[path]])

def get_univ3_single_data(fee):
    return eth_abi.encode_abi(['(uint24)'], [[fee]])

def get_univ3_batch_data(path):
    pathTypes = []
    for idx in range(len(path)):
        if idx % 2 == 0:
            pathTypes.append('address')
        else:
            pathTypes.append('uint24')
    packedEncoder = eth_abi.codec.ABIEncoder(eth_abi.registry.registry_packed)
    return eth_abi.encode_abi(['(bytes)'], [[packedEncoder.encode_abi(
        pathTypes,
        path,
    )]])

def get_crv_batch_data(sellToken, buyToken, amount):
    router = interface.ICurveRouter("0xfA9a30350048B2BF66865ee20363067c66f67e58")
    routes = router.get_exchange_routing(sellToken, buyToken, amount)
    return eth_abi.encode_abi(
        ["(address[6],uint256[8])"],
        [[routes[0], routes[1]]]
    )

def get_deposit_trade_params(dexId, tradeType, amount, slippage, unwrap, exchangeData):
    return eth_abi.encode_abi(
        ['(uint256,(uint16,uint8,uint256,bool,bytes))'],
        [[
            Wei(amount),
            [
                dexId,
                tradeType,
                Wei(slippage),
                unwrap,
                exchangeData
            ]
        ]]
    )

def get_dynamic_trade_params(dexId, tradeType, slippage, unwrap, exchangeData):
    return eth_abi.encode_abi(
        ['(uint16,uint8,uint256,bool,bytes)'],
        [[
            dexId,
            tradeType,
            Wei(slippage),
            unwrap,
            exchangeData
        ]]
    )

def get_deposit_params(minPoolClaim=0, trade=bytes()):
    return eth_abi.encode_abi(
        ['(uint256,bytes)'],
        [[
            minPoolClaim,
            trade
        ]]
    )

def get_redeem_params(minPrimary, minSecondary, trade=None):
    if trade == None:
        trade = bytes()
    return eth_abi.encode_abi(
        ['(uint256,uint256,bytes)'],
        [[
            Wei(minPrimary),
            Wei(minSecondary),
            trade
        ]]
    )

def set_dex_flags(flags, **kwargs):
    binList = list(format(flags, "b").rjust(16, "0"))
    if "UNISWAP_V2" in kwargs:
        binList[1] = "1"
    if "UNISWAP_V3" in kwargs:
        binList[2] = "1"
    if "ZERO_EX" in kwargs:
        binList[3] = "1"
    if "BALANCER_V2" in kwargs:
        binList[4] = "1"
    if "CURVE" in kwargs:
        binList[5] = "1"
    if "NOTIONAL_VAULT" in kwargs:
        binList[6] = "1"
    if "CURVE_V2" in kwargs:
        binList[7] = "1"
    return int("".join(reversed(binList)), 2)

def set_trade_type_flags(flags, **kwargs):
    binList = list(format(flags, "b").rjust(16, "0"))
    if "EXACT_IN_SINGLE" in kwargs:
        binList[0] = "1"
    if "EXACT_OUT_SINGLE" in kwargs:
        binList[1] = "1"
    if "EXACT_IN_BATCH" in kwargs:
        binList[2] = "1"
    if "EXACT_OUT_BATCH" in kwargs:
        binList[3] = "1"
    return int("".join(reversed(binList)), 2)

def get_total_strategy_tokens(notional, vault, maturities):
    total = 0
    for m in maturities:
        total += notional.getVaultState(vault.address, m)["totalStrategyTokens"]
    return total

def get_all_past_maturities(notional, currencyId):
    res = []
    activeMaturities = get_all_active_maturities(notional, currencyId)
    i = 1671840000
    while i < activeMaturities[0]:
        res.append(i)
        i += 3600 * 24 * 90
    return res

def get_all_active_maturities(notional, currencyId):
    return [m[1] for m in notional.getActiveMarkets(currencyId)]

def get_remaining_strategy_tokens(address):
    resp = requests.post("https://api.thegraph.com/subgraphs/name/notional-finance/mainnet-v2",
        json={
            "query":"{\n  leveragedVaultMaturities {\n    id\n    remainingSettledStrategyTokens\n  }\n}",
        })
    data = list(filter(
        lambda x: 
            x["id"].split(":")[0].lower() == address.lower() and x["remainingSettledStrategyTokens"] != None, 
        resp.json()["data"]["leveragedVaultMaturities"]
    ))
    maturities = list(map(
        lambda x: Wei(x["id"].split(":")[1]), data
    ))
    amount = sum(list(map(lambda x: Wei(x["remainingSettledStrategyTokens"]), data)))
    return {
        "maturities": maturities,
        "amount": amount
    }
