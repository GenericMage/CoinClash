# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract (^0.8.2) enables decentralized trading for a token pair, integrating with Uniswap V2 for price discovery via `IERC20.balanceOf`. It manages buy/sell orders, long/short payouts, and normalized (1e18) balances. Volumes are tracked in `_historicalData` during order settlement/cancellation, with auto-generated historical data if not router-provided. Licensed under BSL 1.1 - Peng Protocol 2025, it uses explicit casting, no inline assembly, and graceful degradation.

## Version
- **0.2.23**
- **Changes**:
  - v0.2.23: Modified `update` function to reduce `pending` amount by `filled` amount during settlement for buy/sell orders when `amountSent > 0` or `amounts.pending > 0`. Added underflow protection (`amounts.pending >= u.value`).
  - v0.2.22: Added `floorToMidnightView`, `isSameDayView`, `getDayStartIndex`. Modified `update` to determine order state using `amountSent` and `pending` amounts. For `updateType=1,2` and `structId=2`, if `amountSent > 0` or `pending > 0`, updates `filled` (settlement); else updates `pending` (new order). Moved analytics to `CCDexlytan`, removed `getFullBuyOrderDetails`, `getFullSellOrderDetails`.
  - v0.2.21: Removed `listingPrice` from `update` and `prices`, using `prices` directly. Renamed `getLastDays` to `getMidnightIndices`.
  - v0.2.20: Modified `update` to create `HistoricalData` during settlement.
- **Compatibility**: Compatible with `CCLiquidityTemplate.sol` (v0.1.3), `CCMainPartial.sol` (v0.0.14), `CCLiquidityPartial.sol` (v0.0.27), `ICCLiquidity.sol` (v0.0.5), `ICCListing.sol` (v0.0.7), `CCOrderRouter.sol` (v0.1.0), `TokenRegistry.sol` (2025-08-04), `CCUniPartial.sol` (v0.1.0), `CCOrderPartial.sol` (v0.1.0), `CCSettlementPartial.sol` (v0.1.0).

## Interfaces
- **IERC20**: Defines `decimals()`, `transfer(address, uint256)`, `balanceOf(address)`.
- **IUniswapV2Pair**: Defines `token0`, `token1`.
- **ICCLiquidityTemplate**: Defines `liquidityDetail`.
- **ITokenRegistry**: Defines `initializeTokens(address, address[])`.
- **ICCGlobalizer**: Defines `globalizeOrders(address, address)`.

## Structs
- **PayoutUpdate**: `payoutType` (0: Long, 1: Short), `recipient`, `required`, `filled`, `amountSent`.
- **DayStartFee**: `dayStartXFeesAcc`, `dayStartYFeesAcc`, `timestamp`.
- **Balance**: `xBalance`, `yBalance` (normalized, 1e18).
- **HistoricalData**: `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`.
- **BuyOrderCore**: `makerAddress`, `recipientAddress`, `status` (0: cancelled, 1: pending, 2: partially filled, 3: filled).
- **BuyOrderPricing**: `maxPrice`, `minPrice` (1e18).
- **BuyOrderAmounts**: `pending` (tokenB), `filled` (tokenB), `amountSent` (tokenA).
- **SellOrderCore**, **SellOrderPricing**, **SellOrderAmounts**: Similar, with `pending` (tokenA), `amountSent` (tokenB).
- **LongPayoutStruct**: `makerAddress`, `recipientAddress`, `required` (tokenB), `filled`, `amountSent`, `orderId`, `status`.
- **ShortPayoutStruct**: `makerAddress`, `recipientAddress`, `amount` (tokenA), `filled`, `amountSent`, `orderId`, `status`.
- **UpdateType**: `updateType` (0: balance, 1: buy, 2: sell, 3: historical), `structId`, `index`, `value`, `addr`, `recipient`, `maxPrice`, `minPrice`, `amountSent`.
- **OrderStatus**: `hasCore`, `hasPricing`, `hasAmounts`.

