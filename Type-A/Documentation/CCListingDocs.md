# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract (Solidity ^0.8.2) supports decentralized trading for a token pair, using Uniswap V2 for price discovery via `IERC20.balanceOf`. It manages buy and sell orders and normalized (1e18 precision) balances. Volumes are tracked in `_historicalData` during order settlement or cancellation, with auto-generated historical data if not provided by routers. Licensed under BSL 1.1 - Peng Protocol 2025, it uses explicit casting, avoids inline assembly, and ensures graceful degradation with try-catch for external calls.

**Version**: 0.3.8 (Updated 2025-09-04)

**Changes**:
- v0.3.8: Corrected `_processBuyOrderUpdate` and `_processSellOrderUpdate` to properly update historical volumes: `xVolume` (tokenA) updated with amountSent for buy orders and filled for sell orders; `yVolume` (tokenB) updated with `filled` for buy orders and `amountSent` for sell orders. Volume changes computed as difference between new and old values.
- v0.3.5: Removed payout functionality (`ssUpdate`, `PayoutUpdate`, `LongPayoutStruct`, `ShortPayoutStruct`, `longPayout`, `shortPayout`, `longPayoutByIndex`, `shortPayoutByIndex`, `userPayoutIDs`, `activeLongPayouts`, `activeShortPayouts`, `activeUserPayoutIDs`, and related view functions) to `CCLiquidityTemplate.sol`.
- v0.3.3: Added `resetRouters` function to fetch lister from `ICCAgent`, restrict to lister, and update `_routers` mapping with agent's latest routers. Added helper functions `_clearRouters`, `_fetchAgentRouters`, `_setNewRouters`.
- v0.3.2: Added view functions `activeLongPayoutsView`, `activeShortPayoutsView`, `activeUserPayoutIDsView` for active payout arrays/mappings.
- v0.3.1: Added `activeLongPayouts`, `activeShortPayouts`, `activeUserPayoutIDs` to track active payout IDs (status = 1). Modified `PayoutUpdate` to include `orderId` for explicit targeting. Updated `ssUpdate` to use `orderId`, populate/depopulate active payout arrays, and retain historical arrays.
- v0.3.0: Bumped version.
- v0.2.25: Replaced `update` with `ccUpdate`, using three parameters (`updateType`, `updateSort`, `updateData`). Removed logic in `_processBuyOrderUpdate` and `_processSellOrderUpdate` for reducing `pending` relative to `filled` or distinguishing order creation vs settlement. Routers directly assign fields except auto-generated ones (`orderStatus`, `_historicalData.timestamp`, `_dayStartIndices`, volume updates).

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
- **UpdateType**: `updateType` (0: balance, 1: buy, 2: sell, 3: historical), `structId` (0: Core, 1: Pricing, 2: Amounts), `index`, `value`, `addr`, `recipient`, `maxPrice`, `minPrice`, `amountSent`.
- **OrderStatus**: `hasCore`, `hasPricing`, `hasAmounts`.

## Fee Segregation
`_balance` (`xBalance`, `yBalance`) tracks tokens from order creation/settlement, excluding `ICCLiquidityTemplate` fees. Buy orders (`updateType=1`, `structId=2`) add `amounts.filled` to `yVolume`; sell orders (`updateType=2`, `structId=2`) add `amounts.filled` to `xVolume`. Fees are fetched via `ICCLiquidityTemplate.liquidityDetail`, stored in `dayStartFee`.

## State Variables
- **`_routers`**: `mapping(address => bool) public` - Authorized routers.
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
- **`makerPendingOrders`**: `mapping(address => uint256[]) public` - Maker order IDs.
- **`_historicalData`**: `HistoricalData[] private` - Price/volume history.
- **`_dayStartIndices`**: `mapping(uint256 => uint256) private` - Midnight timestamps to indices.
- **`buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`**: `mapping(uint256 => ...)` - Buy order data.
- **`sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`**: `mapping(uint256 => ...)` - Sell order data.
- **`orderStatus`**: `mapping(uint256 => OrderStatus) private` - Order completeness.

