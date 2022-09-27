from time import sleep
import eth_abi
import json
from brownie import (
    ZERO_ADDRESS,
    accounts, 
    network,
    interface,
    Contract,
    EmptyProxy,
    TradingModule,
    BalancerV2Adapter,
    nProxy,
    MockERC20,
    MockWstETH,
    MockAura,
    MockLiquidityGauge,
    MetaStable2TokenAuraHelper,
    MetaStable2TokenAuraVault
)
from brownie.network.state import Chain
from brownie.convert.datatypes import Wei

from scripts.common import deployArtifact

ETH_ADDRESS = "0x0000000000000000000000000000000000000000"
chain = Chain()

EnvironmentConfig = {
    "goerli": {
        "notional": "0xD8229B55bD73c61D840d339491219ec6Fa667B0a",
        "weightedPool2TokensFactory": "0xA5bf2ddF098bb0Ef6d120C98217dD6B141c74EE0",
        "metaStablePoolFactory": "0xA55F73E2281c60206ba43A3590dB07B8955832Be",
        "balancerVault": "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
        "balancerMinter": "0xdf0399539A72E2689B8B2DD53C3C2A0883879fDd",
        "ETHNOTEPool": {
            "id": "0xde148e6cc3f6047eed6e97238d341a2b8589e19e000200000000000000000053",
            "address": "0xdE148e6cC3F6047EeD6E97238D341A2b8589e19E",
            "liquidityGauge": ZERO_ADDRESS
        },
        "ETHUSDCPool": {
            "config": {
                "name": "50ETH-50USDC",
                "symbol": "50ETH-50USDC-BPT",
                "tokens": [
                    "0x04B9c40dF01bdc99dd2c31Ae4B232f20F4BBaC5B", # WETH
                    "0x31dd61Ac1B7A0bc88f7a58389c0660833a66C35c", # USDC
                ],
                "weights": [ 0.5e18, 0.5e18 ],
                "swapFeePercentage": 0.005e18, # 0.5%
                "oracleEnable": True,
                "initBalances": [ Wei(0.1e18), Wei(100e6) ]
            }
        },
        "BALETHPool": {
            "address": ZERO_ADDRESS # Not used on goerli
        },
        "veToken": "0x33A99Dcc4C85C014cf12626959111D5898bbCAbF",
        "feeDistributor": "0x7F91dcdE02F72b478Dc73cB21730cAcA907c8c44",
        "gaugeController": "0xBB1CE49b16d55A1f2c6e88102f32144C7334B116",
        "sNOTE": "0x9AcDB8100Aa74913f7702bf8b43128f36E6e3f22",
        "NOTE": "0xC5e91B01F9B23952821410Be7Aa3c45B6429C670",
        "WETH": "0xdFCeA9088c8A88A76FF74892C1457C17dfeef9C1",
        "USDC": "0x31dd61Ac1B7A0bc88f7a58389c0660833a66C35c",
        "stETH": "0x85ddf7aD3c038D868Dd2356907017219483129D6",
        "wstETH": "0xd2D24271030ecE6068C7E8874daF61fCC3225acB",
        "BAL": "0x9343F822Bfd32dFe488f6C369A5E40734986143A",
        "AURA": "0x6428dE1090f5a01246D37BEF5E29CC98eca06882",
    },
    "mainnet": {
        "notional": "0x1344A36A1B56144C3Bc62E7757377D288fDE0369",
        "balancerVault": "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
        "balancerMinter": "0x239e55F427D44C3cc793f49bFB507ebe76638a2b",
        "ETHUSDCPool": {
            "id": "0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019",
            "address": "0x96646936b91d6B9D7D0c47C496AfBF3D6ec7B6f8",
            "liquidityGauge": "0x9ab7b0c7b154f626451c9e8a68dc04f58fb6e5ce",
        },
        "ETHNOTEPool": {
            "id": "0x5122e01d819e58bb2e22528c0d68d310f0aa6fd7000200000000000000000163",
            "address": "0x5122e01d819e58bb2e22528c0d68d310f0aa6fd7",
            "liquidityGauge": "0x40ac67ea5bd1215d99244651cc71a03468bce6c0",
        },
        "BALETHPool": {
            "address": "0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56"
        },
        "veToken": "0xC128a9954e6c874eA3d62ce62B468bA073093F25",
        "feeDistributor": "0x26743984e3357eFC59f2fd6C1aFDC310335a61c9",
        "gaugeController": "0xC128468b7Ce63eA702C1f104D55A2566b13D3ABD",
        "sNOTE": "0x38DE42F4BA8a35056b33A746A6b45bE9B1c3B9d2",
        "WETH": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
        "delegateRegistry": "0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446"
    }
}

