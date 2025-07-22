# CCListingTemplate Specifications

## Overview
The `CCListingTemplate` contract, implemented in Solidity (^0.8.2), is a decentralized trading platform component that manages buy/sell orders, payouts, and volume balances, integrating with Uniswap V2 for price derivation. It inherits `ReentrancyGuard` for security and uses `SafeERC20` for token operations, interfacing with `ISSAgent`, `ITokenRegistry`, and `IUniswapV2Pair` for global updates, synchronization, and reserve fetching. State variables are private, accessed via view functions with unique names, and amounts are normalized to 1e18 for precision across token decimals. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.0.2 (Updated 2025-07-14)

### State Variables
- **`routersSet`**: `bool public` - Tracks if routers are set, prevents re-setting.
- **`tokenX`**: `address private` - Address of token X (or ETH if zero).
- **`tokenY`**: `address private` - Address of token Y (or ETH if zero).
- **`decimalX`**: `uint8 private` - Decimals of token X (18 for ETH).
- **`decimalY`**: `uint8 private` - Decimals of token Y (18 for ETH).
- **`uniswapV2Pair`**: `address private` - Address of the Uniswap V2 pair for price derivation.
- **`uniswapV2PairSet`**: `bool private` - Tracks if Uniswap V2 pair is set, prevents re-setting.
- **`listingId`**: `uint256 public` - Unique identifier for the listing.
- **`agent`**: `address public` - Address of the agent contract for global updates.
- **`registryAddress`**: `address public` - Address of the token registry contract.
- **`liquidityAddress`**: `address public` - Address of the liquidity contract.
- **`nextOrderId`**: `uint256 public` - Next available order ID for payouts/orders.
- **`lastDayFee`**: `LastDayFee public` - Stores `xFees`, `yFees`, and `timestamp` for daily fee tracking.
- **`volumeBalance`**: `VolumeBalance public` - Stores `xBalance`, `yBalance`, `xVolume`, `yVolume`.
- **`price`**: `uint256 public` - Current price, derived from Uniswap V2 pair reserves as `(normalizedReserveX * 1e18) / normalizedReserveY`.
- **`pendingBuyOrders`**: `uint256[] public` - Array of pending buy order IDs.
- **`pendingSellOrders`**: `uint256[] public` - Array of pending sell order IDs.
- **`longPayoutsByIndex`**: `uint256[] public` - Array of long payout order IDs.
- **`shortPayoutsByIndex`**: `uint256[] public` - Array of short payout order IDs.
- **`historicalData`**: `HistoricalData[] public` - Array of historical market data.

### Mappings
- **`routers`**: `mapping(address => bool)` - Maps addresses to authorized routers.
- **`buyOrderCores`**: `mapping(uint256 => BuyOrderCore)` - Maps order ID to buy order core data (`makerAddress`, `recipientAddress`, `status`).
- **`buyOrderPricings`**: `mapping(uint256 => BuyOrderPricing)` - Maps order ID to buy order pricing (`maxPrice`, `minPrice`).
- **`buyOrderAmounts`**: `mapping(uint256 => BuyOrderAmounts)` - Maps order ID to buy order amounts (`pending`, `filled`, `amountSent`).
- **`sellOrderCores`**: `mapping(uint256 => SellOrderCore)` - Maps order ID to sell order core data (`makerAddress`, `recipientAddress`, `status`).
- **`sellOrderPricings`**: `mapping(uint256 => SellOrderPricing)` - Maps order ID to sell order pricing (`maxPrice`, `minPrice`).
- **`sellOrderAmounts`**: `mapping(uint256 => SellOrderAmounts)` - Maps order ID to sell order amounts (`pending`, `filled`, `amountSent`).
- **`longPayouts`**: `mapping(uint256 => LongPayoutStruct)` - Maps order ID to long payout data (`makerAddress`, `recipientAddress`, `required`, `filled`, `orderId`, `status`).
- **`shortPayouts`**: `mapping(uint256 => ShortPayoutStruct)` - Maps order ID to short payout data (`makerAddress`, `recipientAddress`, `amount`, `filled`, `orderId`, `status`).
- **`makerPendingOrders`**: `mapping(address => uint256[])` - Maps maker address to their pending order IDs.
- **`userPayoutIDs`**: `mapping(address => uint256[])` - Maps user address to their payout order IDs.

