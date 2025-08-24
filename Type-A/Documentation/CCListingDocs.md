# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract, written in Solidity (^0.8.2), facilitates decentralized trading for a token pair, integrating with Uniswap V2 for price discovery using `IERC20.balanceOf` for token balances at the pair address. It manages buy/sell orders, long/short payouts, and tracks normalized (1e18 precision) balances. Volume is captured in `_historicalData` during order settlement, with `_captureHistoricalData` triggered post-settlement. Licensed under BSL 1.1 - Peng Protocol 2025, it ensures secure, modular design with explicit casting, no inline assembly, and graceful degradation for external calls.

## Version
- **0.2.1**
- **Changes**:
  - v0.2.1: Updated `update()` to handle balance deductions for sell orders (`xBalance -= u.value`, `yBalance += u.amountSent`) and additions for buy orders. Relaxed pending amount validation to avoid precision reverts. Added exchange rate recalculation after balance updates. Generates balance updates if not provided by router, ignores redundant updates from `CCUniPartial`. Compatible with `CCUniPartial.sol` (v0.1.0), `CCOrderPartial.sol` (v0.1.0).
  - v0.2.0: Bumped version.
  - v0.1.18: Fixed inconsistent volume tracking in `update` for sell order logic (`xVolume += u.value`, `yVolume += u.amountSent`) to align with buy order logic (`xVolume += u.amountSent`, `yVolume += u.value`).
  - v0.1.17: Fixed balance update logic in `update` to adjust `_balance.xBalance`, `yBalance` incrementally. Corrected order settlement to use `_getExchangeRate`. Updated volume tracking to reflect token amounts during settlement only.
  - v0.1.16: Fixed TypeError in `setRouters` by using `address` as key for `_routers`.
  - v0.1.15: Fixed ParserError in `queryDurationVolume` by renaming `days` to `durationDays`.
  - v0.1.14: Fixed ParserError in `queryDurationVolume` by casting `days` to `uint256`.
  - v0.1.13: Removed redundant view functions, made state variables/mappings public.
  - v0.1.12: Restored `queryYield` for annualized yield, adjusted `dayStartFee`.
  - v0.1.11: Fixed buy order settlement in `update` to adjust `xBalance`, `yBalance`.
- **Compatibility**: Compatible with `CCLiquidityTemplate.sol` (v0.1.1), `CCMainPartial.sol` (v0.0.12), `CCLiquidityPartial.sol` (v0.0.21), `ICCLiquidity.sol` (v0.0.5), `ICCListing.sol` (v0.0.7), `CCOrderRouter.sol` (v0.0.11), `TokenRegistry.sol` (2025-08-04), `CCUniPartial.sol` (v0.1.0), `CCOrderPartial.sol` (v0.1.0).

## Interfaces
- **IERC20**: Provides `decimals()`, `transfer(address, uint256)`, `balanceOf(address)` for token precision, transfers, and balance queries.
- **ICCListing**: Exposes view functions (`prices`, `volumeBalances`, `liquidityAddressView`, `tokenA`, `tokenB`, `decimalsA`, `decimalsB`) and `ssUpdate`.
- **IUniswapV2Pair**: Provides `token0`, `token1` for pair token mapping.
- **ICCListingTemplate**: Declares `getTokens`, `globalizerAddressView`, `makerPendingBuyOrdersView`, `makerPendingSellOrdersView`, `queryYield`, `queryDurationVolume`, `getLastDays`.
- **ICCLiquidityTemplate**: Provides `liquidityDetail` for fee data.
- **ITokenRegistry**: Defines `initializeTokens(address user, address[] memory tokens)`.
- **ICCGlobalizer**: Defines `globalizeOrders(address maker, address token)`.

## Structs
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
- **PayoutUpdate**: Defines `payoutType` (0: Long, 1: Short), `recipient`, `required`.

## Fee Segregation
The `_balance` struct (`xBalance`, `yBalance`) segregates fees from pending orders by tracking tokens received from the order router during order creation and settlement, excluding fees managed by `ICCLiquidityTemplate`. On buy order creation (`updateType=1`, `structId=2`), `u.value` (tokenB) adds to `yBalance`; on sell order creation (`updateType=2`, `structId=2`), `u.value` (tokenA) adds to `xBalance`. During settlement, buy orders add `u.amountSent` (tokenA) to `xBalance`, subtract `u.value` (tokenB) from `yBalance`; sell orders subtract `u.value` (tokenA) from `xBalance`, add `u.amountSent` (tokenB) to `yBalance`. Fees are fetched via `ICCLiquidityTemplate.liquidityDetail` and stored in `dayStartFee` for `queryYield`.

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

