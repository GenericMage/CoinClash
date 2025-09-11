# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract (Solidity ^0.8.2) enables decentralized trading for a token pair, leveraging Uniswap V2 for price discovery via `IERC20.balanceOf`. It manages buy/sell orders and normalized (1e18 precision) balances. Volumes are tracked in `_historicalData` during order settlement/cancellation, with auto-generated historical data if not provided by routers. Licensed under BSL 1.1 - Peng Protocol 2025, it uses explicit casting, avoids inline assembly, and ensures graceful degradation with try-catch for external calls.

**Version**: 0.3.11 (Updated 2025-09-11)

**Changes**:
- v0.3.11: Updated `_processHistoricalUpdate` to use full `HistoricalUpdate` struct, removing `structId` and `value` parameters. Added `_updateHistoricalData` and `_updateDayStartIndex` helper functions for clarity. Modified `ccUpdate` to align with new `_processHistoricalUpdate` logic. Removed `uint2str` function as it’s no longer used in error messages.
- v0.3.10: Modified `ccUpdate` to accept `BuyOrderUpdate[]`, `SellOrderUpdate[]`, `BalanceUpdate[]`, `HistoricalUpdate[]` instead of `updateType`, `updateSort`, `updateData`. Replaced `UpdateType` with new structs. Updated `_processBuyOrderUpdate` and `_processSellOrderUpdate` to use direct struct fields, removing `abi.decode` and `uint2str` in errors.
- v0.3.9: Fixed `_processBuyOrderUpdate` and `_processSellOrderUpdate` to use `UpdateType` fields directly for Core updates, removing incorrect `abi.decode` of `uint2str(value)`.
- v0.3.8: Corrected `_processBuyOrderUpdate` and `_processSellOrderUpdate` to update `_historicalData.xVolume` (tokenA) with `amountSent` for buy orders and `filled` for sell orders; `yVolume` (tokenB) with `filled` for buy orders and `amountSent` for sell orders. Volume changes computed as differences.
- v0.3.5: Moved payout functionality to `CCLiquidityTemplate.sol`.
- v0.3.3: Added `resetRouters` to fetch lister via `ICCAgent.getLister`, restrict to lister, and update `_routers` with `ICCAgent.getRouters`.
- v0.3.2: Added view functions `activeLongPayoutsView`, `activeShortPayoutsView`, `activeUserPayoutIDsView`.
- v0.3.1: Added `activeLongPayouts`, `activeShortPayouts`, `activeUserPayoutIDs` to track active payout IDs. Modified `PayoutUpdate` to include `orderId`. Updated `ssUpdate` to use `orderId`, manage active payout arrays.
- v0.3.0: Bumped version.
- v0.2.25: Replaced `update` with `ccUpdate`, using `updateType`, `updateSort`, `updateData`. Removed logic in `_processBuyOrderUpdate` and `_processSellOrderUpdate` for `pending` reduction or order creation/settlement distinction.

**Compatibility**:
- CCLiquidityTemplate.sol (v0.1.9)
- CCMainPartial.sol (v0.0.14)
- CCLiquidityPartial.sol (v0.0.27)
- ICCLiquidity.sol (v0.0.5)
- ICCListing.sol (v0.0.7)
- CCOrderRouter.sol (v0.1.0)
- TokenRegistry.sol (2025-08-04)
- CCUniPartial.sol (v0.1.0)
- CCOrderPartial.sol (v0.1.0)
- CCSettlementPartial.sol (v0.1.0)

## Interfaces
- **IERC20**: Defines `decimals()`, `transfer(address, uint256)`, `balanceOf(address)`.
- **IUniswapV2Pair**: Defines `token0()`, `token1()`.
- **ICCLiquidityTemplate**: Defines `liquidityDetail()`.
- **ITokenRegistry**: Defines `initializeTokens(address, address[])`.
- **ICCGlobalizer**: Defines `globalizeOrders(address, address)`.
- **ICCAgent**: Defines `getLister(address)`, `getRouters()`.

## Structs
- **DayStartFee**: `dayStartXFeesAcc`, `dayStartYFeesAcc`, `timestamp`.
- **Balance**: `xBalance`, `yBalance` (normalized, 1e18).
- **HistoricalData**: `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`.
- **BuyOrderCore**: `makerAddress`, `recipientAddress`, `status` (0: cancelled, 1: pending, 2: partially filled, 3: filled).
- **BuyOrderPricing**: `maxPrice`, `minPrice` (1e18).
- **BuyOrderAmounts**: `pending` (tokenB), `filled` (tokenB), `amountSent` (tokenA).
- **SellOrderCore**, **SellOrderPricing**, **SellOrderAmounts**: Similar, with `pending` (tokenA), `amountSent` (tokenB).
- **BuyOrderUpdate**: `structId` (0: Core, 1: Pricing, 2: Amounts), `orderId`, `makerAddress`, `recipientAddress`, `status`, `maxPrice`, `minPrice`, `pending`, `filled`, `amountSent`.
- **SellOrderUpdate**: Same fields as `BuyOrderUpdate`.
- **BalanceUpdate**: `xBalance`, `yBalance`.
- **HistoricalUpdate**: `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`.
- **OrderStatus**: `hasCore`, `hasPricing`, `hasAmounts`.

