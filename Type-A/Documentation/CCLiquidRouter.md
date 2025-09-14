# CCLiquidRouter Contract Documentation

## Overview
The `CCLiquidRouter` contract (Solidity ^0.8.2) settles buy/sell orders using `ICCLiquidity`, inheriting `CCLiquidPartial`. It integrates with `ICCListing`, `ICCLiquidity`, `IERC20`, and `IUniswapV2Pair`. Features include a fee system (max 1% based on liquidity usage), user-specific settlement via `makerPendingOrdersView`, and gas-efficient iteration with `step`. Uses `ReentrancyGuard` for security. Fees are transferred with `pendingAmount` and recorded in `xFees`/`yFees`. Liquidity updates: `pendingAmount` increases `xLiquid`/`yLiquid`, `amountOut` decreases `yLiquid`/`xLiquid`.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.27 (updated 2025-09-14)

**Inheritance Tree:** `CCLiquidRouter` → `CCLiquidPartial` (v0.0.40) → `CCMainPartial` (v0.1.5)

**Compatibility:** `CCListingTemplate.sol` (v0.3.9), `ICCLiquidity.sol` (v0.0.5), `CCMainPartial.sol` (v0.1.5), `CCLiquidPartial.sol` (v0.0.40), `CCLiquidityTemplate.sol` (v0.1.18)

## Mappings
- None defined in `CCLiquidRouter`. Uses `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`, `makerPendingOrdersView`) for order tracking.

## Structs
- **HistoricalUpdateContext** (`CCLiquidRouter`): Holds `xBalance`, `yBalance`, `xVolume`, `yVolume` (uint256).
- **OrderContext** (`CCLiquidPartial`): Holds `listingContract` (ICCListing), `tokenIn`, `tokenOut` (address).
- **PrepOrderUpdateResult** (`CCLiquidPartial`): Holds `tokenAddress`, `makerAddress`, `recipientAddress` (address), `tokenDecimals` (uint8), `amountReceived`, `normalizedReceived`, `amountSent`, `preTransferWithdrawn` (uint256).
- **BuyOrderUpdateContext** (`CCLiquidPartial`): Holds `makerAddress`, `recipient` (address), `status` (uint8), `amountReceived`, `normalizedReceived`, `amountSent`, `preTransferWithdrawn` (uint256).
- **SellOrderUpdateContext** (`CCLiquidPartial`): Holds `makerAddress`, `recipient` (address), `status` (uint8), `amountReceived`, `normalizedReceived`, `amountSent`, `preTransferWithdrawn` (uint256).
- **OrderBatchContext** (`CCLiquidPartial`): Holds `listingAddress` (address), `maxIterations` (uint256), `isBuyOrder` (bool).
- **SwapImpactContext** (`CCLiquidPartial`): Holds `reserveIn`, `reserveOut`, `amountInAfterFee`, `price`, `amountOut` (uint256), `decimalsIn`, `decimalsOut` (uint8).
- **FeeContext** (`CCLiquidPartial`): Holds `feeAmount`, `netAmount`, `liquidityAmount` (uint256), `decimals` (uint8).
- **OrderProcessingContext** (`CCLiquidPartial`): Holds `maxPrice`, `minPrice`, `currentPrice`, `impactPrice` (uint256).
- **LiquidityUpdateContext** (`CCLiquidPartial`): Holds `pendingAmount`, `amountOut` (uint256), `tokenDecimals` (uint8), `isBuyOrder` (bool).

## Formulas
Formulas in `CCLiquidPartial.sol` (v0.0.40) govern settlement and price impact calculations.

1. **Current Price**:
   - **Formula**: `price = listingContract.prices(0)`.
   - **Used in**: `_computeCurrentPrice`, `_validateOrderPricing`, `_processSingleOrder`.
   - **Description**: Fetches price from `ICCListing.prices(0)` with try-catch, ensuring settlement price is within `minPrice` and `maxPrice`. Reverts with detailed reason if fetch fails.
   - **Usage**: Ensures settlement price aligns with listing template in `_processSingleOrder`.

