# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract (Solidity ^0.8.2) supports decentralized trading for a token pair, using Uniswap V2 for price discovery via `IERC20.balanceOf`. It manages buy and sell orders, long and short payouts, and normalized (1e18 precision) balances. Volumes are tracked in `_historicalData` during order settlement or cancellation, with auto-generated historical data if not provided by routers. Licensed under BSL 1.1 - Peng Protocol 2025, it uses explicit casting, avoids inline assembly, and ensures graceful degradation with try-catch for external calls.

## Version
- **0.2.23**
- **Changes**:
  - v0.2.23: Modified `update` function to reduce `pending` amount by `filled` amount during settlement for buy and sell orders when `amountSent > 0` or `amounts.pending > 0`. Added underflow protection (`amounts.pending >= u.value`).
  - v0.2.22: Added `floorToMidnightView` to expose `_floorToMidnight`, `isSameDayView` to expose `_isSameDay`, and `getDayStartIndex` to expose `_dayStartIndices`. Removed `getMidnightIndicies`. Modified `update` to determine order state using `amountSent` and `pending` amounts. For `updateType=1,2` and `structId=2`, if `amountSent > 0` or `pending > 0`, updates `filled` (settlement); else updates `pending` (new order). Removed Core struct validation. Moved analytics to `CCDexlytan`, added required views. Removed `getFullBuyOrderDetails` and `getFullSellOrderDetails`.
  - v0.2.21: Removed `listingPrice` from `update` and `prices`, using `prices` directly for price computation. Renamed `getLastDays` to `getMidnightIndices` with clarified comments.
  - v0.2.20: Modified `update` to always create a `HistoricalData` entry during settlement, preserving day-counting for view functions.
- **Compatibility**: Compatible with `CCLiquidityTemplate.sol` (v0.1.3), `CCMainPartial.sol` (v0.0.14), `CCLiquidityPartial.sol` (v0.0.27), `ICCLiquidity.sol` (v0.0.5), `ICCListing.sol` (v0.0.7), `CCOrderRouter.sol` (v0.1.0), `TokenRegistry.sol` (2025-08-04), `CCUniPartial.sol` (v0.1.0), `CCOrderPartial.sol` (v0.1.0), `CCSettlementPartial.sol` (v0.1.0).

## Interfaces
- **IERC20**: Defines `decimals()`, `transfer(address, uint256)`, `balanceOf(address)`.
- **IUniswapV2Pair**: Defines `token0()`, `token1()`.
- **ICCLiquidityTemplate**: Defines `liquidityDetail()`.
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
- **UpdateType**: `updateType` (0: balance, 1: buy, 2: sell, 3: historical), `structId` (0: Core, 1: Pricing, 2: Amounts), `index`, `value`, `addr`, `recipient`, `maxPrice`, `minPrice`, `amountSent`.
- **OrderStatus**: `hasCore`, `hasPricing`, `hasAmounts`.

## Fee Segregation
`_balance` (`xBalance`, `yBalance`) tracks tokens from order creation/settlement, excluding `ICCLiquidityTemplate` fees. Buy orders (`updateType=1`, `structId=2`) add `u.value` to `yVolume`; sell orders (`updateType=2`, `structId=2`) add `u.value` to `xVolume`. Settlement: buy orders add `u.amountSent` to `xBalance`, subtract `u.value` from `yBalance`; sell orders subtract `u.value` from `xBalance`, add `u.amountSent` to `yBalance`. Fees are fetched via `ICCLiquidityTemplate.liquidityDetail`, stored in `dayStartFee`.

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
- **Purpose**: Sets the address for the globalizer contract to handle order globalization.
- **Logic**: Checks if not already set and address is valid, sets `globalizerAddress`, marks `_globalizerSet` as true, emits `GlobalizerAddressSet`.
- **State Changes**: `globalizerAddress`, `_globalizerSet`.
- **Errors**: Reverts if `_globalizerSet` is true or `globalizerAddress_` is `address(0)`.
- **Internal Call Tree**: None.

