# CCLiquidRouter Contract Documentation

## Overview
The `CCLiquidRouter` contract (Solidity ^0.8.2) settles buy/sell orders using `ICCLiquidity`, inheriting `CCLiquidPartial`. It integrates with `ICCListing`, `ICCLiquidity`, `IERC20`, and `IUniswapV2Pair`. Features include a fee system (max 1% based on liquidity usage), user-specific settlement via `makerPendingOrdersView`, and gas-efficient iteration with `step`. Uses `ReentrancyGuard` for security. Fees are transferred with `pendingAmount` and recorded in `xFees`/`yFees`. Liquidity updates: `pendingAmount` increases `xLiquid`/`yLiquid`, `amountOut` decreases `yLiquid`/`xLiquid`.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.24 (updated 2025-09-10)

**Inheritance Tree:** `CCLiquidRouter` → `CCLiquidPartial` (v0.0.37) → `CCMainPartial` (v0.1.5)

**Compatibility:** `CCListingTemplate.sol` (v0.3.2), `ICCLiquidity.sol` (v0.0.5), `CCMainPartial.sol` (v0.1.5), `CCLiquidPartial.sol` (v0.0.37), `CCLiquidityTemplate.sol` (v0.1.18)

## Mappings
- None defined in `CCLiquidRouter`. Uses `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`, `makerPendingOrdersView`) for order tracking.

## Structs
- **HistoricalUpdateContext** (`CCLiquidRouter`): Holds `xBalance`, `yBalance`, `xVolume`, `yVolume` (uint256).
- **OrderContext** (`CCLiquidPartial`): Holds `listingContract` (ICCListing), `tokenIn`, `tokenOut` (address). Optimized in v0.0.337 by removing unused `liquidityAddr`.
- **PrepOrderUpdateResult** (`CCLiquidPartial`): Holds `tokenAddress`, `makerAddress`, `recipientAddress` (address), `tokenDecimals` (uint8), `amountReceived`, `normalizedReceived`, `amountSent`, `preTransferWithdrawn` (uint256). Optimized in v0.0.337 by removing unused `orderStatus`.
- **BuyOrderUpdateContext** (`CCLiquidPartial`): Holds `makerAddress`, `recipient` (address), `status` (uint8), `amountReceived`, `normalizedReceived`, `amountSent`, `preTransferWithdrawn` (uint256).
- **SellOrderUpdateContext** (`CCLiquidPartial`): Holds `makerAddress`, `recipient` (address), `status` (uint8), `amountReceived`, `normalizedReceived`, `amountSent`, `preTransferWithdrawn` (uint256).
- **OrderBatchContext** (`CCLiquidPartial`): Holds `listingAddress` (address), `maxIterations` (uint256), `isBuyOrder` (bool).
- **SwapImpactContext** (`CCLiquidPartial`): Holds `reserveIn`, `reserveOut`, `amountInAfterFee`, `price`, `amountOut` (uint256), `decimalsIn`, `decimalsOut` (uint8). Optimized in v0.0.337 by removing unused `normalizedReserveIn`, `normalizedReserveOut`.
- **FeeContext** (`CCLiquidPartial`): Holds `feeAmount`, `netAmount`, `liquidityAmount` (uint256), `decimals` (uint8).
- **OrderProcessingContext** (`CCLiquidPartial`): Holds `maxPrice`, `minPrice`, `currentPrice`, `impactPrice` (uint256).
- **LiquidityUpdateContext** (`CCLiquidPartial`): Holds `pendingAmount`, `amountOut` (uint256), `tokenDecimals` (uint8), `isBuyOrder` (bool).

## Formulas
Formulas in `CCLiquidPartial.sol` (v0.0.337) govern settlement and price impact calculations.

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
   - **Used in**: `_getSwapReserves`, `_computeSwapImpact`, `_prepBuy/SellOrderUpdate`, `_processSingleOrder`, `_updateLiquidityBalances`, `_computeFee`, `_prepareLiquidityUpdates`.
   - **Description**: Ensures 18-decimal precision for calculations, reverting to native decimals for transfers.