### Structs
1. **LastDayFee**:
   - `xFees`: `uint256` - Token X fees at start of day.
   - `yFees`: `uint256` - Token Y fees at start of day.
   - `timestamp`: `uint256` - Timestamp of last fee update.

2. **VolumeBalance**:
   - `xBalance`: `uint256` - Normalized balance of token X.
   - `yBalance`: `uint256` - Normalized balance of token Y.
   - `xVolume`: `uint256` - Normalized trading volume of token X.
   - `yVolume`: `uint256` - Normalized trading volume of token Y.

3. **BuyOrderCore**:
   - `makerAddress`: `address` - Address of the order creator.
   - `recipientAddress`: `address` - Address to receive tokens.
   - `status`: `uint8` - Order status (0=cancelled, 1=pending, 2=partially filled, 3=filled).

4. **BuyOrderPricing**:
   - `maxPrice`: `uint256` - Maximum acceptable price (normalized).
   - `minPrice`: `uint256` - Minimum acceptable price (normalized).

5. **BuyOrderAmounts**:
   - `pending`: `uint256` - Normalized pending amount (tokenY).
   - `filled`: `uint256` - Normalized filled amount (tokenY).
   - `amountSent`: `uint256` - Normalized amount of tokenX sent during settlement.

6. **SellOrderCore**:
   - Same as `BuyOrderCore` for sell orders.

7. **SellOrderPricing**:
   - Same as `BuyOrderPricing` for sell orders.

8. **SellOrderAmounts**:
   - `pending`: `uint256` - Normalized pending amount (tokenX).
   - `filled`: `uint256` - Normalized filled amount (tokenX).
   - `amountSent`: `uint256` - Normalized amount of tokenY sent during settlement.

9. **PayoutUpdate**:
   - `payoutType`: `uint8` - Type of payout (0=long, 1=short).
   - `recipient`: `address` - Address to receive payout.
   - `required`: `uint256` - Normalized amount required.

10. **LongPayoutStruct**:
    - `makerAddress`: `address` - Address of the payout creator.
    - `recipientAddress`: `address` - Address to receive payout.
    - `required`: `uint256` - Normalized amount required (tokenY).
    - `filled`: `uint256` - Normalized amount filled (tokenY).
    - `orderId`: `uint256` - Unique payout order ID.
    - `status`: `uint8` - Payout status (0=pending, others undefined).

11. **ShortPayoutStruct**:
    - `makerAddress`: `address` - Address of the payout creator.
    - `recipientAddress`: `address` - Address to receive payout.
    - `amount`: `uint256` - Normalized payout amount (tokenX).
    - `filled`: `uint256` - Normalized amount filled (tokenX).
    - `orderId`: `uint256` - Unique payout order ID.
    - `status`: `uint8` - Payout status (0=pending, others undefined).

12. **HistoricalData**:
    - `price`: `uint256` - Market price at timestamp (normalized, from Uniswap V2 reserves).
    - `xBalance`: `uint256` - Token X balance (normalized).
    - `yBalance`: `uint256` - Token Y balance (normalized).
    - `xVolume`: `uint256` - Token X volume (normalized).
    - `yVolume`: `uint256` - Token Y volume (normalized).
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
   - **Formula**: `price = (normalizedReserveX * 1e18) / normalizedReserveY`
   - **Used in**: `update`, `transact`, `prices`
   - **Description**: Computes current price from Uniswap V2 pair reserves (`reserve0`, `reserve1`), normalized to 1e18 using `decimalX` and `decimalY`, used for order pricing and historical data.

2. **Daily Yield**:
   - **Formula**: `dailyYield = ((feeDifference * 0.0005) * 1e18) / liquidity * 365`
   - **Used in**: `queryYield`
   - **Description**: Calculates annualized yield from `feeDifference` (`xVolume - lastDayFee.xFees` or `yVolume - lastDayFee.yFees`), using 0.05% fee rate and liquidity from `ISSLiquidityTemplate`.

