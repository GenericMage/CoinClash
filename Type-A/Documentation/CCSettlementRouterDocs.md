# CCSettlementRouter Contract Documentation

## Overview
The `CCSettlementRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform using Uniswap V2 for order execution. It inherits functionality from `CCSettlementPartial`, which extends `CCUniPartial` and `CCMainPartial`, integrating with external interfaces (`ICCListing`, `IUniswapV2Pair`, `IUniswapV2Router02`, `IERC20`) for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract handles order settlement via `settleOrders`, with gas optimization through `step` and `maxIterations`, robust error handling, and decimal precision for tokens. It avoids reserved keywords, uses explicit casting, and ensures graceful degradation with try-catch returning decoded error reasons. Transfers to/from the listing call `listingContract.ccUpdate` after successful Uniswap V2 swaps, ensuring state consistency. Transfer taxes are handled using `amountInReceived` for buy/sell orders.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.1.10 (updated 2025-09-16)

**Inheritance Tree:** `CCSettlementRouter` → `CCSettlementPartial` → `CCUniPartial` → `CCMainPartial`

**Compatible Contracts:**
- `CCListingTemplate.sol` (v0.3.9)
- `CCMainPartial.sol` (v0.1.5)
- `CCUniPartial.sol` (v0.1.13)
- `CCSettlementPartial.sol` (v0.1.10)

### Changes
- **v0.1.10**: Updated to reflect `CCSettlementRouter.sol` v0.1.6 (updated `_updateOrder` to use `BuyOrderUpdate`/`SellOrderUpdate` structs directly in `ccUpdate`, updated `OrderContext` to hold `BuyOrderUpdate[]`/`SellOrderUpdate[]`, modified `settleOrders` to use live balances/prices via `volumeBalances` and `prices`), `CCSettlementPartial.sol` v0.1.10 (added `amountIn` to `PrepOrderUpdateResult`, fixing TypeError in `_prepBuyOrderUpdate` and `_prepSellOrderUpdate`), and `CCUniPartial.sol` v0.1.13 (fixed TypeError in `_finalizeTokenSwap`, `_executeBuyETHSwap`, `_finalizeSellTokenSwap`, and `_executeSellETHSwapInternal` by destructuring tuples from `getBuyOrderAmounts` and `getSellOrderAmounts` to access `filled`). Ensured `filled` uses `amountIn` (principal token: tokenB for buys, tokenA for sells) and `amountSent` uses `amountInReceived` (settlement token: tokenA for buys, tokenB for sells).
- **v0.1.9**: Updated to reflect `CCSettlementPartial.sol` v0.1.10 (added `amountIn` to `PrepOrderUpdateResult`, fixing TypeError in `_prepBuyOrderUpdate` and `_prepSellOrderUpdate`) and `CCUniPartial.sol` v0.1.13 (fixed TypeError in `_finalizeTokenSwap`, `_executeBuyETHSwap`, `_finalizeSellTokenSwap`, and `_executeSellETHSwapInternal` by destructuring tuples from `getBuyOrderAmounts` and `getSellOrderAmounts` to access `filled`). Ensured `filled` uses `amountIn` (principal token: tokenB for buys, tokenA for sells) and `amountSent` uses `amountInReceived` (settlement token: tokenA for buys, tokenB for sells).
- **v0.1.8**: Fixed `TypeError` in `settleOrders` by adding `isBuyOrder` to `_updateOrder` call and updating `ccUpdate` to use four arguments (`buyUpdates`, `sellUpdates`, `balanceUpdates`, `historicalUpdates`) per `CCListingTemplate.sol` v0.3.9. Fixed `TypeError` in `_processOrder` by replacing `context.updates` with `context.buyUpdates` or `context.sellUpdates`. Fixed `TypeError` in `_executeOrderSwap` (`CCSettlementPartial.sol`) and `_executeBuyETHSwap`, `_executeSellETHSwapInternal`, `_executeBuyTokenSwap`, `_executeSellTokenSwap` (`CCUniPartial.sol`) by updating return types to `BuyOrderUpdate[]` or `SellOrderUpdate[]`. Added `uint2str` to resolve `DeclarationError`. Updated comments to clarify order updates are prepared in `CCUniPartial.sol`, refined in `CCSettlementPartial.sol`, and applied in `CCSettlementRouter.sol` via `ccUpdate`.
- **v0.1.7**: Fixed `TypeError` in `_applyOrderUpdate` and `_updateOrder` by using `BuyOrderUpdate` and `SellOrderUpdate` structs directly in `ccUpdate`, removing encoding/decoding. Updated `OrderContext` and `OrderProcessContext` to hold `BuyOrderUpdate[]` or `SellOrderUpdate[]`. Updated compatibility to `CCListingTemplate.sol` v0.3.8.
- **v0.1.6**: Modified `settleOrders` to fetch live balances, price, and current historical volumes instead of using latest historical data entry for new historical data creation. Uses `volumeBalances` and `prices` functions from `listingContract` for live data.
- **v0.1.5**: Updated to reflect `CCSettlementRouter.sol` v0.1.2, where `settleOrders` handles `HistoricalData` struct from `getHistoricalDataView`. Assigned struct to a variable and accessed fields explicitly for `ccUpdate`. Ensured compatibility with `CCListingTemplate.sol` v0.3.6, `CCMainPartial.sol` v0.1.5, `CCUniPartial.sol` v0.1.5, `CCSettlementPartial.sol` v0.1.3.
- **v0.1.4**: Updated to reflect `CCSettlementPartial.sol` v0.1.4, where `_processBuyOrder` and `_processSellOrder` were refactored to resolve stack-too-deep errors. Split into helper functions (`_validateOrderParams`, `_computeSwapAmount`, `_executeOrderSwap`, `_prepareUpdateData`, `_applyOrderUpdate`) using `OrderProcessContext` struct, each handling at most 4 variables. Corrected `_computeSwapAmount` to `internal` due to event emissions (`NonCriticalNoPendingOrder`, `NonCriticalPriceOutOfBounds`, `NonCriticalZeroSwapAmount`). Compatible with `CCListingTemplate.sol` v0.2.26, `CCMainPartial.sol` v0.1.1, `CCUniPartial.sol` v0.1.5.
- **v0.1.3**: Added events `NonCriticalPriceOutOfBounds`, `NonCriticalNoPendingOrder`, `NonCriticalZeroSwapAmount` to log non-critical issues. Emitted in `_processBuyOrder` and `_processSellOrder` for price out of bounds, no pending orders, and zero swap amount cases to ensure non-reverting behavior with logging.
- **v0.1.2**: Updated to reflect `CCSettlementRouter.sol` v0.1.0 (refactored `settleOrders` with `OrderContext`), `CCSettlementPartial.sol` v0.1.2 (added `_computeMaxAmountIn`, uses `ccUpdate`), and `CCUniPartial.sol` v0.1.5 (fixed `TypeError` for `BuyOrderUpdateContext`/`SellOrderUpdateContext` with `amountIn`). Corrected `listingContract.update` to `ccUpdate`.
- **v0.0.13**: Refactored `settleOrders` into `_validateOrder`, `_processOrder`, `_updateOrder` with `OrderContext` to resolve stack-too-deep error.
- **v0.0.12**: Removed `this.` from `_processBuyOrder` and `_processSellOrder` calls.
- **v0.0.11**: Enhanced error logging for token transfers, Uniswap swaps, and approvals.

## Mappings
- None defined directly in `CCSettlementRouter` or `CCSettlementPartial`. Relies on `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`) for order tracking.

## Structs
- **OrderContext** (`CCSettlementRouter`): Contains `orderId` (uint256), `pending` (uint256), `status` (uint8), `buyUpdates` (ICCListing.BuyOrderUpdate[]), `sellUpdates` (ICCListing.SellOrderUpdate[]).
- **OrderProcessContext** (`CCSettlementPartial`): Contains `orderId` (uint256), `pendingAmount` (uint256), `filled` (uint256), `amountSent` (uint256), `makerAddress` (address), `recipientAddress` (address), `status` (uint8), `maxPrice` (uint256), `minPrice` (uint256), `currentPrice` (uint256), `maxAmountIn` (uint256), `swapAmount` (uint256), `buyUpdates` (ICCListing.BuyOrderUpdate[]), `sellUpdates` (ICCListing.SellOrderUpdate[]).
- **PrepOrderUpdateResult** (`CCSettlementPartial`): Contains `tokenAddress` (address), `tokenDecimals` (uint8), `makerAddress` (address), `recipientAddress` (address), `orderStatus` (uint8), `amountReceived` (uint256), `normalizedReceived` (uint256), `amountSent` (uint256), `amountIn` (uint256).
- **MaxAmountInContext**, **SwapContext**, **SwapImpactContext**, **BuyOrderUpdateContext**, **SellOrderUpdateContext**, **TokenSwapData**, **ETHSwapData**, **ReserveContext**, **ImpactContext** (`CCUniPartial`): Used for swap execution and update preparation.
- **SwapContext** (`CCUniPartial`): Contains `listingContract` (ICCListing), `makerAddress` (address), `recipientAddress` (address), `status` (uint8), `tokenIn` (address), `tokenOut` (address), `decimalsIn` (uint8), `decimalsOut` (uint8), `denormAmountIn` (uint256), `denormAmountOutMin` (uint256), `price` (uint256), `expectedAmountOut` (uint256).
- **SwapImpactContext** (`CCUniPartial`): Contains `reserveIn` (uint256), `reserveOut` (uint256), `decimalsIn` (uint8), `decimalsOut` (uint8), `normalizedReserveIn` (uint256), `normalizedReserveOut` (uint256), `amountInAfterFee` (uint256), `price` (uint256), `amountOut` (uint256).
- **BuyOrderUpdateContext** (`CCUniPartial`): Contains `makerAddress` (address), `recipient` (address), `status` (uint8), `amountReceived` (uint256, post-transfer tokenA), `normalizedReceived` (uint256), `amountSent` (uint256, post-transfer tokenA), `amountIn` (uint256, pre-transfer tokenB).
- **SellOrderUpdateContext** (`CCUniPartial`): Contains `makerAddress` (address), `recipient` (address), `status` (uint8), `amountReceived` (uint256, post-transfer tokenB), `normalizedReceived` (uint256), `amountSent` (uint256, post-transfer tokenB), `amountIn` (uint256, pre-transfer tokenA).

## External Functions and Call Trees
- **settleOrders(address listingAddress, uint256 step, uint256 maxIterations, bool isBuyOrder)** (`CCSettlementRouter`):
  - **Description**: Processes pending buy or sell orders from `listingAddress` using `pendingBuyOrdersView` or `pendingSellOrdersView`, starting at `step`, up to `maxIterations`. Creates a new `HistoricalUpdate` entry via `ccUpdate` if pending orders exist, using live data from `volumeBalances` and `prices`. Iterates over orders, calling `_validateOrder`, `_processOrder`, and `_updateOrder`.
  - **Call Tree**:
    - Calls `listingContract.pendingBuyOrdersView()` or `pendingSellOrdersView()` to fetch order IDs.
    - Calls `_validateOrder(listingAddress, orderId, isBuyOrder, listingContract)` for each order.
    - Calls `_processOrder(listingAddress, isBuyOrder, listingContract, context)` to process orders.
    - Calls `_updateOrder(listingContract, context, isBuyOrder)` to apply updates via `ccUpdate`.
    - Calls `listingContract.ccUpdate([], [], [], historicalUpdates)` for historical data.
  - **Internal Calls**:
    - `_validateOrder`: Validates order parameters, sets `pending` to 0 if invalid.
    - `_processOrder`: Delegates to `_processBuyOrder` or `_processSellOrder`.
    - `_updateOrder`: Applies `buyUpdates` or `sellUpdates` via `ccUpdate`.
- **_processOrder(address listingAddress, bool isBuyOrder, ICCListing listingContract, OrderContext memory context)** (`CCSettlementRouter`):
  - **Description**: Processes a single order by calling `_processBuyOrder` or `_processSellOrder` and returns updated context with `buyUpdates` or `sellUpdates`.
  - **Call Tree**:
    - Calls `_processBuyOrder(listingAddress, context.orderId, listingContract)` or `_processSellOrder(listingAddress, context.orderId, listingContract)`.
    - Assigns `buyUpdates` or `sellUpdates` to `context`.
  - **Internal Calls**:
    - `_processBuyOrder`/`_processSellOrder`: Handles swap execution and update preparation.
- **_updateOrder(ICCListing listingContract, OrderContext memory context, bool isBuyOrder)** (`CCSettlementRouter`):
  - **Description**: Applies order updates via `listingContract.ccUpdate(buyUpdates, sellUpdates, [], [])`, returns success and reason.
  - **Call Tree**:
    - Calls `listingContract.ccUpdate` with `buyUpdates` or `sellUpdates` based on `isBuyOrder`.
  - **Internal Calls**: None direct; relies on `ccUpdate` implementation in `CCListingTemplate.sol`.
- **_validateOrder(address listingAddress, uint256 orderId, bool isBuyOrder, ICCListing listingContract)** (`CCSettlementRouter`): Validates order status and pricing, returns `OrderContext`.

## Internal Functions
- **_processBuyOrder(address listingAddress, uint256 orderIdentifier, ICCListing listingContract) → ICCListing.BuyOrderUpdate[] memory buyUpdates** (`CCSettlementPartial`):
  - Validates parameters, computes swap amount, executes swap, prepares and applies updates.
  - Calls: `_validateOrderParams`, `_computeSwapAmount`, `_executeOrderSwap`, `_prepareUpdateData`, `_applyOrderUpdate`.
- **_processSellOrder(address listingAddress, uint256 orderIdentifier, ICCListing listingContract) → ICCListing.SellOrderUpdate[] memory sellUpdates** (`CCSettlementPartial`):
  - Similar to `_processBuyOrder` for sell orders.
  - Calls: `_validateOrderParams`, `_computeSwapAmount`, `_executeOrderSwap`, `_prepareUpdateData`, `_applyOrderUpdate`.
- **_validateOrderParams(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, ICCListing listingContract) → OrderProcessContext memory context** (`CCSettlementPartial`): Fetches and validates order data.
- **_computeSwapAmount(address listingAddress, bool isBuyOrder, OrderProcessContext memory context) → OrderProcessContext memory** (`CCSettlementPartial`): Computes `swapAmount` within price and reserve constraints.
- **_executeOrderSwap(address listingAddress, bool isBuyOrder, OrderProcessContext memory context) → OrderProcessContext memory** (`CCSettlementPartial`): Executes Uniswap V2 swap via `_executePartialBuySwap` or `_executePartialSellSwap`.
- **_prepareUpdateData(OrderProcessContext memory context, bool isBuyOrder) → (ICCListing.BuyOrderUpdate[] memory buyUpdates, ICCListing.SellOrderUpdate[] memory sellUpdates)** (`CCSettlementPartial`): Prepares update structs.
- **_applyOrderUpdate(address listingAddress, ICCListing listingContract, OrderProcessContext memory context, bool isBuyOrder) → (ICCListing.BuyOrderUpdate[] memory buyUpdates, ICCListing.SellOrderUpdate[] memory sellUpdates)** (`CCSettlementPartial`): Applies updates via `ccUpdate`.
- **_createBuyOrderUpdates(uint256 orderIdentifier, BuyOrderUpdateContext memory updateContext, uint256 pendingAmount, uint256 filled) → ICCListing.BuyOrderUpdate[] memory** (`CCUniPartial`): Creates buy order updates, sets `filled` to `amountIn` (tokenB), `amountSent` to `amountInReceived` (tokenA).
- **_createSellOrderUpdates(uint256 orderIdentifier, SellOrderUpdateContext memory updateContext, uint256 pendingAmount, uint256 filled) → ICCListing.SellOrderUpdate[] memory** (`CCUniPartial`): Creates sell order updates, sets `filled` to `amountIn` (tokenA), `amountSent` to `amountInReceived` (tokenB).
- **_executeBuyTokenSwap**, **_executeSellTokenSwap**, **_executeBuyETHSwap**, **_executeSellETHSwapInternal**, **_finalizeTokenSwap**, **_finalizeSellTokenSwap**, **_executePartialBuySwap**, **_executePartialSellSwap**, **_computeCurrentPrice**, **_computeSwapImpact**, **_fetchReserves**, **_prepareSwapData**, **_prepareSellSwapData**, **_prepareTokenSwap**, **_executeTokenSwap**, **_performETHBuySwap**, **_performETHSellSwap** (`CCUniPartial`): Handle swap execution and update preparation.

## Key Calculations
- **Maximum Input Amount** (`_computeMaxAmountIn` in `CCSettlementPartial.sol`):
  - **Formulas**:
    - Buy: `priceAdjustedAmount = (pendingAmount * currentPrice) / 1e18`
    - Sell: `priceAdjustedAmount = (pendingAmount * 1e18) / currentPrice`
    - `maxAmountIn = min(priceAdjustedAmount, pendingAmount, normalizedReserveIn)`
  - **Description**: Computes `maxAmountIn` (tokenB for buys, tokenA for sells) within price constraints using `_fetchReserves`. Caps at `pendingAmount` and `normalizedReserveIn`.
  - **Example**: Buy order with `currentPrice = 5000e18`, `pendingAmount = 2000e18`, `reserveIn = 10000e6` (tokenB, 6 decimals):
    - `normalizedReserveIn = normalize(10000e6, 6) = 10000e18`
    - `priceAdjustedAmount = (2000e18 * 5000e18) / 1e18 = 10000e18`
    - `maxAmountIn = min(10000e18, 2000e18, 10000e18) = 2000e18`.
- **Minimum Output** (`_prepareSwapData`/`_prepareSellSwapData` in `CCUniPartial.sol`):
  - **Formulas**:
    - Buy: `denormAmountOutMin = expectedAmountOut`
    - Sell: `denormAmountOutMin = expectedAmountOut`
  - **Description**: Computes `denormAmountOutMin` (tokenA for buys, tokenB for sells) for Uniswap V2 swaps, derived from `_computeSwapImpact`.
  - **Example**: Buy order with `expectedAmountOut = 452.73e18` (tokenA):
    - `denormAmountOutMin = 452.73e18`.

## Limitations and Assumptions
- **No Order Creation/Cancellation**: Handled by `CCOrderRouter`.
- **No Payouts or Liquidity Settlement**: Handled by `CCCLiquidityRouter` or `CCLiquidRouter`.
- **Uniswap V2 Dependency**: Requires valid `uniswapV2Router` and `uniswapV2PairView`.
- **Zero-Amount Handling**: Returns empty `BuyOrderUpdate[]` or `SellOrderUpdate[]` for zero pending amounts or failed swaps.
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
- **Historical Data**: Creates a new `HistoricalUpdate` entry at the start of `settleOrders` if pending orders exist, applying the latest data for `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume` with a new `timestamp` via `ccUpdate`.

## Additional Details
- **Reentrancy Protection**: `nonReentrant` on `settleOrders`.
- **Gas Optimization**: Uses `step`, `maxIterations`, and dynamic arrays. `settleOrders` refactored with `OrderContext` (v0.0.13). `_processBuyOrder`/`_processSellOrder` refactored with `OrderProcessContext` (v0.1.4).
- **Listing Validation**: `onlyValidListing` checks `ICCAgent.isValidListing`.
- **Uniswap V2 Parameters**:
  - `amountIn`: `denormAmountIn` (pre-transfer, tax-adjusted via `amountInReceived`).
  - `amountOutMin`: `denormAmountOutMin` from `_computeSwapImpact`.
  - `path`: `[tokenB, tokenA]` (buy), `[tokenA, tokenB]` (sell).
  - `to`: `recipientAddress`.
  - `deadline`: `block.timestamp + 15 minutes`.
- **Error Handling**: Try-catch in `transactNative`, `transactToken`, `approve`, `swap`, and `ccUpdate` with decoded reasons (v0.1.5).
- **Status Handling**: If `updateContext.status == 1` (active) and `updateContext.amountIn >= pendingAmount`, status is set to `3` (fully settled). Otherwise, status is set to `2` (partially settled). Partially settled orders may also be set to fully settled.
- **ccUpdate Call Locations**:
  - **CCSettlementRouter.sol**: Handles all `ccUpdate` calls to `CCListingTemplate.sol`. The `_updateOrder` function applies order updates (`buyUpdates` or `sellUpdates`) for buy or sell orders. The `settleOrders` function applies historical data updates (`historicalUpdates`) at the start of order processing. Updates are prepared in `CCUniPartial.sol` (via `_createBuyOrderUpdates`/`_createSellOrderUpdates`), refined in `CCSettlementPartial.sol` (via `_prepareUpdateData`/`_applyOrderUpdate`), and applied only in `CCSettlementRouter.sol`.
  - **No Duplicate Calls**: The call tree ensures `ccUpdate` is invoked once per order in `_updateOrder` (via `_processOrder` → `_processBuyOrder`/`_processSellOrder` → `_applyOrderUpdate`) and once for historical data in `settleOrders`. No redundant calls occur, as `_applyOrderUpdate` is part of the `_processOrder` flow, not an independent trigger.
