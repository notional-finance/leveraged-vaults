import json
import re
import eth_abi
from brownie import network, Contract, Wei
from brownie.network.state import Chain

chain = Chain()

DEX_ID = {
    'UNUSED': 0,
    'UNISWAP_V2': 1,
    'UNISWAP_V3': 2,
    'ZERO_EX': 3,
    'BALANCER_V2': 4,
    'CURVE': 5,
    'NOTIONAL_VAULT': 6
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
        kwargs.get("minAccountBorrowSize", 100_000),  # 2: min account borrow size
        kwargs.get("minCollateralRatioBPS", 2000),  # 3: 20% collateral ratio
        kwargs.get("feeRate5BPS", 0),  # 4: 1% fee
        kwargs.get("liquidationRate", 104),  # 5: 4% liquidation discount
        kwargs.get("reserveFeeShare", 20),  # 6: 20% reserve fee share
        kwargs.get("maxBorrowMarketIndex", 2),  # 7: 20% reserve fee share
        kwargs.get("maxDeleverageCollateralRatioBPS", 4000),  # 8: 40% max collateral ratio
        kwargs.get("secondaryBorrowCurrencies", [0, 0]),  # 9: none set
        kwargs.get("maxRequiredAccountCollateralRatio", 30000),  # 10: none set
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
        kwargs.get("maxBalancerPoolShare", settings["maxBalancerPoolShare"]), 
        kwargs.get("settlementCoolDownInMinutes", settings["settlementCoolDownInMinutes"]), 
        kwargs.get("oraclePriceDeviationLimitPercent", settings["oraclePriceDeviationLimitPercent"]),
        kwargs.get("balancerPoolSlippageLimitPercent", settings["balancerPoolSlippageLimitPercent"])
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

def get_deposit_params(minBPT=0, secondaryBorrow=0, trade=bytes(0)):
    return eth_abi.encode_abi(
        ['(uint256,uint256,uint32,uint32,bytes)'],
        [[
            minBPT,
            secondaryBorrow,
            0, # secondaryBorrowLimit
            0, # secondaryRollLendLimit
            trade
        ]]
    )

def get_redeem_params(minPrimary, minSecondary, trade):
    return eth_abi.encode_abi(
        ['(uint256,uint256,bytes)'],
        [[
            Wei(minPrimary * 0.98),
            Wei(minSecondary * 0.98),
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