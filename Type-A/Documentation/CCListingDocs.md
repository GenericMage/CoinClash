# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract, implemented in Solidity (^0.8.2), manages buy/sell orders, payouts, and voetLongPayout(uint256)**: Returns `LongPayoutStruct`.
- **getShortPayout(uint256)**: Returns `ShortPayoutStruct`.
- **getBuyOrderCore(uint256)**: Returns `makerAddress`, `recipientAddress`, `status`.
- **getBuyOrderPricing(uint256)**: Returns `maxPrice`, `minPrice`.
- **getBuyOrderAmounts(uint256)**: Returns `pending`, `filled`, `amountSent`.
- **getSellOrderCore(uint256)**: Returns `makerAddress`, `recipientAddress`, `status`.
- **getSellOrderPricing(uint256)**: Returns `maxPrice`, `minPrice`.
- **getSellOrderAmounts(uint256)**: Returns `pending`, `filled`, `amountSent`.
- **getHistoricalDataView(uint256)**: Returns `HistoricalData`.
- **historicalDataLengthView()**: Returns `_historicalData` length.
- **getHistoricalDataByNearestTimestamp(uint256)**: Returns `HistoricalData` closest to timestamp.

## Additional Details
- **Decimal Handling**: Normalizes to 1e18, denormalizes for transfers using `IERC20.decimals` or `_decimalsA`/`_decimalsB`.
- **Security**: 
  - Reentrancy protection handled by routers, no `nonReentrant` modifier.
  - Try-catch for external calls (`globalizeOrders`, `initializeBalances`, `liquidityAmounts`, `getReserves`).
  - Explicit casting for interfaces.
  - No inline assembly.
- **Gas Optimization**: Dynamic array resizing, minimal external calls, explicit gas limits (1000000 in `globalizeUpdate`, 500000 in `_updateRegistry`).
- **Token Usage**:
  - Buy orders: Input tokenB, output tokenA, `amountSent` tracks tokenA.
  - Sell orders: Input tokenA, output tokenB, `amountSent` tracks tokenB.
  - Long payouts: Output tokenB.
  - Short payouts: Output tokenA.
- **Events**: `OrderUpdated`, `PayoutOrderCreated`, `BalancesUpdated`.
- **Price Clarification**: `_currentPrice` updated in `update`, `transactToken`, `transactNative`; `prices` computes on-demand from Uniswap V2 reserves.
