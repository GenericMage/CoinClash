# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract, written in Solidity (^0.8.2), facilitates decentralized trading for a token pair, integrating with Uniswap V2 for price discovery using token balances (`IERC20.balanceOf`) for consistent scaling. It manages buy/sell orders, long/short payouts, and tracks normalized (1e18 precision) balances and volumes. Licensed under BSL 1.1 - Peng Protocol 2025, it ensures secure, modular design with explicit casting, no inline assembly, and graceful degradation for external calls.

## Version
- **0.1.12**
- **Changes**:
  - v0.1.12: Reintroduced `removePendingOrder(uint256[] storage orders, uint256 orderId)` internal function to remove order IDs from `_pendingBuyOrders`, `_pendingSellOrders`, and `_makerPendingOrders` using swap-and-pop. Modified `update` to call `removePendingOrder` for buy/sell orders with status 0 (cancelled) or 3 (filled), improving gas efficiency by pruning arrays.
  - v0.1.11: Fixed `DeclarationError` by replacing `prices(0)` with `this.prices(0)` in `transactToken` and `transactNative` to correctly call the external `prices` function.
  - v0.1.10: Removed direct price calculations in `transactToken` and `transactNative`, using `this.prices(0)` to reduce code size. Added detailed error logging in `update` for specific failure reasons (invalid update type, struct ID, addresses). Enhanced try-catch blocks in `update`, `_updateRegistry`, `_globalizeUpdate` for detailed error propagation.
  - v0.1.9: Updated price calculation in `prices`, `update`, `transactToken`, and `transactNative` to use `IERC20.balanceOf` for `_tokenA` and `_tokenB` balances in `_uniswapV2Pair`, normalized to 1e18, replacing `getReserves`.
  - v0.1.8: Used `reserveB * 1e18 / reserveA` for tokenB/tokenA pricing in `prices`, `update`, `transactToken`, `transactNative`.
  - v0.1.7: Refactored `_globalizeUpdate` to occur at end of `update`, fetching latest order ID and details (maker, token) for `ICCGlobalizer.globalizeOrders`.
  - v0.1.6: Modified `_globalizeUpdate` to always call `ICCGlobalizer.globalizeOrders` with appropriate token, removing order existence checks.
  - v0.1.5: Updated `_globalizeUpdate` to use `_tokenB` for buy, `_tokenA` for sell in `ICCGlobalizer.globalizeOrders`.
  - v0.1.4: Updated `_updateRegistry` to use `ITokenRegistry.initializeTokens` with both `_tokenA` and `_tokenB`.
  - v0.1.3: Initialized balances for both tokens in `_updateRegistry`.
  - v0.1.2: Modified `LastDayFee` to use `lastDayXFeesAcc`, `lastDayYFeesAcc`. Updated `update` to set these on day change.
  - v0.1.1: Removed `_updateRegistry` calls from `transactToken`, `transactNative`. Added `UpdateRegistryFailed` event.
- **Compatibility**: Compatible with `CCLiquidityTemplate.sol` (v0.1.1), `CCMainPartial.sol` (v0.0.12), `CCLiquidityPartial.sol` (v0.0.21), `ICCLiquidity.sol` (v0.0.5), `ICCListing.sol` (v0.0.7), `CCOrderRouter.sol` (v0.0.11), `TokenRegistry.sol` (2025-08-04), `CCSettlementRouter.sol` (v0.0.10), `CCUniPartial.sol` (v0.0.22), `CCSettlementPartial.sol` (v0.0.25).

## Interfaces
- **IERC20**: Provides `decimals()`, `transfer(address, uint256)`, `balanceOf(address)` for token precision, transfers, and balance queries for `_tokenA`, `_tokenB`.
- **ICCListing**: Exposes view functions (`prices`, `volumeBalances`, `liquidityAddressView`, `tokenA`, `tokenB`, `decimalsA`, `decimalsB`) and `ssUpdate` for payout updates. `PayoutUpdate` struct defines `payoutType` (0: Long, 1: Short), `recipient`, `required`.
- **IUniswapV2Pair**: Provides `token0`, `token1` to map `_tokenA`, `_tokenB` to pair tokens.
- **ICCListingTemplate**: Declares `getTokens`, `globalizerAddressView`, `makerPendingBuyOrdersView`, `makerPendingSellOrdersView`.
- **ICCLiquidityTemplate**: Provides `liquidityDetail` for fee data (`xLiquid`, `yLiquid`, `xFees`, `yFees`, `xFeesAcc`, `yFeesAcc`).
- **ITokenRegistry**: Defines `initializeTokens(address user, address[] memory tokens)` for balance updates.
- **ICCGlobalizer**: Defines `globalizeOrders(address maker, address token)` for order globalization.