## Fee Segregation
`_balance` (`xBalance`, `yBalance`) tracks tokens from order creation/settlement, excluding `ICCLiquidityTemplate` fees. Buy orders add `filled` to `yVolume` (tokenB), `amountSent` to `xVolume` (tokenA); sell orders add `filled` to `xVolume` (tokenA), `amountSent` to `yVolume` (tokenB). Fees fetched via `ICCLiquidityTemplate.liquidityDetail`, stored in `dayStartFee`.

## State Variables
- **`routers`**: `mapping(address => bool) public` - Authorized routers.
- **`routerAddresses`**: `address[] private` - Router address array.
- **`_routersSet`**: `bool private` - Locks router settings.
- **`tokenA`, `tokenB`**: `address public` - Token pair (ETH as `address(0)`).
- **`decimalsA`, `decimalsB`**: `uint8 public` - Token decimals.
- **`uniswapV2PairView`, `uniswapV2PairViewSet`**: `address public`, `bool private` - Uniswap V2 pair.
- **`listingId`**: `uint256 public` - Listing identifier.
- **`agentView`**: `address public` - Agent address.
- **`registryAddress`**: `address public` - Registry address.
- **`liquidityAddressView`**: `address public` - Liquidity contract.
- **`globalizerAddress`, `_globalizerSet`**: `address public`, `bool private` - Globalizer contract.
- **`nextOrderId`**: `uint256 private` - Order ID counter.
- **`dayStartFee`**: `DayStartFee public` - Daily fee tracking.
- **`_balance`**: `Balance private` - Normalized balances.
- **`_pendingBuyOrders`, `_pendingSellOrders`**: `uint256[] private` - Pending order IDs.
- **`makerPendingOrders`**: `mapping(address => uint256[]) private` - Maker order IDs.
- **`_historicalData`**: `HistoricalData[] private` - Price/volume history.
- **`_dayStartIndices`**: `mapping(uint256 => uint256) private` - Midnight timestamps to indices.
- **`buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`**: `mapping(uint256 => ...)` - Buy order data.
- **`sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`**: `mapping(uint256 => ...)` - Sell order data.
- **`orderStatus`**: `mapping(uint256 => OrderStatus) private` - Order completeness.

## Functions
### External Functions
#### setGlobalizerAddress(address globalizerAddress_)
- **Purpose**: Sets globalizer address (callable once).
- **State Changes**: `globalizerAddress`, `_globalizerSet`.
- **Restrictions**: Reverts if set or invalid address.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `globalizerAddress_` for `globalizeUpdate`.

#### setUniswapV2Pair(address uniswapV2Pair_)
- **Purpose**: Sets Uniswap V2 pair address (callable once).
- **State Changes**: `uniswapV2PairView`, `uniswapV2PairViewSet`.
- **Restrictions**: Reverts if set or invalid address.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `uniswapV2PairView` for `prices`, `ccUpdate`.

#### setRouters(address[] memory routers_)
- **Purpose**: Authorizes routers for `ccUpdate`, `transactToken`, `transactNative`.
- **State Changes**: `routers`, `routerAddresses`, `_routersSet`.
- **Restrictions**: Reverts if set or invalid/empty `routers_`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `routers` entries to true, populates `routerAddresses`.

#### resetRouters()
- **Purpose**: Fetches lister via `ICCAgent.getLister`, restricts to lister, clears `routers`, updates with `ICCAgent.getRouters`.
- **State Changes**: `routers`, `routerAddresses`, `_routersSet`.
- **Restrictions**: Reverts if not lister or no routers.
- **Internal Call Tree**: None (directly calls `ICCAgent.getLister`, `ICCAgent.getRouters`).
- **Parameters/Interactions**: Uses `agentView`, `listingId`.

#### setTokens(address tokenA_, address tokenB_)
- **Purpose**: Sets `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, initializes `dayStartFee`, `_historicalData`.
- **State Changes**: `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `dayStartFee`, `_historicalData`, `_dayStartIndices`.
- **Restrictions**: Reverts if tokens set, identical, or both zero.
- **Internal Call Tree**: `_floorToMidnight`.
- **Parameters/Interactions**: Calls `IERC20.decimals`.

