# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract, written in Solidity (^0.8.2), facilitates decentralized trading for a token pair, integrating with Uniswap V2 for price discovery and liquidity management. It handles buy and sell orders, long and short payouts, and tracks volume and balances with normalized values (1e18 precision) for consistent calculations across tokens with varying decimals. The contract adheres to the Business Source License (BSL) 1.1 - Peng Protocol 2025, emphasizing secure, modular design for token pair listings, with explicit casting, no inline assembly, and graceful degradation for external calls.

## Version
- **0.1.4**

## Interfaces
The contract interacts with external contracts via well-defined interfaces, ensuring modularity and compliance with the style guide:
- **IERC20**: Provides `decimals()` for token precision (used for normalization to 1e18) and `transfer(address, uint256)` for token transfers. Applied to `_tokenA` and `_tokenB`.
- **ICCListing**: Exposes view functions (`prices`, `volumeBalances`, `liquidityAddressView`, `tokenA`, `tokenB`, `decimalsA`, `decimalsB`) and `ssUpdate` for payout updates. The `PayoutUpdate` struct defines `payoutType` (0: Long, 1: Short), `recipient`, and `required` amount.
- **IUniswapV2Pair**: Interfaces with Uniswap V2 for `getReserves()` (returns `reserve0`, `reserve1`, `blockTimestampLast`) and `token0`, `token1` to map `_tokenA`, `_tokenB` to pair reserves.
- **ICCListingTemplate**: Declares `getTokens`, `globalizerAddressView`, `makerPendingBuyOrdersView`, `makerPendingSellOrdersView` for token pair and globalizer address access, and pending order queries.
- **ICCLiquidityTemplate**: Provides `liquidityDetail` (returns `xLiquid`, `yLiquid`, `xFees`, `yFees`, `xFeesAcc`, `yFeesAcc`) for yield calculations.
- **ITokenRegistry**: Defines `initializeTokens(address user, address[] memory tokens)` for updating token balances in the registry for a single user.
- **ICCGlobalizer**: Defines `globalizeOrders(address maker, address listing)` for order globalization, called in `globalizeUpdate`.

Interfaces use explicit function declarations, avoid naming conflicts with state variables, and support external calls with revert strings for graceful degradation.

## Structs
Structs organize data for orders, payouts, and historical tracking, with explicit fields to avoid tuple access:
- **LastDayFee**: Stores `lastDayXFeesAcc`, `lastDayYFeesAcc` (cumulative fees at midnight), and `timestamp` for daily fee tracking, reset at midnight.
- **VolumeBalance**: Tracks `xBalance`, `yBalance` (normalized token balances), `xVolume`, `yVolume` (cumulative trading volumes, never decreasing).
- **HistoricalData**: Records `price` (tokenA/tokenB, 1e18), `xBalance`, `yBalance`, `xVolume`, `yVolume`, and `timestamp` for historical analysis.
- **BuyOrderCore**: Tracks `makerAddress` (order creator), `recipientAddress` (payout recipient), `status` (0: cancelled, 1: pending, 2: partially filled, 3: filled) for buy orders.
- **BuyOrderPricing**: Stores `maxPrice`, `minPrice` (1e18 precision) for buy order price bounds.
- **BuyOrderAmounts**: Manages `pending` (tokenB pending, normalized), `filled` (tokenB filled), `amountSent` (tokenA sent during settlement).
- **SellOrderCore**: Similar to `BuyOrderCore` for sell orders.
- **SellOrderPricing**: Similar to `BuyOrderPricing` for sell orders.
- **SellOrderAmounts**: Manages `pending` (tokenA pending, normalized), `filled` (tokenA filled), `amountSent` (tokenB sent).
- **PayoutUpdate**: Defined in `ICCListing`, specifies `payoutType` (0: Long, 1: Short), `recipient`, `required` for payout requests in `ssUpdate`.
- **LongPayoutStruct**: Tracks `makerAddress`, `recipientAddress`, `required` (tokenB amount), `filled`, `orderId`, `status` for long payouts.
- **ShortPayoutStruct**: Tracks `makerAddress`, `recipientAddress`, `amount` (tokenA amount), `filled`, `orderId`, `status` for short payouts.
- **UpdateType**: Manages updates with `updateType` (0: balance, 1: buy order, 2: sell order, 3: historical), `structId` (0: Core, 1: Pricing, 2: Amounts), `index` (orderId or balance/volume slot), `value` (amount/price), `addr` (maker), `recipient`, `maxPrice`, `minPrice`, `amountSent` (opposite token sent).

