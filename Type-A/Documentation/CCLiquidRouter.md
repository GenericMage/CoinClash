# CCLiquidRouter Contract Documentation

## Overview
The `CCLiquidRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform using `ICCLiquidity` for liquid settlement. It inherits from `CCLiquidPartial`, which extends `CCMainPartial`, and integrates with `ICCListing`, `ICCLiquidity`, `IERC20`, and `IUniswapV2Pair` for token operations and reserve data. It uses `ReentrancyGuard` (including `Ownable`) for security. The contract handles liquid settlement via `settleBuyLiquid` and `settleSellLiquid`, supporting a `step` parameter for gas-efficient iteration, ensuring robust error logging, and avoiding re-fetching settled orders.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.21 (updated 2025-09-04)

**Inheritance Tree:** `CCLiquidRouter` → `CCLiquidPartial` (v0.0.30) → `CCMainPartial` (v0.1.1)

**Compatibility:** `CCListingTemplate.sol` (v0.3.0), `ICCLiquidity.sol` (v0.0.5), `CCMainPartial.sol` (v0.1.1), `CCLiquidPartial.sol` (v0.0.30), `CCLiquidityTemplate.sol` (v0.1.3)

## Mappings
- None defined in `CCLiquidRouter`. Uses `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`) for order tracking.

## Structs
- **HistoricalUpdateContext** (`CCLiquidRouter`): holds (uint256) `xBalance`, (uint256) `yBalance`, (uint256) `xVolume`, (uint256) `yVolume`. 
- **OrderContext** (`CCLiquidPartial`): Holds `listingContract` (ICCListing), `tokenIn` (address), `tokenOut` (address), `liquidityAddr` (address).
- **PrepOrderUpdateResult** (`CCLiquidPartial`): Holds `tokenAddress` (address), `tokenDecimals` (uint8), `makerAddress` (address), `recipientAddress` (address), `orderStatus` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, denormalized tokenA for buy, tokenB for sell), `preTransferWithdrawn` (uint256, denormalized amount withdrawn).
- **BuyOrderUpdateContext** (`CCLiquidPartial`): Holds `makerAddress` (address), `recipient` (address), `status` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, denormalized tokenA for buy), `preTransferWithdrawn` (uint256).
- **SellOrderUpdateContext** (`CCLiquidPartial`): Same as `BuyOrderUpdateContext`, with `amountSent` (denormalized tokenB for sell).
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
   - **Used in**: `_getSwapReserves`, `_computeSwapImpact`, `_prepBuy/SellOrderUpdate`, `_processSingleOrder`, `_updateLiquidityBalances`.
   - **Description**: Ensures 18-decimal precision for calculations, reverting to native decimals for transfers.

## External Functions

### settleBuyLiquid(address listingAddress, uint256 maxIterations, uint256 step)
- **Parameters**:
  - `listingAddress` (address): `ICCListing` contract address for order book.
  - `maxIterations` (uint256): Limits orders processed to control gas.
  - `step` (uint256): Starting index in `pendingBuyOrdersView` for gas-efficient iteration.
- **Behavior**: Settles up to `maxIterations` pending buy orders starting from `step` by transferring principal (tokenB) to the liquidity contract via `ICCListing.transactToken` or `transactNative`, and settlement (tokenA) to recipients via `ICCLiquidity.transactToken` or `transactNative`. Checks liquidity via `listingVolumeBalancesView` (yBalance). Decreases `yLiquid` (tokenB) by `pendingAmount` and increases `xLiquid` (tokenA) by `amountOut` via `ICCLiquidity.update` in `_updateLiquidityBalances`. Emits `NoPendingOrders`, `InsufficientBalance`, or `UpdateFailed` and returns if no orders, `step` exceeds orders, insufficient yBalance, or update failure. Ensures price impact (`_computeSwapImpact`) and current price (`_computeCurrentPrice`) are within `minPrice` and `maxPrice`. Uses `ccUpdate` to update order state, with `amountSent` (tokenA) tracking tokens sent to recipients for the current settlement. Creates a new historical data entry at the start if pending orders exist, copying the latest live data for; `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp` and applies them using `ccUpdate`.
- **Internal Call Flow**:
  1. Validates `listingAddress` via `onlyValidListing` (from `CCMainPartial`):
     - Requires `agent != address(0)`; reverts if unset.
     - Calls `ICCAgent.isValidListing(listingAddress)` with try-catch, returning `isValid` and `ListingDetails`.
     - Validates `isValid`, `details.listingAddress == listingAddress`, `details.liquidityAddress != address(0)`, and `details.tokenA != details.tokenB`.
     - Reverts with detailed reason if validation fails.
  2. Declares `listingContract = ICCListing(listingAddress)` for `pendingBuyOrdersView`, `listingVolumeBalancesView`, `ccUpdate`, `decimalsA/B`, `tokenA/B`, `liquidityAddressView`, `getBuyOrderPricing/Amounts/Core`.
  3. Fetches `pendingBuyOrdersView`; emits `NoPendingOrders` if empty or `step >= length`.
  4. Fetches `(xBalance, yBalance, xVolume, yVolume)` via `listingVolumeBalancesView`; emits `InsufficientBalance` if `yBalance == 0`.
  5. Calls `this._processOrderBatch(listingAddress, maxIterations, true, step)` (from `CCLiquidPartial`):
     - Creates `OrderBatchContext` (`listingAddress`, `maxIterations`, `isBuyOrder = true`).
     - Calls `_collectOrderIdentifiers(listingAddress, maxIterations, true, step)`:
       - Fetches `pendingBuyOrdersView`, checks `step <= length`.
       - Collects up to `maxIterations` order IDs starting from `step` (e.g., for IDs `[2, 22, 23, 24, 30]`, `step=2`, `maxIterations=3`, collects `[23, 24, 30]`).
       - Returns `orderIdentifiers` and `iterationCount`.
     - Initializes `tempUpdates` array (size `iterationCount * 3`).
     - Iterates over `orderIdentifiers`:
       - Fetches `pendingAmount` via `getBuyOrderAmounts`; skips if `pendingAmount == 0`.
       - Calls `_processSingleOrder(listingAddress, orderId, true, pendingAmount)`:
         - Fetches `maxPrice`, `minPrice` via `getBuyOrderPricing`.
         - Calls `_computeCurrentPrice(listingAddress)` to get `currentPrice`.
         - Calls `_computeSwapImpact(listingAddress, pendingAmount, true)` to get `impactPrice`, `amountOut`.
         - If `currentPrice` and `impactPrice` within bounds:
           - Calls `executeSingleBuyLiquid(listingAddress, orderId)`:
             - Creates `OrderContext` (`listingContract`, `tokenIn=tokenB`, `tokenOut=tokenA`, `liquidityAddr`).
             - Calls `_prepBuyLiquidUpdates(context, orderId, pendingAmount)`:
               - Calls `_checkPricing(listingAddress, orderId, true, pendingAmount)`:
                 - Uses `_computeSwapImpact` to validate `impactPrice`.
                 - Emits `PriceOutOfBounds` if invalid; returns empty array.
               - Calls `_prepareLiquidityTransaction(listingAddress, pendingAmount, true)` to get `amountOut`, `tokenIn`, `tokenOut`.
               - Checks `uniswapV2Router != address(0)`; emits `MissingUniswapRouter` if unset.
               - Calls `_prepBuyOrderUpdate(listingAddress, orderId, pendingAmount)`:
                 - Fetches `(tokenAddress=tokenB, tokenDecimals=decimalsB)` via `_getTokenAndDecimals`.
                 - Fetches `(makerAddress, recipientAddress, orderStatus)` via `getBuyOrderCore`.
                 - Fetches `(pending, filled, amountSent)` via `getBuyOrderAmounts`; requires `pendingAmount <= pending`.
                 - Computes `amountOut` via `_prepareLiquidityTransaction`.
                 - Denormalizes `pendingAmount` to `decimalsB`, `amountOut` to `decimalsA`.
                 - Computes `preBalance` via `_computeAmountSent(tokenOut=tokenA, recipientAddress, denormalizedAmountOut)`.
                 - If `tokenB != address(0)`, approves `denormalizedAmount` to `uniswapV2Router`; emits `ApprovalFailed` if fails.
                 - Transfers `denormalizedAmount` (tokenB) to `liquidityAddr` via `transactToken` or `transactNative`; emits `TokenTransferFailed` if fails.
                 - Computes `postBalance` of `tokenA` for `recipientAddress`; sets `amountSent = postBalance - preBalance` if positive, else 0.
                 - Sets `preTransferWithdrawn = denormalizedAmount`.
                 - Returns `PrepOrderUpdateResult`.
               - Creates `BuyOrderUpdateContext` (`makerAddress`, `recipientAddress`, `orderStatus`, `amountReceived`, `normalizedReceived`, `amountSent`, `preTransferWithdrawn`).
               - Calls `_createBuyOrderUpdates(orderId, updateContext, pendingAmount)`:
                 - Computes `newStatus = preTransferWithdrawn >= pendingAmount ? 3 : 2` (3: filled, 2: partially filled).
                 - Calls `_prepareCoreUpdate(orderId, listingAddress, true, newStatus)`:
                   - Returns `updateType=1, updateSort=0, updateData=abi.encode(makerAddress, recipientAddress, newStatus)`.
                 - Calls `_prepareAmountsUpdate(orderId, listingAddress, true, preTransferWithdrawn, amountSent)`:
                   - Fetches `(pending, filled, _)` via `getBuyOrderAmounts`.
                   - Computes `newPending = pending >= preTransferWithdrawn ? pending - preTransferWithdrawn : 0`, `newFilled = filled + preTransferWithdrawn`.
                   - Returns `updateType=1, updateSort=2, updateData=abi.encode(newPending, newFilled, amountSent)`.
                 - Calls `_prepareBalanceUpdate(normalizedReceived, true)`:
                   - Returns `updateType=0, updateSort=0, updateData=normalizedReceived` (increases yBalance).
                 - Returns `updateType[3], updateSort[3], updateData[3]`.
               - Calls `listingContract.ccUpdate(updateType, updateSort, updateData)`; emits `UpdateFailed` if fails.
               - Returns empty array.
             - Calls `_updateLiquidityBalances(listingAddress, orderId, true, pendingAmount, amountOut)`:
               - Creates `ICCLiquidity.UpdateType[2]`:
                 - `updateType=0, index=1` (yLiquid): `value = yAmount - normalizedPending` (subtract tokenB).
                 - `updateType=0, index=0` (xLiquid): `value = xAmount + normalizedSettle` (add tokenA).
               - Calls `liquidityContract.update(address(this), liquidityUpdates)`; emits `SwapFailed` if fails.
             - Returns empty array if pricing, router, or swap fails.
           - Emits `PriceOutOfBounds` if prices invalid; returns empty array.
       - Appends updates to `tempUpdates`.
     - Calls `_finalizeUpdates(tempUpdates, updateIndex)`; returns `finalUpdates`.
  6. If `updates.length > 0`, converts `updates` to `updateType`, `updateSort`, `updateData` arrays and calls `listingContract.ccUpdate(updateType, updateSort, updateData)`:
     - Emits `UpdateFailed` with reason or "Unknown update error" if fails.
     - Does not revert, ensuring graceful degradation.
- **Graceful Degradation**: Returns without reverting if no orders, `step` exceeds orders, insufficient balance, price out of bounds, or update failure, emitting appropriate events.
- **Note**: `amountSent` (tokenA) in `_createBuyOrderUpdates` reflects the current settlement, updated via `ccUpdate` in `CCListingTemplate.sol`, accumulating total tokens sent to recipients across all settlements.

### settleSellLiquid(address listingAddress, uint256 maxIterations, uint256 step)
- **Parameters**:
  - `listingAddress` (address): `ICCListing` contract address for order book.
  - `maxIterations` (uint256): Limits orders processed to control gas.
  - `step` (uint256): Starting index in `pendingSellOrdersView` for gas-efficient iteration.
- **Behavior**: Settles up to `maxIterations` pending sell orders starting from `step` by transferring principal (tokenA) to the liquidity contract via `ICCListing.transactToken`, and settlement (tokenB) to recipients via `ICCLiquidity.transactToken` or `transactNative`. Checks liquidity via `listingVolumeBalancesView` (xBalance). Decreases `xLiquid` (tokenA) by `pendingAmount` and increases `yLiquid` (tokenB) by `amountOut` via `ICCLiquidity.update` in `_updateLiquidityBalances`. Emits `NoPendingOrders`, `InsufficientBalance`, or `UpdateFailed` and returns if no orders, `step` exceeds orders, insufficient xBalance, or update failure. Ensures price impact (`_computeSwapImpact`) and current price (`_computeCurrentPrice`) are within `minPrice` and `maxPrice`. Uses `ccUpdate` to update order state, with `amountSent` (tokenB) tracking tokens sent to recipients for the current settlement.
- **Internal Call Flow**:
  1. Validates `listingAddress` via `onlyValidListing` (same as `settleBuyLiquid`).
  2. Declares `listingContract = ICCListing(listingAddress)` for `pendingSellOrdersView`, `listingVolumeBalancesView`, `ccUpdate`, `decimalsA/B`, `tokenA/B`, `liquidityAddressView`, `getSellOrderPricing/Amounts/Core`.
  3. Fetches `pendingSellOrdersView`; emits `NoPendingOrders` if empty or `step >= length`.
  4. Fetches `(xBalance, yBalance, xVolume, yVolume)` via `listingVolumeBalancesView`; emits `InsufficientBalance` if `xBalance == 0`.
  5. Calls `this._processOrderBatch(listingAddress, maxIterations, false, step)`:
     - Creates `OrderBatchContext` (`listingAddress`, `maxIterations`, `isBuyOrder = false`).
     - Calls `_collectOrderIdentifiers(listingAddress, maxIterations, false, step)`:
       - Fetches `pendingSellOrdersView`, checks `step <= length`.
       - Collects up to `maxIterations` order IDs starting from `step`.
       - Returns `orderIdentifiers` and `iterationCount`.
     - Initializes `tempUpdates` array (size `iterationCount * 3`).
     - Iterates over `orderIdentifiers`:
       - Fetches `pendingAmount` via `getSellOrderAmounts`; skips if `pendingAmount == 0`.
       - Calls `_processSingleOrder(listingAddress, orderId, false, pendingAmount)`:
         - Fetches `maxPrice`, `minPrice` via `getSellOrderPricing`.
         - Calls `_computeCurrentPrice(listingAddress)` to get `currentPrice`.
         - Calls `_computeSwapImpact(listingAddress, pendingAmount, false)` to get `impactPrice`, `amountOut`.
         - If `currentPrice` and `impactPrice` within bounds:
           - Calls `executeSingleSellLiquid(listingAddress, orderId)`:
             - Creates `OrderContext` (`listingContract`, `tokenIn=tokenA`, `tokenOut=tokenB`, `liquidityAddr`).
             - Calls `_prepSellLiquidUpdates(context, orderId, pendingAmount)`:
               - Calls `_checkPricing(listingAddress, orderId, false, pendingAmount)`:
                 - Uses `_computeSwapImpact` to validate `impactPrice`.
                 - Emits `PriceOutOfBounds` if invalid; returns empty array.
               - Calls `_prepareLiquidityTransaction(listingAddress, pendingAmount, false)` to get `amountOut`, `tokenIn`, `tokenOut`.
               - Checks `uniswapV2Router != address(0)`; emits `MissingUniswapRouter` if unset.
               - Calls `_prepSellOrderUpdate(listingAddress, orderId, pendingAmount)`:
                 - Fetches `(tokenAddress=tokenA, tokenDecimals=decimalsA)` via `_getTokenAndDecimals`.
                 - Fetches `(makerAddress, recipientAddress, orderStatus)` via `getSellOrderCore`.
                 - Fetches `(pending, filled, amountSent)` via `getSellOrderAmounts`; requires `pendingAmount <= pending`.
                 - Computes `amountOut` via `_prepareLiquidityTransaction`.
                 - Denormalizes `pendingAmount` to `decimalsA`, `amountOut` to `decimalsB`.
                 - Computes `preBalance` via `_computeAmountSent(tokenOut=tokenB, recipientAddress, denormalizedAmountOut)`.
                 - If `tokenA != address(0)`, approves `denormalizedAmount` to `uniswapV2Router`; emits `ApprovalFailed` if fails.
                 - Transfers `denormalizedAmount` (tokenA) to `liquidityAddr` via `transactToken`; emits `TokenTransferFailed` if fails.
                 - Computes `postBalance` of `tokenB` for `recipientAddress`; sets `amountSent = postBalance - preBalance` if positive, else 0.
                 - Sets `preTransferWithdrawn = denormalizedAmount`.
                 - Returns `PrepOrderUpdateResult`.
               - Creates `SellOrderUpdateContext` (`makerAddress`, `recipientAddress`, `orderStatus`, `amountReceived`, `normalizedReceived`, `amountSent`, `preTransferWithdrawn`).
               - Calls `_createSellOrderUpdates(orderId, updateContext, pendingAmount)`:
                 - Computes `newStatus = preTransferWithdrawn >= pendingAmount ? 3 : 2` (3: filled, 2: partially filled).
                 - Calls `_prepareCoreUpdate(orderId, listingAddress, false, newStatus)`:
                   - Returns `updateType=2, updateSort=0, updateData=abi.encode(makerAddress, recipientAddress, newStatus)`.
                 - Calls `_prepareAmountsUpdate(orderId, listingAddress, false, preTransferWithdrawn, amountSent)`:
                   - Fetches `(pending, filled, _)` via `getSellOrderAmounts`.
                   - Computes `newPending = pending >= preTransferWithdrawn ? pending - preTransferWithdrawn : 0`, `newFilled = filled + preTransferWithdrawn`.
                   - Returns `updateType=2, updateSort=2, updateData=abi.encode(newPending, newFilled, amountSent)`.
                 - Calls `_prepareBalanceUpdate(normalizedReceived, false)`:
                   - Returns `updateType=0, updateSort=0, updateData=normalizedReceived` (increases xBalance).
                 - Returns `updateType[3], updateSort[3], updateData[3]`.
               - Calls `listingContract.ccUpdate(updateType, updateSort, updateData)`; emits `UpdateFailed` if fails.
               - Returns empty array.
             - Calls `_updateLiquidityBalances(listingAddress, orderId, false, pendingAmount, amountOut)`:
               - Creates `ICCLiquidity.UpdateType[2]`:
                 - `updateType=0, index=0` (xLiquid): `value = xAmount - normalizedPending` (subtract tokenA).
                 - `updateType=0, index=1` (yLiquid): `value = yAmount + normalizedSettle` (add tokenB).
               - Calls `liquidityContract.update(address(this), liquidityUpdates)`; emits `SwapFailed` if fails.
             - Returns empty array if pricing, router, or swap fails.
           - Emits `PriceOutOfBounds` if prices invalid; returns empty array.
       - Appends updates to `tempUpdates`.
     - Calls `_finalizeUpdates(tempUpdates, updateIndex)`; returns `finalUpdates`.
  6. If `updates.length > 0`, converts `updates` to `updateType`, `updateSort`, `updateData` arrays and calls `listingContract.ccUpdate(updateType, updateSort, updateData)`:
     - Emits `UpdateFailed` with reason or "Unknown update error" if fails.
     - Does not revert, ensuring graceful degradation.
- **Graceful Degradation**: Returns without reverting if no orders, `step` exceeds orders, insufficient balance, price out of bounds, or update failure, emitting appropriate events.
- **Note**: `amountSent` (tokenB) in `_createSellOrderUpdates` reflects the current settlement, updated via `ccUpdate` in `CCListingTemplate.sol`, accumulating total tokens sent to recipients across all settlements.

## Internal Functions (CCLiquidPartial)
- **_getSwapReserves**: Fetches Uniswap V2 reserves via `IERC20.balanceOf` (`token0`, `tokenB`) and normalizes to `SwapImpactContext`.
- **_computeCurrentPrice**: Fetches price from `ICCListing.prices(0)` with try-catch, reverting with detailed reason if failed.
- **_computeSwapImpact**: Calculates output and price impact with 0.3% fee using `balanceOf` reserves.
- **_getTokenAndDecimals**: Retrieves token address and decimals based on order type.
- **_checkPricing**: Validates `impactPrice` within `minPrice` and `maxPrice`.
- **_computeAmountSent**: Computes pre-transfer balance for recipient.
- **_prepareLiquidityTransaction**: Computes `amountOut`, checks liquidity (`xAmount` and `yAmount` for input/output).
- **_prepareCoreUpdate**: Prepares Core update (`updateType=1 or 2, updateSort=0`) with `makerAddress`, `recipientAddress`, `status`.
- **_prepareAmountsUpdate**: Prepares Amounts update (`updateType=1 or 2, updateSort=2`) with `newPending`, `newFilled`, `amountSent` using `preTransferWithdrawn`.
- **_prepareBalanceUpdate**: Prepares Balance update (`updateType=0, updateSort=0`) with `normalizedReceived`.
- **_createBuyOrderUpdates**: Builds update arrays for buy orders using `_prepareCoreUpdate`, `_prepareAmountsUpdate`, `_prepareBalanceUpdate` to reduce stack usage.
- **_createSellOrderUpdates**: Builds update arrays for sell orders using `_prepareCoreUpdate`, `_prepareAmountsUpdate`, `_prepareBalanceUpdate` to reduce stack usage.
- **_prepBuyOrderUpdate**: Handles buy order transfers (principal to liquidity, settlement to recipient) with pre/post balance checks, sets `amountSent` to received tokenA, emits `MissingUniswapRouter`, `ApprovalFailed`, `TokenTransferFailed` on failure, returns `PrepOrderUpdateResult`.
- **_prepSellOrderUpdate**: Handles sell order transfers (principal to liquidity, settlement to recipient) with pre/post balance checks, sets `amountSent` to received tokenB, emits `MissingUniswapRouter`, `ApprovalFailed`, `TokenTransferFailed` on failure, returns `PrepOrderUpdateResult`.
- **_prepBuyLiquidUpdates**: Validates pricing, checks `uniswapV2Router`, computes `amountOut`, calls `_prepBuyOrderUpdate` and `_createBuyOrderUpdates`, emits `PriceOutOfBounds`, `MissingUniswapRouter`, `SwapFailed` if invalid.
- **_prepSellLiquidUpdates**: Validates pricing, checks `uniswapV2Router`, computes `amountOut`, calls `_prepSellOrderUpdate` and `_createSellOrderUpdates`, emits `PriceOutOfBounds`, `MissingUniswapRouter`, `SwapFailed` if invalid.
- **_executeSingleBuyLiquid**: Executes buy order, creates `OrderContext`, calls `_prepBuyLiquidUpdates`.
- **_executeSingleSellLiquid**: Executes sell order, creates `OrderContext`, calls `_prepSellLiquidUpdates`.
- **_collectOrderIdentifiers**: Fetches order IDs starting from `step` up to `maxIterations`, checks `step <= identifiers.length`.
- **_updateLiquidityBalances**: Updates `xLiquid` and `yLiquid` (subtract outgoing, add incoming) via `ICCLiquidity.update`; emits `SwapFailed` on failure.
- **_processSingleOrder**: Validates prices, executes order, calls `_updateLiquidityBalances` to update liquidity; emits `PriceOutOfBounds` or `SwapFailed` if invalid.
- **_processOrderBatch**: Iterates orders, skips settled orders (`pendingAmount == 0`), collects updates.
- **_finalizeUpdates**: Resizes update array.
- **_uint2str**: Converts uint to string for revert messages.

## Internal Functions (CCLiquidRouter)
**_createHistoricalUpdate** fetches live data for; `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`, and applies them in a new historical data entry using `ccUpdate`.

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
  - Sets correct `updateType` and `updateSort` in `_createBuy/SellOrderUpdates` for `ccUpdate`.
  - Skips settled orders via `pendingAmount == 0` check in `_processOrderBatch`.
  - Validates `step <= identifiers.length` in `_collectOrderIdentifiers`.
  - Validates input and output liquidity in `_prepareLiquidityTransaction`.
  - Resolves stack overflow in `_createBuy/SellOrderUpdates` by using helper functions (`_prepareCoreUpdate`, `_prepareAmountsUpdate`, `_prepareBalanceUpdate`) (v0.0.29).
  - Clarifies `amountSent` as settlement-specific in `_createBuy/SellOrderUpdates` (v0.0.28).
  - Uses `preTransferWithdrawn` for pending/filled updates and pre/post balance checks for `amountSent` (v0.0.28).
  - Fixed typo `normalizedSetle` to `normalizedSettle` in `_updateLiquidityBalances` (v0.0.30).

## Limitations and Assumptions
- Relies on `ICCLiquidity` for settlements, not direct Uniswap V2 swaps.
- No order creation, cancellation, payouts, or liquidity management.
- Uses `balanceOf` for Uniswap V2 reserves for price impact, not actual swaps.
- Zero amounts, failed transfers, or invalid prices return empty `UpdateType[]`.
- `depositor` set to `address(this)` in `ICCLiquidity` calls.
- `step` must be <= length of pending orders to avoid `NoPendingOrders` emission.
- `amountSent` accumulation in `CCListingTemplate.ccUpdate` correctly tracks total tokens sent to recipients across all settlements (partial or full).
- **Historical Data**: Creates a new `HistoricalData` entry at the start of `settleOrders` if pending orders exist, applying the latest data for respective; `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume` with a new `timestamp` via `ccUpdate`.

## Differences from CCSettlementRouter
- Focuses on `ICCLiquidity`-based settlements, excludes Uniswap V2 swaps.
- Inherits `CCLiquidPartial`, omits `CCUniPartial`, `CCSettlementPartial`.
- Uses helper functions (`_updateLiquidityBalances`, `_prepareCoreUpdate`, `_prepareAmountsUpdate`, `_prepareBalanceUpdate`) for stack management.
- Enhanced error logging with `UpdateFailed`, `MissingUniswapRouter`, `ApprovalFailed`, `TokenTransferFailed`, `SwapFailed`.
- Avoids re-fetching settled orders via `pendingAmount == 0` check.
- Supports `step` parameter for gas-efficient iteration starting from a specified index.
- Uses `ccUpdate` with three arrays (`updateType`, `updateSort`, `updateData`) instead of `update` (v0.0.20).
