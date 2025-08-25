# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract, written in Solidity (^0.8.2), facilitates decentralized trading for a token pair, integrating with Uniswap V2 for price discovery using `IERC20.balanceOf` for token balances at the pair address. It manages buy/sell orders, long/short payouts, and tracks normalized (1e18 precision) balances. Volume is captured in `_historicalData` during order settlement, with historical data updated post-settlement. Licensed under BSL 1.1 - Peng Protocol 2025, it ensures secure, modular design with explicit casting, no inline assembly, and graceful degradation for external calls.

## Version
- **0.2.7**
- **Changes**:
  - v0.2.7: Fixed TypeError in `update()` by replacing dynamic `mapping(uint256 => bool) storage updatedOrders` with `uint256[] memory updatedOrders` array to track updated order IDs. Fixed TypeError in `ssUpdate` by correcting `payout.amount = u.recipient` to `payout.amount = u.required`. Maintained all existing functionality and compatibility with `CCOrderPartial.sol` (v0.1.0).
  - v0.2.6: Modified `update()` to track order completeness across calls using `OrderStatus` struct and `orderStatus` mapping. Emits `OrderUpdateIncomplete` only if an order remains incomplete after all updates in a call (missing Core, Pricing, or Amounts). Added `OrderUpdatesComplete` event when all structs are set. Maintains graceful degradation. Compatible with `CCOrderPartial.sol` (v0.1.0).
  - v0.2.5: Relaxed address validation in `update()` to only check maker and recipient for Core struct (`structId=0`). Added `OrderUpdateIncomplete` event for partial updates. Maintained graceful degradation by skipping invalid updates instead of reverting. Ensured compatibility with `CCOrderPartial.sol` (v0.1.0).
  - v0.2.4: Fixed `ssUpdate` to resolve TypeError by removing invalid `u.orderId` reference. Used `getNextOrderId` for new payout orders, incrementing it after creation to align with regular order indexing. Validated payouts using recipient and required amount. Ensured no changes to `PayoutUpdate` struct for upstream compatibility. Compatible with `CCOrderRouter.sol` (v0.1.0), `CCOrderPartial.sol` (v0.1.0).
  - v0.2.3: Relaxed order ID validation in `update()` to allow `index == getNextOrderId` for new orders, ensuring new order IDs align with the next available slot. Incremented `getNextOrderId` after successful order creation to prevent reuse. Compatible with `CCOrderRouter.sol` (v0.1.0), `CCOrderPartial.sol` (v0.1.0).
  - v0.2.2: Enhanced `update()` for graceful degradation. Skips invalid updates instead of reverting, emits `UpdateFailed` with detailed reasons for edge cases (zero amounts, invalid order IDs, underflow). Added checks for maker and token validity before registry/globalizer calls. Compatible with `CCUniPartial.sol` (v0.1.0), `CCOrderPartial.sol` (v0.1.0), `CCLiquidPartial.sol` (v0.0.27), `CCMainPartial.sol` (v0.0.14), `CCLiquidityTemplate.sol` (v0.1.3), `CCOrderRouter.sol` (v0.0.11), `TokenRegistry.sol` (2025-08-04).
  - v0.2.1: Updated `update()` to handle balance deductions for sell orders (`xBalance -= u.value`, `yBalance += u.amountSent`) and additions for buy orders. Relaxed pending amount validation to avoid precision reverts. Added exchange rate recalculation after balance updates. Generates balance updates if not provided by router, ignores redundant updates from `CCUniPartial`. Compatible with `CCUniPartial.sol` (v0.1.0), `CCOrderPartial.sol` (v0.1.0).
  - v0.2.0: Bumped version.
- **Compatibility**: Compatible with `CCLiquidityTemplate.sol` (v0.1.3), `CCMainPartial.sol` (v0.0.14), `CCLiquidPartial.sol` (v0.0.27), `ICCLiquidity.sol` (v0.0.5), `ICCListing.sol` (v0.0.7), `CCOrderRouter.sol` (v0.1.0), `TokenRegistry.sol` (2025-08-04), `CCUniPartial.sol` (v0.1.0), `CCOrderPartial.sol` (v0.1.0).

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
- `_registryAddress`: `address` - Registry address.
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
- **Purpose**: Sets `tokenA`, `tokenB`, `decimalsA`, `decimalsB`.
- **Inputs**: `_tokenA`, `_tokenB` (different, at least one non-zero).
- **Logic**: Sets tokens, fetches decimals via `IERC20.decimals`.
- **State Changes**: `tokenA`, `tokenB`, `decimalsA`, `decimalsB`.
- **External Interactions**: `IERC20.decimals`.
- **Errors**: Reverts if tokens set, identical, or both zero.
- **Call Tree**: None.

