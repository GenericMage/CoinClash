# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract, written in Solidity (^0.8.2), facilitates decentralized trading for a token pair, integrating with Uniswap V2 for price discovery using token balances (`IERC20.balanceOf`) for consistent scaling. It manages buy/sell orders, long/short payouts, and tracks normalized (1e18 precision) balances and volumes. Licensed under BSL 1.1 - Peng Protocol 2025, it ensures secure, modular design with explicit casting, no inline assembly, and graceful degradation for external calls.

## Version
- **0.1.10**
- **Changes**:
  - v0.1.10: Added error logging in `update`, `transactToken`, `transactNative` with new events `ExternalCallFailed`, `UpdateFailed`, `TransactionFailed`. Emitted decoded reasons from external calls and added specific revert messages.
  - v0.1.9: Modified price calculation in `prices`, `update`, `transactToken`, and `transactNative` to use `IERC20.balanceOf` for `_tokenA` and `_tokenB` from `_uniswapV2Pair`, addressing incorrect price scaling.
  - v0.1.8: Modified price calculation in `prices`, `update`, `transactToken`, and `transactNative` to use `reserveB / reserveA * 1e18` instead of `reserveA / reserveB * 1e18`.
  - v0.1.7: Refactored `globalizeUpdate` to occur at end of `update`, fetching latest order ID and details (maker, token) for `ICCGlobalizer.globalizeOrders` call.
  - v0.1.6: Modified `globalizeUpdate` to always call `ICCGlobalizer.globalizeOrders` for the maker with appropriate token, removing all checks for order existence.
  - v0.1.5: Updated `globalizeUpdate` to call `ICCGlobalizer.globalizeOrders` with token (`_tokenB` for buy, `_tokenA` for sell) instead of listing address, aligning with new `ICCGlobalizer` interface (v0.2.1).
  - v0.1.4: Updated `_updateRegistry` to use `ITokenRegistry.initializeTokens`, passing both `_tokenA` and `_tokenB` (if non-zero) for a single maker, replacing `initializeBalances` calls.
  - v0.1.3: Updated `_updateRegistry` to initialize balances for both `_tokenA` and `_tokenB` (if non-zero), removing `block.timestamp % 2` token selection.
  - v0.1.2: Modified `LastDayFee` struct to use `lastDayXFeesAcc`, `lastDayYFeesAcc`. Updated `update` to set `lastDayXFeesAcc`, `lastDayYFeesAcc` on day change.
  - v0.1.1: Removed `_updateRegistry` calls from `transactToken`, `transactNative`. Added `UpdateRegistryFailed` event.
- **Compatibility**: Compatible with `CCLiquidityTemplate.sol` (v0.1.1), `CCMainPartial.sol` (v0.0.12), `CCLiquidityPartial.sol` (v0.0.21), `ICCLiquidity.sol` (v0.0.5), `ICCListing.sol` (v0.0.7), `CCOrderRouter.sol` (v0.0.11), `TokenRegistry.sol` (2025-08-04).

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
- **Purpose**: Sets `_globalizerAddress` for `globalizeUpdate`.
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
- **External Interactions**: `IERC20.decimals` for `_tokenA`, `_tokenB`.
- **Errors**: Reverts if tokens already set, identical, or both zero.
- **Call Tree**: None.

#### setAgent(address agent_)
- **Purpose**: Sets `_agent`.
- **Inputs**: `agent_` (non-zero).
- **Logic**: Sets `_agent`.
- **State Changes**: `_agent`.
- **Errors**: Reverts if `_agent != address(0)` or `agent_ == address(0)`.
- **Call Tree**: None.

#### setRegistry(address registryAddress_)
- **Purpose**: Sets `_registryAddress`.
- **Inputs**: `registryAddress_` (non-zero).
- **Logic**: Sets `_registryAddress`.
- **State Changes**: `_registryAddress`.
- **Errors**: Reverts if `_registryAddress != address(0)` or `registryAddress_ == address(0)`.
- **Call Tree**: None.

#### update(UpdateType[] memory updates)
- **Purpose**: Processes balance, buy/sell order, or historical data updates.
- **Inputs**: `updates` (`UpdateType[]` with `updateType`, `structId`, `index`, `value`, `addr`, `recipient`, `maxPrice`, `minPrice`, `amountSent`).
- **Logic**:
  1. Requires `_routers[msg.sender]`.
  2. Checks for volume updates (`updateType=0` for `xVolume`, `yVolume`, or `updateType=1,2` for non-zero `value` in `structId=2`).
  3. If volume updated and new day, fetches fees via `ICCLiquidityTemplate.liquidityDetail`, updates `_lastDayFee`.
  4. Iterates updates:
     - `updateType=0`: Updates `_volumeBalance.xBalance`, `yBalance`, `xVolume`, `yVolume`.
     - `updateType=1`: Updates buy order (`_buyOrderCores`, `_buyOrderPricings`, `_buyOrderAmounts`), emits `OrderUpdated`.
     - `updateType=2`: Updates sell order (`_sellOrderCores`, `_sellOrderPricings`, `_sellOrderAmounts`), emits `OrderUpdated`.
     - `updateType=3`: Pushes to `_historicalData`.
  5. Updates `_currentPrice` using `IERC20.balanceOf(_uniswapV2Pair)` for `_tokenA`, `_tokenB`.
  6. Calls `_updateRegistry` and `globalizeUpdate` for latest maker.
