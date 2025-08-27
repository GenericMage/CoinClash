# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract (^0.8.2) enables decentralized trading for a token pair, integrating with Uniswap V2 for price discovery via `IERC20.balanceOf`. It manages buy/sell orders, long/short payouts, and normalized (1e18) balances. Volumes are tracked in `_historicalData` during order settlement/cancellation, with auto-generated historical data if not router-provided. Licensed under BSL 1.1 - Peng Protocol 2025, it uses explicit casting, no inline assembly, and graceful degradation.

## Version
- **0.2.17**
- **Changes**:
  - v0.2.17: Relaxed maker address check in `update`, refactored into helper functions (`_processBalanceUpdate`, `_processBuyOrderUpdate`, `_processSellOrderUpdate`, `_processHistoricalUpdate`) to reduce complexity.
  - v0.2.16: Adjusted `update` to bypass restrictive maker checks in `globalizeUpdate`.
  - v0.2.14: Updated `PayoutUpdate` struct with `filled`, `amountSent`. Modified `ssUpdate` to initialize `filled=0` in `LongPayoutStruct`, `ShortPayoutStruct`, and support `filled`, `amountSent` updates. Ensured router-only access, emitted events.
  - v0.2.13: Renamed state variables/mappings/arrays, removing "View"/"Get".
  - v0.2.12: Restored `pendingBuyOrdersView`, `pendingSellOrdersView` per `ICCListing`. Privatized arrays, simplified `globalizeUpdate` to check only `globalizerAddress`.

- **Compatibility**: Compatible with `CCLiquidityTemplate.sol` (v0.1.3), `CCMainPartial.sol` (v0.0.14), `CCLiquidityPartial.sol` (v0.0.27), `ICCLiquidity.sol` (v0.0.5), `ICCListing.sol` (v0.0.7), `CCOrderRouter.sol` (v0.1.0), `TokenRegistry.sol` (2025-08-04), `CCUniPartial.sol` (v0.1.0), `CCOrderPartial.sol` (v0.1.0).

