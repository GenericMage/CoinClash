# CCLiquidRouter Contract Documentation

## Overview
The `CCLiquidRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform using `ICCLiquidity` for liquid settlement. It inherits from `CCLiquidPartial`, which extends `CCMainPartial`, and integrates with `ICCListing`, `ICCLiquidity`, `IERC20`, and `IUniswapV2Pair` for token operations and reserve data. It uses `ReentrancyGuard` (including `Ownable`) for security. The contract handles liquid settlement via `settleBuyLiquid` and `settleSellLiquid`, supporting a `step` parameter for gas-efficient iteration, ensuring robust error logging, and avoiding re-fetching settled orders.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.19 (updated 2025-08-23)

**Inheritance Tree:** `CCLiquidRouter` → `CCLiquidPartial` (v0.0.27) → `CCMainPartial` (v0.0.14)

**Compatibility:** CCListingTemplate.sol (v0.2.0), ICCLiquidity.sol (v0.0.5), CCMainPartial.sol (v0.0.14), CCLiquidPartial.sol (v0.0.27), CCLiquidityTemplate.sol (v0.1.3).

## Mappings
- None defined in `CCLiquidRouter`. Uses `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`) for order tracking.

## Structs
- **OrderContext** (`CCLiquidPartial`): Holds `listingContract` (ICCListing), `tokenIn` (address), `tokenOut` (address), `liquidityAddr` (address).
- **PrepOrderUpdateResult** (`CCLiquidPartial`): Holds `tokenAddress` (address), `tokenDecimals` (uint8), `makerAddress` (address), `recipientAddress` (address), `orderStatus` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, denormalized tokenA for buy, tokenB for sell).
- **BuyOrderUpdateContext** (`CCLiquidPartial`): Holds `makerAddress` (address), `recipient` (address), `status` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, denormalized tokenA for buy).
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
- **Behavior**: Settles up to `maxIterations` pending buy orders starting from `step` by transferring principal (tokenB) to the liquidity contract via `ICCListing.transactToken` or `transactNative`, and settlement (tokenA) to recipients via `ICCLiquidity.transactToken` or `transactNative`. Checks liquidity via `listingVolumeBalancesView` (yBalance). Decreases `yLiquid` (tokenB) by `pendingAmount` and increases `xLiquid` (tokenA) by `amountOut` via `ICCLiquidity.update` in `_updateLiquidityBalances`. Emits `NoPendingOrders`, `InsufficientBalance`, or `UpdateFailed` and returns if no orders, `step` exceeds orders, insufficient yBalance, or update failure. Ensures price impact (`_computeSwapImpact`) and current price (`_computeCurrentPrice`) are within `minPrice` and `maxPrice`. Accumulates `amountSent` (tokenA) in `CCListingTemplate.update` to track total tokens sent to recipients across all settlements (partial or full).
- **Internal Call Flow**:
  1. Validates `listingAddress` via `onlyValidListing` (from `CCMainPartial`):
     - Requires `agent != address(0)`; reverts if unset.
     - Calls `ICCAgent.isValidListing(listingAddress)` with try-catch, returning `isValid` and `ListingDetails`.
     - Validates `isValid`, `details.listingAddress == listingAddress`, `details.liquidityAddress != address(0)`, and `details.tokenA != details.tokenB`.
     - Reverts with detailed reason if validation fails.
  2. Declares `listingContract = ICCListing(listingAddress)` for `pendingBuyOrdersView`, `listingVolumeBalancesView`, `update`, `decimalsA/B`, `tokenA/B`, `liquidityAddressView`, `getBuyOrderPricing/Amounts/Core`.
  3. Fetches `pendingBuyOrdersView`; emits `NoPendingOrders` if empty or `step >= length`.
  4. Fetches `(xBalance, yBalance, xVolume, yVolume)` via `listingVolumeBalancesView`; emits `InsufficientBalance` if `yBalance == 0`.
  5. Calls `this._processOrderBatch(listingAddress, maxIterations, true, step)` (from `CCLiquidPartial`):
     - Creates `OrderBatchContext` (`listingAddress`, `maxIterations`, `isBuyOrder = true`).
     - Calls `_collectOrderIdentifiers(listingAddress, maxIterations, true, step)`:
       - Fetches `pendingBuyOrdersView`, checks `step <= length`.
       - Collects up to `maxIterations` order IDs starting from `step` (e.g., for IDs `[2, 22, 23, 24, 30]`, `step=2`, `maxIterations=3`, collects `[23, 24, 30]`).
       - Returns `orderIdentifiers` and `iterationCount`.
     - Initializes `tempUpdates` array (`iterationCount * 3` for core, amounts, balance updates).
     - Iterates up to `iterationCount`:
       - Fetches `(pendingAmount, filled, amountSent)` via `getBuyOrderAmounts(orderIdentifiers[i])`; skips if `pendingAmount == 0` (avoids settled orders).
       - Calls `_processSingleOrder(listingAddress, orderId, true, pendingAmount)`:
         - Declares `listingContract = ICCListing(listingAddress)` for `decimalsA/B`, `liquidityAddressView`, `getBuyOrderPricing/Amounts`.
         - Fetches `(maxPrice, minPrice)` via `getBuyOrderPricing`.
         - Computes `currentPrice` via `_computeCurrentPrice`:
           - Calls `listingContract.prices(0)` with try-catch; reverts with detailed reason if fails.
         - Computes `impactPrice`, `amountOut` via `_computeSwapImpact`:
           - Calls `_getSwapReserves(listingAddress, true)`:
             - Fetches Uniswap V2 `pairAddress` via `uniswapV2PairView`; requires non-zero.
             - Determines `token0` via `IUniswapV2Pair.token0`; checks if `tokenB` is `token0` for input/output.
             - Fetches reserves via `IERC20(tokenB).balanceOf(pairAddress)` (input) and `IERC20(tokenA).balanceOf(pairAddress)` (output).
             - Normalizes reserves to 18 decimals using `normalize`.
           - Applies 0.3% fee (`amountInAfterFee = (pendingAmount * 997) / 1000`).
           - Computes `amountOut = (amountInAfterFee * normalizedReserveOut) / (normalizedReserveIn + amountInAfterFee)`.
           - Computes `price = ((normalizedReserveIn + amountInAfterFee) * 1e18) / (normalizedReserveOut - amountOut)`; sets to `type(uint256).max` if underflow.
           - Denormalizes `amountOut` to `decimalsA`.
         - If `minPrice <= {currentPrice, impactPrice} <= maxPrice`, calls `executeSingleBuyLiquid(listingAddress, orderId)`:
           - Fetches `(pendingAmount, , )` via `getBuyOrderAmounts`; returns empty array if `pendingAmount == 0`.
           - Creates `OrderContext` (`listingContract`, `tokenIn=tokenB`, `tokenOut=tokenA`, `liquidityAddr`).
           - Calls `_prepBuyLiquidUpdates(context, orderId, pendingAmount)`:
             - Calls `_checkPricing(listingAddress, orderId, true, pendingAmount)`:
               - Fetches `(maxPrice, minPrice)` via `getBuyOrderPricing`.
               - Calls `_computeSwapImpact`; emits `PriceOutOfBounds` if `impactPrice` outside bounds.
             - Checks `uniswapV2Router` (from `CCMainPartial`); emits `MissingUniswapRouter` if unset.
             - Calls `_prepareLiquidityTransaction(listingAddress, pendingAmount, true)`:
               - Fetches `liquidityAddr` via `liquidityAddressView`.
               - Declares `liquidityContract = ICCLiquidity(liquidityAddr)`.
               - Fetches `(xAmount, yAmount)` via `liquidityContract.liquidityAmounts`.
               - Calls `_computeSwapImpact` for `amountOut`.
               - Requires `yAmount >= pendingAmount` (tokenB input) and `xAmount >= amountOut` (tokenA output).
               - Returns `amountOut`, `tokenIn=tokenB`, `tokenOut=tokenA`.
             - Calls `_prepBuyOrderUpdate(listingAddress, orderId, pendingAmount)`:
               - Fetches `(tokenAddress=tokenB, tokenDecimals=decimalsB)` via `_getTokenAndDecimals(listingAddress, true)`.
               - Fetches `(makerAddress, recipientAddress, orderStatus)` via `getBuyOrderCore`.
               - Fetches `(pending, filled, amountSent)` via `getBuyOrderAmounts`; requires `pendingAmount <= pending`.
               - Computes `amountOut` via `_prepareLiquidityTransaction`.
               - Denormalizes `pendingAmount` to `decimalsB`, `amountOut` to `decimalsA`.
               - Computes `preBalance` via `_computeAmountSent(tokenOut=tokenA, recipientAddress, denormalizedAmountOut)`:
                 - Returns `recipientAddress.balance` if `tokenOut` is native; else `IERC20(tokenOut).balanceOf(recipientAddress)`.
               - If `tokenB != address(0)`, approves `denormalizedAmount` to `uniswapV2Router`; emits `ApprovalFailed` if fails.
               - Transfers `denormalizedAmount` (tokenB) to `liquidityAddr` via `transactToken` (or `transactNative` if native); emits `TokenTransferFailed` if fails.
               - Computes `postBalance` of `tokenA` for `recipientAddress`; sets `amountSent = postBalance - preBalance` if positive, else 0.
               - Returns `PrepOrderUpdateResult` (`tokenAddress`, `tokenDecimals`, `makerAddress`, `recipientAddress`, `orderStatus`, `amountReceived=pendingAmount`, `normalizedReceived`, `amountSent`).
             - Creates `BuyOrderUpdateContext` (`makerAddress`, `recipientAddress`, `orderStatus`, `amountReceived`, `normalizedReceived`, `amountSent`).
             - Calls `_createBuyOrderUpdates(orderId, updateContext, pendingAmount)`:
               - Returns `UpdateType[3]`:
                 - `updateType=1, structId=0` (core): `index=orderId`, `addr=makerAddress`, `recipient=recipientAddress`.
                 - `updateType=1, structId=2` (amounts): `index=orderId`, `value=normalizedReceived` (tokenB), `amountSent` (tokenA for this settlement).
                 - `updateType=0, structId=0` (balance): `index=1` (yBalance), `value=normalizedReceived` (increase tokenB).
             - Returns empty array if pricing, router, or swap fails.
           - Calls `_updateLiquidityBalances(listingAddress, orderId, true, pendingAmount, amountOut)`:
             - Declares `liquidityContract = ICCLiquidity(liquidityAddr)`.
             - Fetches `(xAmount, yAmount)` via `liquidityAmounts`.
             - Normalizes `pendingAmount` (tokenB), `amountOut` (tokenA).
             - Creates `ICCLiquidity.UpdateType[2]`:
               - `updateType=0, index=1` (yLiquid): `value = yAmount - normalizedPending` (subtract tokenB).
               - `updateType=0, index=0` (xLiquid): `value = xAmount + normalizedSettle` (add tokenA).
             - Calls `liquidityContract.update(address(this), liquidityUpdates)`; emits `SwapFailed` if fails.
           - Returns empty array if pricing or swap fails.
         - Emits `PriceOutOfBounds` if prices invalid; returns empty array.
       - Appends updates to `tempUpdates`.
     - Calls `_finalizeUpdates(tempUpdates, updateIndex)`:
       - Resizes to `updateIndex` (non-empty updates).
       - Returns `finalUpdates`.
  6. If `updates.length > 0`, calls `listingContract.update(updates)` with try-catch:
     - Emits `UpdateFailed` with reason or "Unknown update error" if fails.
     - Does not revert, ensuring graceful degradation.
- **Graceful Degradation**: Returns without reverting if no orders, `step` exceeds orders, insufficient balance, price out of bounds, or update failure, emitting appropriate events (`NoPendingOrders`, `InsufficientBalance`, `PriceOutOfBounds`, `UpdateFailed`, `MissingUniswapRouter`, `ApprovalFailed`, `TokenTransferFailed`, `SwapFailed`).
- **Note**: For orders partially settled by another router, `amountSent` (tokenA) in `getBuyOrderAmounts` accumulates via `amounts.amountSent += u.amountSent` in `CCListingTemplate.update`, correctly tracking the total tokens sent to recipients across all settlements (partial or full).

### settleSellLiquid(address listingAddress, uint256 maxIterations, uint256 step)
- **Parameters**:
  - `listingAddress` (address): `ICCListing` contract address for order book.
  - `maxIterations` (uint256): Limits orders processed to control gas.
  - `step` (uint256): Starting index in `pendingSellOrdersView` for gas-efficient iteration.
- **Behavior**: Settles up to `maxIterations` pending sell orders starting from `step` by transferring principal (tokenA) to the liquidity contract via `ICCListing.transactToken` or `transactNative`, and settlement (tokenB) to recipients via `ICCLiquidity.transactToken` or `transactNative`. Checks liquidity via `listingVolumeBalancesView` (xBalance). Decreases `xLiquid` (tokenA) by `pendingAmount` and increases `yLiquid` (tokenB) by `amountOut` via `ICCLiquidity.update` in `_updateLiquidityBalances`. Emits `NoPendingOrders`, `InsufficientBalance`, or `UpdateFailed` and returns if no orders, `step` exceeds orders, insufficient xBalance, or update failure. Ensures price impact and current price are within `minPrice` and `maxPrice`. Accumulates `amountSent` (tokenB) in `CCListingTemplate.update` to track total tokens sent to recipients across all settlements (partial or full).
- **Internal Call Flow**:
  1. Validates `listingAddress` via `onlyValidListing` (same as `settleBuyLiquid`).
  2. Declares `listingContract = ICCListing(listingAddress)` for `pendingSellOrdersView`, `listingVolumeBalancesView`, `update`, `decimalsA/B`, `tokenA/B`, `liquidityAddressView`, `getSellOrderPricing/Amounts/Core`.
  3. Fetches `pendingSellOrdersView`; emits `NoPendingOrders` if empty or `step >= length`.
  4. Fetches `(xBalance, yBalance, xVolume, yVolume)` via `listingVolumeBalancesView`; emits `InsufficientBalance` if `xBalance == 0`.
  5. Calls `this._processOrderBatch(listingAddress, maxIterations, false, step)`:
     - Creates `OrderBatchContext` (`listingAddress`, `maxIterations`, `isBuyOrder = false`).
     - Calls `_collectOrderIdentifiers(listingAddress, maxIterations, false, step)`:
       - Fetches `pendingSellOrdersView`, checks `step <= length`.
       - Collects up to `maxIterations` order IDs starting from `step`.
       - Returns `orderIdentifiers` and `iterationCount`.
     - Initializes `tempUpdates` array (`iterationCount * 3`).
     - Iterates up to `iterationCount`:
       - Fetches `(pendingAmount, filled, amountSent)` via `getSellOrderAmounts(orderIdentifiers[i])`; skips if `pendingAmount == 0`.
       - Calls `_processSingleOrder(listingAddress, orderId, false, pendingAmount)`:
         - Declares `listingContract = ICCListing(listingAddress)` for `decimalsA/B`, `liquidityAddressView`, `getSellOrderPricing/Amounts`.
         - Fetches `(maxPrice, minPrice)` via `getSellOrderPricing`.
         - Computes `currentPrice` via `_computeCurrentPrice`.
         - Computes `impactPrice`, `amountOut` via `_computeSwapImpact`:
           - Calls `_getSwapReserves(listingAddress, false)`:
             - Fetches reserves via `IERC20(tokenA).balanceOf(pairAddress)` (input) and `IERC20(tokenB).balanceOf(pairAddress)` (output).
             - Normalizes reserves.
           - Applies 0.3% fee, computes `amountOut` and `price`.
         - If `minPrice <= {currentPrice, impactPrice} <= maxPrice`, calls `executeSingleSellLiquid(listingAddress, orderId)`:
           - Fetches `(pendingAmount, , )` via `getSellOrderAmounts`; returns empty array if `pendingAmount == 0`.
           - Creates `OrderContext` (`listingContract`, `tokenIn=tokenA`, `tokenOut=tokenB`, `liquidityAddr`).
           - Calls `_prepSellLiquidUpdates(context, orderId, pendingAmount)`:
             - Calls `_checkPricing(listingAddress, orderId, false, pendingAmount)`; emits `PriceOutOfBounds` if invalid.
             - Checks `uniswapV2Router`; emits `MissingUniswapRouter` if unset.
             - Calls `_prepareLiquidityTransaction(listingAddress, pendingAmount, false)`:
               - Fetches `(xAmount, yAmount)` via `liquidityContract.liquidityAmounts`.
               - Calls `_computeSwapImpact` for `amountOut`.
               - Requires `xAmount >= pendingAmount` (tokenA input) and `yAmount >= amountOut` (tokenB output).
               - Returns `amountOut`, `tokenIn=tokenA`, `tokenOut=tokenB`.
             - Calls `_prepSellOrderUpdate(listingAddress, orderId, pendingAmount)`:
               - Fetches `(tokenAddress=tokenA, tokenDecimals=decimalsA)` via `_getTokenAndDecimals(listingAddress, false)`.
               - Fetches `(makerAddress, recipientAddress, orderStatus)` via `getSellOrderCore`.
               - Fetches `(pending, filled, amountSent)` via `getSellOrderAmounts`; requires `pendingAmount <= pending`.
               - Computes `amountOut` via `_prepareLiquidityTransaction`.
               - Denormalizes `pendingAmount` to `decimalsA`, `amountOut` to `decimalsB`.
               - Computes `preBalance` via `_computeAmountSent(tokenOut=tokenB, recipientAddress, denormalizedAmountOut)`.
               - If `tokenA != address(0)`, approves `denormalizedAmount` to `uniswapV2Router`; emits `ApprovalFailed` if fails.
               - Transfers `denormalizedAmount` (tokenA) to `liquidityAddr` via `transactToken` (or `transactNative`); emits `TokenTransferFailed` if fails.
               - Computes `postBalance` of `tokenB` for `recipientAddress`; sets `amountSent = postBalance - preBalance` if positive, else 0.
               - Returns `PrepOrderUpdateResult`.
             - Creates `SellOrderUpdateContext` (`makerAddress`, `recipientAddress`, `orderStatus`, `amountReceived`, `normalizedReceived`, `amountSent`).
             - Calls `_createSellOrderUpdates(orderId, updateContext, pendingAmount)`:
               - Returns `UpdateType[3]`:
                 - `updateType=2, structId=0` (core): `index=orderId`, `addr=makerAddress`, `recipient=recipientAddress`.
                 - `updateType=2, structId=2` (amounts): `index=orderId`, `value=normalizedReceived` (tokenA), `amountSent` (tokenB for this settlement).
                 - `updateType=0, structId=0` (balance): `index=0` (xBalance), `value=normalizedReceived` (increase tokenA).
             - Returns empty array if pricing, router, or swap fails.
           - Calls `_updateLiquidityBalances(listingAddress, orderId, false, pendingAmount, amountOut)`:
             - Creates `ICCLiquidity.UpdateType[2]`:
               - `updateType=0, index=0` (xLiquid): `value = xAmount - normalizedPending` (subtract tokenA).
               - `updateType=0, index=1` (yLiquid): `value = yAmount + normalizedSettle` (add tokenB).
             - Calls `liquidityContract.update(address(this), liquidityUpdates)`; emits `SwapFailed` if fails.
           - Returns empty array if pricing or swap fails.
         - Emits `PriceOutOfBounds` if prices invalid; returns empty array.
       - Appends updates to `tempUpdates`.
     - Calls `_finalizeUpdates(tempUpdates, updateIndex)`; returns `finalUpdates`.
  6. If `updates.length > 0`, calls `listingContract.update(updates)` with try-catch:
     - Emits `UpdateFailed` with reason or "Unknown update error" if fails.
     - Does not revert, ensuring graceful degradation.
- **Graceful Degradation**: Returns without reverting if no orders, `step` exceeds orders, insufficient balance, price out of bounds, or update failure, emitting appropriate events.
- **Note**: For orders partially settled by another router, `amountSent` (tokenB) in `getSellOrderAmounts` accumulates via `amounts.amountSent += u.amountSent` in `CCListingTemplate.update`, correctly tracking the total tokens sent to recipients across all settlements (partial or full).

## Internal Functions (CCLiquidPartial)
- **_getSwapReserves**: Fetches Uniswap V2 reserves via `IERC20.balanceOf` (`token0`, `tokenB`) and normalizes to `SwapImpactContext`.
- **_computeCurrentPrice**: Fetches price from `ICCListing.prices(0)` with try-catch, reverting with detailed reason if failed.
- **_computeSwapImpact**: Calculates output and price impact with 0.3% fee using `balanceOf` reserves.
- **_checkPricing**: Validates `impactPrice` within `minPrice` and `maxPrice`.
- **_prepareLiquidityTransaction**: Computes `amountOut`, checks liquidity (`xAmount` and `yAmount` for input/output).
- **_prepBuy/SellOrderUpdate**: Handles transfers (principal to liquidity, settlement to recipient) with pre/post balance checks, sets `amountSent` to received token (tokenA for buy, tokenB for sell) for current settlement, emits `MissingUniswapRouter`, `ApprovalFailed`, `TokenTransferFailed` on failure, returns `PrepOrderUpdateResult`.
- **_prepBuy/SellLiquidUpdates**: Validates pricing, checks `uniswapV2Router`, computes `amountOut`, prepares `UpdateType[]` with `addr = makerAddress`; emits `PriceOutOfBounds`, `MissingUniswapRouter`, `SwapFailed` if invalid.
- **_createBuy/SellOrderUpdates**: Builds `UpdateType[]` for order updates with `addr = makerAddress` for registry updates, sets `amountSent` for current settlement only (v0.0.27).
- **_collectOrderIdentifiers**: Fetches order IDs starting from `step` up to `maxIterations`, checks `step <= identifiers.length`.
- **_processSingleOrder**: Validates prices, executes order, calls `_updateLiquidityBalances` to update liquidity (`yLiquid` and `xLiquid` for buy, `xLiquid` and `yLiquid` for sell); emits `PriceOutOfBounds` or `SwapFailed` if invalid.
- **_updateLiquidityBalances**: Updates `xLiquid` and `yLiquid` (subtract outgoing, add incoming) via `ICCLiquidity.update`; emits `SwapFailed` on failure.
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
  - Resolves stack overflow in `_processSingleOrder` by extracting liquidity updates to `_updateLiquidityBalances` (v0.0.26).
  - Clarifies `amountSent` as settlement-specific in `_createBuy/SellOrderUpdates` (v0.0.27).

## Limitations and Assumptions
- Relies on `ICCLiquidity` for settlements, not direct Uniswap V2 swaps.
- No order creation, cancellation, payouts, or liquidity management.
- Uses `balanceOf` for Uniswap V2 reserves for price impact, not actual swaps.
- Zero amounts, failed transfers, or invalid prices return empty `UpdateType[]`.
- `depositor` set to `address(this)` in `ICCLiquidity` calls.
- `step` must be <= length of pending orders to avoid `NoPendingOrders` emission.
- `amountSent` accumulation in `CCListingTemplate.update` correctly tracks total tokens sent to recipients across all settlements (partial or full).

## Differences from CCSettlementRouter
- Focuses on `ICCLiquidity`-based settlements, excludes Uniswap V2 swaps.
- Inherits `CCLiquidPartial`, omits `CCUniPartial`, `CCSettlementPartial`.
- Uses helper functions (`_updateLiquidityBalances`) for stack management.
- Enhanced error logging with `UpdateFailed`, `MissingUniswapRouter`, `ApprovalFailed`, `TokenTransferFailed`, `SwapFailed`.
- Avoids re-fetching settled orders via `pendingAmount == 0` check.
- Supports `step` parameter for gas-efficient iteration starting from a specified index.