Interfaces avoid naming conflicts and use try-catch for external calls.

## Structs
- **LastDayFee**: Tracks `lastDayXFeesAcc`, `lastDayYFeesAcc`, `timestamp` (midnight).
- **VolumeBalance**: Stores `xBalance`, `yBalance`, `xVolume`, `yVolume` (normalized, 1e18).
- **HistoricalData**: Records `price` (tokenB/tokenA, 1e18), `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`.
- **BuyOrderCore**: Stores `makerAddress`, `recipientAddress`, `status` (0: cancelled, 1: pending, 2: partially filled, 3: filled).
- **BuyOrderPricing**: Stores `maxPrice`, `minPrice` (1e18).
- **BuyOrderAmounts**: Tracks `pending` (tokenB), `filled` (tokenB), `amountSent` (tokenA).
- **SellOrderCore**, **SellOrderPricing**, **SellOrderAmounts**: Similar to buy order structs, with `pending` (tokenA), `amountSent` (tokenB).
- **LongPayoutStruct**: Tracks `makerAddress`, `recipientAddress`, `required` (tokenB), `filled`, `orderId`, `status`.
- **ShortPayoutStruct**: Tracks `makerAddress`, `recipientAddress`, `amount` (tokenA), `filled`, `orderId`, `status`.
- **UpdateType**: Defines updates with `updateType` (0: balance, 1: buy order, 2: sell order, 3: historical), `structId` (0: Core, 1: Pricing, 2: Amounts), `index`, `value`, `addr`, `recipient`, `maxPrice`, `minPrice`, `amountSent`.
- **PayoutUpdate**: Specifies `payoutType`, `recipient`, `required` for `ssUpdate`.

Structs avoid nested calls during initialization.

## State Variables
- `_routers`: `mapping(address => bool)` - Authorized routers.
- `_routersSet`: `bool` - Locks router settings.
- `_tokenA`, `_tokenB`: `address` - Token pair (ETH as `address(0)`).
- `_decimalsA`, `_decimalsB`: `uint8` - Token decimals (18 for ETH).
- `_uniswapV2Pair`, `_uniswapV2PairSet`: `address`, `bool` - Uniswap V2 pair.
- `_listingId`: `uint256` - Listing identifier.
- `_agent`: `address` - Agent for registry access.
- `_registryAddress`: `address` - `ITokenRegistry` address.
- `_liquidityAddress`: `address` - `ICCLiquidityTemplate` address.
- `_globalizerAddress`, `_globalizerSet`: `address`, `bool` - Globalizer contract.
- `_nextOrderId`: `uint256` - Order ID counter.
- `_lastDayFee`: `LastDayFee` - Daily fee tracking.
- `_volumeBalance`: `VolumeBalance` - Balances and volumes.
- `_currentPrice`: `uint256` - Current price (tokenB/tokenA, 1e18).
- `_pendingBuyOrders`, `_pendingSellOrders`: `uint256[]` - Pending order IDs.
- `_longPayoutsByIndex`, `_shortPayoutsByIndex`: `uint256[]` - Payout IDs.
- `_makerPendingOrders`: `mapping(address => uint256[])` - Maker order IDs.
- `_userPayoutIDs`: `mapping(address => uint256[])` - User payout IDs.
- `_historicalData`: `HistoricalData[]` - Price and volume history.
- `_buyOrderCores`, `_buyOrderPricings`, `_buyOrderAmounts`: `mapping(uint256 => ...)` - Buy order data.
- `_sellOrderCores`, `_sellOrderPricings`, `_sellOrderAmounts`: `mapping(uint256 => ...)` - Sell order data.
- `_longPayouts`, `_shortPayouts`: `mapping(uint256 => ...)` - Payout data.

