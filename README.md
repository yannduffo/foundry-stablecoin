# Foundry Stablecoin (DSC)

A minimal decentralized stablecoin pegged to 1 USD, inspired by MakerDAO/DAI — no governance, no fees.

## Properties

| Property | Choice |
|---|---|
| Stability | Pegged to USD (Chainlink price feeds) |
| Mechanism | Algorithmic |
| Collateral | Exogenous — wETH & wBTC |
| Collateralization | 200% minimum (liquidation threshold at 50%) |

## Contracts

- **`DecentralizedStableCoin.sol`** — ERC20 token, owned and controlled by DSCEngine
- **`DSCEngine.sol`** — core logic: deposit, mint, burn, redeem, liquidate
- **`OracleLib.sol`** — wraps Chainlink `latestRoundData()` and reverts if price data is stale (> 3h)

## Commands

```bash
forge build
forge test
forge test --match-contract DSCEngineTest -vv   # unit tests
forge test --match-contract InvariantsTest -vv  # invariant tests
```

## Liquidation

A position can be liquidated when its health factor drops below 1:

```
health factor = (collateral USD value × 50%) / DSC minted
```

Liquidators repay the debt and receive the collateral + 10% bonus.

---

## Learning notes

**Stablecoin taxonomy**
- *Relative stability*: pegged/anchored vs. floating
- *Stability mechanism*: governed vs. algorithmic
- *Collateral type*: endogenous (value from within the same ecosystem) vs. exogenous (value from outside — e.g. ETH, BTC)

**Foundry testing**
- *Fuzz tests* (stateless): random data fed into a single function
- *Invariant tests* (stateful): random data + random function call sequences across the whole contract

For invariant tests, prefer splitting into two folders rather than mixing configs:
```
test/fuzz/failOnRevert/
test/fuzz/continueOnRevert/
```
