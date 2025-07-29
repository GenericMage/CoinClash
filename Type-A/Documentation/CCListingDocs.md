# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract, implemented in Solidity (^0.8.2), manages buy/sell orders, payouts, and volume balances on a decentralized trading platform, integrating with Uniswap V2 for price derivation. It inherits `ReentrancyGuard` for security and uses `IERC20` for token operations, interfacing with `ICCAgent`, `ITokenRegistry`, `IUniswapV2Pair`, and `ICCLiquidityTemplate` for global updates, synchronization, reserve fetching, and liquidity amounts. State variables are private, accessed via view functions with unique names, and amounts are normalized to 1e18 for precision. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.0.8 (Updated 2025-07-29)

**Compatibility**: 
- CCAgent.sol (v0.0.5)
- CCLiquidityTemplate.sol (v0.0.5)
- CCLiquidityRouter.sol (v0.0.12)
- CCMainPartial.sol (v0.0.8)

**Version History**:
- v0.0.8: Added explicit gas limit (500000) to `ITokenRegistry.initializeBalances` call in `_updateRegistry` to prevent out-of-gas errors, preserving try-catch for graceful degradation (lines 308-330).
- v0.0.7: Added explicit gas limit (1000000) to `ICCAgent.globalizeOrders` calls in `globalizeUpdate` to prevent out-of-gas errors, preserving try-catch for graceful degradation (lines 375-400).
- v0.0.6: Updated `ICCListing` interface and `liquidityAddressView` to remove uint256 parameter (lines 40, 669).
- v0.0.5: Added `agentView` function to return `_agent` (line 622).

## State Variables
- `_routers`: `mapping(address => bool) private` - Authorized routers.
- `_routersSet`: `bool private` - Prevents router re-setting.
- `_tokenA`: `address private` - Token A (ETH if zero).
- `_tokenB`: `address private` - Token B (ETH if zero).
- `_decimalsA`: `uint8 private` - Token A decimals (18 for ETH).
- `_decimalsB`: `uint8 private` - Token B decimals (18 for ETH).
- `_uniswapV2Pair`: `address private` - Uniswap V2 pair address.
- `_uniswapV2PairSet`: `bool private` - Prevents pair re-setting.
- `_listingId`: `uint256 private` - Unique listing identifier.
- `_agent`: `address private` - Agent contract address.
- `_registryAddress`: `address private` - Token registry address.
- `_liquidityAddress`: `address private` - Liquidity contract address.
- `_nextOrderId`: `uint256 private` - Next order ID.
- `_lastDayFee`: `LastDayFee private` - Daily fee tracking (`xFees`, `yFees`, `timestamp`).
- `_volumeBalance`: `VolumeBalance private` - Balances and volumes (`xBalance`, `yBalance`, `xVolume`, `yVolume`).
- `_currentPrice`: `uint256 private` - Price from Uniswap V2 reserves.
- `_pendingBuyOrders`: `uint256[] private` - Pending buy order IDs.
- `_pendingSellOrders`: `uint256[] private` - Pending sell order IDs.
- `_longPayoutsByIndex`: `uint256[] private` - Long payout order IDs.
- `_shortPayoutsByIndex`: `uint256[] private` - Short payout order IDs.
- `_makerPendingOrders`: `mapping(address => uint256[]) private` - Maker’s pending order IDs.
- `_userPayoutIDs`: `mapping(address => uint256[]) private` - User’s payout order IDs.
- `_historicalData`: `HistoricalData[] private` - Historical market data.

## Mappings
- `_routers`: Authorized routers.
- `_buyOrderCores`: `mapping(uint256 => BuyOrderCore)` - Buy order core data.
- `_buyOrderPricings`: `mapping(uint256 => BuyOrderPricing)` - Buy order pricing.
- `_buyOrderAmounts`: `mapping(uint256 => BuyOrderAmounts)` - Buy order amounts.
- `_sellOrderCores`: `mapping(uint256 => SellOrderCore)` - Sell order core data.
- `_sellOrderPricings`: `mapping(uint256 => SellOrderPricing)` - Sell order pricing.
- `_sellOrderAmounts`: `mapping(uint256 => SellOrderAmounts)` - Sell order amounts.
- `_longPayouts`: `mapping(uint256 => LongPayoutStruct)` - Long payout data.
- `_shortPayouts`: `mapping(uint256 => ShortPayoutStruct)` - Short payout data.
- `_makerPendingOrders`: Maker’s pending orders.
- `_userPayoutIDs`: User’s payout IDs.