## Fee Segregation
`_balance` (`xBalance`, `yBalance`) tracks tokens from order creation/settlement, excluding `ICCLiquidityTemplate` fees. Buy orders (`updateType=1`, `structId=2`) add `u.value` to `yVolume`; sell orders (`updateType=2`, `structId=2`) add `u.value` to `xVolume`. Settlement: buy orders add `u.amountSent` to `xBalance`, subtract `u.value` from `yBalance`; sell orders subtract `u.value` from `xBalance`, add `u.amountSent` to `yBalance`. Fees via `ICCLiquidityTemplate.liquidityDetail`, stored in `dayStartFee`.

## State Variables
- `_routers`: `mapping(address => bool)` - Authorized routers.
- `_routersSet`: `bool` - Locks router settings.
- `tokenA`, `tokenB`: `address` - Token pair (ETH as `address(0)`).
- `decimalsA`, `decimalsB`: `uint8` - Token decimals.
- `uniswapV2PairView`, `uniswapV2PairViewSet`: `address`, `bool` - Uniswap V2 pair.
- `listingId`: `uint256` - Listing identifier.
- `agentView`: `address` - Agent address.
- `registryAddress`: `address` - Registry address.
- `liquidityAddressView`: `address` - Liquidity contract.
- `globalizerAddress`, `_globalizerSet`: `address`, `bool` - Globalizer contract.
- `nextOrderId`: `uint256` - Order ID counter.
- `dayStartFee`: `DayStartFee` - Daily fee tracking.
- `_balance`: `Balance` - Normalized balances.
- `_pendingBuyOrders`, `_pendingSellOrders`: `uint256[]` - Pending order IDs.
- `longPayoutByIndex`, `shortPayoutByIndex`: `uint256[]` - Payout IDs.
- `makerPendingOrders`: `mapping(address => uint256[])` - Maker order IDs.
- `userPayoutIDs`: `mapping(address => uint256[])` - User payout IDs.
- `_historicalData`: `HistoricalData[]` - Price/volume history.
- `_dayStartIndices`: `mapping(uint256 => uint256)` - Midnight timestamps to indices.
- `buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`: `mapping(uint256 => ...)` - Buy order data.
- `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`: `mapping(uint256 => ...)` - Sell order data.
- `longPayout`, `shortPayout`: `mapping(uint256 => ...)` - Payout data.
- `orderStatus`: `mapping(uint256 => OrderStatus)` - Order completeness.

## Functions
### External Functions
#### setGlobalizerAddress(address globalizerAddress_)
- **Purpose**: Sets `globalizerAddress` for order globalization.
- **Logic**: Sets `globalizerAddress`, `_globalizerSet=true`, emits `GlobalizerAddressSet`.
- **State Changes**: `globalizerAddress`, `_globalizerSet`.
- **Errors**: Reverts if `_globalizerSet` or `globalizerAddress_ == address(0)`.
- **Internal Call Tree**: None.

#### setUniswapV2Pair(address uniswapV2Pair_)
- **Purpose**: Sets `uniswapV2PairView` for price discovery.
- **Logic**: Sets `uniswapV2PairView`, `uniswapV2PairViewSet=true`.
- **State Changes**: `uniswapV2PairView`, `uniswapV2PairViewSet`.
- **Errors**: Reverts if `uniswapV2PairViewSet` or `uniswapV2Pair_ == address(0)`.
- **Internal Call Tree**: None.

#### setRouters(address[] memory routers_)
- **Purpose**: Authorizes routers for updates.
- **Logic**: Sets `_routers[router]=true` for each `routers_`, sets `_routersSet=true`.
- **State Changes**: `_routers`, `_routersSet`.
- **Errors**: Reverts if `_routersSet`, `routers_.length == 0`, or any `routers_[i] == address(0)`.
- **Internal Call Tree**: None.

#### setListingId(uint256 _listingId)
- **Purpose**: Sets `listingId` for the contract.
- **Logic**: Sets `listingId`.
- **State Changes**: `listingId`.
- **Errors**: Reverts if `listingId != 0`.
- **Internal Call Tree**: None.

#### setLiquidityAddress(address _liquidityAddress)
- **Purpose**: Sets `liquidityAddressView` for fee queries.
- **Logic**: Sets `liquidityAddressView`.
- **State Changes**: `liquidityAddressView`.
- **Errors**: Reverts if `liquidityAddressView != address(0)` or `_liquidityAddress == address(0)`.
- **Internal Call Tree**: None.

