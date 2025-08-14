# CCLiquidRouter Contract Documentation

## Overview
The `CCLiquidRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform using `ICCLiquidity` for liquid settlement. It inherits functionality from `CCLiquidPartial`, which extends `CCMainPartial`, and integrates with external interfaces (`ICCListing`, `ICCLiquidity`, `IERC20`, `IUniswapV2Pair`) for token operations, reserve data, `ReentrancyGuard` for reentrancy protection, and `Ownable` (via `ReentrancyGuard`) for administrative control. The contract handles liquid settlement (`settleBuyLiquid`, `settleSellLiquid`) via `ICCLiquidity`, with price impact restrictions ensuring hypothetical price changes stay within order bounds. State variables are hidden, accessed via view functions with unique names, and decimal precision is maintained. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation with revert reasons. All transfers to/from the listing call `listingContract.update` after successful liquidity transfers.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.8 (updated 2025-08-14)

**Inheritance Tree:** `CCLiquidRouter` → `CCLiquidPartial` → `CCMainPartial`

**Compatibility:** CCListingTemplate.sol (v0.0.10), ICCLiquidity.sol (v0.0.4), CCMainPartial.sol (v0.0.14), CCLiquidPartial.sol (v0.0.11), CCLiquidityRouter.sol (v0.0.25), CCLiquidityTemplate.sol (v0.1.0).

## Mappings
- None defined directly in `CCLiquidRouter`. Relies on `ICCListing` view functions (e.g., `pendingBuyOrdersView`, `pendingSellOrdersView`) for order tracking.

## Structs
- **OrderContext** (in `CCLiquidPartial`): Contains `listingContract` (ICCListing), `tokenIn` (address), `tokenOut` (address), `liquidityAddr` (address).
- **PrepOrderUpdateResult** (in `CCLiquidPartial`): Contains `tokenAddress` (address), `tokenDecimals` (uint8), `makerAddress` (address), `recipientAddress` (address), `orderStatus` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, denormalized).
- **BuyOrderUpdateContext** (in `CCLiquidPartial`): Contains `makerAddress` (address), `recipient` (address), `status` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, denormalized, tokenA for buy).
- **SellOrderUpdateContext** (in `CCLiquidPartial`): Same as `BuyOrderUpdateContext`, with `amountSent` (tokenB for sell).
- **OrderBatchContext** (in `CCLiquidPartial`): Contains `listingAddress` (address), `maxIterations` (uint256), `isBuyOrder` (bool).
- **SwapImpactContext** (in `CCLiquidPartial`): Contains `reserveIn` (uint256), `reserveOut` (uint256), `decimalsIn` (uint8), `decimalsOut` (uint8), `normalizedReserveIn` (uint256), `normalizedReserveOut` (uint256), `amountInAfterFee` (uint256), `price` (uint256), `amountOut` (uint256).

## Formulas
The formulas govern liquid settlement calculations and price impact in `CCLiquidPartial.sol`.

1. **Price Validation**:
   - **Formula**: `maxPrice >= minPrice`
   - **Used in**: `_checkPricing`, `_prepBuyLiquidUpdates`, `_prepSellLiquidUpdates`.
   - **Description**: Validates order pricing by comparing `maxPrice` and `minPrice` from `getBuyOrderPricing` or `getSellOrderPricing`.
   - **Usage**: Ensures trades meet order price constraints before liquidity transfers.

2. **Buy Order Output**:
   - **Formula**: `amountOut = inputAmount` (simplified, assumes external swap logic in `ICCLiquidity`).
   - **Used in**: `_prepareLiquidityTransaction`, `_prepBuyLiquidUpdates`.
   - **Description**: Computes tokenA output for buy orders, using input amount directly.

3. **Sell Order Output**:
   - **Formula**: Same as buy order output, with `tokenIn = tokenA`, `tokenOut = tokenB`.
   - **Used in**: `_prepareLiquidityTransaction`, `_prepSellLiquidUpdates`.
   - **Description**: Computes tokenB output for sell orders, using input amount directly.

4. **Swap Impact Price**:
   - **Formula**: `price = (inputAmount * 1e18) / amountOut`, where `amountOut = (amountInAfterFee * normalizedReserveOut) / (normalizedReserveIn + amountInAfterFee)`, `amountInAfterFee = (inputAmount * 997) / 1000`.
   - **Used in**: `_computeSwapImpact`, `_processSingleOrder`.
   - **Description**: Computes hypothetical price impact using Uniswap V2 reserves, applying 0.3% fee. Ensures `price` is within `minPrice` and `maxPrice`.
   - **Usage**: Restricts settlement if price impact exceeds order bounds.

## External Functions

### settleBuyLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Address of the `ICCListing` contract managing the order book.
  - `maxIterations` (uint256): Maximum number of buy orders to process, controlling gas usage.
- **Behavior**: Settles up to `maxIterations` pending buy orders by transferring tokenA to recipients, updating liquidity with tokenB, tracking `amountSent` (tokenA), and calling `listingContract.update`. Ensures price impact (`_computeSwapImpact`) stays within `minPrice` and `maxPrice`. Uses `ICCLiquidity` for liquidity updates with `depositor` set to `address(this)`.
- **Internal Call Flow**:
  - Calls `_processOrderBatch` (in `CCLiquidPartial`):
    - Creates `OrderBatchContext` (`listingAddress`, `maxIterations`, `isBuyOrder = true`).
    - Calls `_collectOrderIdentifiers` to fetch `orderIdentifiers` via `pendingBuyOrdersView` and set `iterationCount`.
    - Iterates up to `iterationCount`:
      - Fetches `(pendingAmount, , )` via `getBuyOrderAmounts`.
      - Calls `_processSingleOrder`:
        - Fetches `(maxPrice, minPrice)` via `getBuyOrderPricing`.
        - Computes `price` via `_computeSwapImpact` using Uniswap V2 reserves.
        - If `minPrice <= price <= maxPrice`, calls `executeSingleBuyLiquid`:
          - Fetches `(pendingAmount, filled, amountSent)` via `getBuyOrderAmounts`.
          - Validates pricing via `_checkPricing` (`maxPrice >= minPrice`).
          - Computes `amountOut`, `tokenIn`, `tokenOut` via `_prepareLiquidityTransaction`.
          - Transfers principal (tokenB) via `_checkAndTransferPrincipal`.
          - Transfers tokenA via `listingContract.transactNative` or `transactToken`.
          - Updates liquidity (tokenB) via `_updateLiquidity`, calling `ICCLiquidity.updateLiquidity(address(this), true, normalizedAmount)`.
          - Creates `ICCListing.UpdateType[]` via `_prepBuyLiquidUpdates`, `_createBuyOrderUpdates`.
    - Collects updates in `tempUpdates`, resizes via `_finalizeUpdates` to `finalUpdates`.
  - Applies `finalUpdates` via `listingContract.update`.
- **Balance Checks**:
  - `_checkAndTransferPrincipal`: Ensures `amountSent > 0`, `amountReceived > 0` for principal (tokenB).
  - `_prepBuyOrderUpdate`, `_prepBuyLiquidUpdates`: Pre/post balance checks for tokenA transfer.
- **Mappings/Structs Used**:
  - **Structs**: `OrderContext`, `PrepOrderUpdateResult`, `BuyOrderUpdateContext`, `OrderBatchContext`, `SwapImpactContext`, `ICCListing.UpdateType`.
- **Interactions**:
  - **ICCListing**: Calls `pendingBuyOrdersView`, `getBuyOrderAmounts`, `getBuyOrderPricing`, `transactNative`, `transactToken`, `update`.
  - **ICCLiquidity**: Calls `liquidityAmounts`, `updateLiquidity` (with `depositor = address(this)`).
  - **IERC20**: Checks balances for token transfers.
  - **IUniswapV2Pair**: Fetches reserves via `getReserves` (in `_getSwapReserves`).
- **Restrictions**:
  - Protected by `nonReentrant`, `onlyValidListing`.
  - Reverts if pricing invalid, transfers fail, liquidity insufficient, or price impact exceeds bounds (`"Invalid pricing"`, `"No amount sent from listing"`, `"No amount received by liquidity"`, `"Zero reserves"`).
- **Gas Usage Controls**: Uses `maxIterations`, resizes `tempUpdates` to `finalUpdates` dynamically.

### settleSellLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyLiquid`.
- **Behavior**: Settles up to `maxIterations` pending sell orders by transferring tokenB to recipients, updating liquidity with tokenA, tracking `amountSent` (tokenB), and calling `listingContract.update`. Ensures price impact stays within `minPrice` and `maxPrice`. Uses `ICCLiquidity` for liquidity updates with `depositor` set to `address(this)`.
- **Internal Call Flow**:
  - Calls `_processOrderBatch` (in `CCLiquidPartial`):
    - Creates `OrderBatchContext` (`listingAddress`, `maxIterations`, `isBuyOrder = false`).
    - Calls `_collectOrderIdentifiers` to fetch `orderIdentifiers` via `pendingSellOrdersView` and set `iterationCount`.
    - Iterates up to `iterationCount`:
      - Fetches `(pendingAmount, , )` via `getSellOrderAmounts`.
      - Calls `_processSingleOrder`:
        - Fetches `(maxPrice, minPrice)` via `getSellOrderPricing`.
        - Computes `price` via `_computeSwapImpact`.
        - If `minPrice <= price <= maxPrice`, calls `executeSingleSellLiquid`:
          - Fetches `(pendingAmount, filled, amountSent)` via `getSellOrderAmounts`.
          - Validates pricing via `_checkPricing` (`maxPrice >= minPrice`).
          - Computes `amountOut`, `tokenIn`, `tokenOut` via `_prepareLiquidityTransaction`.
          - Transfers principal (tokenA) via `_checkAndTransferPrincipal`.
          - Transfers tokenB via `listingContract.transactNative` or `transactToken`.
          - Updates liquidity (tokenA) via `_updateLiquidity`, calling `ICCLiquidity.updateLiquidity(address(this), false, normalizedAmount)`.
          - Creates `ICCListing.UpdateType[]` via `_prepSellLiquidUpdates`, `_createSellOrderUpdates`.
    - Collects updates in `tempUpdates`, resizes via `_finalizeUpdates` to `finalUpdates`.
  - Applies `finalUpdates` via `listingContract.update`.
