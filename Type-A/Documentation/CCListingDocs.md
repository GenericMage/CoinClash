# CCListingTemplate Documentation

## Overview
The `CCListingTemplate` contract, written in Solidity (^0.8.2), facilitates decentralized trading for a token pair, integrating with Uniswap V2 for price discovery and liquidity management. It handles buy and sell orders, long and short payouts, and tracks volume and balances with normalized values (1e18 precision) for consistent calculations across tokens with varying decimals. The contract adheres to the Business Source License (BSL) 1.1 - Peng Protocol 2025, emphasizing secure, modular design for token pair listings, with explicit casting, no inline assembly, and graceful degradation for external calls.

## Version
- **0.1.8**
- **Changes**:
  - v0.1.8: Updated price calculation in `prices`, `update`, `transactToken`, and `transactNative` to use `reserveB * 1e18 / reserveA`, flipping the reserve ratio for tokenB/tokenA pricing, normalized to 1e18 precision.
- **Compatibility**: Compatible with `CCLiquidityTemplate.sol` (v0.1.1), `CCMainPartial.sol` (v0.0.12), `CCLiquidityPartial.sol` (v0.0.21), `ICCLiquidity.sol` (v0.0.5), `ICCListing.sol` (v0.0.7), `CCOrderRouter.sol` (v0.0.11), `TokenRegistry.sol` (2025-08-04).

## Interfaces
The contract interacts with external contracts via well-defined interfaces, ensuring modularity and compliance with the style guide:
- **IERC20**: Provides `decimals()` for token precision (used for normalization to 1e18) and `transfer(address, uint256)` for token transfers. Applied to `_tokenA` and `_tokenB`.
- **ICCListing**: Exposes view functions (`prices`, `volumeBalances`, `liquidityAddressView`, `tokenA`, `tokenB`, `decimalsA`, `decimalsB`) and `ssUpdate` for payout updates. The `PayoutUpdate` struct defines `payoutType` (0: Long, 1: Short), `recipient`, and `required` amount.
- **IUniswapV2Pair**: Interfaces with Uniswap V2 for `getReserves()` (returns `reserve0`, `reserve1`, `blockTimestampLast`) and `token0`, `token1` to map `_tokenA`, `_tokenB` to pair reserves.
- **ICCListingTemplate**: Declares `getTokens`, `globalizerAddressView`, `makerPendingBuyOrdersView`, `makerPendingSellOrdersView` for token pair and globalizer address access, and pending order queries.
- **ICCLiquidityTemplate**: Provides `liquidityDetail` (returns `xLiquid`, `yLiquid`, `xFees`, `yFees`, `xFeesAcc`, `yFeesAcc`) for yield calculations.
- **ITokenRegistry**: Defines `initializeTokens(address user, address[] memory tokens)` for updating token balances in the registry for a single user.
- **ICCGlobalizer**: Defines `globalizeOrders(address maker, address token)` for order globalization, called in `globalizeUpdate` with token based on latest order type (`_tokenB` for buy, `_tokenA` for sell).

Interfaces use explicit function declarations, avoid naming conflicts with state variables, and support external calls with revert strings for graceful degradation.

## Structs
Structs organize data for orders, payouts, and historical tracking, with explicit fields to avoid tuple access:
- **LastDayFee**: Stores `lastDayXFeesAcc`, `lastDayYFeesAcc` (cumulative fees at midnight), and `timestamp` for daily fee tracking, reset at midnight.
- **VolumeBalance**: Tracks `xBalance`, `yBalance` (normalized token balances), `xVolume`, `yVolume` (cumulative trading volumes, never decreasing).
- **HistoricalData**: Records `price` (tokenB/tokenA, 1e18), `xBalance`, `yBalance`, `xVolume`, `yVolume`, and `timestamp` for historical analysis.
- **BuyOrderCore**: Tracks `makerAddress` (order creator), `recipientAddress` (payout recipient), `status` (0: cancelled, 1: pending, 2: partially filled, 3: filled) for buy orders.
- **BuyOrderPricing**: Stores `maxPrice`, `minPrice` (1e18 precision) for buy order price bounds.
- **BuyOrderAmounts**: Manages `pending` (tokenB pending, normalized), `filled` (tokenB filled), `amountSent` (tokenA sent during settlement).
- **SellOrderCore**: Similar to `BuyOrderCore` for sell orders.
- **SellOrderPricing**: Similar to `BuyOrderPricing` for sell orders.
- **SellOrderAmounts**: Manages `pending` (tokenA pending, normalized), `filled` (tokenA filled), `amountSent` (tokenB sent).
- **LongPayoutStruct**: Tracks `makerAddress`, `recipientAddress`, `required` (tokenB amount), `filled`, `orderId`, `status` for long payouts.
- **ShortPayoutStruct**: Tracks `makerAddress`, `recipientAddress`, `amount` (tokenA amount), `filled`, `orderId`, `status` for short payouts.
- **UpdateType**: Manages updates with `updateType` (0: balance, 1: buy order, 2: sell order, 3: historical), `structId` (0: Core, 1: Pricing, 2: Amounts), `index` (orderId or balance/volume slot), `value` (amount/price), `addr` (maker), `recipient`, `maxPrice`, `minPrice`, `amountSent` (opposite token sent).
- **PayoutUpdate**: Defined in `ICCListing`, specifies `payoutType` (0: Long for tokenB, 1: Short for tokenA), `recipient`, `required` for payout requests in `ssUpdate`.

Structs avoid nested calls during initialization, computing dependencies first for safe assignments.

