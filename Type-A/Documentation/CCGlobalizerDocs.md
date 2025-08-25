# CCGlobalizer Documentation

## Overview
The `CCGlobalizer` contract, implemented in Solidity (^0.8.2), tracks maker orders and depositor liquidity across tokens, listings, and liquidity templates. It integrates with `ICCLiquidityTemplate`, `ICCListingTemplate`, and `ICCAgent` for validation and data retrieval. It uses `Ownable` for agent setting, employs explicit casting, and ensures non-reverting behavior for `globalizeOrders` and `globalizeLiquidity` with detailed failure events. View functions use `step` and `maxIterations` for gas-efficient pagination, with structured outputs (`OrderGroup`/`SlotGroup`/`SlotHistoryGroup`) for readability. Amounts are normalized to 1e18 via external contracts. Depopulates inactive liquidity templates while preserving historical snapshots.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.2.8 (Updated 2025-08-25)

**Compatibility**:
- CCLiquidityTemplate.sol (v0.1.4)
- CCListingTemplate.sol (v0.2.7)
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

## Events
- **`AgentSet(address indexed agent)`**: Emitted when `agent` is set via `setAgent`.
- **`OrdersGlobalized(address indexed maker, address indexed listing, address indexed token)`**: Emitted on successful `globalizeOrders` call.
- **`LiquidityGlobalized(address indexed depositor, address indexed liquidity, address indexed token, uint256 slotIndex, bool isSpent)`**: Emitted for each slot in `globalizeLiquidity` with allocation and status.
- **`GlobalizeLiquidityFailed(address indexed depositor, address indexed liquidity, address indexed token, string reason)`**: Emitted on `globalizeLiquidity` failure (e.g., invalid inputs, failed external calls).
- **`GlobalizeOrdersFailed(address indexed maker, address indexed listing, address indexed token, string reason)`**: Emitted on `globalizeOrders` failure (e.g., invalid inputs, listing mismatch).

## External Functions
### setAgent(address _agent)
- **Behavior**: Sets `agent` address, callable once by owner. Emits `AgentSet` on success, or `GlobalizeOrdersFailed` if already set or `_agent` is zero.
- **Parameters**: `_agent` (address) - Agent contract address for validation.
- **Restrictions**: Only owner, single-time set.
- **Gas**: Single state write.
- **Interactions**: 
  - Updates `agent` state variable.
  - Emits `AgentSet(address)` or `GlobalizeOrdersFailed(address(0), address(0), address(0), string)`.

### globalizeOrders(address maker, address token)
- **Behavior**: Called by valid listings (verified via `ICCAgent.isValidListing`). Validates `agent`, `maker`, `token`, and listing/token match. Updates `makerTokensByListing`, `makerListings`, `tokenListings` if valid. Emits `OrdersGlobalized` on success, or `GlobalizeOrdersFailed` with reason (e.g., "Agent not set", "Invalid maker address", "Invalid listing", "Token not in listing").
- **Parameters**: 
  - `maker` (address): Order maker.
  - `token` (address): Token in listing.
- **Restrictions**: Caller must be a valid listing, `agent` must be set.
- **Gas**: External call to `ICCAgent`, array pushes, mapping updates.
- **Interactions**: 
  - Calls `ICCAgent.isValidListing` to verify listing and token match.
  - Calls `isInArray` to check for duplicates in `makerTokensByListing`, `makerListings`, `tokenListings`.
  - Updates `makerTokensByListing`, `makerListings`, `tokenListings`.
  - Emits `OrdersGlobalized(address maker, address listing, address token)` or `GlobalizeOrdersFailed(address maker, address listing, address token, string reason)`.

### globalizeLiquidity(address depositor, address token)
- **Behavior**: Called by valid liquidity templates (verified via `ICCLiquidityTemplate.listingAddress` and `ICCAgent.isValidListing`). Validates `agent`, `depositor`, `token`, listing, and token match. Fetches slot indices via `userIndexView`, validates slots via `getXSlotView`/`getYSlotView`, stores `allocation` in `depositorSlotSnapshots`, sets `slotStatus` (spent if `allocation == 0`). Updates `depositorTokensByLiquidity`, `depositorLiquidityTemplates`, `tokenLiquidityTemplates`. Depopulates mappings if no active slots. Emits `LiquidityGlobalized` per slot, or `GlobalizeLiquidityFailed` with reason (e.g., "Agent not set", "Invalid depositor address", "Failed to fetch user indices").
- **Parameters**: 
  - `depositor` (address): Liquidity provider.
  - `token` (address): Token in liquidity template.