#### setTokens(address _tokenA, address _tokenB)
- **Purpose**: Initializes `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `_historicalData`, `dayStartFee`.
- **Logic**: Sets tokens, fetches decimals via `IERC20.decimals`, initializes `_historicalData` with a zeroed entry at midnight, sets `_dayStartIndices[midnight]=0`, and initializes `dayStartFee` with midnight timestamp.
- **State Changes**: `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `_historicalData`, `_dayStartIndices`, `dayStartFee`.
- **External Interactions**: `IERC20.decimals`.
- **Internal Call Tree**: `_floorToMidnight`.
- **Errors**: Reverts if tokens already set, `_tokenA == _tokenB`, or both `address(0)`.

#### setAgent(address _agent)
- **Purpose**: Sets `agentView` for the contract.
- **Logic**: Sets `agentView`.
- **State Changes**: `agentView`.
- **Errors**: Reverts if `agentView != address(0)` or `_agent == address(0)`.
- **Internal Call Tree**: None.

#### setRegistry(address registryAddress_)
- **Purpose**: Sets `registryAddress` for token balance updates.
- **Logic**: Sets `registryAddress`.
- **State Changes**: `registryAddress`.
- **Errors**: Reverts if `registryAddress != address(0)` or `registryAddress_ == address(0)`.
- **Internal Call Tree**: None.

#### ssUpdate(PayoutUpdate[] calldata updates)
- **Purpose**: Processes long/short payouts.
- **Logic**: For each `PayoutUpdate`, creates/updates `longPayout` or `shortPayout`, sets `filled=0` for new payouts, updates `filled`, `amountSent`, `status`, adds to `longPayoutByIndex` or `shortPayoutByIndex` and `userPayoutIDs`, increments `nextOrderId`. Emits `PayoutOrderCreated` for new payouts, `PayoutOrderUpdated` for updates.
- **State Changes**: `longPayout`, `shortPayout`, `longPayoutByIndex`, `shortPayoutByIndex`, `userPayoutIDs`, `nextOrderId`.
- **Errors**: Emits `UpdateFailed` for invalid inputs.
- **Internal Call Tree**: None.

#### update(UpdateType[] calldata updates)
- **Purpose**: Updates balances, buy/sell orders, or historical data.
- **Logic**: Requires `_routers[msg.sender]`. Processes updates via `_processBalanceUpdate` (`updateType=0`), `_processBuyOrderUpdate` (`updateType=1`), `_processSellOrderUpdate` (`updateType=2`), or `_processHistoricalUpdate` (`updateType=3`). Updates `_balance`, order mappings (`buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`, etc.), `_pendingBuyOrders`, `_pendingSellOrders`, `makerPendingOrders`, `_historicalData`, `_dayStartIndices`, `dayStartFee`. For `structId=2`, if `amountSent > 0` or `pending > 0` (settlement), sets `filled` and reduces `pending` by `filled` amount with underflow protection; else sets `pending` (new order). Auto-generates `_historicalData` for settlement/cancellation, updates fees via `ICCLiquidityTemplate.liquidityDetail`, calls `globalizeUpdate`.
- **State Changes**: `_balance`, order mappings, `_pendingBuyOrders`, `_pendingSellOrders`, `makerPendingOrders`, `orderStatus`, `_historicalData`, `_dayStartIndices`, `dayStartFee`, `nextOrderId`.
- **External Interactions**: `IUniswapV2Pair.token0`, `IERC20.balanceOf`, `ITokenRegistry.initializeTokens`, `ICCLiquidityTemplate.liquidityDetail`, `ICCGlobalizer.globalizeOrders`.
- **Internal Call Tree**: `_processBalanceUpdate`, `_processBuyOrderUpdate`, `_processSellOrderUpdate`, `_processHistoricalUpdate`, `removePendingOrder`, `_updateRegistry`, `globalizeUpdate`, `_floorToMidnight`, `_isSameDay`.
- **Errors**: Emits `UpdateFailed`, `OrderUpdateIncomplete`, `OrderUpdatesComplete`.