## Functions
### External Functions
#### setGlobalizerAddress(address globalizerAddress_)
- **Purpose**: Sets `_globalizerAddress` for `_globalizeUpdate`.
- **Inputs**: `globalizerAddress_` (non-zero).
- **Logic**: Sets `_globalizerAddress`, `_globalizerSet=true`, emits `GlobalizerAddressSet`.
- **State Changes**: `_globalizerAddress`, `_globalizerSet`.
- **Errors**: Reverts if `_globalizerSet` or `globalizerAddress_ == address(0)`.
- **Call Tree**: None.

#### setUniswapV2Pair(address uniswapV2Pair_)
- **Purpose**: Sets `_uniswapV2Pair` for price calculations.
- **Inputs**: `uniswapV2Pair_` (non-zero).
- **Logic**: Sets `_uniswapV2Pair`, `_uniswapV2PairSet=true`.
- **State Changes**: `_uniswapV2Pair`, `_uniswapV2PairSet`.
- **Errors**: Reverts if `_uniswapV2PairSet` or `uniswapV2Pair_ == address(0)`.
- **Call Tree**: None.

#### setRouters(address[] memory routers_)
- **Purpose**: Authorizes routers in `_routers`.
- **Inputs**: `routers_` (non-empty, non-zero addresses).
- **Logic**: Sets `_routers[router]=true`, `_routersSet=true`.
- **State Changes**: `_routers`, `_routersSet`.
- **Errors**: Reverts if `_routersSet`, `routers_.length == 0`, or any `routers_[i] == address(0)`.
- **Call Tree**: None.

#### setListingId(uint256 listingId_)
- **Purpose**: Sets `_listingId`.
- **Inputs**: `listingId_`.
- **Logic**: Sets `_listingId`.
- **State Changes**: `_listingId`.
- **Errors**: Reverts if `_listingId != 0`.
- **Call Tree**: None.

#### setLiquidityAddress(address liquidityAddress_)
- **Purpose**: Sets `_liquidityAddress`.
- **Inputs**: `liquidityAddress_` (non-zero).
- **Logic**: Sets `_liquidityAddress`.
- **State Changes**: `_liquidityAddress`.
- **Errors**: Reverts if `_liquidityAddress != address(0)` or `liquidityAddress_ == address(0)`.
- **Call Tree**: None.

#### setTokens(address tokenA_, address tokenB_)
- **Purpose**: Sets `_tokenA`, `_tokenB`, `_decimalsA`, `_decimalsB`.
- **Inputs**: `tokenA_`, `tokenB_` (different, at least one non-zero).
- **Logic**: Sets tokens, fetches decimals via `IERC20.decimals` (18 for ETH).
- **State Changes**: `_tokenA`, `_tokenB`, `_decimalsA`, `_decimalsB`.
- **External Interactions**: `IERC20.decimals`.
- **Errors**: Reverts if tokens already set, identical, or both zero.
- **Call Tree**: None.

#### setAgent(address agentAddress_)
- **Purpose**: Sets `_agent`.
- **Inputs**: `agentAddress_` (non-zero).
- **Logic**: Sets `_agent`.
- **State Changes**: `_agent`.
- **Errors**: Reverts if `_agent != address(0)` or `agentAddress_ == address(0)`.
- **Call Tree**: None.

#### setRegistry(address registryAddress_)
- **Purpose**: Sets `_registryAddress`.
- **Inputs**: `registryAddress_` (non-zero).
- **Logic**: Sets `_registryAddress`.
- **State Changes**: `_registryAddress`.
- **Errors**: Reverts if `_registryAddress != address(0)` or `registryAddress_ == address(0)`.
- **Call Tree**: None.

#### update(UpdateType[] calldata updates)
- **Purpose**: Processes balance, buy/sell order, or historical data updates.
- **Inputs**: `updates` (`UpdateType[]` with `updateType`, `structId`, `index`, `value`, `addr`, `recipient`, `maxPrice`, `minPrice`, `amountSent`).
- **Logic**:
  1. Requires `_routers[msg.sender]`.
  2. Iterates updates:
     - `updateType=0`: Updates `_volumeBalance.xBalance`, `yBalance`, emits `BalancesUpdated`.
     - `updateType=1`: Updates buy order (`_buyOrderCores`, `_buyOrderPricings`, `_buyOrderAmounts`), calls `removePendingOrder` for `status=0` or `3`, emits `OrderUpdated`.
     - `updateType=2`: Updates sell order (`_sellOrderCores`, `_sellOrderPricings`, `_sellOrderAmounts`), calls `removePendingOrder` for `status=0` or `3`, emits `OrderUpdated`.
     - `updateType=3`: Pushes to `_historicalData`.
  3. Calls `_updateRegistry` and `_globalizeUpdate` for latest maker.
