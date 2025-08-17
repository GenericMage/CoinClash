# CCGlobalizer Documentation

## Overview
The `CCGlobalizer` contract, implemented in Solidity (^0.8.2), tracks maker orders and depositor liquidity across tokens, listings, and liquidity templates. It integrates with `ICCLiquidityTemplate`, `ICCListingTemplate`, and `ICCAgent` for validation and data retrieval. It uses `Ownable` for agent setting, employs explicit casting, and ensures non-reverting behavior for `globalizeOrders` and `globalizeLiquidity`. View functions use `step` and `maxIterations` for gas-efficient pagination, with structured outputs (`OrderGroup`/`SlotGroup`/`SlotHistoryGroup`) for readability. Amounts are normalized to 1e18 via external contracts. Depopulates inactive liquidity templates while preserving historical snapshots.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.2.7 (Updated 2025-08-17)

**Compatibility**:
- CCLiquidityTemplate.sol (v0.1.1)
- CCListingTemplate.sol (v0.0.10)
- ICCAgent.sol (v0.1.2)

## Interfaces
- **IERC20**: Provides `decimals()` for token normalization.
- **ICCLiquidityTemplate**: Provides `listingAddress` (returns `address`), `userIndexView` (returns `uint256[]`), `getXSlotView`, `getYSlotView` (returns `Slot`), `activeXLiquiditySlotsView`, `activeYLiquiditySlotsView` (returns `uint256[]`).
- **ICCListingTemplate**: Provides `makerPendingBuyOrdersView`, `makerPendingSellOrdersView`, `makerOrdersView` (returns `uint256[]`), `pendingBuyOrdersView`, `pendingSellOrdersView` (returns `uint256[]`), `tokenA`, `tokenB` (returns `address`).
- **ICCAgent**: Provides `isValidListing(address)` (returns `bool isValid`, `ListingDetails`).

## State Variables
- **`agent`**: `address public` - Agent contract address for listing validation, set via `setAgent`.

## Mappings
- **`makerTokensByListing`**: `mapping(address => mapping(address => address[])) public`  
  - **Parameters**: `maker` (address), `listing` (address)  
  - **Returns**: `address[]` (tokens with orders for maker in listing)  
  - **Usage**: Tracks tokens associated with maker orders per listing, updated in `globalizeOrders`.
- **`depositorTokensByLiquidity`**: `mapping(address => mapping(address => address[])) public`  
  - **Parameters**: `depositor` (address), `liquidityTemplate` (address)  
  - **Returns**: `address[]` (tokens provided by depositor in liquidity template)  
  - **Usage**: Tracks tokens for depositor liquidity, updated/depopulated in `globalizeLiquidity`.
- **`makerListings`**: `mapping(address => address[]) public`  
  - **Parameters**: `maker` (address)  
  - **Returns**: `address[]` (listings with orders for maker)  
  - **Usage**: Lists all listings a maker has orders in, updated in `globalizeOrders`.
- **`depositorLiquidityTemplates`**: `mapping(address => address[]) public`  
  - **Parameters**: `depositor` (address)  
  - **Returns**: `address[]` (liquidity templates for depositor)  
  - **Usage**: Lists liquidity templates a depositor provides liquidity for, updated/depopulated in `globalizeLiquidity`.
- **`tokenListings`**: `mapping(address => address[]) public`  
  - **Parameters**: `token` (address)  
  - **Returns**: `address[]` (listings associated with token)  
  - **Usage**: Tracks listings for a token, updated in `globalizeOrders`.
- **`tokenLiquidityTemplates`**: `mapping(address => address[]) public`  
  - **Parameters**: `token` (address)  
  - **Returns**: `address[]` (liquidity templates for token)  
  - **Usage**: Tracks liquidity templates for a token, updated/depopulated in `globalizeLiquidity`.
- **`depositorSlotSnapshots`**: `mapping(address => mapping(address => mapping(uint256 => uint256))) public`  
  - **Parameters**: `depositor` (address), `template` (address), `slotIndex` (uint256)  
  - **Returns**: `uint256` (allocation snapshot)  
  - **Usage**: Stores allocation snapshots for slots, updated in `globalizeLiquidity`, preserved for historical views.
