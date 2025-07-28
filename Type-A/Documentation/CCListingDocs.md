# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract, implemented in Solidity (^0.8.2), is a decentralized trading platform component that manages buy/sell orders, payouts, and volume balances, integrating with Uniswap V2 for price derivation. It inherits `ReentrancyGuard` for security and uses `IERC20` for token operations, interfacing with `ICCAgent`, `ITokenRegistry`, `IUniswapV2Pair`, and `ICCLiquidityTemplate` for global updates, synchronization, reserve fetching, and liquidity amounts. State variables are private, accessed via view functions with unique names, and amounts are normalized to 1e18 for precision across token decimals. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.0.4 (Updated 2025-07-28)

### State Variables
- `_routers`: `mapping(address => bool) private` - Maps addresses to authorized routers.
- `_routersSet`: `bool private` - Tracks if routers are set, prevents re-setting.
- `_tokenA`: `address private` - Address of token A (or ETH if zero).
- `_tokenB`: `address private` - Address of token B (or ETH if zero).
- `_decimalsA`: `uint8 private` - Decimals of token A (18 for ETH).
- `_decimalsB`: `uint8 private` - Decimals of token B (18 for ETH).
- `_uniswapV2Pair`: `address private` - Address of the Uniswap V2 pair for price derivation.
- `_uniswapV2PairSet`: `bool private` - Tracks if Uniswap V2 pair is set, prevents re-setting.
- `_listingId`: `uint256 private` - Unique identifier for the listing.
- `_agent`: `address private` - Address of the agent contract for global updates.
- `_registryAddress`: `address private` - Address of the token registry contract.
- `_liquidityAddress`: `address private` - Address of the liquidity contract.
- `_nextOrderId`: `uint256 private` - Next available order ID for payouts/orders.
- `_lastDayFee`: `LastDayFee private` - Stores `xFees`, `yFees`, and `timestamp` for daily fee tracking.
- `_volumeBalance`: `VolumeBalance private` - Stores `xBalance`, `yBalance`, `xVolume`, `yVolume`.
- `_currentPrice`: `uint256 private` - Current price, derived from Uniswap V2 pair reserves as `(normalizedReserveA * 1e18) / normalizedReserveB`.
- `_pendingBuyOrders`: `uint256[] private` - Array of pending buy order IDs.
- `_pendingSellOrders`: `uint256[] private` - Array of pending sell order IDs.
- `_longPayoutsByIndex`: `uint256[] private` - Array of long payout order IDs.
- `_shortPayoutsByIndex`: `uint256[] private` - Array of short payout order IDs.
- `_makerPendingOrders`: `mapping(address => uint256[]) private` - Maps maker address to their pending order IDs.
- `_userPayoutIDs`: `mapping(address => uint256[]) private` - Maps user address to their payout order IDs.
- `_historicalData`: `HistoricalData[] private` - Array of historical market data.

### Mappings
- `_routers`: `mapping(address => bool)` - Maps addresses to authorized routers.
- `_buyOrderCores`: `mapping(uint256 => BuyOrderCore)` - Maps order ID to buy order core data (`makerAddress`, `recipientAddress`, `status`).
- `_buyOrderPricings`: `mapping(uint256 => BuyOrderPricing)` - Maps order ID to buy order pricing (`maxPrice`, `minPrice`).
- `_buyOrderAmounts`: `mapping(uint256 => BuyOrderAmounts)` - Maps order ID to buy order amounts (`pending`, `filled`, `amountSent`).
- `_sellOrderCores`: `mapping(uint256 => SellOrderCore)` - Maps order ID to sell order core data (`makerAddress`, `recipientAddress`, `status`).
- `_sellOrderPricings`: `mapping(uint256 => SellOrderPricing)` - Maps order ID to sell order pricing (`maxPrice`, `minPrice`).
- `_sellOrderAmounts`: `mapping(uint256 => SellOrderAmounts)` - Maps order ID to sell order amounts (`pending`, `filled`, `amountSent`).
- `_longPayouts`: `mapping(uint256 => LongPayoutStruct)` - Maps order ID to long payout data (`makerAddress`, `recipientAddress`, `required`, `filled`, `orderId`, `status`).
- `_shortPayouts`: `mapping(uint256 => ShortPayoutStruct)` - Maps order ID to short payout data (`makerAddress`, `recipientAddress`, `amount`, `filled`, `orderId`, `status`).
- `_makerPendingOrders`: `mapping(address => uint256[])` - Maps maker address to their pending order IDs.
- `_userPayoutIDs`: `mapping(address => uint256[])` - Maps user address to their payout order IDs.