- **State Changes**: `_volumeBalance`, `_buyOrderCores`, `_buyOrderPricings`, `_buyOrderAmounts`, `_sellOrderCores`, `_sellOrderPricings`, `_sellOrderAmounts`, `_historicalData`, `_pendingBuyOrders`, `_pendingSellOrders`, `_makerPendingOrders`.
- **External Interactions**: `ITokenRegistry.initializeTokens` via `_updateRegistry`, `ICCGlobalizer.globalizeOrders` via `_globalizeUpdate`.
- **Internal Call Tree**:
  - `_updateRegistry`: Calls `ITokenRegistry.initializeTokens` with `_tokenA`, `_tokenB`.
  - `_globalizeUpdate`: Calls `ICCGlobalizer.globalizeOrders` with latest maker and token.
  - `removePendingOrder`: Removes order IDs from `_pendingBuyOrders`, `_pendingSellOrders`, `_makerPendingOrders`.
- **Errors**: Emits `UpdateFailed` for invalid inputs, uses try-catch for external calls.
- **Gas**: Scales with `updates.length`, mitigated by `maxIterations` in view functions.

#### ssUpdate(PayoutUpdate[] calldata payoutUpdates)
- **Purpose**: Creates long/short payout orders.
- **Inputs**: `payoutUpdates` (`PayoutUpdate[]` with `payoutType`, `recipient`, `required`).
- **Logic**:
  1. Requires `_routers[msg.sender]`.
  2. Creates `LongPayoutStruct` (`payoutType=0`) or `ShortPayoutStruct` (`payoutType=1`), updates `_longPayoutsByIndex` or `_shortPayoutsByIndex`, `_userPayoutIDs`, emits `PayoutOrderCreated`.
  3. Increments `_nextOrderId`.
- **State Changes**: `_longPayouts`, `_shortPayouts`, `_longPayoutsByIndex`, `_shortPayoutsByIndex`, `_userPayoutIDs`, `_nextOrderId`.
- **External Interactions**: None.
- **Internal Call Tree**: None.
- **Errors**: Reverts if `!_routers[msg.sender]`.
- **Gas**: Scales with `payoutUpdates.length`.

#### transactToken(address token, uint256 amount, address recipient)
- **Purpose**: Transfers `_tokenA` or `_tokenB`, updates volumes, price, and historical data.
- **Inputs**: `token` (`_tokenA` or `_tokenB`), `amount`, `recipient`.
- **Logic**:
  1. Requires `_routers[msg.sender]`, valid `token`.
  2. Performs pre/post balance checks via `IERC20.balanceOf`.
  3. Transfers via `IERC20.transfer`.
  4. Updates `_volumeBalance.xVolume` (if `_tokenA`) or `yVolume` (if `_tokenB`) using `normalize`.
  5. Updates `_currentPrice` via `this.prices(0)`.
  6. Pushes to `_historicalData`.
- **State Changes**: `_volumeBalance`, `_currentPrice`, `_historicalData`.
- **External Interactions**: `IERC20.balanceOf`, `IERC20.transfer`, `this.prices`.
- **Internal Call Tree**:
  - `normalize`: Normalizes `amount` to 1e18.
- **Errors**: Reverts for invalid router, token, or transfer failure (with reason).
- **Gas**: Minimal, with single external call.

#### transactNative(uint256 amount, address recipient)
- **Purpose**: Transfers ETH, updates volumes, price, and historical data.
- **Inputs**: `amount`, `recipient`.
- **Logic**:
  1. Requires `_routers[msg.sender]`, `msg.value == amount`, `_tokenA` or `_tokenB` as `address(0)`.
  2. Performs pre/post balance checks via `recipient.balance`.
  3. Transfers ETH via `call`.
  4. Updates `_volumeBalance.xVolume` (if `_tokenA==address(0)`) or `yVolume` (if `_tokenB==address(0)`) using `normalize`.
  5. Updates `_currentPrice` via `this.prices(0)`.
  6. Pushes to `_historicalData`.
