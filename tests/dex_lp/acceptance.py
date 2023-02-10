import math
import pytest
import brownie
from brownie import ZERO_ADDRESS, accounts
from brownie.network.state import Chain
from scripts.common import (
    get_updated_vault_settings, 
    get_deposit_params, 
    get_redeem_params, 
    get_dynamic_trade_params,
    get_all_active_maturities
)
from tests.dex_lp.helpers import (
    snapshot_invariants, 
    check_invariants, 
    check_account,
    enterMaturity, 
    exitVaultPercent,
    convert_to_underlying,
    get_expected_pool_claim_amount,
    get_expected_borrow_amount
)

chain = Chain()

class ETHPrimaryContext:
    def __init__(self, env, vault, mock) -> None:
        self.env = env
        self.vault = vault
        self.mock = mock
        self.currencyId = 1
        self.token = ZERO_ADDRESS
        self.whale = env.whales["ETH"]
        self.primaryPrecision = 1e18
    def balance(self, account):
        return account.balance()
    def approve(self, account, target):
        pass
    def transfer(self, dest, amount):
        self.whale.transfer(dest, amount)

class DAIPrimaryContext:
    def __init__(self, env, vault, mock) -> None:
        self.env = env
        self.vault = vault
        self.mock = mock
        self.currencyId = 2
        self.token = env.tokens["DAI"]
        self.whale = env.whales["DAI_EOA"]
        self.token.approve(env.notional.address, 2**256-1, {"from": self.whale})
        self.primaryPrecision = 10**self.token.decimals()
    def balance(self, account):
        return self.token.balanceOf(account)
    def approve(self, account, target):
        self.token.approve(target, 2**256-1, {"from": account})
    def transfer(self, dest, amount):
        self.token.transfer(dest, amount, {"from": self.whale})

class USDCPrimaryContext:
    def __init__(self, env, vault, mock) -> None:
        self.env = env
        self.vault = vault
        self.mock = mock
        self.currencyId = 3
        self.token = env.tokens["USDC"]
        self.whale = env.whales["USDC"]
        self.token.approve(env.notional.address, 2**256-1, {"from": self.whale})
        self.primaryPrecision = 10**self.token.decimals()
    def balance(self, account):
        return self.token.balanceOf(account)
    def approve(self, account, target):
        self.token.approve(target, 2**256-1, {"from": account})
    def transfer(self, dest, amount):
        self.token.transfer(dest, amount, {"from": self.whale})

def deposit(context, ops):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    primaryPrecision = context.primaryPrecision
    maturities = get_all_active_maturities(notional, currencyId)
    snapshot = snapshot_invariants(env, vault, currencyId)
    depositors = set()
    for op in ops:
        depositAmount = op[0]
        primaryBorrowAmount = op[1]
        depositor = op[2]
        context.approve(depositor, notional.address)
        context.transfer(depositor, depositAmount)
        if depositor not in depositors:
            depositors.add(depositor)
        maturity = maturities[op[3]]
        depositParams = op[4]
        primaryPercent = op[5]
        depositTradeFunc = op[6]
        expectedBorrowAmount = get_expected_borrow_amount(env, currencyId, maturity, primaryBorrowAmount)
        expectedPoolClaimAmount = get_expected_pool_claim_amount(
            context, depositAmount, expectedBorrowAmount, primaryPercent, depositTradeFunc
        )
        enterMaturity(env, vault, currencyId, maturity, depositAmount, primaryBorrowAmount, depositor, False, depositParams)
        vaultAccount = notional.getVaultAccount(depositor, vault.address)
        vaultState = notional.getVaultState(vault.address, maturity)
        assert vaultAccount["fCash"] == -primaryBorrowAmount
        strategyTokens = vaultAccount["vaultShares"] * vaultState["totalStrategyTokens"] / vaultState["totalVaultShares"]
        assert pytest.approx(vault.convertStrategyTokensToPoolClaim(strategyTokens), rel=1e-5) == expectedPoolClaimAmount
        underlyingValue = vault.convertStrategyToUnderlying(depositor, vaultAccount["vaultShares"], maturity)
        assert pytest.approx(underlyingValue, rel=5e-2) == depositAmount + primaryBorrowAmount * primaryPrecision / 1e8
    check_invariants(env, vault, list(depositors), currencyId, snapshot)