## State Variables
State variables are private, accessed via dedicated view functions for encapsulation:
- `_routers`: `mapping(address => bool)` - Tracks authorized routers, set via `setRouters`, restricts sensitive functions.
- `_routersSet`: `bool` - Prevents resetting routers after `setRouters`.
- `_tokenA`, `_tokenB`: `address` - Token pair (ETH as `address(0)`), set via `setTokens`, used for transfers and price calculations.
- `_decimalsA`, `_decimalsB`: `uint8` - Token decimals, fetched via `IERC20.decimals` or set to 18 for ETH in `setTokens`.
- `_uniswapV2Pair`, `_uniswapV2PairSet`: `address`, `bool` - Uniswap V2 pair address and flag, set via `setUniswapV2Pair`.
- `_listingId`: `uint256` - Unique listing identifier, set via `setListingId`, used in events.
- `_agent`: `address` - Agent address, set via `setAgent`, used for registry access.
- `_registryAddress`: `address` - `ITokenRegistry` address, set via `setRegistry`, used in `_updateRegistry`.
- `_liquidityAddress`: `address` - `ICCLiquidityTemplate` address, set via `setLiquidityAddress`, used in fee-related functions.
- `_globalizerAddress`, `_globalizerSet`: `address`, `bool` - Globalizer contract address and flag, set via `setGlobalizerAddress`, used in `globalizeUpdate`.
- `_nextOrderId`: `uint256` - Incremental order ID counter, updated in `update` and `ssUpdate`.
- `_lastDayFee`: `LastDayFee` - Tracks daily fees, updated in `update` when volume changes.
- `_volumeBalance`: `VolumeBalance` - Stores balances and volumes, updated in `update`, `transactToken`, `transactNative`.
- `_currentPrice`: `uint256` - Current price (tokenB/tokenA, 1e18), updated in `update`, `transactToken`, `transactNative`.
- `_pendingBuyOrders`, `_pendingSellOrders`: `uint256[]` - Arrays of pending buy/sell order IDs, updated in `update`.
- `_longPayoutsByIndex`, `_shortPayoutsByIndex`: `uint256[]` - Arrays of long/short payout IDs, updated in `ssUpdate`.
- `_makerPendingOrders`: `mapping(address => uint256[])` - Stores all order IDs (buy or sell) created by a maker, updated in `update`.
- `_userPayoutIDs`: `mapping(address => uint256[])` - Stores payout IDs for users, updated in `ssUpdate`.
- `_historicalData`: `HistoricalData[]` - Stores price and volume history, updated in `update`.
- `_buyOrderCores`, `_buyOrderPricings`, `_buyOrderAmounts`: `mapping(uint256 => ...)` - Store buy order data, updated in `update`.
- `_sellOrderCores`, `_sellOrderPricings`, `_sellOrderAmounts`: `mapping(uint256 => ...)` - Store sell order data, updated in `update`.
- `_longPayouts`, `_shortPayouts`: `mapping(uint256 => ...)` - Store payout data, updated in `ssUpdate`.

## Functions
### External Functions
#### setGlobalizerAddress(address globalizerAddress_)
- **Purpose**: Sets the `_globalizerAddress` for calling `ICCGlobalizer.globalizeOrders` in `globalizeUpdate`, enabling order propagation to a global registry.
- **Inputs**:
  - `globalizerAddress_`: `address` - The address of the `ICCGlobalizer` contract, must be non-zero.
- **Outputs**: None.
- **Logic**:
  1. Verifies `_globalizerSet` is `false` to prevent re-setting.
  2. Ensures `globalizerAddress_` is non-zero to avoid invalid addresses.
  3. Sets `_globalizerAddress` to `globalizerAddress_`.
  4. Sets `_globalizerSet` to `true` to lock the address.
  5. Emits `GlobalizerAddressSet` with `globalizerAddress_`.
- **State Changes**:
  - Updates `_globalizerAddress`.
  - Sets `_globalizerSet` to `true`.
- **External Interactions**: None.
- **Internal Call Trees**: None.
- **Gas Considerations**: Minimal, involves two storage writes and one event emission.
- **Error Handling**:
  - Reverts if `_globalizerSet` is `true` ("Globalizer already set").
  - Reverts if `globalizerAddress_` is `address(0)` ("Invalid globalizer address").

#### setUniswapV2Pair(address uniswapV2Pair_)
- **Purpose**: Sets the `_uniswapV2Pair` address for Uniswap V2 reserve queries used in price calculations.
- **Inputs**:
  - `uniswapV2Pair_`: `address` - The Uniswap V2 pair address, must be non-zero.
- **Outputs**: None.
- **Logic**:
  1. Verifies `_uniswapV2PairSet` is `false` to prevent re-setting.
  2. Ensures `uniswapV2Pair_` is non-zero.
  3. Sets `_uniswapV2Pair` to `uniswapV2Pair_`.
  4. Sets `_uniswapV2PairSet` to `true`.
- **State Changes**:
  - Updates `_uniswapV2Pair`.
  - Sets `_uniswapV2PairSet` to `true`.
- **External Interactions**: None.
- **Internal Call Trees**: None.
- **Gas Considerations**: Minimal, two storage writes.
- **Error Handling**:
  - Reverts if `_uniswapV2PairSet` is `true` ("Uniswap V2 pair already set").
  - Reverts if `uniswapV2Pair_` is `address(0)` ("Invalid pair address").

#### setRouters(address[] memory routers_)
- **Purpose**: Authorizes router addresses in `_routers` mapping to restrict sensitive functions (`update`, `ssUpdate`, `transactToken`, `transactNative`).
- **Inputs**:
  - `routers_`: `address[]` - Array of router addresses, must be non-empty and contain non-zero addresses.
- **Outputs**: None.
- **Logic**:
  1. Verifies `_routersSet` is `false`.
  2. Ensures `routers_` has at least one address.
  3. Iterates over `routers_`, requiring each to be non-zero.
  4. Sets `_routers[router] = true` for each address.
  5. Sets `_routersSet` to `true`.
- **State Changes**:
  - Updates `_routers` mapping for each address in `routers_`.
  - Sets `_routersSet` to `true`.
- **External Interactions**: None.
- **Internal Call Trees**: None.
- **Gas Considerations**: Scales with `routers_.length` due to loop and storage writes (mapping updates are O(1)).
- **Error Handling**:
  - Reverts if `_routersSet` is `true` ("Routers already set").
  - Reverts if `routers_.length == 0` ("No routers provided").
  - Reverts if any `routers_[i]` is `address(0)` ("Invalid router address").

#### setListingId(uint256 listingId_)
- **Purpose**: Sets the `_listingId` to uniquely identify the token pair listing in events.
- **Inputs**:
  - `listingId_`: `uint256` - The listing identifier.
- **Outputs**: None.
- **Logic**:
  1. Verifies `_listingId` is 0 to prevent re-setting.
  2. Sets `_listingId` to `listingId_`.
- **State Changes**:
  - Updates `_listingId`.
- **External Interactions**: None.
- **Internal Call Trees**: None.
- **Gas Considerations**: Minimal, single storage write.
- **Error Handling**:
  - Reverts if `_listingId != 0` ("Listing ID already set").

