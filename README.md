# Foundry Stablecoin (DSC)

[![CI](https://github.com/yannduffo/foundry-stablecoin/actions/workflows/test.yml/badge.svg)](https://github.com/yannduffo/foundry-stablecoin/actions/workflows/test.yml)

A minimal decentralized stablecoin pegged to 1 USD, inspired by MakerDAO/DAI: no governance, no fees. The project is meant to run locally only (Anvil).

Built while following the [Advanced Foundry](https://updraft.cyfrin.io/courses/advanced-foundry) course on Cyfrin Updraft.

## Properties

| Property | Choice |
|---|---|
| Stability | Pegged to USD (Chainlink price feeds) |
| Mechanism | Algorithmic |
| Collateral | Exogenous: wETH & wBTC |
| Collateralization | 200% minimum (liquidation threshold at 50%) |

## Contracts

- **`DecentralizedStableCoin.sol`**: ERC20 token, owned and controlled by DSCEngine
- **`DSCEngine.sol`**: core logic (deposit, mint, burn, redeem, liquidate)
- **`OracleLib.sol`**: wraps Chainlink `latestRoundData()` and reverts if price data is stale (> 3h)
- **`DeployDSC.s.sol`**: deploys the whole system with mock tokens and mock price feeds, reverts outside of a local chain (chain id 31337)

## Getting started

```bash
git clone --recurse-submodules https://github.com/yannduffo/foundry-stablecoin.git
cd foundry-stablecoin

forge build
forge test                                     # full suite (invariants take ~30s)
forge test --no-match-contract InvariantsTest  # everything except invariants, fast
```

Deploy locally:

```bash
anvil   # in a first terminal
forge script script/DeployDSC.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --private-key <anvil_private_key>
```

## Liquidation

A position can be liquidated when its health factor drops below 1:

```
health factor = (collateral USD value × 50%) / DSC minted
```

Liquidators repay the debt and receive the collateral + 10% bonus. Liquidation works while the position is between 200% and 110% collateralized.

## Tests

- **Unit tests** (`test/unit/`): every DSCEngine function, including a fuzz test on liquidation with a random crashed ETH price
- **Invariant tests** (`test/fuzz/`): a handler drives random `deposit`, `mint`, `burn` and `redeem` calls (`fail_on_revert = true`), and after each call we check that:
  - the collateral value is always greater than the DSC total supply
  - the collateral recorded by the engine matches the tokens it actually holds
  - every DSC in circulation is backed by a user debt
  - no user ever falls below the minimum health factor

## Known limitations

These come from design decisions and are kept on purpose:

- **No bad debt handling**: below 110% collateralization, the collateral can't cover debt + bonus, so no liquidation is possible. Below 100%, the position is insolvent. The protocol relies on liquidators acting in time.
- **No price movements in invariant tests**: a sharp price crash would break the main invariant, as explained above.
- **Oracle**: a single 3h staleness timeout for every feed. If a price is stale, the whole protocol freezes (including repaying and redeeming).
- **Educational project**: local only, not audited.

---

## Learning notes

**Stablecoin taxonomy**
- *Relative stability*: pegged/anchored vs. floating
- *Stability mechanism*: governed vs. algorithmic
- *Collateral type*: endogenous (value from within the same ecosystem) vs. exogenous (value from outside, e.g. ETH, BTC)

**Foundry testing**
- *Fuzz tests* (stateless): random data fed into a single function
- *Invariant tests* (stateful): random data + random function call sequences across the whole contract
