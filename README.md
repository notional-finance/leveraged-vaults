# Leveraged Vaults

Notional Leveraged vaults are whitelisted yield strategies that are allowed to borrow from Notional and use a whitelisted yield strategy as collateral. Each strategy will have deposits and redemptions triggered within the Notional V3 leveraged vault framework. It will also be registered on Notional V3 before it can be considered "enabled". Notional governors can also disable a vault if necessary.

Additional Resources:
- https://docs.notional.finance/notional-v3/leveraged-vaults/what-are-leveraged-vaults

# Strategies

## Single Sided LP

A single sided LP strategy borrows one token from Notional and enters a Curve or Balancer V2 LP position single sided. Vaults may be optionally configured (via `TradingModule.setTokenPermissions`) to trade tokens via other DEXes on entry and exit. This may be used in cases where there is significantly more liquidity on other DEXes and entering single sided would cause excess slippage.

These vaults do not have maturities since the LP tokens do not mature. If an account is borrowing at a fixed rate to enter the position, their share of the LP tokens (i.e. vault shares) will be transferred 1-1 to the variable rate borrowing at maturity.

These vaults also have some administrative functions `claimRewardTokens` and `reinvestReward` as well as `emergencyExit` and `restoreVault`.

`claimRewardTokens` and `reinvestReward` will claim LP incentives earned via staking on Convex or Aura and reinvest them into additional LP tokens. These LP tokens will be donated to the vault at large therefore increasing the claim of a single vault share on the overall number of LP tokens.

`emergencyExit` allows a whitelisted account to pull funds from the LP pool proportionally in the case of a security emergency. This function will lock the vault and prevent any deposits, redemptions or liquidations (by disabling the `convertStrategyToUnderlying` method). `restoreVault` will deposit funds back into the pool and unlock the vault. This can only be executed by Notional governance.

### Read Only Re-entrancy

All Balancer V2 pools and Curve vaults that include native ETH are vulnerable to read only re-entrancy issues. An attacker can trigger a liquidation against a Notional vault from inside the `fallback` on either a Balancer V2 vault or a Curve vault that transfers ETH. To mitigate this risk, liquidations on each vault must first be proxied through the vault itself via a call to `BaseStrategyVault.deleverageAccount` where the `_checkReentrancyContext` function will revert if the liquidation is inside a re-entrancy context on Balancer V2 or Curve.

This is enforced by a flag set on the Notional V3 side, `ONLY_VAULT_DELEVERAGE`.

## Cross Currency

A cross currency vault borrows in one currency, sells that currency on a whitelisted DEX for another token and lends it back on Notional. This vault does have maturities and the lend and borrow maturities must match. Matured fCash is converted to variable lending or borrowing at maturity.

This vault uses [Wrapped fCash](https://github.com/notional-finance/wrapped-fcash) as an integration layer back to Notional. Because this vault will re-enter the Notional V3 context, it must have the `ALLOW_REENTRANCY` flag to be set when whitelisted on Notional.

# Trading

A singleton `TradingModule` contract is deployed on each chain to facilitate trading on various DEXes. While the TradingModule has its own configuration and storage (it is deployed behind an UUPS Upgradeable proxy), vaults execute trades via `delegatecall` to `executeTradeWithDynamicSlippage` or `executeTrade`. The relevant code for this is in the `TradeHandler` library.

In order to execute trades, an address must be whitelisted via `setTokenPermissions` on the `TradingModule`. This ensures that vaults may not arbitrarily buy and sell tokens on various vaults.

# Tests

Tests use [Foundry](https://book.getfoundry.sh/). You can run via `forge test`