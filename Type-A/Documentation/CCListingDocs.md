# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract (Solidity ^0.8.2) supports decentralized trading for a token pair, using Uniswap V2 for price discovery via `IERC20.balanceOf`. It manages buy and sell orders, long and short payouts, and normalized (1e18 precision) balances. Volumes are tracked in `_historicalData` during order settlement or cancellation, with auto-generated historical data if not provided by routers. Licensed under BSL 1.1 - Peng Protocol 2025, it uses explicit casting, avoids inline assembly, and ensures graceful degradation with try-catch for external calls.

## Version
- **0.3.0**
- **Changes**:
  - v0.2.25: Replaced `update` with `ccUpdate`, using three parameters (`updateType`, `updateSort`, `updateData`). Removed logic in `_processBuyOrderUpdate` and `_processSellOrderUpdate` for reducing `pending` relative to `filled` or distinguishing order creation vs settlement. Routers now directly assign all fields in `BuyOrderCore`, `BuyOrderPricing`, `BuyOrderAmounts`, `SellOrderCore`, `SellOrderPricing`, `SellOrderAmounts` via `abi.decode`, except auto-generated fields (`orderStatus`, `_historicalData.timestamp`, `_dayStartIndices`, volume updates).
  - v0.2.24: Modified `ccUpdate` and helper functions to remove logic reducing `pending` relative to `filled` or assigning `pending`/`filled` based on order creation vs settlement. Routers directly assign fields except auto-generated ones.
  - v0.2.23: Modified `update` to reduce `pending` by `filled` during settlement for buy and sell orders when `amountSent > 0` or `amounts.pending > 0`. Added underflow protection.
  - v0.2.22: Added `floorToMidnightView`, `isSameDayView`, `getDayStartIndex`. Removed `getMidnightIndicies`. Modified `update` for order state using `amountSent` and `pending`. Moved analytics to `CCDexlytan`.
  - v0.2.21: Removed `listingPrice` from `update` and `prices`. Renamed `getLastDays` to `getMidnightIndices`.
  - v0.2.20: Modified `update` to create `HistoricalData` entry during settlement.
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
- **Purpose**: Sets globalizer contract address (callable once).
- **State Changes**: `globalizerAddress`, `_globalizerSet`.
- **Errors**: Reverts if already set or invalid address.
- **Internal Call Tree**: None.

#### setUniswapV2Pair(address uniswapV2Pair_)
- **Purpose**: Sets Uniswap V2 pair address (callable once).
- **State Changes**: `uniswapV2PairView`, `uniswapV2PairViewSet`.
- **Errors**: Reverts if already set or invalid address.
- **Internal Call Tree**: None.

#### setRouters(address[] memory routers_)
- **Purpose**: Authorizes routers for `ccUpdate`, `ssUpdate`, `transactToken`, `transactNative` (callable once).
- **State Changes**: `_routers`, `_routersSet`.
- **Errors**: Reverts if already set, empty array, or invalid addresses.
- **Internal Call Tree**: None.

#### setListingId(uint256 _listingId)
- **Purpose**: Sets listing identifier (callable once).
- **State Changes**: `listingId`.
- **Errors**: Reverts if already set.
- **Internal Call Tree**: None.

#### setLiquidityAddress(address _liquidityAddress)
- **Purpose**: Sets liquidity contract address (callable once).
- **State Changes**: `liquidityAddressView`.
- **Errors**: Reverts if already set or invalid address.
- **Internal Call Tree**: None.