#### setAgent(address _agent)
- **Purpose**: Sets `agentView`.
- **Inputs**: `_agent` (non-zero).
- **Logic**: Sets `agentView`.
- **State Changes**: `agentView`.
- **Errors**: Reverts if `agentView != address(0)` or `_agent == address(0)`.
- **Call Tree**: None.

#### setRegistry(address _registryAddress)
- **Purpose**: Sets `_registryAddress`.
- **Inputs**: `_registryAddress` (non-zero).
- **Logic**: Sets `_registryAddress`.
- **State Changes**: `_registryAddress`.
- **Errors**: Reverts if `_registryAddress != address(0)` or `_registryAddress == address(0)`.
- **Call Tree**: None.

#### ssUpdate(PayoutUpdate[] calldata updates)
- **Purpose**: Creates long/short payout orders, using `getNextOrderId` for indexing.
- **Inputs**: `updates` (array of `payoutType`, `recipient`, `required`).
- **Logic**: For each update, checks router, valid `payoutType` (0 or 1), `recipient`, `required`. Creates `LongPayoutStruct` (tokenB) or `ShortPayoutStruct` (tokenA) with `getNextOrderId`, sets `makerAddress=recipient`, `amount/required=u.required`, `status` (3 if `required>0`, else 0), pushes to `longPayoutByIndexView` or `shortPayoutByIndexView`, `userPayoutIDsView`, increments `getNextOrderId`, emits `PayoutOrderCreated`.
- **State Changes**: `getLongPayout`, `getShortPayout`, `longPayoutByIndexView`, `shortPayoutByIndexView`, `userPayoutIDsView`, `getNextOrderId`.
- **Errors**: Emits `UpdateFailed` for invalid `recipient`, `payoutType`, or `required`.
- **Call Tree**: None.

#### update(UpdateType[] calldata updates)
- **Purpose**: Processes balance, buy/sell orders, historical data updates, and tracks order completeness.
- **Inputs**: `updates` (array of `updateType`, `structId`, `index`, `value`, `addr`, `recipient`, `maxPrice`, `minPrice`, `amountSent`).
- **Logic**: Checks router. For `updateType=0`: updates `_balance`. For `updateType=1` (buy) or `2` (sell): handles `Core` (`structId=0`, sets `makerAddress`, `recipientAddress`, `status`, removes cancelled orders), `Pricing` (`structId=1`, sets `maxPrice`, `minPrice`), `Amounts` (`structId=2`, updates `pending`, `amountSent`). Tracks updated orders in `updatedOrders` array, checks `orderStatus` for completeness, emits `OrderUpdatesComplete` if all structs set, else `OrderUpdateIncomplete`. For `updateType=3`: adds to `_historicalData`, updates `dayStartFee`, `_dayStartIndices`. Calls `globalizeUpdate`, updates price via `IUniswapV2Pair`.
- **State Changes**: `_balance`, `getBuyOrderCore`, `getBuyOrderPricing`, `getBuyOrderAmounts`, `getSellOrderCore`, `getSellOrderPricing`, `getSellOrderAmounts`, `pendingBuyOrdersView`, `pendingSellOrdersView`, `makerPendingOrdersView`, `_historicalData`, `_dayStartIndices`, `dayStartFee`, `listingPriceView`, `getNextOrderId`, `orderStatus`.
- **External Interactions**: `IUniswapV2Pair.token0`, `IERC20.balanceOf`, `ITokenRegistry.initializeTokens`, `ICCLiquidityTemplate.liquidityDetail`, `ICCGlobalizer.globalizeOrders`.
- **Internal Call Tree**: `_updateRegistry`, `globalizeUpdate`, `removePendingOrder`, `normalize`, `_floorToMidnight`, `_isSameDay`.
- **Errors**: Emits `UpdateFailed`, `ExternalCallFailed`, `OrderUpdateIncomplete` for invalid inputs or failed calls.

#### transactToken(address token, uint256 amount, address recipient)
- **Purpose**: Transfers `tokenA` or `tokenB`.
- **Inputs**: `token`, `amount`, `recipient`.
- **Logic**: Checks router, valid token, non-zero `amount`, `recipient`. Normalizes `amount`, transfers via `IERC20.transfer`, checks post-balance, emits `TransactionFailed` on failure.
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

#### yieldAnnualizedView(bool isTokenA, uint256 depositAmount)
- **Purpose**: Calculates annualized yield from liquidity fees.
- **Inputs**: `isTokenA`, `depositAmount`.
- **Logic**: Fetches fees via `ICCLiquidityTemplate.liquidityDetail`, uses `dayStartFee` to compute daily fees, calculates yield (`dailyFees * 365 * 10000 / depositAmount`).
- **External Interactions**: `ICCLiquidityTemplate.liquidityDetail`.
- **Internal Call Tree**: `_isSameDay`.
- **Errors**: Returns 0 if `liquidityAddressView==address(0)`, `depositAmount==0`, or call fails.

