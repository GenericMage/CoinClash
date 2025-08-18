# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract, written in Solidity (^0.8.2), facilitates decentralized trading for a token pair, integrating with Uniswap V2 for price discovery and liquidity management. It handles buy and sell orders, long and short payouts, and tracks volume and balances with normalized values (1e18 precision) for consistent calculations across tokens with varying decimals. The contract adheres to the Business Source License (BSL) 1.1 - Peng Protocol 2025, emphasizing secure, modular design for token pair listings, with explicit casting, no inline assembly, and graceful degradation for external calls.

## Version
- **0.1.8**
- **Changes**:
  - v0.1.8: Updated price calculation in `prices`, `update`, `transactToken`, and `transactNative` to use `reserveB * 1e18 / reserveA`, flipping the reserve ratio for tokenB/tokenA pricing, normalized to 1e18 precision.
  - v0.1.7: Refactored `globalizeUpdate` to occur at the end of `update`, fetching the latest order ID (`_nextOrderId - 1`), retrieving maker and token (`_tokenB` for buy, `_tokenA` for sell) from order details, and calling `ICCGlobalizer.globalizeOrders` with these, reducing reliance on `update`’s loop.

## Interfaces
The contract interacts with external contracts via well-defined interfaces, ensuring modularity and compliance with the style guide:
- **IERC20**: Provides `decimals()` for token precision (used for normalization to 1e18) and `transfer(address, uint256)` for token transfers. Applied to `_tokenA` and `_tokenB`.
- **ICCListing**: Exposes view functions (`prices`, `volumeBalances`, `liquidityAddressView`, `tokenA`, `tokenB`, `decimalsA`, `decimalsB`) and `ssUpdate` for payout updates. The `PayoutUpdate` struct defines `payoutType` (0: Long, 1: Short), `recipient`, and `required` amount.
- **IUniswapV2Pair**: Interfaces with Uniswap V2 for `getReserves()` (returns `reserve0`, `reserve1`, `blockTimestampLast`) and `token0`, `token1` to map `_tokenA`, `_tokenB` to pair reserves.
- **ICCListingTemplate**: Declares `getTokens`, `globalizerAddressView`, `makerPendingBuyOrdersView`, `makerPendingSellOrdersView` for token pair and globalizer address access, and pending order queries.
- **ICCLiquidityTemplate**: Provides `liquidityDetail` (returns `xLiquid`, `yLiquid`, `xFees`, `yFees`, `xFeesAcc`, `yFeesAcc`) for yield calculations.
- **ITokenRegistry**: Defines `initializeTokens(address user, address[] memory tokens)` for updating token balances in the registry for a single user.
- **ICCGlobalizer**: Defines `globalizeOrders(address maker, address token)` for order globalization, called in `globalizeUpdate` with token based on latest order type (`_tokenB` for buy, `_tokenA` for sell).

Interfaces use explicit function declarations, avoid naming conflicts with state variables, and support external calls with revert strings for graceful degradation.

## Structs
Structs organize data for orders, payouts, and historical tracking, with explicit fields to avoid tuple access:
- **LastDayFee**: Stores `lastDayXFeesAcc`, `lastDayYFeesAcc` (cumulative fees at midnight), and `timestamp` for daily fee tracking, reset at midnight.
- **VolumeBalance**: Tracks `xBalance`, `yBalance` (normalized token balances), `xVolume`, `yVolume` (cumulative trading volumes, never decreasing).
- **HistoricalData**: Records `price` (tokenB/tokenA, 1e18), `xBalance`, `yBalance`, `xVolume`, `yVolume`, and `timestamp` for historical analysis.
- **BuyOrderCore**: Tracks `makerAddress` (order creator), `recipientAddress` (payout recipient), `status` (0: cancelled, 1: pending, 2: partially filled, 3: filled) for buy orders.
- **BuyOrderPricing**: Stores `maxPrice`, `minPrice` (1e18 precision) for buy order price bounds.
- **BuyOrderAmounts**: Manages `pending` (tokenB pending, normalized), `filled` (tokenB filled), `amountSent` (tokenA sent during settlement).
- **SellOrderCore**: Similar to `BuyOrderCore` for sell orders.
- **SellOrderPricing**: Similar to `BuyOrderPricing` for sell orders.
- **SellOrderAmounts**: Manages `pending` (tokenA pending, normalized), `filled` (tokenA filled), `amountSent` (tokenB sent).
- **LongPayoutStruct**: Tracks `makerAddress`, `recipientAddress`, `required` (tokenB amount), `filled`, `orderId`, `status` for long payouts.
- **ShortPayoutStruct**: Tracks `makerAddress`, `recipientAddress`, `amount` (tokenA amount), `filled`, `orderId`, `status` for short payouts.
- **UpdateType**: Manages updates with `updateType` (0: balance, 1: buy order, 2: sell order, 3: historical), `structId` (0: Core, 1: Pricing, 2: Amounts), `index` (orderId or balance/volume slot), `value` (amount/price), `addr` (maker), `recipient`, `maxPrice`, `minPrice`, `amountSent` (opposite token sent).
- **PayoutUpdate**: Defined in `ICCListing`, specifies `payoutType` (0: Long for tokenB, 1: Short for tokenA), `recipient`, `required` for payout requests in `ssUpdate`.

