# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract, implemented in Solidity (^0.8.2), manages buy/sell orders, payouts, and liquidity for a token pair, integrated with Uniswap V2. It supports native ETH and ERC20 tokens, with normalized balances (1e18) for consistency. SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025.

## Version
- **0.0.10** (Latest): Removed `caller` parameter from `update`, `ssUpdate`, `transactToken`, `transactNative`; used `msg.sender` for router validation to prevent unauthorized access.

## Interfaces
- **IERC20**: Defines `decimals`, `transfer`.
- **ICCListing**: Defines `prices`, `volumeBalances`, `liquidityAddressView`, `tokenA`, `tokenB`, `PayoutUpdate`, `ssUpdate`, `decimalsA`, `decimalsB`.
- **IUniswapV2Pair**: Defines `getReserves`, `token0`, `token1`.
- **ICCAgent**: Defines `globalizeOrders`.
- **ICCListingTemplate**: Defines `getTokens`.
- **ICCLiquidityTemplate**: Defines `liquidityAmounts`, `setRouters`, `setListingId`, `setListingAddress`, `setTokens`, `setAgent`.
- **ITokenRegistry**: Defines `initializeBalances`.

## Structs
- **LastDayFee**: Tracks `xFees`, `yFees`, `timestamp`.
- **VolumeBalance**: Tracks `xBalance`, `yBalance`, `xVolume`, `yVolume`.
- **HistoricalData**: Tracks `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`.
- **BuyOrderCore**: Tracks `makerAddress`, `recipientAddress`, `status`.
- **BuyOrderPricing**: Tracks `maxPrice`, `minPrice`.
- **BuyOrderAmounts**: Tracks `pending`, `filled`, `amountSent`.
- **SellOrderCore**: Tracks `makerAddress`, `recipientAddress`, `status`.
- **SellOrderPricing**: Tracks `maxPrice`, `minPrice`.
- **SellOrderAmounts**: Tracks `pending`, `filled`, `amountSent`.
- **PayoutUpdate**: Tracks `payoutType`, `recipient`, `required`.
- **LongPayoutStruct**: Tracks `makerAddress`, `recipientAddress`, `required`, `filled`, `orderId`, `status`.
- **ShortPayoutStruct**: Tracks `makerAddress`, `recipientAddress`, `amount`, `filled`, `orderId`, `status`.
- **UpdateType**: Tracks `updateType`, `structId`, `index`, `value`, `addr`, `recipient`, `maxPrice`, `minPrice`, `amountSent`.

## State Variables
- `_routers`: Mapping for authorized routers.
- `_routersSet`: Flag for router initialization.
- `_tokenA`, `_tokenB`: Token addresses (ETH as 0x0).
- `_decimalsA`, `_decimalsB`: Token decimals.
- `_uniswapV2Pair`, `_uniswapV2PairSet`: Uniswap V2 pair address and flag.
- `_listingId`: Unique listing identifier.
- `_agent`: CCAgent address.
- `_registryAddress`: Token registry address.
- `_liquidityAddress`: Liquidity contract address.
- `_nextOrderId`: Incremental order ID.
- `_lastDayFee`: Last day’s fee data.
- `_volumeBalance`: Balance and volume data.
- `_currentPrice`: Current token pair price.
- `_pendingBuyOrders`, `_pendingSellOrders`: Order ID arrays.
- `_longPayoutsByIndex`, `_shortPayoutsByIndex`: Payout ID arrays.
- `_makerPendingOrders`: Maker’s pending order IDs.
- `_userPayoutIDs`: User’s payout IDs.
- `_historicalData`: Historical price and volume data.
- `_buyOrderCores`, `_buyOrderPricings`, `_buyOrderAmounts`: Buy order data.
- `_sellOrderCores`, `_sellOrderPricings`, `_sellOrderAmounts`: Sell order data.
- `_longPayouts`, `_shortPayouts`: Payout data.

## Functions
### External
- **setUniswapV2Pair(address)**: Sets Uniswap V2 pair, requires unset and non-zero address.
- **queryYield(bool, uint256)**: Returns annualized yield based on fees, uses `maxIterations`.
- **setRouters(address[])**: Sets authorized routers, requires unset and non-zero addresses.
- **setListingId(uint256)**: Sets listing ID, requires unset.
- **setLiquidityAddress(address)**: Sets liquidity address, requires unset and non-zero.
- **setTokens(address, address)**: Sets token pair, requires unset, different, and at least one non-zero.
- **setAgent(address)**: Sets agent, requires unset and non-zero.
- **setRegistry(address)**: Sets registry, requires unset and non-zero.
- **update(UpdateType[])**: Updates balances/orders, restricted to routers via `msg.sender`.
- **ssUpdate(PayoutUpdate[])**: Creates long/short payouts, restricted to routers via `msg.sender`.
- **transactToken(address, uint256, address)**: Transfers ERC20 tokens, restricted to routers via `msg.sender`.
- **transactNative(uint256, address)**: Transfers ETH, restricted to routers via `msg.sender`.

### View
- **agentView()**: Returns `_agent`.
- **uniswapV2PairView()**: Returns `_uniswapV2Pair`.
- **prices(uint256)**: Returns current price from Uniswap V2 reserves.
- **getTokens()**: Returns `_tokenA`, `_tokenB`.
- **volumeBalances(uint256)**: Returns `_volumeBalance.xBalance`, `_volumeBalance.yBalance`.
- **liquidityAddressView()**: Returns `_liquidityAddress`.
- **tokenA()**: Returns `_tokenA`.
- **tokenB()**: Returns `_tokenB`.
- **decimalsA()**: Returns `_decimalsA`.
- **decimalsB()**: Returns `_decimalsB`.
- **getListingId()**: Returns `_listingId`.
- **getNextOrderId()**: Returns `_nextOrderId`.
- **listingVolumeBalancesView()**: Returns `_volumeBalance` fields.
- **listingPriceView()**: Returns `_currentPrice`.
- **pendingBuyOrdersView()**: Returns `_pendingBuyOrders`.
- **pendingSellOrdersView()**: Returns `_pendingSellOrders`.
- **makerPendingOrdersView(address)**: Returns `_makerPendingOrders`.
- **longPayoutByIndexView()**: Returns `_longPayoutsByIndex`.
- **shortPayoutByIndexView()**: Returns `_shortPayoutsByIndex`.
- **userPayoutIDsView(address)**: Returns `_userPayoutIDs`.
- **getLongPayout(uint256)**: Returns `LongPayoutStruct`.
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
  - Router validation uses `msg.sender` to prevent unauthorized access by passing valid router addresses.
- **Gas Optimization**: Dynamic array resizing, minimal external calls, explicit gas limits (1000000 in `globalizeUpdate`, 500000 in `_updateRegistry`).
- **Token Usage**:
  - Buy orders: Input tokenB, output tokenA, `amountSent` tracks tokenA.
  - Sell orders: Input tokenA, output tokenB, `amountSent` tracks tokenB.
  - Long payouts: Output tokenB.
  - Short payouts: Output tokenA.
- **Events**: `OrderUpdated`, `PayoutOrderCreated`, `BalancesUpdated`.
- **Price Clarification**: `_currentPrice` updated in `update`, `transactToken`, `transactNative`; `prices` computes on-demand from Uniswap V2 reserves.