### Structs
1. **LastDayFee**:
   - `xFees`: `uint256` - Token A fees at start of day.
   - `yFees`: `uint256` - Token B fees at start of day.
   - `timestamp`: `uint256` - Timestamp of last fee update.
2. **VolumeBalance**:
   - `xBalance`: `uint256` - Normalized balance of token A.
   - `yBalance`: `uint256` - Normalized balance of token B.
   - `xVolume`: `uint256` - Normalized trading volume of token A.
   - `yVolume`: `uint256` - Normalized trading volume of token B.
3. **BuyOrderCore**:
   - `makerAddress`: `address` - Address of the order creator.
   - `recipientAddress`: `address` - Address to receive tokens.
   - `status`: `uint8` - Order status (0=cancelled, 1=pending, 2=partially filled, 3=filled).
4. **BuyOrderPricing**:
   - `maxPrice`: `uint256` - Maximum acceptable price (normalized).
   - `minPrice`: `uint256` - Minimum acceptable price (normalized).
5. **BuyOrderAmounts**:
   - `pending`: `uint256` - Normalized pending amount (tokenB).
   - `filled`: `uint256` - Normalized filled amount (tokenB).
   - `amountSent`: `uint256` - Normalized amount of tokenA sent during settlement.
6. **SellOrderCore**:
   - `makerAddress`: `address` - Address of the order creator.
   - `recipientAddress`: `address` - Address to receive tokens.
   - `status`: `uint8` - Order status (0=cancelled, 1=pending, 2=partially filled, 3=filled).
7. **SellOrderPricing**:
   - Same as `BuyOrderPricing` for sell orders.
8. **SellOrderAmounts**:
   - `pending`: `uint256` - Normalized pending amount (tokenA).
   - `filled`: `uint256` - Normalized filled amount (tokenA).
   - `amountSent`: `uint256` - Normalized amount of tokenB sent during settlement.
9. **PayoutUpdate**:
   - `payoutType`: `uint8` - Type of payout (0=long, 1=short).
   - `recipient`: `address` - Address to receive payout.
   - `required`: `uint256` - Normalized amount required.
10. **LongPayoutStruct**:
    - `makerAddress`: `address` - Address of the payout creator.
    - `recipientAddress`: `address` - Address to receive payout.
    - `required`: `uint256` - Normalized amount required (tokenB).
    - `filled`: `uint256` - Normalized amount filled (tokenB).
    - `orderId`: `uint256` - Unique payout order ID.
    - `status`: `uint8` - Payout status (0=pending, others undefined).
11. **ShortPayoutStruct**:
    - `makerAddress`: `address` - Address of the payout creator.
    - `recipientAddress`: `address` - Address to receive payout.
    - `amount`: `uint256` - Normalized payout amount (tokenA).
    - `filled`: `uint256` - Normalized amount filled (tokenA).
    - `orderId`: `uint256` - Unique payout order ID.
    - `status`: `uint8` - Payout status (0=pending, others undefined).
12. **HistoricalData**:
    - `price`: `uint256` - Market price at timestamp (normalized, from Uniswap V2 reserves).
    - `xBalance`: `uint256` - Token A balance (normalized).
    - `yBalance`: `uint256` - Token B balance (normalized).
    - `xVolume`: `uint256` - Token A volume (normalized).
    - `yVolume`: `uint256` - Token B volume (normalized).
    - `timestamp`: `uint256` - Time of data snapshot.