def redeem(context, ops):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    maturities = get_all_active_maturities(notional, currencyId)
    maturity = maturities[0]
    snapshot = snapshot_invariants(env, vault, currencyId)
    depositors = set()
    for op in ops:
        depositAmount = op[0]
        primaryBorrowAmount = op[1]
        depositor = op[2]
        context.approve(depositor, notional.address)
        context.transfer(depositor, depositAmount)
        if depositor not in depositors:
            depositors.add(depositor)
        maturity = maturities[op[3]]
        redeemParams = op[4]
        percentages = op[5]
        enterMaturity(env, vault, currencyId, maturity, depositAmount, primaryBorrowAmount, depositor)
        firstRedeem = True
        primaryAmountBefore = context.balance(depositor)
        totalfCashRepaid = 0
        for percentage in percentages:
            vaultShares = notional.getVaultAccount(depositor, vault.address)["vaultShares"]
            if firstRedeem:
                # Min entry blocks
                with brownie.reverts():
                    exitVaultPercent(env, vault, depositor, percentage, redeemParams, True)
                chain.mine(5)

            (sharesRedeemed, fCashRepaid) = exitVaultPercent(env, vault, depositor, percentage, redeemParams)
            totalfCashRepaid += fCashRepaid
            check_account(env, vault, depositor, vaultShares - sharesRedeemed, primaryBorrowAmount - totalfCashRepaid)
            assert pytest.approx(context.balance(depositor) - primaryAmountBefore, rel=5e-2) == depositAmount * percentage
            firstRedeem = False
    check_invariants(env, vault, depositors, currencyId, snapshot)

