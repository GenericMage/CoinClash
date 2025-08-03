# CCGlobalizer Documentation

## Overview
The `CCGlobalizer`, implemented in Solidity (^0.8.2), tracks user liquidity and maker orders across tokens and liquidity pools. It integrates with `CCLiquidityTemplate`, `ICCListingTemplate`, and `ICCAgent` for verification, slot, and order data. It uses `Ownable` for agent setting, employs explicit casting, and ensures gas safety for array operations. Amounts are normalized to 1e18. View functions for makers and tokens return data directly for stack efficiency, while liquidity functions use `maxIterations` and `step` for gas control.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.1.5 (Updated 2025-08-03)

**Compatibility**:
- CCLiquidityTemplate.sol (v0.1.0)
- CCListingTemplate.sol (v0.1.0)
- ICCAgent.sol

## Interfaces
- **IERC20**: Provides `decimals()` for token normalization.
- **ICCLiquidityTemplate**: Provides `userXIndexView`, `userYIndexView` (returns `uint256[] memory indices`), `getXSlotView`, `getYSlotView` (returns `Slot`), `listingAddress` (returns `address`).
- **ICCListingTemplate**: Provides `liquidityAddressView`, `tokenA`, `tokenB`, `globalizerAddressView` (returns `address`), `makerPendingBuyOrdersView`, `makerPendingSellOrdersView` (returns `uint256[] memory orderIds`), `getFullBuyOrderDetails`, `getFullSellOrderDetails` (returns order structs).
- **ICCAgent**: Provides `isValidListing(address)` (returns `bool isValid`, `ListingDetails`).

## State Variables
- **`agent`**: `address public` - Agent contract address, set via `setAgent`.

## Mappings
- **`userLiquidityByToken`**: `mapping(address => mapping(address => uint256)) public`  
  - **Parameters**: `token` (address), `user` (address)  
  - **Returns**: `uint256` (liquidity amount for user’s token)  
  - **Usage**: Tracks liquidity per user for a token across pools.
- **`userLiquidityByPool`**: `mapping(address => mapping(address => uint256)) public`  
  - **Parameters**: `user` (address), `liquidityTemplate` (address)  
  - **Returns**: `uint256` (total liquidity in pool for user)  
  - **Usage**: Tracks user’s total liquidity (tokenA + tokenB) in a pool.
- **`userTokens`**: `mapping(address => address[]) public`  
  - **Parameters**: `user` (address)  
  - **Returns**: `address[]` (tokens user provides liquidity for)  
  - **Usage**: Lists all tokens for a user.
- **`userPools`**: `mapping(address => address[]) public`  
  - **Parameters**: `user` (address)  
  - **Returns**: `address[]` (liquidity templates for user)  
  - **Usage**: Lists all pools for a user.
- **`usersToToken`**: `mapping(address => address[]) public`  
  - **Parameters**: `token` (address)  
  - **Returns**: `address[]` (users providing liquidity for token)  
  - **Usage**: Lists users for a token.
- **`poolsToToken`**: `mapping(address => address[]) public`  
  - **Parameters**: `token` (address)  
  - **Returns**: `address[]` (liquidity templates for token)  
  - **Usage**: Lists pools for a token.
- **`makerBuyOrdersByToken`**: `mapping(address => mapping(address => mapping(address => uint256[]))) public`  
  - **Parameters**: `token` (address), `listing` (address), `maker` (address)  
  - **Returns**: `uint256[]` (buy order IDs)  
  - **Usage**: Tracks buy orders by token, listing, and maker.
- **`makerSellOrdersByToken`**: `mapping(address => mapping(address => mapping(address => uint256[]))) public`  
  - **Parameters**: `token` (address), `listing` (address), `maker` (address)  
  - **Returns**: `uint256[]` (sell order IDs)  
  - **Usage**: Tracks sell orders by token, listing, and maker.
- **`makerActiveBuyOrdersByToken`**: `mapping(address => mapping(address => mapping(address => uint256[]))) public`  
  - **Parameters**: `token` (address), `listing` (address), `maker` (address)  
  - **Returns**: `uint256[]` (active buy order IDs)  
  - **Usage**: Tracks active buy orders by token, listing, and maker.