6. **Fee Calculation**:
   - **Formula**: `feePercent = (normalizedPending / normalizedLiquidity) * 1e18`, capped at 1%; `feeAmount = (pendingAmount * feePercent) / 1e20`; `netAmount = pendingAmount - feeAmount`.
   - **Used in**: `_computeFee`, `_executeOrderWithFees`, `_prepareLiquidityUpdates`.
   - **Description**: Calculates fee based on liquidity usage (`xLiquid` for sell, `yLiquid` for buy). Optimized in v0.0.337 by removing redundant `_computeFeeAndLiquidity`.

7. **Liquidity Updates**:
   - **Formula**:
     - Buy: `xLiquid += normalize(pendingAmount)`, `yLiquid -= normalize(amountOut)`, `yFees += normalize(feeAmount)`.
     - Sell: `yLiquid += normalize(pendingAmount)`, `xLiquid -= normalize(amountOut)`, `xFees += normalize(feeAmount)`.
   - **Used in**: `_prepareLiquidityUpdates`, `ICCLiquidity.ccUpdate`.

## External Functions

### settleBuyLiquid(address listingAddress, uint256 maxIterations, uint256 step)
- **Parameters**:
  - `listingAddress` (address): `ICCListing` contract address for order book.
  - `maxIterations` (uint256): Limits orders processed to control gas.
  - `step` (uint256): Starting index in `makerPendingOrdersView` for gas-efficient iteration.
- **Behavior**: Settles up to `maxIterations` pending buy orders for `msg.sender` starting from `step`. Transfers principal (tokenB) to liquidity contract via `ICCListing.transactToken` or `transactNative`, and settlement (tokenA) to recipients via `ICCLiquidity.transactToken` or `transactNative`. Checks liquidity via `volumeBalances(0)` (yBalance). Updates liquidity via `_prepareLiquidityUpdates` (increases `xLiquid`, decreases `yLiquid`, adds `yFees`). Emits `NoPendingOrders`, `InsufficientBalance`, or `UpdateFailed` and returns if no orders, `step` exceeds orders, insufficient yBalance, or update failure. Ensures price impact (`_computeSwapImpact`) and current price (`_computeCurrentPrice`) are within `minPrice` and `maxPrice`. Creates a historical data entry via `_createHistoricalUpdate` if pending orders exist, using `volumeBalances(0)`, `prices(0)`, and `block.timestamp`. Calls `ccUpdate` individually per `ICCListing.UpdateType` struct.
- **Internal Call Flow**:
  1. Validates `listingAddress` via `onlyValidListing` (from `CCMainPartial`):
     - Requires `agent != address(0)`; reverts if unset.
     - Calls `ICCAgent.isValidListing(listingAddress)` with try-catch, returning `isValid` and `ListingDetails`.
     - Validates `isValid`, `details.listingAddress == listingAddress`, `details.liquidityAddress != address(0)`, and `details.tokenA != details.tokenB`.
     - Reverts with detailed reason if validation fails.
  2. Declares `listingContract = ICCListing(listingAddress)` for `makerPendingOrdersView`, `volumeBalances`, `ccUpdate`, `decimalsA/B`, `tokenA/B`, `liquidityAddressView`, `getBuyOrderPricing/Amounts/Core`.
  3. Fetches `makerPendingOrdersView(msg.sender)`; emits `NoPendingOrders` if empty or `step >= length`.
  4. Fetches `(xBalance, yBalance)` via `volumeBalances(0)`; emits `InsufficientBalance` if `yBalance == 0`.
  5. Calls `_createHistoricalUpdate(listingAddress, listingContract)` if `pendingOrders.length > 0`:
     - Fetches `(xBalance, yBalance)` via `volumeBalances(0)`.
     - Fetches `historicalDataLengthView`; if > 0, gets latest `historicalData` for `xVolume`, `yVolume`.
     - Creates update: `updateType=3`, `updateSort=0`, `updateData=abi.encode(prices(0), xBalance, yBalance, xVolume, yVolume, block.timestamp)`.
     - Calls `listingContract.ccUpdate`; emits `UpdateFailed` if fails.
  6. Calls `_processOrderBatch(listingAddress, maxIterations, true, step)`:
     - Creates `OrderBatchContext` (`listingAddress`, `maxIterations`, `isBuyOrder = true`).
     - Calls `_collectOrderIdentifiers(listingAddress, maxIterations, true, step)`:
       - Fetches `makerPendingOrdersView(msg.sender)`, checks `step <= length`.
       - Collects up to `maxIterations` order IDs starting from `step`.
       - Returns `orderIdentifiers` and `iterationCount`.
     - Iterates over `orderIdentifiers`:
       - Fetches `pendingAmount` via `getBuyOrderAmounts`; skips if `pendingAmount == 0`.
       - Calls `_processSingleOrder(listingAddress, orderId, true, pendingAmount)`:
         - Calls `_validateOrderPricing`:
           - Fetches `maxPrice`, `minPrice` via `getBuyOrderPricing`.
           - Fetches `currentPrice` via `_computeCurrentPrice`.
           - Computes `impactPrice` via `_computeSwapImpact`.
           - Emits `PriceOutOfBounds` if invalid; returns empty array.
         - Calls `_computeFee` to get `feeAmount`, `netAmount`.
         - Calls `_executeOrderWithFees`:
           - Emits `FeeDeducted`.
           - Calls `_computeSwapAmount`, `_prepareLiquidityUpdates`.
           - Calls `executeSingleBuyLiquid`:
             - Creates `OrderContext`.
             - Calls `_prepBuyLiquidUpdates`:
               - Validates pricing, checks `uniswapV2Router`, computes `amountOut`.
               - Calls `_prepBuyOrderUpdate` for transfers and balance checks.
               - Calls `_createBuyOrderUpdates` for update arrays.
             - Calls `listingContract.ccUpdate` per update; emits `UpdateFailed` if fails.
           - Returns empty array.
         - Returns empty array if pricing or swap fails.
  7. Calls `listingContract.ccUpdate` per `ICCListing.UpdateType` struct; emits `UpdateFailed` if fails.
