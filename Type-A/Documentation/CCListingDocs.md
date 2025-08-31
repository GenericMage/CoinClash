# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract (Solidity ^0.8.2) supports decentralized trading for a token pair, using Uniswap V2 for price discovery via `IERC20.balanceOf`. It manages buy and sell orders, long and short payouts, and normalized (1e18 precision) balances. Volumes are tracked in `_historicalData` during order settlement or cancellation, with auto-generated historical data if not provided by routers. Payouts are tracked with active and historical arrays for efficient querying. Licensed under BSL 1.1 - Peng Protocol 2025, it uses explicit casting, avoids inline assembly, and ensures graceful degradation with try-catch for external calls.

## Version
- **0.3.3**
- **Changes**:
  - v0.3.3: Added `resetRouters` function to fetch lister from `CCAgent`, restrict to lister, and update `_routers` mapping with agent's latest routers. Added helper functions `_clearRouters`, `_fetchAgentRouters`, `_setNewRouters` to manage router updates.
  - v0.3.2: Added view functions `activeLongPayoutsView`, `activeShortPayoutsView`, `activeUserPayoutIDsView` for active payout arrays/mappings.
  - v0.3.1: Added `activeLongPayouts`, `activeShortPayouts`, `activeUserPayoutIDs` to track active payout IDs (status = 1). Modified `PayoutUpdate` to include `orderId` for explicit targeting. Updated `ssUpdate` to use `orderId`, populate/depopulate active payout arrays, and retain historical arrays.
  - v0.3.0: Bumped version.
  - v0.2.25: Replaced `update` with `ccUpdate`, using three parameters (`updateType`, `updateSort`, `updateData`). Removed logic in `_processBuyOrderUpdate` and `_processSellOrderUpdate` for reducing `pending` relative to `filled` or distinguishing order creation vs settlement. Routers directly assign fields except auto-generated ones (`orderStatus`, `_historicalData.timestamp`, `_dayStartIndices`, volume updates).
  - v0.2.24: Modified `ccUpdate` and helpers to remove `pending`/`filled` logic. Routers assign fields directly.
  - v0.2.23: Modified `update` to reduce `pending` by `filled` during settlement with underflow protection.
  - v0.2.22: Added `floorToMidnightView`, `isSameDayView`, `getDayStartIndex`. Removed `getMidnightIndicies`. Modified `update` for order state. Moved analytics to `CCDexlytan`.
  - v0.2.21: Removed `listingPrice` from `update` and `prices`. Renamed `getLastDays` to `getMidnightIndices`.
  - v0.2.20: Modified `update` to create `HistoricalData` during settlement.
- **Compatibility**: Compatible with `CCLiquidityTemplate.sol` (v0.1.3), `CCMainPartial.sol` (v0.0.14), `CCLiquidityPartial.sol` (v0.0.27), `ICCLiquidity.sol` (v0.0.5), `ICCListing.sol` (v0.0.7), `CCOrderRouter.sol` (v0.1.0), `TokenRegistry.sol` (2025-08-04), `CCUniPartial.sol` (v0.1.0), `CCOrderPartial.sol` (v0.1.0), `CCSettlementPartial.sol` (v0.1.0).

## Interfaces
- **IERC20**: Defines `decimals()`, `transfer(address, uint256)`, `balanceOf(address)`.
- **IUniswapV2Pair**: Defines `token0()`, `token1()`.
- **ICCLiquidityTemplate**: Defines `liquidityDetail()`.
- **ITokenRegistry**: Defines `initializeTokens(address, address[])`.
- **ICCGlobalizer**: Defines `globalizeOrders(address, address)`.
- **ICCAgent**: Defines `getLister(address)`, `getRouters()`.