- **`slotStatus`**: `mapping(address => mapping(uint256 => bool)) public`  
  - **Parameters**: `template` (address), `slotIndex` (uint256)  
  - **Returns**: `bool` (true for spent, false for unspent)  
  - **Usage**: Tracks spent/unspent status of slots, updated in `globalizeLiquidity`, used in historical views.

## Structs
- **`OrderGroup`**: Used in order-related view functions.  
  - **Fields**: `listing` (address), `orderIds` (uint256[]).
- **`SlotGroup`**: Used in active liquidity view functions.  
  - **Fields**: `template` (address), `slotIndices` (uint256[]), `isX` (bool[]).
- **`SlotHistoryGroup`**: Used in historical liquidity view functions.  
  - **Fields**: `template` (address), `slotIndices` (uint256[]), `isX` (bool[]), `isSpent` (bool[]).
- **`OrderData`**: Internal struct for managing order data.  
  - **Fields**: `buyIds` (uint256[]), `sellIds` (uint256[]), `totalOrders` (uint256).
- **`SlotData`**: Internal struct for managing slot data.  
  - **Fields**: `slotIndices` (uint256[]), `isX` (bool[]), `totalSlots` (uint256).

## External Functions
### setAgent(address _agent)
- **Behavior**: Sets `agent` address, callable once by owner, emits `AgentSet`. Exits silently if already set or `_agent` is zero.
- **Parameters**: `_agent` (address) - Agent contract address for validation.
- **Restrictions**: Only owner, single-time set.
- **Gas**: Single state write.
- **Interactions**: Emits `AgentSet(address)`.

### globalizeOrders(address maker, address token)
- **Behavior**: Called by valid listings (verified via `ICCAgent.isValidListing`). Updates `makerTokensByListing`, `makerListings`, and `tokenListings` if token matches listing’s `tokenA` or `tokenB`. Exits silently on invalid inputs or failed validation. Emits `OrdersGlobalized`.
- **Parameters**: `maker` (address), `token` (address).
- **Restrictions**: Caller must be a valid listing, `agent` must be set.
- **Gas**: External call to `ICCAgent`, array pushes.
- **Interactions**: Calls `ICCAgent.isValidListing`, updates mappings/arrays, emits `OrdersGlobalized(address maker, address listing, address token)`.

### globalizeLiquidity(address depositor, address token)
- **Behavior**: Called by valid liquidity templates (verified via `ICCLiquidityTemplate.listingAddress` and `ICCAgent.isValidListing`). Fetches slot data via `userIndexView`, stores `allocation` in `depositorSlotSnapshots`, sets `slotStatus` (spent if `allocation == 0`, unspent otherwise). Updates `depositorTokensByLiquidity`, `depositorLiquidityTemplates`, `tokenLiquidityTemplates`. Depopulates `depositorLiquidityTemplates` if no active slots (`allocation > 0`), and `depositorTokensByLiquidity`/`tokenLiquidityTemplates` if no slots for the token are active. Emits `LiquidityGlobalized`.
- **Parameters**: `depositor` (address), `token` (address).
- **Restrictions**: Caller must be a valid liquidity template, `agent` must be set.
- **Gas**: External calls to `ICCLiquidityTemplate`, `ICCAgent`, array pushes/pops, mapping updates.
- **Interactions**: Calls `ICCLiquidityTemplate.listingAddress`, `ICCAgent.isValidListing`, `userIndexView`, `getXSlotView`, `getYSlotView`, updates/depopulates mappings/arrays, emits `LiquidityGlobalized(address depositor, address liquidity, address token, uint256 slotIndex, bool isSpent)`.

### getAllUserActiveOrders(address user, uint256 step, uint256 maxIterations) view returns (OrderGroup[] memory orderGroups)
- **Behavior**: Returns paginated `OrderGroup` arrays for a user’s pending orders across listings from `makerListings`. Uses `_fetchOrderData` to get buy/sell orders via `ICCListingTemplate.makerPendingBuyOrdersView` and `makerPendingSellOrdersView`, combined via `_combineOrderIds`. Returns empty array if `step` exceeds listings length.
- **Parameters**: `user` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `orderGroups` (OrderGroup[] - listing, orderIds).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: Queries `ICCListingTemplate`, calls `_fetchOrderData`, `_combineOrderIds`.