Structs avoid nested calls during initialization, computing dependencies first for safe assignments.

## State Variables
State variables are private, accessed via dedicated view functions for encapsulation:
- `_routers`: `mapping(address => bool)` - Tracks authorized routers, set via `setRouters`, restricts sensitive functions.
- `_routersSet`: `bool` - Prevents resetting routers after `setRouters`.
- `_tokenA`, `_tokenB`: `address` - Token pair (ETH as `address(0)`), set via `setTokens`, used for transfers and price calculations.
- `_decimalsA`, `_decimalsB`: `uint8` - Token decimals, fetched via `IERC20.decimals` or set to 18 for ETH in `setTokens`.
- `_uniswapV2Pair`, `_uniswapV2PairSet`: `address`, `bool` - Uniswap V2 pair address and flag, set via `setUniswapV2Pair`.
- `_listingId`: `uint256` - Unique listing identifier, set via `setListingId`, used in events.
- `_agent`: `address` - `ICCAgent` address, set via `setAgent`, used for registry access.
- `_registryAddress`: `address` - `ITokenRegistry` address, set via `setRegistry`, used in `_updateRegistry`.
- `_liquidityAddress`: `address` - `ICCLiquidityTemplate` address, set via `setLiquidityAddress`, used in `queryYield`.
- `_globalizerAddress`: `address` - Globalizer contract address, set via `setGlobalizerAddress`, one-time callable by anyone.
- `_globalizerSet`: `bool` - Prevents resetting `_globalizerAddress`.
- `_nextOrderId`: `uint256` - Incremental order ID counter, updated in `update` and `ssUpdate`.
- `_lastDayFee`: `LastDayFee` - Tracks daily fees, updated in `update` when volume changes.
- `_volumeBalance`: `VolumeBalance` - Stores balances and volumes, updated in `update`, `transactToken`, `transactNative`.
- `_currentPrice`: `uint256` - Current price (tokenA/tokenB, 1e18), updated in `update`, `transactToken`, `transactNative`.
- `_pendingBuyOrders`, `_pendingSellOrders`: `uint256[]` - Arrays of pending buy/sell order IDs, updated in `update`.
- `_longPayoutsByIndex`, `_shortPayoutsByIndex`: `uint256[]` - Arrays of long/short payout IDs, updated in `ssUpdate`.
- `_makerPendingOrders`: `mapping(address => uint256[])` - Stores all order IDs (buy or sell) created by a maker, including cancelled or filled orders, updated in `update`. Depopulated when orders are cancelled (`status=0`) or fully filled (`status=3`).
- `_userPayoutIDs`: `mapping(address => uint256[])` - Stores payout IDs for users, updated in `ssUpdate`.
- `_historicalData`: `HistoricalData[]` - Stores price and volume history, updated in `update`.
- `_buyOrderCores`, `_buyOrderPricings`, `_buyOrderAmounts`: `mapping(uint256 => ...)` - Store buy order data, updated in `update`.
- `_sellOrderCores`, `_sellOrderPricings`, `_sellOrderAmounts`: `mapping(uint256 => ...)` - Store sell order data, updated in `update`.
- `_longPayouts`, `_shortPayouts`: `mapping(uint256 => ...)` - Store payout data, updated in `ssUpdate`.