- **`makerActiveSellOrdersByToken`**: `mapping(address => mapping(address => mapping(address => uint256[]))) public`  
  - **Parameters**: `token` (address), `listing` (address), `maker` (address)  
  - **Returns**: `uint256[]` (active sell order IDs)  
  - **Usage**: Tracks active sell orders by token, listing, and maker.
- **`makerBuyOrdersByListing`**: `mapping(address => mapping(address => uint256[])) public`  
  - **Parameters**: `maker` (address), `listing` (address)  
  - **Returns**: `uint256[]` (buy order IDs)  
  - **Usage**: Tracks buy orders by maker and listing.
- **`makerSellOrdersByListing`**: `mapping(address => mapping(address => uint256[])) public`  
  - **Parameters**: `maker` (address), `listing` (address)  
  - **Returns**: `uint256[]` (sell order IDs)  
  - **Usage**: Tracks sell orders by maker and listing.
- **`makerTokens`**: `mapping(address => address[]) public`  
  - **Parameters**: `maker` (address)  
  - **Returns**: `address[]` (tokens with orders for maker)  
  - **Usage**: Lists tokens with orders for a maker.
- **`makerActiveTokens`**: `mapping(address => address[]) public`  
  - **Parameters**: `maker` (address)  
  - **Returns**: `address[]` (tokens with active orders for maker)  
  - **Usage**: Lists tokens with active orders for a maker.
- **`makerListings`**: `mapping(address => address[]) public`  
  - **Parameters**: `maker` (address)  
  - **Returns**: `address[]` (listings with orders for maker)  
  - **Usage**: Lists listings with orders for a maker.
- **`makerActiveListings`**: `mapping(address => address[]) public`  
  - **Parameters**: `maker` (address)  
  - **Returns**: `address[]` (listings with active orders for maker)  
  - **Usage**: Lists listings with active orders for a maker.
- **`makersToTokens`**: `address[] public`  
  - **Returns**: `address[]` (makers with orders)  
  - **Usage**: Lists all makers with orders.
- **`activeMakersToTokens`**: `address[] public`  
  - **Returns**: `address[]` (makers with active orders)  
  - **Usage**: Lists all makers with active orders.
- **`privateMakerOrders`**: `mapping(address => mapping(address => OrderData[])) private`  
  - **Parameters**: `maker` (address), `listing` (address)  
  - **Returns**: `OrderData[]` (order details)  
  - **Usage**: Stores order data for makers and listings.
- **`privateTokenOrders`**: `mapping(address => OrderData[]) private`  
  - **Parameters**: `token` (address)  
  - **Returns**: `OrderData[]` (order details)  
  - **Usage**: Stores order data for tokens.

## Structs
- **ICCAgent.ListingDetails**:
  - `listingAddress`: Listing contract address.
  - `liquidityAddress`: Associated liquidity contract address.
  - `tokenA`: First token in pair.
  - `tokenB`: Second token in pair.
  - `listingId`: Unique listing identifier.
- **OrderData**:
  - `maker`: Maker address.
  - `listing`: Listing address.
  - `token`: Token address.
  - `orderId`: Order identifier.
  - `amount`: Pending order amount.
  - `isBuy`: True for buy orders, false for sell orders.
- **TempMakerOrderData**:
  - `tokens`: Array of token addresses.
  - `listings`: Array of listing addresses.
  - `orderIds`: Array of order IDs.
  - `isBuy`: Array of order types (true for buy).
  - `index`: Current index for data collection.
- **TempOrderData**:
  - `makers`: Array of maker addresses.
  - `listings`: Array of listing addresses.
  - `orderIds`: Array of order IDs.
  - `amounts`: Array of order amounts.
  - `isBuy`: Array of order types (true for buy).
  - `index`: Current index for data collection.

## External Functions
### setAgent(address _agent)
- **Behavior**: Sets `agent` address, callable once by owner, emits `AgentSet`.
- **Parameters**: `_agent` (address) - Agent contract address.
- **Restrictions**: Reverts if `agent` already set or `_agent` is zero address.
- **Gas**: Single state write.