#### update(UpdateType[] memory updates)
- **Purpose**: Processes balance updates, buy/sell orders, and captures historical data.
- **Inputs**: `updates` (`UpdateType[]` with `updateType`, `structId`, `index`, `value`, `addr`, `recipient`, `maxPrice`, `minPrice`, `amountSent`).
- **Logic**:
  1. Requires `_routers[msg.sender]`.
  2. Tracks volume updates (`updateType=1,2`, `structId=2`, non-zero `value`, `amountSent`).
  3. If volume updated and new day, fetches fees via `ICCLiquidityTemplate.liquidityDetail`, updates `dayStartFee`.
  4. Tracks balance changes: buy orders add `u.amountSent` (tokenA) to `xBalance`, `u.value` (tokenB) to `yBalance`; sell orders add `u.value` (tokenA) to `xBalance` (deduct on settlement), `u.amountSent` (tokenB) to `yBalance`.
  5. Generates balance updates if not provided (`updateType=0`), ignores redundant updates.
  6. Iterates updates:
     - `updateType=0`: Deducts `xBalance` (index=0) or adds `yBalance` (index=1) by `u.value`.
     - `updateType=1`: Buy orders:
       - `structId=0`: Initializes `getBuyOrderCore`, adds to `pendingBuyOrdersView`, `makerPendingOrdersView`, emits `OrderUpdated`.
       - `structId=1`: Sets `getBuyOrderPricing` (`maxPrice`, `minPrice`).
       - `structId=2`: Subtracts `u.value` (tokenB) from `yBalance`, adds `u.amountSent` (tokenA) to `xBalance`, updates `xVolume` (`amountSent`), `yVolume` (`value`), `getBuyOrderAmounts`, `getBuyOrderCore`, emits `OrderUpdated`.
     - `updateType=2`: Sell orders:
       - `structId=0`: Initializes `getSellOrderCore`, adds to `pendingSellOrdersView`, `makerPendingOrdersView`, emits `OrderUpdated`.
       - `structId=1`: Sets `getSellOrderPricing` (`maxPrice`, `minPrice`).
       - `structId=2`: Subtracts `u.value` (tokenA) from `xBalance`, adds `u.amountSent` (tokenB) to `yBalance`, updates `xVolume` (`value`), `yVolume` (`amountSent`), `getSellOrderAmounts`, `getSellOrderCore`, emits `OrderUpdated`.
     - `updateType=3`: Sets `_historicalData.price`.
  7. If balance updated, recalculates `listingPriceView` via `_getExchangeRate`.
  8. If `xVolume` or `yVolume` non-zero, updates `_historicalData`, calls `_captureHistoricalData`.
  9. Calls `_updateRegistry`, `globalizeUpdate` for latest maker.
  10. Emits `BalancesUpdated`.
- **State Changes**: `_balance`, `getBuyOrderCore`, `getBuyOrderPricing`, `getBuyOrderAmounts`, `getSellOrderCore`, `getSellOrderPricing`, `getSellOrderAmounts`, `_historicalData`, `pendingBuyOrdersView`, `pendingSellOrdersView`, `makerPendingOrdersView`, `listingPriceView`, `dayStartFee`, `getNextOrderId`.
- **External Interactions**: `ICCLiquidityTemplate.liquidityDetail`, `IERC20.balanceOf`, `ITokenRegistry.initializeTokens`, `ICCGlobalizer.globalizeOrders`.
- **Internal Call Tree**:
  - `_getExchangeRate`: Fetches price from `IERC20.balanceOf`.
  - `_isSameDay`, `_floorToMidnight`: For `dayStartFee`.
  - `_updateRegistry`: Calls `ITokenRegistry.initializeTokens`.
  - `globalizeUpdate`: Calls `ICCGlobalizer.globalizeOrders`.
  - `_captureHistoricalData`: Stores price, balances, volumes.
  - `removePendingOrder`: Updates order arrays.
  - `normalize`: Normalizes amounts.
- **Errors**: Reverts for invalid router, emits `UpdateFailed`, `ExternalCallFailed` for precision mismatches.

#### ssUpdate(PayoutUpdate[] memory payoutUpdates)
- **Purpose**: Creates long/short payout orders.
- **Inputs**: `payoutUpdates` (`PayoutUpdate[]`).
- **Logic**: Iterates `payoutUpdates`, creates `LongPayoutStruct` (`payoutType=0`) or `ShortPayoutStruct` (`payoutType=1`), updates `getLongPayout`, `getShortPayout`, `longPayoutByIndexView`, `shortPayoutByIndexView`, `userPayoutIDsView`, emits `PayoutOrderCreated`, increments `getNextOrderId`.
- **State Changes**: `getLongPayout`, `getShortPayout`, `longPayoutByIndexView`, `shortPayoutByIndexView`, `userPayoutIDsView`, `getNextOrderId`.
- **Errors**: Reverts if `!_routers[msg.sender]`.
- **Call Tree**: None.