#### getTokens() returns (address tokenA_, address tokenB_)
- **Purpose**: Returns the token pair.
- **Logic**: Returns `tokenA`, `tokenB`.
- **Errors**: Reverts if both `address(0)`.
- **Internal Call Tree**: None.

#### prices(uint256) returns (uint256 price)
- **Purpose**: Computes the current price from Uniswap V2 pair balances.
- **Logic**: Calls `IERC20.balanceOf(uniswapV2PairView)` for `tokenA` and `tokenB`, normalizes balances, computes `(balanceB * 1e18) / balanceA`.
- **External Interactions**: `IERC20.balanceOf`.
- **Internal Call Tree**: `normalize`.
- **Errors**: Returns 0 or 1 on failure.

#### volumeBalances(uint256) returns (uint256 xBalance, uint256 yBalance)
- **Purpose**: Returns normalized contract balances.
- **Logic**: Fetches `IERC20.balanceOf(address(this))` or ETH balance for `tokenA`, `tokenB`, normalizes using `normalize`.
- **External Interactions**: `IERC20.balanceOf`.
- **Internal Call Tree**: `normalize`.

#### makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns up to `maxIterations` pending buy order IDs for `maker` starting from `step`.
- **Logic**: Filters `makerPendingOrders[maker]` for `buyOrderCore.status == 1`, slices from `step`.
- **Internal Call Tree**: None.

#### makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns up to `maxIterations` pending sell order IDs for `maker` starting from `step`.
- **Logic**: Filters `makerPendingOrders[maker]` for `sellOrderCore.status == 1`, slices from `step`.
- **Internal Call Tree**: None.

#### getBuyOrderCore(uint256 orderId) returns (address makerAddress, address recipientAddress, uint8 status)
- **Purpose**: Returns buy order core details.
- **Logic**: Returns `buyOrderCore[orderId]`.
- **Internal Call Tree**: None.

#### getBuyOrderPricing(uint256 orderId) returns (uint256 maxPrice, uint256 minPrice)
- **Purpose**: Returns buy order pricing details.
- **Logic**: Returns `buyOrderPricing[orderId]`.
- **Internal Call Tree**: None.

#### getBuyOrderAmounts(uint256 orderId) returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Purpose**: Returns buy order amounts.
- **Logic**: Returns `buyOrderAmounts[orderId]`.
- **Internal Call Tree**: None.

#### getSellOrderCore(uint256 orderId) returns (address makerAddress, address recipientAddress, uint8 status)
- **Purpose**: Returns sell order core details.
- **Logic**: Returns `sellOrderCore[orderId]`.
- **Internal Call Tree**: None.

#### getSellOrderPricing(uint256 orderId) returns (uint256 maxPrice, uint256 minPrice)
- **Purpose**: Returns sell order pricing details.
- **Logic**: Returns `sellOrderPricing[orderId]`.
- **Internal Call Tree**: None.

#### getSellOrderAmounts(uint256 orderId) returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Purpose**: Returns sell order amounts.
- **Logic**: Returns `sellOrderAmounts[orderId]`.
- **Internal Call Tree**: None.

#### makerOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns up to `maxIterations` order IDs for `maker` starting from `step`.
- **Logic**: Slices `makerPendingOrders[maker]` from `step`, capped by `maxIterations`.
- **Internal Call Tree**: None.

#### makerPendingOrdersView(address maker) returns (uint256[] memory orderIds)
- **Purpose**: Returns all pending order IDs for `maker`.
- **Logic**: Returns `makerPendingOrders[maker]`.
- **Internal Call Tree**: None.

#### longPayoutByIndexView() returns (uint256[] memory orderIds)
- **Purpose**: Returns all long payout order IDs.
- **Logic**: Returns `longPayoutByIndex`.
- **Internal Call Tree**: None.

#### shortPayoutByIndexView() returns (uint256[] memory orderIds)
- **Purpose**: Returns all short payout order IDs.
- **Logic**: Returns `shortPayoutByIndex`.
- **Internal Call Tree**: None.

#### userPayoutIDsView(address user) returns (uint256[] memory orderIds)
- **Purpose**: Returns payout order IDs for `user`.
- **Logic**: Returns `userPayoutIDs[user]`.
- **Internal Call Tree**: None.