- **State Changes**: `_volumeBalance`, `_currentPrice`, `_historicalData`.
- **External Interactions**: `IERC20.balanceOf` (via `this.prices`), low-level `call`.
- **Internal Call Tree**:
  - `normalize`: Normalizes `amount` to 1e18.
- **Errors**: Reverts for invalid router, incorrect `msg.value`, no native token, or transfer failure (with reason).
- **Gas**: Minimal, with single external call.

### Internal Functions
#### normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)
- **Purpose**: Normalizes amounts to 1e18 precision.
- **Callers**: Called by `transactToken`, `transactNative`, `prices` to normalize volumes and balances.
- **Logic**: Adjusts `amount` based on `decimals` (multiply if `<18`, divide if `>18`).
- **Gas**: Minimal, pure arithmetic.

#### denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)
- **Purpose**: Converts from 1e18 to token decimals.
- **Callers**: Not used in v0.1.12 but available for external contracts.
- **Logic**: Inverse of `normalize`.
- **Gas**: Minimal, pure arithmetic.

#### _isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)
- **Purpose**: Checks if two timestamps are on the same day.
- **Callers**: Called by `update` to check `_lastDayFee.timestamp` for fee updates.
- **Logic**: Compares `time1/86400 == time2/86400`.
- **Gas**: Minimal, pure arithmetic.

#### _floorToMidnight(uint256 timestamp) returns (uint256 midnight)
- **Purpose**: Rounds timestamp to midnight.
- **Callers**: Called by `update` to set `_lastDayFee.timestamp`.
- **Logic**: Returns `(timestamp / 86400) * 86400`.
- **Gas**: Minimal, pure arithmetic.

#### _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)
- **Purpose**: Calculates volume change since `startTime` for `_volumeBalance.xVolume` or `yVolume`.
- **Callers**: Not used in v0.1.12 but available for external contracts.
- **Logic**: Compares current volume to historical data, limited by `maxIterations`.
- **Gas**: Scales with `_historicalData.length`, capped by `maxIterations`.

#### _updateRegistry(address maker)
- **Purpose**: Updates `ITokenRegistry` with balances for `maker`.
- **Callers**: Called by `update` after processing updates.
- **Logic**: Calls `ITokenRegistry.initializeTokens` with `_tokenA`, `_tokenB`, emits `UpdateRegistryFailed` on failure.
- **External Interactions**: `ITokenRegistry.initializeTokens`.
- **Errors**: Graceful degradation via try-catch.
- **Gas**: Depends on `ITokenRegistry` implementation.

#### removePendingOrder(uint256[] storage orders, uint256 orderId)
- **Purpose**: Removes `orderId` from `_pendingBuyOrders`, `_pendingSellOrders`, or `_makerPendingOrders` using swap-and-pop.
- **Callers**: Called by `update` for buy/sell orders with `status=0` or `3`.
- **Logic**: Swaps `orderId` with the last element and pops the array.
- **Gas**: Scales with array length.

#### _globalizeUpdate(address maker, bool isBuy)
- **Purpose**: Updates `ICCGlobalizer` with latest order details.
- **Callers**: Called by `update` after processing updates.
- **Logic**: Calls `ICCGlobalizer.globalizeOrders` with `maker` and `_tokenB` (buy) or `_tokenA` (sell), emits `UpdateRegistryFailed` on failure.
- **External Interactions**: `ICCGlobalizer.globalizeOrders`.
- **Errors**: Graceful degradation via try-catch.
- **Gas**: Depends on `ICCGlobalizer` implementation.

