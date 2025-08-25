# CCGlobalizer Documentation

## Overview
The `CCGlobalizer` contract, implemented in Solidity (^0.8.2), tracks maker orders and depositor liquidity across tokens, listings, and liquidity templates. It integrates with `ICCLiquidityTemplate`, `ICCListingTemplate`, and `ICCAgent` for validation and data retrieval. It uses `Ownable` for agent setting, employs explicit casting, and ensures non-reverting behavior for `globalizeOrders` and `globalizeLiquidity` with detailed failure events. View functions use `step` and `maxIterations` for gas-efficient pagination, with structured outputs (`OrderGroup`/`SlotGroup`) in top-down style (latest entries first). Amounts are normalized to 1e18 via external contracts.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.2.13 (Updated 2025-08-25)

**Compatibility**:
- CCLiquidityTemplate.sol (v0.1.4)
- CCListingTemplate.sol (v0.2.7)
- ICCAgent.sol (v0.1.2)

## Interfaces
- **IERC20**: Provides `decimals()` for token normalization.
- **ICCLiquidityTemplate**: Provides `listingAddress` (returns `address`), `userXIndexView`, `userYIndexView` (returns `uint256[]`), `getXSlotView`, `getYSlotView` (returns `Slot`), `activeXLiquiditySlotsView`, `activeYLiquiditySlotsView` (returns `uint256[]`).
- **ICCListingTemplate**: Provides `makerPendingBuyOrdersView`, `makerPendingSellOrdersView`, `pendingBuyOrdersView`, `pendingSellOrdersView` (returns `uint256[]`), `tokenA`, `tokenB` (returns `address`), `makerOrdersView` (returns `uint256[]`).
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
  - **Usage**: Tracks tokens for depositor liquidity, updated in `globalizeLiquidity`.
- **`makerListings`**: `mapping(address => address[]) public`  
  - **Parameters**: `maker` (address)  
  - **Returns**: `address[]` (listings with orders for maker)  
  - **Usage**: Lists all listings a maker has orders in, updated in `globalizeOrders`.
- **`depositorLiquidityTemplates`**: `mapping(address => address[]) public`  
  - **Parameters**: `depositor` (address)  
  - **Returns**: `address[]` (liquidity templates for depositor)  
  - **Usage**: Lists liquidity templates a depositor provides liquidity for, updated in `globalizeLiquidity`.
- **`tokenListings`**: `mapping(address => address[]) public`  
  - **Parameters**: `token` (address)  
  - **Returns**: `address[]` (listings associated with token)  
  - **Usage**: Tracks listings for a token, updated in `globalizeOrders`.
- **`tokenLiquidityTemplates`**: `mapping(address => address[]) public`  
  - **Parameters**: `token` (address)  
  - **Returns**: `address[]` (liquidity templates for token)  
  - **Usage**: Tracks liquidity templates for a token, updated in `globalizeLiquidity`.

## Structs
- **`OrderGroup`**: Used in order-related view functions.  
  - **Fields**: `listing` (address), `orderIds` (uint256[]).
- **`SlotGroup`**: Used in liquidity view functions.  
  - **Fields**: `template` (address), `slotIndices` (uint256[]), `isX` (bool[]).
- **`OrderData`**: Internal struct for managing order data.  
  - **Fields**: `buyIds` (uint256[]), `sellIds` (uint256[]), `totalOrders` (uint256).
- **`SlotData`**: Internal struct for managing slot data.  
  - **Fields**: `slotIndices` (uint256[]), `isX` (bool[]), `totalSlots` (uint256).

## Events
- **`AgentSet(address indexed agent)`**: Emitted when `agent` is set via `setAgent`.
- **`OrdersGlobalized(address indexed maker, address indexed listing, address indexed token)`**: Emitted on successful `globalizeOrders` call.
- **`LiquidityGlobalized(address indexed depositor, address indexed liquidity, address indexed token)`**: Emitted on successful `globalizeLiquidity` call.
- **`GlobalizeLiquidityFailed(address indexed depositor, address indexed liquidity, address indexed token, string reason)`**: Emitted on `globalizeLiquidity` failure (e.g., invalid inputs, failed external calls).
- **`GlobalizeOrdersFailed(address indexed maker, address indexed listing, address indexed token, string reason)`**: Emitted on `globalizeOrders` failure (e.g., invalid inputs, listing mismatch).

