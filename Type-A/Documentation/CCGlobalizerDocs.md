# CCGlobalizer Documentation

## Overview
The `CCGlobalizer` contract, implemented in Solidity (^0.8.2), tracks maker orders and depositor liquidity across tokens, listings, and liquidity templates. It integrates with `ICCLiquidityTemplate`, `ICCListingTemplate`, and `ICCAgent` for validation and data retrieval. It uses `Ownable` for agent setting, employs explicit casting, and ensures non-reverting behavior for `globalizeOrders` and `globalizeLiquidity`. View functions use `step` and `maxIterations` for gas-efficient pagination, with structured outputs (`OrderGroup`/`SlotGroup`) for readability. Amounts are normalized to 1e18 via external contracts.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.2.3 (Updated 2025-08-16)

**Compatibility**:
- CCLiquidityTemplate.sol (v0.0.21)
- CCListingTemplate.sol (v0.0.10)
- ICCAgent.sol (v0.1.2)

## Interfaces
- **IERC20**: Provides `decimals()` for token normalization.
- **ICCLiquidityTemplate**: Provides `listingAddress` (returns `address`), `userIndexView` (returns `uint256[]`), `getXSlotView`, `getYSlotView` (returns `Slot`), `activeXLiquiditySlotsView`, `activeYLiquiditySlotsView` (returns `uint256[]`).
- **ICCListingTemplate**: Provides `makerPendingBuyOrdersView`, `makerPendingSellOrdersView` (returns `uint256[]`), `pendingBuyOrdersView`, `pendingSellOrdersView` (returns `uint256[]`), `tokenA`, `tokenB` (returns `address`).
- **ICCAgent**: Provides `is pairListing(address)` (returns `bool isValid`, `ListingDetails`).

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
  - **Usage**: Tracks tokens for depositor liquidity per template, updated in `globalizeLiquidity`.
- **`makerListings`**: `mapping(address => address[]) public`  
  - **Parameters**: `maker` (address)  
  - **Returns**: `address[]` (listings with orders for maker)  
  - **Usage**: Lists all listings a maker has orders in, updated in `globalizeOrders`.
- **`depositorLiquidityTemplates`**: `mapping(address => address[]) public`  
  - **Parameters**: `depositor` (address)  
  - **Returns**: `address[]` (liquidity templates for depositor)  
  - **Usage**: Lists all liquidity templates a depositor provides liquidity for, updated in `globalizeLiquidity`.
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
- **`SlotGroup`**: Used in liquidity-related view functions.  
  - **Fields**: `template` (address), `slotIndices` (uint256[]), `isX` (bool[]).
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
- **Behavior**: Called by valid liquidity templates (verified via `ICCLiquidityTemplate.listingAddress` and `ICCAgent.isValidListing`). Updates `depositorTokensByLiquidity`, `depositorLiquidityTemplates`, and `tokenLiquidityTemplates` if token matches listing’s `tokenA` or `tokenB`. Exits silently on invalid inputs or failed validation. Emits `LiquidityGlobalized`.
- **Parameters**: `depositor` (address), `token` (address).
- **Restrictions**: Caller must be a valid liquidity template, `agent` must be set.
- **Gas**: External calls to `ICCLiquidityTemplate`, `ICCAgent`, array pushes.
- **Interactions**: Calls `ICCLiquidityTemplate.listingAddress`, `ICCAgent.isValidListing`, updates mappings/arrays, emits `LiquidityGlobalized(address depositor, address liquidity, address token)`.

### getAllUserOrders(address user, uint256 step, uint256 maxIterations) view returns (OrderGroup[] memory orderGroups)
- **Behavior**: Returns paginated `OrderGroup` arrays for a user’s orders across listings from `makerListings`. Uses `_fetchOrderData` to get buy/sell orders via `ICCListingTemplate.makerPendingBuyOrdersView` and `makerPendingSellOrdersView`, combined via `_combineOrderIds`. Returns empty array if `step` exceeds listings length.
- **Parameters**: `user` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `orderGroups` (OrderGroup[] - listing, orderIds).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: Queries `ICCListingTemplate`, calls `_fetchOrderData`, `_combineOrderIds`.

