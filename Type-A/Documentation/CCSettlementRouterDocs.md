# CCSettlementRouter Contract Documentation

## Overview
The `CCSettlementRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform using Uniswap V2 for order execution. It inherits functionality from `CCSettlementPartial`, which extends `CCUniPartial` and `CCMainPartial`, integrating with external interfaces (`ICCListing`, `IUniswapV2Pair`, `IUniswapV2Router02`, `IERC20`) for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract handles order settlement via `settleOrders`, with gas optimization through `step` and `maxIterations`, robust error handling, and decimal precision for tokens. It avoids reserved keywords, uses explicit casting, and ensures graceful degradation with try-catch returning decoded error reasons. Transfers to/from the listing call `listingContract.ccUpdate` after successful Uniswap V2 swaps, ensuring state consistency. Transfer taxes are handled using `amountInReceived` for buy/sell orders.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.1.2 (updated 2025-08-30)

**Inheritance Tree:** `CCSettlementRouter` → `CCSettlementPartial` → `CCUniPartial` → `CCMainPartial`

**Compatible Contracts:**
- `CCListingTemplate.sol` (v0.2.26)
- `CCMainPartial.sol` (v0.0.15)
- `CCUniPartial.sol` (v0.1.5)
- `CCSettlementPartial.sol` (v0.1.2)

## Changes
- **v0.1.2**: Updated to reflect `CCSettlementRouter.sol` v0.1.0 (refactored `settleOrders` with `OrderContext`), `CCSettlementPartial.sol` v0.1.2 (added `_computeMaxAmountIn`, uses `ccUpdate`), and `CCUniPartial.sol` v0.1.5 (fixed `TypeError` for `BuyOrderUpdateContext`/`SellOrderUpdateContext` with `amountIn`). Corrected `listingContract.update` to `ccUpdate`. Updated struct descriptions and call trees for `pending`/`filled` (pre-transfer: tokenB for buys, tokenA for sells) and `amountSent` (post-transfer: tokenA for buys, tokenB for sells).
- **v0.0.13**: Refactored `settleOrders` into `_validateOrder`, `_processOrder`, `_updateOrder` with `OrderContext` to resolve stack-too-deep error.
- **v0.0.12**: Removed `this.` from `_processBuyOrder` and `_processSellOrder` calls.
- **v0.0.11**: Enhanced error logging for token transfers, Uniswap swaps, and approvals.

## Mappings
- None defined directly in `CCSettlementRouter` or `CCSettlementPartial`. Relies on `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`) for order tracking.

## Structs
- **OrderContext** (`CCSettlementRouter`): Contains `orderId` (uint256), `pending` (uint256), `status` (uint8), `updates` (ICCListing.UpdateType[]).
- **PrepOrderUpdateResult** (`CCSettlementPartial`): Contains `tokenAddress` (address), `tokenDecimals` (uint8), `makerAddress` (address), `recipientAddress` (address), `orderStatus` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, denormalized).
- **MaxAmountInContext** (`CCUniPartial`): Contains `reserveIn` (uint256), `decimalsIn` (uint8), `normalizedReserveIn` (uint256), `currentPrice` (uint256).
- **SwapContext** (`CCUniPartial`): Contains `listingContract` (ICCListing), `makerAddress` (address), `recipientAddress` (address), `status` (uint8), `tokenIn` (address), `tokenOut` (address), `decimalsIn` (uint8), `decimalsOut` (uint8), `denormAmountIn` (uint256), `denormAmountOutMin` (uint256), `price` (uint256), `expectedAmountOut` (uint256).
- **SwapImpactContext** (`CCUniPartial`): Contains `reserveIn` (uint256), `reserveOut` (uint256), `decimalsIn` (uint8), `decimalsOut` (uint8), `normalizedReserveIn` (uint256), `normalizedReserveOut` (uint256), `amountInAfterFee` (uint256), `price` (uint256), `amountOut` (uint256).
- **BuyOrderUpdateContext** (`CCUniPartial`): Contains `makerAddress` (address), `recipient` (address), `status` (uint8), `amountReceived` (uint256, post-transfer tokenA), `normalizedReceived` (uint256), `amountSent` (uint256, post-transfer tokenA), `amountIn` (uint256, pre-transfer tokenB).
- **SellOrderUpdateContext** (`CCUniPartial`): Contains `makerAddress` (address), `recipient` (address), `status` (uint8), `amountReceived` (uint256, post-transfer tokenB), `normalizedReceived` (uint256), `amountSent` (uint256, post-transfer tokenB), `amountIn` (uint256, pre-transfer tokenA).
- **TokenSwapData** (`CCUniPartial`): Contains `preBalanceIn` (uint256), `postBalanceIn` (uint256), `amountInReceived` (uint256), `preBalanceOut` (uint256), `postBalanceOut` (uint256), `amountReceived` (uint256), `amountOut` (uint256).
- **ETHSwapData** (`CCUniPartial`): Contains `preBalanceIn` (uint256), `postBalanceIn` (uint256), `amountInReceived` (uint256), `preBalanceOut` (uint256), `postBalanceOut` (uint256), `amountReceived` (uint256), `amountOut` (uint256).
- **ReserveContext** (`CCUniPartial`): Contains `reserveIn` (uint256), `decimalsIn` (uint8), `normalizedReserveIn` (uint256), `tokenA` (address).
- **ImpactContext** (`CCUniPartial`): Contains `currentPrice` (uint256), `maxImpactPercent` (uint256), `maxAmountIn` (uint256), `pendingAmount` (uint256).

## External Functions and Call Trees
### `settleOrders(address listingAddress, uint256 step, uint256 maxIterations, bool isBuyOrder)`
- **Purpose**: Iterates over pending buy or sell orders, validates price impact, processes swaps via Uniswap V2, updates the listing state via `ccUpdate`, and returns a reason if no orders are settled.
- **Modifiers**: `nonReentrant`, `onlyValidListing(listingAddress)` (from `CCMainPartial`).
- **Parameters**:
  - `listingAddress`: Address of the `ICCListing` contract.
  - `step`: Starting index for order processing (e.g., if `pendingBuyOrdersView` returns `[10,11,22,23,24]` and `step = 3`, starts at orderId `23`).
  - `maxIterations`: Maximum number of orders to process for gas control.
  - `isBuyOrder`: True for buy orders (tokenB → tokenA), false for sell orders (tokenA → tokenB).
- **Call Tree**:
  - Calls `ICCListing.pendingBuyOrdersView` or `pendingSellOrdersView` to retrieve order IDs.
  - For each order (from `step` up to `maxIterations`):
    - Calls `_validateOrder` (checks `status == 1` and `pendingAmount > 0`).
    - Calls `_processOrder` → `_processBuyOrder` or `_processSellOrder` (from `CCSettlementPartial.sol`):
      - `_processBuyOrder`:
        - Calls `ICCListing.getBuyOrderCore` for `makerAddress`, `recipientAddress`, `status`.
        - Calls `ICCListing.getBuyOrderAmounts` for `pendingAmount`, `filled`, `amountSent`.
        - Calls `ICCListing.getBuyOrderPricing` for `maxPrice`, `minPrice`.
        - Calls `ICCListing.prices(0)` for `currentPrice`.
        - Calls `_computeMaxAmountIn` (computes `swapAmount` using `_fetchReserves`).
        - Calls `_executePartialBuySwap` (from `CCUniPartial.sol`):
          - Calls `_prepareSwapData` (sets `SwapContext` with `tokenIn = tokenB`, `tokenOut = tokenA`, `denormAmountIn`, `denormAmountOutMin`).
          - If `tokenIn = address(0)` (ETH buy), calls `_executeBuyETHSwap` → `_performETHBuySwap`.
          - Else, calls `_executeBuyTokenSwap` → `_prepareTokenSwap` → `_executeTokenSwap` → `_finalizeTokenSwap`.
          - `_finalizeTokenSwap` creates `BuyOrderUpdateContext` with `amountIn` (tokenB, pre-transfer), `amountSent` (tokenA, post-transfer).
          - Returns `ICCListing.UpdateType[]` via `_createBuyOrderUpdates`.
        - Calls `ICCListing.ccUpdate` with `updateType`, `updateSort`, `updateData`.
      - `_processSellOrder`: Similar, using `getSellOrderCore`, `getSellOrderAmounts`, `getSellOrderPricing`, `_executePartialSellSwap` → `_executeSellTokenSwap` or `_executeSellETHSwapInternal` → `_finalizeSellTokenSwap` → `_createSellOrderUpdates`.
    - Calls `_updateOrder` (calls `ccUpdate`, checks status).
  - **Returns**: String reason if no orders settled (e.g., "No pending orders", "Price out of range").
- **Internal Functions Called**:
  - `_validateOrder`: Validates order status and pending amount.
  - `_processOrder`: Dispatches to `_processBuyOrder` or `_processSellOrder`.
  - `_updateOrder`: Calls `ccUpdate` with try-catch, returns success or reason.
  - `_processBuyOrder`, `_processSellOrder`: Fetch order data, compute `swapAmount`, execute swaps, call `ccUpdate`.
  - `_prepBuyOrderUpdate`, `_prepSellOrderUpdate`: Handle token transfers with pre/post balance checks.
  - `_getTokenAndDecimals`, `_checkPricing`, `_computeAmountSent`, `_computeMaxAmountIn`: Support pricing and transfer logic.
  - From `CCUniPartial.sol`: `_computeCurrentPrice`, `_computeSwapImpact`, `_fetchReserves`, `_prepareSwapData`, `_prepareSellSwapData`, `_prepareTokenSwap`, `_executeTokenSwap`, `_performETHBuySwap`, `_performETHSellSwap`, `_finalizeTokenSwap`, `_finalizeSellTokenSwap`, `_executeBuyETHSwap`, `_executeSellETHSwapInternal`, `_executeBuyTokenSwap`, `_executeSellTokenSwap`, `_executePartialBuySwap`, `_executePartialSellSwap`, `_createBuyOrderUpdates`, `_createSellOrderUpdates`.

### `setUniswapV2Router(address _uniswapV2Router)`
- **Purpose**: Sets the Uniswap V2 router address post-deployment.
- **Modifiers**: `onlyOwner` (from `Ownable`).
- **Parameters**: `_uniswapV2Router` (address of the Uniswap V2 router).
- **Call Tree**:
  - Updates `uniswapV2Router` state variable.
  - No internal calls.
- **Internal Functions Affected**:
  - `_executeTokenSwap`, `_performETHBuySwap`, `_performETHSellSwap`: Use `uniswapV2Router` for swaps.
  - Indirectly affects `_executeBuyTokenSwap`, `_executeSellTokenSwap`, `_executeBuyETHSwap`, `_executeSellETHSwapInternal`, `_finalizeTokenSwap`, `_finalizeSellTokenSwap`, `_executePartialBuySwap`, `_executePartialSellSwap`.

## Internal Functions (Relative to External Calls)
- **_validateOrder** (`CCSettlementRouter`): Called by `settleOrders` to validate order status and pending amount.
- **_processOrder** (`CCSettlementRouter`): Called by `settleOrders`, dispatches to `_processBuyOrder` or `_processSellOrder`.
- **_updateOrder** (`CCSettlementRouter`): Called by `settleOrders`, handles `ccUpdate` with error handling.
- **_processBuyOrder**, **_processSellOrder** (`CCSettlementPartial`): Called by `settleOrders` via `_processOrder`. Fetch order data, compute `swapAmount`, execute swaps, call `ccUpdate`.
- **_prepBuyOrderUpdate**, **_prepSellOrderUpdate** (`CCSettlementPartial`): Called by `_processBuyOrder`/`_processSellOrder` for token transfers.
- **_getTokenAndDecimals** (`CCSettlementPartial`): Called by `_prepBuyOrderUpdate`/`_prepSellOrderUpdate`.
- **_checkPricing** (`CCSettlementPartial`): Called by `_processBuyOrder`/`_processSellOrder`.
- **_computeAmountSent** (`CCSettlementPartial`): Called by `_prepBuyOrderUpdate`/`_prepSellOrderUpdate`.
- **_computeMaxAmountIn** (`CCSettlementPartial`): Called by `_processBuyOrder`/`_processSellOrder`, uses `_fetchReserves`.
- **_computeCurrentPrice**, **_computeSwapImpact**, **_fetchReserves**, **_prepareSwapData**, **_prepareSellSwapData**, **_prepareTokenSwap**, **_executeTokenSwap**, **_performETHBuySwap**, **_performETHSellSwap**, **_finalizeTokenSwap**, **_finalizeSellTokenSwap**, **_executeBuyETHSwap**, **_executeSellETHSwapInternal**, **_executeBuyTokenSwap**, **_executeSellTokenSwap**, **_executePartialBuySwap**, **_executePartialSellSwap**, **_createBuyOrderUpdates**, **_createSellOrderUpdates** (`CCUniPartial`): Called by `_processBuyOrder`/`_processSellOrder` via `_executePartialBuySwap`/`_executePartialSellSwap`.

## Key Calculations
- **Maximum Input Amount** (`_computeMaxAmountIn` in `CCSettlementPartial.sol`):
  - **Formulas**:
    - Buy: `maxImpactPercent = (maxPrice * 100e18 / currentPrice - 100e18) / 1e18`
    - Sell: `maxImpactPercent = (currentPrice * 100e18 / minPrice - 100e18) / 1e18`
    - `maxAmountIn = min((normalizedReserveIn * maxImpactPercent) / (100 * 2), pendingAmount)`
  - **Description**: Computes `maxAmountIn` (tokenB for buys, tokenA for sells) within price impact limits using `_fetchReserves`. Caps at `pendingAmount`.
  - **Example**: Buy order with `maxPrice = 5500e18`, `currentPrice = 5000e18`, `pendingAmount = 2000e18`, `reserveIn = 10000e6` (tokenB, 6 decimals):
    - `normalizedReserveIn = normalize(10000e6, 6) = 10000e18`
    - `maxImpactPercent = (5500e18 * 100e18 / 5000e18 - 100e18) / 1e18 = 10`
    - `maxAmountIn = (10000e18 * 10) / (100 * 2) = 500e18`
    - `maxAmountIn = min(500e18, 2000e18) = 500e18`.
- **Minimum Output** (`_prepareSwapData`/`_prepareSellSwapData` in `CCUniPartial.sol`):
  - **Formulas**:
    - Buy: `denormAmountOutMin = (expectedAmountOut * 1e18) / maxPrice`
    - Sell: `denormAmountOutMin = (expectedAmountOut * minPrice) / 1e18`
  - **Description**: Computes `denormAmountOutMin` (tokenA for buys, tokenB for sells) for Uniswap V2 swaps, ensuring price constraints.
  - **Example**: Buy order with `expectedAmountOut = 452.73e18` (tokenA), `maxPrice = 5500e18`:
    - `denormAmountOutMin = (452.73e18 * 1e18) / 5500e18 ≈ 82.31e18`.

## Limitations and Assumptions
- **No Order Creation/Cancellation**: Handled by `CCOrderRouter`.
- **No Payouts or Liquidity Settlement**: Handled by `CCCLiquidityRouter` or `CCLiquidRouter`.
- **Uniswap V2 Dependency**: Requires valid `uniswapV2Router` and `uniswapV2PairView`.
- **Zero-Amount Handling**: Returns empty `ICCListing.UpdateType[]` for zero pending amounts or failed swaps.
- **Decimal Handling**: Uses `normalize`/`denormalize` for 18-decimal precision, assumes `IERC20.decimals` or 18 for ETH.
- **Token Flow**:
  - Buy: `transactToken(tokenB)` or `transactNative` → `swapExactTokensForTokens` or `swapExactETHForTokens` → `amountReceived` (tokenA).
  - Sell: `transactToken(tokenA)` → `swapExactTokensForTokens` or `swapExactTokensForETH` → `amountReceived` (tokenB or ETH).
- **Price Impact**:
  - Uses `IERC20.balanceOf(listingAddress)` for `tokenA` and `tokenB` in `_computeSwapImpact` (v0.1.5).
  - Buy: Increases price (via `listingContract.prices(0)`).
  - Sell: Decreases price (via `listingContract.prices(0)`).
- **Pending/Filled**: Uses `amountIn` (pre-transfer: tokenB for buys, tokenA for sells) for `pending` and `filled`, accumulating `filled`.
- **AmountSent**: Uses `amountInReceived` (post-transfer: tokenA for buys, tokenB for sells) with pre/post balance checks.

## Additional Details
- **Reentrancy Protection**: `nonReentrant` on `settleOrders`.
- **Gas Optimization**: Uses `step`, `maxIterations`, and dynamic arrays. `settleOrders` refactored with `OrderContext` (v0.0.13).
- **Listing Validation**: `onlyValidListing` checks `ICCAgent.isValidListing`.
- **Uniswap V2 Parameters**:
  - `amountIn`: `denormAmountIn` (pre-transfer, tax-adjusted via `amountInReceived`).
  - `amountOutMin`: `denormAmountOutMin` from `(expectedAmountOut * 1e18) / maxPrice` (buy) or `(expectedAmountOut * minPrice) / 1e18` (sell).
  - `path`: `[tokenB, tokenA]` (buy), `[tokenA, tokenB]` (sell).
  - `to`: `recipientAddress`.
  - `deadline`: `block.timestamp + 15 minutes`.
- **Error Handling**: Try-catch in `transactNative`, `transactToken`, `approve`, `swap`, and `ccUpdate` with decoded reasons (v0.1.5).