def normal_settlement(context, depositAmount, primaryBorrowAmount, maturityIndex, depositor, operator, redeemParams, percent):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    maturity = env.notional.getActiveMarkets(currencyId)[maturityIndex][1]
    context.approve(depositor, notional.address)
    context.transfer(depositor, depositAmount)
    context.approve(operator, notional.address)
    context.transfer(operator, depositAmount)
    snapshot = snapshot_invariants(env, vault, currencyId)
    enterMaturity(env, vault, currencyId, maturity, depositAmount, primaryBorrowAmount, depositor)

    # Enter settlement window
    settlementWindow = vault.getStrategyContext()["baseStrategy"]["settlementPeriodInSeconds"]
    chain.sleep(maturity - settlementWindow + 1 - chain.time())
    chain.mine(5)
    # Disable oracle freshness check
    env.tradingModule.setMaxOracleFreshness(2 ** 32 - 1, {"from": env.notional.owner()})

    tokensToRedeem = math.floor(env.notional.getVaultState(vault.address, maturity)["totalStrategyTokens"] * percent)
    tradeParams = redeemParams[2]
    if tradeParams != None:
        redeemParamsEncoded = get_redeem_params(
            redeemParams[0], 
            redeemParams[1], 
            get_dynamic_trade_params(
                tradeParams[0], tradeParams[1], tradeParams[2], tradeParams[3], tradeParams[4]
            )
        )
    else:
        redeemParamsEncoded = get_redeem_params(redeemParams[0], redeemParams[1])

    # Can't settle without the proper role
    with brownie.reverts():
        vault.settleVaultNormal.call(maturity, tokensToRedeem, redeemParamsEncoded, {"from": operator})

    # Only Notional owner can grant roles
    with brownie.reverts():
        vault.grantRole.call(vault.getRoles()["normalSettlement"], operator, {"from": context.whale})
    vault.grantRole(vault.getRoles()["normalSettlement"], operator, {"from": env.notional.owner()})

    # Can't settle with bad slippage setting
    if tradeParams != None:
        with brownie.reverts():
            badSlippage = vault.getStrategyContext()["baseStrategy"]["vaultSettings"]["settlementSlippageLimitPercent"] + 1
            vault.settleVaultNormal.call(maturity, tokensToRedeem, get_redeem_params(
                redeemParams[0], 
                redeemParams[1], 
                get_dynamic_trade_params(
                    tradeParams[0], tradeParams[1], badSlippage, tradeParams[3], tradeParams[4]
                )
            ), {"from": operator})

    # Test settlement (settle half)
    vaultState = env.notional.getVaultState(vault.address, maturity)
    underlyingCashBefore = vault.convertStrategyToUnderlying(depositor, vaultState["totalStrategyTokens"], maturity)
    vault.settleVaultNormal(maturity, tokensToRedeem, redeemParamsEncoded, {"from": operator})
    vaultState = env.notional.getVaultState(vault.address, maturity)
    totalUnderlyingCash = convert_to_underlying(env, currencyId, vaultState["totalAssetCash"], context.primaryPrecision)
    assert pytest.approx(totalUnderlyingCash, rel=1e-2) == underlyingCashBefore * percent
    assert vaultState["totalStrategyTokens"] == vaultState["totalVaultShares"] - tokensToRedeem

    # Can't deposit during settlement (totalAssetCash > 0)
    with brownie.reverts():
        enterMaturity(env, vault, currencyId, maturity, depositAmount, primaryBorrowAmount, operator, True)

    # Redeem is allowed
    if tradeParams != None:
        redeemParamsEncoded2 = get_redeem_params(
            redeemParams[0], 
            redeemParams[1], 
            get_dynamic_trade_params(
                tradeParams[0], tradeParams[1], badSlippage, tradeParams[3], tradeParams[4]
            )
        )
    else:
        redeemParamsEncoded2 = get_redeem_params(redeemParams[0], redeemParams[1])

    exitVaultPercent(env, vault, depositor, 1.0, redeemParamsEncoded2)
    chain.undo()

    tokensToRedeem = env.notional.getVaultState(vault.address, maturity)["totalStrategyTokens"]

    # Settlement cool down
    with brownie.reverts():
        vault.settleVaultNormal.call(maturity, tokensToRedeem, redeemParamsEncoded, {"from": operator})

    chain.sleep(3600 * 10)
    chain.mine(5)    

    # Can't redeem beyond maxUnderlyingSurplus
    settings = vault.getStrategyContext()["baseStrategy"]["vaultSettings"]
    oldMaxUnderlyingSurplus = settings["maxUnderlyingSurplus"]
    vault.setStrategyVaultSettings(
        get_updated_vault_settings(settings, maxUnderlyingSurplus=0), {"from": env.notional.owner()}
    )
    with brownie.reverts():
        vault.settleVaultNormal.call(maturity, tokensToRedeem, redeemParamsEncoded, {"from": operator})
    vault.setStrategyVaultSettings(
        get_updated_vault_settings(settings, maxUnderlyingSurplus=oldMaxUnderlyingSurplus), {"from": env.notional.owner()}
    )

    # Complete settlement
    vault.settleVaultNormal(maturity, tokensToRedeem, redeemParamsEncoded, {"from": operator})
    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert vaultState["totalStrategyTokens"] == 0
    assert vaultState["isSettled"] == False
    totalUnderlyingCash = convert_to_underlying(env, currencyId, vaultState["totalAssetCash"], context.primaryPrecision)
    assert pytest.approx(totalUnderlyingCash, rel=1e-2) == underlyingCashBefore
    check_invariants(env, vault, [depositor], currencyId, snapshot)