- **Restrictions**: Caller must be a valid liquidity template, `agent` must be set.
- **Gas**: External calls to `ICCLiquidityTemplate`, `ICCAgent`, array pushes/pops, mapping updates.
- **Interactions**: 
  - Calls `ICCLiquidityTemplate.listingAddress` to get listing address.
  - Calls `ICCAgent.isValidListing` to verify listing and liquidity template match.
  - Calls `ICCLiquidityTemplate.userIndexView`, `getXSlotView`, `getYSlotView` to fetch slot data.
  - Calls `isInArray` to check for duplicates in `depositorTokensByLiquidity`, `depositorLiquidityTemplates`, `tokenLiquidityTemplates`.
  - Calls `removeFromArray` to depopulate `depositorLiquidityTemplates`, `depositorTokensByLiquidity`, `tokenLiquidityTemplates` if no active slots.
  - Updates `depositorSlotSnapshots`, `slotStatus`, `depositorTokensByLiquidity`, `depositorLiquidityTemplates`, `tokenLiquidityTemplates`.
  - Emits `LiquidityGlobalized(address depositor, address liquidity, address token, uint256 slotIndex, bool isSpent)` or `GlobalizeLiquidityFailed(address depositor, address liquidity, address token, string reason)`.

### getAllUserActiveOrders(address user, uint256 step, uint256 maxIterations) view returns (OrderGroup[] memory orderGroups)
- **Behavior**: Returns paginated `OrderGroup` arrays for a user’s pending orders across listings from `makerListings`. Returns empty array if `step` exceeds listings length.
- **Parameters**: 
  - `user` (address): Order maker.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum listings to process.
- **Returns**: `orderGroups` (OrderGroup[] - listing, orderIds).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: 
  - Queries `makerListings` for user’s listings.
  - Calls `_fetchOrderData` to get pending buy/sell orders.
  - Calls `_combineOrderIds` to merge order IDs.

### getAllUserOrdersHistory(address user, uint256 step, uint256 maxIterations) view returns (OrderGroup[] memory orderGroups)
- **Behavior**: Returns paginated `OrderGroup` arrays for all user orders (pending, filled, canceled) across listings from `makerListings`. Returns empty array if `step` exceeds listings length.
- **Parameters**: 
  - `user` (address): Order maker.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum listings to process.
- **Returns**: `orderGroups` (OrderGroup[] - listing, orderIds).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: 
  - Queries `makerListings` for user’s listings.
  - Calls `_fetchAllOrderData` to get all orders.
  - Calls `_combineOrderIds` to merge order IDs.

### getAllUserTokenActiveOrders(address user, address token, uint256 step, uint256 maxIterations) view returns (OrderGroup[] memory orderGroups)
- **Behavior**: Returns paginated `OrderGroup` arrays for a user’s pending token orders across listings from `makerListings`, filtering by `makerTokensByListing`. Returns empty array if `step` exceeds listings length.
- **Parameters**: 
  - `user` (address): Order maker.
  - `token` (address): Token to filter orders.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum listings to process.
- **Returns**: `orderGroups` (OrderGroup[] - listing, orderIds).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: 
  - Queries `makerListings` and `makerTokensByListing` for valid listings.
  - Calls `_countValidListings` to size output array.
  - Calls `_fetchOrderData` to get pending orders.
  - Calls `_combineOrderIds` to merge order IDs.

### getAllUserTokenOrdersHistory(address user, address token, uint256 step, uint256 maxIterations) view returns (OrderGroup[] memory orderGroups)
- **Behavior**: Returns paginated `OrderGroup` arrays for all user token orders (pending, filled, canceled) across listings from `makerListings`, filtering by `makerTokensByListing`. Returns empty array if `step` exceeds listings length.
- **Parameters**: 
  - `user` (address): Order maker.
  - `token` (address): Token to filter orders.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum listings to process.
- **Returns**: `orderGroups` (OrderGroup[] - listing, orderIds).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: 
  - Queries `makerListings` and `makerTokensByListing` for valid listings.
  - Calls `_countValidListings` to size output array.
  - Calls `_fetchAllOrderData` to get all orders.
  - Calls `_combineOrderIds` to merge order IDs.

### getAllTokenOrders(address token, uint256 step, uint256 maxIterations) view returns (OrderGroup[] memory orderGroups)
- **Behavior**: Returns paginated `OrderGroup` arrays for a token’s pending orders across listings from `tokenListings`. Returns empty array if `step` exceeds listings length.
- **Parameters**: 
  - `token` (address): Token to filter orders.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum listings to process.
- **Returns**: `orderGroups` (OrderGroup[] - listing, orderIds).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: 
  - Queries `tokenListings` for token’s listings.
  - Calls `_fetchTokenOrderData` to get pending orders.
  - Calls `_combineOrderIds` to merge order IDs.

### getAllListingOrders(address listing, uint256 step, uint256 maxIterations) view returns (OrderGroup memory orderGroup)
- **Behavior**: Returns a single `OrderGroup` for a listing’s pending orders. Returns empty group if `step` exceeds total orders.
- **Parameters**: 
  - `listing` (address): Listing to query.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum orders to process.