#### setLiquidityAddress(address liquidityAddress_)
- **Purpose**: Sets the `_liquidityAddress` for fetching liquidity data from `ICCLiquidityTemplate`.
- **Inputs**:
  - `liquidityAddress_`: `address` - The `ICCLiquidityTemplate` address, must be non-zero.
- **Outputs**: None.
- **Logic**:
  1. Verifies `_liquidityAddress` is `address(0)`.
  2. Ensures `liquidityAddress_` is non-zero.
  3. Sets `_liquidityAddress` to `liquidityAddress_`.
- **State Changes**:
  - Updates `_liquidityAddress`.
- **External Interactions**: None.
- **Internal Call Trees**: None.
- **Gas Considerations**: Minimal, single storage write.
- **Error Handling**:
  - Reverts if `_liquidityAddress != address(0)` ("Liquidity already set").
  - Reverts if `liquidityAddress_ == address(0)` ("Invalid liquidity address").

#### setTokens(address tokenA_, address tokenB_)
- **Purpose**: Sets the trading pair (`_tokenA`, `_tokenB`) and their decimals (`_decimalsA`, `_decimalsB`) for normalization and price calculations.
- **Inputs**:
  - `tokenA_`: `address` - First token (ETH as `address(0)`).
  - `tokenB_`: `address` - Second token (ETH as `address(0)`).
- **Outputs**: None.
- **Logic**:
  1. Verifies `_tokenA` and `_tokenB` are unset (`address(0)`).
  2. Ensures `tokenA_ != tokenB_` to prevent identical tokens.
  3. Requires at least one token to be non-zero.
  4. Sets `_tokenA = tokenA_`, `_tokenB = tokenB_`.
  5. Sets `_decimalsA = IERC20(tokenA_).decimals()` if `tokenA_ != address(0)`, else 18.
  6. Sets `_decimalsB = IERC20(tokenB_).decimals()` if `tokenB_ != address(0)`, else 18.
- **State Changes**:
  - Updates `_tokenA`, `_tokenB`, `_decimalsA`, `_decimalsB`.
- **External Interactions**:
  - Calls `IERC20.decimals` for non-zero `tokenA_`, `tokenB_`.
- **Internal Call Trees**: None.
- **Gas Considerations**: Four storage writes, up to two external calls (`decimals`), which are view functions and lightweight.
- **Error Handling**:
  - Reverts if `_tokenA != address(0) || _tokenB != address(0)` ("Tokens already set").
  - Reverts if `tokenA_ == tokenB_` ("Tokens must be different").
  - Reverts if `tokenA_ == address(0) && tokenB_ == address(0)` ("Both tokens cannot be zero").

#### setAgent(address agent_)
- **Purpose**: Sets the `_agent` address for registry access or validation in related contracts.
- **Inputs**:
  - `agent_`: `address` - The agent address, must be non-zero.
- **Outputs**: None.
- **Logic**:
  1. Verifies `_agent` is `address(0)`.
  2. Ensures `agent_` is non-zero.
  3. Sets `_agent = agent_`.
- **State Changes**:
  - Updates `_agent`.
- **External Interactions**: None.
- **Internal Call Trees**: None.
- **Gas Considerations**: Minimal, single storage write.
- **Error Handling**:
  - Reverts if `_agent != address(0)` ("Agent already set").
  - Reverts if `agent_ == address(0)` ("Invalid agent address").

#### setRegistry(address registryAddress_)
- **Purpose**: Sets the `_registryAddress` for `ITokenRegistry` interactions in `_updateRegistry`.
- **Inputs**:
  - `registryAddress_`: `address` - The `ITokenRegistry` address, must be non-zero.
- **Outputs**: None.
- **Logic**:
  1. Verifies `_registryAddress` is `address(0)`.
  2. Ensures `registryAddress_` is non-zero.
  3. Sets `_registryAddress = registryAddress_`.
- **State Changes**:
  - Updates `_registryAddress`.
- **External Interactions**: None.
- **Internal Call Trees**: None.
- **Gas Considerations**: Minimal, single storage write.
- **Error Handling**:
  - Reverts if `_registryAddress != address(0)` ("Registry already set").
  - Reverts if `registryAddress_ == address(0)` ("Invalid registry address").

#### update(UpdateType[] memory updates)
- **Purpose**: Processes a batch of updates for balances, buy/sell orders, or historical data, restricted to authorized routers. Updates fees, registry, and globalizes the latest order.
- **Inputs**:
  - `updates`: `UpdateType[]` - Array of updates with fields: `updateType` (0: balance, 1: buy order, 2: sell order, 3: historical), `structId` (0: Core, 1: Pricing, 2: Amounts), `index` (orderId or balance/volume slot), `value` (amount/price), `addr` (maker), `recipient`, `maxPrice`, `minPrice`, `amountSent`.