### View Functions
- **agentView**: Returns `_agent`.
- **uniswapV2PairView**: Returns `_uniswapV2Pair`.
- **prices(uint256)**: Computes price as `reserveB * 1e18 / reserveA` using `IERC20.balanceOf(_uniswapV2Pair)`, normalized via `normalize`. Returns `_currentPrice` on failure.
- **getTokens**: Returns `_tokenA`, `_tokenB`, requires one non-zero.
- **volumeBalances(uint256)**: Returns `_volumeBalance.xBalance`, `yBalance`.
- **liquidityAddressView**: Returns `_liquidityAddress`.
- **tokenA**: Returns `_tokenA`.
- **tokenB**: Returns `_tokenB`.
- **decimalsA**: Returns `_decimalsA`.
- **decimalsB**: Returns `_decimalsB`.
- **getListingId**: Returns `_listingId`.
- **getNextOrderId**: Returns `_nextOrderId`.
- **listingVolumeBalancesView**: Returns `_volumeBalance` fields.
- **listingPriceView**: Returns `_currentPrice`.
- **pendingBuyOrdersView**: Returns `_pendingBuyOrders`.
- **pendingSellOrdersView**: Returns `_pendingSellOrders`.
- **makerPendingOrdersView**: Returns `_makerPendingOrders[maker]`.
- **longPayoutByIndexView**: Returns `_longPayoutsByIndex`.
- **shortPayoutByIndexView**: Returns `_shortPayoutsByIndex`.
- **userPayoutIDsView**: Returns `_userPayoutIDs[user]`.
- **getLongPayout**: Returns `_longPayouts[orderId]`.
- **getShortPayout**: Returns `_shortPayouts[orderId]`.
- **getBuyOrderCore**: Returns `_buyOrderCores[orderId]` fields.
- **getBuyOrderPricing**: Returns `_buyOrderPricings[orderId]` fields.
- **getBuyOrderAmounts**: Returns `_buyOrderAmounts[orderId]` fields.
- **getSellOrderCore**: Returns `_sellOrderCores[orderId]` fields.
- **getSellOrderPricing**: Returns `_sellOrderPricings[orderId]` fields.
- **getSellOrderAmounts**: Returns `_sellOrderAmounts[orderId]` fields.
- **getHistoricalDataView**: Returns `_historicalData[index]`, reverts if invalid.
- **historicalDataLengthView**: Returns `_historicalData.length`.
- **getHistoricalDataByNearestTimestamp**: Returns `_historicalData` entry closest to `targetTimestamp`.
- **globalizerAddressView**: Returns `_globalizerAddress`.
- **makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations)**: Returns pending buy order IDs for `maker`, limited by `maxIterations`, starting at `step`.
- **makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations)**: Returns pending sell order IDs for `maker`, limited by `maxIterations`, starting at `step`.
- **getFullBuyOrderDetails**: Returns `_buyOrderCores`, `_buyOrderPricings`, `_buyOrderAmounts` for `orderId`.
- **getFullSellOrderDetails**: Returns `_sellOrderCores`, `_sellOrderPricings`, `_sellOrderAmounts` for `orderId`.
- **makerOrdersView(address maker, uint256 step, uint256 maxIterations)**: Returns `maker` order IDs from `_makerPendingOrders`, limited by `maxIterations`, starting at `step`.

## Parameters and Interactions
- **Orders** (`UpdateType`): Updates balances (`updateType=0`), buy orders (`updateType=1`, input `_tokenB`, output `_tokenA`), sell orders (`updateType=2`, input `_tokenA`, output `_tokenB`), or historical data (`updateType=3`). Amounts normalized to 1e18 via `normalize`.
- **Payouts** (`PayoutUpdate`): Long payouts (`payoutType=0`, output `_tokenB`), short payouts (`payoutType=1`, output `_tokenA`). Created via `ssUpdate`.
- **Price**: Computed as `reserveB * 1e18 / reserveA` using `IERC20.balanceOf(_uniswapV2Pair)` for `_tokenA`, `_tokenB`, normalized via `normalize`. Stored in `_currentPrice`, updated in `update`, `transactToken`, `transactNative` via `this.prices(0)`.
- **Registry**: Updated via `_updateRegistry` in `update`, calling `ITokenRegistry.initializeTokens` with `_tokenA`, `_tokenB`.
- **Globalizer**: Updated via `_globalizeUpdate` in `update`, calling `ICCGlobalizer.globalizeOrders` with latest maker and token (`_tokenB` for buy, `_tokenA` for sell).
- **Liquidity**: `ICCLiquidityTemplate.liquidityDetail` fetches fees for `_lastDayFee` updates in `update`.
- **External Calls**:
  - `IERC20.balanceOf`, `IERC20.transfer` in `transactToken`, `prices`.
  - `IERC20.decimals` in `setTokens`.
  - `ITokenRegistry.initializeTokens` in `_updateRegistry`.
  - `ICCGlobalizer.globalizeOrders` in `_globalizeUpdate`.
  - Low-level `call` in `transactNative`.
- **Security**: Router checks, try-catch on external calls, explicit casting, no tuple access.
- **Optimization**: Swap-and-pop via `removePendingOrder`, normalized amounts, `maxIterations` for gas control.