### getAllUserOrdersHistory(address user, uint256 step, uint256 maxIterations) view returns (OrderGroup[] memory orderGroups)
- **Behavior**: Returns paginated `OrderGroup` arrays for all user orders (pending, filled, canceled) across listings from `makerListings`. Uses `_fetchAllOrderData` to get orders via `ICCListingTemplate.makerOrdersView`, combined via `_combineOrderIds`. Returns empty array if `step` exceeds listings length.
- **Parameters**: `user` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `orderGroups` (OrderGroup[] - listing, orderIds).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: Queries `ICCListingTemplate`, calls `_fetchAllOrderData`, `_combineOrderIds`.

### getAllUserTokenActiveOrders(address user, address token, uint256 step, uint256 maxIterations) view returns (OrderGroup[] memory orderGroups)
- **Behavior**: Returns paginated `OrderGroup` arrays for a user’s pending token orders across listings from `makerListings`, filtering by `makerTokensByListing`. Uses `_countValidListings` to size output, `_fetchOrderData` for buy/sell orders, and `_combineOrderIds` to combine. Returns empty array if `step` exceeds listings length.
- **Parameters**: `user` (address), `token` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `orderGroups` (OrderGroup[] - listing, orderIds).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: Queries `ICCListingTemplate`, calls `_countValidListings`, `_fetchOrderData`, `_combineOrderIds`, checks `makerTokensByListing`.

### getAllUserTokenOrdersHistory(address user, address token, uint256 step, uint256 maxIterations) view returns (OrderGroup[] memory orderGroups)
- **Behavior**: Returns paginated `OrderGroup` arrays for all user token orders (pending, filled, canceled) across listings from `makerListings`, filtering by `makerTokensByListing`. Uses `_countValidListings` to size output, `_fetchAllOrderData` for orders, and `_combineOrderIds` to combine. Returns empty array if `step` exceeds listings length.
- **Parameters**: `user` (address), `token` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `orderGroups` (OrderGroup[] - listing, orderIds).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: Queries `ICCListingTemplate`, calls `_countValidListings`, `_fetchAllOrderData`, `_combineOrderIds`, checks `makerTokensByListing`.

### getAllTokenOrders(address token, uint256 step, uint256 maxIterations) view returns (OrderGroup[] memory orderGroups)
- **Behavior**: Returns paginated `OrderGroup` arrays for a token’s pending orders across listings from `tokenListings`. Uses `_fetchTokenOrderData` for buy/sell orders via `ICCListingTemplate.pendingBuyOrdersView` and `pendingSellOrdersView`, combined via `_combineOrderIds`. Returns empty array if `step` exceeds listings length.
- **Parameters**: `token` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `orderGroups` (OrderGroup[] - listing, orderIds).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: Queries `ICCListingTemplate`, calls `_fetchTokenOrderData`, `_combineOrderIds`.

### getAllListingOrders(address listing, uint256 step, uint256 maxIterations) view returns (OrderGroup memory orderGroup)
- **Behavior**: Returns a single `OrderGroup` for a listing’s pending orders, fetching buy/sell orders via `_fetchListingOrderData` (using `ICCListingTemplate.pendingBuyOrdersView` and `pendingSellOrdersView`). Returns empty group if `step` exceeds total orders.
- **Parameters**: `listing` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `orderGroup` (OrderGroup - listing, orderIds).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: Queries `ICCListingTemplate`, calls `_fetchListingOrderData`.

### getAllUserActiveLiquidity(address user, uint256 step, uint256 maxIterations) view returns (SlotGroup[] memory slotGroups)
- **Behavior**: Returns paginated `SlotGroup` arrays for a user’s active liquidity slots (`allocation > 0`) across templates from `depositorLiquidityTemplates`. Uses `_fetchSlotData` to get indices via `ICCLiquidityTemplate.userIndexView` and validate slots with `getXSlotView`/`getYSlotView`. Returns empty array if `step` exceeds templates length.
- **Parameters**: `user` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `slotGroups` (SlotGroup[] - template, slotIndices, isX).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Interactions**: Queries `ICCLiquidityTemplate`, calls `_fetchSlotData`.