#### setAgent(address agent_)
- **Purpose**: Sets `agentView` (callable once).
- **State Changes**: `agentView`.
- **Restrictions**: Reverts if set or invalid address.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `agentView` for `resetRouters`.

#### setListingId(uint256 listingId_)
- **Purpose**: Sets `listingId` (callable once).
- **State Changes**: `listingId`.
- **Restrictions**: Reverts if set.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `listingId` for events.

#### setRegistry(address registryAddress_)
- **Purpose**: Sets `registryAddress` (callable once).
- **State Changes**: `registryAddress`.
- **Restrictions**: Reverts if set or invalid address.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `registryAddress` for `_updateRegistry`.

#### setLiquidityAddress(address _liquidityAddress)
- **Purpose**: Sets `liquidityAddressView` (callable once).
- **State Changes**: `liquidityAddressView`.
- **Restrictions**: Reverts if set or invalid address.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `liquidityAddressView` for fee fetching.

#### transactToken(address token, uint256 amount, address recipient)
- **Purpose**: Transfers ERC20 tokens via `IERC20.transfer`, updates `_balance`.
- **State Changes**: `_balance.xBalance` or `yBalance`.
- **Restrictions**: Router-only, sufficient balance.
- **Internal Call Tree**: `denormalize`, `_updateRegistry`.
- **Parameters/Interactions**: Uses `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `registryAddress`.

#### transactNative(uint256 amount, address recipient)
- **Purpose**: Transfers ETH via `call`, updates `_balance`.
- **State Changes**: `_balance.xBalance` or `yBalance`.
- **Restrictions**: Router-only, sufficient balance, ETH supported.
- **Internal Call Tree**: `denormalize`, `_updateRegistry`.
- **Parameters/Interactions**: Uses `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `registryAddress`.

#### ccUpdate(BuyOrderUpdate[] calldata buyUpdates, SellOrderUpdate[] calldata sellUpdates, BalanceUpdate[] calldata balanceUpdates, HistoricalUpdate[] calldata historicalUpdates)
- **Purpose**: Updates balances, buy/sell orders, or historical data, callable by routers.
- **Parameters**:
  - `buyUpdates`: Array of `BuyOrderUpdate` (structId, orderId, makerAddress, recipientAddress, status, maxPrice, minPrice, pending, filled, amountSent).
  - `sellUpdates`: Array of `SellOrderUpdate` (similar).
  - `balanceUpdates`: Array of `BalanceUpdate` (xBalance, yBalance).
  - `historicalUpdates`: Array of `HistoricalUpdate` (price, xBalance, yBalance, xVolume, yVolume, timestamp).
- **Logic**:
  1. Verifies router caller.
  2. Processes buy updates via `_processBuyOrderUpdate`:
     - `structId=0` (Core): Updates `buyOrderCore[orderId]`, manages `_pendingBuyOrders`, `makerPendingOrders`, emits `OrderUpdated`.
     - `structId=1` (Pricing): Updates `buyOrderPricing[orderId]`.
     - `structId=2` (Amounts): Updates `buyOrderAmounts[orderId]`, adds `filled` difference to `yVolume`, `amountSent` to `xVolume`.
  3. Processes sell updates via `_processSellOrderUpdate` (similar, `xVolume` for `filled`, `yVolume` for `amountSent`).
  4. Processes balance updates, sets `_balance`, emits `BalancesUpdated`.
  5. Processes historical updates via `_processHistoricalUpdate`, pushes to `_historicalData`, updates `_dayStartIndices` if new day.
  6. Checks `orderStatus` for completeness, emits `OrderUpdatesComplete` or `OrderUpdateIncomplete`.
  7. If `balanceUpdated`, fetches pair balances via `IUniswapV2Pair`, `IERC20.balanceOf`.
  8. Calls `globalizeUpdate`.
- **State Changes**: `_balance`, `buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`, `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_pendingBuyOrders`, `_pendingSellOrders`, `makerPendingOrders`, `orderStatus`, `_historicalData`, `_dayStartIndices`.
- **External Interactions**: `IUniswapV2Pair.token0`, `IERC20.balanceOf`, `ICCLiquidityTemplate.liquidityDetail`, `ITokenRegistry.initializeTokens`, `ICCGlobalizer.globalizeOrders`.
- **Internal Call Tree**: `_processBuyOrderUpdate` (calls `removePendingOrder`, `_updateRegistry`), `_processSellOrderUpdate` (similar), `_updateHistoricalData` (called by `_processHistoricalUpdate`), `_updateDayStartIndex` (called by `_processHistoricalUpdate`), `_updateRegistry` (`ITokenRegistry.initializeTokens`), `globalizeUpdate` (`ICCGlobalizer.globalizeOrders`), `_floorToMidnight`, `_isSameDay`, `removePendingOrder`.
- **Errors**: Emits `UpdateFailed`, `OrderUpdateIncomplete`, `OrderUpdatesComplete`, `ExternalCallFailed`, `RegistryUpdateFailed`, `GlobalUpdateFailed`.