### globalizeLiquidity(address user, address liquidityTemplate)
- **Behavior**: Verifies `liquidityTemplate` via `ICCLiquidityTemplate.listingAddress`, `ICCListingTemplate.liquidityAddressView`, and `ICCAgent.isValidListing`. Fetches x/y slot indices, aggregates allocations, updates mappings/arrays, emits `LiquidityGlobalized`.
- **Parameters**: `user` (address), `liquidityTemplate` (address).
- **Restrictions**: Reverts if `agent` unset, invalid template, or external calls fail (returns decoded error string).
- **Gas**: Multiple external calls, array resizing, gas check (<10% initial gas).

### globalizeOrders(address maker, address listing)
- **Behavior**: Verifies listing via `ICCAgent.isValidListing` and `ICCListingTemplate.globalizerAddressView`. Fetches pending buy/sell orders, updates order mappings/arrays, emits `OrdersGlobalized`. Clears outdated data using `clearOrderData`.
- **Parameters**: `maker` (address), `listing` (address).
- **Restrictions**: Reverts if `agent` unset, invalid listing, unauthorized globalizer, or external calls fail (decoded error string).
- **Gas**: External calls, array resizing, gas check (<10% initial gas).

### getAllMakerActiveOrders(address maker) view returns (address[] memory tokens, address[] memory listings, uint256[] memory orderIds, bool[] memory isBuy)
- **Behavior**: Returns all active orders for a maker from `privateMakerOrders`.
- **Parameters**: `maker` (address).
- **Returns**: `tokens` (address[]), `listings` (address[]), `orderIds` (uint256[]), `isBuy` (bool[]).

### getAllMakerOrders(address maker) view returns (address[] memory tokens, address[] memory listings, uint256[] memory orderIds, bool[] memory isBuy)
- **Behavior**: Returns all orders (active/inactive) for a maker from `makerBuyOrdersByToken`, `makerSellOrdersByToken`.
- **Parameters**: `maker` (address).
- **Returns**: `tokens` (address[]), `listings` (address[]), `orderIds` (uint256[]), `isBuy` (bool[]).

### getAllActiveTokenOrders(address token) view returns (address[] memory makers, address[] memory listings, uint256[] memory orderIds, bool[] memory isBuy)
- **Behavior**: Returns all active orders for a token from `privateTokenOrders`.
- **Parameters**: `token` (address).
- **Returns**: `makers` (address[]), `listings` (address[]), `orderIds` (uint256[]), `isBuy` (bool[]).

### getAllTokenOrders(address token) view returns (address[] memory makers, address[] memory listings, uint256[] memory orderIds, bool[] memory isBuy)
- **Behavior**: Returns all orders (active/inactive) for a token from `makerBuyOrdersByToken`, `makerSellOrdersByToken`.
- **Parameters**: `token` (address).
- **Returns**: `makers` (address[]), `listings` (address[]), `orderIds` (uint256[]), `isBuy` (bool[]).

### viewActiveMakersByToken(address token) view returns (address[] memory makers, address[] memory listings, uint256[] memory orderIds, uint256[] memory amounts, bool[] memory isBuy)
- **Behavior**: Returns active makers, their orders, and amounts for a token from `privateTokenOrders`.
- **Parameters**: `token` (address).
- **Returns**: `makers` (address[]), `listings` (address[]), `orderIds` (uint256[]), `amounts` (uint256[]), `isBuy` (bool[]).

### viewProvidersByToken(address token, uint256 maxIterations) view returns (address[] memory users, uint256[] memory amounts)
- **Behavior**: Returns up to `maxIterations` users and their liquidity amounts for a token from `userLiquidityByToken`.
- **Parameters**: `token` (address), `maxIterations` (uint256).
- **Returns**: `users` (address[]), `amounts` (uint256[]).

### getAllUserLiquidity(address user, uint256 maxIterations) view returns (address[] memory tokens, uint256[] memory amounts)
- **Behavior**: Returns up to `maxIterations` tokens and liquidity amounts for a user from `userLiquidityByToken`.
- **Parameters**: `user` (address), `maxIterations` (uint256).
- **Returns**: `tokens` (address[]), `amounts` (uint256[]).

### getTotalTokenLiquidity(address token) view returns (uint256 total)
- **Behavior**: Sums liquidity for a token across all users in `userLiquidityByToken`.
- **Parameters**: `token` (address).
- **Returns**: `total` (uint256).