### getAllUserLiquidityHistory(address user, uint256 step, uint256 maxIterations) view returns (SlotHistoryGroup[] memory slotGroups)
- **Behavior**: Returns paginated `SlotHistoryGroup` arrays for a user’s historical liquidity slots (including spent/unspent) across templates from `depositorLiquidityTemplates`. Uses `_fetchHistoricalSlotData` to get indices from `depositorSlotSnapshots`, validate Y slots with `getYSlotView`, and retrieve snapshots/status from `depositorSlotSnapshots`/`slotStatus`. Returns empty array if `step` exceeds templates length.
- **Parameters**: `user` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `slotGroups` (SlotHistoryGroup[] - template, slotIndices, isX, isSpent).
- **Gas**: External calls to `ICCLiquidityTemplate` for Y slots, array allocation.
- **Interactions**: Queries `depositorSlotSnapshots`, `slotStatus`, calls `_fetchHistoricalSlotData`.

### getAllUserTokenActiveLiquidity(address user, address token, uint256 step, uint256 maxIterations) view returns (SlotGroup[] memory slotGroups)
- **Behavior**: Returns paginated `SlotGroup` arrays for a user’s active token liquidity slots (`allocation > 0`) across templates from `depositorLiquidityTemplates`, filtering by `depositorTokensByLiquidity`. Uses `_countValidTemplates` to size output, `_fetchSlotData` for indices and slot validation. Returns empty array if `step` exceeds templates length.
- **Parameters**: `user` (address), `token` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `slotGroups` (SlotGroup[] - template, slotIndices, isX).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Interactions**: Queries `ICCLiquidityTemplate`, calls `_countValidTemplates`, `_fetchSlotData`, checks `depositorTokensByLiquidity`.

### getAllUserTokenLiquidityHistory(address user, address token, uint256 step, uint256 maxIterations) view returns (SlotHistoryGroup[] memory slotGroups)
- **Behavior**: Returns paginated `SlotHistoryGroup` arrays for a user’s historical token liquidity slots (including spent/unspent) across templates from `depositorLiquidityTemplates`, filtering by `depositorTokensByLiquidity`. Uses `_countValidTemplates` to size output, `_fetchHistoricalSlotData` for indices, snapshots, and status from `depositorSlotSnapshots`/`slotStatus`. Returns empty array if `step` exceeds templates length.
- **Parameters**: `user` (address), `token` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `slotGroups` (SlotHistoryGroup[] - template, slotIndices, isX, isSpent).
- **Gas**: External calls to `ICCLiquidityTemplate` for Y slots, array allocation.
- **Interactions**: Queries `depositorSlotSnapshots`, `slotStatus`, calls `_countValidTemplates`, `_fetchHistoricalSlotData`, checks `depositorTokensByLiquidity`.

### getAllTokenLiquidity(address token, uint256 step, uint256 maxIterations) view returns (SlotGroup[] memory slotGroups)
- **Behavior**: Returns paginated `SlotGroup` arrays for a token’s active liquidity slots across templates from `tokenLiquidityTemplates`. Uses `_fetchTokenSlotData` to get slots via `ICCLiquidityTemplate.activeXLiquiditySlotsView` and `activeYLiquiditySlotsView`, validated with `getXSlotView`/`getYSlotView`. Returns empty array if `step` exceeds templates length.
- **Parameters**: `token` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `slotGroups` (SlotGroup[] - template, slotIndices, isX).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Interactions**: Queries `ICCLiquidityTemplate`, calls `_fetchTokenSlotData`.

### getAllTemplateLiquidity(address template, uint256 step, uint256 maxIterations) view returns (SlotGroup memory slotGroup)
- **Behavior**: Returns a single `SlotGroup` for a template’s active liquidity slots, fetching slots via `_fetchTemplateSlotData` (using `ICCLiquidityTemplate.activeXLiquiditySlotsView` and `activeYLiquiditySlotsView`, validated with `getXSlotView`/`getYSlotView`). Returns empty group if `step` exceeds total slots.
- **Parameters**: `template` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `slotGroup` (SlotGroup - template, slotIndices, isX).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Interactions**: Queries `ICCLiquidityTemplate`, calls `_fetchTemplateSlotData`.

