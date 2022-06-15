from brownie import (
    accounts, 
    network,
    Balancer2TokenVault,
    BalancerBoostController
)

EnvironmentConfig = {
    "goerli": {
        "notional": "0xD8229B55bD73c61D840d339491219ec6Fa667B0a",
        "balancerVault": "0xBA12222222228d8Ba445958a75a0704d566BF2C8"
    },
    "mainnet": {
        "notional": "0x1344A36A1B56144C3Bc62E7757377D288fDE0369",
        "balancerVault": "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
        "ETHUSDCVault": {

        },
        "ETHNOTEVault": {

        }
    }
}

class Environment:
    def __init__(self, config, deployer) -> None:
        self.config = config
        # Deploy balancer test pool

        boostController = BalancerBoostController.deploy({"from": deployer})

        Balancer2TokenVault.deploy(
            "Balancer 2-Token Vault",
            config["notional"],
            3, # USDC
            True,
            True,
            [
                config["balancerVault"],
                config["balancerETHUSDCPool"],
                boostController.address,
                ILiquidityGauge liquidityGauge;
        IBalancerMinter balancerMinter;
        IVeBalDelegator veBalDelegator;
        ITradingModule tradingModule;
        WETH9 weth;
        uint256 oracleWindowInSeconds;
        uint256 settlementPeriod; // 1 week settlement
        uint256 maxSettlementPercentage; // 20%
        uint256 settlementCooldown; // 6 hour cooldown
            ],
            {"from": deployer}
        )

def main():
    networkName = network.show_active()
    if networkName == "hardhat-fork":
        networkName = "mainnet"
    deployer = accounts.load(networkName.upper() + "_DEPLOYER")
    env = Environment(EnvironmentConfig[networkName], deployer)