- **Graceful Degradation**: Returns without reverting if no orders, `step` exceeds orders, insufficient balance, price out of bounds, or update failure, emitting appropriate events.
- **Note**: `amountSent` (tokenA) reflects the current settlement, updated via `ccUpdate` in `CCListingTemplate.sol`, accumulating total tokens sent across settlements.

### settleSellLiquid(address listingAddress, uint256 maxIterations, uint256 step)
- **Parameters**: Same as `settleBuyLiquid`.
- **Behavior**: Similar to `settleBuyLiquid`, but for sell orders. Transfers principal (tokenA) to liquidity contract, settlement (tokenB) to recipients. Checks `xBalance` via `volumeBalances(0)`. Updates liquidity (increases `yLiquid`, decreases `xLiquid`, adds `xFees`). Creates historical data entry if pending orders exist. Calls `ccUpdate` individually per `ICCListing.UpdateType` struct.
- **Internal Call Flow**: Similar to `settleBuyLiquid`, but:
  - Uses `makerPendingOrdersView(msg.sender)` for sell orders.
  - Emits `InsufficientBalance` if `xBalance == 0`.
  - Calls `_processOrderBatch(listingAddress, maxIterations, false, step)`:
    - Uses `getSellOrderAmounts/Core/Pricing`.
    - Calls `executeSingleSellLiquid`, `_prepSellLiquidUpdates`, `_prepSellOrderUpdate`, `_createSellOrderUpdates`.
    - Updates `yLiquid += normalize(pendingAmount)`, `xLiquid -= normalize(amountOut)`, `xFees += normalize(feeAmount)`.
- **Graceful Degradation**: Same as `settleBuyLiquid`.
- **Note**: `amountSent` (tokenB) reflects the current settlement, accumulating total tokens sent.