#### getHistoricalDataView(uint256 index) returns (HistoricalData memory data)
- **Purpose**: Returns `_historicalData[index]`.
- **Logic**: Returns data at `index`, reverts if invalid.
- **Errors**: Reverts if `index >= _historicalData.length`.
- **Internal Call Tree**: None.

#### historicalDataLengthView() returns (uint256 length)
- **Purpose**: Returns `_historicalData.length`.
- **Logic**: Returns the length of `_historicalData`.
- **Internal Call Tree**: None.

#### floorToMidnightView(uint256 inputTimestamp) returns (uint256 midnight)
- **Purpose**: Rounds a timestamp to the start of its day (midnight UTC).
- **Logic**: Computes `(inputTimestamp / 86400) * 86400`.
- **Internal Call Tree**: None.
- **Usage**: Used by external contracts (e.g., `CCDexlytan`) for time-based queries.

#### isSameDayView(uint256 firstTimestamp, uint256 secondTimestamp) returns (bool sameDay)
- **Purpose**: Checks if two timestamps are in the same calendar day (UTC).
- **Logic**: Returns `(firstTimestamp / 86400) == (secondTimestamp / 86400)`.
- **Internal Call Tree**: None.
- **Usage**: Used by external contracts (e.g., `CCDexlytan`) for fee/time checks.

#### getDayStartIndex(uint256 midnightTimestamp) returns (uint256 index)
- **Purpose**: Returns the `_historicalData` index for a given midnight timestamp.
- **Logic**: Returns `_dayStartIndices[midnightTimestamp]`, or 0 if unset.
- **Internal Call Tree**: None.
- **Usage**: Used by external contracts (e.g., `CCDexlytan`) for historical data queries.

### Internal Functions
#### normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)
- **Purpose**: Normalizes amounts to 1e18 precision.
- **Logic**: Adjusts `amount` based on `decimals` relative to 18.
- **Callers**: Called by `update`, `prices`, `volumeBalances`.

#### denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)
- **Purpose**: Converts amounts from 1e18 to token decimals.
- **Logic**: Adjusts `amount` based on `decimals` relative to 18.
- **Callers**: None in v0.2.23.

#### _isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)
- **Purpose**: Checks if two timestamps are in the same calendar day.
- **Logic**: Returns `(time1 / 86400) == (time2 / 86400)`.
- **Callers**: `update` (for `dayStartFee` vs. `block.timestamp` in fee updates).

#### _floorToMidnight(uint256 timestamp) returns (uint256 midnight)
- **Purpose**: Rounds a timestamp to midnight UTC.
- **Logic**: Returns `(timestamp / 86400) * 86400`.
- **Callers**: `setTokens` (initializes `_historicalData`, `dayStartFee`), `update` (sets `_dayStartIndices`, `dayStartFee`).

#### _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)
- **Purpose**: Returns volume from `_historicalData` at or after `startTime`.
- **Logic**: Iterates `_historicalData` backward, returns `xVolume` or `yVolume` based on `isA`.
- **Callers**: None in v0.2.23 (moved to `CCDexlytan`).

#### _updateRegistry(address maker)
- **Purpose**: Updates `ITokenRegistry` with `tokenA`, `tokenB` balances.
- **Logic**: Calls `ITokenRegistry.initializeTokens` with `maker` and token array.
- **Callers**: `update` (after order processing).
- **External Interactions**: `ITokenRegistry.initializeTokens`.
- **Errors**: Emits `RegistryUpdateFailed`, `ExternalCallFailed`.

#### removePendingOrder(uint256[] storage orders, uint256 orderId)
- **Purpose**: Removes `orderId` from `_pendingBuyOrders`, `_pendingSellOrders`, or `makerPendingOrders`.
- **Logic**: Swaps `orderId` with the last element and pops the array.
- **Callers**: `update` (when `status=0` for cancelled orders).

#### globalizeUpdate()
- **Purpose**: Calls `ICCGlobalizer.globalizeOrders` for the latest order.
- **Logic**: Calls `globalizeOrders` with `makerAddress` and `tokenA` or `tokenB`.
- **Callers**: `update` (after processing updates).
- **External Interactions**: `ICCGlobalizer.globalizeOrders`.
- **Errors**: Emits `ExternalCallFailed`, `globalUpdateFailed`.