### getAllUserTokenOrders(address user, address token, uint256 step, uint256 maxIterations) view returns (OrderGroup[] memory orderGroups)
- **Behavior**: Returns paginated `OrderGroup` arrays for a user’s token orders across listings from `makerListings`, filtering by `makerTokensByListing`. Uses `_countValidListings` to size output, `_fetchOrderData` for buy/sell orders, and `_combineOrderIds` to combine. Returns empty array if `step` exceeds listings length.
- **Parameters**: `user` (address), `token` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `orderGroups` (OrderGroup[] - listing, orderIds).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: Queries `ICCListingTemplate`, calls `_countValidListings`, `_fetchOrderData`, `_combineOrderIds`, checks `makerTokensByListing`.

### getAllTokenOrders(address token, uint256 step, uint256 maxIterations) view returns (OrderGroup[] memory orderGroups)
- **Behavior**: Returns paginated `OrderGroup` arrays for a token’s orders across listings from `tokenListings`. Uses `_fetchTokenOrderData` for buy/sell orders via `ICCListingTemplate.pendingBuyOrdersView` and `pendingSellOrdersView`, combined via `_combineOrderIds`. Returns empty array if `step` exceeds listings length.
- **Parameters**: `token` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `orderGroups` (OrderGroup[] - listing, orderIds).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: Queries `ICCListingTemplate`, calls `_fetchTokenOrderData`, `_combineOrderIds`.

### getAllListingOrders(address listing, uint256 step, uint256 maxIterations) view returns (OrderGroup memory orderGroup)
- **Behavior**: Returns a single `OrderGroup` for a listing’s orders, fetching buy/sell orders via `_fetchListingOrderData` (using `ICCListingTemplate.pendingBuyOrdersView` and `pendingSellOrdersView`). Returns empty group if `step` exceeds total orders.
- **Parameters**: `listing` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `orderGroup` (OrderGroup - listing, orderIds).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: Queries `ICCListingTemplate`, calls `_fetchListingOrderData`.

### getAllUserLiquidity(address user, uint256 step, uint256 maxIterations) view returns (SlotGroup[] memory slotGroups)
- **Behavior**: Returns paginated `SlotGroup` arrays for a user’s liquidity slots across templates from `depositorLiquidityTemplates`. Uses `_fetchSlotData` to get indices via `ICCLiquidityTemplate.userIndexView` and validate slots with `getXSlotView`/`getYSlotView`. Returns empty array if `step` exceeds templates length.
- **Parameters**: `user` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `slotGroups` (SlotGroup[] - template, slotIndices, isX).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Interactions**: Queries `ICCLiquidityTemplate`, calls `_fetchSlotData`.

### getAllUserTokenLiquidity(address user, address token, uint256 step, uint256 maxIterations) view returns (SlotGroup[] memory slotGroups)
- **Behavior**: Returns paginated `SlotGroup` arrays for a user’s token liquidity slots across templates from `depositorLiquidityTemplates`, filtering by `depositorTokensByLiquidity`. Uses `_countValidTemplates` to size output, `_fetchSlotData` for indices and slot validation. Returns empty array if `step` exceeds templates length.
- **Parameters**: `user` (address), `token` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `slotGroups` (SlotGroup[] - template, slotIndices, isX).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Interactions**: Queries `ICCLiquidityTemplate`, calls `_countValidTemplates`, `_fetchSlotData`, checks `depositorTokensByLiquidity`.

### getAllTokenLiquidity(address token, uint256 step, uint256 maxIterations) view returns (SlotGroup[] memory slotGroups)
- **Behavior**: Returns paginated `SlotGroup` arrays for a token’s liquidity slots across templates from `tokenLiquidityTemplates`. Uses `_fetchTokenSlotData` to get slots via `ICCLiquidityTemplate.activeXLiquiditySlotsView` and `activeYLiquiditySlotsView`, validated with `getXSlotView`/`getYSlotView`. Returns empty array if `step` exceeds templates length.
- **Parameters**: `token` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `slotGroups` (SlotGroup[] - template, slotIndices, isX).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Interactions**: Queries `ICCLiquidityTemplate`, calls `_fetchTokenSlotData`.

### getAllTemplateLiquidity(address template, uint256 step, uint256 maxIterations) view returns (SlotGroup memory slotGroup)
- **Behavior**: Returns a single `SlotGroup` for a template’s liquidity slots, fetching slots via `_fetchTemplateSlotData` (using `ICCLiquidityTemplate.activeXLiquiditySlotsView` and `activeYLiquiditySlotsView`, validated with `getXSlotView`/`getYSlotView`). Returns empty group if `step` exceeds total slots.
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