## Functions
### External Functions
#### setGlobalizerAddress(address globalizerAddress_)
- **Purpose**: Sets globalizer contract address (callable once).
- **State Changes**: `globalizerAddress`, `_globalizerSet`.
- **Restrictions**: Reverts if already set or invalid address.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `globalizerAddress_` for `globalizeUpdate` calls to `ICCGlobalizer.globalizeOrders`.

#### setUniswapV2Pair(address uniswapV2Pair_)
- **Purpose**: Sets Uniswap V2 pair address (callable once).
- **State Changes**: `uniswapV2PairView`, `uniswapV2PairViewSet`.
- **Restrictions**: Reverts if already set or invalid address.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `uniswapV2PairView` for `prices` and `ccUpdate`.

#### setRouters(address[] memory routers_)
- **Purpose**: Authorizes routers for `ccUpdate`, `transactToken`, `transactNative`.
- **State Changes**: `_routers`, `_routersSet`.
- **Restrictions**: Reverts if `_routersSet` or `routers_` invalid/empty.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `_routers` entries to true.

#### resetRouters()
- **Purpose**: Fetches lister via `ICCAgent.getLister`, restricts to lister, clears `_routers`, updates with `ICCAgent.getRouters`.
- **State Changes**: `_routers`, `_routersSet`.
- **Restrictions**: Reverts if `msg.sender` not lister or no routers.
- **Internal Call Tree**: `_clearRouters` (`ICCAgent.getRouters`), `_fetchAgentRouters` (`ICCAgent.getRouters`), `_setNewRouters`.
- **Parameters/Interactions**: Uses `agentView`, `listingId`.

#### setTokens(address tokenA_, address tokenB_)
- **Purpose**: Sets `tokenA`, `tokenB`, `decimalsA`, `decimalsB` (callable once).
- **State Changes**: `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `dayStartFee`.
- **Restrictions**: Reverts if tokens set, identical, or both zero.
- **Internal Call Tree**: `_floorToMidnight`.
- **Parameters/Interactions**: Calls `IERC20.decimals` for `tokenA_`, `tokenB_`.

#### setAgent(address agent_)
- **Purpose**: Sets `agentView` (callable once).
- **State Changes**: `agentView`.
- **Restrictions**: Reverts if `agentView` set or `agent_` invalid.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `agentView` for `resetRouters`.

#### setListingId(uint256 listingId_)
- **Purpose**: Sets `listingId` (callable once).
- **State Changes**: `listingId`.
- **Restrictions**: Reverts if `listingId` set.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `listingId` for event emissions.

#### setRegistry(address registryAddress_)
- **Purpose**: Sets `registryAddress` (callable once).
- **State Changes**: `registryAddress`.
- **Restrictions**: Reverts if `registryAddress` set or invalid.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `registryAddress` for `_updateRegistry`.

#### transactToken(address recipient, address token, uint256 amount)
- **Purpose**: Transfers ERC20 tokens via `IERC20.transfer`, updates `_balance`, calls `_updateRegistry`.
- **State Changes**: `_balance.xBalance` or `yBalance`.
- **Restrictions**: Router-only, sufficient balance.
- **Internal Call Tree**: `denormalize`, `_updateRegistry` (`ITokenRegistry.initializeTokens`, `uint2str`).
- **Parameters/Interactions**: Uses `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `registryAddress`.

