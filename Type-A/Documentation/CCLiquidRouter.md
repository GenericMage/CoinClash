# CCLiquidRouter Contract Documentation

## Overview
The `CCLiquidRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform using `ICCLiquidityTemplate` for liquid settlement. It inherits functionality from `CCLiquidPartial`, which extends `CCMainPartial`, and integrates with external interfaces (`ICCListing`, `ICCLiquidityTemplate`, `IERC20`, `IUniswapV2Pair`) for token operations, reserve data, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract handles liquid settlement (`settleBuyLiquid`, `settleSellLiquid`) via `ICCLiquidityTemplate`, with price impact restrictions ensuring hypothetical price changes stay within order bounds. State variables are hidden, accessed via view functions with unique names, and decimal precision is maintained. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation. All transfers to/from the listing call `listingContract.update` after successful liquidity transfers.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.4 (updated 2025-07-29)

**Inheritance Tree:** `CCLiquidRouter` → `CCLiquidPartial` → `CCMainPartial`

**Compatibility:** CCListingTemplate.sol (v0.0.6), CCMainPartial.sol (v0.0.9), CCLiquidPartial.sol (v0.0.4), CCLiquidityRouter.sol (v0.0.14).

## Mappings
- None defined directly in `CCLiquidRouter`. Relies on `ICCListing` view functions (e.g., `pendingBuyOrdersView`, `pendingSellOrdersView`) for order tracking.

## Structs
- **OrderContext**: Contains `listingContract` (ICCListing), `tokenIn` (address), `tokenOut` (address), `liquidityAddr` (address).
- **PrepOrderUpdateResult**: Contains `tokenAddress` (address), `tokenDecimals` (uint8), `makerAddress` (address), `recipientAddress` (address), `orderStatus` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, denormalized).
- **BuyOrderUpdateContext**: Contains `makerAddress` (address), `recipient` (address), `status` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, denormalized, tokenA for buy).
- **SellOrderUpdateContext**: Same as `BuyOrderUpdateContext`, with `amountSent` (tokenB for sell).
- **SwapImpactContext**: Contains `reserveIn` (uint256), `reserveOut` (uint256), `decimalsIn` (uint8), `decimalsOut` (uint8), `normalizedReserveIn` (uint256), `normalizedReserveOut` (uint256), `amountInAfterFee` (uint256), `price` (uint256), `amountOut` (uint256).

## Formulas
The formulas govern liquid settlement calculations in `CCLiquidPartial.sol` and price impact in `CCLiquidRouter.sol`.

1. **Price Validation**:
   - **Formula**: `maxPrice >= minPrice`
   - **Used in**: `_checkPricing`, `_prepBuyLiquidUpdates`, `_prepSellLiquidUpdates`.
   - **Description**: Validates order pricing by comparing `maxPrice` and `minPrice` from `getBuyOrderPricing` or `getSellOrderPricing`.
   - **Usage**: Ensures trades meet order price constraints before liquidity transfers.

2. **Buy Order Output**:
   - **Formula**: `amountOut = inputAmount` (simplified, assumes external swap logic).
   - **Used in**: `_prepareLiquidityTransaction`, `_prepBuyLiquidUpdates`.
   - **Description**: Computes tokenA output for buy orders, using input amount directly.

3. **Sell Order Output**:
   - **Formula**: Same as buy order output, with `tokenIn = tokenA`, `tokenOut = tokenB`.
   - **Used in**: `_prepareLiquidityTransaction`, `_prepSellLiquidUpdates`.
   - **Description**: Computes tokenB output for sell orders, using input amount directly.

4. **Swap Impact Price**:
   - **Formula**: `price = (inputAmount * 1e18) / amountOut`, where `amountOut = (amountInAfterFee * normalizedReserveOut) / (normalizedReserveIn + amountInAfterFee)`, `amountInAfterFee = (inputAmount * 997) / 1000`.
   - **Used in**: `_computeSwapImpact`, `settleBuyLiquid`, `settleSellLiquid`.
   - **Description**: Computes hypothetical price impact using Uniswap V2 reserves, applying 0.3% fee. Ensures `price` is within `minPrice` and `maxPrice`.
   - **Usage**: Restricts settlement if price impact exceeds order bounds.

## External Functions

### settleBuyLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Settles pending buy orders up to `maxIterations` using `ICCLiquidityTemplate`, transferring tokenA to recipients, updating liquidity (tokenB), tracking `amountSent` (tokenA), and calling `listingContract.update` after successful transfers. Ensures hypothetical price impact (`_computeSwapImpact`) stays within order bounds (`minPrice <= price <= maxPrice`).
- **Internal Call Flow**:
  - Fetches `orderIdentifiers` via `pendingBuyOrdersView`.
  - Iterates up to `maxIterations`:
    - Fetches `(pendingAmount, , )` via `getBuyOrderAmounts`, `(maxPrice, minPrice)` via `getBuyOrderPricing`.
    - Computes `price` via `_computeSwapImpact` using Uniswap V2 reserves.
    - If `minPrice <= price <= maxPrice`, calls `executeSingleBuyLiquid`:
      - Fetches `(pendingAmount, filled, amountSent)` via `getBuyOrderAmounts`.
      - Validates pricing via `_checkPricing` (`maxPrice >= minPrice`).
      - Computes `amountOut`, `tokenIn`, `tokenOut` via `_prepareLiquidityTransaction`.
      - Transfers principal (tokenB) via `_checkAndTransferPrincipal`.
      - Transfers tokenA via `listingContract.transactNative` or `transactToken`.
      - Updates liquidity (tokenB) via `_updateLiquidity`.
      - Creates `ICCListing.UpdateType[]` via `_prepBuyLiquidUpdates`, `_createBuyOrderUpdates`.
  - Collects updates in `tempUpdates`, resizes to `finalUpdates`, applies via `listingContract.update`.
- **Balance Checks**:
  - `_checkAndTransferPrincipal`: Ensures `amountSent > 0`, `amountReceived > 0` for principal.
  - `_prepBuyOrderUpdate`, `_prepBuyLiquidUpdates`: Pre/post balance checks for tokenA transfer.
- **Mappings/Structs Used**:
  - **Structs**: `OrderContext`, `PrepOrderUpdateResult`, `BuyOrderUpdateContext`, `ICCListing.UpdateType`, `SwapImpactContext`.
- **Restrictions**:
  - Protected by `nonReentrant`, `onlyValidListing`.
  - Requires `liquidityContract.routers(address(this))`.
  - Reverts if pricing invalid, transfers fail, liquidity insufficient, or price impact exceeds bounds.
- **Gas Usage Controls**: `maxIterations`, dynamic array resizing.

### settleSellLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyLiquid`.
- **Behavior**: Settles pending sell orders up to `maxIterations` using `ICCLiquidityTemplate`, transferring tokenB to recipients, updating liquidity (tokenA), tracking `amountSent` (tokenB), and calling `listingContract.update`. Ensures hypothetical price impact stays within order bounds.
- **Internal Call Flow**:
  - Fetches `orderIdentifiers` via `pendingSellOrdersView`.
  - Iterates up to `maxIterations`:
    - Fetches `(pendingAmount, , )` via `getSellOrderAmounts`, `(maxPrice, minPrice)` via `getSellOrderPricing`.
    - Computes `price` via `_computeSwapImpact`.
    - If `minPrice <= price <= maxPrice`, calls `executeSingleSellLiquid`:
      - Fetches `(pendingAmount, filled, amountSent)` via `getSellOrderAmounts`.
      - Validates pricing via `_checkPricing` (`maxPrice >= minPrice`).
      - Computes `amountOut`, `tokenIn`, `tokenOut` via `_prepareLiquidityTransaction`.
      - Transfers principal (tokenA) via `_checkAndTransferPrincipal`.
      - Transfers tokenB via `listingContract.transactNative` or `transactToken`.
      - Updates liquidity (tokenA) via `_updateLiquidity`.
      - Creates `ICCListing.UpdateType[]` via `_prepSellLiquidUpdates`, `_createSellOrderUpdates`.
  - Collects updates in `tempUpdates`, resizes to `finalUpdates`, applies via `listingContract.update`.