2. **Swap Impact**:
   - **Formula**:
     - `amountInAfterFee = (inputAmount * 997) / 1000` (0.3% Uniswap V2 fee).
     - `amountOut = (amountInAfterFee * normalizedReserveOut) / (normalizedReserveIn + amountInAfterFee)`.
     - `price = ((normalizedReserveIn + amountInAfterFee) * 1e18) / (normalizedReserveOut - amountOut)`.
   - **Used in**: `_computeSwapImpact`, `_processSingleOrder`, `_checkPricing`, `_validateOrderPricing`.
   - **Description**: Calculates output and hypothetical price impact for buy (input tokenB, output tokenA) or sell (input tokenA, output tokenB) orders using `balanceOf` for Uniswap V2 LP reserves, ensuring `minPrice <= price <= maxPrice`.
   - **Usage**: Restricts settlement if price impact exceeds bounds; emits `PriceOutOfBounds` for graceful degradation.

3. **Buy Order Output**:
   - **Formula**: `amountOut = (amountInAfterFee * normalizedReserveOut) / (normalizedReserveIn + amountInAfterFee)`, denormalized to tokenA decimals.
   - **Used in**: `_computeSwapImpact`, `_prepareLiquidityTransaction`, `_prepBuyLiquidUpdates`, `_computeSwapAmount`.
   - **Description**: Computes tokenA output for buy orders, aligning with `buyOutput ≈ buyPrincipal / currentPrice`, adjusted for fees and pool dynamics.

4. **Sell Order Output**:
   - **Formula**: Same as buy, with `tokenIn = tokenA`, `tokenOut = tokenB`.
   - **Used in**: `_computeSwapImpact`, `_prepareLiquidityTransaction`, `_prepSellLiquidUpdates`, `_computeSwapAmount`.
   - **Description**: Computes tokenB output for sell orders, aligning with `sellOutput ≈ sellPrincipal * currentPrice`, adjusted for fees.

5. **Normalization/Denormalization**:
   - **Normalize**: `normalize(amount, decimals) = decimals < 18 ? amount * 10^(18-decimals) : amount / 10^(decimals-18)`.
   - **Denormalize**: `denormalize(amount, decimals) = decimals < 18 ? amount / 10^(18-decimals) : amount * 10^(decimals-18)`.
   - **Used in**: `_getSwapReserves`, `_computeSwapImpact`, `_prepBuy/SellOrderUpdate`, `_processSingleOrder`, `_prepareLiquidityUpdates`, `_computeFee`, `_prepareLiquidityUpdates`.
   - **Description**: Ensures 18-decimal precision for calculations, reverting to native decimals for transfers.

6. **Fee Calculation**:
   - **Formula**: `feePercent = (normalizedPending / normalizedLiquidity) * 1e18`, capped at 1%; `feeAmount = (pendingAmount * feePercent) / 1e20`; `netAmount = pendingAmount - feeAmount`.
   - **Used in**: `_computeFee`, `_executeOrderWithFees`, `_prepareLiquidityUpdates`.
   - **Description**: Calculates fee based on liquidity usage (`xLiquid` for sell, `yLiquid` for buy).

7. **Liquidity Updates**:
   - **Formula**:
     - Buy: `xLiquid += normalize(pendingAmount)`, `yLiquid -= normalize(amountOut)`, `yFees += normalize(feeAmount)`.
     - Sell: `yLiquid += normalize(pendingAmount)`, `xLiquid -= normalize(amountOut)`, `xFees += normalize(feeAmount)`.
   - **Used in**: `_prepareLiquidityUpdates`, `ICCLiquidity.ccUpdate`.

## External Functions

### settleBuyLiquid(address listingAddress, uint256 maxIterations, uint256 step)
- **Parameters**:
  - `listingAddress` (address): `ICCListing` contract address for order book.
  - `maxIterations` (uint256): Maximum orders to process in a batch.
  - `step` (uint256): Starting index for order processing (gas optimization).