13. **UpdateType**:
    - `updateType`: `uint8` - Update type (0=balance, 1=buy order, 2=sell order, 3=historical).
    - `structId`: `uint8` - Struct to update (0=core, 1=pricing, 2=amounts).
    - `index`: `uint256` - Order ID or balance index (0=xBalance, 1=yBalance, 2=xVolume, 3=yVolume).
    - `value`: `uint256` - Normalized amount or price (for historical updates, from Uniswap V2 reserves).
    - `addr`: `address` - Maker address.
    - `recipient`: `address` - Recipient address.
    - `maxPrice`: `uint256` - Max price or packed xBalance/yBalance (historical).
    - `minPrice`: `uint256` - Min price or packed xVolume/yVolume (historical).
    - `amountSent`: `uint256` - Normalized amount of opposite token sent during settlement.

### Formulas
1. **Price Calculation**:
   - **Formula**: `price = (normalizedReserveA * 1e18) / normalizedReserveB`
   - **Used in**: `update`, `transactToken`, `transactNative`, `prices`
   - **Description**: Computes current price from Uniswap V2 pair reserves (`reserve0`, `reserve1`), normalized to 1e18 using `decimalsA` and `decimalsB`, used for order pricing and historical data. Returns 0 if reserves are zero.
2. **Daily Yield**:
   - **Formula**: `dailyYield = ((feeDifference * 0.0005) * 1e18) / liquidity * 365`
   - **Used in**: `queryYield`
   - **Description**: Calculates annualized yield from `feeDifference` (`xVolume - lastDayFee.xFees` or `yVolume - lastDayFee.yFees`), using 0.05% fee rate and liquidity from `ICCLiquidityTemplate.liquidityAmounts`.

### External Functions
#### setUniswapV2Pair(address uniswapV2Pair_)
- **Parameters**: `uniswapV2Pair_` - Uniswap V2 pair address.
- **Behavior**: Sets `_uniswapV2Pair`, callable once.
- **Internal Call Flow**: Updates `_uniswapV2Pair` and `_uniswapV2PairSet`.
- **Restrictions**: Reverts if `_uniswapV2PairSet` is true or `uniswapV2Pair_` is zero.
- **Gas Usage Controls**: Minimal, two state writes.

#### setRouters(address[] memory routers_)
- **Parameters**: `routers_` - Array of router addresses.
- **Behavior**: Sets authorized routers, callable once.
- **Internal Call Flow**: Updates `_routers` mapping, sets `_routersSet` to true.
- **Restrictions**: Reverts if `_routersSet` is true or `routers_` is empty/invalid.
- **Gas Usage Controls**: Single loop, minimal state writes.

#### setListingId(uint256 listingId_)
- **Parameters**: `listingId_` - Listing ID.
- **Behavior**: Sets `_listingId`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `_listingId` already set.
- **Gas Usage Controls**: Minimal, single state write.

#### setLiquidityAddress(address liquidityAddress_)
- **Parameters**: `liquidityAddress_` - Liquidity contract address.
- **Behavior**: Sets `_liquidityAddress`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `_liquidityAddress` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### setTokens(address tokenA_, address tokenB_)
- **Parameters**: `tokenA_`, `tokenB_` - Token addresses.
- **Behavior**: Sets `_tokenA`, `_tokenB`, `_decimalsA`, `_decimalsB`, callable once.
- **Internal Call Flow**: Fetches decimals via `IERC20.decimals` (18 for ETH), validates non-zero decimals.
- **Restrictions**: Reverts if tokens already set, same, both zero, or invalid decimals.
- **Gas Usage Controls**: Minimal, state writes and external calls.

#### setAgent(address agent_)
- **Parameters**: `agent_` - Agent contract address.
- **Behavior**: Sets `_agent`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `_agent` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### setRegistry(address registryAddress_)
- **Parameters**: `registryAddress_` - Registry contract address.
- **Behavior**: Sets `_registryAddress`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `_registryAddress` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### update(address caller, UpdateType[] memory updates)
- **Parameters**:
  - `caller` - Router address.
  - `updates` - Array of update structs.