### View Functions
- **pendingBuyOrdersView**, **pendingSellOrdersView**: Return `_pendingBuyOrders`, `_pendingSellOrders`.
- **routerAddressesView**: Returns `routerAddresses`.
- **prices**: Computes price from `IUniswapV2Pair` balances.
- **volumeBalances**: Returns real-time normalized balances.
- **makerPendingBuyOrdersView**, **makerPendingSellOrdersView**: Return pending order IDs for a maker, using `maxIterations`.
- **getBuyOrderCore**, **getBuyOrderPricing**, **getBuyOrderAmounts**: Return buy order details.
- **getSellOrderCore**, **getSellOrderPricing**, **getSellOrderAmounts**: Return sell order details.
- **makerOrdersView**, **makerPendingOrdersView**: Return maker order IDs.
- **getHistoricalDataView**, **historicalDataLengthView**: Access `_historicalData`.
- **getTokens**, **getNextOrderId**, **floorToMidnightView**, **isSameDayView**, **getDayStartIndex**: Utility views.

### Internal Functions
#### normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)
- Normalizes amounts to 1e18 precision. Used in `ccUpdate`, `prices`, `volumeBalances`.

#### denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)
- Denormalizes amounts to token decimals. Used in `transactToken`, `transactNative`.

#### _isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)
- Checks if timestamps are on the same day. Used in `ccUpdate`.

#### _floorToMidnight(uint256 timestamp) returns (uint256 midnight)
- Rounds timestamp to midnight UTC. Used in `setTokens`, `ccUpdate`, `_updateHistoricalData`.

#### _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)
- Queries `_historicalData` for volume since `startTime`, using `maxIterations`.

#### _updateRegistry(address maker)
- Updates `ITokenRegistry` with token balances. Called by `ccUpdate`, `transactToken`, `transactNative`.

#### globalizeUpdate()
- Notifies `ICCGlobalizer` of latest order. Called by `ccUpdate`.

#### _processBuyOrderUpdate(BuyOrderUpdate memory update)
- Updates buy order structs, `_pendingBuyOrders`, `makerPendingOrders`, `_historicalData` volumes (`yVolume` for `filled`, `xVolume` for `amountSent`). Calls `removePendingOrder`, `_updateRegistry`.

#### _processSellOrderUpdate(SellOrderUpdate memory update)
- Updates sell order structs, `_pendingSellOrders`, `makerPendingOrders`, `_historicalData` volumes (`xVolume` for `filled`, `yVolume` for `amountSent`). Calls `removePendingOrder`, `_updateRegistry`.

#### _updateHistoricalData(HistoricalUpdate memory update)
- Pushes new `HistoricalData` entry with normalized balances if `xBalance` or `yBalance` is zero. Called by `_processHistoricalUpdate`.

#### _updateDayStartIndex(uint256 timestamp)
- Updates `_dayStartIndices` for new midnight timestamp. Called by `_processHistoricalUpdate`.

#### _processHistoricalUpdate(HistoricalUpdate memory update) returns (bool historicalUpdated)
- Validates `price`, calls `_updateHistoricalData`, `_updateDayStartIndex`. Used in `ccUpdate`.

## Parameters and Interactions
- **Orders**: `ccUpdate` updates `_balance` (via `BalanceUpdate`), buy orders (input: tokenB `filled`, output: tokenA `amountSent`), sell orders (input: tokenA `filled`, output: tokenB `amountSent`). Tracked via `orderStatus`, emits `OrderUpdatesComplete` or `OrderUpdateIncomplete`.
- **Price**: Computed via `IUniswapV2Pair`, `IERC20.balanceOf` in `prices`.
- **Registry**: Updated via `_updateRegistry` with `tokenA`, `tokenB`.
- **Globalizer**: Updated via `globalizeUpdate` with `maker`, `tokenA` or `tokenB`.
- **Liquidity**: `ICCLiquidityTemplate.liquidityDetail` fetches fees, stored in `dayStartFee`.
- **Historical Data**: Stored in `_historicalData` via `ccUpdate` or auto-generated.
- **External Calls**: `IERC20.balanceOf`, `IERC20.transfer`, `IERC20.decimals`, `IUniswapV2Pair.token0`, `ICCLiquidityTemplate.liquidityDetail`, `ITokenRegistry.initializeTokens`, `ICCGlobalizer.globalizeOrders`, `ICCAgent.getLister`, `ICCAgent.getRouters`, low-level `call`.
- **Security**: Router checks, try-catch, explicit casting, emits errors for failures.
- **Optimization**: Struct-based `ccUpdate`, helper functions, `maxIterations`, auto-generated data.