- **Outputs**: None.
- **Logic**:
  1. Verifies `msg.sender` is in `_routers`.
  2. Initializes `volumeUpdated = false`, `maker = address(0)` for tracking.
  3. First loop over `updates`:
     - Sets `volumeUpdated = true` if updating volumes (`updateType=0, index=2|3`) or buy/sell order amounts (`updateType=1|2, structId=2, value>0`).
     - Sets `maker = u.addr` for buy/sell orders (`updateType=1|2`).
  4. If `volumeUpdated` and `_lastDayFee.timestamp` is 0 or not same day as `block.timestamp`:
     - Calls `ICCLiquidityTemplate.liquidityDetail` to fetch `xFeesAcc`, `yFeesAcc`.
     - On failure, uses `_lastDayFee.lastDayXFeesAcc`, `_lastDayFee.lastDayYFeesAcc`.
     - Sets `_lastDayFee` with `xFeesAcc`, `yFeesAcc`, and `_floorToMidnight(block.timestamp)`.
  5. Second loop over `updates`:
     - **Balance Update (`updateType=0`)**:
       - `index=0`: Sets `_volumeBalance.xBalance = value`.
       - `index=1`: Sets `_volumeBalance.yBalance = value`.
       - `index=2`: Increments `_volumeBalance.xVolume += value`.
       - `index=3`: Increments `_volumeBalance.yVolume += value`.
     - **Buy Order Update (`updateType=1`)**:
       - `structId=0` (Core):
         - If `_buyOrderCores[index].makerAddress == address(0)`: Creates new order, sets `makerAddress`, `recipientAddress`, `status=1`, pushes `index` to `_pendingBuyOrders` and `_makerPendingOrders[addr]`, updates `_nextOrderId`, emits `OrderUpdated`.
         - If `value=0`: Cancels order, sets `status=0`, calls `removePendingOrder` for `_pendingBuyOrders` and `_makerPendingOrders`, emits `OrderUpdated`.
       - `structId=1` (Pricing): Sets `_buyOrderPricings[index].maxPrice`, `minPrice`.
       - `structId=2` (Amounts):
         - If `pending=0` and `makerAddress != address(0)`: Initializes `pending`, `amountSent`, increases `_volumeBalance.yBalance`, `yVolume`.
         - If `status=1`: Reduces `pending`, increases `filled`, `amountSent`, decreases `_volumeBalance.xBalance`, sets `status` (3 if `pending=0`, else 2), removes from arrays if `pending=0`, emits `OrderUpdated`.
     - **Sell Order Update (`updateType=2`)**:
       - Similar to buy order, but for `_sellOrderCores`, `_sellOrderPricings`, `_sellOrderAmounts`, with `pending` as tokenA, `amountSent` as tokenB, increasing `_volumeBalance.xBalance`, `xVolume`, decreasing `yBalance`.
     - **Historical Update (`updateType=3`)**:
       - Creates `HistoricalData` with `value` (price), current `_volumeBalance`, `block.timestamp`, pushes to `_historicalData`.
  6. Updates `_currentPrice` via `IUniswapV2Pair.getReserves`, computing `reserveB * 1e18 / reserveA` (tokenB/tokenA), or retains `_currentPrice` on failure.
  7. Calls `_updateRegistry(maker)` if `maker != address(0)`.
  8. Calls `globalizeUpdate()` to process the latest order.
  9. Emits `BalancesUpdated` with `_listingId`, `_volumeBalance.xBalance`, `yBalance`.
- **State Changes**:
  - Updates `_volumeBalance`, `_lastDayFee`, `_pendingBuyOrders`, `_pendingSellOrders`, `_makerPendingOrders`, `_historicalData`, `_buyOrderCores`, `_buyOrderPricings`, `_buyOrderAmounts`, `_sellOrderCores`, `_sellOrderPricings`, `_sellOrderAmounts`, `_nextOrderId`, `_currentPrice`.
- **External Interactions**:
  - `ICCLiquidityTemplate.liquidityDetail` (try-catch) for fee updates.
  - `IUniswapV2Pair.getReserves`, `token0` (try-catch) for price update.
  - `ITokenRegistry.initializeTokens` via `_updateRegistry`.
  - `ICCGlobalizer.globalizeOrders` via `globalizeUpdate`.
- **Internal Call Trees**:
  - `_isSameDay(block.timestamp, _lastDayFee.timestamp)`
  - `_floorToMidnight(block.timestamp)`
  - `removePendingOrder(_pendingBuyOrders, index)`, `removePendingOrder(_makerPendingOrders[addr], index)`
  - `_updateRegistry(maker)`
  - `globalizeUpdate()`
- **Gas Considerations**: Scales with `updates.length` (two loops), array operations (`push`, `removePendingOrder`), external calls, and storage updates. Gas limits in `_updateRegistry` (500,000) and `globalizeUpdate` (gasleft/10) mitigate risks.
- **Error Handling**:
  - Reverts if `!_routers[msg.sender]` ("Router only").
  - Reverts if `amounts.pending < u.value` in buy/sell amounts update ("Insufficient pending").
  - Try-catch on external calls, with reverts for `_updateRegistry` and `globalizeUpdate` failures.

#### ssUpdate(PayoutUpdate[] memory payoutUpdates)
- **Purpose**: Creates long or short payout orders for tokenB or tokenA, restricted to routers, used for settlement.
- **Inputs**:
  - `payoutUpdates`: `ICCListing.PayoutUpdate[]` - Array of payout updates with `payoutType` (0: Long, 1: Short), `recipient`, `required` (amount).
- **Outputs**: None.
- **Logic**:
  1. Verifies `msg.sender` is in `_routers`.
  2. Iterates over `payoutUpdates`:
     - **Long Payout (`payoutType=0`)**:
       - Creates `LongPayoutStruct` at `_longPayouts[_nextOrderId]`.
       - Sets `makerAddress`, `recipientAddress` to `recipient`, `required`, `orderId=_nextOrderId`, `status=1`.
       - Pushes `_nextOrderId` to `_longPayoutsByIndex`, `_userPayoutIDs[recipient]`.
       - Emits `PayoutOrderCreated(_nextOrderId, true, 1)`.
       - Increments `_nextOrderId`.
     - **Short Payout (`payoutType=1`)**:
       - Creates `ShortPayoutStruct` at `_shortPayouts[_nextOrderId]`.
       - Sets `makerAddress`, `recipientAddress`, `amount`, `orderId`, `status=1`.
       - Pushes `_nextOrderId` to `_shortPayoutsByIndex`, `_userPayoutIDs[recipient]`.
       - Emits `PayoutOrderCreated(_nextOrderId, false, 1)`.
       - Increments `_nextOrderId`.
- **State Changes**:
  - Updates `_longPayouts`, `_shortPayouts`, `_longPayoutsByIndex`, `_shortPayoutsByIndex`, `_userPayoutIDs`, `_nextOrderId`.
- **External Interactions**: None.
- **Internal Call Trees**: None.
- **Gas Considerations**: Scales with `payoutUpdates.length`, involves multiple storage writes per iteration (mappings, arrays).
- **Error Handling**:
  - Reverts if `!_routers[msg.sender]` ("Router only").

#### transactToken(address token, uint256 amount, address recipient)
- **Purpose**: Transfers ERC20 tokens (`_tokenA` or `_tokenB`) to a recipient, updates balances and volumes, and refreshes price, restricted to routers.
- **Inputs**:
  - `token`: `address` - Token to transfer (`_tokenA` or `_tokenB`).
  - `amount`: `uint256` - Amount to transfer (token decimals).
  - `recipient`: `address` - Recipient address.
