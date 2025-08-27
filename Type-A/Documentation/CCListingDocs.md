# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract, written in Solidity (^0.8.2), facilitates decentralized trading for a token pair, integrating with Uniswap V2 for price discovery using `IERC20.balanceOf` for token balances at the pair address. It manages buy/sell orders, long/short payouts, and tracks normalized (1e18 precision) balances. Volume is captured in `_historicalData` during order settlement or cancellation, with historical data auto-generated if not provided by the router. Licensed under BSL 1.1 - Peng Protocol 2025, it ensures secure, modular design with explicit casting, no inline assembly, and graceful degradation for external calls.

## Version
- **0.2.11**
- **Changes**:
  - v0.2.11: Fixed shadowed declaration in `_updateRegistry` by renaming `tokens` to `emptyTokens`. Commented out unused `xLiq` and `yLiq` in `update` try/catch to eliminate warnings. Added `TransactionFailed` event to fix undeclared identifier errors in `transactToken` and `transactNative`. Removed validation in `update()` to treat router data as correct. Removed gas limit on `initializeTokens` in `_updateRegistry`. Added `RegistryUpdateFailed` event for registry-specific errors. Ensured maker address validation before registry call. Compatible with `CCOrderPartial.sol` (v0.1.0), `CCOrderRouter.sol` (v0.1.0), `CCLiquidityTemplate.sol` (v0.1.3), `CCMainPartial.sol` (v0.0.14), `CCLiquidityPartial.sol` (v0.0.27), `CCUniPartial.sol` (v0.1.0), `TokenRegistry.sol` (2025-08-04).
  - v0.2.10: Added auto-generation of historical data in `update()` when `updateType=3` is not provided, using current Uniswap V2 pair price and carrying forward previous volumes. Updated historical volume (`xVolume`, `yVolume`) in `update()` for buy/sell orders on cancellation (`status=0`) or settlement (`status=3`), accumulating `filled` and `amountSent` (normalized). Compatible with `CCOrderPartial.sol` (v0.1.0), `CCOrderRouter.sol` (v0.1.0), `CCLiquidityTemplate.sol` (v0.1.3), `CCMainPartial.sol` (v0.0.14), `CCLiquidityPartial.sol` (v0.0.27), `CCUniPartial.sol` (v0.1.0), `TokenRegistry.sol` (2025-08-04).
  - v0.2.9: Named mapping and array input parameters for clarity and Etherscan visibility (e.g., `orderId`, `maker`, `timestamp`). Confirmed `dayStartFee` and historical data population in `update()` for `updateType=3`, no updates in `transactToken`/`transactNative` as they only handle transfers. Cleared changelog entries older than v0.2.8. Compatible with `CCOrderPartial.sol` (v0.1.0), `CCOrderRouter.sol` (v0.1.0), `CCLiquidityTemplate.sol` (v0.1.3), `CCMainPartial.sol` (v0.0.14), `CCLiquidityPartial.sol` (v0.0.27), `CCUniPartial.sol` (v0.1.0), `TokenRegistry.sol` (2025-08-04).
  - v0.2.8: Initialized `dayStartFee` and historical data in `setTokens` to ensure data availability without router updates. Updated `volumeBalances` to fetch real-time token balances from contract. Fixed pending amount validation in `update()` to set `pending` for new orders. Made `_registryAddress` public as `registryAddress`. Added registry call validation in `_updateRegistry`. Compatible with `CCOrderPartial.sol` (v0.1.0), `CCOrderRouter.sol` (v0.1.0), `CCLiquidityTemplate.sol` (v0.1.3), `CCMainPartial.sol` (v0.0.14), `CCLiquidityPartial.sol` (v0.0.27), `CCUniPartial.sol` (v0.1.0), `TokenRegistry.sol` (2025-08-04).

- **Compatibility**: Compatible with `CCLiquidityTemplate.sol` (v0.1.3), `CCMainPartial.sol` (v0.0.14), `CCLiquidityPartial.sol` (v0.0.27), `ICCLiquidity.sol` (v0.0.5), `ICCListing.sol` (v0.0.7), `CCOrderRouter.sol` (v0.1.0), `TokenRegistry.sol` (2025-08-04), `CCUniPartial.sol` (v0.1.0), `CCOrderPartial.sol` (v0.1.0).