- **Returns**: `orderGroup` (OrderGroup - listing, orderIds).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: 
  - Calls `_fetchListingOrderData` to get pending orders.

### getAllUserActiveLiquidity(address user, uint256 step, uint256 maxIterations) view returns (SlotGroup[] memory slotGroups)
- **Behavior**: Returns paginated `SlotGroup` arrays for a user’s active liquidity slots (`allocation > 0`) across templates from `depositorLiquidityTemplates`. Returns empty array if `step` exceeds templates length.
- **Parameters**: 
  - `user` (address): Liquidity depositor.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum templates to process.
- **Returns**: `slotGroups` (SlotGroup[] - template, slotIndices, isX).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Interactions**: 
  - Queries `depositorLiquidityTemplates` for user’s templates.
  - Calls `_fetchSlotData` to get active slots.

### getAllUserLiquidityHistory(address user, uint256 step, uint256 maxIterations) view returns (SlotHistoryGroup[] memory slotGroups)
- **Behavior**: Returns paginated `SlotHistoryGroup` arrays for a user’s historical liquidity slots (including spent/unspent) across templates from `depositorLiquidityTemplates`. Returns empty array if `step` exceeds templates length.
- **Parameters**: 
  - `user` (address): Liquidity depositor.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum templates to process.
- **Returns**: `slotGroups` (SlotHistoryGroup[] - template, slotIndices, isX, isSpent).
- **Gas**: External calls to `ICCLiquidityTemplate` for Y slots, array allocation.
- **Interactions**: 
  - Queries `depositorSlotSnapshots` and `slotStatus` for historical data.
  - Calls `_fetchHistoricalSlotData` to get slot indices and status.

### getAllUserTokenActiveLiquidity(address user, address token, uint256 step, uint256 maxIterations) view returns (SlotGroup[] memory slotGroups)
- **Behavior**: Returns paginated `SlotGroup` arrays for a user’s active token liquidity slots (`allocation > 0`) across templates from `depositorLiquidityTemplates`, filtering by `depositorTokensByLiquidity`. Returns empty array if `step` exceeds templates length.
- **Parameters**: 
  - `user` (address): Liquidity depositor.
  - `token` (address): Token to filter liquidity.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum templates to process.
- **Returns**: `slotGroups` (SlotGroup[] - template, slotIndices, isX).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Interactions**: 
  - Queries `depositorLiquidityTemplates` and `depositorTokensByLiquidity` for valid templates.
  - Calls `_countValidTemplates` to size output array.
  - Calls `_fetchSlotData` to get active slots.

### getAllUserTokenLiquidityHistory(address user, address token, uint256 step, uint256 maxIterations) view returns (SlotHistoryGroup[] memory slotGroups)
- **Behavior**: Returns paginated `SlotHistoryGroup` arrays for a user’s historical token liquidity slots (including spent/unspent) across templates from `depositorLiquidityTemplates`, filtering by `depositorTokensByLiquidity`. Returns empty array if `step` exceeds templates length.
- **Parameters**: 
  - `user` (address): Liquidity depositor.
  - `token` (address): Token to filter liquidity.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum templates to process.
- **Returns**: `slotGroups` (SlotHistoryGroup[] - template, slotIndices, isX, isSpent).
- **Gas**: External calls to `ICCLiquidityTemplate` for Y slots, array allocation.
- **Interactions**: 
  - Queries `depositorLiquidityTemplates`, `depositorTokensByLiquidity`, `depositorSlotSnapshots`, and `slotStatus`.
  - Calls `_countValidTemplates` to size output array.
  - Calls `_fetchHistoricalSlotData` to get slot indices and status.

### getAllTokenLiquidity(address token, uint256 step, uint256 maxIterations) view returns (SlotGroup[] memory slotGroups)
- **Behavior**: Returns paginated `SlotGroup` arrays for a token’s active liquidity slots across templates from `tokenLiquidityTemplates`. Returns empty array if `step` exceeds templates length.
- **Parameters**: 
  - `token` (address): Token to filter liquidity.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum templates to process.
- **Returns**: `slotGroups` (SlotGroup[] - template, slotIndices, isX).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Interactions**: 
  - Queries `tokenLiquidityTemplates` for token’s templates.
  - Calls `_fetchTokenSlotData` to get active slots.

### getAllTemplateLiquidity(address template, uint256 step, uint256 maxIterations) view returns (SlotGroup memory slotGroup)
- **Behavior**: Returns a single `SlotGroup` for a template’s active liquidity slots. Returns empty group if `step` exceeds total slots.
- **Parameters**: 
  - `template` (address): Liquidity template to query.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum slots to process.