#### transactNative(address recipient, uint256 amount)
- **Purpose**: Transfers ETH via low-level `call`, updates `_balance`, calls `_updateRegistry`.
- **State Changes**: `_balance.xBalance` or `yBalance`.
- **Restrictions**: Router-only, sufficient balance.
- **Internal Call Tree**: `denormalize`, `_updateRegistry` (`ITokenRegistry.initializeTokens`, `uint2str`).
- **Parameters/Interactions**: Uses `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `registryAddress`.

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
       - `structId=2` (Amounts): Decodes `updateData[i]` as `(uint256 pending, uint256 filled, uint256 amountSent)`. Updates `buyOrderAmounts[orderId]`, adds difference of old and new `filled` to `_historicalData.yVolume`, same for `amountSent` to `_historicalData.xVolume`. Sets `orderStatus.hasAmounts`.
       - Invalid `structId` emits `UpdateFailed`.
     - **Sell Order (`updateType=2`)**: Similar, updates `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_pendingSellOrders`, adds differenc of old and new `filled` to `_historicalData.xVolume`, same for `amountSent` to `_historicalData.yVolume`. 
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


### Internal Functions
#### normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)
- **Purpose**: Converts amounts to 1e18 precision.
- **Callers**: `ccUpdate` (`_processBalanceUpdate`, `_processBuyOrderUpdate`, `_processSellOrderUpdate`), `prices`, `volumeBalances`.
- **Parameters/Interactions**: Uses `decimalsA`, `decimalsB`.

#### denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)
- **Purpose**: Converts amounts from 1e18 to token decimals.
- **Callers**: `transactToken`, `transactNative`.
- **Parameters/Interactions**: Uses `decimalsA`, `decimalsB`.

#### _isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)
- **Purpose**: Checks if timestamps are in the same day.
- **Callers**: `ccUpdate`.
- **Parameters/Interactions**: Used for `dayStartFee` updates.

#### _floorToMidnight(uint256 timestamp) returns (uint256 midnight)
- **Purpose**: Rounds timestamp to midnight UTC.
- **Callers**: `setTokens`, `ccUpdate` (`_processHistoricalUpdate`).
- **Parameters/Interactions**: Used for `HistoricalData.timestamp`, `dayStartFee.timestamp`, `_dayStartIndices`.

#### _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)
- **Purpose**: Returns volume from `_historicalData` at/after `startTime`.
- **Callers**: None (analytics in `CCDexlytan`).
- **Parameters/Interactions**: Queries `_historicalData` with `maxIterations`.

#### _updateRegistry(address maker)
- **Purpose**: Updates registry with token balances.
- **Callers**: `ccUpdate` (`_processBuyOrderUpdate`, `_processSellOrderUpdate`), `transactToken`, `transactNative`.
- **Internal Call Tree**: `uint2str`.
- **Parameters/Interactions**: Calls `ITokenRegistry.initializeTokens` with `tokenA`, `tokenB`.

#### globalizeUpdate()
- **Purpose**: Notifies `ICCGlobalizer` of latest order.
- **Callers**: `ccUpdate`.
- **Internal Call Tree**: `uint2str`.
- **Parameters/Interactions**: Calls `ICCGlobalizer.globalizeOrders` with `maker`, `tokenA` or `tokenB`.

#### uint2str(uint256 _i) returns (string str)
- **Purpose**: Converts uint to string for error messages.
- **Callers**: `ccUpdate`, `transactToken`, `transactNative`, `_updateRegistry`, `globalizeUpdate`.
- **Parameters/Interactions**: Supports error messages.

#### _processBalanceUpdate(uint8 structId, uint256 value) returns (bool balanceUpdated)
- **Purpose**: Updates `_balance.xBalance` or `yBalance`.
- **Callers**: `ccUpdate`.
- **Parameters/Interactions**: Uses `structId` (0: xBalance, 1: yBalance), `value` (normalized).

#### _processBuyOrderUpdate(uint8 structId, uint256 value, uint256[] memory updatedOrders, uint256 updatedCount) returns (uint256)
- **Purpose**: Updates buy order structs, manages `_pendingBuyOrders`, `makerPendingOrders`.
- **Callers**: `ccUpdate`.
- **Internal Call Tree**: `removePendingOrder`, `uint2str`, `_updateRegistry`.
- **Parameters/Interactions**: Updates `buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`, `_historicalData.yVolume`, `_historicalData.xVolume`. 

#### _processSellOrderUpdate(uint8 structId, uint256 value, uint256[] memory updatedOrders, uint256 updatedCount) returns (uint256)
- **Purpose**: Updates sell order structs, manages `_pendingSellOrders`, `makerPendingOrders`.
- **Callers**: `ccUpdate`.
- **Internal Call Tree**: `removePendingOrder`, `uint2str`, `_updateRegistry`.
- **Parameters/Interactions**: Updates `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_historicalData.xVolume`, `_historicalData.yVolume`.

#### _processHistoricalUpdate(uint8 structId, uint256 value) returns (bool historicalUpdated)
- **Purpose**: Creates `HistoricalData` entry.
- **Callers**: `ccUpdate`.
- **Internal Call Tree**: `_floorToMidnight`.
- **Parameters/Interactions**: Uses `value` as `price`, `_balance`, and timestamp.

#### _clearRouters()
- **Purpose**: Clears `_routers` mapping using `ICCAgent.getRouters`.
- **Callers**: `resetRouters`.
- **Internal Call Tree**: `ICCAgent.getRouters`.
- **Parameters/Interactions**: Resets `_routers`, `_routersSet`.

#### _fetchAgentRouters() returns (address[] memory newRouters)
- **Purpose**: Fetches routers from `ICCAgent.getRouters`.
- **Callers**: `resetRouters`.
- **Internal Call Tree**: `ICCAgent.getRouters`.
- **Parameters/Interactions**: Returns router array or empty array.

#### _setNewRouters(address[] memory newRouters)
- **Purpose**: Updates `_routers` mapping with new routers.
- **Callers**: `resetRouters`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `_routers` entries to true, updates `_routersSet`.

## Parameters and Interactions
- **Orders**: `ccUpdate` with `updateType=0` updates `_balance`. Buy (`updateType=1`): inputs `tokenB` (`amounts.filled`), outputs `tokenA` (`amounts.amountSent`). Sell (`updateType=2`): inputs `tokenA` (`amounts.filled`), outputs `tokenB` (`amounts.amountSent`). Buy adds to `yVolume`, sell to `xVolume`. Tracked via `orderStatus`, emits `OrderUpdatesComplete` or `OrderUpdateIncomplete`.
- **Price**: Computed via `IUniswapV2Pair`, `IERC20.balanceOf` in `prices`.
- **Registry**: Updated via `_updateRegistry` in `ccUpdate`, `transactToken`, `transactNative` with `tokenA`, `tokenB`.
- **Globalizer**: Updated via `globalizeUpdate` in `ccUpdate` with `maker`, `tokenA` or `tokenB`.
- **Liquidity**: `ICCLiquidityTemplate.liquidityDetail` for fees in `ccUpdate`, stored in `dayStartFee`.
- **Historical Data**: Stored in `_historicalData` via `ccUpdate` (`updateType=3`) or auto-generated, using Uniswap V2 price.
- **External Calls**: `IERC20.balanceOf` (`prices`, `volumeBalances`, `transactToken`), `IERC20.transfer` (`transactToken`), `IERC20.decimals` (`setTokens`), `IUniswapV2Pair.token0` (`ccUpdate`), `ICCLiquidityTemplate.liquidityDetail` (`ccUpdate`), `ITokenRegistry.initializeTokens` (`_updateRegistry`), `ICCGlobalizer.globalizeOrders` (`globalizeUpdate`), `ICCAgent.getLister` (`resetRouters`), `ICCAgent.getRouters` (`resetRouters`, `_clearRouters`, `_fetchAgentRouters`), low-level `call` (`transactNative`).
- **Security**: Router checks, try-catch, explicit casting, relaxed validation, emits `UpdateFailed`, `TransactionFailed`, `ExternalCallFailed`, `RegistryUpdateFailed`, `GlobalUpdateFailed`.
- **Optimization**: Normalized amounts, `maxIterations` in view functions, auto-generated historical data, helper functions in `ccUpdate` and `resetRouters`.
