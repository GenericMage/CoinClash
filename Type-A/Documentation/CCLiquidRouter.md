# CCLiquidRouter Contract Documentation

## Overview
The `CCLiquidRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform using `ICCLiquidity` for liquid settlement. It inherits from `CCLiquidPartial`, which extends `CCMainPartial`, and integrates with `ICCListing`, `ICCLiquidity`, `IERC20`, and `IUniswapV2Pair` for token operations and reserve data. It uses `ReentrancyGuard` (including `Ownable`) for security. The contract handles liquid settlement via `settleBuyLiquid` and `settleSellLiquid`, supporting a `step` parameter for gas-efficient iteration, ensuring robust error logging, and avoiding re-fetching settled orders.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.18 (updated 2025-08-23)

**Inheritance Tree:** `CCLiquidRouter` → `CCLiquidPartial` → `CCMainPartial`

**Compatibility:** CCListingTemplate.sol (v0.2.0), ICCLiquidity.sol (v0.0.4), CCMainPartial.sol (v0.0.14), CCLiquidPartial.sol (v0.0.24), CCLiquidityTemplate.sol (v0.1.3).

## Mappings
- None defined in `CCLiquidRouter`. Uses `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`) for order tracking.

## Structs
- **OrderContext** (`CCLiquidPartial`): Holds `listingContract` (ICCListing), `tokenIn` (address), `tokenOut` (address), `liquidityAddr` (address).
- **PrepOrderUpdateResult** (`CCLiquidPartial`): Holds `tokenAddress` (address), `tokenDecimals` (uint8), `makerAddress` (address), `recipientAddress` (address), `orderStatus` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, normalized tokenA for buy, tokenB for sell).
- **BuyOrderUpdateContext** (`CCLiquidPartial`): Holds `makerAddress` (address), `recipient` (address), `status` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, tokenA for buy).
- **SellOrderUpdateContext** (`CCLiquidPartial`): Same as `BuyOrderUpdateContext`, with `amountSent` (tokenB for sell).
- **OrderBatchContext** (`CCLiquidPartial`): Holds `listingAddress` (address), `maxIterations` (uint256), `isBuyOrder` (bool).
- **SwapImpactContext** (`CCLiquidPartial`): Holds `reserveIn` (uint256), `reserveOut` (uint256), `decimalsIn` (uint8), `decimalsOut` (uint8), `normalizedReserveIn` (uint256), `normalizedReserveOut` (uint256), `amountInAfterFee` (uint256), `price` (uint256), `amountOut` (uint256).

## Formulas
Formulas in `CCLiquidPartial.sol` govern settlement and price impact calculations.

1. **Current Price**:
   - **Formula**: `price = listingContract.prices(0)`.
   - **Used in**: `_computeCurrentPrice`, `_processSingleOrder`.
   - **Description**: Fetches price from `ICCListing.prices(0)` with try-catch, ensuring settlement price is within `minPrice` and `maxPrice`. Reverts with detailed reason if fetch fails.
   - **Usage**: Ensures settlement price aligns with listing template in `_processSingleOrder`.

2. **Swap Impact**:
   - **Formula**:
     - `amountInAfterFee = (inputAmount * 997) / 1000` (0.3% Uniswap V2 fee).
     - `amountOut = (amountInAfterFee * normalizedReserveOut) / (normalizedReserveIn + amountInAfterFee)`.
     - `price = ((normalizedReserveIn + amountInAfterFee) * 1e18) / (normalizedReserveOut - amountOut)`.
   - **Used in**: `_computeSwapImpact`, `_processSingleOrder`, `_checkPricing`.
   - **Description**: Calculates output and hypothetical price impact for buy (input tokenB, output tokenA) or sell (input tokenA, output tokenB) orders using `balanceOf` for Uniswap V2 LP reserves, ensuring `minPrice <= price <= maxPrice`.
   - **Usage**: Restricts settlement if price impact exceeds bounds; emits `PriceOutOfBounds` for graceful degradation.

3. **Buy Order Output**:
   - **Formula**: `amountOut = (amountInAfterFee * normalizedReserveOut) / (normalizedReserveIn + amountInAfterFee)`, denormalized to tokenA decimals.
   - **Used in**: `_computeSwapImpact`, `_prepareLiquidityTransaction`, `_prepBuyLiquidUpdates`.
   - **Description**: Computes tokenA output for buy orders, aligning with `buyOutput ≈ buyPrincipal / currentPrice`, adjusted for fees and pool dynamics.

4. **Sell Order Output**:
   - **Formula**: Same as buy, with `tokenIn = tokenA`, `tokenOut = tokenB`.
   - **Used in**: `_computeSwapImpact`, `_prepareLiquidityTransaction`, `_prepSellLiquidUpdates`.
   - **Description**: Computes tokenB output for sell orders, aligning with `sellOutput ≈ sellPrincipal * currentPrice`, adjusted for fees.

5. **Normalization/Denormalization**:
   - **Normalize**: `normalize(amount, decimals) = decimals < 18 ? amount * 10^(18-decimals) : amount / 10^(decimals-18)`.
   - **Denormalize**: `denormalize(amount, decimals) = decimals < 18 ? amount / 10^(18-decimals) : amount * 10^(decimals-18)`.
   - **Used in**: `_getSwapReserves`, `_computeSwapImpact`, `_prepBuy/SellOrderUpdate`, `_processSingleOrder`.
   - **Description**: Ensures 18-decimal precision for calculations, reverting to native decimals for transfers.

## External Functions

### settleBuyLiquid(address listingAddress, uint256 maxIterations, uint256 step)
- **Parameters**:
  - `listingAddress` (address): `ICCListing` contract address for order book.
  - `maxIterations` (uint256): Limits orders processed to control gas.
  - `step` (uint256): Starting index in `pendingBuyOrdersView` for gas-efficient iteration.
- **Behavior**: Settles up to `maxIterations` pending buy orders starting from `step` by transferring principal (tokenB) to the liquidity contract via `ICCListing.transactToken` or `transactNative`, and settlement (tokenA) to recipients via `ICCLiquidity.transactToken` or `transactNative`. Checks liquidity via `listingVolumeBalancesView` (yBalance). Decreases `yLiquid` (tokenB) by `pendingAmount` and increases `xLiquid` (tokenA) by `amountOut` via `ICCLiquidity.update`. Emits `NoPendingOrders`, `InsufficientBalance`, or `UpdateFailed` and returns if no orders, `step` exceeds orders, insufficient yBalance, or update failure. Ensures price impact (`_computeSwapImpact`) and current price (`_computeCurrentPrice`) are within `minPrice` and `maxPrice`.
- **Internal Call Flow**:
  1. Validates `listingAddress` via `onlyValidListing` (calls `ICCAgent.isValidListing` with try-catch, verifies non-zero addresses).
  2. Fetches `pendingBuyOrdersView`; emits `NoPendingOrders` if empty or `step >= length`.
  3. Fetches `(xBalance, yBalance, xVolume, yVolume)` via `listingVolumeBalancesView`; emits `InsufficientBalance` if `yBalance == 0`.
  4. Calls `this._processOrderBatch(listingAddress, maxIterations, true, step)` (from `CCLiquidPartial`):
     - Creates `OrderBatchContext` (`listingAddress`, `maxIterations`, `isBuyOrder = true`).
     - Calls `_collectOrderIdentifiers(listingAddress, maxIterations, true, step)`:
       - Fetches `pendingBuyOrdersView`, checks `step <= length`.
       - Collects up to `maxIterations` order IDs starting from `step` (e.g., for IDs `[2, 22, 23, 24, 30]`, `step=2`, `maxIterations=3`, collects `[23, 24, 30]`).
       - Returns `orderIdentifiers` and `iterationCount`.
     - Iterates up to `iterationCount`:
       - Fetches `(pendingAmount, filled, )` via `getBuyOrderAmounts`; skips if `pendingAmount == 0` (avoids settled orders).
       - Calls `_processSingleOrder(listingAddress, orderId, true, pendingAmount)`:
         - Declares `listingContract = ICCListing(listingAddress)` for `decimalsA/B`, `liquidityAddressView`.
         - Fetches `(maxPrice, minPrice)` via `getBuyOrderPricing`.
         - Computes `currentPrice` via `_computeCurrentPrice` (uses `prices(0)` with try-catch).
         - Computes `impactPrice`, `amountOut` via `_computeSwapImpact`:
           - Calls `_getSwapReserves(listingAddress, true)`:
             - Fetches Uniswap V2 reserves via `balanceOf` for `tokenB` (input) and `tokenA` (output).
             - Normalizes reserves to 18 decimals using `normalize`.
           - Applies 0.3% fee, computes `amountOut` and `price`.
         - If `minPrice <= {currentPrice, impactPrice} <= maxPrice`, calls `executeSingleBuyLiquid(listingAddress, orderId)`:
           - Fetches `(pendingAmount, , )` via `getBuyOrderAmounts`.
           - Creates `OrderContext` with `tokenIn=tokenB`, `tokenOut=tokenA`, `liquidityAddr`.
           - Calls `_prepBuyLiquidUpdates(context, orderId, pendingAmount)`:
             - Validates pricing via `_checkPricing`; emits `PriceOutOfBounds` if invalid.
             - Checks `uniswapV2Router`; emits `MissingUniswapRouter` if unset.
             - Calls `_prepareLiquidityTransaction(listingAddress, pendingAmount, true)`:
               - Checks `yAmount >= pendingAmount` (tokenB) and `xAmount >= amountOut` (tokenA).
               - Computes `amountOut`.
             - Calls `_prepBuyOrderUpdate(listingAddress, orderId, pendingAmount)`:
               - Fetches `tokenB`, `decimalsB` via `_getTokenAndDecimals(listingAddress, true)`.
               - Fetches `(makerAddress, recipientAddress, orderStatus)` via `getBuyOrderCore`.
               - Approves tokenB to `uniswapV2Router`; emits `ApprovalFailed` if fails.
               - Calls `listingContract.update` with `UpdateType[]` from `_createBuyOrderUpdates`.
               - Transfers tokenB to `liquidityAddr` via `transactToken` or `transactNative`; emits `TokenTransferFailed` if fails.
               - Captures `amountSent` (tokenA) via pre/post balance checks; emits `SwapFailed` if no tokens received.
               - Returns `PrepOrderUpdateResult`.
             - Creates `BuyOrderUpdateContext` and calls `_createBuyOrderUpdates`:
               - Returns `UpdateType[]` with `addr = makerAddress`, `value = normalizedReceived`, `amountSent` (tokenA), and status (`3` if filled, `2` if partial).
         - Updates liquidity via `ICCLiquidity.update`:
           - Decreases `yLiquid` (tokenB, `pendingAmount`), increases `xLiquid` (tokenA, `amountOut`).
           - Emits `SwapFailed` if update fails.
         - Returns empty `UpdateType[]` if price out of bounds or swap fails.
     - Resizes updates via `_finalizeUpdates`.
  5. Calls `listingContract.update(updates)`; emits `UpdateFailed` on error.
- **Graceful Degradation**: Returns without reverting if no orders, `step` exceeds orders, insufficient balance, price out of bounds, or update failure, emitting appropriate events.

### settleSellLiquid(address listingAddress, uint256 maxIterations, uint256 step)
- **Parameters**:
  - `listingAddress` (address): `ICCListing` contract address for order book.
  - `maxIterations` (uint256): Limits orders processed to control gas.
  - `step` (uint256): Starting index in `pendingSellOrdersView` for gas-efficient iteration.
- **Behavior**: Settles up to `maxIterations` pending sell orders starting from `step` by transferring principal (tokenA) to the liquidity contract via `ICCListing.transactToken` or `transactNative`, and settlement (tokenB) to recipients via `ICCLiquidity.transactToken` or `transactNative`. Checks liquidity via `listingVolumeBalancesView` (xBalance). Decreases `xLiquid` (tokenA) by `pendingAmount` and increases `yLiquid` (tokenB) by `amountOut` via `ICCLiquidity.update`. Emits `NoPendingOrders`, `InsufficientBalance`, or `UpdateFailed` and returns if no orders, `step` exceeds orders, insufficient xBalance, or update failure. Ensures price impact and current price are within `minPrice` and `maxPrice`.
- **Internal Call Flow**:
  1. Validates `listingAddress` via `onlyValidListing`.
  2. Fetches `pendingSellOrdersView`; emits `NoPendingOrders` if empty or `step >= length`.
  3. Fetches `(xBalance, yBalance, xVolume, yVolume)` via `listingVolumeBalancesView`; emits `InsufficientBalance` if `xBalance == 0`.
  4. Calls `this._processOrderBatch(listingAddress, maxIterations, false, step)` (from `CCLiquidPartial`):
     - Creates `OrderBatchContext` (`listingAddress`, `maxIterations`, `isBuyOrder = false`).
     - Calls `_collectOrderIdentifiers(listingAddress, maxIterations, false, step)`:
       - Fetches `pendingSellOrdersView`, checks `step <= length`.
       - Collects up to `maxIterations` order IDs starting from `step`.
       - Returns `orderIdentifiers` and `iterationCount`.
     - Iterates up to `iterationCount`:
       - Fetches `(pendingAmount, , )` via `getSellOrderAmounts`; skips if `pendingAmount == 0`.
       - Calls `_processSingleOrder(listingAddress, orderId, false, pendingAmount)`:
         - Declares `listingContract = ICCListing(listingAddress)` for `decimalsA/B`, `liquidityAddressView`.
         - Fetches `(maxPrice, minPrice)` via `getSellOrderPricing`.
         - Computes `currentPrice` via `_computeCurrentPrice`.
         - Computes `impactPrice`, `amountOut` via `_computeSwapImpact`:
           - Calls `_getSwapReserves(listingAddress, false)`:
             - Fetches reserves via `balanceOf` for `tokenA` (input) and `tokenB` (output).
             - Normalizes reserves.
           - Applies 0.3% fee, computes `amountOut` and `price`.
         - If `minPrice <= {currentPrice, impactPrice} <= maxPrice`, calls `executeSingleSellLiquid(listingAddress, orderId)`:
           - Fetches `(pendingAmount, , )` via `getSellOrderAmounts`.
           - Creates `OrderContext` with `tokenIn=tokenA`, `tokenOut=tokenB`, `liquidityAddr`.
           - Calls `_prepSellLiquidUpdates(context, orderId, pendingAmount)`:
             - Validates pricing via `_checkPricing`; emits `PriceOutOfBounds`.
             - Checks `uniswapV2Router`; emits `MissingUniswapRouter`.
             - Calls `_prepareLiquidityTransaction(listingAddress, pendingAmount, false)`:
               - Checks `xAmount >= pendingAmount` (tokenA) and `yAmount >= amountOut` (tokenB).
               - Computes `amountOut`.
             - Calls `_prepSellOrderUpdate(listingAddress, orderId, pendingAmount)`:
               - Fetches `tokenA`, `decimalsA` via `_getTokenAndDecimals(listingAddress, false)`.
               - Approves tokenA; emits `ApprovalFailed` if fails.
               - Calls `listingContract.update` with `UpdateType[]` from `_createSellOrderUpdates`.
               - Transfers tokenA to `liquidityAddr`; emits `TokenTransferFailed` if fails.
               - Transfers tokenB to recipient, capturing `amountSent` (tokenB); emits `SwapFailed` if no tokens received.
               - Returns `PrepOrderUpdateResult`.
             - Creates `SellOrderUpdateContext` and calls `_createSellOrderUpdates`:
               - Returns `UpdateType[]` with `addr = makerAddress`, `value = normalizedReceived`, `amountSent` (tokenB), and status (`3` if filled, `2` if partial).
         - Updates liquidity via `ICCLiquidity.update`:
           - Decreases `xLiquid` (tokenA, `pendingAmount`), increases `yLiquid` (tokenB, `amountOut`).
           - Emits `SwapFailed` if update fails.
         - Returns empty `UpdateType[]` if price out of bounds or swap fails.
     - Resizes updates via `_finalizeUpdates`.
  5. Calls `listingContract.update(updates)`; emits `UpdateFailed` on error.
- **Graceful Degradation**: Returns without reverting if no orders, `step` exceeds orders, insufficient balance, price out of bounds, or update failure, emitting appropriate events.

## Internal Functions (CCLiquidPartial)
- **_getSwapReserves**: Fetches Uniswap V2 reserves via `balanceOf` (`token0`, `tokenB`) and normalizes to `SwapImpactContext`.
- **_computeCurrentPrice**: Fetches price from `ICCListing.prices(0)` with try-catch, reverting with detailed reason if failed.
- **_computeSwapImpact**: Calculates output and price impact with 0.3% fee using `balanceOf` reserves.
- **_checkPricing**: Validates `impactPrice` within `minPrice` and `maxPrice`.
- **_prepareLiquidityTransaction**: Computes `amountOut`, checks liquidity (`xAmount` and `yAmount` for both input and output tokens).
- **_prepBuy/SellOrderUpdate**: Handles transfers (principal to liquidity, settlement to recipient) with pre/post balance checks, sets `amountSent` to received token (tokenA for buy, tokenB for sell), calls `listingContract.update`, emits `MissingUniswapRouter`, `ApprovalFailed`, `TokenTransferFailed`, `UpdateFailed` on failure, returns `PrepOrderUpdateResult`.
- **_prepBuy/SellLiquidUpdates**: Validates pricing, checks `uniswapV2Router`, computes `amountOut`, prepares `UpdateType[]` with `addr = makerAddress`; emits `PriceOutOfBounds`, `MissingUniswapRouter`, `SwapFailed` if invalid.
- **_createBuy/SellOrderUpdates**: Builds `UpdateType[]` for order updates with `addr = makerAddress` for registry updates.
- **_collectOrderIdentifiers**: Fetches order IDs starting from `step` up to `maxIterations`, checks `step <= identifiers.length`.
- **_processSingleOrder**: Validates prices, executes order, updates liquidity (`yLiquid` and `xLiquid` for buy, `xLiquid` and `yLiquid` for sell); emits `PriceOutOfBounds` or `SwapFailed` if invalid.
- **_processOrderBatch**: Iterates orders, skips settled orders (`pendingAmount == 0`), collects updates.
- **_finalizeUpdates**: Resizes update array.
- **uint2str**: Converts uint to string for revert messages.

## Security Measures
- **Reentrancy Protection**: `nonReentrant` on `settleBuyLiquid`, `settleSellLiquid`.
- **Listing Validation**: `onlyValidListing` uses `ICCAgent.isValidListing` with try-catch and detailed validation (non-zero addresses, valid token pair).
- **Safe Transfers**: `IERC20` with pre/post balance checks in `_prepBuy/SellOrderUpdate`.
- **Safety**:
  - Explicit casting for interfaces (`ICCListing`, `ICCLiquidity`).
  - No inline assembly.
  - Hidden state variables (`agent`, `uniswapV2Router`) accessed via `agentView`, `uniswapV2RouterView`.
  - Avoids reserved keywords, `virtual`/`override`.
  - Graceful degradation with events (`NoPendingOrders`, `InsufficientBalance`, `PriceOutOfBounds`, `UpdateFailed`, `MissingUniswapRouter`, `ApprovalFailed`, `TokenTransferFailed`, `SwapFailed`) and detailed revert reasons.
  - Sets `addr = makerAddress` in `UpdateType` structs for accurate registry updates.
  - Skips settled orders via `pendingAmount == 0` check in `_processOrderBatch`.
  - Validates `step <= identifiers.length` in `_collectOrderIdentifiers`.
  - Validates input and output liquidity in `_prepareLiquidityTransaction`.

## Limitations and Assumptions
- Relies on `ICCLiquidity` for settlements, not direct Uniswap V2 swaps.
- No order creation, cancellation, payouts, or liquidity management.
- Uses `balanceOf` for Uniswap V2 reserves for price impact, not actual swaps.
- Zero amounts, failed transfers, or invalid prices return empty `UpdateType[]`.
- `depositor` set to `address(this)` in `ICCLiquidity` calls.
- `step` must be <= length of pending orders to avoid `NoPendingOrders` emission.

## Differences from CCSettlementRouter
- Focuses on `ICCLiquidity`-based settlements, excludes Uniswap V2 swaps.
- Inherits `CCLiquidPartial`, omits `CCUniPartial`, `CCSettlementPartial`.
- Uses helper functions for stack management.
- Enhanced error logging with `UpdateFailed`, `MissingUniswapRouter`, `ApprovalFailed`, `TokenTransferFailed`, `SwapFailed`.
- Avoids re-fetching settled orders via `pendingAmount == 0` check.
- Supports `step` parameter for gas-efficient iteration starting from a specified index.