### External Functions
#### setUniswapV2Pair(address _uniswapV2Pair)
- **Parameters**: `_uniswapV2Pair` - Uniswap V2 pair address.
- **Behavior**: Sets `uniswapV2Pair`, callable once.
- **Internal Call Flow**: Updates `uniswapV2Pair` and `uniswapV2PairSet`.
- **Restrictions**: Reverts if `uniswapV2PairSet` is true or `_uniswapV2Pair` is zero.
- **Gas Usage Controls**: Minimal, two state writes.

#### setRouters(address[] memory _routers)
- **Parameters**: `_routers` - Array of router addresses.
- **Behavior**: Sets authorized routers, callable once.
- **Internal Call Flow**: Updates `routers` mapping, sets `routersSet` to true.
- **Restrictions**: Reverts if `routersSet` is true or `_routers` is empty/invalid.
- **Gas Usage Controls**: Single loop, minimal state writes.

#### setListingId(uint256 _listingId)
- **Parameters**: `_listingId` - Listing ID.
- **Behavior**: Sets `listingId`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `listingId` already set.
- **Gas Usage Controls**: Minimal, single state write.

#### setLiquidityAddress(address _liquidityAddress)
- **Parameters**: `_liquidityAddress` - Liquidity contract address.
- **Behavior**: Sets `liquidityAddress`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `liquidityAddress` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### setTokens(address _tokenA, address _tokenB)
- **Parameters**: `_tokenA`, `_tokenB` - Token addresses.
- **Behavior**: Sets `tokenX`, `tokenY`, `decimalX`, `decimalY`, callable once.
- **Internal Call Flow**: Fetches decimals via `IERC20.decimals` (18 for ETH).
- **Restrictions**: Reverts if tokens already set, same, or both zero.
- **Gas Usage Controls**: Minimal, state writes and external calls.

#### setAgent(address _agent)
- **Parameters**: `_agent` - Agent contract address.
- **Behavior**: Sets `agent`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `agent` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### setRegistry(address _registryAddress)
- **Parameters**: `_registryAddress` - Registry contract address.
- **Behavior**: Sets `registryAddress`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `registryAddress` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### update(address caller, UpdateType[] memory updates)
- **Parameters**:
  - `caller` - Router address.
  - `updates` - Array of update structs.
- **Behavior**: Updates balances, orders, or historical data, derives price from Uniswap V2 pair, triggers `globalizeUpdate`.
- **Internal Call Flow**:
  - Checks `volumeUpdated` to update `lastDayFee` if new day.
  - Processes `updates`:
    - `updateType=0`: Updates `xBalance`, `yBalance`, `xVolume`, `yVolume`.
    - `updateType=1`: Updates buy order `core`, `pricing`, or `amounts` (including `amountSent` for tokenX), adjusts `pendingBuyOrders`, `makerPendingOrders`, `yBalance`, `yVolume`, `xBalance`.
    - `updateType=2`: Updates sell order `core`, `pricing`, or `amounts` (including `amountSent` for tokenY), adjusts `pendingSellOrders`, `makerPendingOrders`, `xBalance`, `xVolume`, `yBalance`.
    - `updateType=3`: Adds `HistoricalData` with price from Uniswap V2 reserves and packed balances/volumes.
  - Updates `price` from Uniswap V2 reserves, calls `globalizeUpdate`, emits `BalancesUpdated` or `OrderUpdated`.
- **Balance Checks**: Ensures sufficient `xBalance`/`yBalance` for order updates, adjusts for `amountSent`.
- **Mappings/Structs Used**:
  - **Mappings**: `buyOrderCores`, `buyOrderPricings`, `buyOrderAmounts`, `sellOrderCores`, `sellOrderPricings`, `sellOrderAmounts`, `pendingBuyOrders`, `pendingSellOrders`, `makerPendingOrders`, `historicalData`.
  - **Structs**: `UpdateType`, `BuyOrderCore`, `BuyOrderPricing`, `BuyOrderAmounts`, `SellOrderCore`, `SellOrderPricing`, `SellOrderAmounts`, `HistoricalData`.
- **Restrictions**: `nonReentrant`, requires `routers[caller]`.
- **Gas Usage Controls**: Dynamic array resizing, loop over `updates`, emits events for updates, external Uniswap V2 reserve calls.

#### ssUpdate(address caller, PayoutUpdate[] memory payoutUpdates)
- **Parameters**:
  - `caller` - Router address.
  - `payoutUpdates` - Array of payout updates.