### _fetchOrderData(address listing, address user) view returns (OrderData memory)
- **Behavior**: Fetches buy/sell orders for a user in a listing via `ICCListingTemplate.makerPendingBuyOrdersView` and `makerPendingSellOrdersView`.
- **Parameters**: `listing` (address), `user` (address).
- **Returns**: `OrderData` (buyIds, sellIds, totalOrders).
- **Gas**: External calls to `ICCListingTemplate`.
- **Called By**: `getAllUserOrders`, `getAllUserTokenOrders`.

### _combineOrderIds(OrderData memory data) pure returns (uint256[] memory)
- **Behavior**: Combines buy/sell order IDs into a single array.
- **Parameters**: `data` (OrderData).
- **Returns**: `uint256[]` (combined order IDs).
- **Gas**: Array allocation, loops.
- **Called By**: `getAllUserOrders`, `getAllUserTokenOrders`, `getAllTokenOrders`.

### _countValidListings(address user, address token, uint256 step, uint256 maxIterations) view returns (uint256)
- **Behavior**: Counts listings in `makerListings` where `makerTokensByListing` includes the token.
- **Parameters**: `user` (address), `token` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `uint256` (valid listing count).
- **Gas**: Loop over listings, array checks.
- **Called By**: `getAllUserTokenOrders`.

### _fetchTokenOrderData(address listing) view returns (OrderData memory)
- **Behavior**: Fetches all buy/sell orders for a listing via `ICCListingTemplate.pendingBuyOrdersView` and `pendingSellOrdersView`.
- **Parameters**: `listing` (address).
- **Returns**: `OrderData` (buyIds, sellIds, totalOrders).
- **Gas**: External calls to `ICCListingTemplate`.
- **Called By**: `getAllTokenOrders`.

### _fetchListingOrderData(address listing, uint256 step, uint256 maxIterations) view returns (OrderData memory)
- **Behavior**: Fetches paginated buy/sell orders for a listing via `ICCListingTemplate.pendingBuyOrdersView` and垂SellOrdersView`.
- **Parameters**: `listing` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `OrderData` (combinedIds, empty sellIds, totalOrders).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Called By**: `getAllListingOrders`.

### _fetchSlotData(address template, address user) view returns (SlotData memory)
- **Behavior**: Fetches user’s liquidity slot indices from `ICCLiquidityTemplate.userIndexView`, validates slots with `getXSlotView`/`getYSlotView`.
- **Parameters**: `template` (address), `user` (address).
- **Returns**: `SlotData` (slotIndices, isX, totalSlots).
- **Gas**: External calls to `ICCLiquidityTemplate`, array allocation.
- **Called By**: `getAllUserLiquidity`, `getAllUserTokenLiquidity`.

### _countValidTemplates(address user, address token, uint256 step, uint256 maxIterations) view returns (uint256)
- **Behavior**: Counts templates in `depositorLiquidityTemplates` where `depositorTokensByLiquidity` includes the token.
- **Parameters**: `user` (address), `token` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `uint256` (valid template count).
- **Gas**: Loop over templates, array checks.
- **Called By**: `getAllUserTokenLiquidity`.

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
- **Gas Optimization**: Uses `step` and `maxIterations` for pagination. Avoids inline assembly, uses high-level Solidity for array operations. Call tree structure in view functions reduces stack usage.
- **Events**: `AgentSet(address agent)`, `OrdersGlobalized(address maker, address listing, address token)`, `LiquidityGlobalized(address depositor, address liquidity, address token)`.
- **Safety**:
  - Explicit casting for interface calls.
  - Try-catch for external calls in `globalizeLiquidity` with silent exits.
  - Public mappings accessed directly in view functions.
  - No reserved keywords, no `virtual`/`override`.
  - Non-reverting `globalizeOrders` and `globalizeLiquidity`.
- **Verification**: Validates listings via `ICCAgent.isValidListing`, liquidity templates via `ICCLiquidityTemplate.listingAddress` and `ICCAgent.isValidListing`.
- **Interactions**:
  - `setAgent`: Owner-only, sets `agent`.
  - `globalizeOrders`: Called by listings, verifies via `ICCAgent`, updates mappings, emits event.
  - `globalizeLiquidity`: Called by liquidity templates, verifies via `ICCLiquidityTemplate` and `ICCAgent`, updates mappings, emits event.
  - Order view functions: Query `ICCListingTemplate`, use internal helpers for data processing.
  - Liquidity view functions: Query `ICCLiquidityTemplate`, use internal helpers for data processing.