- **Balance Checks**:
  - `_checkAndTransferPrincipal`: Ensures `amountSent > 0`, `amountReceived > 0` for principal (tokenA).
  - `_prepSellOrderUpdate`, `_prepSellLiquidUpdates`: Pre/post balance checks for tokenB transfer.
- **Mappings/Structs Used**:
  - **Structs**: `OrderContext`, `PrepOrderUpdateResult`, `SellOrderUpdateContext`, `OrderBatchContext`, `SwapImpactContext`, `ICCListing.UpdateType`.
- **Interactions**:
  - **ICCListing**: Calls `pendingSellOrdersView`, `getSellOrderAmounts`, `getSellOrderPricing`, `transactNative`, `transactToken`, `update`.
  - **ICCLiquidity**: Calls `liquidityAmounts`, `updateLiquidity` (with `depositor = address(this)`).
  - **IERC20**: Checks balances for token transfers.
  - **IUniswapV2Pair**: Fetches reserves via `getReserves` (in `_getSwapReserves`).
- **Restrictions**: Same as `settleBuyLiquid`.
- **Gas Usage Controls**: Same as `settleBuyLiquid`.

### setAgent(address newAgent)
- **Parameters**:
  - `newAgent` (address): New `ICCAgent` address for listing validation.
- **Behavior**: Updates the `agent` state variable (inherited from `CCMainPartial`) used in `onlyValidListing` modifier to validate listings via `ICCAgent.isValidListing`.
- **Internal Call Flow**: Direct state update, validates `newAgent` is non-zero.
- **Mappings/Structs Used**:
  - **agent** (state variable, in `CCMainPartial`): Stores `ICCAgent` address.
