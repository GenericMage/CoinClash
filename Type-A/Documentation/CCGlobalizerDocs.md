# CCGlobalizer Documentation

## Overview
The `CCGlobalizer` contract, implemented in Solidity (^0.8.2), tracks maker orders and depositor liquidity across tokens, listings, and liquidity templates. It integrates with `ICCLiquidityTemplate`, `ICCListingTemplate`, and `ICCAgent` for validation and data retrieval. It uses `Ownable` for agent setting, employs explicit casting, and ensures non-reverting behavior for `globalizeOrders` and `globalizeLiquidity` to prevent stalling. View functions use `step` and `maxIterations` for gas-efficient pagination. Amounts are normalized to 1e18 via external contracts.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.2.0 (Updated 2025-08-15)

**Compatibility**:
- CCLiquidityTemplate.sol (v0.1.0)
- CCListingTemplate.sol (v0.1.0)
- ICCAgent.sol (v0.1.2)

## Interfaces
- **IERC20**: Provides `decimals()` for token normalization.
- **ICCLiquidityTemplate**: Provides `listingAddress` (returns `address`).
- **ICCListingTemplate**: Provides `makerPendingBuyOrdersView`, `makerPendingSellOrdersView`, `pendingBuyOrdersView`, `pendingSellOrdersView` (returns `uint256[] memory orderIds`), `tokenA`, `tokenB` (returns `address`).
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
- **Restrictions**: Caller must be a valid listing (via `ICCAgent.isValidListing`), `agent` must be set.
- **Gas**: External call to `ICCAgent`, array pushes.
- **Interactions**: Calls `ICCAgent.isValidListing`, updates mappings/arrays, emits `OrdersGlobalized(address maker, address listing, address token)`.

### globalizeLiquidity(address depositor, address token)
- **Behavior**: Called by valid liquidity templates (verified via `ICCLiquidityTemplate.listingAddress` and `ICCAgent.isValidListing`). Updates `depositorTokensByLiquidity`, `depositorLiquidityTemplates`, and `tokenLiquidityTemplates` if token matches listing’s `tokenA` or `tokenB`. Exits silently on invalid inputs or failed validation. Emits `LiquidityGlobalized`.
- **Parameters**: `depositor` (address), `token` (address).
- **Restrictions**: Caller must be a valid liquidity template, `agent` must be set.
- **Gas**: External calls to `ICCLiquidityTemplate` and `ICCAgent`, array pushes.
- **Interactions**: Calls `ICCLiquidityTemplate.listingAddress`, `ICCAgent.isValidListing`, updates mappings/arrays, emits `LiquidityGlobalized(address depositor, address liquidity, address token)`.

### getAllUserOrders(address user, uint256 step, uint256 maxIterations) view returns (address[] memory listings, uint256[] memory orderIds)
- **Behavior**: Returns paginated order IDs for a user across listings from `makerListings`, fetching buy/sell orders via `ICCListingTemplate.makerPendingBuyOrdersView` and `makerPendingSellOrdersView`. Returns empty arrays if `step` exceeds listings length.
- **Parameters**: `user` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `listings` (address[]), `orderIds` (uint256[]).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: Queries `ICCListingTemplate` for pending orders.

### getAllUserTokenOrders(address user, address token, uint256 step, uint256 maxIterations) view returns (address[] memory listings, uint256[] memory orderIds)
- **Behavior**: Returns paginated order IDs for a user’s token across listings from `makerListings`, filtering by `makerTokensByListing`. Fetches buy/sell orders via `ICCListingTemplate`. Returns empty arrays if `step` exceeds listings length.
- **Parameters**: `user` (address), `token` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `listings` (address[]), `orderIds` (uint256[]).
ASP: **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: Queries `ICCListingTemplate` for pending orders, checks `makerTokensByListing`.

### getAllTokenOrders(address token, uint256 step, uint256 maxIterations) view returns (address[] memory listings, uint256[] memory orderIds)
- **Behavior**: Returns paginated order IDs for a token across listings from `tokenListings`, fetching buy/sell orders via `ICCListingTemplate.pendingBuyOrdersView` and `pendingSellOrdersView`. Returns empty arrays if `step` exceeds listings length.
- **Parameters**: `token` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `listings` (address[]), `orderIds` (uint256[]).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: Queries `ICCListingTemplate` for pending orders.

### getAllListingOrders(address listing, uint256 step, uint256 maxIterations) view returns (uint256[] memory orderIds)
- **Behavior**: Returns paginated order IDs for a listing, fetching buy/sell orders via `ICCListingTemplate.pendingBuyOrdersView` and `pendingSellOrdersView`. Returns empty array if `step` exceeds total orders.
- **Parameters**: `listing` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `orderIds` (uint256[]).
- **Gas**: External calls to `ICCListingTemplate`, array allocation.
- **Interactions**: Queries `ICCListingTemplate` for pending orders.

## Internal Functions
### isInArray(address[] memory array, address element) pure returns (bool)
- **Behavior**: Checks if an address exists in an array.
- **Parameters**: `array` (address[]), `element` (address).
- **Returns**: `bool`.
- **Gas**: Loop over array length.

## Additional Details
- **Decimal Handling**: Relies on `ICCListingTemplate` and `ICCLiquidityTemplate` for normalization to 1e18.
- **Gas Optimization**: Uses `step` and `maxIterations` for pagination in view functions to control gas usage. Avoids inline assembly and uses high-level Solidity for array operations.
- **Events**: `AgentSet(address agent)`, `OrdersGlobalized(address maker, address listing, address token)`, `LiquidityGlobalized(address depositor, address liquidity, address token)`.
- **Safety**:
  - Explicit casting for interface calls.
  - Try-catch for external calls in `globalizeLiquidity` with silent exits on failure.
  - Public mappings accessed directly in view functions (e.g., `makerTokensByListing[maker][listing]`).
  - No reserved keywords, no `virtual`/`override`.
  - Non-reverting `globalizeOrders` and `globalizeLiquidity` to prevent stalling external contracts.
- **Verification**: Validates listings via `ICCAgent.isValidListing`, liquidity templates via `ICCLiquidityTemplate.listingAddress` and `ICCAgent.isValidListing`.
- **Interactions**:
  - `setAgent`: Owner-only, sets `agent` for validation.
  - `globalizeOrders`: Called by listings, verifies via `ICCAgent`, updates mappings, emits event.
  - `globalizeLiquidity`: Called by liquidity templates, verifies via `ICCLiquidityTemplate` and `ICCAgent`, updates mappings, emits event.
  - View functions: Query `ICCListingTemplate` for real-time order data, use mappings for efficient filtering.