## External Functions
### setAgent(address _agent)
- **Behavior**: Sets `agent` address, callable once by owner. Validates `_agent` is non-zero and `agent` is unset. Emits `AgentSet` on success, or `GlobalizeOrdersFailed` if invalid.
- **Parameters**: `_agent` (address) - Agent contract address for validation.
- **Restrictions**: Only owner, single-time set.
- **Gas**: Single state write.
- **Interactions**: 
  - Updates `agent` state variable.
  - Emits `AgentSet(address)` or `GlobalizeOrdersFailed(address(0), address(0), address(0), string)`.
- **Internal Call Tree**: None.

### globalizeOrders(address maker, address token)
- **Behavior**: Called by valid listings (verified via `ICCAgent.isValidListing`). Validates `agent`, `maker`, `token`, and listing/token match. Updates `makerTokensByListing`, `makerListings`, `tokenListings` for both `tokenA` and `tokenB` if not already present (checked via `isInArray`). Emits `OrdersGlobalized` on success, or `GlobalizeOrdersFailed` with reason (e.g., "Agent not set", "Invalid listing"). Idempotent for already globalized listings.
- **Parameters**: 
  - `maker` (address): Order maker.
  - `token` (address): Token in listing.
- **Restrictions**: Caller must be a valid listing, `agent` must be set.
- **Gas**: External calls to `ICCAgent`, `ICCListingTemplate`, array pushes, mapping updates.
- **Interactions**: 
  - Calls `ICCAgent.isValidListing` to verify listing and token match.
  - Calls `ICCListingTemplate.tokenA` and `tokenB` to initialize `tokenListings`.
  - Calls `isInArray` to check duplicates in `makerTokensByListing`, `makerListings`, `tokenListings`.
  - Updates `makerTokensByListing`, `makerListings`, `tokenListings`.
  - Emits `OrdersGlobalized` or `GlobalizeOrdersFailed`.
- **Internal Call Tree**: 
  - `isInArray` (checks duplicates in mappings/arrays).

### globalizeLiquidity(address depositor, address token)
- **Behavior**: Called by valid liquidity templates (verified via `ICCLiquidityTemplate.listingAddress` and `ICCAgent.isValidListing`). Validates `agent`, `depositor`, `token`, listing, and token match. Updates `depositorTokensByLiquidity`, `depositorLiquidityTemplates`, `tokenLiquidityTemplates` if not already present (checked via `isInArray`). Emits `LiquidityGlobalized` on success, or `GlobalizeLiquidityFailed` with reason (e.g., "Agent not set", "Invalid listing"). Idempotent for already globalized templates.
- **Parameters**: 
  - `depositor` (address): Liquidity provider.
  - `token` (address): Token in liquidity template.
- **Restrictions**: Caller must be a valid liquidity template, `agent` must be set.
- **Gas**: External calls to `ICCLiquidityTemplate`, `ICCAgent`, array pushes.
- **Interactions**: 
  - Calls `ICCLiquidityTemplate.listingAddress` to get listing address.
  - Calls `ICCAgent.isValidListing` to verify listing and template match.
  - Calls `isInArray` to check duplicates in `depositorTokensByLiquidity`, `depositorLiquidityTemplates`, `tokenLiquidityTemplates`.
  - Updates `depositorTokensByLiquidity`, `depositorLiquidityTemplates`, `tokenLiquidityTemplates`.
  - Emits `LiquidityGlobalized` or `GlobalizeLiquidityFailed`.
- **Internal Call Tree**: 
  - `isInArray` (checks duplicates in mappings/arrays).

### getAllUserActiveOrders(address user, uint256 step, uint256 maxIterations) view returns (OrderGroup[] memory orderGroups)
- **Behavior**: Returns paginated `OrderGroup` arrays for a user’s pending orders across globalized listings from `makerListings` (verified via `_isListingGlobalized`) in top-down order (latest first). Returns empty array if `step` exceeds listings length.
- **Parameters**: 
  - `user` (address): Order maker.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum listings to process.
- **Returns**: `orderGroups` (OrderGroup[] - listing, orderIds).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: 
  - Queries `makerListings` for user’s listings.
  - Calls `_isListingGlobalized` to verify globalization.
  - Calls `_fetchOrderData` to get pending orders.
  - Calls `_combineOrderIds` to merge order IDs.