## Interfaces
- **IERC20**: Defines `decimals()`, `transfer(address, uint256)`, `balanceOf(address)`.
- **ICCListing**: Defines view functions (`prices`, `volumeBalances`, `liquidityAddressView`, `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `pendingBuyOrdersView`, `pendingSellOrdersView`).
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
`_balance` (`xBalance`, `yBalance`) tracks tokens from order creation/settlement, excluding `ICCLiquidityTemplate` fees. Buy orders (`updateType=1`, `structId=2`) add `u.value` to `yBalance`; sell orders (`updateType=2`, `structId=2`) add `u.value` to `xBalance`. Settlement: buy orders add `u.amountSent` to `xBalance`, subtract `u.value` from `yBalance`; sell orders subtract `u.value` from `xBalance`, add `u.amountSent` to `yBalance`. Fees via `ICCLiquidityTemplate.liquidityDetail`, stored in `dayStartFee` for `queryYield`.

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
- `listingPrice`: `uint256` - Price (tokenB/tokenA, 1e18).
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
- **Purpose**: Sets `globalizerAddress`.
- **Logic**: Sets `globalizerAddress`, `_globalizerSet=true`, emits `GlobalizerAddressSet`.
- **State Changes**: `globalizerAddress`, `_globalizerSet`.
- **Errors**: Reverts if `_globalizerSet` or `globalizerAddress_ == address(0)`.

#### setUniswapV2Pair(address uniswapV2Pair_)
- **Purpose**: Sets `uniswapV2PairView`.
- **Logic**: Sets `uniswapV2PairView`, `uniswapV2PairViewSet=true`.
- **State Changes**: `uniswapV2PairView`, `uniswapV2PairViewSet`.
- **Errors**: Reverts if `uniswapV2PairViewSet` or `uniswapV2Pair_ == address(0)`.

#### setRouters(address[] memory routers_)
- **Purpose**: Authorizes routers.
- **Logic**: Sets `_routers[router]=true`, `_routersSet=true`.
- **State Changes**: `_routers`, `_routersSet`.
- **Errors**: Reverts if `_routersSet`, `routers_.length == 0`, or any `routers_[i] == address(0)`.

#### setListingId(uint256 _listingId)
- **Purpose**: Sets `listingId`.
- **Logic**: Sets `listingId`.
- **State Changes**: `listingId`.
- **Errors**: Reverts if `listingId != 0`.

#### setLiquidityAddress(address _liquidityAddress)
- **Purpose**: Sets `liquidityAddressView`.
- **Logic**: Sets `liquidityAddressView`.
- **State Changes**: `liquidityAddressView`.
- **Errors**: Reverts if `liquidityAddressView != address(0)` or `_liquidityAddress == address(0)`.

#### setTokens(address _tokenA, address _tokenB)
- **Purpose**: Sets `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `_historicalData`, `dayStartFee`.
- **Logic**: Sets tokens, fetches decimals, initializes `_historicalData`, `dayStartFee` with midnight timestamp.
- **State Changes**: `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `_historicalData`, `_dayStartIndices`, `dayStartFee`.
- **External Interactions**: `IERC20.decimals`.
- **Internal Call Tree**: `_floorToMidnight`.
- **Errors**: Reverts if tokens set, `_tokenA == _tokenB`, or both `address(0)`.

#### setAgent(address _agent)
- **Purpose**: Sets `agentView`.
- **Logic**: Sets `agentView`.
- **State Changes**: `agentView`.
- **Errors**: Reverts if `agentView != address(0)` or `_agent == address(0)`.

#### setRegistry(address registryAddress_)
- **Purpose**: Sets `registryAddress`.
- **Logic**: Sets `registryAddress`.
- **State Changes**: `registryAddress`.
- **Errors**: Reverts if `registryAddress != address(0)` or `registryAddress_ == address(0)`.

#### ssUpdate(PayoutUpdate[] calldata updates)
- **Purpose**: Processes long/short payouts.
- **Logic**: Creates/updates `longPayout`/`shortPayout`, initializes `filled=0`, updates `filled`, `amountSent`, `longPayoutByIndex`, `shortPayoutByIndex`, `userPayoutIDs`, increments `nextOrderId`, emits `PayoutOrderCreated`/`PayoutOrderUpdated`.
- **State Changes**: `longPayout`, `shortPayout`, `longPayoutByIndex`, `shortPayoutByIndex`, `userPayoutIDs`, `nextOrderId`.
- **Errors**: Emits `UpdateFailed` for invalid inputs.

#### update(UpdateType[] calldata updates)
- **Purpose**: Updates balances, orders, historical data.
- **Logic**: Uses `_processBalanceUpdate`, `_processBuyOrderUpdate`, `_processSellOrderUpdate`, `_processHistoricalUpdate` for `updateType=0,1,2,3`. Updates `_balance`, orders, `_pendingBuyOrders`, `_pendingSellOrders`, `makerPendingOrders`, `orderStatus`, `_historicalData`, `dayStartFee`, `_dayStartIndices`. Auto-generates `_historicalData`, updates `listingPrice`, calls `globalizeUpdate`.
- **State Changes**: `_balance`, order mappings, arrays, `_historicalData`, `_dayStartIndices`, `dayStartFee`, `listingPrice`, `nextOrderId`, `orderStatus`.
- **External Interactions**: `IUniswapV2Pair.token0`, `IERC20.balanceOf`, `ITokenRegistry.initializeTokens`, `ICCLiquidityTemplate.liquidityDetail`, `ICCGlobalizer.globalizeOrders`.
- **Internal Call Tree**: `_processBalanceUpdate`, `_processBuyOrderUpdate`, `_processSellOrderUpdate`, `_processHistoricalUpdate`, `_updateRegistry`, `globalizeUpdate`, `removePendingOrder`, `normalize`, `_floorToMidnight`, `_isSameDay`.
- **Errors**: Emits `UpdateFailed`, `ExternalCallFailed`, `OrderUpdateIncomplete`.

#### transactToken(address token, uint256 amount, address recipient)
- **Purpose**: Transfers `tokenA`/`tokenB`.
- **Logic**: Checks router, token, `amount`, `recipient`. Transfers via `IERC20.transfer`, checks balances, emits `TransactionFailed` on failure.
- **External Interactions**: `IERC20.balanceOf`, `IERC20.transfer`.
- **Internal Call Tree**: `normalize`.
- **Errors**: Reverts for invalid inputs, emits `TransactionFailed`.

#### transactNative(uint256 amount, address recipient)
- **Purpose**: Transfers ETH.
- **Logic**: Checks router, native support, `amount`, `recipient`, `msg.value`. Transfers via `call`, checks balances, emits `TransactionFailed` on failure.
- **External Interactions**: Low-level `call`.
- **Errors**: Reverts for invalid inputs, emits `TransactionFailed`.

#### queryYield(bool isTokenA, uint256 depositAmount) returns (uint256 yieldAnnualized)
- **Purpose**: Calculates annualized yield.
- **Logic**: Fetches fees from `ICCLiquidityTemplate.liquidityDetail`, uses `dayStartFee`, computes `dailyFees * 365 * 10000 / depositAmount`.
- **External Interactions**: `ICCLiquidityTemplate.liquidityDetail`.
- **Internal Call Tree**: `_isSameDay`.
- **Errors**: Returns 0 if invalid inputs or call fails.

#### queryDurationVolume(bool isA, uint256 durationDays, uint256 maxIterations) returns (uint256 volume)
- **Purpose**: Sums volume over `durationDays`.
- **Logic**: Sums `xVolume`/`yVolume` from `_historicalData`, capped by `maxIterations`.
- **Internal Call Tree**: `_floorToMidnight`.
- **Errors**: Reverts if `durationDays==0` or `maxIterations==0`, returns 0 if `_historicalData` empty.

#### getLastDays(uint256 count, uint256 maxIterations) returns (uint256[] memory indices, uint256[] memory timestamps)
- **Purpose**: Returns day boundary indices/timestamps.
- **Logic**: Collects `_dayStartIndices` entries, capped by `maxIterations`.
- **Internal Call Tree**: `_floorToMidnight`.
- **Errors**: Reverts if `maxIterations==0`.

#### getTokens() returns (address tokenA_, address tokenB_)
- **Purpose**: Returns token pair.
- **Logic**: Returns `tokenA`, `tokenB`.
- **Errors**: Reverts if both `address(0)`.

#### prices(uint256) returns (uint256 price)
- **Purpose**: Computes price from Uniswap V2 balances.
- **Logic**: Normalizes `IERC20.balanceOf(uniswapV2PairView)`, computes `(balanceB * 1e18) / balanceA`.
- **External Interactions**: `IERC20.balanceOf`.
- **Internal Call Tree**: `normalize`.
- **Errors**: Returns `listingPrice` if call fails.

#### volumeBalances(uint256) returns (uint256 xBalance, uint256 yBalance)
- **Purpose**: Returns normalized contract balances.
- **Logic**: Fetches `IERC20.balanceOf(address(this))` or ETH balance, normalizes.
- **External Interactions**: `IERC20.balanceOf`.
- **Internal Call Tree**: `normalize`.

#### pendingBuyOrdersView() returns (uint256[] memory)
- **Purpose**: Returns `_pendingBuyOrders`.
- **Logic**: Returns pending buy order IDs.

#### pendingSellOrdersView() returns (uint256[] memory)
- **Purpose**: Returns `_pendingSellOrders`.
- **Logic**: Returns pending sell order IDs.

#### makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory)
- **Purpose**: Returns pending buy order IDs for `maker`.
- **Logic**: Filters `makerPendingOrders[maker]` for `status=1`, capped by `maxIterations`.

#### makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory)
- **Purpose**: Returns pending sell order IDs for `maker`.
- **Logic**: Filters `makerPendingOrders[maker]` for `status=1`, capped by `maxIterations`.

#### getBuyOrderCore(uint256 orderId) returns (address makerAddress, address recipientAddress, uint8 status)
- **Purpose**: Returns buy order core details.
- **Logic**: Returns `buyOrderCore[orderId]`.

#### getBuyOrderPricing(uint256 orderId) returns (uint256 maxPrice, uint256 minPrice)
- **Purpose**: Returns buy order pricing.
- **Logic**: Returns `buyOrderPricing[orderId]`.

#### getBuyOrderAmounts(uint256 orderId) returns (uint256 pending

, uint256 filled, uint256 amountSent)
- **Purpose**: Returns buy order amounts.
- **Logic**: Returns `buyOrderAmounts[orderId]`.

#### getSellOrderCore(uint256 orderId) returns (address makerAddress, address recipientAddress, uint8 status)
- **Purpose**: Returns sell order core details.
- **Logic**: Returns `sellOrderCore[orderId]`.

#### getSellOrderPricing(uint256 orderId) returns (uint256 maxPrice, uint256 minPrice)
- **Purpose**: Returns sell order pricing.
- **Logic**: Returns `sellOrderPricing[orderId]`.

#### getSellOrderAmounts(uint256 orderId) returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Purpose**: Returns sell order amounts.
- **Logic**: Returns `sellOrderAmounts[orderId]`.

#### getFullBuyOrderDetails(uint256 orderId) returns (BuyOrderCore, BuyOrderPricing, BuyOrderAmounts)
- **Purpose**: Returns full buy order details.
- **Logic**: Returns `buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`.

#### getFullSellOrderDetails(uint256 orderId) returns (SellOrderCore, SellOrderPricing, SellOrderAmounts)
- **Purpose**: Returns full sell order details.
- **Logic**: Returns `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`.

#### makerOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory)
- **Purpose**: Returns `maker` order IDs from `step`.
- **Logic**: Slices `makerPendingOrders[maker]`, capped by `maxIterations`.

#### makerPendingOrdersView(address maker) returns (uint256[] memory)
- **Purpose**: Returns all `maker` pending order IDs.
- **Logic**: Returns `makerPendingOrders[maker]`.

#### longPayoutByIndexView() returns (uint256[] memory)
- **Purpose**: Returns `longPayoutByIndex`.
- **Logic**: Returns long payout order IDs.

#### shortPayoutByIndexView() returns (uint256[] memory)
- **Purpose**: Returns `shortPayoutByIndex`.
- **Logic**: Returns short payout order IDs.

#### userPayoutIDsView(address user) returns (uint256[] memory)
- **Purpose**: Returns `user` payout order IDs.
- **Logic**: Returns `userPayoutIDs[user]`.

#### getHistoricalDataView(uint256 index) returns (HistoricalData)
- **Purpose**: Returns `_historicalData[index]`.
- **Logic**: Returns data, reverts if `index` invalid.
- **Errors**: Reverts if `index >= _historicalData.length`.

#### historicalDataLengthView() returns (uint256)
- **Purpose**: Returns `_historicalData.length`.
- **Logic**: Returns length.

### Internal Functions
#### normalize(uint256 amount, uint8 decimals) returns (uint256)
- **Purpose**: Normalizes to 1e18.
- **Callers**: `transactToken`, `update`, `prices`, `volumeBalances`.

#### denormalize(uint256 amount, uint8 decimals) returns (uint256)
- **Purpose**: Converts from 1e18 to token decimals.
- **Callers**: None in v0.2.17.

#### _isSameDay(uint256 time1, uint256 time2) returns (bool)
- **Purpose**: Checks same-day timestamps.
- **Callers**: `update`, `queryYield`.

#### _floorToMidnight(uint256 timestamp) returns (uint256)
- **Purpose**: Rounds timestamp to midnight.
- **Callers**: `setTokens`, `update`, `queryDurationVolume`, `getLastDays`.

#### _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256)
- **Purpose**: Returns volume from `_historicalData` at/after `startTime`.
- **Callers**: None in v0.2.17.

#### _updateRegistry(address maker)
- **Purpose**: Updates registry with `tokenA`, `tokenB` balances.
- **Callers**: `update`.
- **External Interactions**: `ITokenRegistry.initializeTokens`.
- **Errors**: Emits `RegistryUpdateFailed`, `ExternalCallFailed`.

#### removePendingOrder(uint256[] storage orders, uint256 orderId)
- **Purpose**: Removes `orderId` from order arrays.
- **Callers**: `update`.

#### globalizeUpdate()
- **Purpose**: Calls `ICCGlobalizer.globalizeOrders` for latest order.
- **Callers**: `update`.
- **External Interactions**: `ICCGlobalizer.globalizeOrders`.
- **Errors**: Emits `ExternalCallFailed`, `globalUpdateFailed`.

#### _processBalanceUpdate(UpdateType calldata u)
- **Purpose**: Updates `_balance` for `updateType=0`.
- **Callers**: `update`.

#### _processBuyOrderUpdate(UpdateType calldata u, bool hasBalanceUpdate)
- **Purpose**: Updates buy orders for `updateType=1`.
- **Callers**: `update`.

#### _processSellOrderUpdate(UpdateType calldata u, bool hasBalanceUpdate)
- **Purpose**: Updates sell orders for `updateType=2`.
- **Callers**: `update`.

#### _processHistoricalUpdate(UpdateType calldata u)
- **Purpose**: Updates `_historicalData` for `updateType=3`.
- **Callers**: `update`.

#### uint2str(uint256 _i) returns (string)
- **Purpose**: Converts uint to string for errors.
- **Callers**: None in v0.2.17.

## Parameters and Interactions
- **Orders** (`UpdateType`): `updateType=0`: updates `_balance`. Buy (`updateType=1`): inputs `tokenB` (`value`), outputs `tokenA` (`amountSent`). Sell (`updateType=2`): inputs `tokenA` (`value`), outputs `tokenB` (`amountSent`). Creation: buy adds `value` to `yBalance`, sell adds `value` to `xBalance`. Settlement: buy adds `amountSent` to `xBalance`, subtracts `value` from `yBalance`; sell subtracts `value` from `xBalance`, adds `amountSent` to `yBalance`. Cancellation (`status=0`) or settlement (`status=3`): buy updates `yVolume += pending`, sell updates `xVolume += pending`. Tracked via `orderStatus`, emits `OrderUpdatesComplete`/`OrderUpdateIncomplete`.
- **Payouts** (`PayoutUpdate`): Long (`payoutType=0`, `tokenB`), short (`payoutType=1`, `tokenA`) via `ssUpdate`, indexed by `nextOrderId`. Supports `filled`, `amountSent` updates.
- **Price**: Computed via `IUniswapV2Pair`, `IERC20.balanceOf(uniswapV2PairView)`, stored in `listingPrice`.
- **Registry**: Updated via `_updateRegistry` in `update`.
- **Globalizer**: Updated via `globalizeUpdate` in `update`.
- **Liquidity**: `ICCLiquidityTemplate.liquidityDetail` used in `update`, `queryYield`.
- **Historical Data**: Stored in `_historicalData` via `update` (`updateType=3`) or auto-generated if not same-day, using Uniswap V2 price, carrying forward volumes. Updated on order cancellation/settlement.
- **External Calls**: `IERC20.balanceOf`, `IERC20.transfer`, `IERC20.decimals`, `ITokenRegistry.initializeTokens`, `ICCLiquidityTemplate.liquidityDetail`, `ICCGlobalizer.globalizeOrders`, low-level `call`.
- **Security**: Router checks, try-catch, explicit casting, no tuple access, relaxed validation, emits `UpdateFailed` for invalid updates.
- **Optimization**: Normalized amounts, `maxIterations`, auto-generated historical data, helper functions in `update`.