### getTokenPools(address token, uint256 step, uint256 maxIterations) view returns (address[] memory pools)
- **Behavior**: Returns up to `maxIterations` liquidity templates for a token from `poolsToToken`, starting at `step`.
- **Parameters**: `token` (address), `step` (uint256), `maxIterations` (uint256).
- **Returns**: `pools` (address[]).

## Internal Functions
### updateLiquidityMappings(address user, address liquidityTemplate, address tokenA, address tokenB, uint256 totalX, uint256 totalY)
- **Behavior**: Updates liquidity mappings/arrays, removes zeroed-out entries, emits `LiquidityGlobalized`.
- **Parameters**: `user`, `liquidityTemplate`, `tokenA`, `tokenB` (address), `totalX`, `totalY` (uint256).
- **Gas**: Array resizing, gas check.

### updateBuyOrderData(address maker, address listing, address token, uint256[] memory buyOrderIds) returns (OrderData[] memory orders)
- **Behavior**: Fetches buy order details, stores active orders in `OrderData`, resizes array if needed.
- **Parameters**: `maker`, `listing`, `token` (address), `buyOrderIds` (uint256[]).
- **Returns**: `orders` (OrderData[]).

### updateSellOrderData(address maker, address listing, address token, uint256[] memory sellOrderIds) returns (OrderData[] memory orders)
- **Behavior**: Fetches sell order details, stores active orders in `OrderData`, resizes array if needed.
- **Parameters**: `maker`, `listing`, `token` (address), `sellOrderIds` (uint256[]).
- **Returns**: `orders` (OrderData[]).

### clearOrderData(address maker, address listing, address tokenA, address tokenB)
- **Behavior**: Clears `privateMakerOrders` and `privateTokenOrders` for a maker and listing.
- **Parameters**: `maker`, `listing`, `tokenA`, `tokenB` (address).

### updateTokenArrays(address maker, address listing, address token, bool isBuy)
- **Behavior**: Updates `makerTokens`, `makerActiveTokens`, `makerListings`, `makerActiveListings`, `makersToTokens`, `activeMakersToTokens`.
- **Parameters**: `maker`, `listing`, `token` (address), `isBuy` (bool).

### countMakerActiveOrders(address maker) view returns (uint256 totalOrders)
- **Behavior**: Counts active orders for a maker from `privateMakerOrders`.
- **Parameters**: `maker` (address).
- **Returns**: `totalOrders` (uint256).

### initMakerOrderData(uint256 totalOrders) pure returns (TempMakerOrderData memory data)
- **Behavior**: Initializes `TempMakerOrderData` for order collection.
- **Parameters**: `totalOrders` (uint256).
- **Returns**: `data` (TempMakerOrderData).

### collectMakerActiveOrders(address maker, uint256 totalOrders) view returns (address[] memory tokens, address[] memory listings, uint256[] memory orderIds, bool[] memory isBuy)
- **Behavior**: Collects active orders for a maker from `privateMakerOrders`.
- **Parameters**: `maker` (address), `totalOrders` (uint256).
- **Returns**: `tokens` (address[]), `listings` (address[]), `orderIds` (uint256[]), `isBuy` (bool[]).

### countMakerAllOrders(address maker) view returns (uint256 totalOrders)
- **Behavior**: Counts all orders for a maker from `makerBuyOrdersByToken`, `makerSellOrdersByToken`.
- **Parameters**: `maker` (address).
- **Returns**: `totalOrders` (uint256).

### collectMakerAllOrders(address maker, uint256 totalOrders) view returns (address[] memory tokens, address[] memory listings, uint256[] memory orderIds, bool[] memory isBuy)
- **Behavior**: Collects all orders for a maker from `makerBuyOrdersByToken`, `makerSellOrdersByToken`.
- **Parameters**: `maker` (address), `totalOrders` (uint256).
- **Returns**: `tokens` (address[]), `listings` (address[]), `orderIds` (uint256[]), `isBuy` (bool[]).

### countActiveTokenOrders(address token) view returns (uint256 totalOrders)
- **Behavior**: Counts active orders for a token from `privateTokenOrders`.
- **Parameters**: `token` (address).
- **Returns**: `totalOrders` (uint256).