- **Internal Call Tree**: 
  - `_isListingGlobalized` (checks listing globalization).
  - `_fetchOrderData` (fetches pending buy/sell orders via `ICCListingTemplate`).
  - `_combineOrderIds` (merges buy/sell order IDs).

### getAllUserOrdersHistory(address user, uint256 step, uint256 maxIterations) view returns (OrderGroup[] memory orderGroups)
- **Behavior**: Returns paginated `OrderGroup` arrays for all user orders (pending, filled, canceled) across globalized listings from `makerListings` (verified via `_isListingGlobalized`) in top-down order. Returns empty array if `step` exceeds listings length.
- **Parameters**: 
  - `user` (address): Order maker.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum listings to process.
- **Returns**: `orderGroups` (OrderGroup[] - listing, orderIds).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: 
  - Queries `makerListings` for user’s listings.
  - Calls `_isListingGlobalized` to verify globalization.
  - Calls `_fetchAllOrderData` to get all orders.
  - Calls `_combineOrderIds` to merge order IDs.
- **Internal Call Tree**: 
  - `_isListingGlobalized` (checks listing globalization).
  - `_fetchAllOrderData` (fetches all orders via `ICCListingTemplate`).
  - `_combineOrderIds` (merges order IDs).

### getAllUserTokenActiveOrders(address user, address token, uint256 step, uint256 maxIterations) view returns (OrderGroup[] memory orderGroups)
- **Behavior**: Returns paginated `OrderGroup` arrays for a user’s pending token orders across globalized listings from `makerListings` (verified via `_isListingGlobalized`), filtering by `makerTokensByListing`, in top-down order. Returns empty array if `step` exceeds listings length.
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
  - Calls `_isListingGlobalized` to verify globalization.
  - Calls `_fetchOrderData` to get pending orders.
  - Calls `_combineOrderIds` to merge order IDs.
- **Internal Call Tree**: 
  - `_countValidListings` (counts valid listings for token).
  - `_isListingGlobalized` (checks listing globalization).
  - `_fetchOrderData` (fetches pending orders).
  - `_combineOrderIds` (merges order IDs).

### getAllUserTokenOrdersHistory(address user, address token, uint256 step, uint256 maxIterations) view returns (OrderGroup[] memory orderGroups)
- **Behavior**: Returns paginated `OrderGroup` arrays for all user token orders across globalized listings from `makerListings` (verified via `_isListingGlobalized`), filtering by `makerTokensByListing`, in top-down order. Returns empty array if `step` exceeds listings length.
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
  - Calls `_isListingGlobalized` to verify globalization.
  - Calls `_fetchAllOrderData` to get all orders.
  - Calls `_combineOrderIds` to merge order IDs.
- **Internal Call Tree**: 
  - `_countValidListings` (counts valid listings for token).
  - `_isListingGlobalized` (checks listing globalization).
  - `_fetchAllOrderData` (fetches all orders).
  - `_combineOrderIds` (merges order IDs).

### getAllUserActiveLiquidity(address user, uint256 step, uint256 maxIterations) view returns (SlotGroup[] memory slotGroups)
- **Behavior**: Returns paginated `SlotGroup` arrays for a user’s active liquidity slots (`allocation > 0`) across templates from `depositorLiquidityTemplates`, filtering globalized templates via `_isTemplateGlobalized`, in top-down order. Returns empty array if `step` exceeds templates length.
- **Parameters**: 
  - `user` (address): Liquidity depositor.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum templates to process.
- **Returns**: `slotGroups` (SlotGroup[] - template, slotIndices, isX).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Interactions**: 
  - Queries `depositorLiquidityTemplates` for valid templates.
  - Calls `_countValidTemplates` to size output array.
  - Calls `_isTemplateGlobalized` to verify globalization.
  - Calls `_fetchSlotData` to get active slots.
- **Internal Call Tree**: 
  - `_countValidTemplates` (counts valid templates).
  - `_isTemplateGlobalized` (checks template globalization).
  - `_fetchSlotData` (fetches active slots).

### getAllUserTokenActiveLiquidity(address user, address token, uint256 step, uint256 maxIterations) view returns (SlotGroup[] memory slotGroups)
- **Behavior**: Returns paginated `SlotGroup` arrays for a user’s active token liquidity slots (`allocation > 0`) across templates from `depositorLiquidityTemplates`, filtering by `depositorTokensByLiquidity` and `_isTemplateGlobalized`, in top-down order. Returns empty array if `step` exceeds templates length.
- **Parameters**: 
  - `user` (address): Liquidity depositor.
  - `token` (address): Token to filter liquidity.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum templates to process.