## Structs
1. **LastDayFee**:
   - `xFees`: `uint256` - Token A fees at day start.
   - `yFees`: `uint256` - Token B fees at day start.
   - `timestamp`: `uint256` - Last fee update timestamp.
2. **VolumeBalance**:
   - `xBalance`: `uint256` - Normalized token A balance.
   - `yBalance`: `uint256` - Normalized token B balance.
   - `xVolume`: `uint256` - Normalized token A volume.
   - `yVolume`: `uint256` - Normalized token B volume.
3. **BuyOrderCore**:
   - `makerAddress`: `address` - Order creator.
   - `recipientAddress`: `address` - Token recipient.
   - `status`: `uint8` - Order status (0=cancelled, 1=pending, 2=partially filled, 3=filled).
4. **BuyOrderPricing**:
   - `maxPrice`: `uint256` - Maximum acceptable price (normalized).
   - `minPrice`: `uint256` - Minimum acceptable price (normalized).
5. **BuyOrderAmounts**:
   - `pending`: `uint256` - Normalized pending amount (tokenB).
   - `filled`: `uint256` - Normalized filled amount (tokenB).
   - `amountSent`: `uint256` - Normalized amount of tokenA sent.
6. **SellOrderCore**:
   - Same as `BuyOrderCore`.
7. **SellOrderPricing**:
   - Same as `BuyOrderPricing`.
8. **SellOrderAmounts**:
   - `pending`: `uint256` - Normalized pending amount (tokenA).
   - `filled`: `uint256` - Normalized filled amount (tokenA).
   - `amountSent`: `uint256` - Normalized amount of tokenB sent.
9. **PayoutUpdate**:
   - `payoutType`: `uint8` - Payout type (0=long, 1=short).
   - `recipient`: `address` - Payout recipient.
   - `required`: `uint256` - Normalized amount required.
10. **LongPayoutStruct**:
    - `makerAddress`: `address` - Payout creator.
    - `recipientAddress`: `address` - Payout recipient.
    - `required`: `uint256` - Normalized amount required (tokenB).
    - `filled`: `uint256` - Normalized amount filled (tokenB).
    - `orderId`: `uint256` - Unique payout order ID.
    - `status`: `uint8` - Payout status (0=pending).
11. **ShortPayoutStruct**:
    - `makerAddress`: `address` - Payout creator.
    - `recipientAddress`: `address` - Payout recipient.
    - `amount`: `uint256` - Normalized payout amount (tokenA).
    - `filled`: `uint256` - Normalized amount filled (tokenA).
    - `orderId`: `uint256` - Unique payout order ID.
    - `status`: `uint8` - Payout status (0=pending).
12. **HistoricalData**:
    - `price`: `uint256` - Normalized price from Uniswap V2 reserves.
    - `xBalance`: `uint256` - Normalized token A balance.
    - `yBalance`: `uint256` - Normalized token B balance.
    - `xVolume`: `uint256` - Normalized token A volume.
    - `yVolume`: `uint256` - Normalized token B volume.
    - `timestamp`: `uint256` - Snapshot timestamp.
13. **UpdateType**:
    - `updateType`: `uint8` - Update type (0=balance, 1=buy order, 2=sell order, 3=historical).
    - `structId`: `uint8` - Struct to update (0=core, 1=pricing, 2=amounts).
    - `index`: `uint256` - Order ID or balance index (0=xBalance, 1=yBalance, 2=xVolume, 3=yVolume).
    - `value`: `uint256` - Normalized amount or price.
    - `addr`: `address` - Maker address.
    - `recipient`: `address` - Recipient address.
    - `maxPrice`: `uint256` - Max price or packed xBalance/yBalance (historical).
    - `minPrice`: `uint256` - Min price or packed xVolume/yVolume (historical).
    - `amountSent`: `uint256` - Normalized amount of opposite token sent.

## Formulas
1. **Price Calculation**:
   - **Formula**: `price = (normalizedReserveA * 1e18) / normalizedReserveB`
   - **Used in**: `update`, `transactToken`, `transactNative`, `prices`
   - **Description**: Computes price from Uniswap V2 reserves, normalized to 1e18 using `decimalsA`/`decimalsB`. Returns 0 if reserves are zero.