- **Behavior**: Settles buy orders for `msg.sender`. Checks pending orders via `makerPendingOrdersView(msg.sender)` and `yBalance` via `volumeBalances(0)`. Creates historical data entry if orders exist. Processes orders via `_processOrderBatch`, which handles `ccUpdate` with `BuyOrderUpdate` structs. Emits events for failures. Validates `yLiquid` and `xLiquid` before settlement, skipping orders with insufficient liquidity or invalid pricing.
- **Internal Call Flow**:
  1. `listingContract.makerPendingOrdersView(msg.sender)`: Fetches pending buy order IDs.
  2. `listingContract.volumeBalances(0)`: Checks `yBalance`.
  3. `_createHistoricalUpdate`: Creates `HistoricalUpdate` with `volumeBalances(0)`, `prices(0)`, `historicalDataLengthView`, `getHistoricalDataView`, and `block.timestamp`.
  4. `_processOrderBatch(listingAddress, maxIterations, true, step)`:
     - `_collectOrderIdentifiers`: Fetches order IDs from `step`.
     - `_processSingleOrder`: Validates prices (`_validateOrderPricing`, `_computeCurrentPrice`, `_computeSwapImpact`), checks `xLiquid`/`yLiquid`, computes fees (`_computeFee`), executes order (`_executeOrderWithFees`).
     - `_executeOrderWithFees`: Emits `FeeDeducted`, updates liquidity (`_prepareLiquidityUpdates`, `ICCLiquidity.ccUpdate`), calls `executeSingleBuyLiquid`, reverts on critical failures (execution, liquidity updates, transfers).
     - `executeSingleBuyLiquid`: Calls `_prepBuyLiquidUpdates`, `_prepBuyOrderUpdate`, `_createBuyOrderUpdates`, executes `ccUpdate` with `BuyOrderUpdate[]`.
- **Emits**: `NoPendingOrders` (empty orders or invalid step), `InsufficientBalance` (zero `yBalance` or insufficient `xLiquid`/`yLiquid`), `UpdateFailed` (batch processing failure), `PriceOutOfBounds` (invalid pricing).
- **Graceful Degradation**: Returns without reverting if no orders, `step` exceeds orders, or insufficient balance. Skips orders with insufficient liquidity or invalid pricing.
- **Note**: `amountSent` (tokenA) reflects the current settlement, accumulating total tokens sent across settlements.

### settleSellLiquid(address listingAddress, uint256 maxIterations, uint256 step)
- **Parameters**: Same as `settleBuyLiquid`.
- **Behavior**: Settles sell orders for `msg.sender`. Checks pending orders via `makerPendingOrdersView(msg.sender)` and `xBalance` via `volumeBalances(0)`. Creates historical data entry if orders exist. Processes orders via `_processOrderBatch`, which handles `ccUpdate` with `SellOrderUpdate` structs. Emits events for failures. Validates `xLiquid` and `yLiquid` before settlement, skipping orders with insufficient liquidity or invalid pricing.
- **Internal Call Flow**: Similar to `settleBuyLiquid`, but:
  - Uses `xBalance` from `volumeBalances(0)`.
  - Calls `_processOrderBatch(listingAddress, maxIterations, false, step)`:
    - Uses `getSellOrderAmounts/Core/Pricing`.
    - Updates `yLiquid`, `xLiquid`, `xFees` in `_prepareLiquidityUpdates`.
    - Calls `executeSingleSellLiquid` (uses `_prepSellLiquidUpdates`, `_createSellOrderUpdates`, `ccUpdate` with `SellOrderUpdate[]`).
- **Emits**: `NoPendingOrders`, `InsufficientBalance` (zero `xBalance` or insufficient `xLiquid`/`yLiquid`), `UpdateFailed`, `PriceOutOfBounds`.
- **Graceful Degradation**: Same as `settleBuyLiquid`.
- **Note**: `amountSent` (tokenB) reflects the current settlement, accumulating total tokens sent.