- **State Changes**: `_volumeBalance`, `_buyOrderCores`, `_buyOrderPricings`, `_buyOrderAmounts`, `_sellOrderCores`, `_sellOrderPricings`, `_sellOrderAmounts`, `_historicalData`, `_pendingBuyOrders`, `_pendingSellOrders`, `_makerPendingOrders`, `_currentPrice`, `_lastDayFee`, `_nextOrderId`.
- **External Interactions**:
  - `ICCLiquidityTemplate.liquidityDetail` for fees.
  - `IERC20.balanceOf` for `_tokenA`, `_tokenB` in `_uniswapV2Pair`.
  - `ITokenRegistry.initializeTokens` via `_updateRegistry`.
  - `ICCGlobalizer.globalizeOrders` via `globalizeUpdate`.
- **Internal Call Tree**:
  - `_isSameDay`: Checks if `_lastDayFee.timestamp` is same day as `block.timestamp`.
  - `_floorToMidnight`: Rounds `block.timestamp` for `_lastDayFee.timestamp`.
  - `_updateRegistry`: Calls `ITokenRegistry.initializeTokens` with `_tokenA`, `_tokenB`.
  - `globalizeUpdate`: Calls `ICCGlobalizer.globalizeOrders` with latest maker and token.
  - `normalize`: Normalizes balances for `_currentPrice`.
- **Errors**: Reverts for invalid router, insufficient pending amounts, or external call failures (emits `UpdateFailed`, `ExternalCallFailed`).
- **Gas**: Scales with `updates.length`, mitigated by `maxIterations` in view functions.

#### ssUpdate(PayoutUpdate[] memory payoutUpdates)
- **Purpose**: Creates long/short payout orders.
- **Inputs**: `payoutUpdates` (`PayoutUpdate[]` with `payoutType`, `recipient`, `required`).
- **Logic**:
  1. Requires `_routers[msg.sender]`.
  2. Iterates `payoutUpdates`:
     - `payoutType=0`: Creates `LongPayoutStruct`, updates `_longPayouts`, `_longPayoutsByIndex`, `_userPayoutIDs`.
     - `payoutType=1`: Creates `ShortPayoutStruct`, updates `_shortPayouts`, `_shortPayoutsByIndex`, `_userPayoutIDs`.
  3. Emits `PayoutOrderCreated`, increments `_nextOrderId`.
- **State Changes**: `_longPayouts`, `_shortPayouts`, `_longPayoutsByIndex`, `_shortPayoutsByIndex`, `_userPayoutIDs`, `_nextOrderId`.
- **External Interactions**: None.
- **Internal Call Tree**: None.
- **Errors**: Reverts if `!_routers[msg.sender]`.
- **Gas**: Scales with `payoutUpdates.length`.

#### transactToken(address token, uint256 amount, address recipient)
- **Purpose**: Transfers `_tokenA` or `_tokenB`, updates volumes and price.
- **Inputs**: `token` (`_tokenA` or `_tokenB`), `amount`, `recipient`.
- **Logic**:
  1. Requires `_routers[msg.sender]`, valid `token`.
  2. Normalizes `amount` to 1e18 via `normalize`.
  3. Updates `_volumeBalance.xBalance`, `xVolume` (if `_tokenA`) or `yBalance`, `yVolume` (if `_tokenB`).
  4. Updates `_currentPrice` using `IERC20.balanceOf(_uniswapV2Pair)` for `_tokenA`, `_tokenB`.
  5. Transfers via `IERC20.transfer`, emits `BalancesUpdated`.
- **State Changes**: `_volumeBalance`, `_currentPrice`.
- **External Interactions**:
  - `IERC20.balanceOf` for `_tokenA`, `_tokenB` in `_uniswapV2Pair`.
  - `IERC20.transfer` for `token`.
- **Internal Call Tree**:
  - `normalize`: Normalizes `amount` to 1e18.
- **Errors**: Reverts for invalid router, token, or transfer failure (emits `TransactionFailed`, `ExternalCallFailed`).
- **Gas**: Minimal, with two `balanceOf` and one `transfer` call.

#### transactNative(uint256 amount, address recipient)
- **Purpose**: Transfers ETH, updates volumes and price.
- **Inputs**: `amount`, `recipient`.
- **Logic**:
  1. Requires `_routers[msg.sender]`, `_tokenA` or `_tokenB` as `address(0)`.
  2. Normalizes `amount` to 1e18 via `normalize`.
  3. Updates `_volumeBalance.xBalance`, `xVolume` (if `_tokenA==address(0)`) or `yBalance`, `yVolume` (if `_tokenB==address(0)`).
  4. Updates `_currentPrice` using `IERC20.balanceOf(_uniswapV2Pair)` for `_tokenA`, `_tokenB`.
  5. Transfers ETH via low-level `call`, emits `BalancesUpdated`.