#### setUniswapV2Pair(address uniswapV2Pair_)
- **Purpose**: Sets the Uniswap V2 pair address for price discovery.
- **Logic**: Checks if not already set and address is valid, sets `uniswapV2PairView`, marks `uniswapV2PairViewSet` as true.
- **State Changes**: `uniswapV2PairView`, `uniswapV2PairViewSet`.
- **Errors**: Reverts if `uniswapV2PairViewSet` is true or `uniswapV2Pair_` is `address(0)`.
- **Internal Call Tree**: None.

#### setRouters(address[] memory routers_)
- **Purpose**: Authorizes router addresses for calling `update`.
- **Logic**: Checks if not already set and array is non-empty, validates each address, sets `_routers[router]=true`, marks `_routersSet` as true.
- **State Changes**: `_routers`, `_routersSet`.
- **Errors**: Reverts if `_routersSet` is true, `routers_.length == 0`, or any `routers_[i] == address(0)`.
- **Internal Call Tree**: None.

#### setListingId(uint256 _listingId)
- **Purpose**: Sets the unique listing identifier.
- **Logic**: Checks if not already set, sets `listingId`.
- **State Changes**: `listingId`.
- **Errors**: Reverts if `listingId != 0`.
- **Internal Call Tree**: None.

#### setLiquidityAddress(address _liquidityAddress)
- **Purpose**: Sets the liquidity contract address for fee queries.
- **Logic**: Checks if not already set and address is valid, sets `liquidityAddressView`.
- **State Changes**: `liquidityAddressView`.
- **Errors**: Reverts if `liquidityAddressView != address(0)` or `_liquidityAddress == address(0)`.
- **Internal Call Tree**: None.