- **Interactions**:
  - **ICCAgent**: Used in `onlyValidListing` to verify listing validity via `isValidListing`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `newAgent` is zero (`"Invalid agent address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

### setUniswapV2Router(address newRouter)
- **Parameters**:
  - `newRouter` (address): New Uniswap V2 router address.
- **Behavior**: Updates the `uniswapV2Router` state variable (inherited from `CCMainPartial`) for potential future Uniswap V2 integrations.
- **Internal Call Flow**: Direct state update, validates `newRouter` is non-zero.
- **Mappings/Structs Used**:
  - **uniswapV2Router** (state variable, in `CCMainPartial`): Stores Uniswap V2 router address.
- **Interactions**: None currently, reserved for future use.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `newRouter` is zero (`"Invalid router address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

### agentView() returns (address)
- **Behavior**: Returns the current `agent` address (inherited from `CCMainPartial`).
- **Internal Call Flow**: Direct read of `agent` state variable.
- **Mappings/Structs Used**:
  - **agent** (state variable, in `CCMainPartial`).
- **Interactions**: None.
- **Restrictions**: None (public view function).
- **Gas Usage Controls**: Minimal gas due to simple read.

### uniswapV2RouterView() returns (address)
- **Behavior**: Returns the current `uniswapV2Router` address (inherited from `CCMainPartial`).
- **Internal Call Flow**: Direct read of `uniswapV2Router` state variable.
- **Mappings/Structs Used**:
  - **uniswapV2Router** (state variable, in `CCMainPartial`).
- **Interactions**: None.
- **Restrictions**: None (public view function).
- **Gas Usage Controls**: Minimal gas due to simple read.

## Clarifications and Nuances

### ICCLiquidity Integration
- **Liquid Settlement Process**: `settleBuyLiquid` and `settleSellLiquid` transfer principal (tokenB for buy, tokenA for sell) from listing to `ICCLiquidity` via `_checkAndTransferPrincipal`, update liquidity via `_updateLiquidity` (calling `ICCLiquidity.updateLiquidity` with `depositor = address(this)`), transfer output tokens (tokenA for buy, tokenB for sell) to recipients via listing contract, and call `listingContract.update` with `depositor = address(this)`.
- **Router Registration**: Router validation is handled by `CCLiquidityTemplate.sol` via the `routers` mapping in functions like `update`, `transactToken`, `transactNative`, ensuring only authorized routers can call these functions.
- **Depositor Usage**: `depositor` is set to `address(this)` in `ICCLiquidity` calls (`updateLiquidity`, `transactToken`, `transactNative`), aligning with `ICCLiquidity.sol` (v0.0.4) updates replacing `caller` with `depositor` for consistency.
- **Balance Checks**: Pre/post balance checks in `_checkAndTransferPrincipal`, `_prepBuy/SellOrderUpdate`, `_prepBuy/SellLiquidUpdates` handle fee-on-transfer tokens and ETH.

### Price Impact Restrictions
- **Validation**: Uses `_computeSwapImpact` (in `CCLiquidPartial`) to calculate hypothetical price impact using Uniswap V2 reserves (0.3% fee). Orders are only settled if `minPrice <= price <= maxPrice`.
- **Implementation**: Uses `SwapImpactContext`, `_getSwapReserves`, `_computeSwapImpact` in `_processSingleOrder` to check price impact before calling `executeSingleBuyLiquid` or `executeSingleSellLiquid`.

### Decimal Handling
- **Normalization**: Amounts normalized to 1e18 via `normalize` (inherited) for calculations in `_updateLiquidity`, `_prepBuy/SellOrderUpdate`, `_computeSwapImpact`.
- **Denormalization**: Input/output amounts denormalized to native decimals via `denormalize` for transfers in `_prepBuy/SellOrderUpdate`.
- **ETH Handling**: ETH transfers use 18 decimals, `msg.value` in `transactNative`.

### Order Settlement Mechanics
- **Execution**: Orders processed fully (status 3) if `normalizedReceived >= pendingAmount`, otherwise skipped (returns empty `UpdateType[]`).
- **Amount Tracking**: `amountSent` tracks output tokens (tokenA for buy, tokenB for sell), `amountReceived`/`normalizedReceived` track received tokens.
- **Pricing**: `_checkPricing` uses `maxPrice >= minPrice`, supplemented by `_computeSwapImpact` for impact validation.

### Gas Optimization
- **Max Iterations**: `maxIterations` limits loop iterations in `settleBuyLiquid`, `settleSellLiquid`.
- **Dynamic Arrays**: `tempUpdates` oversized (`iterationCount * 3`), resized to `finalUpdates` in `_finalizeUpdates` for `listingContract.update`.
- **Helper Functions**: Logic split into `_collectOrderIdentifiers`, `_processOrderBatch`, `_processSingleOrder`, `_finalizeUpdates`, `_getSwapReserves`, `_computeSwapImpact`, `_prepareLiquidityTransaction`, `_checkAndTransferPrincipal`, `_prepBuy/SellLiquidUpdates`, `_createBuy/SellOrderUpdates`.

### Security Measures
- **Reentrancy Protection**: `nonReentrant` on `settleBuyLiquid`, `settleSellLiquid`.
- **Listing Validation**: `onlyValidListing` checks `ICCAgent.isValidListing` with try-catch, validating non-zero addresses and token pair integrity.
- **Safe Transfers**: Uses `IERC20` from `CCMainPartial` with pre/post balance checks in `_checkAndTransferPrincipal`, `_prepBuy/SellOrderUpdate`.
- **Safety**:
  - Explicit casting for interfaces (`ICCListing`, `ICCLiquidity`, `IERC20`, `IUniswapV2Pair`).
  - No inline assembly, per style guide.
  - Hidden state variables (`agent`, `uniswapV2Router`) accessed via `agentView`, `uniswapV2RouterView`.
  - Avoids reserved keywords, unnecessary `virtual`/`override`.
  - Graceful degradation with descriptive revert reasons (e.g., `"Invalid pricing"`, `"No amount sent from listing"`, `"Listing validation failed: <reason>"`).

### Limitations and Assumptions
- **No Uniswap V2 Swaps**: Relies on `ICCLiquidity` for settlements, not direct Uniswap V2 swaps.
- **No Order Creation/Cancellation**: Lacks order creation, cancellation, payouts, or liquidity management, focusing solely on liquid settlement.
- **Price Impact**: Uses Uniswap V2 reserves for hypothetical price impact, not actual swaps.
- **Zero-Amount Handling**: Zero amounts or failed transfers return empty `ICCListing.UpdateType[]` in `_prepBuy/SellLiquidUpdates`.
- **Depositor Usage**: `depositor` set to `address(this)` in `ICCLiquidity` calls for consistency, not used for user-specific state updates in `settleBuyLiquid` or `settleSellLiquid`.

### Differences from CCSettlementRouter
- **Scope**: Focuses on liquid settlements via `ICCLiquidity`, omitting Uniswap V2-based settlements, order creation, cancellation, payouts, or liquidity management.
- **Inheritance**: Inherits `CCLiquidPartial`, `CCMainPartial`, excludes `CCUniPartial`, `CCSettlementPartial`.
- **Pricing**: Uses `_computeSwapImpact` for price impact restrictions, retains simplified `_checkPricing`.
- **Refactoring**: Uses `_processOrderBatch`, `_processSingleOrder`, `_collectOrderIdentifiers`, `_finalizeUpdates` to address stack-too-deep errors, with `OrderBatchContext` for data passing.

## Additional Details
- **Decimal Handling**: Normalizes to 1e18 for calculations, denormalizes for transfers, ETH uses 18 decimals.
- **Reentrancy Protection**: `nonReentrant` on all state-changing functions.
- **Gas Optimization**: Uses `maxIterations`, dynamic array resizing, helper functions for modularity.
- **Listing Validation**: `onlyValidListing` ensures listing integrity via `ICCAgent.isValidListing`.
- **Token Usage**:
  - Buy orders: Input tokenB, output tokenA, `amountSent` tracks tokenA.
  - Sell orders: Input tokenA, output tokenB, `amountSent` tracks tokenB.
- **Events**: Relies on `listingContract` (`LiquidityUpdated`, `FeesUpdated`) and `liquidityContract` events, does not emit own events.
- **Safety**:
  - Explicit interface casting for `ICCListing`, `ICCLiquidity`, `IERC20`, `IUniswapV2Pair`.
  - No inline assembly, per style guide.
  - Hidden state variables (`agent`, `uniswapV2Router`) accessed via view functions (`agentView`, `uniswapV2RouterView`).
  - Avoids reserved keywords, unnecessary `virtual`/`override`.