## Functions
### External Functions
- **setGlobalizerAddress(address globalizerAddress_)**: Sets `_globalizerAddress`, requires `_globalizerSet` false and non-zero address. Sets `_globalizerSet` to true, emits `GlobalizerAddressSet`. Callable once by anyone. Gas: Single write, event emission.
- **setUniswapV2Pair(address uniswapV2Pair_)**: Sets `_uniswapV2Pair`, requires `_uniswapV2PairSet` false and non-zero address. Sets `_uniswapV2PairSet` to true. Gas: Single write.
- **queryYield(bool isA, uint256 maxIterations, uint256 depositAmount, bool isTokenA)**: Calculates annualized yield based on daily fee share, using `maxIterations` to limit historical data traversal. Fetches liquidity from `ICCLiquidityTemplate.liquidityDetail`, returns 0 if no fees or liquidity. Gas: External call with try-catch, arithmetic.
- **setRouters(address[] memory routers_)**: Sets `_routers` mapping, requires `_routersSet` false and non-zero addresses. Sets `_routersSet` to true. Gas: Loop over `routers_`.
- **setListingId(uint256 listingId_)**: Sets `_listingId`, requires unset (0). Gas: Single write.
- **setLiquidityAddress(address liquidityAddress_)**: Sets `_liquidityAddress`, requires unset and non-zero address. Gas: Single write.
- **setTokens(address tokenA_, address tokenB_)**: Sets `_tokenA`, `_tokenB`, requires unset, different tokens, and at least one non-zero. Sets `_decimalsA`, `_decimalsB` via `IERC20.decimals` or 18 for ETH. Gas: State writes, two external calls.
- **setAgent(address agent_)**: Sets `_agent`, requires unset and non-zero address. Gas: Single write.
- **setRegistry(address registryAddress_)**: Sets `_registryAddress`, requires unset and non-zero address. Gas: Single write.
- **update(UpdateType[] memory updates)**: Router-only, updates `_volumeBalance`, buy/sell orders, or `_historicalData`. Updates `_lastDayFee` on volume changes, calls `_updateRegistry(maker)` for individual maker balance updates during order creation, cancellation, or settlement, emits `BalancesUpdated`. Calls `globalizeUpdate` if maker exists. Gas: Loop over `updates`, array operations, external calls.
- **ssUpdate(PayoutUpdate[] memory payoutUpdates)**: Router-only, creates long/short payouts using `ICCListing.PayoutUpdate`, updates `_longPayouts`, `_shortPayouts`, `_longPayoutsByIndex`, `_userPayoutIDs`, emits `PayoutOrderCreated`. Gas: Loop over `payoutUpdates`, array pushes.
- **transactToken(address token, uint256 amount, address recipient)**: Router-only, transfers ERC20 (`_tokenA` or `_tokenB`), updates `_volumeBalance`, `_currentPrice`, emits `BalancesUpdated`. Gas: External `IERC20.transfer`, array updates.
- **transactNative(uint256 amount, address recipient)**: Router-only, transfers ETH if `_tokenA` or `_tokenB` is `address(0)`, updates `_volumeBalance`, `_currentPrice`, emits `BalancesUpdated`. Gas: Native call, array updates.

### Internal Functions
- **normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)**: Converts amounts to 1e18 precision. Gas: Pure, minimal arithmetic.
- **denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)**: Converts amounts from 1e18 to token decimals. Gas: Pure, minimal arithmetic.
- **_isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)**: Checks if timestamps are on the same day (86400 seconds). Gas: Pure, arithmetic.
- **_floorToMidnight(uint256 timestamp) returns (uint256 midnight)**: Rounds timestamp to midnight. Gas: Pure, arithmetic.
- **_findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)**: Calculates volume change since `startTime`, using `maxIterations` to limit traversal. Gas: View, loop up to `maxIterations`.
- **_updateRegistry(address maker)**: Updates `ITokenRegistry.initializeTokens` for a single maker with `_tokenA` and `_tokenB` (if non-zero), uses 500,000 gas cap, emits `UpdateRegistryFailed` with reason on failure, reverts with decoded string. Gas: External call, dynamic array creation.
- **removePendingOrder(uint256[] storage orders, uint256 orderId)**: Removes order ID from array, swaps with last element and pops. Gas: Array operation.
- **globalizeUpdate(address maker)**: Calls `ICCGlobalizer.globalizeOrders(maker, address(this))` with gas checks, reverts with decoded reason on failure. Gas: External call with try-catch.