Structs avoid nested calls during initialization, computing dependencies first for safe assignments.

## State Variables
State variables are private, accessed via dedicated view functions for encapsulation:
- `_routers`: `mapping(address => bool)` - Tracks authorized routers, set via `setRouters`, restricts sensitive functions.
- `_routersSet`: `bool` - Prevents resetting routers after `setRouters`.
- `_tokenA`, `_tokenB`: `address` - Token pair (ETH as `address(0)`), set via `setTokens`, used for transfers and price calculations.
- `_decimalsA`, `_decimalsB`: `uint8` - Token decimals, fetched via `IERC20.decimals` or set to 18 for ETH in `setTokens`.
- `_uniswapV2Pair`, `_uniswapV2PairSet`: `address`, `bool` - Uniswap V2 pair address and flag, set via `setUniswapV2Pair`.
- `_listingId`: `uint256` - Unique listing identifier, set via `setListingId`, used in events.
- `_agent`: `address` - Agent address, set via `setAgent`, used for registry access.
- `_registryAddress`: `address` - `ITokenRegistry` address, set via `setRegistry`, used in `_updateRegistry`.
- `_liquidityAddress`: `address` - `ICCLiquidityTemplate` address, set via `setLiquidityAddress`, used in fee-related functions.
- `_globalizerAddress`, `_globalizerSet`: `address`, `bool` - Globalizer contract address and flag, set via `setGlobalizerAddress`, used in `globalizeUpdate`.
- `_nextOrderId`: `uint256` - Incremental order ID counter, updated in `update` and `ssUpdate`.
- `_lastDayFee`: `LastDayFee` - Tracks daily fees, updated in `update` when volume changes.
- `_volumeBalance`: `VolumeBalance` - Stores balances and volumes, updated in `update`, `transactToken`, `transactNative`.
- `_currentPrice`: `uint256` - Current price (tokenB/tokenA, 1e18), updated in `update`, `transactToken`, `transactNative`.
- `_pendingBuyOrders`, `_pendingSellOrders`: `uint256[]` - Arrays of pending buy/sell order IDs, updated in `update`.
- `_longPayoutsByIndex`, `_shortPayoutsByIndex`: `uint256[]` - Arrays of long/short payout IDs, updated in `ssUpdate`.
- `_makerPendingOrders`: `mapping(address => uint256[])` - Stores all order IDs (buy or sell) created by a maker, updated in `update`.
- `_userPayoutIDs`: `mapping(address => uint256[])` - Stores payout IDs for users, updated in `ssUpdate`.
- `_historicalData`: `HistoricalData[]` - Stores price and volume history, updated in `update`.
- `_buyOrderCores`, `_buyOrderPricings`, `_buyOrderAmounts`: `mapping(uint256 => ...)` - Store buy order data, updated in `update`.
- `_sellOrderCores`, `_sellOrderPricings`, `_sellOrderAmounts`: `mapping(uint256 => ...)` - Store sell order data, updated in `update`.
- `_longPayouts`, `_shortPayouts`: `mapping(uint256 => ...)` - Store payout data, updated in `ssUpdate`.

