# CCSettlementRouter Contract Documentation

## Overview
The `CCSettlementRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform using Uniswap V2 for order execution. It inherits functionality from `CCSettlementPartial`, which extends `CCUniPartial` and `CCMainPartial`, integrating with external interfaces (`ICCListing`, `IUniswapV2Pair`, `IUniswapV2Router02`, `IERC20`) for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract handles order settlement via `settleOrders`, with gas optimization through `step` and `maxIterations`, robust error handling, and decimal precision for tokens. It avoids reserved keywords, uses explicit casting, and ensures graceful degradation with try-catch returning decoded error reasons. Transfers to/from the listing call `listingContract.update` after successful Uniswap V2 swaps, ensuring state consistency. Transfer taxes are handled using `amountInReceived`.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.10 (updated 2025-08-21)

**Inheritance Tree:** `CCSettlementRouter` → `CCSettlementPartial` → `CCUniPartial` → `CCMainPartial`

**Compatible Contracts:**
- `CCListingTemplate.sol` (v0.1.9)
- `CCMainPartial.sol` (v0.0.15)
- `CCUniPartial.sol` (v0.0.21)
- `CCSettlementPartial.sol` (v0.0.24)

## Mappings
- None defined directly in `CCSettlementRouter` or `CCSettlementPartial`. Relies on `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`) for order tracking.

## Structs
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
- **Returns**: `string memory` (reason if no orders settled, e.g., "No pending orders or invalid step", "No orders settled: price out of range or insufficient tokens", or empty string if successful).
- **Internal Call Tree**:
  1. **Fetch Orders**: Calls `listingContract.pendingBuyOrdersView()` or `pendingSellOrdersView()` to get `orderIds`.
     - Returns "No pending orders or invalid step" if `orderIds.length == 0` or `step >= orderIds.length`.
  2. **Iterate Orders**: Loops from `i = step` to `min(orderIds.length, step + maxIterations)`.
     - Fetches `pending` via `listingContract.getBuyOrderAmounts(orderId)` or `getSellOrderAmounts(orderId)`.
     - Skips if `pending == 0`.
  3. **Validate Pricing**: Calls `_checkPricing(listingAddress, orderId, isBuyOrder, pending)`:
     - Gets `maxPrice`, `minPrice` via `listingContract.getBuyOrderPricing` or `getSellOrderPricing`.
     - Fetches `currentPrice` via `listingContract.prices(0)` (updated in `CCSettlementPartial.sol` v0.0.24).
     - Returns `true` if `currentPrice <= maxPrice && currentPrice >= minPrice`, else skips.
  4. **Process Order**: Calls `_processBuyOrder` or `_processSellOrder` (from `CCSettlementPartial`):
     - **_processBuyOrder/_processSellOrder**:
       - Fetches `pending`, `filled`, `amountSent`, and `makerAddress`, `recipientAddress`, `status` via `getBuyOrderAmounts`/`getSellOrderAmounts` and `getBuyOrderCore`/`getSellOrderCore`.
       - Returns empty array if `pending == 0` or `currentPrice` (from `listingContract.prices(0)`) is outside `minPrice`/`maxPrice`.
       - Calls `_computeMaxAmountIn` (from `CCUniPartial`) to get `maxAmountIn`.
       - Sets `swapAmount = min(maxAmountIn, pendingAmount)` with validation (`require(swapAmount <= pendingAmount)`).
       - Calls `_executePartialBuySwap` or `_executePartialSellSwap` (from `CCUniPartial`).
       - Updates `UpdateType` structs to include `makerAddress` and `recipientAddress` for all updates (fixed in `CCSettlementPartial.sol` v0.0.24).
     - **_executePartialBuySwap/_executePartialSellSwap**:
       - Calls `_prepareSwapData` or `_prepareSellSwapData` to populate `SwapContext` and `path`.
       - Returns empty array if `context.price == 0`.
       - For buy orders, if `tokenIn == address(0)`, calls `_executeBuyETHSwap`; else, `_executeBuyTokenSwap`.
       - For sell orders, if `tokenOut == address(0)`, calls `_executeSellETHSwapInternal`; else, `_executeSellTokenSwap`.
     - **_executeBuyETHSwap/_executeSellETHSwapInternal**:
       - Calls `_performETHBuySwap` or `_performETHSellSwap` to execute Uniswap V2 swaps.
       - Populates `ETHSwapData` with pre/post balance checks.
       - Calls `_createBuyOrderUpdates` or `_createSellOrderUpdates` to generate `ICCListing.UpdateType[]`.
     - **_executeBuyTokenSwap/_executeSellTokenSwap**:
       - Calls `_prepareTokenSwap` and `_executeTokenSwap` to execute token-to-token swaps.
       - Populates `TokenSwapData` with pre/post balance checks.
       - Calls `_finalizeTokenSwap` or `_finalizeSellTokenSwap`, which calls `_createBuyOrderUpdates` or `_createSellOrderUpdates`.
     - **_performETHBuySwap/_performETHSellSwap/_executeTokenSwap**:
       - Executes `transactNative` or `transactToken` (from `listingContract`) to transfer input tokens/ETH.
       - Approves tokens for Uniswap V2 via `IERC20.approve(uniswapV2Router, amountInReceived)`.
       - Calls `IUniswapV2Router02.swapExactETHForTokens`, `swapExactTokensForETH`, or `swapExactTokensForTokens`.
       - Computes `amountReceived` via pre/post balance checks.
     - **_createBuyOrderUpdates/_createSellOrderUpdates**:
       - Returns `ICCListing.UpdateType[]` with updates for amount received and order status, setting `makerAddress` and `recipient` for all updates (fixed in `CCUniPartial.sol` v0.0.21).
  5. **Update Listing**: Calls `listingContract.update(updates)` with try-catch, reverting with decoded error reasons (e.g., `"Update failed for order <orderId>: <reason>"`).
  6. **Validation**: Increments `count` on successful updates, returns "No orders settled: price out of range or insufficient tokens" if `count == 0`, else empty string.
- **Error Handling**:
  - Reverts only on catastrophic failures (e.g., failed `transactNative`, `transactToken`, `approve`, `swap`, or `update`) with decoded reasons.
  - Returns descriptive strings for non-catastrophic cases (e.g., no pending orders, invalid step, price out of range).
  - Skips invalid orders (zero pending, invalid pricing) without state changes.
- **Gas Optimization**:
  - Uses `step` to skip processed orders.
  - Limits iterations with `maxIterations`.
  - Avoids nested calls during struct initialization.

## Partial Settlement Functionality
The system supports partial settlement of pending orders to minimize price impact and ensure execution within acceptable price bounds. In `_processBuyOrder` and `_processSellOrder` (from `CCSettlementPartial.sol`), the contract calculates `maxAmountIn` using `_computeMaxAmountIn` (from `CCUniPartial.sol`), which considers the maximum allowable price impact based on the order's `maxPrice` and `minPrice`. The `swapAmount` is set to `min(maxAmountIn, pendingAmount)`, ensuring that only a portion of the pending order is executed if the full amount would cause excessive price slippage. This partial execution:
- **Reduces Price Impact**: By limiting the input amount (`swapAmount`), the contract minimizes the effect on the pool's price, as calculated in `_computeSwapImpact`.
- **Ensures Price Constraints**: Only executes swaps within the order's `maxPrice` (for buy orders) or `minPrice` (for sell orders), skipping orders if `currentPrice` (from `listingContract.prices(0)`) is outside these bounds.
- **Handles Partial Fills**: Updates the order's `filled` and `pending` amounts via `listingContract.update`, setting the order status to partially filled (`status = 2`) if `normalizedReceived < pendingAmount`, or filled (`status = 3`) if fully executed.
- **Iterative Processing**: The `settleOrders` function processes multiple orders in a single transaction (up to `maxIterations`), allowing partial settlements across orders to optimize gas and maintain market stability.

## Formulas
Uniswap V2 formulas (from `CCUniPartial.sol`):
- **Price Calculation** (`_computeCurrentPrice`, updated in `CCUniPartial.sol` v0.0.21):
  - **Formula**: `price = listingContract.prices(0)`
  - **Description**: Retrieves the current price from the `ICCListing` contract's `prices(0)` function, which uses `IERC20.balanceOf` for `tokenA` and `tokenB` at `listingAddress` (as updated in `CCListingTemplate.sol` v0.1.9). The price is normalized to 18 decimals, representing the tokenA/tokenB ratio. Reverts if `price == 0` to ensure valid pricing.
  - **Example**: If `listingContract.prices(0)` returns `5000e18` (5000 tokenA per tokenB), the price is used directly for swap calculations.
- **Swap Impact** (`_computeSwapImpact`, updated in `CCUniPartial.sol` v0.0.21):
  - **Formulas**:
    - `reserveIn = isBuyOrder ? IERC20(tokenB).balanceOf(listingAddress) : IERC20(tokenA).balanceOf(listingAddress)`
    - `reserveOut = isBuyOrder ? IERC20(tokenA).balanceOf(listingAddress) : IERC20(tokenB).balanceOf(listingAddress)`
    - `normalizedReserveIn = normalize(reserveIn, decimalsIn)`
    - `normalizedReserveOut = normalize(reserveOut, decimalsOut)`
    - `amountInAfterFee = (amountIn * 997) / 1000`
    - `amountOut = (amountInAfterFee * normalizedReserveOut) / (normalizedReserveIn + amountInAfterFee)`
    - `price = listingContract.prices(0)`
  - **Description**: Calculates the expected output (`amountOut`) and price impact for a swap. Uses `IERC20.balanceOf` to fetch reserves of `tokenA` and `tokenB` from `listingAddress`, normalizing to 18 decimals. Applies Uniswap V2’s 0.3% fee (`amountIn * 997 / 1000`). The `amountOut` is computed using the constant product formula, adjusted for fees. The `price` is sourced from `listingContract.prices(0)` for consistency with the listing’s price feed.
  - **Impact Price Explanation**: The price impact is implicitly calculated as the change in `price` post-swap, but `_computeSwapImpact` focuses on `amountOut` for execution. The impact is limited by `_computeMaxAmountIn`, which ensures the swap amount does not exceed the acceptable price slippage defined by `maxPrice` (buy) or `minPrice` (sell). For a buy order, adding `amountInAfterFee` to `normalizedReserveIn` increases the price, while for a sell order, reducing `normalizedReserveOut` decreases the price.
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

## Internal Functions
- **_getTokenAndDecimals** (`CCSettlementPartial`): Returns `tokenAddress` and `tokenDecimals` from `listingContract.tokenA()`/`tokenB()` and `decimalsA()`/`decimalsB()`.
- **_checkPricing** (`CCSettlementPartial`): Validates `currentPrice` (from `listingContract.prices(0)`) against `maxPrice`/`minPrice`.
- **_computeAmountSent** (`CCSettlementPartial`): Returns pre-transfer balance for recipient (ETH or token).
- **_prepBuyOrderUpdate/_prepSellOrderUpdate** (`CCSettlementPartial`): Prepares `PrepOrderUpdateResult` with balance checks, calls `transactNative` or `transactToken`.
- **_processBuyOrder/_processSellOrder** (`CCSettlementPartial`): Validates `pendingAmount`, `currentPrice` (from `listingContract.prices(0)`), and `swapAmount`, calls `_executePartialBuySwap` or `_executePartialSellSwap`, ensures `makerAddress` and `recipientAddress` in all `UpdateType` structs (fixed in v0.0.24).
- **_computeCurrentPrice**, **_computeSwapImpact**, **_fetchReserves**, **_computeImpactPercent**, **_computeMaxAmount**, **_prepareSwapData**, **_prepareSellSwapData**, **_prepareTokenSwap**, **_executeTokenSwap**, **_performETHBuySwap**, **_performETHSellSwap**, **_finalizeTokenSwap**, **_finalizeSellTokenSwap**, **_executeBuyETHSwap**, **_executeSellETHSwapInternal**, **_executeBuyTokenSwap**, **_executeSellTokenSwap**, **_executePartialBuySwap**, **_executePartialSellSwap**, **_createBuyOrderUpdates**, **_createSellOrderUpdates** (`CCUniPartial`): Handle swap logic, balance checks, and update generation.

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
  - Uses `IERC20.balanceOf(listingAddress)` for `tokenA` and `tokenB` in `_computeSwapImpact` (updated in `CCUniPartial.sol` v0.0.21).
  - Buy: Increases price (handled by `listingContract.prices(0)`).
  - Sell: Decreases price (handled by `listingContract.prices(0)`).

## Additional Details
- **Reentrancy Protection**: `nonReentrant` on `settleOrders`.
- **Gas Optimization**: Uses `step`, `maxIterations`, and dynamic arrays.
- **Listing Validation**: `onlyValidListing` checks `ICCAgent.isValidListing`.
- **Uniswap V2 Parameters**:
  - `amountIn`: `amountInReceived` (tax-adjusted) or `denormAmountIn`.
  - `amountOutMin`: `denormAmountOutMin` from `(expectedAmountOut * 1e18) / maxPrice` (buy) or `(expectedAmountOut * minPrice) / 1e18` (sell).
  - `path`: `[tokenB, tokenA]` (buy), `[tokenA, tokenB]` (sell).
  - `to`: `recipientAddress`.
  - `deadline`: `block.timestamp + 300`.
- **Error Handling**: Try-catch in `transactNative`, `transactToken`, `approve`, `swap`, and `update` with decoded reasons (updated in `CCUniPartial.sol` v0.0.21).
- **Changes**:
  - `CCSettlementRouter.sol` (v0.0.9): Ensured graceful degradation, removed `require(count > 0)`, added detailed return reasons.
  - `CCSettlementPartial.sol` (v0.0.24): Fixed `makerAddress` and `recipientAddress` in all `UpdateType` structs for `listingContract.update`, ensuring compatibility with `CCListingTemplate.sol` (v0.1.9).
  - `CCUniPartial.sol` (v0.0.21): Updated `_createBuyOrderUpdates` and `_createSellOrderUpdates` to set `makerAddress` and `recipient` for all updates, fixed price impact calculations using `IERC20.balanceOf`.