## Structs
- **PayoutUpdate**: `payoutType` (0: Long, 1: Short), `recipient`, `orderId`, `required`, `filled`, `amountSent`.
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
`_balance` (`xBalance`, `yBalance`) tracks tokens from order creation/settlement, excluding `ICCLiquidityTemplate` fees. Buy orders (`updateType=1`, `structId=2`) add `amounts.filled` to `yVolume`; sell orders (`updateType=2`, `structId=2`) add `amounts.filled` to `xVolume`. Fees are fetched via `ICCLiquidityTemplate.liquidityDetail`, stored in `dayStartFee`.

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
- `longPayoutByIndex`, `shortPayoutByIndex`: `uint256[]` - All payout IDs (historical).
- `activeLongPayouts`, `activeShortPayouts`: `uint256[]` - Active payout IDs (status = 1).
- `makerPendingOrders`: `mapping(address => uint256[])` - Maker order IDs.
- `userPayoutIDs`: `mapping(address => uint256[])` - All user payout IDs (historical).
- `activeUserPayoutIDs`: `mapping(address => uint256[])` - Active user payout IDs (status = 1).
- `_historicalData`: `HistoricalData[]` - Price/volume history.
- `_dayStartIndices`: `mapping(uint256 => uint256)` - Midnight timestamps to indices.
- `buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`: `mapping(uint256 => ...)` - Buy order data.
- `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`: `mapping(uint256 => ...)` - Sell order data.
- `longPayout`, `shortPayout`: `mapping(uint256 => ...)` - Payout data.
- `orderStatus`: `mapping(uint256 => OrderStatus)` - Order completeness.

## Functions
### External Functions
#### setGlobalizerAddress(address globalizerAddress_)
- **Purpose**: Sets globalizer contract address (callable once).
- **State Changes**: `globalizerAddress`, `_globalizerSet`.
- **Errors**: Reverts if already set or invalid address.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `globalizerAddress_` for `globalizeUpdate` calls to `ICCGlobalizer.globalizeOrders`.

#### setUniswapV2Pair(address uniswapV2Pair_)
- **Purpose**: Sets Uniswap V2 pair address (callable once).
- **State Changes**: `uniswapV2PairView`, `uniswapV2PairViewSet`.
- **Errors**: Reverts if already set or invalid address.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `uniswapV2PairView` for `prices` and `ccUpdate` balance updates via `IERC20.balanceOf`.

#### setRouters(address[] memory routers_)
- **Purpose**: Authorizes routers for `ccUpdate`, `ssUpdate`, `transactToken`, `transactNative` (callable once).
- **State Changes**: `_routers`, `_routersSet`.
- **Errors**: Reverts if already set, empty array, or invalid addresses.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: `routers_` authorizes addresses for restricted functions.

#### resetRouters()
- **Purpose**: Resets `_routers` mapping to agent's latest routers, restricted to lister.
- **Logic**:
  1. Calls `ICCAgent.getLister` to fetch lister for current contract address.
  2. Verifies `msg.sender` is lister.
  3. Calls `_clearRouters` to reset `_routers` mapping and `_routersSet`.
  4. Calls `_fetchAgentRouters` to get agent's routers via `ICCAgent.getRouters`.
  5. Calls `_setNewRouters` to update `_routers` mapping with new routers.
- **State Changes**: `_routers`, `_routersSet`.
- **External Interactions**: `ICCAgent.getLister`, `ICCAgent.getRouters`.
- **Internal Call Tree**: `_clearRouters` (fetches current routers via `ICCAgent.getRouters`, clears `_routers`), `_fetchAgentRouters` (calls `ICCAgent.getRouters`), `_setNewRouters` (updates `_routers`, sets `_routersSet`).
- **Errors**: Emits `ExternalCallFailed` for failed external calls, `UpdateFailed` if no routers fetched, reverts if caller not lister or invalid router addresses.
- **Parameters/Interactions**: Uses `agentView` for `ICCAgent` interactions, updates `_routers` to match `CCAgent` routers.

#### setListingId(uint256 _listingId)
- **Purpose**: Sets listing identifier (callable once).
- **State Changes**: `listingId`.
- **Errors**: Reverts if already set.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `listingId` for event emissions.