- **Returns**: `slotGroups` (SlotGroup[] - template, slotIndices, isX).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Interactions**: 
  - Queries `depositorLiquidityTemplates` and `depositorTokensByLiquidity` for valid templates.
  - Calls `_countValidTokenTemplates` to size output array.
  - Calls `_isTemplateGlobalized` to verify globalization.
  - Calls `_fetchSlotData` to get active slots.
- **Internal Call Tree**: 
  - `_countValidTokenTemplates` (counts valid templates for token).
  - `_isTemplateGlobalized` (checks template globalization).
  - `_fetchSlotData` (fetches active slots).

### getAllTokenLiquidity(address token, uint256 step, uint256 maxIterations) view returns (SlotGroup[] memory slotGroups)
- **Behavior**: Returns paginated `SlotGroup` arrays for a token’s active liquidity slots across templates from `tokenLiquidityTemplates`, filtering globalized templates via `_isTemplateGlobalized`, in top-down order. Returns empty array if `step` exceeds templates length.
- **Parameters**: 
  - `token` (address): Token to filter liquidity.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum templates to process.
- **Returns**: `slotGroups` (SlotGroup[] - template, slotIndices, isX).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Interactions**: 
  - Queries `tokenLiquidityTemplates` for token’s templates.
  - Calls `_isTemplateGlobalized` to verify globalization.
  - Calls `_fetchSlotData` to get active slots.
- **Internal Call Tree**: 
  - `_isTemplateGlobalized` (checks template globalization).
  - `_fetchSlotData` (fetches active slots).

### getAllTemplateLiquidity(address template, uint256 step, uint256 maxIterations) view returns (SlotGroup memory slotGroup)
- **Behavior**: Returns a single `SlotGroup` for a template’s active X and Y liquidity slots if globalized (via `_isTemplateGlobalized`). Returns empty group if not globalized.
- **Parameters**: 
  - `template` (address): Liquidity template to query.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum slots to process.
- **Returns**: `slotGroup` (SlotGroup - template, slotIndices, isX).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Interactions**: 
  - Calls `_isTemplateGlobalized` to verify globalization.
  - Calls `_fetchTemplateSlotData` to get active slots.
- **Internal Call Tree**: 
  - `_isTemplateGlobalized` (checks template globalization).
  - `_fetchTemplateSlotData` (fetches active X and Y slots).

### getUserHistoricalTemplates(address user, uint256 step, uint256 maxIterations) view returns (address[] memory templates)
- **Behavior**: Returns paginated liquidity templates from `depositorLiquidityTemplates` in top-down order. Returns empty array if `step` exceeds templates length.
- **Parameters**: 
  - `user` (address): Liquidity depositor.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum templates to process.
- **Returns**: `templates` (address[]).
- **Gas**: Array allocation, mapping access.
- **Interactions**: 
  - Queries `depositorLiquidityTemplates` for user’s templates.
- **Internal Call Tree**: None.

### getAllListingOrders(address listing, uint256 step, uint256 maxIterations) view returns (OrderGroup memory orderGroup)
- **Behavior**: Returns a single `OrderGroup` for a listing’s pending orders if globalized (via `_isListingGlobalized`). Returns empty group if not globalized.
- **Parameters**: 
  - `listing` (address): Listing to query.
  - `step` (uint256): Starting index for pagination.
  - `maxIterations` (uint256): Maximum orders to process.
- **Returns**: `orderGroup` (OrderGroup - listing, orderIds).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: 
  - Calls `_isListingGlobalized` to verify globalization.
  - Queries `ICCListingTemplate.pendingBuyOrdersView` and `pendingSellOrdersView` for order IDs.
- **Internal Call Tree**: 
  - `_isListingGlobalized` (checks listing globalization).

## Internal Functions
### isInArray(address[] memory array, address element) pure returns (bool)
- **Behavior**: Checks if an address exists in an array.
- **Parameters**: `array` (address[]), `element` (address).
- **Returns**: `bool`.
- **Gas**: Loop over array length.
- **Called By**: 
  - `globalizeOrders` (checks duplicates in `makerTokensByListing`, `makerListings`, `tokenListings`).
  - `globalizeLiquidity` (checks duplicates in `depositorTokensByLiquidity`, `depositorLiquidityTemplates`, `tokenLiquidityTemplates`).
  - `_countValidListings` (checks token in `makerTokensByListing`).
  - `_countValidTokenTemplates` (checks token in `depositorTokensByLiquidity`).
  - `_isListingGlobalized` (checks listing in `tokenListings`).