- **Behavior**: Updates balances, orders, or historical data, derives price from Uniswap V2 pair, triggers `globalizeUpdate`.
- **Internal Call Flow**:
  - Checks `volumeUpdated` to update `_lastDayFee` if new day.
  - Processes `updates`:
    - `updateType=0`: Updates `xBalance`, `yBalance`, `xVolume`, `yVolume`.
    - `updateType=1`: Updates buy order `core`, `pricing`, or `amounts` (including `amountSent` for tokenA), adjusts `_pendingBuyOrders`, `_makerPendingOrders`, `yBalance`, `yVolume`, `xBalance`.
    - `updateType=2`: Updates sell order `core`, `pricing`, or `amounts` (including `amountSent` for tokenB), adjusts `_pendingSellOrders`, `_makerPendingOrders`, `xBalance`, `xVolume`, `yBalance`.
    - `updateType=3`: Adds `HistoricalData` with price from Uniswap V2 reserves and packed balances/volumes.
  - Updates `_currentPrice` from Uniswap V2 reserves, calls `globalizeUpdate`, emits `BalancesUpdated` or `OrderUpdated`.
- **Balance Checks**: Ensures sufficient `xBalance`/`yBalance` for order updates, adjusts for `amountSent`.
- **Mappings/Structs Used**:
  - **Mappings**: `_buyOrderCores`, `_buyOrderPricings`, `_buyOrderAmounts`, `_sellOrderCores`, `_sellOrderPricings`, `_sellOrderAmounts`, `_pendingBuyOrders`, `_pendingSellOrders`, `_makerPendingOrders`, `_historicalData`.
  - **Structs**: `UpdateType`, `BuyOrderCore`, `BuyOrderPricing`, `BuyOrderAmounts`, `SellOrderCore`, `SellOrderPricing`, `SellOrderAmounts`, `HistoricalData`.
- **Restrictions**: `nonReentrant`, requires `_routers[caller]`.
- **Gas Usage Controls**: Dynamic array resizing, loop over `updates`, emits events for updates, external Uniswap V2 reserve calls.

#### ssUpdate(address caller, PayoutUpdate[] memory payoutUpdates)
- **Parameters**:
  - `caller` - Router address.
  - `payoutUpdates` - Array of payout updates.
- **Behavior**: Creates long/short payout orders, increments `_nextOrderId`.
- **Internal Call Flow**:
  - Creates `LongPayoutStruct` (tokenB) or `ShortPayoutStruct` (tokenA), updates `_longPayoutsByIndex`, `_shortPayoutsByIndex`, `_userPayoutIDs`.
  - Increments `_nextOrderId`, emits `PayoutOrderCreated`.
- **Balance Checks**: None, defers to `transactToken` or `transactNative`.
- **Mappings/Structs Used**:
  - **Mappings**: `_longPayouts`, `_shortPayouts`, `_longPayoutsByIndex`, `_shortPayoutsByIndex`, `_userPayoutIDs`.
  - **Structs**: `PayoutUpdate`, `LongPayoutStruct`, `ShortPayoutStruct`.
- **Restrictions**: `nonReentrant`, requires `_routers[caller]`.
- **Gas Usage Controls**: Loop over `payoutUpdates`, dynamic arrays, minimal state writes.

#### transactToken(address caller, address token, uint256 amount, address recipient)
- **Parameters**:
  - `caller` - Router address.
  - `token` - TokenA or tokenB (non-zero address).
  - `amount` - Denormalized amount.
  - `recipient` - Recipient address.
- **Behavior**: Transfers ERC20 tokens, updates balances and volumes, derives price from Uniswap V2 pair, updates registry.
- **Internal Call Flow**:
  - Normalizes `amount` using `_decimalsA` or `_decimalsB`.
  - Updates `xBalance` (tokenA) or `yBalance` (tokenB), requires sufficient balance.
  - Transfers via `IERC20.transfer`, replacing `SafeERC20`.
  - Updates `xVolume`/`yVolume`, `_lastDayFee`, `_currentPrice` from Uniswap V2 reserves.
  - Calls `_updateRegistry`, emits `BalancesUpdated`.
- **Balance Checks**: Requires sufficient `xBalance` or `yBalance`.
- **Mappings/Structs Used**:
  - **Mappings**: `_volumeBalance`.
  - **Structs**: `VolumeBalance`.
- **Restrictions**: `nonReentrant`, requires `_routers[caller]`, valid non-zero token.
- **Gas Usage Controls**: Single transfer, minimal state updates, Uniswap V2 reserve call.