## Internal Functions (CCLiquidPartial, v0.0.337)
- **_getSwapReserves**: Fetches Uniswap V2 reserves via `IERC20.balanceOf` (`token0`, `tokenB`) into `SwapImpactContext`. Optimized by initializing unused fields to avoid warnings.
- **_computeCurrentPrice**: Fetches price from `ICCListing.prices(0)` with try-catch, reverting with detailed reason if failed.
- **_computeSwapImpact**: Calculates output and price impact with 0.3% fee using `balanceOf` reserves. Optimized by removing unused normalized fields.
- **_getTokenAndDecimals**: Retrieves token address and decimals based on order type.
- **_checkPricing**: Validates `impactPrice` within `minPrice` and `maxPrice`.
- **_computeAmountSent**: Computes pre-transfer balance for recipient.
- **_prepareLiquidityTransaction**: Computes `amountOut`, checks liquidity (`xAmount`, `yAmount`).
- **_prepareCoreUpdate**: Prepares Core update (`updateType=1 or 2, updateSort=0`) with `makerAddress`, `recipientAddress`, `status`.
- **_prepareAmountsUpdate**: Prepares Amounts update (`updateType=1 or 2, updateSort=2`) with `newPending`, `newFilled`, `amountSent`.
- **_prepareBalanceUpdate**: Prepares Balance update (`updateType=0, updateSort=0`) with `normalizedReceived`.
- **_createBuyOrderUpdates**: Builds update arrays for buy orders using helper functions.
- **_createSellOrderUpdates**: Builds update arrays for sell orders using helper functions.
- **_prepBuyOrderUpdate**: Handles buy order transfers, sets `amountSent` (tokenA), emits failure events.
- **_prepSellOrderUpdate**: Handles sell order transfers, sets `amountSent` (tokenB), emits failure events.
- **_prepBuyLiquidUpdates**: Validates pricing, computes `amountOut`, calls `_prepBuyOrderUpdate`, `_createBuyOrderUpdates`.
- **_prepSellLiquidUpdates**: Validates pricing, computes `amountOut`, calls `_prepSellOrderUpdate`, `_createSellOrderUpdates`.
- **_executeSingleBuyLiquid**: Executes buy order, calls `_prepBuyLiquidUpdates`.
- **_executeSingleSellLiquid**: Executes sell order, calls `_prepSellLiquidUpdates`.
- **_collectOrderIdentifiers**: Fetches order IDs starting from `step` up to `maxIterations`.
- **_updateLiquidityBalances**: Updates `xLiquid`, `yLiquid` via `ICCLiquidity.ccUpdate`; emits `SwapFailed` on failure.
- **_validateOrderPricing**: Validates prices, emits `PriceOutOfBounds` if invalid.
- **_computeFee**: Calculates `feeAmount`, `netAmount` based on liquidity usage.
- **_computeSwapAmount**: Computes `amountOut` for liquidity updates.
- **_toSingleUpdateArray**: Converts single update to array for `ccUpdate`.
- **_prepareLiquidityUpdates**: Transfers `pendingAmount`, executes individual `ccUpdate` calls for `xLiquid`, `yLiquid`, `xFees`/`yFees`. Optimized in v0.0.337 by removing redundant `_computeFeeAndLiquidity`.
- **_executeOrderWithFees**: Emits `FeeDeducted`, executes order with fee deduction, calls `executeSingleBuy/SellLiquid`. Optimized in v0.0.337 by streamlining calls.
- **_processSingleOrder**: Validates prices, computes fees, executes order, updates liquidity.
- **_processOrderBatch**: Iterates orders, skips settled orders, collects updates.
- **_finalizeUpdates**: Resizes update array.
- **_uint2str**: Converts uint to string for error messages.

## Internal Functions (CCLiquidRouter)
- **_createHistoricalUpdate**: Fetches `volumeBalances(0)`, `prices(0)`, and historical data (`xVolume`, `yVolume`); creates update with `block.timestamp` via `ccUpdate`.

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
  - Correct `updateType` and `updateSort` in `_createBuy/SellOrderUpdates`.
  - Skips settled orders via `pendingAmount == 0`.
  - Validates `step <= identifiers.length`.
  - Validates liquidity in `_prepareLiquidityTransaction`.
  - Individual `ccUpdate` calls per struct (v0.0.24).
  - Optimized struct fields in v0.0.337 (`OrderContext`, `PrepOrderUpdateResult`, `SwapImpactContext`).
  - Removed redundant `_computeFeeAndLiquidity` in v0.0.337.

## Limitations and Assumptions
- Relies on `ICCLiquidity` for settlements, not direct Uniswap V2 swaps.
- No order creation, cancellation, payouts, or liquidity management.
- Uses `balanceOf` for reserves in `_computeSwapImpact`.
- Zero amounts, failed transfers, or invalid prices return empty `UpdateType[]`.
- `depositor` set to `address(this)` in `ICCLiquidity` calls.
- `step` must be <= length of pending orders.
- `amountSent` accumulates total tokens sent across settlements.
- Historical data created at start of settlement if orders exist.