- **Outputs**: None.
- **Logic**:
  1. Verifies `msg.sender` is in `_routers`.
  2. Ensures `token` is `_tokenA` or `_tokenB`.
  3. Gets decimals (`_decimalsA` or `_decimalsB`).
  4. Normalizes `amount` to 1e18 precision using `normalize`.
  5. If `token == _tokenA`:
     - Increments `_volumeBalance.xBalance`, `xVolume` by normalized amount.
  6. If `token == _tokenB`:
     - Increments `_volumeBalance.yBalance`, `yVolume`.
  7. Updates `_currentPrice` via `IUniswapV2Pair.getReserves` (tokenB/tokenA, `reserveB * 1e18 / reserveA`), retains `_currentPrice` on failure.
  8. Calls `IERC20(token).transfer(recipient, amount)`, reverts on failure.
  9. Emits `BalancesUpdated`.
- **State Changes**:
  - Updates `_volumeBalance.xBalance`, `xVolume` or `yBalance`, `yVolume`.
  - Updates `_currentPrice`.
- **External Interactions**:
  - `IUniswapV2Pair.getReserves`, `token0` (try-catch).
  - `IERC20.transfer`.
- **Internal Call Trees**:
  - `normalize(amount, decimals)`.
- **Gas Considerations**: External calls (`transfer`, `getReserves`), storage updates, normalization arithmetic.
- **Error Handling**:
  - Reverts if `!_routers[msg.sender]` ("Router only").
  - Reverts if `token != _tokenA && token != _tokenB` ("Invalid token").
  - Reverts if `IERC20.transfer` fails ("Token transfer failed").

#### transactNative(uint256 amount, address recipient)
- **Purpose**: Transfers native ETH if `_tokenA` or `_tokenB` is `address(0)`, updates balances and volumes, and refreshes price, restricted to routers.
- **Inputs**:
  - `amount`: `uint256` - ETH amount to transfer (18 decimals).
  - `recipient`: `address` - Recipient address.
- **Outputs**: None.
- **Logic**:
  1. Verifies `msg.sender` is in `_routers`.
  2. Ensures `_tokenA` or `_tokenB` is `address(0)`.
  3. Normalizes `amount` to 1e18 (identity for ETH, decimals=18).
  4. If `_tokenA == address(0)`:
     - Increments `_volumeBalance.xBalance`, `xVolume`.
  5. If `_tokenB == address(0)`:
     - Increments `_volumeBalance.yBalance`, `yVolume`.
  6. Updates `_currentPrice` via `IUniswapV2Pair.getReserves` (tokenB/tokenA), retains on failure.
  7. Performs low-level `call` to transfer ETH, reverts on failure.
  8. Emits `BalancesUpdated`.
- **State Changes**:
  - Updates `_volumeBalance.xBalance`, `xVolume` or `yBalance`, `yVolume`.
  - Updates `_currentPrice`.
- **External Interactions**:
  - `IUniswapV2Pair.getReserves`, `token0` (try-catch).
  - Low-level `call` for ETH transfer.
- **Internal Call Trees**:
  - `normalize(amount, 18)`.
- **Gas Considerations**: External call (`getReserves`), low-level call, storage updates.
- **Error Handling**:
  - Reverts if `!_routers[msg.sender]` ("Router only").
  - Reverts if `_tokenA != address(0) && _tokenB != address(0)` ("No native token").
  - Reverts if `call` fails ("Native transfer failed").

### Internal Functions
#### normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)
- **Purpose**: Converts an amount from token decimals to 1e18 precision for consistent calculations.
- **External Callers**: `transactToken`, `transactNative`.
- **Inputs**:
  - `amount`: `uint256` - Amount in token decimals.
  - `decimals`: `uint8` - Token decimals (from `_decimalsA`, `_decimalsB`, or 18 for ETH).
- **Outputs**:
  - `normalized`: `uint256` - Amount scaled to 1e18.
- **Logic**:
  1. If `decimals == 18`, returns `amount`.
  2. If `decimals < 18`, multiplies `amount * 10^(18-decimals)`.
  3. If `decimals > 18`, divides `amount / 10^(decimals-18)`.
- **State Changes**: None (pure).
- **External Interactions**: None.
- **Gas Considerations**: Minimal, pure arithmetic (multiplication or division).
- **Error Handling**: None, assumes valid `decimals`.

#### denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)
- **Purpose**: Converts an amount from 1e18 precision to token decimals (inverse of `normalize`).
- **External Callers**: None (available for future use).
- **Inputs**:
  - `amount`: `uint256` - Amount in 1e18 precision.
  - `decimals`: `uint8` - Token decimals.
- **Outputs**:
  - `denormalized`: `uint256` - Amount in token decimals.
- **Logic**:
  1. If `decimals == 18`, returns `amount`.
  2. If `decimals < 18`, divides `amount / 10^(18-decimals)`.
  3. If `decimals > 18`, multiplies `amount * 10^(decimals-18)`.
- **State Changes**: None (pure).
- **External Interactions**: None.
- **Gas Considerations**: Minimal, pure arithmetic.
- **Error Handling**: None.

#### _isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)
- **Purpose**: Checks if two timestamps are on the same day (86400 seconds).
- **External Callers**: `update`.
- **Inputs**:
  - `time1`, `time2`: `uint256` - Timestamps to compare.
- **Outputs**:
  - `sameDay`: `bool` - True if timestamps are on the same day.
- **Logic**:
  1. Divides `time1` and `time2` by 86400, compares results.
- **State Changes**: None (pure).
- **External Interactions**: None.
- **Gas Considerations**: Minimal, pure arithmetic (division, comparison).
- **Error Handling**: None.

#### _floorToMidnight(uint256 timestamp) returns (uint256 midnight)
- **Purpose**: Rounds a timestamp to the start of its day (midnight).
- **External Callers**: `update`.
- **Inputs**:
  - `timestamp`: `uint256` - Timestamp to round.
- **Outputs**:
  - `midnight`: `uint256` - Timestamp at midnight.
- **Logic**:
  1. Divides `timestamp` by 86400, multiplies by 86400.
- **State Changes**: None (pure).
- **External Interactions**: None.
- **Gas Considerations**: Minimal, pure arithmetic.
- **Error Handling**: None.