#### setTokens(address _tokenA, address _tokenB)
- **Purpose**: Initializes token pair, decimals, and historical data.
- **Logic**: Checks if tokens are not set, different, and at least one is non-zero. Sets `tokenA`, `tokenB`, fetches decimals via `IERC20.decimals`. Initializes `_historicalData` with a zeroed entry at midnight, sets `_dayStartIndices[midnight]=0`, and initializes `dayStartFee` with midnight timestamp.
- **State Changes**: `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `_historicalData`, `_dayStartIndices`, `dayStartFee`.
- **External Interactions**: `IERC20.decimals`.
- **Internal Call Tree**: `_floorToMidnight`.
- **Errors**: Reverts if tokens already set, `_tokenA == _tokenB`, or both are `address(0)`.

#### setAgent(address _agent)
- **Purpose**: Sets the agent address.
- **Logic**: Checks if not already set and address is valid, sets `agentView`.
- **State Changes**: `agentView`.
- **Errors**: Reverts if `agentView != address(0)` or `_agent == address(0)`.
- **Internal Call Tree**: None.

#### setRegistry(address registryAddress_)
- **Purpose**: Sets the registry address for token balance updates.
- **Logic**: Checks if not already set and address is valid, sets `registryAddress`.
- **State Changes**: `registryAddress`.
- **Errors**: Reverts if `registryAddress != address(0)` or `registryAddress_ == address(0)`.
- **Internal Call Tree**: None.

#### ssUpdate(PayoutUpdate[] calldata updates)
- **Purpose**: Processes long and short payout updates.
- **Logic**: Iterates over `PayoutUpdate` array. For each, creates or updates `longPayout` (if `payoutType=0`) or `shortPayout` (if `payoutType=1`). Sets `filled=0` for new payouts, updates `filled`, `amountSent`, `status`. Adds to `longPayoutByIndex` or `shortPayoutByIndex` and `userPayoutIDs`. Increments `nextOrderId`. Emits `PayoutOrderCreated` for new payouts, `PayoutOrderUpdated` for updates.
- **State Changes**: `longPayout`, `shortPayout`, `longPayoutByIndex`, `shortPayoutByIndex`, `userPayoutIDs`, `nextOrderId`.
- **Errors**: Emits `UpdateFailed` for invalid inputs.
- **Internal Call Tree**: None.

#### update(UpdateType[] calldata updates)
- **Purpose**: Updates balances, buy/sell orders, or historical data, only callable by authorized routers.
- **Logic** (step-by-step in simple language):
  1. **Check Caller**: Ensures the caller is an authorized router (`_routers[msg.sender]`), reverts if not.
  2. **Get Current Midnight**: Calculates the current day’s midnight timestamp (`currentMidnight = (block.timestamp / 86400) * 86400`).
  3. **Initialize Variables**: Sets `balanceUpdated=false` to track balance changes and creates an array `updatedOrders` to store updated order IDs, with `updatedCount` to track the number of updates.
  4. **Process Updates Loop**: Iterates over the `updates` array, handling each `UpdateType`:
     - **Balance Update (`updateType=0`)**:
       - Sets `_balance.xBalance = u.index` and `_balance.yBalance = u.value` (normalized amounts).
       - Marks `balanceUpdated=true`.
       - Emits `BalancesUpdated` with `listingId`, `xBalance`, `yBalance`.
     - **Buy Order Update (`updateType=1`)**:
       - Checks if `updatedOrders` has space, else emits `UpdateFailed`.
       - Stores `u.index` (order ID) in `updatedOrders`, increments `updatedCount`.
       - Gets `orderStatus[u.index]` to track completeness.
       - If `structId=0` (Core):
         - Sets `buyOrderCore[u.index]` with `makerAddress=u.addr`, `recipientAddress=u.recipient`, `status=u.value`.
         - If `status=1` (pending), adds `u.index` to `_pendingBuyOrders` and `makerPendingOrders[u.addr]`.
         - If `status=0` (cancelled), removes `u.index` from `_pendingBuyOrders` and `makerPendingOrders[u.addr]` using `removePendingOrder`.
         - Sets `orderStatus.hasCore=true`.
         - Emits `OrderUpdated` with `listingId`, `u.index`, `isBuy=true`, `status`.
       - If `structId=1` (Pricing):
         - Sets `buyOrderPricing[u.index]` with `maxPrice=u.maxPrice`, `minPrice=u.minPrice`.
         - Sets `orderStatus.hasPricing=true`.
       - If `structId=2` (Amounts):
         - Gets `buyOrderAmounts[u.index]`.
         - If `u.amountSent > 0` or `amounts.pending > 0` (settlement):
           - Sets `amounts.filled = u.value` (filled amount, normalized).
           - Reduces `amounts.pending` by `u.value` if `amounts.pending >= u.value`, else sets `amounts.pending=0` to prevent underflow.
         - Else (new order):
           - Sets `amounts.pending = u.value`.
         - If `u.amountSent > 0`, sets `amounts.amountSent = u.amountSent` (tokenA sent).
         - Sets `orderStatus.hasAmounts=true`.
       - If `structId` is invalid, emits `UpdateFailed`.
     - **Sell Order Update (`updateType=2`)**:
       - Same as buy order, but updates `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_pendingSellOrders`.
       - For `structId=2`, sets `amounts.filled = u.value`, reduces `amounts.pending` by `u.value` (with underflow check), sets `amounts.amountSent = u.amountSent` (tokenB sent).
       - Emits `OrderUpdated` with `isBuy=false`.
     - **Historical Update (`updateType=3`)**:
       - If `u.index >= _historicalData.length`, creates a new `HistoricalData` entry with `price=u.value`, current `_balance.xBalance`, `_balance.yBalance`, `xVolume=0`, `yVolume=0`, and `timestamp` (uses `u.value` if non-zero, else midnight).
       - If `u.index` exists, updates `price`, `xBalance`, `yBalance`, `timestamp`.
       - If the timestamp is today’s midnight, sets `_dayStartIndices[currentMidnight]=u.index`.
       - Marks `balanceUpdated=true`.
     - If `updateType` is invalid, emits `UpdateFailed`.
  5. **Update Fees**: If `_historicalData` exists and `dayStartFee.timestamp` is not today’s midnight, resets `dayStartFee` with zero fees and `currentMidnight`. Calls `ICCLiquidityTemplate.liquidityDetail` to fetch `xFees`, `yFees`, updates `dayStartFee.dayStartXFeesAcc`, `dayStartFee.dayStartYFeesAcc`. Emits `UpdateFailed` if the call fails.
  6. **Check Order Completeness**: For each `updatedOrders[i]`:
     - Checks `orderStatus[orderId]` for `hasCore`, `hasPricing`, `hasAmounts`.
     - Determines `isBuy` if `buyOrderCore[orderId].makerAddress != address(0)`.
     - Emits `OrderUpdatesComplete` if all fields are set, else emits `OrderUpdateIncomplete` with the missing field reason.
  7. **Update Balances and Price**: If `balanceUpdated`, calls `IUniswapV2Pair.token0` and `IERC20.balanceOf(uniswapV2PairView)` for `tokenA`, `tokenB`. Normalizes balances using `normalize`. Emits `UpdateFailed` if the call fails.
  8. **Globalize Orders**: Calls `globalizeUpdate` to notify `ICCGlobalizer` of the latest order.
- **State Changes**: `_balance`, `buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`, `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_pendingBuyOrders`, `_pendingSellOrders`, `makerPendingOrders`, `orderStatus`, `_historicalData`, `_dayStartIndices`, `dayStartFee`.
- **External Interactions**: `IUniswapV2Pair.token0`, `IERC20.balanceOf`, `ITokenRegistry.initializeTokens`, `ICCLiquidityTemplate.liquidityDetail`, `ICCGlobalizer.globalizeOrders`.
- **Internal Call Tree**: `removePendingOrder`, `_updateRegistry`, `globalizeUpdate`, `_floorToMidnight`, `_isSameDay`.
- **Errors**: Emits `UpdateFailed`, `OrderUpdateIncomplete`, `OrderUpdatesComplete`.

#### transactToken(address token, uint256 amount, address recipient)
- **Purpose**: Transfers ERC20 tokens to a recipient.
- **Logic**: Checks if caller is a router, `token` is `tokenA` or `tokenB`, `recipient` is valid, and `amount > 0`. Calls `IERC20.transfer` with `amount` to `recipient`. Tracks pre/post balances, emits `TransactionFailed` if no tokens are received.
- **State Changes**: None (transfers tokens).
- **External Interactions**: `IERC20.balanceOf`, `IERC20.transfer`.
- **Internal Call Tree**: `uint2str`.
- **Errors**: Reverts if not router, invalid token, recipient, or amount. Emits `TransactionFailed`.

#### transactNative(uint256 amount, address recipient)
- **Purpose**: Transfers native ETH to a recipient.
- **Logic**: Checks if caller is a router, `recipient` is valid, and `amount > 0`. Uses low-level `call` to transfer `amount` ETH. Tracks pre/post balances, emits `TransactionFailed` if no ETH is received.
- **State Changes**: None (transfers ETH).
- **External Interactions**: Low-level `call`.
- **Internal Call Tree**: `uint2str`.
- **Errors**: Reverts if not router, invalid recipient, or amount. Emits `TransactionFailed`.

#### getTokens() returns (address tokenA_, address tokenB_)
- **Purpose**: Returns the token pair addresses.
- **Logic**: Returns `tokenA`, `tokenB`.
- **Errors**: Reverts if both are `address(0)`.
- **Internal Call Tree**: None.

#### getNextOrderId() returns (uint256 orderId_)
- **Purpose**: Returns the next order ID.
- **Logic**: Returns `nextOrderId`.
- **Internal Call Tree**: None.

#### getLongPayout(uint256 orderId) returns (LongPayoutStruct memory payout)
- **Purpose**: Returns long payout details for an order ID.
- **Logic**: Returns `longPayout[orderId]`.
- **Internal Call Tree**: None.

#### getShortPayout(uint256 orderId) returns (ShortPayoutStruct memory payout)
- **Purpose**: Returns short payout details for an order ID.
- **Logic**: Returns `shortPayout[orderId]`.
- **Internal Call Tree**: None.

#### prices(uint256) returns (uint256 price)
- **Purpose**: Computes the current price from Uniswap V2 pair balances.
- **Logic**: Fetches `IERC20.balanceOf(uniswapV2PairView)` for `tokenA` and `tokenB`, normalizes balances, computes `(balanceB * 1e18) / balanceA`. Returns 1 on failure or if `balanceA == 0`.
- **External Interactions**: `IERC20.balanceOf`.
- **Internal Call Tree**: `normalize`.
- **Errors**: Returns 1 if external calls fail.

#### volumeBalances(uint256) returns (uint256 xBalance, uint256 yBalance)
- **Purpose**: Returns normalized contract balances.
- **Logic**: Fetches `IERC20.balanceOf(address(this))` or ETH balance for `tokenA`, `tokenB`, normalizes using `normalize`.
- **External Interactions**: `IERC20.balanceOf`.
- **Internal Call Tree**: `normalize`.

#### makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns up to `maxIterations` pending buy order IDs for a maker starting from `step`.
- **Logic**: Filters `makerPendingOrders[maker]` for `buyOrderCore.status == 1`, slices from `step`.
- **Internal Call Tree**: None.

#### makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns up to `maxIterations` pending sell order IDs for a maker starting from `step`.
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
- **Purpose**: Returns up to `maxIterations` order IDs for a maker starting from `step`.
- **Logic**: Slices `makerPendingOrders[maker]` from `step`, capped by `maxIterations`.
- **Internal Call Tree**: None.

#### makerPendingOrdersView(address maker) returns (uint256[] memory orderIds)
- **Purpose**: Returns all pending order IDs for a maker.
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
- **Purpose**: Returns payout order IDs for a user.
- **Logic**: Returns `userPayoutIDs[user]`.
- **Internal Call Tree**: None.

#### getHistoricalDataView(uint256 index) returns (HistoricalData memory data)
- **Purpose**: Returns historical data at a given index.
- **Logic**: Returns `_historicalData[index]`, reverts if invalid.
- **Errors**: Reverts if `index >= _historicalData.length`.
- **Internal Call Tree**: None.

#### historicalDataLengthView() returns (uint256 length)
- **Purpose**: Returns the length of historical data.
- **Logic**: Returns `_historicalData.length`.
- **Internal Call Tree**: None.

#### floorToMidnightView(uint256 inputTimestamp) returns (uint256 midnight)
- **Purpose**: Rounds a timestamp to midnight UTC.
- **Logic**: Computes `(inputTimestamp / 86400) * 86400`.
- **Internal Call Tree**: None.
- **Usage**: Used by external contracts (e.g., `CCDexlytan`) for time-based queries.

#### isSameDayView(uint256 firstTimestamp, uint256 secondTimestamp) returns (bool sameDay)
- **Purpose**: Checks if two timestamps are in the same calendar day.
- **Logic**: Returns `(firstTimestamp / 86400) == (secondTimestamp / 86400)`.
- **Internal Call Tree**: None.
- **Usage**: Used by external contracts (e.g., `CCDexlytan`) for fee or time checks.

#### getDayStartIndex(uint256 midnightTimestamp) returns (uint256 index)
- **Purpose**: Returns the historical data index for a midnight timestamp.
- **Logic**: Returns `_dayStartIndices[midnightTimestamp]`, or 0 if unset.
- **Internal Call Tree**: None.
- **Usage**: Used by external contracts (e.g., `CCDexlytan`) for historical data queries.

### Internal Functions
#### normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)
- **Purpose**: Converts amounts to 1e18 precision.
- **Logic**: Adjusts `amount` based on `decimals` relative to 18.
- **Callers**: Called by `update`, `prices`, `volumeBalances`.

#### denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)
- **Purpose**: Converts amounts from 1e18 to token decimals.
- **Logic**: Adjusts `amount` based on `decimals` relative to 18.
- **Callers**: Called by `transactToken`, `transactNative`.

#### _isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)
- **Purpose**: Checks if two timestamps are in the same calendar day.
- **Logic**: Returns `(time1 / 86400) == (time2 / 86400)`.
- **Callers**: Called by `update` to check `dayStartFee.timestamp` against `block.timestamp`.

#### _floorToMidnight(uint256 timestamp) returns (uint256 midnight)
- **Purpose**: Rounds a timestamp to midnight UTC.
- **Logic**: Returns `(timestamp / 86400) * 86400`.
- **Callers**: Called by `setTokens`, `update`.

#### _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)
- **Purpose**: Returns volume from `_historicalData` at or after `startTime`.
- **Logic**: Iterates `_historicalData` backward, returns `xVolume` or `yVolume` based on `isA`.
- **Callers**: None in v0.2.23 (analytics moved to `CCDexlytan`).

#### _updateRegistry(address maker)
- **Purpose**: Updates token registry with `tokenA`, `tokenB` balances.
- **Logic**: Calls `ITokenRegistry.initializeTokens` with `maker` and token array.
- **Callers**: Called by `update`.
- **External Interactions**: `ITokenRegistry.initializeTokens`.
- **Errors**: Emits `RegistryUpdateFailed`, `ExternalCallFailed`.

#### removePendingOrder(uint256[] storage orders, uint256 orderId)
- **Purpose**: Removes an order ID from `_pendingBuyOrders`, `_pendingSellOrders`, or `makerPendingOrders`.
- **Logic**: Swaps `orderId` with the last element and pops the array.
- **Callers**: Called by `update`.

#### globalizeUpdate()
- **Purpose**: Notifies `ICCGlobalizer` of the latest order.
- **Logic**: Calls `globalizeOrders` with `makerAddress` and `tokenA` or `tokenB` based on the latest order.
- **Callers**: Called by `update`.
- **External Interactions**: `ICCGlobalizer.globalizeOrders`.
- **Errors**: Emits `ExternalCallFailed`, `globalUpdateFailed`.

#### uint2str(uint256 _i) returns (string str)
- **Purpose**: Converts uint to string for error messages.
- **Logic**: Converts `_i` to a string representation.
- **Callers**: Called by `transactToken`, `transactNative`.

## Parameters and Interactions
- **Orders** (`UpdateType`): `updateType=0`: updates `_balance`. Buy (`updateType=1`): inputs `tokenB` (`value` as filled), outputs `tokenA` (`amountSent`). Sell (`updateType=2`): inputs `tokenA` (`value` as filled), outputs `tokenB` (`amountSent`). Creation: buy adds to `yVolume`, sell adds to `xVolume`. Settlement: buy orders add `u.amountSent` to `xBalance`, subtract `u.value` from `yBalance`; sell orders subtract `u.value` from `xBalance`, add `u.amountSent` to `yBalance`. For `structId=2`, sets `filled` and reduces `pending` if `amountSent > 0` or `pending > 0`, else sets `pending`. Tracked via `orderStatus`, emits `OrderUpdatesComplete` or `OrderUpdateIncomplete`.
- **Payouts** (`PayoutUpdate`): Long (`payoutType=0`, `tokenB`), short (`payoutType=1`, `tokenA`) via `ssUpdate`, indexed by `nextOrderId`. Supports `filled`, `amountSent` updates.
- **Price**: Computed via `IUniswapV2Pair`, `IERC20.balanceOf(uniswapV2PairView)`, using `prices` function.
- **Registry**: Updated via `_updateRegistry` in `update`.
- **Globalizer**: Updated via `globalizeUpdate` in `update`.
- **Liquidity**: `ICCLiquidityTemplate.liquidityDetail` used in `update` for fee tracking.
- **Historical Data**: Stored in `_historicalData` via `update` (`updateType=3`) or auto-generated for settlement/cancellation, using Uniswap V2 price via `prices`, carrying forward volumes. `_dayStartIndices` maps midnight timestamps to `_historicalData` indices, accessible via `getDayStartIndex`.
- **External Calls**: `IERC20.balanceOf`, `IERC20.transfer`, `IERC20.decimals`, `ITokenRegistry.initializeTokens`, `ICCLiquidityTemplate.liquidityDetail`, `ICCGlobalizer.globalizeOrders`, low-level `call`.
- **Security**: Router checks, try-catch, explicit casting, no tuple access, relaxed validation, emits `UpdateFailed`.
- **Optimization**: Normalized amounts, `maxIterations`, auto-generated historical data, helper functions in `update`.