## Functions
### External Functions
- **setGlobalizerAddress(address globalizerAddress_)**: Sets `_globalizerAddress`, requires `_globalizerSet` false and non-zero address. Sets `_globalizerSet` to true, emits `GlobalizerAddressSet`. Callable once. Gas: Single write, event emission.
- **setUniswapV2Pair(address uniswapV2Pair_)**: Sets `_uniswapV2Pair`, requires `_uniswapV2PairSet` false and non-zero address. Sets `_uniswapV2PairSet` to true. Gas: Single write.
- **setRouters(address[] memory routers_)**: Sets `_routers` mapping, requires `_routersSet` false and non-zero addresses. Sets `_routersSet` to true. Gas: Loop over `routers_`.
- **setListingId(uint256 listingId_)**: Sets `_listingId`, requires unset (0). Gas: Single write.
- **setLiquidityAddress(address liquidityAddress_)**: Sets `_liquidityAddress`, requires unset and non-zero address. Gas: Single write.
- **setTokens(address tokenA_, address tokenB_)**: Sets `_tokenA`, `_tokenB`, requires unset, different tokens, and at least one non-zero. Sets `_decimalsA`, `_decimalsB` via `IERC20.decimals` or 18 for ETH. Gas: State writes, two external calls.
- **setAgent(address agent_)**: Sets `_agent`, requires unset and non-zero address. Gas: Single write.
- **setRegistry(address registryAddress_)**: Sets `_registryAddress`, requires unset and non-zero address. Gas: Single write.
- **update(UpdateType[] memory updates)**: Router-only, updates `_volumeBalance`, buy/sell orders, or `_historicalData`. Updates `_lastDayFee` on volume changes, processes order updates (creation, cancellation, or settlement), calls `_updateRegistry(maker)` if maker is present, calls `globalizeUpdate()` at the end, emits `BalancesUpdated`. Gas: Loop over `updates`, array operations, external calls.
- **ssUpdate(PayoutUpdate[] memory payoutUpdates)**: Router-only, creates long/short payouts, updates `_longPayouts`, `_shortPayouts`, `_longPayoutsByIndex`, `_userPayoutIDs`, emits `PayoutOrderCreated`. Gas: Loop over `payoutUpdates`, array pushes.
- **transactToken(address token, uint256 amount, address recipient)**: Router-only, transfers ERC20 (`_tokenA` or `_tokenB`), updates `_volumeBalance`, `_currentPrice`, emits `BalancesUpdated`. Gas: External `IERC20.transfer`, array updates.
- **transactNative(uint256 amount, address recipient)**: Router-only, transfers ETH if `_tokenA` or `_tokenB` is `address(0)`, updates `_volumeBalance`, `_currentPrice`, emits `BalancesUpdated`. Gas: Native call, array updates.

### Internal Functions
- **normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)**: Converts amounts to 1e18 precision. Called by `transactToken`, `transactNative` to normalize amounts for `_volumeBalance`. Gas: Pure, minimal arithmetic.
- **denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)**: Converts amounts from 1e18 to token decimals. Not directly called but available for future use. Gas: Pure, minimal arithmetic.
- **_isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)**: Checks if timestamps are on the same day (86400 seconds). Called by `update`. Gas: Pure, arithmetic.
- **_floorToMidnight(uint256 timestamp) returns (uint256 midnight)**: Rounds timestamp to midnight. Called by `update` for `_lastDayFee`. Gas: Pure, arithmetic.
- **_findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)**: Calculates volume change since `startTime`, using `maxIterations` to limit traversal of `_historicalData`. Called by none but available for volume analysis. Gas: View, loop up to `maxIterations`.
- **_updateRegistry(address maker)**: Updates `ITokenRegistry.initializeTokens` for a single maker with `_tokenA` and `_tokenB` (if non-zero), uses 500,000 gas cap, emits `UpdateRegistryFailed` with reason on failure, reverts with decoded string. Called by `update` after order updates. Gas: External call, dynamic array creation.
- **removePendingOrder(uint256[] storage orders, uint256 orderId)**: Removes order ID from array, swaps with last element and pops. Called by `update` for cancelled or filled orders in `_pendingBuyOrders`, `_pendingSellOrders`, `_makerPendingOrders`. Gas: Array operation.
- **globalizeUpdate()**: Calls `ICCGlobalizer.globalizeOrders` with maker and token from the latest order (`_nextOrderId - 1`), using `_tokenB` for buy orders or `_tokenA` for sell orders, with try-catch and gas limit (gasleft/10), reverts with decoded reason on failure. Called by `update` at the end. Gas: External call.