#### transactToken(address token, uint256 amount, address recipient)
- **Purpose**: Transfers `tokenA` or `tokenB`, updates balances, price.
- **Inputs**: `token`, `amount`, `recipient`.
- **Logic**: Checks router, valid token, normalizes `amount`, updates `_balance`, fetches price via `IERC20.balanceOf`, transfers via `IERC20.transfer`, emits `BalancesUpdated`.
- **State Changes**: `_balance`, `listingPriceView`.
- **External Interactions**: `IERC20.balanceOf`, `IERC20.transfer`.
- **Internal Call Tree**: `normalize`.
- **Errors**: Reverts for invalid router, token, or transfer failure, emits `TransactionFailed`, `ExternalCallFailed`.

#### transactNative(uint256 amount, address recipient)
- **Purpose**: Transfers ETH, updates balances, price.
- **Inputs**: `amount`, `recipient`.
- **Logic**: Checks router, native token, normalizes `amount`, updates `_balance`, fetches price via `IERC20.balanceOf`, transfers ETH via `call`, emits `BalancesUpdated`.
- **State Changes**: `_balance`, `listingPriceView`.
- **External Interactions**: `IERC20.balanceOf`, low-level `call`.
- **Internal Call Tree**: `normalize`.
- **Errors**: Reverts for invalid router, no native token, or transfer failure, emits `TransactionFailed`.

#### queryYield(uint256 maxIterations, uint256 depositAmount, bool isTokenA)
- **Purpose**: Calculates annualized yield from liquidity fees.
- **Inputs**: `isA`, `maxIterations` (>0), `depositAmount`, `isTokenA`.
- **Logic**: Fetches fees via `ICCLiquidityTemplate.liquidityDetail`, calculates daily fees using `dayStartFee`, computes yield (`dailyFees * 365 * 10000 / depositAmount`).
- **External Interactions**: `ICCLiquidityTemplate.liquidityDetail`.
- **Internal Call Tree**: `_isSameDay`.
- **Errors**: Returns 0 if `maxIterations == 0`, `liquidityAddressView == address(0)`, or call fails.

#### queryDurationVolume(bool isA, uint256 durationDays, uint256 maxIterations)
- **Purpose**: Sums volume over `durationDays` for `tokenA` or `tokenB`.
- **Inputs**: `isA`, `durationDays` (>0), `maxIterations` (>0).
- **Logic**: Sums `xVolume` or `yVolume` from `_historicalData` within `durationDays`, capped by `maxIterations`.
- **Internal Call Tree**: `_floorToMidnight`.
- **Errors**: Reverts if `durationDays == 0` or `maxIterations == 0`. Returns 0 if `_historicalData` empty.

#### getLastDays(uint256 count, uint256 maxIterations)
- **Purpose**: Returns day boundary indices, timestamps from `_dayStartIndices`.
- **Inputs**: `count`, `maxIterations` (>0).
- **Logic**: Collects indices, timestamps for up to `count` days, capped by `maxIterations`.
- **Internal Call Tree**: `_floorToMidnight`.
- **Errors**: Reverts if `maxIterations == 0`.

### Internal Functions
#### _getExchangeRate() returns (uint256 price)
- **Purpose**: Computes price using `IERC20.balanceOf(uniswapV2PairView)`.
- **Callers**: `update`, `transactToken`, `transactNative`.
- **Logic**: Fetches normalized balances, returns `balanceB * 1e18 / balanceA` or `listingPriceView` on failure.
- **External Interactions**: `IERC20.balanceOf`.
- **Internal Call Tree**: `normalize`.
- **Errors**: Graceful degradation, emits `ExternalCallFailed`.

#### normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)
- **Purpose**: Normalizes amounts to 1e18.
- **Callers**: `transactToken`, `transactNative`, `_captureHistoricalData`, `prices`, `_getExchangeRate`.

#### denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)
- **Purpose**: Converts from 1e18 to token decimals.
- **Callers**: None in v0.2.1.

#### _isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)
- **Purpose**: Checks same-day timestamps.
- **Callers**: `update`, `queryYield`, `_captureHistoricalData`.

#### _floorToMidnight(uint256 timestamp) returns (uint256 midnight)
- **Purpose**: Rounds timestamp to midnight.
- **Callers**: `update`, `queryDurationVolume`, `getLastDays`, `_captureHistoricalData`.

#### _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)
- **Purpose**: Returns volume from `_historicalData` at or after `startTime`.
- **Callers**: None in v0.2.1.