### removeFromArray(address[] storage array, address element)
- **Behavior**: Removes an address from a storage array by swapping with the last element and popping.
- **Parameters**: `array` (address[] storage), `element` (address).
- **Gas**: Loop over array length, state write.
- **Called By**: 
  - `globalizeLiquidity` (depopulates mappings for inactive slots).

### _fetchOrderData(address listing, address user) view returns (OrderData memory)
- **Behavior**: Fetches pending buy/sell orders via `ICCListingTemplate.makerPendingBuyOrdersView` and `makerPendingSellOrdersView`.
- **Parameters**: `listing` (address), `user` (address).
- **Returns**: `OrderData` (buyIds, sellIds, totalOrders).
- **Gas**: External calls to `ICCListingTemplate`.
- **Called By**: 
  - `getAllUserActiveOrders` (fetches user’s pending orders).
  - `getAllUserTokenActiveOrders` (fetches user’s token-specific pending orders).

### _fetchAllOrderData(address listing, address user) view returns (OrderData memory)
- **Behavior**: Fetches all orders (pending, filled, canceled) via `ICCListingTemplate.makerOrdersView`.
- **Parameters**: `listing` (address), `user` (address).
- **Returns**: `OrderData` (buyIds, sellIds, totalOrders).
- **Gas**: External calls to `ICCListingTemplate`.
- **Called By**: 
  - `getAllUserOrdersHistory` (fetches user’s all orders).
  - `getAllUserTokenOrdersHistory` (fetches user’s token-specific all orders).

### _combineOrderIds(OrderData memory data) pure returns (uint256[] memory)
- **Behavior**: Combines buy/sell order IDs into a single array.
- **Parameters**: `data` (OrderData).
- **Returns**: `uint256[]` (combined order IDs).
- **Gas**: Array allocation, loops.
- **Called By**: 
  - `getAllUserActiveOrders` (merges pending order IDs).
  - `getAllUserOrdersHistory` (merges all order IDs).
  - `getAllUserTokenActiveOrders` (merges token-specific pending order IDs).
  - `getAllUserTokenOrdersHistory` (merges token-specific all order IDs).

### _countValidListings(address user, address token, uint256 step, uint256 maxIterations) view returns (uint256)
- **Behavior**: Counts globalized listings in `makerListings` where `makerTokensByListing` includes the token, verified via `_isListingGlobalized`.
- **Parameters**: `user` (address), `token` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `uint256` (valid listing count).
- **Gas**: Loop over listings, array checks.
- **Called By**: 
  - `getAllUserTokenActiveOrders` (sizes output array for token orders).
  - `getAllUserTokenOrdersHistory` (sizes output array for token orders).

### _fetchSlotData(address template, address user) view returns (SlotData memory)
- **Behavior**: Fetches user’s active liquidity slot indices from `ICCLiquidityTemplate.userXIndexView` and `userYIndexView`, validates slots with `getXSlotView`/`getYSlotView` for `allocation > 0`.
- **Parameters**: `template` (address), `user` (address).
- **Returns**: `SlotData` (slotIndices, isX, totalSlots).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Called By**: 
  - `getAllUserActiveLiquidity` (fetches user’s active slots).
  - `getAllUserTokenActiveLiquidity` (fetches user’s token-specific active slots).
  - `getAllTokenLiquidity` (fetches token’s active slots).
  - `getAllTemplateLiquidity` (fetches template’s active slots).

### _fetchTemplateSlotData(address template) view returns (SlotData memory)
- **Behavior**: Fetches all active X and Y slots via `ICCLiquidityTemplate.activeXLiquiditySlotsView` and `activeYLiquiditySlotsView`, validated with `getXSlotView`/`getYSlotView` for `allocation > 0`.
- **Parameters**: `template` (address).
- **Returns**: `SlotData` (slotIndices, isX, totalSlots).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Called By**: 
  - `getAllTemplateLiquidity` (fetches template’s active slots).