### View Functions
View functions are pure or view, avoiding state changes, with explicit return naming:
- **agentView() returns (address agent)**: Returns `_agent`.
- **uniswapV2PairView() returns (address pair)**: Returns `_uniswapV2Pair`.
- **prices(uint256) returns (uint256 price)**: Computes price from Uniswap V2 reserves (tokenB/tokenA, 1e18).
- **getTokens() returns (address tokenA, address tokenB)**: Returns `_tokenA`, `_tokenB`, requires at least one non-zero.
- **volumeBalances(uint256) returns (uint256 xBalance, uint256 yBalance)**: Returns `_volumeBalance.xBalance`, `_volumeBalance.yBalance`.
- **liquidityAddressView() returns (address liquidityAddress)**: Returns `_liquidityAddress`.
- **tokenA() returns (address token)**: Returns `_tokenA`.
- **tokenB() returns (address token)**: Returns `_tokenB`.
- **decimalsA() returns (uint8 decimals)**: Returns `_decimalsA`.
- **decimalsB() returns (uint8 decimals)**: Returns `_decimalsB`.
- **getListingId() returns (uint256 listingId)**: Returns `_listingId`.
- **getNextOrderId() returns (uint256 nextOrderId)**: Returns `_nextOrderId`.
- **listingVolumeBalancesView() returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume)**: Returns `_volumeBalance` fields.
- **listingPriceView() returns (uint256 price)**: Returns `_currentPrice`.
- **pendingBuyOrdersView() returns (uint256[] memory orderIds)**: Returns `_pendingBuyOrders`.
- **pendingSellOrdersView() returns (uint256[] memory orderIds)**: Returns `_pendingSellOrders`.
- **makerPendingOrdersView(address maker) returns (uint256[] memory orderIds)**: Returns `_makerPendingOrders[maker]`.
- **longPayoutByIndexView() returns (uint256[] memory orderIds)**: Returns `_longPayoutsByIndex`.
- **shortPayoutByIndexView() returns (uint256[] memory orderIds)**: Returns `_shortPayoutsByIndex`.
- **userPayoutIDsView(address user) returns (uint256[] memory orderIds)**: Returns `_userPayoutIDs[user]`.
- **getLongPayout(uint256 orderId) returns (LongPayoutStruct memory payout)**: Returns `_longPayouts[orderId]`.
- **getShortPayout(uint256 orderId) returns (ShortPayoutStruct memory payout)**: Returns `_shortPayouts[orderId]`.
- **getBuyOrderCore(uint256 orderId) returns (address makerAddress, address recipientAddress, uint8 status)**: Returns `_buyOrderCores[orderId]` fields.
- **getBuyOrderPricing(uint256 orderId) returns (uint256 maxPrice, uint256 minPrice)**: Returns `_buyOrderPricings[orderId]` fields.
- **getBuyOrderAmounts(uint256 orderId) returns (uint256 pending, uint256 filled, uint256 amountSent)**: Returns `_buyOrderAmounts[orderId]` fields.
- **getSellOrderCore(uint256 orderId) returns (address makerAddress, address recipientAddress, uint8 status)**: Returns `_sellOrderCores[orderId]` fields.
- **getSellOrderPricing(uint256 orderId) returns (uint256 maxPrice, uint256 minPrice)**: Returns `_sellOrderPricings[orderId]` fields.
- **getSellOrderAmounts(uint256 orderId) returns (uint256 pending, uint256 filled, uint256 amountSent)**: Returns `_sellOrderAmounts[orderId]` fields.
- **makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)**: Returns up to `maxIterations` pending buy order IDs (status=1) from `_makerPendingOrders[maker]`, starting from `step`.
- **makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)**: Returns up to `maxIterations` pending sell order IDs (status=1) from `_makerPendingOrders[maker]`, starting from `step`.
- **getFullBuyOrderDetails(uint256 orderId) returns (BuyOrderCore memory core, BuyOrderPricing memory pricing, BuyOrderAmounts memory amounts)**: Returns all buy order structs for `orderId`.
- **getFullSellOrderDetails(uint256 orderId) returns (SellOrderCore memory core, SellOrderPricing memory pricing, SellOrderAmounts memory amounts)**: Returns all sell order structs for `orderId`.
- **makerOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)**: Returns up to `maxIterations` order IDs (buy or sell, any status) from `_makerPendingOrders[maker]`, starting from `step`.
- **getHistoricalDataView(uint256 index) returns (HistoricalData memory data)**: Returns `_historicalData[index]`, requires valid index.
- **historicalDataLengthView() returns (uint256 length)**: Returns `_historicalData` length.
- **getHistoricalDataByNearestTimestamp(uint256 targetTimestamp) returns (HistoricalData memory data)**: Returns `HistoricalData` closest to `targetTimestamp`.