class Environment:
    def __init__(self, config, deployer) -> None:
        self.config = config
        self.deployer = deployer
        self.notional = interface.NotionalProxy(config["notional"])
        self.weth = interface.IERC20(config["WETH"])
        self.usdc = interface.IERC20(config["USDC"])
        self.note = interface.IERC20(config["NOTE"])
        self.stETH = interface.IERC20(config["stETH"])
        self.wstETH = interface.IERC20(config["wstETH"])
        self.bal = interface.IERC20(config["BAL"])
        self.aura = interface.IERC20(config["AURA"])
        self.tradingModule = Contract.from_abi(
            "TradingModule", "0xd250e8FB009Dc1783d121A48B619bEAA34c4913B", TradingModule.abi
        )
        self.balancerVault = interface.IBalancerVault(config["balancerVault"])
        self.pool2TokensFactory = self.loadPool2TokensFactory(config["weightedPool2TokensFactory"])
        self.metaStablePoolFactory = self.loadMetaStablePoolFactory(config["metaStablePoolFactory"])
        self.metaStablePool = interface.IMetaStablePool("0x945a00E88c662886241ce93D333009bEE2B3dF3F")
        self.metaStablePoolId = "0x945a00e88c662886241ce93d333009bee2b3df3f0002000000000000000001c2"
        self.metaStableGauge = Contract.from_abi(
            "LiquidityGauge", "0x6AEbe2d1e94504079702fF1AEA16975dADf24cD3", MockLiquidityGauge.abi
        )
        self.mockAuraBooster = Contract.from_abi(
            "AuraBooster", "0x69232d11F36C17813C1B01ed73d6a4841a205dfa", MockAura.abi
        )
        self.metaStableVault = Contract.from_abi(
            "MetaStable2TokenAuraVault", "0xE767769b639Af18dbeDc5FB534E263fF7BE43456", MetaStable2TokenAuraVault.abi
        )

    def deployTradingModule(self):
        self.balancerV2Adapter = BalancerV2Adapter.deploy(self.config["balancerVault"], {"from": self.deployer})
        impl = TradingModule.deploy(
            ZERO_ADDRESS,
            ZERO_ADDRESS,
            self.balancerV2Adapter.address,
            ZERO_ADDRESS,
            ZERO_ADDRESS,
            ZERO_ADDRESS,            
            {"from": self.deployer}
        )

        initData = impl.initialize.encode_input(self.deployer.address)
        self.proxy = nProxy.deploy(impl.address, initData, {"from": self.deployer})
        self.tradingModule = Contract.from_abi("TradingModule", self.proxy.address, interface.ITradingModule.abi)        

    def loadPool2TokensFactory(self, address):
        with open("./abi/balancer/poolFactory.json", "r") as f:
            abi = json.load(f)
        return Contract.from_abi('Weighted Pool 2 Token Factory', address, abi)

    def loadMetaStablePoolFactory(self, address):
        with open("./abi/balancer/MetaStablePoolFactory.json", "r") as f:
            abi = json.load(f)
        return Contract.from_abi('MetaStable Pool Factory', address, abi)

    def deployMockStETH(self):
        stETH = MockERC20.deploy("Notional stETH", "stETH", 18, 0, {"from": self.deployer})
        MockERC20.publish_source(stETH)

    def deployMockWstETH(self, stETH):
        wstETH = MockWstETH.deploy(stETH, {"from": self.deployer})
        MockWstETH.publish_source(wstETH)

    def deployMockBalToken(self):
        bal = MockERC20.deploy("Notional BAL", "BAL", 18, 0, {"from": self.deployer})
        MockERC20.publish_source(bal)

    def deployMockAuraToken(self):
        aura = MockERC20.deploy("Notional AURA", "AURA", 18, 0, {"from": self.deployer})
        MockERC20.publish_source(aura)

    def deployMockLiquidityGauge(self):
        gauge = MockLiquidityGauge.deploy(self.metaStablePool.address, {"from": self.deployer})
        MockLiquidityGauge.publish_source(gauge)

    def deployMockAura(self):
        aura = MockAura.deploy(
            1,
            self.metaStablePool.address,
            self.bal.address,
            self.aura.address,
            {"from": self.deployer}
        )
        MockAura.publish_source(aura)

    def deployTradingModule(self):
        emptyImpl = EmptyProxy.deploy({"from": self.deployer})
        EmptyProxy.publish_source(emptyImpl)
        proxy = nProxy.deploy(emptyImpl.address, bytes(0), {"from": self.deployer})
        nProxy.publish_source(proxy)

        impl = TradingModule.deploy(self.notional.address, proxy.address, {"from": self.deployer})
        TradingModule.publish_source(impl)
        emptyProxy = Contract.from_abi("EmptyProxy", proxy.address, EmptyProxy.abi)
        emptyProxy.upgradeTo(impl.address, {"from": self.deployer})        

    def deployMetaStableVault(self):
        #helper = MetaStable2TokenAuraHelper.deploy({"from": self.deployer})
        #MetaStable2TokenAuraHelper.publish_source(helper)

        deployArtifact(
            "scripts/artifacts/MetaStable2TokenAuraVault.json", 
            [
                self.notional.address,
                [
                    self.mockAuraBooster.address,
                    [
                        1,
                        self.metaStablePoolId,
                        self.metaStableGauge.address,
                        self.tradingModule.address,
                        3600 * 24 * 7,
                        "0x8638f94155c333fd7087c012Dc51B0528bb06035" # Treasury manager
                    ]
                ]
            ],
            self.deployer,
            "MetaStable2TokenAuraVault",
            {"$8eca08c2c2913e10a3819288bd975d0c9a$": "0x248aCAA436491b7CEFD03A006409a9Ad664AB45D"}
        )

        #impl = MetaStable2TokenAuraVault.deploy(
        #    self.notional.address,
        #    [
        #        self.mockAuraBooster.address,
        #        [
        #            1,
        #            self.metaStablePoolId,
        #            self.metaStableGauge.address,
        #            self.tradingModule.address,
        #            3600 * 24 * 7,
        #            "0x8638f94155c333fd7087c012Dc51B0528bb06035" # Treasury manager
        #        ]
        #    ],
        #    {"from": self.deployer}
        #)
        #MetaStable2TokenAuraVault.publish_source(impl)

        #proxy = nProxy.deploy(impl.address, bytes(0), {"from": self.deployer})
        #nProxy.publish_source(proxy)

    def initMetaStableVault(self):
        print(self.metaStableVault.initialize.encode_input(
            [
                "wstETH/ETH Aura Vault",
                1,
                [
                    100e18, # maxUnderlyingSurplus,
                    60, #oracleWindowInSeconds
                    5e6, #settlementSlippageLimitPercent 
                    10e6, #postMaturitySettlementSlippageLimitPercent 
                    10e6, #emergencySettlementSlippageLimitPercent 
                    5e6, #maxRewardTradeSlippageLimitPercent
                    1e4, #maxBalancerPoolShare
                    0.6e4, #balancerOracleWeight
                    60 * 6, #settlementCoolDownInMinutes
                    1e2, #feePercentage
                    500, #oraclePriceDeviationLimitPercent
                    9900 #balancerPoolSlippageLimitPercent
                ]
            ]
        ))

    def deployMetaStablePool(self):
        self.metaStablePoolFactory.create(
            "wstETH/ETH Balancer Pool",
            "wstETH-BPT",
            [self.wstETH.address, self.weth.address],
            50, # Amplification parameter 1e3 precision
            ["0x2d0605E29b7B7453Ea837662D21006B2908F9Fb7", ZERO_ADDRESS],
            [10800, 0],
            400000000000000,
            True,
            self.deployer,
            {"from": self.deployer}
        )

    def initMetaStablePool(self):
    #    self.wstETH.approve(self.balancerVault.address, 2**256 - 1, {"from": self.deployer})
        userData = eth_abi.encode_abi(
            ['uint256', 'uint256[]'],
            [0, [Wei(0.1e18), Wei(0.1e18)]]
        )

        self.balancerVault.joinPool(
            self.metaStablePoolId,
            self.deployer,
            self.deployer,
            (
                [self.wstETH.address, ETH_ADDRESS],
                [Wei(0.1e18), Wei(0.1e18)],
                userData,
                False
            ),
            {
                "from": self.deployer,
                "value": Wei(0.1e18)
            }
        )

    def deployBalancerPool(self, poolConfig, owner, deployer):
        # NOTE: owner is immutable, need to deploy the proxy first
        txn = self.pool2TokensFactory.create(
            poolConfig["name"],
            poolConfig["symbol"],
            poolConfig["tokens"],
            poolConfig["weights"],
            poolConfig["swapFeePercentage"],
            poolConfig["oracleEnable"],
            owner,
            {"from": deployer}
        )
        poolRegistered = txn.events["PoolRegistered"]
        return {
            "pool": interface.IBalancerPool(poolRegistered['poolAddress']),
            "id": poolRegistered['poolId'],
            "liquidityGauge": ZERO_ADDRESS # TODO: create gauge
        }

    def initBalancerPool(self, poolConfig, poolInstance, initializer):
        self.weth.approve(self.balancerVault.address, 2**256 - 1, {"from": initializer})
        self.usdc.approve(self.balancerVault.address, 2**256 - 1, {"from": initializer})
        userData = eth_abi.encode_abi(
            ['uint256', 'uint256[]'],
            [0, poolConfig["initBalances"]]
        )

        self.balancerVault.joinPool(
            poolInstance["id"],
            initializer.address,
            initializer.address,
            (
                poolConfig["tokens"],
                poolConfig["initBalances"],
                userData,
                False
            ),
            {"from": initializer}
        )

    def balancerSwap(self, poolId, fromToken, toToken, amount, trader):
        self.balancerVault.swap(
            [poolId, 0, fromToken, toToken, amount, 0x0], 
            [trader, False, trader, False],
            0, 
            chain.time() + 20000, 
            { "from": trader }
        )