def post_maturity_settlement(context, depositAmount, primaryBorrowAmount, maturityIndex, depositor, operator, redeemParams, percent):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    maturity = env.notional.getActiveMarkets(currencyId)[maturityIndex][1]
    context.approve(depositor, notional.address)
    context.transfer(depositor, depositAmount)
    context.approve(operator, notional.address)
    context.transfer(operator, depositAmount)
    snapshot = snapshot_invariants(env, vault, currencyId)
    enterMaturity(env, vault, currencyId, maturity, depositAmount, primaryBorrowAmount, depositor)

    tokensToRedeem = math.floor(env.notional.getVaultState(vault.address, maturity)["totalStrategyTokens"] * percent)
    tradeParams = redeemParams[2]
    if tradeParams != None:
        redeemParamsEncoded = get_redeem_params(
            redeemParams[0], 
            redeemParams[1], 
            get_dynamic_trade_params(
                tradeParams[0], tradeParams[1], tradeParams[2], tradeParams[3], tradeParams[4]
            )
        )
    else:
        redeemParamsEncoded = get_redeem_params(redeemParams[0], redeemParams[1]) 

    # Can't call settleVaultPostMaturity before maturity
    with brownie.reverts():
        vault.settleVaultPostMaturity.call(maturity, tokensToRedeem, redeemParamsEncoded, {"from": env.notional.owner()})

    chain.sleep(maturity + 1 - chain.time())
    chain.mine(5)
    # Disable oracle freshness check
    env.tradingModule.setMaxOracleFreshness(2 ** 32 - 1, {"from": env.notional.owner()})

    # Can't call settleVaultPostNormal after maturity
    with brownie.reverts():
        vault.grantRole.call(vault.getRoles()["normalSettlement"], operator, {"from": env.notional.owner()})
        vault.settleVaultNormal.call(maturity, tokensToRedeem, redeemParamsEncoded, {"from": operator})

    # Only Notional owner can grant roles
    with brownie.reverts():
        vault.grantRole.call(vault.getRoles()["postMaturitySettlement"], operator, {"from": context.whale})
    vault.grantRole(vault.getRoles()["postMaturitySettlement"], operator, {"from": env.notional.owner()})

    # Can't settle with bad slippage setting
    if tradeParams != None:
        with brownie.reverts():
            badSlippage = vault.getStrategyContext()["baseStrategy"]["vaultSettings"]["postMaturitySettlementSlippageLimitPercent"] + 1
            vault.settleVaultPostMaturity.call(maturity, tokensToRedeem, get_redeem_params(
                redeemParams[0], 
                redeemParams[1], 
                get_dynamic_trade_params(
                    tradeParams[0], tradeParams[1], badSlippage, tradeParams[3], tradeParams[4]
                )
            ), {"from": operator})

    vaultState = env.notional.getVaultState(vault.address, maturity)
    underlyingCashBefore = vault.convertStrategyToUnderlying(depositor, vaultState["totalStrategyTokens"], maturity)

    vault.settleVaultPostMaturity(maturity, tokensToRedeem, redeemParamsEncoded, {"from": operator})
    vaultState = env.notional.getVaultState(vault.address, maturity)
    totalUnderlyingCash = convert_to_underlying(env, currencyId, vaultState["totalAssetCash"], context.primaryPrecision)
    assert pytest.approx(totalUnderlyingCash, rel=1e-2) == underlyingCashBefore * percent
    assert vaultState["totalStrategyTokens"] == vaultState["totalVaultShares"] - tokensToRedeem
    assert vaultState["isSettled"] == False

    tokensToRedeem = env.notional.getVaultState(vault.address, maturity)["totalStrategyTokens"]

    # Complete settlement
    vault.settleVaultPostMaturity(maturity, tokensToRedeem - 1e8, redeemParamsEncoded, {"from": operator})
    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert vaultState["totalStrategyTokens"] == 1e8
    assert vaultState["isSettled"] == True
    totalUnderlyingCash = convert_to_underlying(env, currencyId, vaultState["totalAssetCash"], context.primaryPrecision)
    assert pytest.approx(totalUnderlyingCash, rel=1e-2) == underlyingCashBefore
    check_invariants(env, vault, [depositor], currencyId, snapshot)