2. **Daily Yield**:
   - **Formula**: `dailyYield = ((feeDifference * 0.0005) * 1e18) / liquidity * 365`
   - **Used in**: `queryYield`
   - **Description**: Calculates annualized yield from fee difference (`xVolume - lastDayFee.xFees` or `yVolume - lastDayFee.yFees`), using 0.05% fee rate and liquidity from `ICCLiquidityTemplate.liquidityAmounts`.

## External Functions
### setUniswapV2Pair(address uniswapV2Pair_)
- **Parameters**: `uniswapV2Pair_` - Uniswap V2 pair address.
- **Behavior**: Sets `_uniswapV2Pair`, callable once.
- **Internal Call Flow**: Updates `_uniswapV2Pair`, `_uniswapV2PairSet`.
- **Restrictions**: Reverts if already set or address is zero.
- **Gas Usage Controls**: Minimal, two state writes.

### queryYield(bool isA, uint256 maxIterations)
- **Parameters**:
  - `isA`: True for tokenA, false for tokenB.
  - `maxIterations`: Max historical data iterations.
- **Behavior**: Returns annualized yield based on daily fees.
- **Internal Call Flow**:
  - Checks `_lastDayFee.timestamp` for same-day.
  - Computes `feeDifference` from `_volumeBalance` and `_lastDayFee`.
  - Fetches liquidity via `ICCLiquidityTemplate.liquidityAmounts`.
  - Calculates yield using formula.
- **Balance Checks**: None, relies on external call.
- **Restrictions**: Reverts if `maxIterations` is zero or no same-day data.
- **Gas Usage Controls**: Single external call, try-catch.

### setRouters(address[] memory routers_)
- **Parameters**: `routers_` - Array of router addresses.
- **Behavior**: Sets authorized routers, callable once.
- **Internal Call Flow**: Updates `_routers`, sets `_routersSet`.
- **Restrictions**: Reverts if already set or array is empty/invalid.
- **Gas Usage Controls**: Single loop, minimal state writes.

### setListingId(uint256 listingId_)
- **Parameters**: `listingId_` - Listing ID.
- **Behavior**: Sets `_listingId`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if already set.
- **Gas Usage Controls**: Minimal, single state write.

### setLiquidityAddress(address liquidityAddress_)
- **Parameters**: `liquidityAddress_` - Liquidity contract address.
- **Behavior**: Sets `_liquidityAddress`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

### setTokens(address tokenA_, address tokenB_)
- **Parameters**: `tokenA_`, `tokenB_` - Token addresses.
- **Behavior**: Sets `_tokenA`, `_tokenB`, `_decimalsA`, `_decimalsB`, callable once.
- **Internal Call Flow**: Fetches decimals via `IERC20.decimals` (18 for ETH).
- **Restrictions**: Reverts if already set, tokens are same, both zero, or invalid decimals.
- **Gas Usage Controls**: Minimal, state writes, external calls.

### setAgent(address agent_)
- **Parameters**: `agent_` - Agent contract address.
- **Behavior**: Sets `_agent`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

### setRegistry(address registryAddress_)
- **Parameters**: `registryAddress_` - Registry contract address.
- **Behavior**: Sets `_registryAddress`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

### agentView() view returns (address)
- **Behavior**: Returns `_agent`.
- **Gas Usage Controls**: Minimal, single state read.

### update(address caller, UpdateType[] memory updates)
- **Parameters**:
  - `caller`: Router address.
  - `updates`: Array of update structs.
- **Behavior**: Updates balances, orders, or historical data, derives price, triggers `globalizeUpdate`.
- **Internal Call Flow**:
  - Updates `_lastDayFee` if new day.
  - Processes updates:
    - `updateType=0`: Updates `xBalance`, `yBalance`, `xVolume`, `yVolume`.
    - `updateType=1`: Updates buy order data, adjusts arrays, balances.
    - `updateType=2`: Updates sell order data, adjusts arrays, balances.
    - `updateType=3`: Adds `HistoricalData` with Uniswap V2 price.
  - Updates `_currentPrice`, calls `globalizeUpdate`, emits `BalancesUpdated` or `OrderUpdated`.
- **Balance Checks**: Ensures sufficient balances for orders.
- **Mappings/Structs Used**: `_buyOrderCores`, `_buyOrderPricings`, `_buyOrderAmounts`, `_sellOrderCores`, `_sellOrderPricings`, `_sellOrderAmounts`, `_pendingBuyOrders`, `_pendingSellOrders`, `_makerPendingOrders`, `_historicalData`, `UpdateType`, `VolumeBalance`.
- **Restrictions**: `nonReentrant`, requires `_routers[caller]`.
- **Gas Usage Controls**: Dynamic array resizing, loop over updates, external reserve calls, `globalizeUpdate` with gas limit (1000000).

