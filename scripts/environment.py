from brownie import (
    accounts, 
    network,
    Balancer2TokenVault
)

EnvironmentConfig = {
    "goerli": {
        "notional": "0xD8229B55bD73c61D840d339491219ec6Fa667B0a",
        "balancerVault": "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
    }
}

class Environment:
    def __init__(self, config, deployer) -> None:
        self.config = config
        # Deploy balancer test pool

        Balancer2TokenVault.deploy(
            "Balancer 2-Token Vault"
            "B2T",
            config["notional"],
            1,
            True,
            True,
            config["balancerVault"],
            config["balancerETHUSDCPool"],
            {"from": deployer}
        )

def main():
    deployer = accounts.load(network.show_active().upper() + "_DEPLOYER")
    env = Environment(EnvironmentConfig[network.show_active()], deployer)