def emergency_settlement(context, depositAmount, primaryBorrowAmount, maturityIndex, depositor, operator, redeemParams):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    maturity = env.notional.getActiveMarkets(currencyId)[maturityIndex][1]
    context.approve(depositor, notional.address)
    context.transfer(depositor, depositAmount)
    context.approve(operator, notional.address)
    context.transfer(operator, depositAmount)
    snapshot = snapshot_invariants(env, vault, currencyId)
    enterMaturity(env, vault, currencyId, maturity, depositAmount, primaryBorrowAmount, depositor)

    tradeParams = redeemParams[2]
    if tradeParams != None:
        redeemParamsEncoded = get_redeem_params(
            redeemParams[0], 
            redeemParams[1], 
            get_dynamic_trade_params(
                tradeParams[0], tradeParams[1], tradeParams[2], tradeParams[3], tradeParams[4]
            )
        )
    else:
        redeemParamsEncoded = get_redeem_params(redeemParams[0], redeemParams[1])

    # Role check
    with brownie.reverts():
        vault.settleVaultEmergency.call(maturity, redeemParamsEncoded, {"from": operator})

    # Only Notional owner can grant roles
    with brownie.reverts():
        vault.grantRole.call(vault.getRoles()["emergencySettlement"], operator, {"from": context.whale})
    vault.grantRole(vault.getRoles()["emergencySettlement"], operator, {"from": env.notional.owner()})

    # Can't settle with bad slippage setting
    if tradeParams != None:
        with brownie.reverts():
            badSlippage = vault.getStrategyContext()["baseStrategy"]["vaultSettings"]["emergencySettlementSlippageLimitPercent"] + 1
            vault.settleVaultEmergency.call(maturity, get_redeem_params(
                redeemParams[0], 
                redeemParams[1], 
                get_dynamic_trade_params(
                    tradeParams[0], tradeParams[1], badSlippage, tradeParams[3], tradeParams[4]
                )
            ), {"from": operator})

    # Cannot get emergency settlement amount if we are below the threshold
    with brownie.reverts():
        vault.getEmergencySettlementPoolClaimAmount(maturity)

    settings = vault.getStrategyContext()["baseStrategy"]["vaultSettings"]
    vault.setStrategyVaultSettings(get_updated_vault_settings(settings, maxPoolShare=0), {"from": env.notional.owner()})

    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert vault.getEmergencySettlementPoolClaimAmount(maturity) == vault.convertStrategyTokensToPoolClaim(vaultState["totalStrategyTokens"])
    underlyingCashBefore = vault.convertStrategyToUnderlying(depositor, vaultState["totalStrategyTokens"], maturity)

    vault.settleVaultEmergency(maturity, redeemParamsEncoded, {"from": operator})

    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert vaultState["totalStrategyTokens"] <= 1 # Rounding error?
    totalUnderlyingCash = convert_to_underlying(env, currencyId, vaultState["totalAssetCash"], context.primaryPrecision)
    assert pytest.approx(totalUnderlyingCash, rel=1e-2) == underlyingCashBefore
    check_invariants(env, vault, [depositor], currencyId, snapshot)

def roll(context, depositAmount, primaryBorrowAmount, depositor, maturityIndex1, maturityIndex2):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    maturity1 = env.notional.getActiveMarkets(currencyId)[maturityIndex1][1]
    maturity2 = env.notional.getActiveMarkets(currencyId)[maturityIndex2][1]
    snapshot = snapshot_invariants(env, vault, currencyId)
    context.approve(depositor, notional.address)
    context.transfer(depositor, depositAmount)
    enterMaturity(env, vault, currencyId, maturity1, depositAmount, primaryBorrowAmount, depositor)
    notional.rollVaultPosition(
        depositor,
        vault.address,
        primaryBorrowAmount * 1.1,
        maturity2,
        0,
        0,
        0,
        get_deposit_params(),
        {"from": depositor}
    )
    check_invariants(env, vault, [depositor], currencyId, snapshot)