#### setTokens(address _tokenA, address _tokenB)
- **Purpose**: Initializes token pair, decimals, and historical data.
- **State Changes**: `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `_historicalData`, `_dayStartIndices`, `dayStartFee`.
- **External Interactions**: `IERC20.decimals`.
- **Internal Call Tree**: `_floorToMidnight`.
- **Errors**: Reverts if tokens already set, identical, or both zero.

#### setAgent(address _agent)
- **Purpose**: Sets agent address (callable once).
- **State Changes**: `agentView`.
- **Errors**: Reverts if already set or invalid address.
- **Internal Call Tree**: None.

#### setRegistry(address registryAddress_)
- **Purpose**: Sets registry address (callable once).
- **State Changes**: `registryAddress`.
- **Errors**: Reverts if already set or invalid address.
- **Internal Call Tree**: None.

#### ssUpdate(PayoutUpdate[] calldata updates)
- **Purpose**: Processes long/short payout updates.
- **Logic**: Creates/updates `longPayout` or `shortPayout`, sets `filled=0` for new payouts, updates fields, adds to `longPayoutByIndex`, `shortPayoutByIndex`, `userPayoutIDs`. Increments `nextOrderId`.
- **State Changes**: `longPayout`, `shortPayout`, `longPayoutByIndex`, `shortPayoutByIndex`, `userPayoutIDs`, `nextOrderId`.
- **Errors**: Emits `UpdateFailed` for invalid inputs.
- **Internal Call Tree**: None.

#### ccUpdate(uint8[] calldata updateType, uint8[] calldata updateSort, uint256[] calldata updateData)
- **Purpose**: Updates balances, buy/sell orders, or historical data, callable by routers.
- **Parameters**:
  - `updateType`: Array of update types (0: balance, 1: buy order, 2: sell order, 3: historical).
  - `updateSort`: Array specifying the struct to update (0: Core, 1: Pricing, 2: Amounts for orders; 0 for balance/historical).
  - `updateData`: Array of encoded data for struct fields, decoded based on `updateSort` and `updateType`.
- **Logic**:
  1. Verifies router caller and array length consistency (`updateType.length == updateSort.length == updateData.length`).
  2. Computes current midnight timestamp (`(block.timestamp / 86400) * 86400`).
  3. Initializes `balanceUpdated`, `updatedOrders`, `updatedCount` for tracking.
  4. Processes updates in a loop:
     - **Balance (`updateType=0`)**: Calls `_processBalanceUpdate`, sets `_balance.xBalance` or `yBalance` based on `updateSort` (0 for `xBalance`, 1 for `yBalance`) and `updateData` (value), emits `BalancesUpdated`.
     - **Buy Order (`updateType=1`)**: Calls `_processBuyOrderUpdate`. Uses `updateSort` to determine struct:
       - `structId=0` (Core): Decodes `updateData[i]` as `(address makerAddress, address recipientAddress, uint8 status)`. Updates `buyOrderCore[orderId]`, `_pendingBuyOrders`, `makerPendingOrders`. Sets `orderStatus.hasCore`.
       - `structId=1` (Pricing): Decodes `updateData[i]` as `(uint256 maxPrice, uint256 minPrice)`. Updates `buyOrderPricing[orderId]`. Sets `orderStatus.hasPricing`.
       - `structId=2` (Amounts): Decodes `updateData[i]` as `(uint256 pending, uint256 filled, uint256 amountSent)`. Updates `buyOrderAmounts[orderId]`, adds `filled` to `yVolume`. Sets `orderStatus.hasAmounts`.
       - Invalid `structId` emits `UpdateFailed`.
     - **Sell Order (`updateType=2`)**: Similar to buy, updates `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_pendingSellOrders`, adds `filled` to `xVolume`.
     - **Historical (`updateType=3`)**: Calls `_processHistoricalUpdate`, creates `HistoricalData` with `price=updateData[i]`, current balances, and timestamp, updates `_dayStartIndices`.
  5. Updates `dayStartFee` if not same day, fetches fees via `ICCLiquidityTemplate.liquidityDetail`.
  6. Checks order completeness (`orderStatus[orderId]`), emits `OrderUpdatesComplete` if all fields set, else `OrderUpdateIncomplete`.
  7. If `balanceUpdated`, fetches pair balances via `IUniswapV2Pair`, `IERC20.balanceOf`.
  8. Calls `globalizeUpdate`.
- **updateSort and updateData Details**:
  - **Purpose**: `updateSort` and `updateData` replace the `UpdateType` struct's fields (`structId`, `index`, `value`, `addr`, `recipient`, `maxPrice`, `minPrice`, `amountSent`) to simplify the function signature and reduce gas costs for routers.
  - **updateSort**: Specifies the target struct for updates:
    - For `updateType=0` (balance): `0` (sets `xBalance`), `1` (sets `yBalance`).
    - For `updateType=1` or `2` (buy/sell orders): `0` (Core), `1` (Pricing), `2` (Amounts).
    - For `updateType=3` (historical): Must be `0` (new `HistoricalData` entry).
  - **updateData**: Encodes struct fields as a single `uint256`, decoded via `abi.decode` using `uint2str` for string conversion:
    - For `updateType=0`: `updateData[i]` is the balance value (normalized, 1e18).
    - For `updateType=1` or `2`:
      - `structId=0`: `updateData[i]` encodes `(address makerAddress, address recipientAddress, uint8 status)`.
      - `structId=1`: `updateData[i]` encodes `(uint256 maxPrice, uint256 minPrice)`.
      - `structId=2`: `updateData[i]` encodes `(uint256 pending, uint256 filled, uint256 amountSent)`.
    - For `updateType=3`: `updateData[i]` is the price or zero (uses midnight timestamp if zero).
  - **Decoding Process**: Uses `abi.decode(bytes(uint2str(updateData[i])), (...))` to extract fields. The `uint2str` function converts `updateData[i]` to a string for decoding, ensuring routers provide pre-encoded data matching the expected struct format.
  - **Usage Example**:
    - Buy order Core update (`updateType=1`, `updateSort=0`): `updateData[i]` might encode `(0x123..., 0x456..., 1)` for `makerAddress`, `recipientAddress`, `status=1` (pending).
    - Buy order Amounts update (`updateType=1`, `updateSort=2`): `updateData[i]` encodes `(1000, 500, 200)` for `pending`, `filled`, `amountSent`.
    - Balance update (`updateType=0`, `updateSort=1`): `updateData[i]` is a direct value, e.g., `1000e18` for `yBalance`.
  - **Validation**: Ensures array lengths match and `structId` is valid, emitting `UpdateFailed` otherwise.
- **State Changes**: `_balance`, `buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`, `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_pendingBuyOrders`, `_pendingSellOrders`, `makerPendingOrders`, `orderStatus`, `_historicalData`, `_dayStartIndices`, `dayStartFee`.
- **External Interactions**: `IUniswapV2Pair.token0`, `IERC20.balanceOf`, `ITokenRegistry.initializeTokens`, `ICCLiquidityTemplate.liquidityDetail`, `ICCGlobalizer.globalizeOrders`.
- **Internal Call Tree**: `_processBalanceUpdate`, `_processBuyOrderUpdate`, `_processSellOrderUpdate`, `_processHistoricalUpdate`, `removePendingOrder`, `_updateRegistry`, `globalizeUpdate`, `_floorToMidnight`, `_isSameDay`, `uint2str`.
- **Errors**: Emits `UpdateFailed`, `OrderUpdateIncomplete`, `OrderUpdatesComplete`.

#### transactToken(address token, uint256 amount, address recipient)
- **Purpose**: Transfers ERC20 tokens.
- **Logic**: Verifies router, token, recipient, amount. Calls `IERC20.transfer`, checks balances.
- **External Interactions**: `IERC20.balanceOf`, `IERC20.transfer`.
- **Internal Call Tree**: `uint2str`.
- **Errors**: Reverts for invalid inputs, emits `TransactionFailed`.

#### transactNative(uint256 amount, address recipient)
- **Purpose**: Transfers ETH.
- **Logic**: Verifies router, recipient, amount. Uses `call`, checks balances.
- **External Interactions**: Low-level `call`.
- **Internal Call Tree**: `uint2str`.
- **Errors**: Reverts for invalid inputs, emits `TransactionFailed`.

#### getTokens() returns (address tokenA_, address tokenB_)
- **Purpose**: Returns token pair addresses.
- **Errors**: Reverts if both are `address(0)`.
- **Internal Call Tree**: None.

#### getNextOrderId() returns (uint256 orderId_)
- **Purpose**: Returns next order ID.
- **Internal Call Tree**: None.

#### getLongPayout(uint256 orderId) returns (LongPayoutStruct memory payout)
- **Purpose**: Returns long payout details.
- **Internal Call Tree**: None.

#### getShortPayout(uint256 orderId) returns (ShortPayoutStruct memory payout)
- **Purpose**: Returns short payout details.
- **Internal Call Tree**: None.

#### prices(uint256) returns (uint256 price)
- **Purpose**: Computes price from Uniswap V2 pair balances.
- **Logic**: Fetches `IERC20.balanceOf`, normalizes, computes `(balanceB * 1e18) / balanceA`.
- **External Interactions**: `IERC20.balanceOf`.
- **Internal Call Tree**: `normalize`.
- **Errors**: Returns 1 if calls fail.

#### volumeBalances(uint256) returns (uint256 xBalance, uint256 yBalance)
- **Purpose**: Returns normalized contract balances.
- **External Interactions**: `IERC20.balanceOf`.
- **Internal Call Tree**: `normalize`.

#### makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns pending buy order IDs for a maker.
- **Internal Call Tree**: None.

#### makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns pending sell order IDs for a maker.
- **Internal Call Tree**: None.

#### getBuyOrderCore(uint256 orderId) returns (address makerAddress, address recipientAddress, uint8 status)
- **Purpose**: Returns buy order core details.
- **Internal Call Tree**: None.

#### getBuyOrderPricing(uint256 orderId) returns (uint256 maxPrice, uint256 minPrice)
- **Purpose**: Returns buy order pricing details.
- **Internal Call Tree**: None.

#### getBuyOrderAmounts(uint256 orderId) returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Purpose**: Returns buy order amounts.
- **Internal Call Tree**: None.

#### getSellOrderCore(uint256 orderId) returns (address makerAddress, address recipientAddress, uint8 status)
- **Purpose**: Returns sell order core details.
- **Internal Call Tree**: None.

#### getSellOrderPricing(uint256 orderId) returns (uint256 maxPrice, uint256 minPrice)
- **Purpose**: Returns sell order pricing details.
- **Internal Call Tree**: None.

#### getSellOrderAmounts(uint256 orderId) returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Purpose**: Returns sell order amounts.
- **Internal Call Tree**: None.

#### makerOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns maker order IDs.
- **Internal Call Tree**: None.

#### makerPendingOrdersView(address maker) returns (uint256[] memory orderIds)
- **Purpose**: Returns all pending order IDs for a maker.
- **Internal Call Tree**: None.

#### longPayoutByIndexView() returns (uint256[] memory orderIds)
- **Purpose**: Returns long payout order IDs.
- **Internal Call Tree**: None.

#### shortPayoutByIndexView() returns (uint256[] memory orderIds)
- **Purpose**: Returns short payout order IDs.
- **Internal Call Tree**: None.

#### userPayoutIDsView(address user) returns (uint256[] memory orderIds)
- **Purpose**: Returns user payout order IDs.
- **Internal Call Tree**: None.

#### getHistoricalDataView(uint256 index) returns (HistoricalData memory data)
- **Purpose**: Returns historical data at index.
- **Errors**: Reverts if invalid index.
- **Internal Call Tree**: None.

#### historicalDataLengthView() returns (uint256 length)
- **Purpose**: Returns historical data length.
- **Internal Call Tree**: None.

#### floorToMidnightView(uint256 inputTimestamp) returns (uint256 midnight)
- **Purpose**: Rounds timestamp to midnight UTC.
- **Internal Call Tree**: None.

#### isSameDayView(uint256 firstTimestamp, uint256 secondTimestamp) returns (bool sameDay)
- **Purpose**: Checks if timestamps are in the same day.
- **Internal Call Tree**: None.

#### getDayStartIndex(uint256 midnightTimestamp) returns (uint256 index)
- **Purpose**: Returns historical data index for midnight timestamp.
- **Internal Call Tree**: None.

### Internal Functions
#### normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)
- **Purpose**: Converts amounts to 1e18 precision.
- **Callers**: `ccUpdate`, `prices`, `volumeBalances`.

#### denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)
- **Purpose**: Converts amounts from 1e18 to token decimals.
- **Callers**: `transactToken`, `transactNative`.

#### _isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)
- **Purpose**: Checks if timestamps are in the same day.
- **Callers**: `ccUpdate`.

#### _floorToMidnight(uint256 timestamp) returns (uint256 midnight)
- **Purpose**: Rounds timestamp to midnight UTC.
- **Callers**: `setTokens`, `ccUpdate`.

#### _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)
- **Purpose**: Returns volume from `_historicalData` at/after `startTime`.
- **Callers**: None (analytics in `CCDexlytan`).

#### _updateRegistry(address maker)
- **Purpose**: Updates registry with token balances.
- **Callers**: `ccUpdate`.
- **External Interactions**: `ITokenRegistry.initializeTokens`.

#### removePendingOrder(uint256[] storage orders, uint256 orderId)
- **Purpose**: Removes order ID from arrays.
- **Callers**: `ccUpdate`.

#### globalizeUpdate()
- **Purpose**: Notifies `ICCGlobalizer` of latest order.
- **Callers**: `ccUpdate`.
- **External Interactions**: `ICCGlobalizer.globalizeOrders`.

#### uint2str(uint256 _i) returns (string str)
- **Purpose**: Converts uint to string for `abi.decode` and errors.
- **Callers**: `ccUpdate`, `transactToken`, `transactNative`.

## Parameters and Interactions
- **Orders**: `ccUpdate` with `updateType=0`: updates `_balance`. Buy (`updateType=1`): inputs `tokenB` (`amounts.filled`), outputs `tokenA` (`amounts.amountSent`). Sell (`updateType=2`): inputs `tokenA` (`amounts.filled`), outputs `tokenB` (`amounts.amountSent`). Buy adds to `yVolume`, sell to `xVolume`. Tracked via `orderStatus`, emits `OrderUpdatesComplete` or `OrderUpdateIncomplete`.
- **Payouts**: Long (`tokenB`), short (`tokenA`) via `ssUpdate`, indexed by `nextOrderId`.
- **Price**: Computed via `IUniswapV2Pair`, `IERC20.balanceOf`.
- **Registry**: Updated via `_updateRegistry` in `ccUpdate`.
- **Globalizer**: Updated via `globalizeUpdate` in `ccUpdate`.
- **Liquidity**: `ICCLiquidityTemplate.liquidityDetail` for fees in `ccUpdate`.
- **Historical Data**: Stored in `_historicalData` via `ccUpdate` (`updateType=3`) or auto-generated, using Uniswap V2 price.
- **External Calls**: `IERC20.balanceOf`, `IERC20.transfer`, `IERC20.decimals`, `ITokenRegistry.initializeTokens`, `ICCLiquidityTemplate.liquidityDetail`, `ICCGlobalizer.globalizeOrders`, low-level `call`.
- **Security**: Router checks, try-catch, explicit casting, relaxed validation, emits `UpdateFailed`.
- **Optimization**: Normalized amounts, `maxIterations`, auto-generated historical data, helper functions in `ccUpdate`.