#### _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)
- **Purpose**: Calculates volume change for tokenA (`isA=true`) or tokenB (`isA=false`) since `startTime`, limited by `maxIterations`.
- **External Callers**: None (available for future use).
- **Inputs**:
  - `isA`: `bool` - True for tokenA (`xVolume`), false for tokenB (`yVolume`).
  - `startTime`: `uint256` - Start timestamp for volume calculation.
  - `maxIterations`: `uint256` - Maximum historical entries to check.
- **Outputs**:
  - `volumeChange`: `uint256` - Volume difference since `startTime`.
- **Logic**:
  1. Gets current volume from `_volumeBalance.xVolume` or `yVolume`.
  2. If `_historicalData` is empty, returns 0.
  3. Iterates `_historicalData` backwards, up to `maxIterations`:
     - If `data.timestamp >= startTime`, returns current volume minus historical volume.
  4. If no matching timestamp or iteration limit reached, uses earliest `_historicalData[0]` volume.
- **State Changes**: None (view).
- **External Interactions**: None.
- **Gas Considerations**: Scales with `_historicalData.length` and `maxIterations`, reads storage array.
- **Error Handling**: None.

#### _updateRegistry(address maker)
- **Purpose**: Updates `ITokenRegistry` with maker’s balances for `_tokenA` and `_tokenB`, called after order updates.
- **External Callers**: `update`.
- **Inputs**:
  - `maker`: `address` - Maker address to update in registry.
- **Outputs**: None.
- **Logic**:
  1. Returns if `_registryAddress` or `maker` is `address(0)`.
  2. Creates dynamic array `tokens` with `_tokenA` and/or `_tokenB` (if non-zero).
  3. Calls `ITokenRegistry.initializeTokens(maker, tokens)` with 500,000 gas limit.
  4. On failure, emits `UpdateRegistryFailed` with `maker`, `tokens`, and decoded reason, then reverts.
  5. Checks gas usage, reverts if exceeds 500,000.
- **State Changes**: None (external contract modifies state).
- **External Interactions**:
  - `ITokenRegistry.initializeTokens` (try-catch).
- **Internal Call Trees**: None.
- **Gas Considerations**: Dynamic array creation, external call with gas limit, gas check.
- **Error Handling**:
  - Emits `UpdateRegistryFailed` and reverts with reason on `initializeTokens` failure.
  - Reverts if gas used > 500,000 ("Registry call out of gas").

#### removePendingOrder(uint256[] storage orders, uint256 orderId)
- **Purpose**: Removes an order ID from a storage array (`_pendingBuyOrders`, `_pendingSellOrders`, `_makerPendingOrders`) using swap-and-pop.
- **External Callers**: `update`.
- **Inputs**:
  - `orders`: `uint256[] storage` - Array to modify.
  - `orderId`: `uint256` - ID to remove.
- **Outputs**: None.
- **Logic**:
  1. Iterates `orders`, finds `orderId`.
  2. Swaps with last element, calls `pop()`.
- **State Changes**: Modifies `orders` array.
- **External Interactions**: None.
- **Gas Considerations**: Scales with `orders.length`, storage array modification (swap and pop).
- **Error Handling**: None (assumes `orderId` exists).

#### globalizeUpdate()
- **Purpose**: Propagates the latest order to `ICCGlobalizer` for global registry updates, called at the end of `update`.
- **External Callers**: `update`.
- **Inputs**: None.
- **Outputs**: None.
- **Logic**:
  1. Returns if `_globalizerAddress` or `_nextOrderId` is 0.
  2. Gets latest `orderId = _nextOrderId - 1`.
  3. Checks `_buyOrderCores[orderId]`: If `makerAddress != address(0)`, sets `maker = makerAddress`, `token = _tokenB` (or `_tokenA` if `_tokenB` is zero).
  4. If no buy order, checks `_sellOrderCores[orderId]`: Sets `maker`, `token = _tokenA` (or `_tokenB` if `_tokenA` is zero).
  5. Returns if no valid order.
  6. Calls `ICCGlobalizer.globalizeOrders(maker, token)` with gas limit `gasleft()/10`.
  7. On failure, reverts with decoded reason.
- **State Changes**: None.
- **External Interactions**:
  - `ICCGlobalizer.globalizeOrders` (try-catch).
- **Internal Call Trees**: None.
- **Gas Considerations**: External call with dynamic gas limit, storage reads for order data.
- **Error Handling**:
  - Reverts with decoded reason on `globalizeOrders` failure.

### View Functions
#### agentView() returns (address agent)
- **Purpose**: Returns the `_agent` address.
- **Logic**: Returns `_agent`.
- **Gas**: Minimal, single storage read.
- **Error Handling**: None.

#### uniswapV2PairView() returns (address pair)
- **Purpose**: Returns the `_uniswapV2Pair` address.
- **Logic**: Returns `_uniswapV2Pair`.
- **Gas**: Minimal, single storage read.
- **Error Handling**: None.

#### prices(uint256) returns (uint256 price)
- **Purpose**: Computes current price (tokenB/tokenA, 1e18) from Uniswap V2 reserves.
- **Logic**:
  1. Calls `IUniswapV2Pair.getReserves` (try-catch).
  2. Maps `_tokenA` to `reserve0` or `reserve1` using `token0`.
  3. Computes `reserveB * 1e18 / reserveA`, returns 0 if `reserveA == 0`.
  4. On failure, returns `_currentPrice`.
- **Gas**: External call, storage read, arithmetic.
- **Error Handling**: Try-catch, falls back to `_currentPrice`.

#### getTokens() returns (address tokenA, address tokenB)
- **Purpose**: Returns `_tokenA`, `_tokenB`.
- **Logic**: Requires at least one non-zero, returns both.
- **Gas**: Minimal, two storage reads.
- **Error Handling**: Reverts if both `_tokenA` and `_tokenB` are `address(0)`.

#### volumeBalances(uint256) returns (uint256 xBalance, uint256 yBalance)
- **Purpose**: Returns `_volumeBalance.xBalance`, `yBalance`.
- **Logic**: Returns struct fields.
- **Gas**: Minimal, storage read.
- **Error Handling**: None.

#### liquidityAddressView() returns (address liquidityAddress)
- **Purpose**: Returns `_liquidityAddress`.
- **Logic**: Returns `_liquidityAddress`.
- **Gas**: Minimal, storage read.
- **Error Handling**: None.

#### tokenA() returns (address token)
- **Purpose**: Returns `_tokenA`.
- **Logic**: Returns `_tokenA`.
- **Gas**: Minimal, storage read.
- **Error Handling**: None.