- **State Changes**: `_volumeBalance`, `_currentPrice`.
- **External Interactions**:
  - `IERC20.balanceOf` for `_tokenA`, `_tokenB` in `_uniswapV2Pair`.
  - Low-level `call` for ETH transfer.
- **Internal Call Tree**:
  - `normalize`: Normalizes `amount` to 1e18.
- **Errors**: Reverts for invalid router, no native token, or transfer failure (emits `TransactionFailed`).
- **Gas**: Minimal, with two `balanceOf` and one `call`.

### Internal Functions
#### normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)
- **Purpose**: Normalizes amounts to 1e18 precision.
- **Callers**: `transactToken`, `transactNative`, `update`, `prices`.
- **Logic**: Adjusts `amount` based on `decimals` (multiply if `<18`, divide if `>18`).
- **Gas**: Minimal, pure arithmetic.

#### denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)
- **Purpose**: Converts from 1e18 to token decimals.
- **Callers**: Not used in v0.1.10.
- **Logic**: Inverse of `normalize`.
- **Gas**: Minimal, pure arithmetic.

#### _isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)
- **Purpose**: Checks if two timestamps are on the same day.
- **Callers**: `update` (for `_lastDayFee.timestamp` check).
- **Logic**: Compares `time1/86400 == time2/86400`.
- **Gas**: Minimal, pure arithmetic.

#### _floorToMidnight(uint256 timestamp) returns (uint256 midnight)
- **Purpose**: Rounds timestamp to midnight.
- **Callers**: `update` (for `_lastDayFee.timestamp`).
- **Logic**: Returns `(timestamp / 86400) * 86400`.
- **Gas**: Minimal, pure arithmetic.

#### _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)
- **Purpose**: Calculates volume change since `startTime` for `_volumeBalance.xVolume` or `yVolume`.
- **Callers**: Not used in v0.1.10.
- **Logic**: Compares current volume to historical data, limited by `maxIterations`.
- **Gas**: Scales with `_historicalData.length`, capped by `maxIterations`.

#### _updateRegistry(address maker)
- **Purpose**: Updates `ITokenRegistry` with balances for `maker`.
- **Callers**: `update`.
- **Logic**: Calls `ITokenRegistry.initializeTokens` with `_tokenA`, `_tokenB`, emits `UpdateRegistryFailed`, `ExternalCallFailed` on failure.
- **External Interactions**: `ITokenRegistry.initializeTokens`.
- **Errors**: Graceful degradation via try-catch.
- **Gas**: Depends on `ITokenRegistry` implementation.

#### removePendingOrder(uint256[] storage orders, uint256 orderId)
- **Purpose**: Removes `orderId` from `_pendingBuyOrders`, `_pendingSellOrders`, or `_makerPendingOrders`.
- **Callers**: `update`.
- **Logic**: Swaps `orderId` with the last element and pops the array.
- **Gas**: Scales with array length.

#### globalizeUpdate()
- **Purpose**: Updates `ICCGlobalizer` with latest order details.
- **Callers**: `update`.
- **Logic**: Calls `ICCGlobalizer.globalizeOrders` with latest maker and token (`_tokenB` for buy, `_tokenA` for sell), emits `ExternalCallFailed` on failure.
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
- **Price**: Computed as `reserveB * 1e18 / reserveA` using `IERC20.balanceOf(_uniswapV2Pair)` for `_tokenA`, `_tokenB`, normalized via `normalize`. Stored in `_currentPrice`, updated in `update`, `transactToken`, `transactNative`.
- **Registry**: Updated via `_updateRegistry` in `update`, calling `ITokenRegistry.initializeTokens` with `_tokenA`, `_tokenB`.
- **Globalizer**: Updated via `globalizeUpdate` in `update`, calling `ICCGlobalizer.globalizeOrders` with latest maker and token (`_tokenB` for buy, `_tokenA` for sell).
- **Liquidity**: `ICCLiquidityTemplate.liquidityDetail` fetches fees for `_lastDayFee` updates in `update`.
- **External Calls**:
  - `IERC20.balanceOf` in `transactToken`, `transactNative`, `update`, `prices`.
  - `IERC20.transfer` in `transactToken`.
  - `IERC20.decimals` in `setTokens`.
  - `ITokenRegistry.initializeTokens` in `_updateRegistry`.
  - `ICCLiquidityTemplate.liquidityDetail` in `update`.
  - `ICCGlobalizer.globalizeOrders` in `globalizeUpdate`.
  - Low-level `call` in `transactNative`.
- **Security**: Router checks, try-catch on external calls, explicit casting, no tuple access.
- **Optimization**: Normalized amounts, `maxIterations` for gas control.