### collectActiveTokenOrders(address token, uint256 totalOrders) view returns (address[] memory makers, address[] memory listings, uint256[] memory orderIds, bool[] memory isBuy)
- **Behavior**: Collects active orders for a token from `privateTokenOrders`.
- **Parameters**: `token` (address), `totalOrders` (uint256).
- **Returns**: `makers` (address[]), `listings` (address[]), `orderIds` (uint256[]), `isBuy` (bool[]).

### countTokenOrders(address token) view returns (uint256 totalOrders)
- **Behavior**: Counts all orders for a token from `makerBuyOrdersByToken`, `makerSellOrdersByToken`.
- **Parameters**: `token` (address).
- **Returns**: `totalOrders` (uint256).

### collectTokenOrders(address token, uint256 totalOrders) view returns (address[] memory makers, address[] memory listings, uint256[] memory orderIds, bool[] memory isBuy)
- **Behavior**: Collects all orders for a token from `makerBuyOrdersByToken`, `makerSellOrdersByToken`.
- **Parameters**: `token` (address), `totalOrders` (uint256).
- **Returns**: `makers` (address[]), `listings` (address[]), `orderIds` (uint256[]), `isBuy` (bool[]).

### countActiveMakersOrders(address token) view returns (uint256 totalOrders)
- **Behavior**: Counts active makers and orders for a token from `privateTokenOrders`.
- **Parameters**: `token` (address).
- **Returns**: `totalOrders` (uint256).

### collectActiveMakersOrders(address token, uint256 totalOrders) view returns (address[] memory makers, address[] memory listings, uint256[] memory orderIds, uint256[] memory amounts, bool[] memory isBuy)
- **Behavior**: Collects active makers, orders, and amounts for a token from `privateTokenOrders`.
- **Parameters**: `token` (address), `totalOrders` (uint256).
- **Returns**: `makers` (address[]), `listings` (address[]), `orderIds` (uint256[]), `amounts` (uint256[]), `isBuy` (bool[]).

### isInArray(address[] memory array, address element) pure returns (bool)
- **Behavior**: Checks if an address exists in an array.
- **Parameters**: `array` (address[]), `element` (address).
- **Returns**: `bool`.

### removeUserToken(address user, address token)
- **Behavior**: Removes a token from `userTokens`.
- **Parameters**: `user`, `token` (address).

### removeUserFromToken(address token, address user)
- **Behavior**: Removes a user from `usersToToken`.
- **Parameters**: `token`, `user` (address).

### removeUserPool(address user, address pool)
- **Behavior**: Removes a pool from `userPools`.
- **Parameters**: `user`, `pool` (address).

### removeMakerFromActiveTokens(address maker, address token)
- **Behavior**: Removes a token from `makerActiveTokens`.
- **Parameters**: `maker`, `token` (address).

### removeMakerFromActiveListings(address maker, address listing)
- **Behavior**: Removes a listing from `makerActiveListings`.
- **Parameters**: `maker`, `listing` (address).

### removeMakerFromActiveMakers(address maker)
- **Behavior**: Removes a maker from `activeMakersToTokens`.
- **Parameters**: `maker` (address).

## Additional Details
- **Decimal Handling**: Relies on `CCLiquidityTemplate` for normalization to 1e18.
- **Gas Optimization**: Uses `maxIterations` and `step` for liquidity functions; removed from maker/token view functions for stack efficiency.
- **Events**: `LiquidityGlobalized(address user, address token, address pool, uint256 amount)`, `AgentSet(address agent)`, `OrdersGlobalized(address maker, address listing, address token, uint256[] orderIds, bool isBuy)`.
- **Safety**:
  - Explicit casting for interface calls.
  - No inline assembly, high-level Solidity.
  - Try-catch for external calls with decoded revert strings.
  - Public mappings accessed directly (e.g., `userLiquidityByToken[token][user]`).
  - No reserved keywords, no `virtual`/`override`.
- **Verification**: Validates listings via `ICCAgent.isValidListing`, globalizer via `ICCListingTemplate.globalizerAddressView`.
- **Globalization**: Tracks liquidity and orders across tokens/pools, removes zeroed-out entries for efficiency.