def claim_rewards(context, depositAmount, primaryBorrowAmount, depositor, expectedRewardTokenAmounts):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId    
    maturity = notional.getActiveMarkets(currencyId)[0][1]
    context.approve(depositor, notional.address)
    context.transfer(depositor, depositAmount)
    snapshot = snapshot_invariants(env, vault, currencyId)
    enterMaturity(env, vault, currencyId, maturity, depositAmount, primaryBorrowAmount, depositor)
    chain.sleep(3600 * 24 * 365)
    chain.mine()

    currentBalances = {}
    for key in expectedRewardTokenAmounts:
        currentBalances[key] = env.tokens[key].balanceOf(vault.address)

    # Cannot claim without the proper role assigned
    with brownie.reverts():
        vault.claimRewardTokens.call({"from": depositor})

    # Only Notional owner can grant roles
    with brownie.reverts():
        vault.grantRole.call(vault.getRoles()["rewardReinvestment"], depositor, {"from": context.whale})
    vault.grantRole(vault.getRoles()["rewardReinvestment"], depositor, {"from": env.notional.owner()})
    
    ret = vault.claimRewardTokens.call({"from": depositor})
    vault.claimRewardTokens({"from": depositor})

    i = 0
    for key in expectedRewardTokenAmounts:
        assert env.tokens[key].balanceOf(vault.address) - currentBalances[key] > 0
        assert env.tokens[key].balanceOf(vault.address) - currentBalances[key] >= expectedRewardTokenAmounts[key]
        assert ret[i] == env.tokens[key].balanceOf(vault.address) - currentBalances[key]
        i += 1
    check_invariants(env, vault, [depositor], currencyId, snapshot)

def reinvest_reward(context, depositor, rewardToken, rewardAmount, rewardParams, poolClaimBefore, expectedPoolClaimAmount, shouldRevert=False):
    env = context.env
    vault = context.vault
    currencyId = context.currencyId   
    env.tokens[rewardToken].transfer(vault.address, rewardAmount, {"from": env.whales[rewardToken]})
    snapshot = snapshot_invariants(env, vault, currencyId)

    # Cannot reinvest without the proper role assigned
    with brownie.reverts():
        vault.reinvestReward.call(rewardParams, {"from": depositor})

    # Only Notional owner can grant roles
    with brownie.reverts():
        vault.grantRole.call(vault.getRoles()["rewardReinvestment"], depositor, {"from": context.whale})
    vault.grantRole(vault.getRoles()["rewardReinvestment"], depositor, {"from": env.notional.owner()})
    
    if shouldRevert == True:
        with brownie.reverts():
            vault.reinvestReward.call(rewardParams, {"from": depositor})
    else:
        vault.reinvestReward(rewardParams, {"from": depositor})
        poolClaimAfter = vault.getStrategyContext()["baseStrategy"]["vaultState"]["totalPoolClaim"]
        assert poolClaimAfter - poolClaimBefore >= expectedPoolClaimAmount

    vault.revokeRole(vault.getRoles()["rewardReinvestment"], depositor, {"from": env.notional.owner()})
    check_invariants(env, vault, [], currencyId, snapshot)

def leverage_ratio_too_high(context, depositAmount, primaryBorrowAmount):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    depositor = context.whale
    maturities = [m[1] for m in notional.getActiveMarkets(currencyId)]
    with brownie.reverts("Insufficient Collateral"):
        enterMaturity(env, vault, currencyId, maturities[0], depositAmount, primaryBorrowAmount, depositor, True)

def pool_share_too_high(context, depositAmount, primaryBorrowAmount):
    env = context.env
    vault = context.vault
    settings = vault.getStrategyContext()["baseStrategy"]["vaultSettings"]
    # Only Notional owner can change settings
    with brownie.reverts():
        vault.setStrategyVaultSettings.call(
            get_updated_vault_settings(settings, maxPoolShare=0),
            {"from": accounts[0]}
        )
    vault.setStrategyVaultSettings(
        get_updated_vault_settings(settings, maxPoolShare=0),
        {"from": env.notional.owner()}
    )
    with brownie.reverts():
        enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"], True)