#### transactNative(address caller, uint256 amount, address recipient)
- **Parameters**:
  - `caller` - Router address.
  - `amount` - Denormalized amount (ETH).
  - `recipient` - Recipient address.
- **Behavior**: Transfers native ETH, updates balances and volumes, derives price from Uniswap V2 pair, updates registry.
- **Internal Call Flow**:
  - Normalizes `amount` using 18 decimals.
  - Updates `xBalance` (if tokenA is ETH) or `yBalance` (if tokenB is ETH), requires sufficient balance.
  - Transfers ETH via low-level call with try-catch.
  - Updates `xVolume`/`yVolume`, `_lastDayFee`, `_currentPrice` from Uniswap V2 reserves.
  - Calls `_updateRegistry`, emits `BalancesUpdated`.
- **Balance Checks**: Requires sufficient `xBalance` or `yBalance`.
- **Mappings/Structs Used**:
  - **Mappings**: `_volumeBalance`.
  - **Structs**: `VolumeBalance`.
- **Restrictions**: `nonReentrant`, requires `_routers[caller]`, one token must be ETH.
- **Gas Usage Controls**: Single transfer, minimal state updates, try-catch error handling, Uniswap V2 reserve call.

#### queryYield(bool isA, uint256 maxIterations)
- **Parameters**:
  - `isA` - True for tokenA, false for tokenB.
  - `maxIterations` - Max historical data iterations.
- **Behavior**: Returns annualized yield based on daily fees.
- **Internal Call Flow**:
  - Checks `_lastDayFee.timestamp`, ensures same-day calculation.
  - Computes `feeDifference` (`xVolume - lastDayFee.xFees` or `yVolume - lastDayFee.yFees`).
  - Fetches liquidity (`xLiquid` or `yLiquid`) via `ICCLiquidityTemplate.liquidityAmounts`.
  - Calculates `dailyYield = (feeDifference * 0.0005 * 1e18) / liquidity * 365`.
- **Balance Checks**: None, relies on external `liquidityAmounts` call.
- **Mappings/Structs Used**:
  - **Mappings**: `_volumeBalance`, `_lastDayFee`.
  - **Structs**: `LastDayFee`, `VolumeBalance`.
- **Restrictions**: Reverts if `maxIterations` is zero or no historical data/same-day timestamp.
- **Gas Usage Controls**: Minimal, single external call, try-catch for `liquidityAmounts`.

#### getTokens() view returns (address tokenA, address tokenB)
- **Behavior**: Returns `_tokenA` and `_tokenB` with non-zero checks for `ICCAgent` compatibility.
- **Gas Usage Controls**: Minimal, two state reads with validation.

#### uniswapV2PairView() view returns (address)
- **Behavior**: Returns `_uniswapV2Pair` address.
- **Gas Usage Controls**: Minimal, single state read.

#### prices(uint256) view returns (uint256)
- **Parameters**: Ignored listing ID.
- **Behavior**: Returns price derived from Uniswap V2 pair reserves (`normalizedReserveA * 1e18 / normalizedReserveB`).
- **Internal Call Flow**: Fetches reserves via `IUniswapV2Pair.getReserves`, normalizes using `_decimalsA` and `_decimalsB`.
- **Gas Usage Controls**: Minimal, single external call.

#### volumeBalances(uint256) view returns (uint256 xBalance, uint256 yBalance)
- **Parameters**: Ignored listing ID.
- **Behavior**: Returns `_volumeBalance.xBalance`, `_volumeBalance.yBalance`.
- **Mappings/Structs Used**: `_volumeBalance` (`VolumeBalance`).
- **Gas Usage Controls**: Minimal, single state read.

#### liquidityAddressView(uint256) view returns (address)
- **Behavior**: Returns `_liquidityAddress`.
- **Gas Usage Controls**: Minimal, single state read.

#### tokenA() view returns (address)
- **Behavior**: Returns `_tokenA`.
- **Gas Usage Controls**: Minimal, single state read.

#### tokenB() view returns (address)
- **Behavior**: Returns `_tokenB`.
- **Gas Usage Controls**: Minimal, single state read.

