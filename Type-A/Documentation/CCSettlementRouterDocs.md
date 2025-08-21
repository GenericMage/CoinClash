# CCSettlementRouter Contract Documentation

## Overview
The `CCSettlementRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform using Uniswap V2 for order execution. It inherits functionality from `CCSettlementPartial`, which extends `CCUniPartial` and `CCMainPartial`, integrating with external interfaces (`ICCListing`, `IUniswapV2Pair`, `IUniswapV2Router02`, `IERC20`) for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract handles order settlement via `settleOrders`, with gas optimization through `step` and `maxIterations`, robust error handling, and decimal precision for tokens. It avoids reserved keywords, uses explicit casting, and ensures graceful degradation with try-catch returning decoded error reasons. Transfers to/from the listing call `listingContract.update` after successful Uniswap V2 swaps, ensuring state consistency. Transfer taxes are handled using `amountInReceived`.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.13 (updated 2025-08-21)

**Inheritance Tree:** `CCSettlementRouter` → `CCSettlementPartial` → `CCUniPartial` → `CCMainPartial`

**Compatible Contracts:**
- `CCListingTemplate.sol` (v0.1.12)
- `CCMainPartial.sol` (v0.0.15)
- `CCUniPartial.sol` (v0.0.22)
- `CCSettlementPartial.sol` (v0.0.27)

## Mappings
- None defined directly in `CCSettlementRouter` or `CCSettlementPartial`. Relies on `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`) for order tracking.

## Structs
- **OrderContext** (`CCSettlementRouter`): Contains `orderId` (uint256), `pending` (uint256), `status` (uint8), `updates` (ICCListing.UpdateType[]).
- **PrepOrderUpdateResult** (`CCSettlementPartial`): Contains `tokenAddress` (address), `tokenDecimals` (uint8), `makerAddress` (address), `recipientAddress` (address), `orderStatus` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, denormalized).
- **MaxAmountInContext** (`CCUniPartial`): Contains `reserveIn` (uint256), `decimalsIn` (uint8), `normalizedReserveIn` (uint256), `currentPrice` (uint256).
- **SwapContext** (`CCUniPartial`): Contains `listingContract` (ICCListing), `makerAddress` (address), `recipientAddress` (address), `status` (uint8), `tokenIn` (address), `tokenOut` (address), `decimalsIn` (uint8), `decimalsOut` (uint8), `denormAmountIn` (uint256), `denormAmountOutMin` (uint256), `price` (uint256), `expectedAmountOut` (uint256).
- **SwapImpactContext** (`CCUniPartial`): Contains `reserveIn` (uint256), `reserveOut` (uint256), `decimalsIn` (uint8), `decimalsOut` (uint8), `normalizedReserveIn` (uint256), `normalizedReserveOut` (uint256), `amountInAfterFee` (uint256), `price` (uint256), `amountOut` (uint256).
- **BuyOrderUpdateContext** (`CCUniPartial`): Contains `makerAddress` (address), `recipient` (address), `status` (uint8), `amountReceived` (uint256), `normalizedReceived` (uint256), `amountSent` (uint256).
- **SellOrderUpdateContext** (`CCUniPartial`): Same as `BuyOrderUpdateContext` for sell orders.
- **TokenSwapData** (`CCUniPartial`): Contains `preBalanceIn` (uint256), `postBalanceIn` (uint256), `amountInReceived` (uint256), `preBalanceOut` (uint256), `postBalanceOut` (uint256), `amountReceived` (uint256), `amountOut` (uint256).
- **ETHSwapData** (`CCUniPartial`): Contains `preBalanceIn` (uint256), `postBalanceIn` (uint256), `amountInReceived` (uint256), `preBalanceOut` (uint256), `postBalanceOut` (uint256), `amountReceived` (uint256), `amountOut` (uint256).
- **ReserveContext** (`CCUniPartial`): Contains `reserveIn` (uint256), `decimalsIn` (uint8), `normalizedReserveIn` (uint256), `tokenA` (address).
- **ImpactContext** (`CCUniPartial`): Contains `currentPrice` (uint256), `maxImpactPercent` (uint256), `maxAmountIn` (uint256), `pendingAmount` (uint256).

## External Functions and Call Trees
### `settleOrders(address listingAddress, uint256 step, uint256 maxIterations, bool isBuyOrder)`
- **Purpose**: Iterates over pending buy or sell orders, validates price impact, processes swaps via Uniswap V2, updates the listing state, and returns a reason if no orders are settled.
- **Modifiers**: `nonReentrant`, `onlyValidListing(listingAddress)` (from `CCMainPartial`).
- **Parameters**:
  - `listingAddress`: Address of the `ICCListing` contract.
  - `step`: Starting index for order processing (e.g., if `pendingBuyOrdersView` returns `[10,11,22,23,24]` and `step = 3`, processing starts at index 3, orderId `23`).
  - `maxIterations`: Maximum number of orders to process for gas control.
  - `isBuyOrder`: True for buy orders, false for sell orders.
- **Returns**: `string memory` (reason if no orders settled, e.g., "No pending orders or invalid step", "No orders settled: price out of range, insufficient tokens, or swap failure", or empty string if successful).
- **Internal Call Tree**:
  1. **Fetch Orders**: Calls `listingContract.pendingBuyOrdersView()` or `pendingSellOrdersView()` to get `orderIds`.
     - Returns "No pending orders or invalid step" if `orderIds.length == 0` or `step >= orderIds.length`.
  2. **Iterate Orders**: Loops from `i = step` to `min(orderIds.length, step + maxIterations)`:
     - Calls `_validateOrder(listingAddress, orderId, isBuyOrder, listingContract)`:
       - Fetches `pending` via `listingContract.getBuyOrderAmounts(orderId)` or `getSellOrderAmounts(orderId)`.
       - Fetches `status` via `getBuyOrderCore` or `getSellOrderCore`.
       - Sets `context.pending = 0` if `_checkPricing` fails.
       - Returns `OrderContext` with `orderId`, `pending`, `status`, empty `updates`.
     - Skips if `context.pending == 0` or `context.status != 1`.
  3. **Process Order**: Calls `_processOrder(listingAddress, isBuyOrder, listingContract, context)`:
     - Calls `_processBuyOrder` or `_processSellOrder` (from `CCSettlementPartial`).
     - Returns updated `context` with `updates`.
  4. **Update Order**: Calls `_updateOrder(listingContract, context)`:
     - Calls `listingContract.update(context.updates)` with try-catch.
     - Verifies post-update `status` via `getBuyOrderCore` or `getSellOrderCore`.
     - Returns `(success, reason)` tuple; `success = true` if update succeeds and `status` is not 0 or 3.
  5. **Error Handling**: Returns `reason` from `_updateOrder` if non-empty; else continues loop. Returns "No orders settled: price out of range, insufficient tokens, or swap failure" if `count == 0`.
  - **_processBuyOrder/_processSellOrder** (from `CCSettlementPartial`):
    - Fetches `pending`, `filled`, `amountSent`, and `makerAddress`, `recipientAddress`, `status` via `getBuyOrderAmounts`/`getSellOrderAmounts` and `getBuyOrderCore`/`getSellOrderCore`.
    - Returns empty array if `pending == 0` or `currentPrice` (from `listingContract.prices(0)`) is outside `minPrice`/`maxPrice`.
    - Calls `_computeMaxAmountIn` (from `CCUniPartial`) to get `maxAmountIn`.
    - Sets `swapAmount = min(maxAmountIn, pendingAmount)`.
    - Calls `_executePartialBuySwap` or `_executePartialSellSwap` (from `CCUniPartial`).
    - Updates `UpdateType` structs to include `makerAddress` and `recipientAddress` for all updates (fixed in `CCSettlementPartial.sol` v0.0.24).
  - **_executePartialBuySwap/_executePartialSellSwap** (from `CCUniPartial`):
    - Calls `_prepareSwapData` or `_prepareSellSwapData` to populate `SwapContext` and `path`.
    - Returns empty array if `context.price == 0`.
    - For buy orders, if `tokenIn == address(0)`, calls `_executeBuyETHSwap`; else, `_executeBuyTokenSwap`.
    - For sell orders, if `tokenOut == address(0)`, calls `_executeSellETHSwapInternal`; else, `_executeSellTokenSwap`.
  - **_executeBuyETHSwap/_executeSellETHSwapInternal** (from `CCUniPartial`):
    - Calls `_performETHBuySwap` or `_performETHSellSwap` to execute Uniswap V2 swaps.
    - Populates `ETHSwapData` with pre/post balance checks.
    - Calls `_createBuyOrderUpdates` or `_createSellOrderUpdates` to return `UpdateType[]`.

## Internal Functions
- **_validateOrder** (`CCSettlementRouter`): Validates order details (`pending`, `status`) and pricing via `_checkPricing`. Returns `OrderContext`.
- **_processOrder** (`CCSettlementRouter`): Calls `_processBuyOrder` or `_processSellOrder` to process swaps, updates `OrderContext.updates`.
- **_updateOrder** (`CCSettlementRouter`): Calls `listingContract.update` with try-catch, verifies post-update `status`, returns `(success, reason)`.
- **_getTokenAndDecimals** (`CCSettlementPartial`): Returns `tokenAddress` and `tokenDecimals` from `listingContract.tokenA()`/`tokenB()` and `decimalsA()`/`decimalsB()`.
- **_checkPricing** (`CCSettlementPartial`): Validates `currentPrice` (from `listingContract.prices(0)`) against `maxPrice`/`minPrice`.
- **_computeAmountSent** (`CCSettlementPartial`): Returns pre-transfer balance for recipient (ETH or token).
- **_prepBuyOrderUpdate/_prepSellOrderUpdate** (`CCSettlementPartial`): Prepares `PrepOrderUpdateResult` with balance checks, calls `transactNative` or `transactToken`.
- **_processBuyOrder/_processSellOrder** (`CCSettlementPartial`): Validates `pendingAmount`, `currentPrice`, and `swapAmount`, calls `_executePartialBuySwap` or `_executePartialSellSwap`, ensures `makerAddress` and `recipientAddress` in all `UpdateType` structs.
- **_computeCurrentPrice**, **_computeSwapImpact**, **_fetchReserves**, **_computeImpactPercent**, **_computeMaxAmount**, **_prepareSwapData**, **_prepareSellSwapData**, **_prepareTokenSwap**, **_executeTokenSwap**, **_performETHBuySwap**, **_performETHSellSwap**, **_finalizeTokenSwap**, **_finalizeSellTokenSwap**, **_executeBuyETHSwap**, **_executeSellETHSwapInternal**, **_executeBuyTokenSwap**, **_executeSellTokenSwap**, **_executePartialBuySwap**, **_executePartialSellSwap**, **_createBuyOrderUpdates**, **_createSellOrderUpdates** (`CCUniPartial`): Handle swap logic, balance checks, and update generation.

## Swap Impact and Formulas
- **Price Impact** (`_computeSwapImpact`, called by `_executePartialBuySwap/_executePartialSellSwap`):
  - **Formulas**:
    - `reserveIn = isBuyOrder ? IERC20(tokenB).balanceOf(listingAddress) : IERC20(tokenA).balanceOf(listingAddress)`
    - `reserveOut = isBuyOrder ? IERC20(tokenA).balanceOf(listingAddress) : IERC20(tokenB).balanceOf(listingAddress)`
    - `normalizedReserveIn = normalize(reserveIn, decimalsIn)`
    - `normalizedReserveOut = normalize(reserveOut, decimalsOut)`
    - `amountInAfterFee = (amountIn * 997) / 1000`
    - `amountOut = (amountInAfterFee * normalizedReserveOut) / (normalizedReserveIn + amountInAfterFee)`
    - `price = listingContract.prices(0)`
  - **Description**: Calculates `amountOut` and `price` for a swap using `IERC20.balanceOf` for reserves. Applies Uniswap V2 fee (0.3%) via `amountInAfterFee`. The `listingContract` transfers tokens to `uniswapV2Pair` for execution. The impact is limited by `_computeMaxAmountIn`, which ensures the swap amount does not exceed the acceptable price slippage defined by `maxPrice` (buy) or `minPrice` (sell).
  - **Example**: For a buy order with `amountIn = 1000e18` (tokenB), `reserveIn = 10000e6` (tokenB, 6 decimals), `reserveOut = 5000e18` (tokenA, 18 decimals), `decimalsIn = 6`, `decimalsOut = 18`:
    - `normalizedReserveIn = normalize(10000e6, 6) = 10000e18`
    - `normalizedReserveOut = normalize(5000e18, 18) = 5000e18`
    - `amountInAfterFee = (1000e18 * 997) / 1000 = 997e18`
    - `amountOut = (997e18 * 5000e18) / (10000e18 + 997e18) ≈ 452.73e18` (tokenA)
    - `price = listingContract.prices(0)` (e.g., `5000e18`).
- **Max Amount In** (`_computeMaxAmountIn`, called via `_computeMaxAmount`, `_computeImpactPercent`, `_fetchReserves`):
  - **Formulas**:
    - `reserveContext = _fetchReserves(listingAddress, isBuyOrder)`
    - `reserveIn = isBuyOrder ? (tokenA == token0 ? reserve1 : reserve0) : (tokenA == token0 ? reserve0 : reserve1)`
    - `normalizedReserveIn = normalize(reserveIn, decimalsIn)`
    - `currentPrice = _computeCurrentPrice(listingAddress)`
    - `maxImpactPercent = isBuyOrder ? (maxPrice * 100e18 / currentPrice - 100e18) / 1e18 : (currentPrice * 100e18 / minPrice - 100e18) / 1e18`
    - `maxAmountIn = min((normalizedReserveIn * maxImpactPercent) / (100 * 2), pendingAmount)`
  - **Description**: Determines the maximum input amount (`maxAmountIn`) that keeps the swap within acceptable price impact limits. Fetches reserves from `IUniswapV2Pair.getReserves`, adjusting for token order (`token0`/`token1`). Normalizes reserves to 18 decimals. Calculates `maxImpactPercent` as the percentage deviation allowed from `currentPrice` (based on `maxPrice` for buy, `minPrice` for sell). Limits `maxAmountIn` to half the reserve-scaled impact to prevent excessive slippage, then caps at `pendingAmount`.
  - **Example**: For a buy order with `maxPrice = 5500e18`, `currentPrice = 5000e18`, `pendingAmount = 2000e18`, `reserveIn = 10000e6` (tokenB, 6 decimals):
    - `normalizedReserveIn = normalize(10000e6, 6) = 10000e18`
    - `maxImpactPercent = (5500e18 * 100e18 / 5000e18 - 100e18) / 1e18 = 10`
    - `maxAmountIn = (10000e18 * 10) / (100 * 2) = 500e18`
    - `maxAmountIn = min(500e18, 2000e18) = 500e18`.
- **Minimum Output** (`_prepareSwapData`/`_prepareSellSwapData`):
  - **Formulas**:
    - Buy: `denormAmountOutMin = (expectedAmountOut * 1e18) / maxPrice`
    - Sell: `denormAmountOutMin = (expectedAmountOut * minPrice) / 1e18`
  - **Description**: Calculates the minimum acceptable output (`denormAmountOutMin`) for Uniswap V2 swaps, denormalized to the output token’s decimals. For buy orders, divides `expectedAmountOut` (from `_computeSwapImpact`) by `maxPrice` to ensure the swap meets the maximum price constraint. For sell orders, multiplies by `minPrice` to enforce the minimum price. This protects against excessive slippage during execution.
  - **Example**: For a buy order with `expectedAmountOut = 452.73e18` (tokenA, 18 decimals), `maxPrice = 5500e18`:
    - `denormAmountOutMin = (452.73e18 * 1e18) / 5500e18 ≈ 82.31e18` (tokenA).

## Limitations and Assumptions
- **No Order Creation/Cancellation**: Handled by `CCOrderRouter`.
- **No Payouts or Liquidity Settlement**: Handled by `CCCLiquidityRouter` or `CCLiquidRouter`.
- **Uniswap V2 Dependency**: Requires valid `uniswapV2Router` and `uniswapV2PairView`.
- **Zero-Amount Handling**: Returns empty `ICCListing.UpdateType[]` for zero pending amounts or failed swaps.
- **Decimal Handling**: Uses `normalize`/`denormalize` for 1e18 precision, assumes `IERC20.decimals` or 18 for ETH.
- **Token Flow**:
  - Buy: `transactToken(tokenB)` or `transactNative` → `swapExactTokensForTokens` or `swapExactETHForTokens` → `amountReceived` (tokenA).
  - Sell: `transactToken(tokenA)` → `swapExactTokensForTokens` or `swapExactTokensForETH` → `amountReceived` (tokenB or ETH).
- **Price Impact**:
  - Uses `IERC20.balanceOf(listingAddress)` for `tokenA` and `tokenB` in `_computeSwapImpact` (updated in `CCUniPartial.sol` v0.0.22).
  - Buy: Increases price (handled by `listingContract.prices(0)`).
  - Sell: Decreases price (handled by `listingContract.prices(0)`).

## Additional Details
- **Reentrancy Protection**: `nonReentrant` on `settleOrders`.
- **Gas Optimization**: Uses `step`, `maxIterations`, and dynamic arrays. Refactored `settleOrders` into helper functions (`_validateOrder`, `_processOrder`, `_updateOrder`) with `OrderContext` to reduce stack pressure (v0.0.13).
- **Listing Validation**: `onlyValidListing` checks `ICCAgent.isValidListing`.
- **Uniswap V2 Parameters**:
  - `amountIn`: `amountInReceived` (tax-adjusted) or `denormAmountIn`.
  - `amountOutMin`: `denormAmountOutMin` from `(expectedAmountOut * 1e18) / maxPrice` (buy) or `(expectedAmountOut * minPrice) / 1e18` (sell).
  - `path`: `[tokenB, tokenA]` (buy), `[tokenA, tokenB]` (sell).
  - `to`: `recipientAddress`.
  - `deadline`: `block.timestamp + 300`.
- **Error Handling**: Try-catch in `transactNative`, `transactToken`, `approve`, `swap`, and `update` with decoded reasons (updated in `CCUniPartial.sol` v0.0.22).
- **Changes**:
  - `CCSettlementRouter.sol` (v0.0.13): Refactored `settleOrders` into `_validateOrder`, `_processOrder`, `_updateOrder` with `OrderContext` to resolve stack-too-deep error.
  - `CCSettlementRouter.sol` (v0.0.12): Removed `this.` from `_processBuyOrder` and `_processSellOrder` calls.
  - `CCSettlementPartial.sol` (v0.0.27): Removed `try` from `_executePartialBuySwap` and `_executePartialSellSwap` calls.
  - `CCSettlementPartial.sol` (v0.0.24): Fixed `makerAddress` and `recipientAddress` in all `UpdateType` structs for `listingContract.update`.
  - `CCUniPartial.sol` (v0.0.22): Updated `_createBuyOrderUpdates` and `_createSellOrderUpdates` to set `makerAddress` and `recipient` for all updates, fixed price impact calculations using `IERC20.balanceOf`.