- **Returns**: `slotGroup` (SlotGroup - template, slotIndices, isX).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Interactions**: 
  - Calls `_fetchTemplateSlotData` to get active slots.

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
- **Behavior**: Fetches pending buy/sell orders via `ICCListingTemplate.makerPendingBuyOrdersView` and `makerPendingSellOrdersView`.
- **Parameters**: `listing` (address), `user` (address).
- **Returns**: `OrderData` (buyIds, sellIds, totalOrders).
- **Gas**: External calls to `ICCListingTemplate`.
- **Called By**: `getAllUserActiveOrders`, `getAllUserTokenActiveOrders`.

### _fetchAllOrderData(address listing, address user) view returns (OrderData memory)
- **Behavior**: Fetches all orders (pending, filled, canceled) via `ICCListingTemplate.makerOrdersView`.
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
- **Behavior**: Fetches all pending buy/sell orders via `ICCListingTemplate.pendingBuyOrdersView` and `pendingSellOrdersView`.
- **Parameters**: `listing` (address).
- **Returns**: `OrderData` (buyIds, sellIds, totalOrders).
- **Gas**: External calls to `ICCListingTemplate`.
- **Called By**: `getAllTokenOrders`.

### _fetchListingOrderData(address listing, uint256 step, uint256 maxIterations) view returns (OrderData memory)
- **Behavior**: Fetches paginated pending buy/sell orders via `ICCListingTemplate.pendingBuyOrdersView` and `pendingSellOrdersView`.
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
- **Behavior**: Fetches user’s historical liquidity slot indices from `depositorSlotSnapshots`, validates Y slots with `getYSlotView`, retrieves snapshots/status from `depositorSlotSnapshots`/`slotStatus`. Uses a fixed iteration cap (1000) for gas safety.
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
- **Behavior**: Fetches all active slots via `ICCLiquidityTemplate.activeXLiquiditySlotsView` and `activeYLiquiditySlotsView`, validated with `getXSlotView`/`getYSlotView`.
- **Parameters**: `template` (address).
- **Returns**: `SlotData` (slotIndices, isX, totalSlots).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Called By**: `getAllTokenLiquidity`.

### _fetchTemplateSlotData(address template, uint256 step, uint256 maxIterations) view returns (SlotData memory)
- **Behavior**: Fetches paginated active slots via `ICCLiquidityTemplate.activeXLiquiditySlotsView` and `activeYLiquiditySlotsView`, validated with `getXSlotView`/`getYSlotView`.
- **Parameters**: `template` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `SlotData` (slotIndices, isX, totalSlots).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Called By**: `getAllTemplateLiquidity`.

## Additional Details
- **Decimal Handling**: Relies on `ICCListingTemplate` and `ICCLiquidityTemplate` for normalization to 1e18.
- **Gas Optimization**: Uses `step` and `maxIterations` for pagination. Avoids inline assembly, uses high-level Solidity for array operations. Call tree structure in view functions reduces stack usage. Historical views use fixed iteration cap (1000) for gas safety.
- **Safety**:
  - Explicit casting for interface calls.
  - Try-catch for external calls in `globalizeLiquidity` with failure events.
  - Public mappings accessed directly in view functions.
  - No reserved keywords, no `virtual`/`override`.
  - Non-reverting `globalizeOrders` and `globalizeLiquidity` with `GlobalizeOrdersFailed` and `GlobalizeLiquidityFailed` events.
  - Depopulates `depositorLiquidityTemplates`, `depositorTokensByLiquidity`, `tokenLiquidityTemplates` for inactive slots while preserving historical snapshots.
- **Verification**: Validates listings via `ICCAgent.isValidListing`, liquidity templates via `ICCLiquidityTemplate.listingAddress` and `ICCAgent.isValidListing`.
- **Interactions**:
  - `setAgent`: Owner-only, sets `agent`, emits `AgentSet` or `GlobalizeOrdersFailed`.
  - `globalizeOrders`: Called by listings, verifies via `ICCAgent`, updates mappings, emits `OrdersGlobalized` or `GlobalizeOrdersFailed`.
  - `globalizeLiquidity`: Called by liquidity templates, verifies via `ICCLiquidityTemplate` and `ICCAgent`, updates/depopulates mappings, stores snapshots, sets status, emits `LiquidityGlobalized` or `GlobalizeLiquidityFailed`.
  - Order view functions: Query `ICCListingTemplate`, use `_fetchOrderData`, `_fetchAllOrderData`, `_combineOrderIds`, `_countValidListings`.
  - Liquidity view functions: Query `ICCLiquidityTemplate` for active data, `depositorSlotSnapshots`/`slotStatus` for historical data; use `_fetchSlotData`, `_fetchHistoricalSlotData`, `_countValidTemplates`, `_fetchTokenSlotData`, `_fetchTemplateSlotData`.