#### tokenB() returns (address token)
- **Purpose**: Returns `_tokenB`.
- **Logic**: Returns `_tokenB`.
- **Gas**: Minimal, storage read.
- **Error Handling**: None.

#### decimalsA() returns (uint8 decimals)
- **Purpose**: Returns `_decimalsA`.
- **Logic**: Returns `_decimalsA`.
- **Gas**: Minimal, storage read.
- **Error Handling**: None.

#### decimalsB() returns (uint8 decimals)
- **Purpose**: Returns `_decimalsB`.
- **Logic**: Returns `_decimalsB`.
- **Gas**: Minimal, storage read.
- **Error Handling**: None.

#### getListingId() returns (uint256 listingId)
- **Purpose**: Returns `_listingId`.
- **Logic**: Returns `_listingId`.
- **Gas**: Minimal, storage read.
- **Error Handling**: None.

#### getNextOrderId() returns (uint256 nextOrderId)
- **Purpose**: Returns `_nextOrderId`.
- **Logic**: Returns `_nextOrderId`.
- **Gas**: Minimal, storage read.
- **Error Handling**: None.

#### listingVolumeBalancesView() returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume)
- **Purpose**: Returns all `_volumeBalance` fields.
- **Logic**: Returns `xBalance`, `yBalance`, `xVolume`, `yVolume`.
- **Gas**: Minimal, storage read.
- **Error Handling**: None.

#### listingPriceView() returns (uint256 price)
- **Purpose**: Returns `_currentPrice`.
- **Logic**: Returns `_currentPrice`.
- **Gas**: Minimal, storage read.
- **Error Handling**: None.

#### pendingBuyOrdersView() returns (uint256[] memory orderIds)
- **Purpose**: Returns `_pendingBuyOrders`.
- **Logic**: Returns array.
- **Gas**: Scales with array length.
- **Error Handling**: None.

#### pendingSellOrdersView() returns (uint256[] memory orderIds)
- **Purpose**: Returns `_pendingSellOrders`.
- **Logic**: Returns array.
- **Gas**: Scales with array length.
- **Error Handling**: None.

#### makerPendingOrdersView(address maker) returns (uint256[] memory orderIds)
- **Purpose**: Returns `_makerPendingOrders[maker]`.
- **Logic**: Returns array.
- **Gas**: Scales with array length.
- **Error Handling**: None.

#### longPayoutByIndexView() returns (uint256[] memory orderIds)
- **Purpose**: Returns `_longPayoutsByIndex`.
- **Logic**: Returns array.
- **Gas**: Scales with array length.
- **Error Handling**: None.

#### shortPayoutByIndexView() returns (uint256[] memory orderIds)
- **Purpose**: Returns `_shortPayoutsByIndex`.
- **Logic**: Returns array.
- **Gas**: Scales with array length.
- **Error Handling**: None.

#### userPayoutIDsView(address user) returns (uint256[] memory orderIds)
- **Purpose**: Returns `_userPayoutIDs[user]`.
- **Logic**: Returns array.
- **Gas**: Scales with array length.
- **Error Handling**: None.

#### getLongPayout(uint256 orderId) returns (LongPayoutStruct memory payout)
- **Purpose**: Returns `_longPayouts[orderId]`.
- **Logic**: Returns struct.
- **Gas**: Storage read.
- **Error Handling**: None.

#### getShortPayout(uint256 orderId) returns (ShortPayoutStruct memory payout)
- **Purpose**: Returns `_shortPayouts[orderId]`.
- **Logic**: Returns struct.
- **Gas**: Storage read.
- **Error Handling**: None.

#### getBuyOrderCore(uint256 orderId) returns (address makerAddress, address recipientAddress, uint8 status)
- **Purpose**: Returns `_buyOrderCores[orderId]` fields.
- **Logic**: Returns `makerAddress`, `recipientAddress`, `status`.
- **Gas**: Storage read.
- **Error Handling**: None.

#### getBuyOrderPricing(uint256 orderId) returns (uint256 maxPrice, uint256 minPrice)
- **Purpose**: Returns `_buyOrderPricings[orderId]` fields.
- **Logic**: Returns `maxPrice`, `minPrice`.
- **Gas**: Storage read.
- **Error Handling**: None.

#### getBuyOrderAmounts(uint256 orderId) returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Purpose**: Returns `_buyOrderAmounts[orderId]` fields.
- **Logic**: Returns `pending`, `filled`, `amountSent`.
- **Gas**: Storage read.
- **Error Handling**: None.

#### getSellOrderCore(uint256 orderId) returns (address makerAddress, address recipientAddress, uint8 status)
- **Purpose**: Returns `_sellOrderCores[orderId]` fields.
- **Logic**: Returns `makerAddress`, `recipientAddress`, `status`.
- **Gas**: Storage read.
- **Error Handling**: None.

#### getSellOrderPricing(uint256 orderId) returns (uint256 maxPrice, uint256 minPrice)
- **Purpose**: Returns `_sellOrderPricings[orderId]` fields.
- **Logic**: Returns `maxPrice`, `minPrice`.
- **Gas**: Storage read.
- **Error Handling**: None.

#### getSellOrderAmounts(uint256 orderId) returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Purpose**: Returns `_sellOrderAmounts[orderId]` fields.
- **Logic**: Returns `pending`, `filled`, `amountSent`.
- **Gas**: Storage read.
- **Error Handling**: None.

#### getHistoricalDataView(uint256 index) returns (HistoricalData memory data)
- **Purpose**: Returns `_historicalData[index]`.
- **Logic**: Requires `index < _historicalData.length`, returns struct.
- **Gas**: Storage read.
- **Error Handling**: Reverts if `index >= _historicalData.length` ("Invalid index").

#### historicalDataLengthView() returns (uint256 length)
- **Purpose**: Returns `_historicalData.length`.
- **Logic**: Returns length.
- **Gas**: Minimal, storage read.
- **Error Handling**: None.

#### getHistoricalDataByNearestTimestamp(uint256 targetTimestamp) returns (HistoricalData memory data)
- **Purpose**: Returns `_historicalData` entry closest to `targetTimestamp`.
- **Logic**:
  1. Returns empty `HistoricalData` if `_historicalData` is empty.
  2. Iterates `_historicalData`, tracks smallest timestamp difference.
  3. Returns closest entry.
