# Deploying a New Vault - Single Sided LP

## Prerequisites

- Ensure that any required oracle adapters have been deployed and listed in the `tests/config.py` file before proceeding.
- If new tokens are being used as rewards or inside the pool, add them to the list inside `tests/config.py` as well.

## Add Configuration to SingleSidedLP.yml

Add the required configuration parameters to the [SingleSidedLP.yml](tests/SingleSidedLP/SingleSidedLPTests.yml). This is an annotated example:

```
# This is an arbitrum vault so it needs to go in that section of the file.
# The vault name will follow the pattern: <strategy name>:<protocol>:[<borrowed token>]/<other tokens>/...
# This naming convention is important because it is parsed on the front end to
# determine how to display it properly.
  - vaultName: SingleSidedLP:Convex:[WBTC]/tBTC
# The vault type will refer to the implementation that is deployed
    vaultType: Curve2TokenConvex
# Select a fork block for testing after the pool, booster and any necessary
# oracles have been deployed and listed.
    forkBlock: 215828254
# The list of valid symbols can be found in `tests/config.py`
    primaryBorrowCurrency: WBTC
# Get these addresses from the relevant website.
    rewardPool: "0x6B7B84F6EC1c019aF08C7A2F34D3C10cCB8A8eA6"
    poolToken: "0x755D6688AD74661Add2FB29212ef9153D40fcA46"
    lpToken: "0x755D6688AD74661Add2FB29212ef9153D40fcA46"
# This parameter is specific to different Curve pools
    curveInterface: V1
# List the reward tokens expected for claim reward tests. See the list
# of valid symbols in `tests/config.py`
    rewards: [CRV]
# List the required oracles for tests. See valid symbols in `tests/config.py`
    oracles: [WBTC, tBTC]
# These are default settings for the initialization of the strategy vault settings
    settings:
      maxPoolShare: 4000
      oraclePriceDeviationLimitPercent: 150
# These settings are used only in testing. Choose min and max deposits that are
# appropriate for the amount of liquidity on Notional at the fork block.
    setUp:
      minDeposit: 0.01e8
      maxDeposit: 1e8
      maxRelEntryValuation: 50
      maxRelExitValuation: 50
# These are the vault configuration settings, when listing a new vault set a lower
# minAccountBorrowSize, maxPrimaryBorrow and minCollateralRatioBPS so that we can
# run an initial liquidation test.
    config:
      feeRate5BPS: 20
      liquidationRate: 103
      reserveFeeShare: 80
      maxBorrowMarketIndex: 2
      minCollateralRatioBPS: 800
      maxRequiredAccountCollateralRatioBPS: 10_000
      maxDeleverageCollateralRatioBPS: 2_300
      minAccountBorrowSize: 0.05e8
      maxPrimaryBorrow: 0.1e8
```

## Run Tests Before Deployment

Execute `bin/runTests.sh` which will run the entire test suite. A new file will be created with the name: `tests/generated/arbitrum/SingleSidedLP_Convex_tBTC_xWBTC.t.sol`. Note the naming convention here, the `x` precedes the borrowed token.

## Deploy the Vault

Execute the deployment script:

`scripts/deployVault.sh <arbitrum|mainnet> Convex tBTC_xWBTC WBTC --update`

Replace the parameters according to the name of the file generated above.

This script will deploy both the implementation and proxy addresses for the vault. The proxy will be initialized to point to the implementation. It will also create or update the files with the pattern:

`<vault address>.initVault.json`: upload to Gnosis safe to initialize the vault
`<vault address>.updateConfig.json`: upload to Gnosis safe to list the vault on Notional, the vault will not appear on the UI until it is explicitly whitelisted on the UI.
`vaults.json`: Will add the vault name and address
`emergency/**`: Will generate or update emergency exit calls for all the affected vaults.

## Backfill Vault APY Data

Add the new vault address to the vault-apy package and backfill the APY data. Create a new view for the vault address and add it to the `whitelisted_views` table in the database so it will start to synchronize to the website.

## Create Test Vault Position

After the Gnosis safe transactions have been executed, update the UI in order to create an initial vault position. This is done in two files:

[default-pools.ts](https://github.com/notional-finance/notional-monorepo/blob/v3/prod/packages/core-entities/src/exchanges/default-pools.ts): add an appropriate entry for the underlying liquidity pool for the vault. Make sure to properly register the LP token metadata and any other tokens that the pool holds that are not already listed on Notional.

[whitelisted-vaults.ts](https://github.com/notional-finance/notional-monorepo/blob/v3/prod/packages/core-entities/src/config/whitelisted-vaults.ts): add the vault address the list.

Next, redeploy the registry cache to get the new LP pool data synchronizing. This can be done with the command:

`yarn nx publish-wrangler-manual registry --env prod`

Now, you can run the website locally in order to create a test vault position

`yarn nx serve web`

And navigate to localhost:3000 in your browser. Also be sure to check that the vault APY data shows up properly.

## Run Liquidation Test

Once a test position is created, you can increase the `minCollateralRatioBPS` in the `SingleSidedLP.yml` file at the top of this file. You can generate a new Gnosis safe JSON file using the command:

`scripts/updateConfig.sh <arbitrum|mainnet> Convex tBTC_xWBTC WBTC`

Once governance executes this update, the vault liquidator should pick up the under collateralized account and liquidate it.

## List the Vault on Prod

Create a PR using the changes made to the website code. Once merged, the vault will appear on the production site.


## Add Vault to Reward Reinvestment Bot

See PR: https://github.com/notional-finance/notional-monorepo/pull/968#pullrequestreview-2156755564