#### _updateRegistry(address maker)
- **Purpose**: Updates registry with `tokenA`, `tokenB` balances.
- **Callers**: `update`.
- **External Interactions**: `ITokenRegistry.initializeTokens`.

#### removePendingOrder(uint256[] storage orders, uint256 orderId)
- **Purpose**: Removes `orderId` from order arrays.
- **Callers**: `update`.

#### globalizeUpdate()
- **Purpose**: Calls `ICCGlobalizer.globalizeOrders` for latest order.
- **Callers**: `update`.
- **External Interactions**: `ICCGlobalizer.globalizeOrders`.

#### _captureHistoricalData()
- **Purpose**: Stores price, balances, zeroed volumes in `_historicalData`.
- **Callers**: `update`.
- **External Interactions**: `IERC20.balanceOf`.
- **Internal Call Tree**: `normalize`, `_isSameDay`, `_floorToMidnight`.

### View Functions
- **agentView**, **uniswapV2PairView**, **getListingId**, **getNextOrderId**, **liquidityAddressView**, **tokenA**, **tokenB**, **decimalsA**, **decimalsB**, **listingPriceView**, **pendingBuyOrdersView**, **pendingSellOrdersView**, **makerPendingOrdersView**, **longPayoutByIndexView**, **shortPayoutByIndexView**, **userPayoutIDsView**, **getLongPayout**, **getShortPayout**, **getBuyOrderCore**, **getBuyOrderPricing**, **getBuyOrderAmounts**, **getSellOrderCore**, **getSellOrderPricing**, **getSellOrderAmounts**: Return respective state variables/mappings.
- **prices(uint256)**: Computes price from `IERC20.balanceOf`, returns `listingPriceView` on failure.
- **getTokens**: Returns `tokenA`, `tokenB`.
- **volumeBalances(uint256)**: Returns `_balance.xBalance`, `yBalance`.
- **listingVolumeBalancesView**: Returns `_balance.xBalance`, `yBalance`, `xVolume`, `yVolume` from `_historicalData`.
- **makerPendingBuyOrdersView**, **makerPendingSellOrdersView**: Returns pending order IDs for `maker`, capped by `maxIterations`.
- **getFullBuyOrderDetails**, **getFullSellOrderDetails**: Returns full order details.
- **makerOrdersView**: Returns maker order IDs, capped by `maxIterations`.
- **getHistoricalDataView**: Returns `_historicalData[index]`.
- **historicalDataLengthView**: Returns `_historicalData.length`.
- **getHistoricalDataByNearestTimestamp**: Returns `_historicalData` closest to `targetTimestamp`.
- **globalizerAddressView**: Returns `_globalizerAddress`.

## Parameters and Interactions
- **Orders** (`UpdateType`): `updateType=0` deducts `xBalance` or adds `yBalance`. Buy orders (`updateType=1`) input `tokenB` (`value`), output `tokenA` (`amountSent`); sell orders (`updateType=2`) input `tokenA` (`value`), output `tokenB` (`amountSent`). On creation, buy orders add `value` to `yBalance`, sell orders add `value` to `xBalance`. On settlement, buy orders add `amountSent` to `xBalance`, subtract `value` from `yBalance`; sell orders subtract `value` from `xBalance`, add `amountSent` to `yBalance`. Volumes updated as `xVolume=amountSent`, `yVolume=value` (buy) or `xVolume=value`, `yVolume=amountSent` (sell).
- **Payouts** (`PayoutUpdate`): Long (`payoutType=0`, `tokenB`), short (`payoutType=1`, `tokenA`) via `ssUpdate`.
- **Price**: Computed via `_getExchangeRate` using `IERC20.balanceOf(uniswapV2PairView)`, stored in `listingPriceView` after balance updates.
- **Registry**: Updated via `_updateRegistry` in `update`.
- **Globalizer**: Updated via `globalizeUpdate` in `update`.
- **Liquidity**: `ICCLiquidityTemplate.liquidityDetail` used in `update`, `queryYield`.
- **Historical Data**: `_captureHistoricalData` stores price, balances, zeroed volumes in `update`. Settlement volumes updated in `_historicalData`.
- **External Calls**: `IERC20.balanceOf`, `IERC20.transfer`, `IERC20.decimals`, `ITokenRegistry.initializeTokens`, `ICCLiquidityTemplate.liquidityDetail`, `ICCGlobalizer.globalizeOrders`, low-level `call`.
- **Security**: Router checks, try-catch, explicit casting, no tuple access, relaxed validation for precision mismatches.
- **Optimization**: Normalized amounts, `maxIterations`, `_getExchangeRate` for accurate settlement, generated balance updates.