## Interfaces
- **IERC20**: Provides `decimals()`, `transfer(address, uint256)`, `balanceOf(address)` for token precision, transfers, and balance queries.
- **ICCListing**: Exposes view functions (`prices`, `volumeBalances`, `liquidityAddressView`, `tokenA`, `tokenB`, `decimalsA`, `decimalsB`).
- **IUniswapV2Pair**: Provides `token0`, `token1` for pair token mapping.
- **ICCLiquidityTemplate**: Provides `liquidityDetail` for fee data.
- **ITokenRegistry**: Defines `initializeTokens(address user, address[] memory tokens)`.
- **ICCGlobalizer**: Defines `globalizeOrders(address maker, address token)`.

## Structs
- **PayoutUpdate**: Defines `payoutType` (0: Long, 1: Short), `recipient`, `required`.
- **DayStartFee**: Tracks `dayStartXFeesAcc`, `dayStartYFeesAcc`, `timestamp`.
- **Balance**: Stores `xBalance`, `yBalance` (normalized, 1e18).
- **HistoricalData**: Records `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`.
- **BuyOrderCore**: Stores `makerAddress`, `recipientAddress`, `status` (0: cancelled, 1: pending, 2: partially filled, 3: filled).
- **BuyOrderPricing**: Stores `maxPrice`, `minPrice` (1e18).
- **BuyOrderAmounts**: Tracks `pending` (tokenB), `filled` (tokenB), `amountSent` (tokenA).
- **SellOrderCore**, **SellOrderPricing**, **SellOrderAmounts**: Similar, with `pending` (tokenA), `amountSent` (tokenB).
- **LongPayoutStruct**: Tracks `makerAddress`, `recipientAddress`, `required` (tokenB), `filled`, `orderId`, `status`.
- **ShortPayoutStruct**: Tracks `makerAddress`, `recipientAddress`, `amount` (tokenA), `filled`, `orderId`, `status`.
- **UpdateType**: Defines `updateType` (0: balance, 1: buy order, 2: sell order, 3: historical), `structId`, `index`, `value`, `addr`, `recipient`, `maxPrice`, `minPrice`, `amountSent`.
- **OrderStatus**: Tracks `hasCore`, `hasPricing`, `hasAmounts` for order completeness.

## Fee Segregation
The `_balance` struct (`xBalance`, `yBalance`) segregates fees from pending orders by tracking tokens received from the order router during order creation and settlement, excluding fees managed by `ICCLiquidityTemplate`. On buy order creation (`updateType=1`, `structId=2`), `u.value` (tokenB) adds to `yBalance`; on sell order creation (`updateType=2`, `structId=2`), `u.value` (tokenA) adds to `xBalance`. During settlement, buy orders add `u.amountSent` (tokenA) to `xBalance`, subtract `u.value` (tokenB) from `yBalance`; sell orders subtract `u.value` (tokenA) from `xBalance`, add `u.amountSent` (tokenB) to `yBalance`. Fees are fetched via `ICCLiquidityTemplate.liquidityDetail` and stored in `dayStartFee` for `yieldAnnualizedView`.

## State Variables
- `_routers`: `mapping(address => bool)` - Authorized routers.
- `_routersSet`: `bool` - Locks router settings.
- `tokenA`, `tokenB`: `address` - Token pair (ETH as `address(0)`).
- `decimalsA`, `decimalsB`: `uint8` - Token decimals.
- `uniswapV2PairView`, `_uniswapV2PairSet`: `address`, `bool` - Uniswap V2 pair.
- `getListingId`: `uint256` - Listing identifier.
- `agentView`: `address` - Agent address.
- `registryAddress`: `address` - Registry address (public since v0.2.8).
- `liquidityAddressView`: `address` - Liquidity contract address.
- `_globalizerAddress`, `_globalizerSet`: `address`, `bool` - Globalizer contract.
- `getNextOrderId`: `uint256` - Order ID counter.
- `dayStartFee`: `DayStartFee` - Daily fee tracking.
- `_balance`: `Balance` - Normalized balances.
- `listingPriceView`: `uint256` - Current price (tokenB/tokenA, 1e18).
- `pendingBuyOrdersView`, `pendingSellOrdersView`: `uint256[]` - Pending order IDs.
- `longPayoutByIndexView`, `shortPayoutByIndexView`: `uint256[]` - Payout IDs.
- `makerPendingOrdersView`: `mapping(address => uint256[])` - Maker order IDs.
- `userPayoutIDsView`: `mapping(address => uint256[])` - User payout IDs.
- `_historicalData`: `HistoricalData[]` - Price and volume history.
- `_dayStartIndices`: `mapping(uint256 => uint256)` - Maps midnight timestamps to historical data indices.
- `getBuyOrderCore`, `getBuyOrderPricing`, `getBuyOrderAmounts`: `mapping(uint256 => ...)` - Buy order data.
- `getSellOrderCore`, `getSellOrderPricing`, `getSellOrderAmounts`: `mapping(uint256 => ...)` - Sell order data.
- `getLongPayout`, `getShortPayout`: `mapping(uint256 => ...)` - Payout data.
- `orderStatus`: `mapping(uint256 => OrderStatus)` - Tracks order completeness.