### View Functions
View functions are pure or view, avoiding state changes and naming conflicts, with explicit return naming:
- **agentView() returns (address agent)**: Returns `_agent`. Gas: Single read.
- **uniswapV2PairView() returns (address pair)**: Returns `_uniswapV2Pair`. Gas: Single read.
- **prices(uint256) returns (uint256 price)**: Computes price from Uniswap V2 reserves, normalized to 1e18. Gas: External call, arithmetic.
- **getTokens() returns (address tokenA, address tokenB)**: Returns `_tokenA`, `_tokenB`, requires at least one non-zero. Gas: Reads, revert check.
- **volumeBalances(uint256) returns (uint256 xBalance, uint256 yBalance)**: Returns `_volumeBalance.xBalance`, `_volumeBalance.yBalance`. Gas: Struct read.
- **liquidityAddressView() returns (address liquidityAddress)**: Returns `_liquidityAddress`. Gas: Single read.
- **tokenA() returns (address token)**: Returns `_tokenA`. Gas: Single read.
- **tokenB() returns (address token)**: Returns `_tokenB`. Gas: Single read.
- **decimalsA() returns (uint8 decimals)**: Returns `_decimalsA`. Gas: Single read.
- **decimalsB() returns (uint8 decimals)**: Returns `_decimalsB`. Gas: Single read.
- **getListingId() returns (uint256 listingId)**: Returns `_listingId`. Gas: Single read.
- **getNextOrderId() returns (uint256 nextOrderId)**: Returns `_nextOrderId`. Gas: Single read.
- **listingVolumeBalancesView() returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume)**: Returns `_volumeBalance` fields. Gas: Struct read.
- **listingPriceView() returns (uint256 price)**: Returns `_currentPrice`. Gas: Single read.
- **pendingBuyOrdersView() returns (uint256[] memory orderIds)**: Returns `_pendingBuyOrders`. Gas: Array read.
- **pendingSellOrdersView() returns (uint256[] memory orderIds)**: Returns `_pendingSellOrders`. Gas: Array read.
- **makerPendingOrdersView(address maker) returns (uint256[] memory orderIds)**: Returns `_makerPendingOrders[maker]`, including all orders (active or not). Gas: Array read.
- **longPayoutByIndexView() returns (uint256[] memory orderIds)**: Returns `_longPayoutsByIndex`. Gas: Array read.
- **shortPayoutByIndexView() returns (uint256[] memory orderIds)**: Returns `_shortPayoutsByIndex`. Gas: Array read.
- **userPayoutIDsView(address user) returns (uint256[] memory orderIds)**: Returns `_userPayoutIDs[user]`. Gas: Array read.
- **getLongPayout(uint256 orderId) returns (LongPayoutStruct memory payout)**: Returns `_longPayouts[orderId]`. Gas: Mapping read.
- **getShortPayout(uint256 orderId) returns (ShortPayoutStruct memory payout)**: Returns `_shortPayouts[orderId]`. Gas: Mapping read.
- **getBuyOrderCore(uint256 orderId) returns (address makerAddress, address recipientAddress, uint8 status)**: Returns `_buyOrderCores[orderId]` fields. Gas: Mapping read.
- **getBuyOrderPricing(uint256 orderId) returns (uint256 maxPrice, uint256 minPrice)**: Returns `_buyOrderPricings[orderId]` fields. Gas: Mapping read.
- **getBuyOrderAmounts(uint256 orderId) returns (uint256 pending, uint256 filled, uint256 amountSent)**: Returns `_buyOrderAmounts[orderId]` fields. Gas: Mapping read.
- **getSellOrderCore(uint256 orderId) returns (address makerAddress, address recipientAddress, uint8 status)**: Returns `_sellOrderCores[orderId]` fields. Gas: Mapping read.
- **getSellOrderPricing(uint256 orderId) returns (uint256 maxPrice, uint256 minPrice)**: Returns `_sellOrderPricings[orderId]` fields. Gas: Mapping read.
- **getSellOrderAmounts(uint256 orderId) returns (uint256 pending, uint256 filled, uint256 amountSent)**: Returns `_sellOrderAmounts[orderId]` fields. Gas: Mapping read.
- **makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)**: Returns up to `maxIterations` pending buy order IDs (status=1) from `_makerPendingOrders[maker]`, starting from `step`. Gas: Array loop, mapping reads.
- **makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)**: Returns up to `maxIterations` pending sell order IDs (status=1) from `_makerPendingOrders[maker]`, starting from `step`. Gas: Array loop, mapping reads.
- **getFullBuyOrderDetails(uint256 orderId) returns (BuyOrderCore memory core, BuyOrderPricing memory pricing, BuyOrderAmounts memory amounts)**: Returns all buy order structs for `orderId`. Gas: Multiple mapping reads.
- **getFullSellOrderDetails(uint256 orderId) returns (SellOrderCore memory core, SellOrderPricing memory pricing, SellOrderAmounts memory amounts)**: Returns all sell order structs for `orderId`. Gas: Multiple mapping reads.
- **makerOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)**: Returns up to `maxIterations` order IDs (buy or sell, any status) from `_makerPendingOrders[maker]`, starting from `step`. Gas: Array slice.
- **getHistoricalDataView(uint256 index) returns (HistoricalData memory data)**: Returns `_historicalData[index]`, requires valid index. Gas: Array read.
- **historicalDataLengthView() returns (uint256 length)**: Returns `_historicalData` length. Gas: Single read.
- **getHistoricalDataByNearestTimestamp(uint256 targetTimestamp) returns (HistoricalData memory data)**: Returns `HistoricalData` closest to `targetTimestamp`. Gas: Array loop.

