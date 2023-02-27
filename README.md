| Module     | File                                     | Code | Comments | Total Lines | Complexity / Line |
| :--------- | :--------------------------------------- | ---: | -------: | ----------: | ----------------: |
| Adapters   | BalancerV2Adapter.sol                    |   80 |        2 |          91 |              17.5 |
| Adapters   | CurveAdapter.sol                         |   77 |        3 |          92 |              35.1 |
| Adapters   | UniV2Adapter.sol                         |   45 |        2 |          53 |              15.6 |
| Adapters   | UniV3Adapter.sol                         |   69 |        2 |          89 |              21.7 |
| Adapters   | ZeroExAdapter.sol                        |  194 |       29 |         240 |              19.6 |
| Balancer   | BalancerEvents.sol                       |   17 |        2 |          24 |               0.0 |
| Balancer   | BalancerStrategyBase.sol                 |   22 |        3 |          32 |               4.5 |
| Balancer   | BalancerVaultTypes.sol                   |  159 |       21 |         207 |               0.0 |
| External   | Boosted3TokenAuraHelper.sol              |  122 |       12 |         157 |               4.9 |
| External   | MetaStable2TokenAuraHelper.sol           |  124 |       10 |         155 |               4.8 |
| Global     | Constants.sol                            |   63 |       36 |         116 |               0.0 |
| Global     | DateTime.sol                             |   92 |       28 |         139 |              34.8 |
| Global     | Deployments.sol                          |   24 |        2 |          30 |               0.0 |
| Global     | Errors.sol                               |   23 |        2 |          26 |               0.0 |
| Global     | TypeConvert.sol                          |   19 |        1 |          25 |               5.3 |
| Global     | Types.sol                                |  308 |      233 |         586 |               0.0 |
| Internal   | BalancerConstants.sol                    |   25 |       23 |          51 |               0.0 |
| Internal   | BalancerVaultStorage.sol                 |   44 |        6 |          60 |               0.0 |
| Math       | Stable2TokenOracleMath.sol               |   80 |        9 |         106 |              11.2 |
| Math       | StableMath.sol                           |  230 |      100 |         391 |              16.5 |
| Mixins     | AuraStakingMixin.sol                     |   66 |        6 |          85 |              13.6 |
| Mixins     | BalancerOracleMixin.sol                  |   20 |        2 |          27 |               0.0 |
| Mixins     | Boosted3TokenPoolMixin.sol               |  110 |       15 |         148 |              10.9 |
| Mixins     | MetaStable2TokenVaultMixin.sol           |   25 |        3 |          32 |               0.0 |
| Mixins     | PoolMixin.sol                            |   19 |        1 |          24 |               0.0 |
| Mixins     | TwoTokenPoolMixin.sol                    |   66 |        9 |          88 |               6.1 |
| Oracles    | wstETHChainlinkOracle.sol                |   66 |        1 |          80 |               1.5 |
| Pool       | BalancerUtils.sol                        |  129 |        9 |         152 |               7.8 |
| Pool       | Boosted3TokenPoolUtils.sol               |  201 |       40 |         272 |               3.5 |
| Pool       | TwoTokenPoolUtils.sol                    |   94 |       30 |         143 |              14.9 |
| Proxy      | nBeaconProxy.sol                         |    7 |        2 |          12 |               0.0 |
| Proxy      | nProxy.sol                               |   13 |        2 |          19 |               0.0 |
| Proxy      | nUpgradeableBeacon.sol                   |    5 |        3 |          10 |               0.0 |
| Reward     | Boosted3TokenAuraRewardUtils.sol         |   92 |        8 |         116 |               5.4 |
| Reward     | TwoTokenAuraRewardUtils.sol              |   98 |       11 |         121 |               9.2 |
| Settlement | SettlementUtils.sol                      |  112 |       34 |         166 |               9.8 |
| Staking    | AuraStakingUtils.sol                     |   44 |        7 |          59 |               9.1 |
| Strategy   | StrategyUtils.sol                        |   70 |       12 |          92 |              25.7 |
| Trading    | TradeHandler.sol                         |  134 |       21 |         181 |              31.3 |
| Trading    | TradingModule.sol                        |  213 |       53 |         300 |              13.1 |
| Utils      | BoringOwnable.sol                        |   33 |       16 |          58 |              18.2 |
| Utils      | EmptyProxy.sol                           |   11 |        3 |          18 |               9.1 |
| Utils      | TokenUtils.sol                           |   45 |        5 |          60 |              15.6 |
| Vaults     | BaseStrategyVault.sol                    |  147 |       37 |         216 |              10.2 |
| Vaults     | Boosted3TokenAuraVault.sol               |  175 |       10 |         206 |               3.4 |
| Vaults     | CrossCurrencyfCashVault.sol              |  205 |       78 |         320 |               6.8 |
| Vaults     | MetaStable2TokenAuraVault.sol            |  176 |        7 |         204 |               4.0 |

# Running Unit Tests
### Install brownie
```
python3 -m pip install --user pipx
python3 -m pipx ensurepath
pipx install eth-brownie
```
https://eth-brownie.readthedocs.io/en/stable/install.html
### Install hardhat
```
yarn install
```
### Add mainnet-fork
* Add the following YAML block to ~/.brownie/network-config.yaml under development
```
- name: Hardhat (Mainnet Fork)
  id: mainnet-fork
  cmd: "npx.cmd hardhat node"
  host: http://127.0.0.1
  timeout: 120
  cmd_settings:
    port: 8545
    fork: mainnet
```
https://eth-brownie.readthedocs.io/en/stable/network-management.html#
### Execute tests
* Balancer tests
```
brownie test tests/dex_lp/balancer --network mainnet-fork
```
* Curve tests
```
brownie test tests/dex_lp/curve --network mainnet-fork
```