#### decimalsA() view returns (uint8)
- **Behavior**: Returns `_decimalsA`.
- **Gas Usage Controls**: Minimal, single state read.

#### decimalsB() view returns (uint8)
- **Behavior**: Returns `_decimalsB`.
- **Gas Usage Controls**: Minimal, single state read.

#### getListingId() view returns (uint256)
- **Behavior**: Returns `_listingId`.
- **Gas Usage Controls**: Minimal, single state read.

#### getNextOrderId() view returns (uint256)
- **Behavior**: Returns `_nextOrderId`.
- **Gas Usage Controls**: Minimal, single state read.

#### listingVolumeBalancesView() view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume)
- **Behavior**: Returns all fields from `_volumeBalance`.
- **Mappings/Structs Used**: `_volumeBalance` (`VolumeBalance`).
- **Gas Usage Controls**: Minimal, single state read.

#### listingPriceView() view returns (uint256)
- **Behavior**: Returns `_currentPrice`.
- **Gas Usage Controls**: Minimal, single state read.

#### pendingBuyOrdersView() view returns (uint256[] memory)
- **Behavior**: Returns `_pendingBuyOrders`.
- **Mappings/Structs Used**: `_pendingBuyOrders`.
- **Gas Usage Controls**: Minimal, array read.

#### pendingSellOrdersView() view returns (uint256[] memory)
- **Behavior**: Returns `_pendingSellOrders`.
- **Mappings/Structs Used**: `_pendingSellOrders`.
- **Gas Usage Controls**: Minimal, array read.

#### makerPendingOrdersView(address maker) view returns (uint256[] memory)
- **Parameters**: `maker` - Maker address.
- **Behavior**: Returns maker's pending order IDs.
- **Mappings/Structs Used**: `_makerPendingOrders`.
- **Gas Usage Controls**: Minimal, array read.

#### longPayoutByIndexView() view returns (uint256[] memory)
- **Behavior**: Returns `_longPayoutsByIndex`.
- **Mappings/Structs Used**: `_longPayoutsByIndex`.
- **Gas Usage Controls**: Minimal, array read.

#### shortPayoutByIndexView() view returns (uint256[] memory)
- **Behavior**: Returns `_shortPayoutsByIndex`.
- **Mappings/Structs Used**: `_shortPayoutsByIndex`.
- **Gas Usage Controls**: Minimal, array read.

#### userPayoutIDsView(address user) view returns (uint256[] memory)
- **Parameters**: `user` - User address.
- **Behavior**: Returns user's payout order IDs.
- **Mappings/Structs Used**: `_userPayoutIDs`.
- **Gas Usage Controls**: Minimal, array read.