- **Gas**: Scales with `_historicalData.length`.
- **Error Handling**: None.

#### globalizerAddressView() returns (address globalizerAddress)
- **Purpose**: Returns `_globalizerAddress`.
- **Logic**: Returns `_globalizerAddress`.
- **Gas**: Minimal, storage read.
- **Error Handling**: None.

#### makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns up to `maxIterations` pending buy order IDs (`status=1`) for `maker`, starting from `step`.
- **Logic**:
  1. Gets `_makerPendingOrders[maker]`.
  2. Counts valid orders (`_buyOrderCores[i].makerAddress == maker && status == 1`) from `step`, up to `maxIterations`.
  3. Creates array, populates with valid IDs.
- **Gas**: Scales with `_makerPendingOrders[maker].length` and `maxIterations`.
- **Error Handling**: None.

#### makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns up to `maxIterations` pending sell order IDs (`status=1`) for `maker`, starting from `step`.
- **Logic**: Similar to `makerPendingBuyOrdersView`, but checks `_sellOrderCores`.
- **Gas**: Scales with `_makerPendingOrders[maker].length` and `maxIterations`.
- **Error Handling**: None.

#### getFullBuyOrderDetails(uint256 orderId) returns (BuyOrderCore memory core, BuyOrderPricing memory pricing, BuyOrderAmounts memory amounts)
- **Purpose**: Returns all buy order structs for `orderId`.
- **Logic**: Returns `_buyOrderCores[orderId]`, `_buyOrderPricings[orderId]`, `_buyOrderAmounts[orderId]`.
- **Gas**: Multiple storage reads.
- **Error Handling**: None.

#### getFullSellOrderDetails(uint256 orderId) returns (SellOrderCore memory core, SellOrderPricing memory pricing, SellOrderAmounts memory amounts)
- **Purpose**: Returns all sell order structs for `orderId`.
- **Logic**: Returns `_sellOrderCores[orderId]`, `_sellOrderPricings[orderId]`, `_sellOrderAmounts[orderId]`.
- **Gas**: Multiple storage reads.
- **Error Handling**: None.

#### makerOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns up to `maxIterations` order IDs (buy or sell, any status) for `maker`, starting from `step`.
- **Logic**:
  1. Gets `_makerPendingOrders[maker]`.
  2. Returns empty array if `step >= length`.
  3. Returns up to `maxIterations` IDs from `step`.
- **Gas**: Scales with `_makerPendingOrders[maker].length` and `maxIterations`.
- **Error Handling**: None.

## Parameters and Interactions
- **Orders** (`UpdateType`): Defines updates for balances (`updateType=0`), buy orders (`1`), sell orders (`2`), or historical data (`3`). Fields include `structId` (0: Core, 1: Pricing, 2: Amounts), `index` (orderId or balance/volume slot), `value` (amount/price), `addr` (maker), `recipient`, `maxPrice`, `minPrice`, `amountSent` (opposite token sent).
- **Payouts** (`PayoutUpdate`): Specifies `payoutType` (0: Long for tokenB, 1: Short for tokenA), `recipient`, `required` for `ssUpdate`, creating payout orders tracked in `_longPayouts` or `_shortPayouts`.
- **Maker Orders** (`_makerPendingOrders`): Maps maker addresses to arrays of order IDs (buy or sell, any status: 0=cancelled, 1=pending, 2=partially filled, 3=filled). Populated in `update` when created, depopulated when cancelled (`value=0`, `status=0`) or fully filled (`pending=0`, `status=3`).

## Security and Optimization
- **Security**:
  - Router validation (`_routers[msg.sender]`) restricts sensitive functions.
  - No `SafeERC20`, inline assembly, `virtual`/`override`, or reserved keywords.
  - Gas checks in `_updateRegistry` (500,000) and `globalizeUpdate` (gasleft/10) prevent out-of-gas failures.
  - Try-catch in external calls ensures graceful degradation.
  - Setters replace constructor arguments for flexible deployment.
  - No nested calls in struct initialization.
  - `_makerPendingOrders` depopulation prevents stale entries.
- **Optimization**:
  - `removePendingOrder` uses swap-and-pop for array resizing.
  - Normalized amounts (1e18) simplify calculations.
  - `maxIterations` and `step` limit gas in view functions.
  - Single-maker `_updateRegistry` reduces gas.
  - `globalizeUpdate` focuses on latest order, minimizing redundant calls.

## Token Usage
- **Buy Orders**: Input `_tokenB`, output `_tokenA`. `amountSent` tracks `_tokenA` sent. `yBalance` increases on creation, `xBalance` decreases on fill.
- **Sell Orders**: Input `_tokenA`, output `_tokenB`. `amountSent` tracks `_tokenB` sent. `xBalance` increases on creation, `yBalance` decreases on fill.
- **Long Payouts**: Output `_tokenB`, tracked in `LongPayoutStruct.required`.
- **Short Payouts**: Output `_tokenA`, tracked in `ShortPayoutStruct.amount`.
- **Normalization**: Uses `_decimalsA`, `_decimalsB` or `IERC20.decimals` for 1e18 precision.

## Price Clarification
- **_currentPrice**: Updated in `update`, `transactToken`, `transactNative` using Uniswap V2 reserves (tokenB/tokenA, 1e18). Stored for `listingPriceView`.
- **prices(uint256)**: Computes price on-demand from Uniswap V2 reserves (tokenB/tokenA, 1e18), consistent with `_currentPrice`.

## Maker Orders Clarification
- **_makerPendingOrders**: Stores all order IDs (buy or sell, any status). Added in `update` when created, removed via `removePendingOrder` when cancelled or fully filled. Accessible via `makerOrdersView`, filtered by `makerPendingBuyOrdersView`, `makerPendingSellOrdersView` for pending orders (status=1).

## LastDay Initialization
- **Deployment**: `_lastDayFee` is initialized with `lastDayXFeesAcc=0`, `lastDayYFeesAcc=0`, `timestamp=0`.
- **Updates**: Occur in `update` on volume changes if `_lastDayFee.timestamp` is 0 or not same day as `block.timestamp`. Fetches `xFeesAcc`, `yFeesAcc` from `ICCLiquidityTemplate.liquidityDetail`, sets `_lastDayFee` with midnight timestamp.