- **Behavior**: Creates long/short payout orders, increments `nextOrderId`.
- **Internal Call Flow**:
  - Creates `LongPayoutStruct` (tokenY) or `ShortPayoutStruct` (tokenX), updates `longPayoutsByIndex`, `shortPayoutsByIndex`, `userPayoutIDs`.
  - Increments `nextOrderId`, emits `PayoutOrderCreated`.
- **Balance Checks**: None, defers to `transact`.
- **Mappings/Structs Used**:
  - **Mappings**: `longPayouts`, `shortPayouts`, `longPayoutsByIndex`, `shortPayoutsByIndex`, `userPayoutIDs`.
  - **Structs**: `PayoutUpdate`, `LongPayoutStruct`, `ShortPayoutStruct`.
- **Restrictions**: `nonReentrant`, requires `routers[caller]`.
- **Gas Usage Controls**: Loop over `payoutUpdates`, dynamic arrays, minimal state writes.

#### transact(address caller, address token, uint256 amount, address recipient)
- **Parameters**:
  - `caller` - Router address.
  - `token` - TokenX or tokenY.
  - `amount` - Denormalized amount.
  - `recipient` - Recipient address.
- **Behavior**: Transfers tokens/ETH, updates balances, derives price from Uniswap V2 pair, and updates registry.
- **Internal Call Flow**:
  - Normalizes `amount` using `decimalX` or `decimalY`.
  - Checks `xBalance` (tokenX) or `yBalance` (tokenY).
  - Transfers via `SafeERC20.safeTransfer` or ETH call with try-catch.
  - Updates `xVolume`/`yVolume`, `lastDayFee`, `price` from Uniswap V2 reserves.
  - Calls `_updateRegistry`, emits `BalancesUpdated`.
- **Balance Checks**: Pre-transfer balance check for `xBalance` or `yBalance`.
- **Mappings/Structs Used**:
  - **Mappings**: `volumeBalance`.
  - **Structs**: `VolumeBalance`.
- **Restrictions**: `nonReentrant`, requires `routers[caller]`, valid token.
- **Gas Usage Controls**: Single transfer, minimal state updates, try-catch error handling, Uniswap V2 reserve call.

#### queryYield(bool isA, uint256 maxIterations)
- **Parameters**:
  - `isA` - True for tokenX, false for tokenY.
  - `maxIterations` - Max historical data iterations.
- **Behavior**: Returns annualized yield based on daily fees.
- **Internal Call Flow**:
  - Checks `lastDayFee.timestamp`, ensures same-day calculation.
  - Computes `feeDifference` (`xVolume - lastDayFee.xFees` or `yVolume - lastDayFee.yFees`).
  - Fetches liquidity (`xLiquid` or `yLiquid`) via `ISSLiquidityTemplate.liquidityAmounts`.
  - Calculates `dailyYield = (feeDifference * 0.0005 * 1e18) / liquidity * 365`.
- **Balance Checks**: None, relies on external `liquidityAmounts` call.
- **Mappings/Structs Used**:
  - **Mappings**: `volumeBalance`, `lastDayFee`.
  - **Structs**: `LastDayFee`, `VolumeBalance`.
- **Restrictions**: Reverts if `maxIterations` is zero or no historical data/same-day timestamp.
- **Gas Usage Controls**: Minimal, single external call, try-catch for `liquidityAmounts`.

#### uniswapV2PairView() view returns (address)
- **Behavior**: Returns `uniswapV2Pair` address.
- **Gas Usage Controls**: Minimal, single state read.

#### prices(uint256) view returns (uint256)
- **Parameters**: Ignored listing ID.
- **Behavior**: Returns price derived from Uniswap V2 pair reserves (`normalizedReserveX * 1e18 / normalizedReserveY`).
- **Internal Call Flow**: Fetches reserves via `IUniswapV2Pair.getReserves`, normalizes using `decimalX` and `decimalY`.
- **Gas Usage Controls**: Minimal, single external call.

#### volumeBalances(uint256) view returns (uint256 xBalance, uint256 yBalance)
- **Parameters**: Ignored listing ID.
- **Behavior**: Returns `xBalance`, `yBalance` from `volumeBalance`.
- **Mappings/Structs Used**: `volumeBalance` (`VolumeBalance`).
- **Gas Usage Controls**: Minimal, single state read.

