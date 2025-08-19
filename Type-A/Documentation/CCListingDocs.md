# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract, written in Solidity (^0.8.2), facilitates decentralized trading for a token pair, integrating with Uniswap V2 for price discovery using token balances (`IERC20.balanceOf`) to ensure compatible scaling. It manages buy/sell orders, long/short payouts, and tracks normalized (1e18 precision) balances and volumes. Licensed under BSL 1.1 - Peng Protocol 2025, it ensures secure, modular design with explicit casting, no inline assembly, and graceful degradation for external calls.

## Version
- **0.1.9**
- **Changes**:
  - v0.1.9: Updated price calculation in `prices`, `update`, `transactToken`, and `transactNative` to use `IERC20.balanceOf` for `_tokenA` and `_tokenB` balances in `_uniswapV2Pair`, normalized to 1e18, replacing `getReserves` to fix incorrect price scaling.
  - v0.1.8: Used `reserveB * 1e18 / reserveA` for tokenB/tokenA pricing in `prices`, `update`, `transactToken`, `transactNative`.
- **Compatibility**: Compatible with `CCLiquidityTemplate.sol` (v0.1.1), `CCMainPartial.sol` (v0.0.12), `CCLiquidityPartial.sol` (v0.0.21), `ICCLiquidity.sol` (v0.0.5), `ICCListing.sol` (v0.0.7), `CCOrderRouter.sol` (v0.0.11), `TokenRegistry.sol` (2025-08-04).

## Interfaces
- **IERC20**: Provides `decimals()`, `transfer(address, uint256)`, and `balanceOf(address)` for token precision, transfers, and balance queries for `_tokenA`, `_tokenB`.
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
- **Purpose**: Sets `_globalizerAddress` for `globalizeUpdate`.
- **Inputs**: `globalizerAddress_` (non-zero).
- **Logic**: Sets `_globalizerAddress`, `_globalizerSet=true`, emits `GlobalizerAddressSet`.
- **State Changes**: `_globalizerAddress`, `_globalizerSet`.
- **Errors**: Reverts if `_globalizerSet` or `globalizerAddress_ == address(0)`.

#### setUniswapV2Pair(address uniswapV2Pair_)
- **Purpose**: Sets `_uniswapV2Pair` for price calculations.
- **Inputs**: `uniswapV2Pair_` (non-zero).
- **Logic**: Sets `_uniswapV2Pair`, `_uniswapV2PairSet=true`.
- **State Changes**: `_uniswapV2Pair`, `_uniswapV2PairSet`.
- **Errors**: Reverts if `_uniswapV2PairSet` or `uniswapV2Pair_ == address(0)`.

#### setRouters(address[] memory routers_)
- **Purpose**: Authorizes routers in `_routers`.
- **Inputs**: `routers_` (non-empty, non-zero addresses).
- **Logic**: Sets `_routers[router]=true`, `_routersSet=true`.
- **State Changes**: `_routers`, `_routersSet`.
- **Errors**: Reverts if `_routersSet`, `routers_.length == 0`, or any `routers_[i] == address(0)`.

#### setListingId(uint256 listingId_)
- **Purpose**: Sets `_listingId`.
- **Inputs**: `listingId_`.
- **Logic**: Sets `_listingId`.
- **State Changes**: `_listingId`.
- **Errors**: Reverts if `_listingId != 0`.

#### setLiquidityAddress(address liquidityAddress_)
- **Purpose**: Sets `_liquidityAddress`.
- **Inputs**: `liquidityAddress_` (non-zero).
- **Logic**: Sets `_liquidityAddress`.
- **State Changes**: `_liquidityAddress`.
- **Errors**: Reverts if `_liquidityAddress != address(0)` or `liquidityAddress_ == address(0)`.

#### setTokens(address tokenA_, address tokenB_)
- **Purpose**: Sets `_tokenA`, `_tokenB`, `_decimalsA`, `_decimalsB`.
- **Inputs**: `tokenA_`, `tokenB_` (different, at least one non-zero).
- **Logic**: Sets tokens, fetches decimals via `IERC20.decimals` (18 for ETH).
- **State Changes**: `_tokenA`, `_tokenB`, `_decimalsA`, `_decimalsB`.
- **External Interactions**: `IERC20.decimals`.
- **Errors**: Reverts if tokens set, `tokenA_ == tokenB_`, or both zero.

#### setAgent(address agent_)
- **Purpose**: Sets `_agent`.
- **Inputs**: `agent_` (non-zero).
- **Logic**: Sets `_agent`.
- **State Changes**: `_agent`.
- **Errors**: Reverts if `_agent != address(0)` or `agent_ == address(0)`.

#### setRegistry(address registryAddress_)
- **Purpose**: Sets `_registryAddress`.
- **Inputs**: `registryAddress_` (non-zero).
- **Logic**: Sets `_registryAddress`.
- **State Changes**: `_registryAddress`.
- **Errors**: Reverts if `_registryAddress != address(0)` or `registryAddress_ == address(0)`.