def main():
    networkName = network.show_active()
    if networkName == "hardhat-fork":
        networkName = "mainnet"
    elif networkName == "hardhat-fork-goerli":
        networkName = "goerli"
    deployer = accounts.load(networkName.upper() + "_DEPLOYER")
    env = Environment(EnvironmentConfig[networkName], deployer)
    poolId = "0x945a00e88c662886241ce93d333009bee2b3df3f0002000000000000000001c2"
    for i in range(1024):
        try:
            if env.weth.balanceOf(deployer) == 0:
                print("wstETH -> weth")
                env.balancerSwap(poolId, env.wstETH.address, env.weth.address, 0.05e18, deployer)
            else:
                print("weth -> wstETH")
                env.balancerSwap(poolId, env.weth.address, env.wstETH.address, env.weth.balanceOf(deployer), deployer)
            sleep(120)
        except:
            sleep(120)

    #poolId = "0xde148e6cc3f6047eed6e97238d341a2b8589e19e000200000000000000000053"
    #for i in range(210):
    #    try:
    #        if env.weth.balanceOf(deployer) == 0:
    #            print("note -> weth")
    #            env.balancerSwap(poolId, env.note.address, env.weth.address, 0.1e8, deployer)
    #        else:
    #            print("weth -> note")
    #            env.balancerSwap(poolId, env.weth.address, env.note.address, env.weth.balanceOf(deployer), deployer)
    #        sleep(120)
    #    except:
    #        sleep(60)