#### liquidityAddressView(uint256) view returns (address)
- **Parameters**: Ignored listing ID.
- **Behavior**: Returns `liquidityAddress`.
- **Gas Usage Controls**: Minimal, single state read.

#### tokenA() view returns (address)
- **Behavior**: Returns `tokenX`.
- **Gas Usage Controls**: Minimal, single state read.

#### tokenB() view returns (address)
- **Behavior**: Returns `tokenY`.
- **Gas Usage Controls**: Minimal, single state read.

#### decimalsA() view returns (uint8)
- **Behavior**: Returns `decimalX`.
- **Gas Usage Controls**: Minimal, single state read.

#### decimalsB() view returns (uint8)
- **Behavior**: Returns `decimalY`.
- **Gas Usage Controls**: Minimal, single state read.

#### getListingId() view returns (uint256)
- **Behavior**: Returns `listingId`.
- **Gas Usage Controls**: Minimal, single state read.

#### getNextOrderId() view returns (uint256)
- **Behavior**: Returns `nextOrderId`.
- **Gas Usage Controls**: Minimal, single state read.

#### listingVolumeBalancesView() view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume)
- **Behavior**: Returns all fields from `volumeBalance`.
- **Mappings/Structs Used**: `volumeBalance` (`VolumeBalance`).
- **Gas Usage Controls**: Minimal, single state read.

#### listingPriceView() view returns (uint256)
- **Behavior**: Returns `price`.
- **Gas Usage Controls**: Minimal, single state read.

#### pendingBuyOrdersView() view returns (uint256[] memory)
- **Behavior**: Returns `pendingBuyOrders`.
- **Mappings/Structs Used**: `pendingBuyOrders`.
- **Gas Usage Controls**: Minimal, array read.

#### pendingSellOrdersView() view returns (uint256[] memory)
- **Behavior**: Returns `pendingSellOrders`.
- **Mappings/Structs Used**: `pendingSellOrders`.
- **Gas Usage Controls**: Minimal, array read.

#### makerPendingOrdersView(address maker) view returns (uint256[] memory)
- **Parameters**: `maker` - Maker address.
- **Behavior**: Returns maker's pending order IDs.
- **Mappings/Structs Used**: `makerPendingOrders`.
- **Gas Usage Controls**: Minimal, array read.

#### longPayoutByIndexView() view returns (uint256[] memory)
- **Behavior**: Returns `longPayoutsByIndex`.
- **Mappings/Structs Used**: `longPayoutsByIndex`.
- **Gas Usage Controls**: Minimal, array read.

#### shortPayoutByIndexView() view returns (uint256[] memory)
- **Behavior**: Returns `shortPayoutsByIndex`.
- **Mappings/Structs Used**: `shortPayoutsByIndex`.
- **Gas Usage Controls**: Minimal, array read.

#### userPayoutIDsView(address user) view returns (uint256[] memory)
- **Parameters**: `user` - User address.
- **Behavior**: Returns user's payout order IDs.
- **Mappings/Structs Used**: `userPayoutIDs`.
- **Gas Usage Controls**: Minimal, array read.