- **Balance Checks**: Same as `settleBuyLiquid`.
- **Mappings/Structs Used**:
  - **Structs**: `OrderContext`, `PrepOrderUpdateResult`, `SellOrderUpdateContext`, `ICCListing.UpdateType`, `SwapImpactContext`.
- **Restrictions**: Same as `settleBuyLiquid`.
- **Gas Usage Controls**: Same as `settleBuyLiquid`.

### setAgent(address newAgent)
- **Parameters**:
  - `newAgent` (address): New ICCAgent address.
- **Behavior**: Updates `agent` state variable for listing validation, inherited from `CCMainPartial`.
- **Internal Call Flow**: Direct state update, validates `newAgent` is non-zero.
- **Mappings/Structs Used**:
  - **agent** (state variable): Stores ICCAgent address.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `newAgent` is zero (`"Invalid agent address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

## Clarifications and Nuances

### ICCLiquidityTemplate Integration
- **Liquid Settlement Process**: `settleBuyLiquid` and `settleSellLiquid` transfer principal from listing to `ICCLiquidityTemplate` (`_checkAndTransferPrincipal`), update liquidity (`_updateLiquidity`), transfer output tokens to recipients via listing contract, and call `listingContract.update`.
- **Router Registration**: Requires `liquidityContract.routers(address(this))` to be true.
- **Balance Checks**: Pre/post balance checks in `_checkAndTransferPrincipal`, `_prepBuy/SellOrderUpdate`, `_prepBuy/SellLiquidUpdates` handle fee-on-transfer tokens and ETH.

### Price Impact Restrictions
- **Validation**: Uses `_computeSwapImpact` to calculate hypothetical price impact using Uniswap V2 reserves (0.3% fee). Orders are only settled if `minPrice <= price <= maxPrice`.
- **Implementation**: Added `SwapImpactContext`, `_getSwapReserves`, `_computeSwapImpact` to check price impact before calling `executeSingleBuyLiquid` or `executeSingleSellLiquid`.

### Decimal Handling
- **Normalization**: Amounts normalized to 18 decimals via `normalize` (inherited) for consistent calculations.
- **Denormalization**: Input/output amounts denormalized to native decimals via `denormalize`.
- **ETH Handling**: ETH transfers use 18 decimals, `msg.value`.

### Order Settlement Mechanics
- **Execution**: Orders processed fully (status 3) if `normalizedReceived >= pendingAmount`, otherwise skipped.
- **Amount Tracking**: `amountSent` tracks output tokens (tokenA for buy, tokenB for sell), `amountReceived`/`normalizedReceived` track received tokens.
- **Pricing**: `_checkPricing` uses `maxPrice >= minPrice`, supplemented by `_computeSwapImpact` for impact validation.

### Gas Optimization
- **Max Iterations**: `maxIterations` limits loop iterations.
- **Dynamic Arrays**: `tempUpdates` oversized (`iterationCount * 3`), resized to `finalUpdates`.
- **Helper Functions**: Logic split into `_getSwapReserves`, `_computeSwapImpact`, `_prepareLiquidityTransaction`, `_checkAndTransferPrincipal`, `_prepBuy/SellLiquidUpdates`.

### Security Measures
- **Reentrancy Protection**: `nonReentrant` on all external functions.
- **Listing Validation**: `onlyValidListing` checks `ICCAgent.getListing`.
- **Safe Transfers**: IERC20 from `CCMainPartial` with pre/post balance checks.
- **Router Validation**: Requires `liquidityContract.routers(address(this))`.
- **Safety**:
  - Explicit casting for interfaces.
  - No inline assembly.
  - Hidden state variables (`agent`) accessed via `agentView`.
  - Avoids reserved keywords, unnecessary virtual/override.

### Limitations and Assumptions
- **No Uniswap V2 Swaps**: Relies on `ICCLiquidityTemplate` for settlements.
- **No Order Creation/Cancellation**: Lacks order creation, cancellation, payouts, liquidity management.
- **Price Impact**: Uses Uniswap V2 reserves for hypothetical price impact, not actual swaps.
- **Zero-Amount Handling**: Zero amounts or failed transfers return empty `ICCListing.UpdateType[]`.

### Differences from CCSettlementRouter
- **Scope**: Focuses on liquid settlements, omitting Uniswap V2-based settlements, order creation, cancellation, payouts, liquidity management.
- **Inheritance**: Inherits `CCLiquidPartial`, `CCMainPartial`, excludes `CCUniPartial`, `CCSettlementPartial`.
- **Pricing**: Uses `_computeSwapImpact` for impact restrictions, retains simplified `_checkPricing`.

## Additional Details
- **Decimal Handling**: Normalizes to 1e18, denormalizes for transfers, ETH uses 18 decimals.
- **Reentrancy Protection**: `nonReentrant` on all state-changing functions.
- **Gas Optimization**: `maxIterations`, dynamic arrays, helper functions.
- **Listing Validation**: `onlyValidListing` ensures listing integrity.
- **Token Usage**:
  - Buy orders: Input tokenB, output tokenA, `amountSent` tracks tokenA.
  - Sell orders: Input tokenA, output tokenB, `amountSent` tracks tokenB.
- **Events**: Relies on `listingContract`, `liquidityContract` events.
- **Safety**:
  - Explicit casting for interfaces.
  - No inline assembly.
  - Hidden state variables accessed via view functions.
  - Avoids reserved keywords, unnecessary virtual/override.
