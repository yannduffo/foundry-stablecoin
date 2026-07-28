# Foundry stablecoin project

## Technical def

A stablecoin has 3 main properties : 
- Relative Stability : Pegged/Anchored or Floating
- Stability Mechanism : Governed or Alogorithmic
- Collateral Type : Endogenous (collateral value from the same ecosystem) or Exogenous (collateral value existing outside of the stablecoin project)

## Our choices for our stablecoin

- Pegged to 1USD (using a Chainlink priceFeed to always exhange the good ETH or BTC amount for 1$ of our stablecoin)
- Algorothmic (collateral minting)
- Exogenous (wETH & wBTC as collateral)

## Note about foundry : 
- Foundry fuzz tests : stateless fuzz test -> random data over 1 function
- Foundry invariant tests : statefull fuzz test -> random data & random function calls to many functions

For invariants tests, we either use `fail_on_revert = true` or `fail_on_revert = false`. A better practice is to make 2 folders : `fuzz/continueOnRevert/` and  `fuzz/failOnRevert` so we don't mix them.

## To do to clean project

- Faire plus d'unit test
- Finir les commentaires des fonctions
- MAJ readme

questions : 
- comment est-ce qu'on halt le system si on a une stale dans le priceFeed : j'ai pas compris comment on influence le contrat (mais si je crois qu'on passe par la lib tout le temps mais jsplus ou)