## Parameters and Interactions
### Parameters
- **Token Pair** (`_tokenA`, `_tokenB`): Represents the trading pair (ETH as `address(0)`), set via `setTokens`. `_decimalsA`, `_decimalsB` store token decimals (fetched from `IERC20.decimals` or 18 for ETH), used for normalization/denormalization in transfers and price calculations.
- **Listing ID** (`_listingId`): Uniquely identifies the trading pair, set via `setListingId`, used in `OrderUpdated` and `BalancesUpdated` events for tracking.
- **Routers** (`_routers`): Restricts `update`, `ssUpdate`, `transactToken`, `transactNative` to authorized addresses, set via `setRouters`. Ensures only trusted contracts execute sensitive operations.
- **Uniswap V2 Pair** (`_uniswapV2Pair`): Provides reserves for price calculation (tokenB/tokenA, 1e18), set via `setUniswapV2Pair`. Token order is mapped using `token0`, `token1` to align `_tokenA`, `_tokenB`.
- **Agent** (`_agent`): Agent address, set via `setAgent`, used to fetch registry or validate listings in related contracts.
- **Registry** (`_registryAddress`): `ITokenRegistry` address, set via `setRegistry`, used in `_updateRegistry` to initialize a single maker’s balances for `_tokenA` and `_tokenB`.
- **Globalizer** (`_globalizerAddress`): Globalizer contract address, set via `setGlobalizerAddress`. One-time set ensures immutability, accessible via `globalizerAddressView`. Used in `globalizeUpdate` to propagate the latest order with `_tokenB` (buy) or `_tokenA` (sell).
- **Liquidity** (`_liquidityAddress`): `ICCLiquidityTemplate` address, set via `setLiquidityAddress`, provides liquidity data for fee calculations.
- **Orders** (`UpdateType`): Defines updates for balances (`updateType=0`), buy orders (`1`), sell orders (`2`), or historical data (`3`). Fields include `structId` (0: Core, 1: Pricing, 2: Amounts), `index` (orderId or balance/volume slot), `value` (amount/price), `addr` (maker), `recipient`, `maxPrice`, `minPrice`, `amountSent` (opposite token sent).
- **Payouts** (`PayoutUpdate`): Specifies `payoutType` (0: Long for tokenB, 1: Short for tokenA), `recipient`, `required` for `ssUpdate`, creating payout orders tracked in `_longPayouts` or `_shortPayouts`.
- **Maker Orders** (`_makerPendingOrders`): Maps maker addresses to arrays of order IDs (buy or sell, any status: 0=cancelled, 1=pending, 2=partially filled, 3=filled). Populated in `update` when orders are created, depopulated when cancelled (`value=0`, `status=0`) or fully filled (`pending=0`, `status=3`).

### Interactions
- **Uniswap V2**: `prices`, `update`, `transactToken`, `transactNative` call `IUniswapV2Pair.getReserves` to compute `_currentPrice` (tokenB/tokenA, 1e18). Token order is resolved using `token0`, `token1`. Calls use try-catch for reliability.
- **ITokenRegistry**: `_updateRegistry` calls `initializeTokens` with a single maker and an array of `_tokenA` and `_tokenB` (if non-zero), capped at 500,000 gas. Emits `UpdateRegistryFailed` with reason and reverts on failure. Called in `update` for order creation, cancellation, or settlement.
- **ICCLiquidityTemplate**: Used for fetching liquidity data, with try-catch to ensure robust fee calculations.
- **ICCGlobalizer**: `globalizeUpdate` calls `globalizeOrders` with maker and token from the latest order (`_nextOrderId - 1`), using `_tokenB` for buy or `_tokenA` for sell, with try-catch and gas limit (gasleft/10), reverts with decoded reason on failure. Called at the end of `update`.
- **IERC20**: `transactToken` calls `transfer` for ERC20 tokens, `setTokens` calls `decimals` for normalization. `transactNative` uses low-level `call` for ETH transfers, reverting on failure.
- **Internal Call Trees**:
  - **update**:
    - Iterates `UpdateType` array to update `_volumeBalance` (`updateType=0`), buy orders (`1`), sell orders (`2`), or `_historicalData` (`3`).
    - Calls `_isSameDay` and `_floorToMidnight` to update `_lastDayFee` on volume changes.
    - Calls `removePendingOrder` for cancelled or filled orders in `_pendingBuyOrders`, `_pendingSellOrders`, `_makerPendingOrders`.
    - Calls `_updateRegistry(maker)` if maker is non-zero, followed by `globalizeUpdate()` to process the latest order.
  - **ssUpdate**: Iterates `PayoutUpdate` array, updates `_longPayouts` or `_shortPayouts`, pushes to `_longPayoutsByIndex`, `_userPayoutIDs`. No internal function calls.
  - **transactToken**, **transactNative**: Call `normalize` to update `_volumeBalance`, use `IUniswapV2Pair.getReserves` for `_currentPrice`. No other internal calls.
  - **globalizeUpdate**: Calls `ICCGlobalizer.globalizeOrders` with latest order’s maker and token, no other internal calls.
  - **_updateRegistry**: Builds dynamic token array, calls `ITokenRegistry.initializeTokens`, no other internal calls.
  - **removePendingOrder**: Modifies storage arrays, no other internal calls.
  - **_findVolumeChange**: Iterates `_historicalData`, no other internal calls.
  - **normalize**, **denormalize**, **_isSameDay**, **_floorToMidnight**: Pure functions, no internal calls.