#### getLongPayout(uint256 orderId) view returns (LongPayoutStruct memory)
- **Parameters**: `orderId` - Payout order ID.
- **Behavior**: Returns `LongPayoutStruct` for given `orderId`.
- **Mappings/Structs Used**: `_longPayouts` (`LongPayoutStruct`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getShortPayout(uint256 orderId) view returns (ShortPayoutStruct memory)
- **Parameters**: `orderId` - Payout order ID.
- **Behavior**: Returns `ShortPayoutStruct` for given `orderId`.
- **Mappings/Structs Used**: `_shortPayouts` (`ShortPayoutStruct`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getBuyOrderCore(uint256 orderId) view returns (address makerAddress, address recipientAddress, uint8 status)
- **Parameters**: `orderId` - Buy order ID.
- **Behavior**: Returns fields from `_buyOrderCores[orderId]` with explicit destructuring.
- **Mappings/Structs Used**: `_buyOrderCores` (`BuyOrderCore`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getBuyOrderPricing(uint256 orderId) view returns (uint256 maxPrice, uint256 minPrice)
- **Parameters**: `orderId` - Buy order ID.
- **Behavior**: Returns fields from `_buyOrderPricings[orderId]` with explicit destructuring.
- **Mappings/Structs Used**: `_buyOrderPricings` (`BuyOrderPricing`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getBuyOrderAmounts(uint256 orderId) view returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Parameters**: `orderId` - Buy order ID.
- **Behavior**: Returns fields from `_buyOrderAmounts[orderId]` with explicit destructuring, including `amountSent` (tokenA).
- **Mappings/Structs Used**: `_buyOrderAmounts` (`BuyOrderAmounts`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getSellOrderCore(uint256 orderId) view returns (address makerAddress, address recipientAddress, uint8 status)
- **Parameters**: `orderId` - Sell order ID.
- **Behavior**: Returns fields from `_sellOrderCores[orderId]` with explicit destructuring.
- **Mappings/Structs Used**: `_sellOrderCores` (`SellOrderCore`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getSellOrderPricing(uint256 orderId) view returns (uint256 maxPrice, uint256 minPrice)
- **Parameters**: `orderId` - Sell order ID.
- **Behavior**: Returns fields from `_sellOrderPricings[orderId]` with explicit destructuring.
- **Mappings/Structs Used**: `_sellOrderPricings` (`SellOrderPricing`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getSellOrderAmounts(uint256 orderId) view returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Parameters**: `orderId` - Sell order ID.
- **Behavior**: Returns fields from `_sellOrderAmounts[orderId]` with explicit destructuring, including `amountSent` (tokenB).
- **Mappings/Structs Used**: `_sellOrderAmounts` (`SellOrderAmounts`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getHistoricalDataView(uint256 index) view returns (HistoricalData memory)
- **Parameters**: `index` - Historical data index.
- **Behavior**: Returns `HistoricalData` at given index.
- **Mappings/Structs Used**: `_historicalData` (`HistoricalData`).
- **Restrictions**: Reverts if `index` is invalid.
- **Gas Usage Controls**: Minimal, single array read.

#### historicalDataLengthView() view returns (uint256)
- **Behavior**: Returns length of `_historicalData`.
- **Mappings/Structs Used**: `_historicalData`.
- **Gas Usage Controls**: Minimal, single state read.

#### getHistoricalDataByNearestTimestamp(uint256 targetTimestamp) view returns (HistoricalData memory)
- **Parameters**: `targetTimestamp` - Target timestamp.
- **Behavior**: Returns `HistoricalData` with timestamp closest to `targetTimestamp`.
- **Mappings/Structs Used**: `_historicalData` (`HistoricalData`).
- **Restrictions**: Reverts if no historical data exists.
- **Gas Usage Controls**: Loop over `_historicalData`, minimal state reads.

### Additional Details
- **Decimal Handling**: Uses `normalize` and `denormalize` (1e18) for amounts and Uniswap V2 reserves, fetched via `IERC20.decimals` or `_decimalsA`/`_decimalsB`.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant` modifier.
- **Gas Optimization**: Dynamic array resizing, minimal external calls, try-catch for external calls (`globalizeOrders`, `initializeBalances`, `liquidityAmounts`, `getReserves`).
- **Token Usage**:
  - Buy orders: Input tokenB, output tokenA, `amountSent` tracks tokenA.
  - Sell orders: Input tokenA, output tokenB, `amountSent` tracks tokenB.
  - Long payouts: Output tokenB, no `amountSent`.
  - Short payouts: Output tokenA, no `amountSent`.
- **Events**: `OrderUpdated`, `PayoutOrderCreated`, `BalancesUpdated`.
- **Safety**:
  - Explicit casting for interfaces (e.g., `ICCLiquidityTemplate`, `IERC20`, `IUniswapV2Pair`).
  - No inline assembly, uses high-level Solidity.
  - Try-catch for external calls to handle failures gracefully.
  - Hidden state variables accessed via view functions (`tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `uniswapV2PairView`, `getTokens`, etc.).
  - Avoids reserved keywords and unnecessary virtual/override modifiers.
  - Supports non-zero balance pools via `volumeBalances`.
- **Compatibility**: Aligned with `SSAgent.sol` (v0.0.2), `SS-LiquidityTemplate.sol` (v0.0.3).
- **Price vs Prices Clarification**: `_currentPrice` is a state variable updated in `update`, `transactToken`, and `transactNative`, potentially laggy. `prices` is a view function computing price on-demand from Uniswap V2 reserves, using the same formula, preferred for real-time external queries.