### _isTemplateGlobalized(address template) view returns (bool)
- **Behavior**: Checks if a template is associated with a valid listing via `ICCLiquidityTemplate.listingAddress` and `ICCAgent.isValidListing`.
- **Parameters**: `template` (address).
- **Returns**: `bool`.
- **Gas**: External calls to `ICCLiquidityTemplate`, `ICCAgent`.
- **Called By**: 
  - `getAllUserActiveLiquidity` (verifies template globalization).
  - `getAllUserTokenActiveLiquidity` (verifies template globalization).
  - `getAllTokenLiquidity` (verifies template globalization).
  - `getAllTemplateLiquidity` (verifies template globalization).

### _isListingGlobalized(address listing) view returns (bool)
- **Behavior**: Checks if a listing is associated with any token in `tokenListings` by querying `ICCListingTemplate.tokenA` and `tokenB`.
- **Parameters**: `listing` (address).
- **Returns**: `bool`.
- **Gas**: External calls to `ICCListingTemplate`, array checks.
- **Called By**: 
  - `getAllUserActiveOrders` (verifies listing globalization).
  - `getAllUserOrdersHistory` (verifies listing globalization).
  - `getAllUserTokenActiveOrders` (verifies listing globalization).
  - `getAllUserTokenOrdersHistory` (verifies listing globalization).
  - `getAllListingOrders` (verifies listing globalization).

### _countValidTemplates(address user, uint256 step, uint256 maxIterations) view returns (uint256)
- **Behavior**: Counts templates in `depositorLiquidityTemplates` with non-empty active slots, filtering globalized templates via `_isTemplateGlobalized`.
- **Parameters**: `user` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `uint256` (valid template count).
- **Gas**: Loop over templates, external calls to `ICCLiquidityTemplate`.
- **Called By**: 
  - `getAllUserActiveLiquidity` (sizes output array).

### _countValidTokenTemplates(address user, address token, uint256 step, uint256 maxIterations) view returns (uint256)
- **Behavior**: Counts templates in `depositorLiquidityTemplates` with non-empty active slots for a token, filtering by `depositorTokensByLiquidity` and `_isTemplateGlobalized`.
- **Parameters**: `user` (address), `token` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `uint256` (valid template count).
- **Gas**: Loop over templates, external calls to `ICCLiquidityTemplate`.
- **Called By**: 
  - `getAllUserTokenActiveLiquidity` (sizes output array).

## Additional Details
- **Decimal Handling**: Relies on `ICCListingTemplate` and `ICCLiquidityTemplate` for normalization to 1e18.
- **Gas Optimization**: Uses `step` and `maxIterations` for pagination. Avoids inline assembly, uses high-level Solidity for array operations. Call tree structure in view functions reduces stack usage.
- **Safety**:
  - Explicit casting for interface calls.
  - Try-catch for external calls in `globalizeLiquidity` and `globalizeOrders` with failure events.
  - Public mappings accessed directly in view functions.
  - No reserved keywords, no `virtual`/`override`, no `SafeERC20`.
  - Non-reverting `globalizeOrders` and `globalizeLiquidity` with `GlobalizeOrdersFailed` and `GlobalizeLiquidityFailed` events.
- **Verification**: Validates listings via `ICCAgent.isValidListing`, liquidity templates via `ICCLiquidityTemplate.listingAddress` and `ICCAgent.isValidListing`. Globalized listings/templates verified via `_isListingGlobalized` and `_isTemplateGlobalized`.
- **Interactions**:
  - `setAgent`: Owner-only, sets `agent`, emits `AgentSet` or `GlobalizeOrdersFailed`.
  - `globalizeOrders`: Called by listings, verifies via `ICCAgent`, initializes `tokenListings` for both tokens, updates mappings, emits `OrdersGlobalized` or `GlobalizeOrdersFailed`.
  - `globalizeLiquidity`: Called by liquidity templates, verifies via `ICCLiquidityTemplate` and `ICCAgent`, updates mappings, emits `LiquidityGlobalized` or `GlobalizeLiquidityFailed`.
  - Order view functions: Query `ICCListingTemplate`, use `_fetchOrderData`, `_fetchAllOrderData`, `_combineOrderIds`, `_countValidListings`, `_isListingGlobalized`.
  - Liquidity view functions: Query `ICCLiquidityTemplate` for active data, use `_fetchSlotData`, `_fetchTemplateSlotData`, `_isTemplateGlobalized`, `_countValidTemplates`, `_countValidTokenTemplates`.