#### _processBalanceUpdate(UpdateType calldata u)
- **Purpose**: Updates `_balance` for `updateType=0`.
- **Logic**: Sets `xBalance` or `yBalance` based on `u.index`.
- **Callers**: `update`.

#### _processBuyOrderUpdate(UpdateType calldata u, uint256[] memory updatedOrders, uint256 updatedCount)
- **Purpose**: Updates buy orders for `updateType=1`.
- **Logic**: Updates `buyOrderCore`, `buyOrderPricing`, or `buyOrderAmounts`, manages `_pendingBuyOrders`, `makerPendingOrders`, `orderStatus`.
- **Callers**: `update`.

#### _processSellOrderUpdate(UpdateType calldata u, uint256[] memory updatedOrders, uint256 updatedCount)
- **Purpose**: Updates sell orders for `updateType=2`.
- **Logic**: Updates `sellOrderCore`, `sellOrderPricing`, or `sellOrderAmounts`, manages `_pendingSellOrders`, `makerPendingOrders`, `orderStatus`.
- **Callers**: `update`.

#### _processHistoricalUpdate(UpdateType calldata u)
- **Purpose**: Updates `_historicalData` for `updateType=3`.
- **Logic**: Adds or updates `_historicalData` with `u.value` as price, current `_balance`, and timestamp.
- **Callers**: `update`.

#### uint2str(uint256 _i) returns (string str)
- **Purpose**: Converts uint to string for error messages.
- **Logic**: Converts `_i` to a string representation.
- **Callers**: None in v0.2.23.

## Parameters and Interactions
- **Orders** (`UpdateType`): 
  - `updateType=0`: Updates `_balance` (`xBalance`, `yBalance`).
  - `updateType=1` (Buy): Inputs `tokenB` (`value` as filled), outputs `tokenA` (`amountSent`). Creation adds to `yVolume`. Settlement (`amountSent > 0` or `pending > 0`) sets `filled`, reduces `pending` by `filled` (with underflow protection), updates `yVolume`. Cancellation (`status=0`) sets `pending=0`, updates `yVolume`.
  - `updateType=2` (Sell): Inputs `tokenA` (`value` as filled), outputs `tokenB` (`amountSent`). Creation adds to `xVolume`. Settlement (`amountSent > 0` or `pending > 0`) sets `filled`, reduces `pending` by `filled` (with underflow protection), updates `xVolume`. Cancellation (`status=0`) sets `pending=0`, updates `xVolume`.
  - For `structId=2`, settlement updates `filled`, reduces `pending`, sets `amountSent`; new orders set `pending`. Tracked via `orderStatus`, emits `OrderUpdatesComplete`/`OrderUpdateIncomplete`.
- **Payouts** (`PayoutUpdate`): Long (`payoutType=0`, `tokenB`), short (`payoutType=1`, `tokenA`) via `ssUpdate`, indexed by `nextOrderId`. Supports `filled`, `amountSent` updates.
- **Price**: Computed via `IUniswapV2Pair`, `IERC20.balanceOf(uniswapV2PairView)`, using `prices` function.
- **Registry**: Updated via `_updateRegistry` in `update`.
- **Globalizer**: Updated via `globalizeUpdate` in `update`.
- **Liquidity**: `ICCLiquidityTemplate.liquidityDetail` used in `update`.
- **Historical Data**: Stored in `_historicalData` via `update` (`updateType=3`) or auto-generated for settlement/cancellation, using Uniswap V2 price via `prices`, carrying forward volumes. `_dayStartIndices` maps midnight timestamps to `_historicalData` indices, accessible via `getDayStartIndex`.
- **External Calls**: `IERC20.balanceOf`, `IERC20.transfer`, `IERC20.decimals`, `ITokenRegistry.initializeTokens`, `ICCLiquidityTemplate.liquidityDetail`, `ICCGlobalizer.globalizeOrders`.
- **Security**: Router checks, try-catch, explicit casting, no tuple access, relaxed validation, emits `UpdateFailed`.
- **Optimization**: Normalized amounts, `maxIterations`, auto-generated historical data, helper functions in `update`.