## Internal Functions
### isInArray(address[] memory array, address element) pure returns (bool)
- **Behavior**: Checks if an address exists in an array.
- **Parameters**: `array` (address[]), `element` (address).
- **Returns**: `bool`.
- **Gas**: Loop over array length.
- **Called By**: `globalizeOrders`, `globalizeLiquidity`, `_countValidListings`, `_countValidTemplates`.

### removeFromArray(address[] storage array, address element)
- **Behavior**: Removes an address from a storage array by swapping with the last element and popping.
- **Parameters**: `array` (address[] storage), `element` (address).
- **Gas**: Loop over array length, state write.
- **Called By**: `globalizeLiquidity`.

### _fetchOrderData(address listing, address user) view returns (OrderData memory)
- **Behavior**: Fetches pending buy/sell orders for a user in a listing via `ICCListingTemplate.makerPendingBuyOrdersView` and `makerPendingSellOrdersView`.
- **Parameters**: `listing` (address), `user` (address).
- **Returns**: `OrderData` (buyIds, sellIds, totalOrders).
- **Gas**: External calls to `ICCListingTemplate`.
- **Called By**: `getAllUserActiveOrders`, `getAllUserTokenActiveOrders`.

### _fetchAllOrderData(address listing, address user) view returns (OrderData memory)
- **Behavior**: Fetches all orders (pending, filled, canceled) for a user in a listing via `ICCListingTemplate.makerOrdersView`.
- **Parameters**: `listing` (address), `user` (address).
- **Returns**: `OrderData` (buyIds, sellIds, totalOrders).
- **Gas**: External calls to `ICCListingTemplate`.
- **Called By**: `getAllUserOrdersHistory`, `getAllUserTokenOrdersHistory`.

### _combineOrderIds(OrderData memory data) pure returns (uint256[] memory)
- **Behavior**: Combines buy/sell order IDs into a single array.
- **Parameters**: `data` (OrderData).
- **Returns**: `uint256[]` (combined order IDs).
- **Gas**: Array allocation, loops.
- **Called By**: `getAllUserActiveOrders`, `getAllUserOrdersHistory`, `getAllUserTokenActiveOrders`, `getAllUserTokenOrdersHistory`, `getAllTokenOrders`.

### _countValidListings(address user, address token, uint256 step, uint256 maxIterations) view returns (uint256)
- **Behavior**: Counts listings in `makerListings` where `makerTokensByListing` includes the token.
- **Parameters**: `user` (address), `token` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `uint256` (valid listing count).
- **Gas**: Loop over listings, array checks.
- **Called By**: `getAllUserTokenActiveOrders`, `getAllUserTokenOrdersHistory`.

### _fetchTokenOrderData(address listing) view returns (OrderData memory)
- **Behavior**: Fetches all pending buy/sell orders for a listing via `ICCListingTemplate.pendingBuyOrdersView` and `pendingSellOrdersView`.
- **Parameters**: `listing` (address).
- **Returns**: `OrderData` (buyIds, sellIds, totalOrders).
- **Gas**: External calls to `ICCListingTemplate`.
- **Called By**: `getAllTokenOrders`.

### _fetchListingOrderData(address listing, uint256 step, uint256 maxIterations) view returns (OrderData memory)
- **Behavior**: Fetches paginated pending buy/sell orders for a listing via `ICCListingTemplate.pendingBuyOrdersView` and `pendingSellOrdersView`.
- **Parameters**: `listing` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `OrderData` (combinedIds, empty sellIds, totalOrders).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Called By**: `getAllListingOrders`.

### _fetchSlotData(address template, address user) view returns (SlotData memory)
- **Behavior**: Fetches user’s active liquidity slot indices from `ICCLiquidityTemplate.userIndexView`, validates slots with `getXSlotView`/`getYSlotView` for `allocation > 0`.
- **Parameters**: `template` (address), `user` (address).
- **Returns**: `SlotData` (slotIndices, isX, totalSlots).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Called By**: `getAllUserActiveLiquidity`, `getAllUserTokenActiveLiquidity`.