## Functions
### External Functions
#### setGlobalizerAddress(address globalizerAddress_)
- **Purpose**: Sets `_globalizerAddress`.
- **Inputs**: `globalizerAddress_` (non-zero).
- **Logic**: Sets `_globalizerAddress`, `_globalizerSet=true`, emits `GlobalizerAddressSet`.
- **State Changes**: `_globalizerAddress`, `_globalizerSet`.
- **Errors**: Reverts if `_globalizerSet` or `globalizerAddress_ == address(0)`.
- **Call Tree**: None.

#### setUniswapV2Pair(address _uniswapV2Pair)
- **Purpose**: Sets `uniswapV2PairView`.
- **Inputs**: `_uniswapV2Pair` (non-zero).
- **Logic**: Sets `uniswapV2PairView`, `_uniswapV2PairSet=true`.
- **State Changes**: `uniswapV2PairView`, `_uniswapV2PairSet`.
- **Errors**: Reverts if `_uniswapV2PairSet` or `_uniswapV2Pair == address(0)`.
- **Call Tree**: None.

#### setRouters(address[] memory routers_)
- **Purpose**: Authorizes routers.
- **Inputs**: `routers_` (non-empty, non-zero addresses).
- **Logic**: Sets `_routers[router]=true`, `_routersSet=true`.
- **State Changes**: `_routers`, `_routersSet`.
- **Errors**: Reverts if `_routersSet`, `routers_.length == 0`, or any `routers_[i] == address(0)`.
- **Call Tree**: None.

#### setListingId(uint256 _listingId)
- **Purpose**: Sets `getListingId`.
- **Inputs**: `_listingId`.
- **Logic**: Sets `getListingId`.
- **State Changes**: `getListingId`.
- **Errors**: Reverts if `getListingId != 0`.
- **Call Tree**: None.

#### setLiquidityAddress(address _liquidityAddress)
- **Purpose**: Sets `liquidityAddressView`.
- **Inputs**: `_liquidityAddress` (non-zero).
- **Logic**: Sets `liquidityAddressView`.
- **State Changes**: `liquidityAddressView`.
- **Errors**: Reverts if `liquidityAddressView != address(0)` or `_liquidityAddress == address(0)`.
- **Call Tree**: None.