#### setLiquidityAddress(address _liquidityAddress)
- **Purpose**: Sets liquidity contract address (callable once).
- **State Changes**: `liquidityAddressView`.
- **Errors**: Reverts if already set or invalid address.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `liquidityAddressView` for `ccUpdate` fee updates via `ICCLiquidityTemplate.liquidityDetail`.

#### setTokens(address _tokenA, address _tokenB)
- **Purpose**: Initializes token pair, decimals, and historical data.
- **State Changes**: `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `_historicalData`, `_dayStartIndices`, `dayStartFee`.
- **External Interactions**: `IERC20.decimals` for non-ETH tokens.
- **Internal Call Tree**: `_floorToMidnight` (sets `HistoricalData.timestamp`, `dayStartFee.timestamp`).
- **Errors**: Reverts if tokens already set, identical, or both zero.
- **Parameters/Interactions**: `_tokenA`, `_tokenB` define the trading pair; `decimalsA`, `decimalsB` used in `normalize`, `denormalize`.

#### setAgent(address _agent)
- **Purpose**: Sets agent address (callable once).
- **State Changes**: `agentView`.
- **Errors**: Reverts if already set or invalid address.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `agentView` for `resetRouters` interactions with `ICCAgent`.

#### setRegistry(address registryAddress_)
- **Purpose**: Sets registry address (callable once).
- **State Changes**: `registryAddress`.
- **Errors**: Reverts if already set or invalid address.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `registryAddress` for `_updateRegistry` calls to `ITokenRegistry.initializeTokens`.

#### ssUpdate(PayoutUpdate[] calldata updates)
- **Purpose**: Creates/updates long/short payouts, only callable by routers.
- **Parameters**:
  - `updates`: Array of `PayoutUpdate` structs (`payoutType`, `recipient`, `orderId`, `required`, `filled`, `amountSent`).
- **Logic**:
  1. Verifies `msg.sender` is a router.
  2. Iterates `updates`:
     - Validates `recipient` (non-zero), `payoutType` (0 or 1), `required` or `filled` (non-zero).
     - For `payoutType=0` (long):
       - If `longPayout[orderId].orderId == 0` (new): Initializes `LongPayoutStruct` with `recipient`, `required`, `orderId`, `status` (1 if `required > 0`, else 0). Adds `orderId` to `longPayoutByIndex`, `userPayoutIDs[recipient]`, and if `status=1`, to `activeLongPayouts`, `activeUserPayoutIDs[recipient]`. Emits `PayoutOrderCreated`.
       - Else (existing): Updates `filled`, `amountSent`, `required` if non-zero. Sets `status` (3 if `filled >= required`, 2 if `0 < filled < required`, 1 if `filled = 0`). Manages `activeLongPayouts`, `activeUserPayoutIDs` via `removePendingOrder` if `status` changes to 0 or 3, or adds if `status` changes to 1. Emits `PayoutOrderUpdated`.
     - For `payoutType=1` (short): Similar, using `ShortPayoutStruct`, `amount` (instead of `required`), `shortPayoutByIndex`, `activeShortPayouts`.
     - Increments `nextOrderId` to `orderId + 1` for new payouts if `orderId` is unused.
  3. Emits `UpdateFailed` for invalid inputs.
- **State Changes**: `longPayout`, `shortPayout`, `longPayoutByIndex`, `shortPayoutByIndex`, `activeLongPayouts`, `activeShortPayouts`, `userPayoutIDs`, `activeUserPayoutIDs`, `nextOrderId`.
- **External Interactions**: None.
- **Internal Call Tree**: `removePendingOrder` (for active payout array management), `uint2str` (for error messages).
- **Errors**: Emits `UpdateFailed`, `PayoutOrderCreated`, `PayoutOrderUpdated`.
- **Parameters/Interactions**: `updates` array allows routers to create/update payouts. `orderId` ensures targeted updates. `required` (long: tokenB, short: tokenA), `filled`, `amountSent` (opposite token) are normalized (1e18).

#### ccUpdate(uint8[] calldata updateType, uint8[] calldata updateSort, uint256[] calldata updateData)
- **Purpose**: Updates balances, buy/sell orders, or historical data, callable by routers.
- **Parameters**:
  - `updateType`: Array of update types (0: balance, 1: buy order, 2: sell order, 3: historical).
  - `updateSort`: Array specifying struct to update (0: Core, 1: Pricing, 2: Amounts for orders;  assent
- **Logic**:
  1. Verifies router caller and array length consistency.
  2. Computes current midnight timestamp (`(block.timestamp / 86400) * 86400`).
  3. Initializes `balanceUpdated`, `updatedOrders`, `updatedCount`.
  4. Processes updates:
     - **Balance (`updateType=0`)**: Calls `_processBalanceUpdate` to set `_balance.xBalance` (`updateSort=0`) or `yBalance` (`updateSort=1`) from `updateData[i]`. Emits `BalancesUpdated`.
     - **Buy Order (`updateType=1`)**: Calls `_processBuyOrderUpdate`:
       - `structId=0` (Core): Decodes `updateData[i]` as `(address makerAddress, address recipientAddress, uint8 status)`. Updates `buyOrderCore[orderId]`, manages `_pendingBuyOrders`, `makerPendingOrders` via `removePendingOrder` if `status=0` or `3`. Sets `orderStatus.hasCore`. Emits `OrderUpdated`.
       - `structId=1` (Pricing): Decodes `updateData[i]` as `(uint256 maxPrice, uint256 minPrice)`. Updates `buyOrderPricing[orderId]`. Sets `orderStatus.hasPricing`.
       - `structId=2` (Amounts): Decodes `updateData[i]` as `(uint256 pending, uint256 filled, uint256 amountSent)`. Updates `buyOrderAmounts[orderId]`, adds `filled` to `_historicalData.yVolume`. Sets `orderStatus.hasAmounts`.
       - Invalid `structId` emits `UpdateFailed`.
     - **Sell Order (`updateType=2`)**: Similar, updates `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_pendingSellOrders`, adds `filled` to `_historicalData.xVolume`.
     - **Historical (`updateType=3`)**: Calls `_processHistoricalUpdate` to create `HistoricalData` with `price=updateData[i]`, current balances, timestamp, updates `_dayStartIndices`.
  5. Updates `dayStartFee` if not same day, fetching fees via `ICCLiquidityTemplate.liquidityDetail`.
  6. Checks `orderStatus` for completeness, emits `OrderUpdatesComplete` or `OrderUpdateIncomplete`.
  7. If `balanceUpdated`, fetches pair balances via `IUniswapV2Pair`, `IERC20.balanceOf`.
  8. Calls `globalizeUpdate`.
- **State Changes**: `_balance`, `buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`, `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_pendingBuyOrders`, `_pendingSellOrders`, `makerPendingOrders`, `orderStatus`, `_historicalData`, `_dayStartIndices`, `dayStartFee`.
- **External Interactions**: `IUniswapV2Pair.token0`, `IERC20.balanceOf`, `ICCLiquidityTemplate.liquidityDetail`, `ITokenRegistry.initializeTokens` (via `_updateRegistry`), `ICCGlobalizer.globalizeOrders` (via `globalizeUpdate`).
- **Internal Call Tree**: `_processBalanceUpdate` (sets `_balance`, emits `BalancesUpdated`), `_processBuyOrderUpdate` (updates buy orders, calls `removePendingOrder`, `uint2str`, `_updateRegistry`), `_processSellOrderUpdate` (updates sell orders, calls `removePendingOrder`, `uint2str`, `_updateRegistry`), `_processHistoricalUpdate` (creates `HistoricalData`, calls `_floorToMidnight`), `_updateRegistry` (calls `ITokenRegistry.initializeTokens`), `globalizeUpdate` (calls `ICCGlobalizer.globalizeOrders`, `uint2str`), `_floorToMidnight` (timestamp rounding), `_isSameDay` (day check), `removePendingOrder` (array management), `uint2str` (error messages).
- **Errors**: Emits `UpdateFailed`, `OrderUpdateIncomplete`, `OrderUpdatesComplete`, `ExternalCallFailed`, `RegistryUpdateFailed`, `GlobalUpdateFailed`.
- **Parameters/Interactions**: `updateType`, `updateSort`, `updateData` allow flexible updates. `updateData` encodes struct fields (e.g., `(address, address, uint8)` for Core) via `abi.decode`. Balances use `tokenA`, `tokenB` via `IERC20.balanceOf`. Fees and global updates interact with external contracts.

#### transactToken(address token, uint256 amount, address recipient)
- **Purpose**: Transfers ERC20 tokens.
- **Parameters**: `token` (must be `tokenA` or `tokenB`), `amount` (non-zero), `recipient` (non-zero).
- **Logic**: Verifies router, inputs. Calls `IERC20.transfer`, checks pre/post balances.
- **State Changes**: None (transfers tokens).
- **External Interactions**: `IERC20.balanceOf`, `IERC20.transfer`.
- **Internal Call Tree**: `uint2str` (error messages).
- **Errors**: Reverts for invalid inputs, emits `TransactionFailed`.
- **Parameters/Interactions**: Uses `tokenA` or `tokenB` for transfers, with `normalize`/`denormalize` for amount handling.

#### transactNative(uint256 amount, address recipient)
- **Purpose**: Transfers ETH.
- **Parameters**: `amount` (non-zero, matches `msg.value`), `recipient` (non-zero).
- **Logic**: Verifies router, ETH support, inputs. Uses low-level `call`, checks balances.
- **State Changes**: None (transfers ETH).
- **External Interactions**: Low-level `call`.
- **Internal Call Tree**: `uint2str` (error messages).
- **Errors**: Reverts for invalid inputs, emits `TransactionFailed`.
- **Parameters/Interactions**: Supports ETH if `tokenA` or `tokenB` is `address(0)`.

#### getTokens() returns (address tokenA_, address tokenB_)
- **Purpose**: Returns token pair addresses.
- **Errors**: Reverts if both are `address(0)`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Returns `tokenA`, `tokenB` for external use.

#### getNextOrderId() returns (uint256 orderId_)
- **Purpose**: Returns next order ID for `ssUpdate`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Provides `nextOrderId` for routers to create new payouts.

#### getLongPayout(uint256 orderId) returns (LongPayoutStruct memory payout)
- **Purpose**: Returns long payout details.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `longPayout[orderId]` for external inspection.

#### getShortPayout(uint256 orderId) returns (ShortPayoutStruct memory payout)
- **Purpose**: Returns short payout details.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `shortPayout[orderId]` for external inspection.

#### prices(uint256) returns (uint256 price)
- **Purpose**: Computes price from Uniswap V2 pair balances.
- **Logic**: Fetches `IERC20.balanceOf` for `tokenA`, `tokenB`, normalizes, computes `(balanceB * 1e18) / balanceA`.
- **External Interactions**: `IERC20.balanceOf`.
- **Internal Call Tree**: `normalize` (amount conversion).
- **Errors**: Returns 1 if calls fail.
- **Parameters/Interactions**: Uses `uniswapV2PairView`, `tokenA`, `tokenB` for price calculation.

#### volumeBalances(uint256) returns (uint256 xBalance, uint256 yBalance)
- **Purpose**: Returns normalized contract balances.
- **External Interactions**: `IERC20.balanceOf` (or contract balance for ETH).
- **Internal Call Tree**: `normalize` (amount conversion).
- **Parameters/Interactions**: Queries `tokenA`, `tokenB` balances at contract address.

#### makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns up to `maxIterations` pending buy order IDs for `maker` from `step`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Filters `makerPendingOrders[maker]` for `buyOrderCore.status=1`.

#### makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns up to `maxIterations` pending sell order IDs for `maker` from `step`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Filters `makerPendingOrders[maker]` for `sellOrderCore.status=1`.

#### getBuyOrderCore(uint256 orderId) returns (address makerAddress, address recipientAddress, uint8 status)
- **Purpose**: Returns buy order core details.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `buyOrderCore[orderId]`.

#### getBuyOrderPricing(uint256 orderId) returns (uint256 maxPrice, uint256 minPrice)
- **Purpose**: Returns buy order pricing details.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `buyOrderPricing[orderId]`.

#### getBuyOrderAmounts(uint256 orderId) returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Purpose**: Returns buy order amounts.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `buyOrderAmounts[orderId]`.

#### getSellOrderCore(uint256 orderId) returns (address makerAddress, address recipientAddress, uint8 status)
- **Purpose**: Returns sell order core details.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `sellOrderCore[orderId]`.

#### getSellOrderPricing(uint256 orderId) returns (uint256 maxPrice, uint256 minPrice)
- **Purpose**: Returns sell order pricing details.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `sellOrderPricing[orderId]`.

#### getSellOrderAmounts(uint256 orderId) returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Purpose**: Returns sell order amounts.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `sellOrderAmounts[orderId]`.

#### makerOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns up to `maxIterations` order IDs for `maker` from `step`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Slices `makerPendingOrders[maker]` from `step`.

#### makerPendingOrdersView(address maker) returns (uint256[] memory orderIds)
- **Purpose**: Returns all order IDs for `maker`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Returns `makerPendingOrders[maker]`.

#### longPayoutByIndexView() returns (uint256[] memory orderIds)
- **Purpose**: Returns all long payout order IDs (historical).
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Returns `longPayoutByIndex`.

#### shortPayoutByIndexView() returns (uint256[] memory orderIds)
- **Purpose**: Returns all short payout order IDs (historical).
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Returns `shortPayoutByIndex`.

#### userPayoutIDsView(address user) returns (uint256[] memory orderIds)
- **Purpose**: Returns all payout order IDs for `user` (historical).
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Returns `userPayoutIDs[user]`.

#### activeLongPayoutsView() returns (uint256[] memory orderIds)
- **Purpose**: Returns active long payout order IDs (status = 1).
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Returns `activeLongPayouts`.

#### activeShortPayoutsView() returns (uint256[] memory orderIds)
- **Purpose**: Returns active short payout order IDs (status = 1).
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Returns `activeShortPayouts`.

#### activeUserPayoutIDsView(address user) returns (uint256[] memory orderIds)
- **Purpose**: Returns active payout order IDs for `user` (status = 1).
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Returns `activeUserPayoutIDs[user]`.

#### getHistoricalDataView(uint256 index) returns (HistoricalData memory data)
- **Purpose**: Returns historical data at `index`.
- **Errors**: Reverts if invalid index.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `_historicalData[index]`.

#### historicalDataLengthView() returns (uint256 length)
- **Purpose**: Returns historical data length.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Returns `_historicalData.length`.

#### floorToMidnightView(uint256 inputTimestamp) returns (uint256 midnight)
- **Purpose**: Rounds timestamp to midnight UTC.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Computes `(inputTimestamp / 86400) * 86400`.

#### isSameDayView(uint256 firstTimestamp, uint256 secondTimestamp) returns (bool sameDay)
- **Purpose**: Checks if timestamps are in the same day.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Computes `(firstTimestamp / 86400) == (secondTimestamp / 86400)`.

#### getDayStartIndex(uint256 midnightTimestamp) returns (uint256 index)
- **Purpose**: Returns historical data index for midnight timestamp.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `_dayStartIndices[midnightTimestamp]`.

### Internal Functions
#### normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)
- **Purpose**: Converts amounts to 1e18 precision.
- **Callers**: `ccUpdate` (_processBalanceUpdate, _processBuyOrderUpdate, _processSellOrderUpdate), `prices`, `volumeBalances`.
- **Parameters/Interactions**: Uses `decimalsA`, `decimalsB` for `tokenA`, `tokenB`.

#### denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)
- **Purpose**: Converts amounts from 1e18 to token decimals.
- **Callers**: `transactToken`, `transactNative`.
- **Parameters/Interactions**: Uses `decimalsA`, `decimalsB` for `tokenA`, `tokenB`.

#### _isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)
- **Purpose**: Checks if timestamps are in the same day.
- **Callers**: `ccUpdate`.
- **Parameters/Interactions**: Used for `dayStartFee` updates.

#### _floorToMidnight(uint256 timestamp) returns (uint256 midnight)
- **Purpose**: Rounds timestamp to midnight UTC.
- **Callers**: `setTokens`, `ccUpdate` (_processHistoricalUpdate).
- **Parameters/Interactions**: Used for `HistoricalData.timestamp`, `dayStartFee.timestamp`, `_dayStartIndices`.

#### _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)
- **Purpose**: Returns volume from `_historicalData` at/after `startTime`.
- **Callers**: None (analytics in `CCDexlytan`).
- **Parameters/Interactions**: Queries `_historicalData` with `maxIterations` limit.

#### _updateRegistry(address maker)
- **Purpose**: Updates registry with token balances.
- **Callers**: `ccUpdate` (via `_processBuyOrderUpdate`, `_processSellOrderUpdate`).
- **External Interactions**: `ITokenRegistry.initializeTokens` with `tokenA`, `tokenB`.
- **Internal Call Tree**: `uint2str` (error messages).
- **Parameters/Interactions**: Uses `maker`, `tokenA`, `tokenB` for registry updates.

#### removePendingOrder(uint256[] storage orders, uint256 orderId)
- **Purpose**: Removes `orderId` from arrays.
- **Callers**: `ccUpdate` (_processBuyOrderUpdate, _processSellOrderUpdate), `ssUpdate`.
- **Parameters/Interactions**: Manages `_pendingBuyOrders`, `_pendingSellOrders`, `makerPendingOrders`, `activeLongPayouts`, `activeShortPayouts`, `activeUserPayoutIDs`.

#### globalizeUpdate()
- **Purpose**: Notifies `ICCGlobalizer` of latest order.
- **Callers**: `ccUpdate`.
- **External Interactions**: `ICCGlobalizer.globalizeOrders` with `maker`, `tokenA` or `tokenB`.
- **Internal Call Tree**: `uint2str` (error messages).
- **Parameters/Interactions**: Uses `nextOrderId`, `buyOrderCore`, `sellOrderCore`, `tokenA`, `tokenB`.

#### uint2str(uint256 _i) returns (string str)
- **Purpose**: Converts uint to string for `abi.decode` and errors.
- **Callers**: `ccUpdate` (_processBuyOrderUpdate, _processSellOrderUpdate), `transactToken`, `transactNative`, `ssUpdate`, `_updateRegistry`, `globalizeUpdate`.
- **Parameters/Interactions**: Supports `abi.decode` in `ccUpdate`, error messages elsewhere.

#### _processBalanceUpdate(uint8 structId, uint256 value) returns (bool balanceUpdated)
- **Purpose**: Updates `_balance.xBalance` or `yBalance`.
- **Callers**: `ccUpdate`.
- **Parameters/Interactions**: `structId` (0: xBalance, 1: yBalance), `value` (normalized).

#### _processBuyOrderUpdate(uint8 structId, uint256 value, uint256[] memory updatedOrders, uint256 updatedCount) returns (uint256)
- **Purpose**: Updates buy order structs, manages `_pendingBuyOrders`, `makerPendingOrders`.
- **Callers**: `ccUpdate`.
- **Internal Call Tree**: `removePendingOrder`, `uint2str`, `_updateRegistry`.
- **Parameters/Interactions**: Decodes `value` based on `structId`, updates `buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`, `_historicalData.yVolume`.

#### _processSellOrderUpdate(uint8 structId, uint256 value, uint256[] memory updatedOrders, uint256 updatedCount) returns (uint256)
- **Purpose**: Updates sell order structs, manages `_pendingSellOrders`, `makerPendingOrders`.
- **Callers**: `ccUpdate`.
- **Internal Call Tree**: `removePendingOrder`, `uint2str`, `_updateRegistry`.
- **Parameters/Interactions**: Decodes `value` based on `structId`, updates `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_historicalData.xVolume`.

#### _processHistoricalUpdate(uint8 structId, uint256 value) returns (bool historicalUpdated)
- **Purpose**: Creates `HistoricalData` entry.
- **Callers**: `ccUpdate`.
- **Internal Call Tree**: `_floorToMidnight`.
- **Parameters/Interactions**: Uses `value` as `price`, `_balance`, and timestamp for `_historicalData`.

#### _clearRouters()
- **Purpose**: Clears `_routers` mapping by fetching current routers from `ICCAgent.getRouters`.
- **Callers**: `resetRouters`.
- **External Interactions**: `ICCAgent.getRouters`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Resets `_routers` and `_routersSet` for new router updates.

#### _fetchAgentRouters() returns (address[] memory newRouters)
- **Purpose**: Fetches routers from `ICCAgent.getRouters`.
- **Callers**: `resetRouters`.
- **External Interactions**: `ICCAgent.getRouters`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Returns router array or empty array on failure.

#### _setNewRouters(address[] memory newRouters)
- **Purpose**: Updates `_routers` mapping with new routers.
- **Callers**: `resetRouters`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `_routers` entries to true, updates `_routersSet`.

## Parameters and Interactions
- **Orders**: `ccUpdate` with `updateType=0` updates `_balance`. Buy (`updateType=1`): inputs `tokenB` (`amounts.filled`), outputs `tokenA` (`amounts.amountSent`). Sell (`updateType=2`): inputs `tokenA` (`amounts.filled`), outputs `tokenB` (`amounts.amountSent`). Buy adds to `yVolume`, sell to `xVolume`. Tracked via `orderStatus`, emits `OrderUpdatesComplete` or `OrderUpdateIncomplete`.
- **Payouts**: Long (`tokenB`), short (`tokenA`) via `ssUpdate`, indexed by `orderId`. Active payouts (status=1) tracked in `activeLongPayouts`, `activeShortPayouts`, `activeUserPayoutIDs`; historical in `longPayoutByIndex`, `shortPayoutByIndex`, `userPayoutIDs`.
- **Price**: Computed via `IUniswapV2Pair`, `IERC20.balanceOf` in `prices`.
- **Registry**: Updated via `_updateRegistry` in `ccUpdate` with `tokenA`, `tokenB`.
- **Globalizer**: Updated via `globalizeUpdate` in `ccUpdate` with `maker`, `tokenA` or `tokenB`.
- **Liquidity**: `ICCLiquidityTemplate.liquidityDetail` for fees in `ccUpdate`, stored in `dayStartFee`.
- **Historical Data**: Stored in `_historicalData` via `ccUpdate` (`updateType=3`) or auto-generated, using Uniswap V2 price.
- **External Calls**: `IERC20.balanceOf` (`prices`, `volumeBalances`, `transactToken`), `IERC20.transfer` (`transactToken`), `IERC20.decimals` (`setTokens`), `IUniswapV2Pair.token0` (`ccUpdate`), `ICCLiquidityTemplate.liquidityDetail` (`ccUpdate`), `ITokenRegistry.initializeTokens` (`_updateRegistry`), `ICCGlobalizer.globalizeOrders` (`globalizeUpdate`), `ICCAgent.getLister` (`resetRouters`), `ICCAgent.getRouters` (`resetRouters`, `_clearRouters`, `_fetchAgentRouters`), low-level `call` (`transactNative`).
- **Security**: Router checks, try-catch, explicit casting, relaxed validation, emits `UpdateFailed`, `TransactionFailed`, `ExternalCallFailed`, `RegistryUpdateFailed`, `GlobalUpdateFailed`.
- **Optimization**: Normalized amounts, `maxIterations` in view functions, auto-generated historical data, helper functions in `ccUpdate` and `resetRouters`, active payout arrays for efficient querying.