### _fetchHistoricalSlotData(address template, address user) view returns (SlotData memory, bool[] memory isSpent)
- **Behavior**: Fetches user’s historical liquidity slot indices from `depositorSlotSnapshots`, validates Y slots with `getYSlotView` for active slots, and retrieves snapshots/status from `depositorSlotSnapshots`/`slotStatus`. Uses a fixed iteration cap (1000) for gas safety.
- **Parameters**: `template` (address), `user` (address).
- **Returns**: `SlotData` (slotIndices, isX, totalSlots), `isSpent` (bool[]).
- **Gas**: External calls to `ICCLiquidityTemplate` for Y slots, array allocation.
- **Called By**: `getAllUserLiquidityHistory`, `getAllUserTokenLiquidityHistory`.

### _countValidTemplates(address user, address token, uint256 step, uint256 maxIterations) view returns (uint256)
- **Behavior**: Counts templates in `depositorLiquidityTemplates` where `depositorTokensByLiquidity` includes the token.
- **Parameters**: `user` (address), `token` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `uint256` (valid template count).
- **Gas**: Loop over templates, array checks.
- **Called By**: `getAllUserTokenActiveLiquidity`, `getAllUserTokenLiquidityHistory`.

### _fetchTokenSlotData(address template) view returns (SlotData memory)
- **Behavior**: Fetches all active slots for a template via `ICCLiquidityTemplate.activeXLiquiditySlotsView` and `activeYLiquiditySlotsView`, validated with `getXSlotView`/`getYSlotView`.
- **Parameters**: `template` (address).
- **Returns**: `SlotData` (slotIndices, isX, totalSlots).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Called By**: `getAllTokenLiquidity`.

### _fetchTemplateSlotData(address template, uint256 step, uint256 maxIterations) view returns (SlotData memory)
- **Behavior**: Fetches paginated active slots for a template via `ICCLiquidityTemplate.activeXLiquiditySlotsView` and `activeYLiquiditySlotsView`, validated with `getXSlotView`/`getYSlotView`.
- **Parameters**: `template` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `SlotData` (slotIndices, isX, totalSlots).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Called By**: `getAllTemplateLiquidity`.

## Additional Details
- **Decimal Handling**: Relies on `ICCListingTemplate` and `ICCLiquidityTemplate` for normalization to 1e18.
- **Gas Optimization**: Uses `step` and `maxIterations` for pagination. Avoids inline assembly, uses high-level Solidity for array operations. Call tree structure in view functions reduces stack usage. Historical views use fixed iteration cap (1000) for gas safety.
- **Events**: `AgentSet(address agent)`, `OrdersGlobalized(address maker, address listing, address token)`, `LiquidityGlobalized(address depositor, address liquidity, address token, uint256 slotIndex, bool isSpent)`.
- **Safety**:
  - Explicit casting for interface calls.
  - Try-catch for external calls in `globalizeLiquidity` with silent exits.
  - Public mappings accessed directly in view functions.
  - No reserved keywords, no `virtual`/`override`.
  - Non-reverting `globalizeOrders` and `globalizeLiquidity`.
  - Depopulates `depositorLiquidityTemplates`, `depositorTokensByLiquidity`, `tokenLiquidityTemplates` for inactive slots while preserving historical snapshots.
- **Verification**: Validates listings via `ICCAgent.isValidListing`, liquidity templates via `ICCLiquidityTemplate.listingAddress` and `ICCAgent.isValidListing`.
- **Interactions**:
  - `setAgent`: Owner-only, sets `agent`.
  - `globalizeOrders`: Called by listings, verifies via `ICCAgent`, updates mappings, emits event.
  - `globalizeLiquidity`: Called by liquidity templates, verifies via `ICCLiquidityTemplate` and `ICCAgent`, updates/depopulates mappings, stores snapshots, sets status, emits event.
  - Order view functions: Query `ICCListingTemplate`, use internal helpers for data processing.
  - Liquidity view functions: Query `ICCLiquidityTemplate` for active data, `depositorSlotSnapshots`/`slotStatus` for historical data; active views return live data, historical views include snapshots/status.