#### update(UpdateType[] memory updates)
- **Purpose**: Updates balances, orders, or historical data, refreshes fees, registry, and globalizes orders.
- **Inputs**: `updates` (`UpdateType[]`).
- **Logic**:
  1. Requires `_routers[msg.sender]`.
  2. Tracks `volumeUpdated`, `maker`.
  3. Updates `_lastDayFee` if volume changed and new day.
  4. Processes updates:
     - `updateType=0`: Updates `_volumeBalance` fields.
     - `updateType=1`: Updates buy orders (`_buyOrderCores`, `_buyOrderPricings`, `_buyOrderAmounts`).
     - `updateType=2`: Updates sell orders (`_sellOrderCores`, `_sellOrderPricings`, `_sellOrderAmounts`).
     - `updateType=3`: Adds to `_historicalData`.
  5. Updates `_currentPrice` using `IERC20.balanceOf` for `_tokenA`, `_tokenB` in `_uniswapV2Pair`.
  6. Calls `_updateRegistry`, `globalizeUpdate`.
  7. Emits `BalancesUpdated`.
- **State Changes**: `_volumeBalance`, `_lastDayFee`, `_pendingBuyOrders`, `_pendingSellOrders`, `_makerPendingOrders`, `_historicalData`, `_buyOrderCores`, `_buyOrderPricings`, `_buyOrderAmounts`, `_sellOrderCores`, `_sellOrderPricings`, `_sellOrderAmounts`, `_nextOrderId`, `_currentPrice`.
- **External Interactions**: `ICCLiquidityTemplate.liquidityDetail`, `IERC20.balanceOf`, `ITokenRegistry.initializeTokens`, `ICCGlobalizer.globalizeOrders`.
- **Internal Call Trees**: `_isSameDay`, `_floorToMidnight`, `removePendingOrder`, `_updateRegistry`, `globalizeUpdate`.
- **Errors**: Reverts for invalid router, insufficient pending amounts, or failed external calls.

#### ssUpdate(PayoutUpdate[] memory payoutUpdates)
- **Purpose**: Creates long/short payout orders.
- **Inputs**: `payoutUpdates` (`PayoutUpdate[]`).
- **Logic**:
  1. Requires `_routers[msg.sender]`.
  2. Creates `LongPayoutStruct` or `ShortPayoutStruct`, updates arrays, emits `PayoutOrderCreated`.
- **State Changes**: `_longPayouts`, `_shortPayouts`, `_longPayoutsByIndex`, `_shortPayoutsByIndex`, `_userPayoutIDs`, `_nextOrderId`.
- **Errors**: Reverts if `!_routers[msg.sender]`.

#### transactToken(address token, uint256 amount, address recipient)
- **Purpose**: Transfers `_tokenA` or `_tokenB`, updates balances, volumes, and price.
- **Inputs**: `token` (`_tokenA` or `_tokenB`), `amount`, `recipient`.
- **Logic**:
  1. Requires `_routers[msg.sender]`, valid `token`.
  2. Normalizes `amount`, updates `_volumeBalance`.
  3. Updates `_currentPrice` using `IERC20.balanceOf`.
  4. Transfers via `IERC20.transfer`.
  5. Emits `BalancesUpdated`.
- **State Changes**: `_volumeBalance`, `_currentPrice`.
- **External Interactions**: `IERC20.balanceOf`, `IERC20.transfer`.
- **Internal Call Trees**: `normalize`.
- **Errors**: Reverts for invalid router, token, or transfer failure.

#### transactNative(uint256 amount, address recipient)
- **Purpose**: Transfers ETH, updates balances, volumes, and price.
- **Inputs**: `amount`, `recipient`.
- **Logic**:
  1. Requires `_routers[msg.sender]`, `_tokenA` or `_tokenB` as `address(0)`.
  2. Normalizes `amount`, updates `_volumeBalance`.
  3. Updates `_currentPrice` using `IERC20.balanceOf`.
  4. Transfers ETH via `call`.
  5. Emits `BalancesUpdated`.
- **State Changes**: `_volumeBalance`, `_currentPrice`.
- **External Interactions**: `IERC20.balanceOf`, low-level `call`.
- **Internal Call Trees**: `normalize`.
- **Errors**: Reverts for invalid router, no native token, or transfer failure.

### Internal Functions
#### normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)
- **Purpose**: Normalizes amounts to 1e18.
- **Callers**: `transactToken`, `transactNative`, `update`, `prices`.
- **Logic**: Adjusts `amount` based on `decimals` (multiply if `<18`, divide if `>18`).
- **Gas**: Minimal, pure arithmetic.

#### denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)
- **Purpose**: Converts from 1e18 to token decimals.
- **Callers**: None.
- **Logic**: Inverse of `normalize`.
- **Gas**: Minimal, pure arithmetic.

#### _isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)
- **Purpose**: Checks same-day timestamps.
- **Callers**: `update`.
- **Logic**: Compares `time1/86400 == time2/86400`.
- **Gas**: Minimal, pure arithmetic.

#### _floorToMidnight(uint256 timestamp) returns (uint256 midnight)
- **Purpose**: Rounds to midnight.
- **Callers**: `update`.
- **Logic**: Returns `(timestamp / 86400) * 86400`.
- **Gas**: Minimal, pure arithmetic.

#### _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)
- **Purpose**: Calculates volume change since `startTime`.
- **Callers**: None.
- **Logic**: Compares current volume to historical, limited by `maxIterations`.
- **Gas**: Scales with `_historicalData.length`.

#### _updateRegistry(address maker)
- **Purpose**: Updates `ITokenRegistry` for `maker`.
- **Callers**: `update`.
- **Logic**: Calls `initializeTokens` with `_tokenA`, `_tokenB`.
- **External Interactions**: `ITokenRegistry.initializeTokens`.
- **Errors**: Reverts on failure or gas limit exceeded.

#### removePendingOrder(uint256[] storage orders, uint256 orderId)
- **Purpose**: Removes `orderId` from array.
- **Callers**: `update`.
- **Logic**: Swap-and-pop.
- **Gas**: Scales with array length.

#### globalizeUpdate()
- **Purpose**: Calls `ICCGlobalizer.globalizeOrders` for latest order.
- **Callers**: `update`.
- **Logic**: Uses latest `orderId`, selects `token` based on order type.
- **External Interactions**: `ICCGlobalizer.globalizeOrders`.
- **Errors**: Reverts on failure.

### View Functions
- **agentView**, **uniswapV2PairView**, **liquidityAddressView**, **tokenA**, **tokenB**, **decimalsA**, **decimalsB**, **getListingId**, **getNextOrderId**, **listingPriceView**: Return respective state variables.
- **prices(uint256)**: Computes price using `IERC20.balanceOf`, returns `_currentPrice` on failure.
- **getTokens**: Returns `_tokenA`, `_tokenB`, requires one non-zero.
- **volumeBalances(uint256)**: Returns `_volumeBalance.xBalance`, `yBalance`.
- **listingVolumeBalancesView**: Returns all `_volumeBalance` fields.
- **pendingBuyOrdersView**, **pendingSellOrdersView**, **makerPendingOrdersView**, **longPayoutByIndexView**, **shortPayoutByIndexView**, **userPayoutIDsView**: Return arrays.
- **getLongPayout**, **getShortPayout**: Return payout structs.
- **getBuyOrderCore**, **getBuyOrderPricing**, **getBuyOrderAmounts**, **getSellOrderCore**, **getSellOrderPricing**, **getSellOrderAmounts**: Return order struct fields.
- **getHistoricalDataView**: Returns `_historicalData[index]`.
- **historicalDataLengthView**: Returns `_historicalData.length`.
- **getHistoricalDataByNearestTimestamp**: Returns closest `_historicalData` entry.
- **globalizerAddressView**: Returns `_globalizerAddress`.
- **makerPendingBuyOrdersView**, **makerPendingSellOrdersView**: Return pending order IDs with `maxIterations`, `step`.
- **getFullBuyOrderDetails**, **getFullSellOrderDetails**: Return full order structs.
- **makerOrdersView**: Returns maker order IDs with `maxIterations`, `step`.

## Parameters and Interactions
- **Orders** (`UpdateType`): Updates balances, buy/sell orders, or historical data. Buy orders input `_tokenB`, output `_tokenA`; sell orders input `_tokenA`, output `_tokenB`. Normalized to 1e18.
- **Payouts** (`PayoutUpdate`): Long payouts output `_tokenB`, short payouts output `_tokenA`. Created via `ssUpdate`.
- **Price**: Computed as `reserveB * 1e18 / reserveA` using `IERC20.balanceOf(_uniswapV2Pair)` for `_tokenA`, `_tokenB`, normalized to 1e18. Stored in `_currentPrice`, updated in `update`, `transactToken`, `transactNative`.
- **Registry**: Updated via `_updateRegistry` for makers, using `ITokenRegistry.initializeTokens`.
- **Globalizer**: Called in `globalizeUpdate` with latest order’s `maker` and `token` (`_tokenB` for buy, `_tokenA` for sell).
- **Liquidity**: `ICCLiquidityTemplate.liquidityDetail` fetches fees for `_lastDayFee`.

## Security and Optimization
- **Security**: Router checks, try-catch on external calls, gas limits, no inline assembly, explicit casting, no tuple access.
- **Optimization**: Swap-and-pop for arrays, normalized amounts, `maxIterations` for gas control, single-maker registry updates.
