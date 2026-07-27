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