#### queryDurationVolume(bool isA, uint256 durationDays, uint256 maxIterations)
- **Purpose**: Sums volume over `durationDays` for `tokenA` or `tokenB`.
- **Inputs**: `isA`, `durationDays` (>0), `maxIterations` (>0).
- **Logic**: Sums `xVolume` or `yVolume` from `_historicalData` within `durationDays`, capped by `maxIterations`.
- **Internal Call Tree**: `_floorToMidnight`.
- **Errors**: Reverts if `durationDays==0` or `maxIterations==0`. Returns 0 if `_historicalData` empty.

#### getLastDays(uint256 count, uint256 maxIterations)
- **Purpose**: Returns day boundary indices, timestamps from `_dayStartIndices`.
- **Inputs**: `count`, `maxIterations` (>0).
- **Logic**: Collects indices, timestamps for up to `count` days, capped by `maxIterations`.
- **Internal Call Tree**: `_floorToMidnight`.
- **Errors**: Reverts if `maxIterations==0`.

### Internal Functions
#### normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)
- **Purpose**: Normalizes amounts to 1e18.
- **Callers**: `transactToken`, `transactNative`, `update`, `prices`.

#### denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)
- **Purpose**: Converts from 1e18 to token decimals.
- **Callers**: None in v0.2.7.

#### _isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)
- **Purpose**: Checks same-day timestamps.
- **Callers**: `update`, `yieldAnnualizedView`.

#### _floorToMidnight(uint256 timestamp) returns (uint256 midnight)
- **Purpose**: Rounds timestamp to midnight.
- **Callers**: `update`, `queryDurationVolume`, `getLastDays`.

#### _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)
- **Purpose**: Returns volume from `_historicalData` at or after `startTime`.
- **Callers**: None in v0.2.7.

#### _updateRegistry(address maker)
- **Purpose**: Updates registry with `tokenA`, `tokenB` balances.
- **Callers**: `update`.
- **External Interactions**: `ITokenRegistry.initializeTokens`.
- **Errors**: Emits `UpdateRegistryFailed`, `ExternalCallFailed`.

#### removePendingOrder(uint256[] storage orders, uint256 orderId)
- **Purpose**: Removes `orderId` from order arrays.
- **Callers**: `update`.

#### globalizeUpdate()
- **Purpose**: Calls `ICCGlobalizer.globalizeOrders` for latest order.
- **Callers**: `update`.
- **External Interactions**: `ICCGlobalizer.globalizeOrders`.
- **Errors**: Emits `ExternalCallFailed`, `UpdateFailed`.

## Parameters and Interactions
- **Orders** (`UpdateType`): `updateType=0` updates `_balance`. Buy orders (`updateType=1`) input `tokenB` (`value`), output `tokenA` (`amountSent`); sell orders (`updateType=2`) input `tokenA` (`value`), output `tokenB` (`amountSent`). On creation, buy orders add `value` to `yBalance`, sell orders add `value` to `xBalance`. On settlement, buy orders add `amountSent` to `xBalance`, subtract `value` from `yBalance`; sell orders subtract `value` from `xBalance`, add `amountSent` to `yBalance`. Volumes updated in `_historicalData` as `xVolume=amountSent`, `yVolume=value` (buy) or `xVolume=value`, `yVolume=amountSent` (sell). Order completeness tracked via `orderStatus`, emitting `OrderUpdatesComplete` or `OrderUpdateIncomplete`.
- **Payouts** (`PayoutUpdate`): Long (`payoutType=0`, `tokenB`), short (`payoutType=1`, `tokenA`) via `ssUpdate`, using `getNextOrderId` for indexing.
- **Price**: Computed via `IUniswapV2Pair` and `IERC20.balanceOf(uniswapV2PairView)`, stored in `listingPriceView` after balance updates.
- **Registry**: Updated via `_updateRegistry` in `update`.
- **Globalizer**: Updated via `globalizeUpdate` in `update`.
- **Liquidity**: `ICCLiquidityTemplate.liquidityDetail` used in `update`, `yieldAnnualizedView`.
- **Historical Data**: Stored in `_historicalData` during `update`, with volumes updated post-settlement.
- **External Calls**: `IERC20.balanceOf`, `IERC20.transfer`, `IERC20.decimals`, `ITokenRegistry.initializeTokens`, `ICCLiquidityTemplate.liquidityDetail`, `ICCGlobalizer.globalizeOrders`, low-level `call`.
- **Security**: Router checks, try-catch, explicit casting, no tuple access, relaxed validation, skips invalid updates with `UpdateFailed`.
- **Optimization**: Normalized amounts, `maxIterations`, generated balance updates.