#### setTokens(address _tokenA, address _tokenB)
- **Purpose**: Sets `tokenA`, `tokenB`, initializes `decimalsA`, `decimalsB`, `_historicalData`, `dayStartFee`.
- **Inputs**: `_tokenA`, `_tokenB` (distinct, at least one non-zero).
- **Logic**: Sets tokens, fetches decimals, initializes `_historicalData` with zeroed entry, sets `dayStartFee` with midnight timestamp.
- **State Changes**: `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `_historicalData`, `_dayStartIndices`, `dayStartFee`.
- **External Interactions**: `IERC20.decimals`.
- **Internal Call Tree**: `_floorToMidnight`.
- **Errors**: Reverts if tokens already set, `_tokenA == _tokenB`, or both are `address(0)`.

#### setAgent(address _agent)
- **Purpose**: Sets `agentView`.
- **Inputs**: `_agent` (non-zero).
- **Logic**: Sets `agentView`.
- **State Changes**: `agentView`.
- **Errors**: Reverts if `agentView != address(0)` or `_agent == address(0)`.
- **Call Tree**: None.

#### setRegistry(address registryAddress_)
- **Purpose**: Sets `registryAddress`.
- **Inputs**: `registryAddress_` (non-zero).
- **Logic**: Sets `registryAddress`.
- **State Changes**: `registryAddress`.
- **Errors**: Reverts if `registryAddress != address(0)` or `registryAddress_ == address(0)`.
- **Call Tree**: None.

#### ssUpdate(PayoutUpdate[] calldata updates)
- **Purpose**: Processes long/short payouts.
- **Inputs**: `updates` array (`payoutType`, `recipient`, `required`).
- **Logic**: Validates router, `recipient`, `payoutType`, `required`. Creates `LongPayoutStruct` or `ShortPayoutStruct`, updates `longPayoutByIndexView`, `shortPayoutByIndexView`, `userPayoutIDsView`, increments `getNextOrderId`. Emits `PayoutOrderCreated`.
- **State Changes**: `getLongPayout`, `getShortPayout`, `longPayoutByIndexView`, `shortPayoutByIndexView`, `userPayoutIDsView`, `getNextOrderId`.
- **Internal Call Tree**: None.
- **Errors**: Emits `UpdateFailed` for invalid `recipient`, `payoutType`, `required`.

#### update(UpdateType[] memory updates)
- **Purpose**: Updates balances, orders, or historical data.
- **Inputs**: `updates` array (`updateType`, `structId`, `index`, `value`, `addr`, `recipient`, `maxPrice`, `minPrice`, `amountSent`).
- **Logic**: For `updateType=0`: updates `_balance`. For `updateType=1` or `2`: updates buy/sell order structs (`Core`, `Pricing`, `Amounts`), manages `pendingBuyOrdersView`, `pendingSellOrdersView`, `makerPendingOrdersView`, updates `xVolume`, `yVolume` on cancellation/settlement. For `updateType=3`: adds to `_historicalData`, updates `dayStartFee`, `_dayStartIndices`. Auto-generates `_historicalData` entry if none provided and not same-day, using Uniswap V2 price. Calls `globalizeUpdate`, updates price via `IUniswapV2Pair`.
- **State Changes**: `_balance`, `getBuyOrderCore`, `getBuyOrderPricing`, `getBuyOrderAmounts`, `getSellOrderCore`, `getSellOrderPricing`, `getSellOrderAmounts`, `pendingBuyOrdersView`, `pendingSellOrdersView`, `makerPendingOrdersView`, `_historicalData`, `_dayStartIndices`, `dayStartFee`, `listingPriceView`, `getNextOrderId`, `orderStatus`.
- **External Interactions**: `IUniswapV2Pair.token0`, `IERC20.balanceOf`, `ITokenRegistry.initializeTokens`, `ICCLiquidityTemplate.liquidityDetail`, `ICCGlobalizer.globalizeOrders`.
- **Internal Call Tree**: `_updateRegistry`, `globalizeUpdate`, `removePendingOrder`, `normalize`, `_floorToMidnight`, `_isSameDay`.
- **Errors**: Emits `UpdateFailed`, `ExternalCallFailed`, `OrderUpdateIncomplete` for invalid inputs or failed calls.

#### transactToken(address token, uint256 amount, address recipient)
- **Purpose**: Transfers `tokenA` or `tokenB`.
- **Inputs**: `token`, `amount`, `recipient`.
- **Logic**: Checks router, valid token, non-zero `amount`, `recipient`. Transfers via `IERC20.transfer`, checks post-balance, emits `TransactionFailed` on failure.
- **State Changes**: None.
- **External Interactions**: `IERC20.balanceOf`, `IERC20.transfer`.
- **Internal Call Tree**: `normalize`.
- **Errors**: Reverts for invalid router, token, `amount`, `recipient`. Emits `TransactionFailed`.

#### transactNative(uint256 amount, address recipient)
- **Purpose**: Transfers ETH.
- **Inputs**: `amount`, `recipient`.
- **Logic**: Checks router, native token support, non-zero `amount`, `recipient`, `msg.value==amount`. Transfers via low-level `call`, checks post-balance, emits `TransactionFailed` on failure.
- **State Changes**: None.
- **External Interactions**: Low-level `call`.
- **Internal Call Tree**: None.
- **Errors**: Reverts for invalid router, no native token, `amount`, `recipient`, or `msg.value`. Emits `TransactionFailed`.

#### yieldAnnualizedView(bool isTokenA, uint256 depositAmount) returns (uint256 yieldAnnualized)
- **Purpose**: Calculates annualized yield from liquidity fees.
- **Inputs**: `isTokenA`, `depositAmount`.
- **Logic**: Fetches fees via `ICCLiquidityTemplate.liquidityDetail`, uses `dayStartFee` to compute daily fees, calculates yield (`dailyFees * 365 * 10000 / depositAmount`).
- **External Interactions**: `ICCLiquidityTemplate.liquidityDetail`.
- **Internal Call Tree**: `_isSameDay`.
- **Errors**: Returns 0 if `liquidityAddressView==address(0)`, `depositAmount==0`, or call fails.

#### queryDurationVolume(bool isA, uint256 durationDays, uint256 maxIterations) returns (uint256 volume)
- **Purpose**: Sums volume over `durationDays` for `tokenA` or `tokenB`.
- **Inputs**: `isA`, `durationDays` (>0), `maxIterations` (>0).
- **Logic**: Sums `xVolume` or `yVolume` from `_historicalData` within `durationDays`, capped by `maxIterations`.
- **Internal Call Tree**: `_floorToMidnight`.
- **Errors**: Reverts if `durationDays==0` or `maxIterations==0`. Returns 0 if `_historicalData` empty.

#### getLastDays(uint256 count, uint256 maxIterations) returns (uint256[] memory indices, uint256[] memory timestamps)
- **Purpose**: Returns day boundary indices, timestamps from `_dayStartIndices`.
- **Inputs**: `count`, `maxIterations` (>0).
- **Logic**: Collects indices, timestamps for up to `count` days, capped by `maxIterations`.
- **Internal Call Tree**: `_floorToMidnight`.
- **Errors**: Reverts if `maxIterations==0`.

#### getTokens() returns (address tokenA_, address tokenB_)
- **Purpose**: Returns `tokenA`, `tokenB`.
- **Logic**: Returns token pair, reverts if both unset.
- **State Changes**: None.
- **Errors**: Reverts if `tokenA` and `tokenB` are both `address(0)`.

#### prices(uint256) returns (uint256 price)
- **Purpose**: Computes current price from Uniswap V2 pair balances.
- **Logic**: Fetches `IERC20.balanceOf(uniswapV2PairView)`, normalizes, computes `price = (balanceB * 1e18) / balanceA`.
- **External Interactions**: `IERC20.balanceOf`.
- **Internal Call Tree**: `normalize`.
- **Errors**: Returns `listingPriceView` if call fails.

#### volumeBalances(uint256) returns (uint256 xBalance, uint256 yBalance)
- **Purpose**: Returns real-time normalized contract balances.
- **Logic**: Fetches `IERC20.balanceOf(address(this))` or ETH balance, normalizes.
- **External Interactions**: `IERC20.balanceOf`.
- **Internal Call Tree**: `normalize`.

#### listingVolumeBalancesView() returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume)
- **Purpose**: Returns balances and latest volumes.
- **Logic**: Calls `this.volumeBalances`, fetches `xVolume`, `yVolume` from `_historicalData`.
- **Internal Call Tree**: `volumeBalances`.

#### makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns pending buy order IDs for `maker`, starting from `step`.
- **Logic**: Filters `makerPendingOrdersView[maker]` for `status=1`, capped by `maxIterations`.
- **Internal Call Tree**: None.

#### makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns pending sell order IDs for `maker`, starting from `step`.
- **Logic**: Filters `makerPendingOrdersView[maker]` for `status=1`, capped by `maxIterations`.
- **Internal Call Tree**: None.

#### getFullBuyOrderDetails(uint256 orderId) returns (BuyOrderCore, BuyOrderPricing, BuyOrderAmounts)
- **Purpose**: Returns full buy order details.
- **Logic**: Returns `getBuyOrderCore`, `getBuyOrderPricing`, `getBuyOrderAmounts` for `orderId`.
- **Internal Call Tree**: None.

#### getFullSellOrderDetails(uint256 orderId) returns (SellOrderCore, SellOrderPricing, SellOrderAmounts)
- **Purpose**: Returns full sell order details.
- **Logic**: Returns `getSellOrderCore`, `getSellOrderPricing`, `getSellOrderAmounts` for `orderId`.
- **Internal Call Tree**: None.

#### makerOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns up to `maxIterations` order IDs for `maker`, starting from `step`.
- **Logic**: Slices `makerPendingOrdersView[maker]` from `step`.
- **Internal Call Tree**: None.

#### getHistoricalDataView(uint256 index) returns (HistoricalData)
- **Purpose**: Returns `_historicalData[index]`.
- **Logic**: Returns data, reverts if `index` invalid.
- **Errors**: Reverts if `index >= _historicalData.length`.

#### historicalDataLengthView() returns (uint256)
- **Purpose**: Returns `_historicalData.length`.
- **Logic**: Returns length.
- **Internal Call Tree**: None.

#### getHistoricalDataByNearestTimestamp(uint256 targetTimestamp) returns (HistoricalData)
- **Purpose**: Returns `_historicalData` entry closest to `targetTimestamp`.
- **Logic**: Finds entry with minimum timestamp difference.
- **Internal Call Tree**: None.

#### globalizerAddressView() returns (address)
- **Purpose**: Returns `_globalizerAddress`.
- **Logic**: Returns `_globalizerAddress`.
- **Internal Call Tree**: None.

### Internal Functions
#### normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)
- **Purpose**: Normalizes amounts to 1e18.
- **Callers**: `transactToken`, `update`, `prices`, `volumeBalances`.

#### denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)
- **Purpose**: Converts from 1e18 to token decimals.
- **Callers**: None in v0.2.11.

#### _isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)
- **Purpose**: Checks same-day timestamps.
- **Callers**: `update`, `yieldAnnualizedView`.

#### _floorToMidnight(uint256 timestamp) returns (uint256 midnight)
- **Purpose**: Rounds timestamp to midnight.
- **Callers**: `setTokens`, `update`, `queryDurationVolume`, `getLastDays`.

#### _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)
- **Purpose**: Returns volume from `_historicalData` at or after `startTime`.
- **Callers**: None in v0.2.11.

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
- **Errors**: Emits `ExternalCallFailed`, `UpdateFailed`.

#### uint2str(uint256 _i) returns (string)
- **Purpose**: Converts uint to string for error messages.
- **Callers**: None in v0.2.11.

## Parameters and Interactions
- **Orders** (`UpdateType`): `updateType=0` updates `_balance`. Buy orders (`updateType=1`) input `tokenB` (`value`), output `tokenA` (`amountSent`); sell orders (`updateType=2`) input `tokenA` (`value`), output `tokenB` (`amountSent`). On creation, buy orders add `value` to `yBalance`, sell orders add `value` to `xBalance`. On settlement, buy orders add `amountSent` to `xBalance`, subtract `value` from `yBalance`; sell orders subtract `value` from `xBalance`, add `amountSent` to `yBalance`. On cancellation (`status=0`) or settlement (`status=3`), buy orders update `_historicalData` with `xVolume += normalize(amountSent, decimalsA)`; sell orders update `yVolume += normalize(amountSent, decimalsB)`. Order completeness tracked via `orderStatus`, emitting `OrderUpdatesComplete` or `OrderUpdateIncomplete`.
- **Payouts** (`PayoutUpdate`): Long (`payoutType=0`, `tokenB`), short (`payoutType=1`, `tokenA`) via `ssUpdate`, using `getNextOrderId` for indexing.
- **Price**: Computed via `IUniswapV2Pair` and `IERC20.balanceOf(uniswapV2PairView)`, stored in `listingPriceView` after balance updates.
- **Registry**: Updated via `_updateRegistry` in `update`.
- **Globalizer**: Updated via `globalizeUpdate` in `update`.
- **Liquidity**: `ICCLiquidityTemplate.liquidityDetail` used in `update`, `yieldAnnualizedView`.
- **Historical Data**: Stored in `_historicalData` during `update` (`updateType=3`) or auto-generated if not provided and not same-day, using Uniswap V2 price and carrying forward previous volumes. Volumes updated on order cancellation/settlement.
- **External Calls**: `IERC20.balanceOf`, `IERC20.transfer`, `IERC20.decimals`, `ITokenRegistry.initializeTokens`, `ICCLiquidityTemplate.liquidityDetail`, `ICCGlobalizer.globalizeOrders`, low-level `call`.
- **Security**: Router checks, try-catch, explicit casting, no tuple access, relaxed validation, skips invalid updates with `UpdateFailed`.
- **Optimization**: Normalized amounts, `maxIterations`, auto-generated historical data, generated balance updates.