## Parameters and Interactions
### Parameters
- **Token Pair** (`_tokenA`, `_tokenB`): Represents the trading pair (ETH as `address(0)`), set via `setTokens`. `_decimalsA`, `_decimalsB` store token decimals (fetched from `IERC20.decimals` or 18 for ETH), used for normalization/denormalization in transfers and price calculations.
- **Listing ID** (`_listingId`): Uniquely identifies the trading pair, set via `setListingId`, used in `OrderUpdated` and `BalancesUpdated` events for tracking.
- **Routers** (`_routers`): Restricts `update`, `ssUpdate`, `transactToken`, `transactNative` to authorized addresses, set via `setRouters`. Ensures only trusted contracts execute sensitive operations.
- **Uniswap V2 Pair** (`_uniswapV2Pair`): Provides reserves for price calculation (tokenA/tokenB, 1e18), set via `setUniswapV2Pair`. Token order is mapped using `token0`, `token1` to align `_tokenA`, `_tokenB`.
- **Agent** (`_agent`): `ICCAgent` address, set via `setAgent`, used to fetch registry or validate listings in related contracts.
- **Registry** (`_registryAddress`): `ITokenRegistry` address, set via `setRegistry`, used in `_updateRegistry` to initialize a single maker’s balances for `_tokenA` and `_tokenB`.
- **Globalizer** (`_globalizerAddress`): Address of the globalizer contract for order tracking, set via `setGlobalizerAddress`. One-time set ensures immutability, with `globalizerAddressView` for access. Used in `globalizeUpdate` for order globalization.
- **Liquidity** (`_liquidityAddress`): `ICCLiquidityTemplate` address, set via `setLiquidityAddress`, provides liquidity data for `queryYield` to calculate fees relative to pool size.
- **Orders** (`UpdateType`): Defines updates for balances (`updateType=0`), buy orders (`1`), sell orders (`2`), or historical data (`3`). Fields include `structId` (0: Core, 1: Pricing, 2: Amounts), `index` (orderId or balance/volume slot), `value` (amount/price), `addr` (maker), `recipient`, `maxPrice`, `minPrice`, `amountSent` (opposite token sent).
- **Payouts** (`PayoutUpdate`): Specifies `payoutType` (0: Long for tokenB, 1: Short for tokenA), `recipient`, `required` for `ssUpdate`, creating payout orders tracked in `_longPayouts` or `_shortPayouts`.
- **Maker Orders** (`_makerPendingOrders`): Maps maker addresses to arrays of order IDs (buy or sell, any status: 0=cancelled, 1=pending, 2=partially filled, 3=filled). Populated in `update` when orders are created, depopulated when cancelled (`value=0`, `status=0`) or fully filled (`pending=0`, `status=3`). Persists historical orders for auditing, accessible via `makerOrdersView`.