#### getLongPayout(uint256 orderId) view returns (LongPayoutStruct memory)
- **Parameters**: `orderId` - Payout order ID.
- **Behavior**: Returns `LongPayoutStruct` for given `orderId`.
- **Mappings/Structs Used**: `longPayouts` (`LongPayoutStruct`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getShortPayout(uint256 orderId) view returns (ShortPayoutStruct memory)
- **Parameters**: `orderId` - Payout order ID.
- **Behavior**: Returns `ShortPayoutStruct` for given `orderId`.
- **Mappings/Structs Used**: `shortPayouts` (`ShortPayoutStruct`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getBuyOrderCore(uint256 orderId) view returns (address makerAddress, address recipientAddress, uint8 status)
- **Parameters**: `orderId` - Buy order ID.
- **Behavior**: Returns fields from `buyOrderCores[orderId]` with explicit destructuring.
- **Mappings/Structs Used**: `buyOrderCores` (`BuyOrderCore`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getBuyOrderPricing(uint256 orderId) view returns (uint256 maxPrice, uint256 minPrice)
- **Parameters**: `orderId` - Buy order ID.
- **Behavior**: Returns fields from `buyOrderPricings[orderId]` with explicit destructuring.
- **Mappings/Structs Used**: `buyOrderPricings` (`BuyOrderPricing`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getBuyOrderAmounts(uint256 orderId) view returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Parameters**: `orderId` - Buy order ID.
- **Behavior**: Returns fields from `buyOrderAmounts[orderId]` with explicit destructuring, including `amountSent` (tokenX).
- **Mappings/Structs Used**: `buyOrderAmounts` (`BuyOrderAmounts`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getSellOrderCore(uint256 orderId) view returns (address makerAddress, address recipientAddress, uint8 status)
- **Parameters**: `orderId` - Sell order ID.
- **Behavior**: Returns fields from `sellOrderCores[orderId]` with explicit destructuring.
- **Mappings/Structs Used**: `sellOrderCores` (`SellOrderCore`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getSellOrderPricing(uint256 orderId) view returns (uint256 maxPrice, uint256 minPrice)
- **Parameters**: `orderId` - Sell order ID.
- **Behavior**: Returns fields from `sellOrderPricings[orderId]` with explicit destructuring.
- **Mappings/Structs Used**: `sellOrderPricings` (`SellOrderPricing`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getSellOrderAmounts(uint256 orderId) view returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Parameters**: `orderId` - Sell order ID.
- **Behavior**: Returns fields from `sellOrderAmounts[orderId]` with explicit destructuring, including `amountSent` (tokenY).
- **Mappings/Structs Used**: `sellOrderAmounts` (`SellOrderAmounts`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getHistoricalDataView(uint256 index) view returns (HistoricalData memory)
- **Parameters**: `index` - Historical data index.
- **Behavior**: Returns `HistoricalData` at given index.
- **Mappings/Structs Used**: `historicalData` (`HistoricalData`).
- **Restrictions**: Reverts if `index` is invalid.
- **Gas Usage Controls**: Minimal, single array read.

#### historicalDataLengthView() view returns (uint256)
- **Behavior**: Returns length of `historicalData`.
- **Mappings/Structs Used**: `historicalData`.
- **Gas Usage Controls**: Minimal, single state read.

#### getHistoricalDataByNearestTimestamp(uint256 targetTimestamp) view returns (HistoricalData memory)
- **Parameters**: `targetTimestamp` - Target timestamp.
- **Behavior**: Returns `HistoricalData` with timestamp closest to `targetTimestamp`.
- **Mappings/Structs Used**: `historicalData` (`HistoricalData`).
- **Restrictions**: Reverts if no historical data exists.
- **Gas Usage Controls**: Loop over `historicalData`, minimal state reads.

### Additional Details
- **Decimal Handling**: Uses `normalize` and `denormalize` (1e18) for amounts and Uniswap V2 reserves, fetched via `IERC20.decimals` or `decimalX`/`decimalY`.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant` modifier.
- **Gas Optimization**: Dynamic array resizing, minimal external calls, try-catch for external calls (`globalizeOrders`, `initializeBalances`, `liquidityAmounts`, `getReserves`).
- **Token Usage**:
  - Buy orders: Input tokenY, output tokenX, `amountSent` tracks tokenX.
  - Sell orders: Input tokenX, output tokenY, `amountSent` tracks tokenY.
  - Long payouts: Output tokenY, no `amountSent`.
  - Short payouts: Output tokenX, no `amountSent`.
- **Events**: `OrderUpdated`, `PayoutOrderCreated`, `BalancesUpdated`.
- **Safety**:
  - Explicit casting for interfaces (e.g., `ISSListingTemplate`, `IERC20`, `IUniswapV2Pair`).
  - No inline assembly, uses high-level Solidity.
  - Try-catch for external calls to handle failures gracefully.
  - Hidden state variables (`tokenX`, `tokenY`, `decimalX`, `decimalY`, `uniswapV2Pair`, `uniswapV2PairSet`) accessed via view functions (`tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `uniswapV2PairView`).
  - Avoids reserved keywords and unnecessary virtual/override modifiers.
- **Compatibility**: Aligned with `SSRouter` (v0.0.62), `SSAgent` (v0.0.2), `SSOrderPartial` (v0.0.18), `SSLiquidityTemplate` (v0.0.3), and Uniswap V2 for price derivation.