## Internal Functions (CCLiquidPartial, v0.0.40)
- **_getSwapReserves**: Fetches Uniswap V2 reserves via `IERC20.balanceOf` (`token0`, `tokenB`) into `SwapImpactContext`.
- **_computeCurrentPrice**: Fetches price from `ICCListing.prices(0)` with try-catch.
- **_computeSwapImpact**: Calculates output and price impact with 0.3% fee using `balanceOf` reserves.
- **_getTokenAndDecimals**: Retrieves token address and decimals.
- **_checkPricing**: Validates `impactPrice` within `minPrice` and `maxPrice`.
- **_computeAmountSent**: Computes pre-transfer balance.
- **_prepareLiquidityTransaction**: Computes `amountOut`, checks liquidity.
- **_prepBuyOrderUpdate**: Handles buy order transfers, sets `amountSent` (tokenA).
- **_prepSellOrderUpdate**: Handles sell order transfers, sets `amountSent` (tokenB).
- **_prepBuyLiquidUpdates**: Validates pricing, computes `amountOut`, calls `_prepBuyOrderUpdate`, `_createBuyOrderUpdates`.
- **_prepSellLiquidUpdates**: Validates pricing, computes `amountOut`, calls `_prepSellOrderUpdate`, `_createSellOrderUpdates`.
- **_executeSingleBuyLiquid**: Executes buy order via `_prepBuyLiquidUpdates`.
- **_executeSingleSellLiquid**: Executes sell order via `_prepSellLiquidUpdates`.
- **_collectOrderIdentifiers**: Fetches order IDs from `step` up to `maxIterations`.
- **_prepareLiquidityUpdates**: Transfers `pendingAmount`, updates `xLiquid`, `yLiquid`, `xFees`/`yFees` via `ICCLiquidity.ccUpdate`, reverts on critical failures (liquidity updates, transfers).
- **_validateOrderPricing**: Validates prices, emits `PriceOutOfBounds`.
- **_computeFee**: Calculates `feeAmount`, `netAmount` based on liquidity usage.
- **_computeSwapAmount**: Computes `amountOut` for liquidity updates.
- **_toSingleUpdateArray**: Converts single update to array for `ICCLiquidity.ccUpdate`.
- **_createBuyOrderUpdates**: Builds `BuyOrderUpdate` structs for `ccUpdate`.
- **_createSellOrderUpdates**: Builds `SellOrderUpdate` structs for `ccUpdate`.
- **_executeOrderWithFees**: Emits `FeeDeducted`, executes order, calls `executeSingleBuy/SellLiquid`, reverts on critical failures.
- **_processSingleOrder**: Validates prices and liquidity, computes fees, executes order, skips on insufficient liquidity or invalid pricing.
- **_processOrderBatch**: Iterates orders, skips settled orders, returns success status.
- **_finalizeUpdates**: Resizes `BuyOrderUpdate[]` or `SellOrderUpdate[]` based on `isBuyOrder`.
- **_uint2str**: Converts uint to string for error messages.

## Internal Functions (CCLiquidRouter)
- **_createHistoricalUpdate**: Fetches `volumeBalances(0)`, `prices(0)`, historical data (`xVolume`, `yVolume`); creates `HistoricalUpdate` with `block.timestamp` via `ccUpdate`.

## Security Measures
- **Reentrancy Protection**: `nonReentrant` on `settleBuyLiquid`, `settleSellLiquid`.
- **Listing Validation**: `onlyValidListing` uses `ICCAgent.isValidListing` with try-catch.
- **Safe Transfers**: `IERC20` with pre/post balance checks in `_prepBuy/SellOrderUpdate`.
- **Safety**:
  - Explicit casting for interfaces.
  - No inline assembly.
  - Hidden state variables (`agent`, `uniswapV2Router`) accessed via view functions.
  - Avoids reserved keywords, `virtual`/`override`.
  - Graceful degradation with events (`NoPendingOrders`, `InsufficientBalance`, `PriceOutOfBounds`, `UpdateFailed`, `MissingUniswapRouter`, `ApprovalFailed`, `TokenTransferFailed`, `SwapFailed`).
  - Skips settled orders via `pendingAmount == 0`.
  - Validates `step <= identifiers.length`.
  - Validates liquidity in `_prepareLiquidityTransaction` and `_processSingleOrder` (v0.0.40).
  - Struct-based `ccUpdate` calls with `BuyOrderUpdate`, `SellOrderUpdate`, `BalanceUpdate`, `HistoricalUpdate` (v0.0.25).
  - Optimized struct fields in `CCLiquidPartial.sol` v0.0.40.
  - Reverts on critical failures (execution, liquidity updates, transfers) in `_executeOrderWithFees`, `_prepareLiquidityUpdates` (v0.0.40).
  - Skips orders with insufficient `xLiquid`/`yLiquid` or invalid pricing in `_processSingleOrder` (v0.0.40).

## Limitations and Assumptions
- Relies on `ICCLiquidity` for settlements, not direct Uniswap V2 swaps.
- No order creation, cancellation, payouts, or liquidity management.
- Uses `balanceOf` for reserves in `_computeSwapImpact`.
- Zero amounts, failed transfers, or invalid prices return `false` in `_processOrderBatch`.
- `depositor` set to `address(this)` in `ICCLiquidity` calls.
- `step` must be <= length of pending orders.
- `amountSent` accumulates total tokens sent across settlements.
- Historical data created at start of settlement if orders exist.