### ssUpdate(address caller, PayoutUpdate[] memory payoutUpdates)
- **Parameters**:
  - `caller`: Router address.
  - `payoutUpdates`: Array of payout updates.
- **Behavior**: Creates long/short payouts, increments `_nextOrderId`.
- **Internal Call Flow**:
  - Creates `LongPayoutStruct` or `ShortPayoutStruct`, updates `_longPayoutsByIndex`, `_shortPayoutsByIndex`, `_userPayoutIDs`.
  - Emits `PayoutOrderCreated`.
- **Balance Checks**: None, defers to `transactToken` or `transactNative`.
- **Mappings/Structs Used**: `_longPayouts`, `_shortPayouts`, `_longPayoutsByIndex`, `_shortPayoutsByIndex`, `_userPayoutIDs`, `PayoutUpdate`, `LongPayoutStruct`, `ShortPayoutStruct`.
- **Restrictions**: `nonReentrant`, requires `_routers[caller]`.
- **Gas Usage Controls**: Loop over `payoutUpdates`, dynamic arrays.

### transactToken(address caller, address token, uint256 amount, address recipient)
- **Parameters**:
  - `caller`: Router address.
  - `token`: TokenA or tokenB (non-zero).
  - `amount`: Denormalized amount.
  - `recipient`: Recipient address.
- **Behavior**: Transfers ERC20, updates balances/volumes, derives price, updates registry.
- **Internal Call Flow**:
  - Normalizes amount, checks balance.
  - Transfers via `IERC20.transfer`.
  - Updates `_lastDayFee`, `_currentPrice`, emits `BalancesUpdated`.
  - Calls `_updateRegistry` with gas limit (500000).
- **Balance Checks**: Requires sufficient balance.
- **Mappings/Structs Used**: `_volumeBalance`, `VolumeBalance`.
- **Restrictions**: `nonReentrant`, requires `_routers[caller]`, valid token.
- **Gas Usage Controls**: Single transfer, minimal updates, reserve call, registry call with gas limit.

### transactNative(address caller, uint256 amount, address recipient)
- **Parameters**:
  - `caller`: Router address.
  - `amount`: Denormalized ETH amount.
  - `recipient`: Recipient address.
- **Behavior**: Transfers ETH, updates balances/volumes, derives price, updates registry.
- **Internal Call Flow**:
  - Normalizes amount, checks balance.
  - Transfers ETH via low-level call with try-catch.
  - Updates `_lastDayFee`, `_currentPrice`, emits `BalancesUpdated`.
  - Calls `_updateRegistry` with gas limit (500000).
- **Balance Checks**: Requires sufficient balance.
- **Mappings/Structs Used**: `_volumeBalance`, `VolumeBalance`.
- **Restrictions**: `nonReentrant`, requires `_routers[caller]`, one token must be ETH.
- **Gas Usage Controls**: Single transfer, try-catch, reserve call, registry call with gas limit.

### View Functions
- **uniswapV2PairView()**: Returns `_uniswapV2Pair`.
- **prices(uint256)**: Returns price from Uniswap V2 reserves.
- **getTokens()**: Returns `_tokenA`, `_tokenB`.
- **volumeBalances(uint256)**: Returns `xBalance`, `yBalance`.
- **liquidityAddressView()**: Returns `_liquidityAddress`.
- **tokenA()**: Returns `_tokenA`.
- **tokenB()**: Returns `_tokenB`.
- **decimalsA()**: Returns `_decimalsA`.
- **decimalsB()**: Returns `_decimalsB`.
- **getListingId()**: Returns `_listingId`.
- **getNextOrderId()**: Returns `_nextOrderId`.
- **listingVolumeBalancesView()**: Returns `xBalance`, `yBalance`, `xVolume`, `yVolume`.
- **listingPriceView()**: Returns `_currentPrice`.
- **pendingBuyOrdersView()**: Returns `_pendingBuyOrders`.
- **pendingSellOrdersView()**: Returns `_pendingSellOrders`.
- **makerPendingOrdersView(address)**: Returns maker’s pending orders.
- **longPayoutByIndexView()**: Returns `_longPayoutsByIndex`.
- **shortPayoutByIndexView()**: Returns `_shortPayoutsByIndex`.
- **userPayoutIDsView(address)**: Returns user’s payout IDs.
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
  - `nonReentrant` on state-changing functions.
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