## Security and Optimization
- **Security**:
  - Router validation (`_routers[msg.sender]`) restricts sensitive functions.
  - No `SafeERC20`, inline assembly, `virtual`/`override`, or reserved keywords.
  - Gas checks in `_updateRegistry` (500,000) and `globalizeUpdate` (gasleft/10) prevent out-of-gas failures.
  - Try-catch in external calls ensures graceful degradation.
  - Setters replace constructor arguments for flexible deployment.
  - No nested calls in struct initialization.
  - `_makerPendingOrders` depopulation prevents stale entries.
- **Optimization**:
  - `removePendingOrder` uses swap-and-pop for array resizing.
  - Normalized amounts (1e18) simplify calculations.
  - `maxIterations` and `step` limit gas in view functions.
  - Single-maker `_updateRegistry` reduces gas.
  - `globalizeUpdate` focuses on latest order, minimizing redundant calls.

## Token Usage
- **Buy Orders**: Input `_tokenB`, output `_tokenA`. `amountSent` tracks `_tokenA` sent. `yBalance` increases on creation, `xBalance` decreases on fill.
- **Sell Orders**: Input `_tokenA`, output `_tokenB`. `amountSent` tracks `_tokenB` sent. `xBalance` increases on creation, `yBalance` decreases on fill.
- **Long Payouts**: Output `_tokenB`, tracked in `LongPayoutStruct.required`.
- **Short Payouts**: Output `_tokenA`, tracked in `ShortPayoutStruct.amount`.
- **Normalization**: Uses `_decimalsA`, `_decimalsB` or `IERC20.decimals` for 1e18 precision.

## Events
- **OrderUpdated(uint256 listingId, uint256 orderId, bool isBuy, uint8 status)**: Emitted on buy/sell order creation, cancellation, or status change.
- **PayoutOrderCreated(uint256 orderId, bool isLong, uint8 status)**: Emitted on payout creation.
- **BalancesUpdated(uint256 listingId, uint256 xBalance, uint256 yBalance)**: Emitted on balance changes.
- **GlobalizerAddressSet(address globalizer)**: Emitted on `_globalizerAddress` set.
- **UpdateRegistryFailed(address user, address[] tokens, string reason)**: Emitted on `_updateRegistry` failure.

## Price Clarification
- **_currentPrice**: Updated in `update`, `transactToken`, `transactNative` using Uniswap V2 reserves (tokenB/tokenA, 1e18). Stored for `listingPriceView`.
- **prices(uint256)**: Computes price on-demand from Uniswap V2 reserves (tokenB/tokenA, 1e18), consistent with `_currentPrice`.

## Maker Orders Clarification
- **_makerPendingOrders**: Stores all order IDs (buy or sell, any status). Added in `update` when created, removed via `removePendingOrder` when cancelled or fully filled. Accessible via `makerOrdersView`, filtered by `makerPendingBuyOrdersView`, `makerPendingSellOrdersView` for pending orders (status=1).

## LastDay Initialization
- **Deployment**: `_lastDayFee` is initialized with `lastDayXFeesAcc=0`, `lastDayYFeesAcc=0`, `timestamp=0`.
- **Updates**: Occur in `update` on volume changes if `_lastDayFee.timestamp` is 0 or not same day as `block.timestamp`. Fetches `xFeesAcc`, `yFeesAcc` from `ICCLiquidityTemplate.liquidityDetail`, sets `_lastDayFee` with midnight timestamp.