### Interactions
- **Uniswap V2**: `prices`, `update`, `transactToken`, `transactNative` call `IUniswapV2Pair.getReserves` to compute `_currentPrice` (tokenA/tokenB, 1e18). Token order is resolved using `token0`, `token1`. Calls use try-catch for reliability.
- **ITokenRegistry**: `_updateRegistry(address maker)` calls `initializeTokens` with a single maker and an array of `_tokenA` and `_tokenB` (if non-zero), capped at 500,000 gas. Emits `UpdateRegistryFailed` with reason and reverts on failure. Called in `update` for order creation, cancellation, or settlement.
- **ICCLiquidityTemplate**: `queryYield` calls `liquidityDetail` to fetch `xLiquid`, `yLiquid`, `xFees`, `yFees`, `xFeesAcc`, `yFeesAcc`, with try-catch to return 0 on failure, ensuring robust yield calculation.
- **ICCGlobalizer**: `globalizeUpdate` calls `globalizeOrders` with maker and listing address, using try-catch to revert with decoded reason on failure, ensuring robust order globalization.
- **IERC20**: `transactToken` calls `transfer` for ERC20 tokens, `decimals` for normalization. `transactNative` uses low-level `call` for ETH transfers, reverting on failure.
- **Order Management**: `update` processes `UpdateType` arrays to modify `_volumeBalance`, buy/sell orders, or `_historicalData`. Buy orders input tokenB, output tokenA; sell orders input tokenA, output tokenB. Status updates trigger `OrderUpdated` events. `_makerPendingOrders` tracks all orders, with `removePendingOrder` clearing cancelled or filled orders.
- **Payouts**: `ssUpdate` creates long (tokenB) or short (tokenA) payouts, assigning `_nextOrderId`, updating `_longPayouts`, `_shortPayouts`, `_longPayoutsByIndex`, `_userPayoutIDs`, emitting `PayoutOrderCreated`.
- **Fee Tracking**: `_lastDayFee` updates daily (86400 seconds) in `update` when volume changes. `queryYield` uses fee difference (`xFeesAcc - lastDayXFeesAcc` or `yFeesAcc - lastDayYFeesAcc`) for yield calculation based on deposit contribution.
- **Historical Data**: `update` (type 3) pushes `HistoricalData` with `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, used in `queryYield` and view functions like `getHistoricalDataView`.
- **Globalization**: `globalizeUpdate` calls `ICCGlobalizer.globalizeOrders` to propagate maker orders to the globalizer contract, ensuring cross-listing tracking.

## Security and Optimization
- **Security**:
  - Router validation (`_routers[msg.sender]`) restricts `update`, `ssUpdate`, `transactToken`, `transactNative` to authorized callers.
  - No `SafeERC20`, inline assembly, `virtual`/`override`, or reserved keywords, per style guide.
  - Explicit gas checks in `_updateRegistry` (500,000) and `globalizeUpdate` (gasleft < gasBefore/10) prevent out-of-gas failures, with `UpdateRegistryFailed` event and clear revert messages.
  - Try-catch in `queryYield`, Uniswap V2 calls (`getReserves`), `_updateRegistry`, and `globalizeUpdate` ensures graceful degradation.
  - Setters (`setTokens`, `setAgent`, etc.) replace constructor arguments, allowing post-deployment configuration.
  - No nested calls in struct initialization; dependencies computed first.
  - `_globalizerAddress` set once, ensuring immutability.
  - `_makerPendingOrders` depopulation in `update` prevents stale entries, maintaining integrity.
- **Optimization**:
  - Dynamic array resizing in `removePendingOrder` uses swap-and-pop, avoiding fixed iteration limits.
  - Normalized amounts (1e18) simplify calculations across token decimals.
  - `maxIterations` and `step` in `makerPendingBuyOrdersView`, `makerPendingSellOrdersView`, `makerOrdersView` limit gas usage.
  - Single-maker `_updateRegistry` with `initializeTokens` reduces gas by handling both tokens in one call.
  - View functions use explicit destructuring, minimizing state reads.
- **Error Handling**: Reverts provide detailed reasons (e.g., "Invalid token", "Insufficient pending", "Router only"). `UpdateRegistryFailed` ensures robust registry call handling.

## Token Usage
- **Buy Orders**: Input tokenB (`_tokenB`), output tokenA (`_tokenA`). `amountSent` tracks tokenA sent. `yBalance` increases on order creation, `xBalance` decreases on fill.
- **Sell Orders**: Input tokenA, output tokenB. `amountSent` tracks tokenB sent. `xBalance` increases on order creation, `yBalance` decreases on fill.
- **Long Payouts**: Output tokenB, tracked in `LongPayoutStruct.required`.
- **Short Payouts**: Output tokenA, tracked in `ShortPayoutStruct.amount`.
- **Normalization**: `normalize` and `denormalize` use `_decimalsA`, `_decimalsB` or `IERC20.decimals` for consistent 1e18 precision.

## Events
- **OrderUpdated(uint256 listingId, uint256 orderId, bool isBuy, uint8 status)**: Emitted on buy/sell order creation, cancellation, or status change (0, 1, 2, 3).
- **PayoutOrderCreated(uint256 orderId, bool isLong, uint8 status)**: Emitted on long/short payout creation.
- **BalancesUpdated(uint256 listingId, uint256 xBalance, uint256 yBalance)**: Emitted on balance changes in `update`, `transactToken`, `transactNative`.
- **GlobalizerAddressSet(address globalizer)**: Emitted when `_globalizerAddress` is set.
- **UpdateRegistryFailed(address user, address[] tokens, string reason)**: Emitted on `_updateRegistry` failure, with user, tokens, and reason.

## Price Clarification
- **_currentPrice**: Updated in `update`, `transactToken`, `transactNative` using Uniswap V2 reserves (tokenA/tokenB, 1e18). Stored for quick access via `listingPriceView`.
- **prices(uint256)**: Computes price on-demand from Uniswap V2 reserves, normalized to 1e18, consistent with `_currentPrice`.

## Maker Orders Clarification
- **_makerPendingOrders**: Stores all order IDs (buy or sell) created by a maker, including cancelled (`status=0`), pending (`status=1`), partially filled (`status=2`), or filled (`status=3`) orders. Added in `update` when created (`structId=0`, `status=1`) and removed via `removePendingOrder` when cancelled (`value=0`, `status=0`) or fully filled (`pending=0`, `status=3`). Persists historical orders for auditing, accessible via `makerOrdersView`. `makerPendingBuyOrdersView` and `makerPendingSellOrdersView` filter for `status=1`.
