# CCSettlementRouter Contract Documentation

## Overview
The `CCSettlementRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform using Uniswap V2 for order execution. It inherits functionality from `CCSettlementPartial`, which extends `CCUniPartial` and `CCMainPartial`, integrating with external interfaces (`ICCListing`, `IUniswapV2Pair`, `IUniswapV2Router02`, `IERC20`) for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract handles order settlement via `settleOrders`, with gas optimization through `step` and `maxIterations`, robust error handling, and decimal precision for tokens. It avoids reserved keywords, uses explicit casting, and ensures graceful degradation with try-catch returning decoded error reasons. Transfers to/from the listing call `listingContract.ccUpdate` after successful Uniswap V2 swaps, ensuring state consistency. Transfer taxes are handled using `amountInReceived` for buy/sell orders.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.1.11 (updated 2025-09-16)

**Inheritance Tree:** `CCSettlementRouter` → `CCSettlementPartial` → `CCUniPartial` → `CCMainPartial`

**Compatible Contracts:**
- `CCListingTemplate.sol` (v0.3.9)
- `CCMainPartial.sol` (v0.1.5)
- `CCUniPartial.sol` (v0.1.12)
- `CCSettlementPartial.sol` (v0.1.11)

### Changes
- **v0.1.11**: Updated to reflect `CCSettlementPartial.sol` v0.1.11 (removed `ccUpdate` from `_applyOrderUpdate`, made it pure, ensuring single `ccUpdate` in `CCSettlementRouter.sol`'s `_updateOrder`, fixing redundant updates to `pending`, `filled`, `amountSent`). Compatible with `CCSettlementRouter.sol` v0.1.6, `CCUniPartial.sol` v0.1.12, `CCListingTemplate.sol` v0.3.9.
- **v0.1.10**: Updated to reflect `CCSettlementRouter.sol` v0.1.6 (updated `_updateOrder` to use `BuyOrderUpdate`/`SellOrderUpdate` structs directly in `ccUpdate`, updated `OrderContext` to hold `BuyOrderUpdate[]`/`SellOrderUpdate[]`, modified `settleOrders` to use live balances/prices via `volumeBalances` and `prices`), `CCSettlementPartial.sol` v0.1.10 (added `amountIn` to `PrepOrderUpdateResult`, fixing TypeError in `_prepBuyOrderUpdate` and `_prepSellOrderUpdate`), and `CCUniPartial.sol` v0.1.13 (fixed TypeError in `_finalizeTokenSwap`, `_executeBuyETHSwap`, `_finalizeSellTokenSwap`, and `_executeSellETHSwapInternal` by destructuring tuples from `getBuyOrderAmounts` and `getSellOrderAmounts` to access `filled`). Ensured `filled` uses `amountIn` (principal token: tokenB for buys, tokenA for sells) and `amountSent` uses `amountInReceived` (settlement token: tokenA for buys, tokenB for sells).
- **v0.1.9**: Updated to reflect `CCSettlementPartial.sol` v0.1.10 and `CCUniPartial.sol` v0.1.13. Ensured `filled` uses `amountIn` and `amountSent` uses `amountInReceived`.
- **v0.1.8**: Fixed `TypeError` in `settleOrders` by adding `isBuyOrder` to `_updateOrder` call and updating `ccUpdate` to use four arguments (`buyUpdates`, `sellUpdates`, `balanceUpdates`, `historicalUpdates`) per `CCListingTemplate.sol` v0.3.9. Fixed `TypeError` in `_processOrder` by replacing `context.updates` with `context.buyUpdates` or `context.sellUpdates`. Fixed `TypeError` in `_executeOrderSwap`, `_executeBuyETHSwap`, `_executeSellETHSwapInternal`, `_executeBuyTokenSwap`, `_executeSellTokenSwap` by updating return types to `BuyOrderUpdate[]` or `SellOrderUpdate[]`. Added `uint2str` to resolve `DeclarationError`. Updated comments to clarify order updates are prepared in `CCUniPartial.sol`, refined in `CCSettlementPartial.sol`, and applied in `CCSettlementRouter.sol` via `ccUpdate`.
- **v0.1.7**: Fixed `TypeError` in `_applyOrderUpdate` and `_updateOrder` by using `BuyOrderUpdate` and `SellOrderUpdate` structs directly in `ccUpdate`, removing encoding/decoding. Updated `OrderContext` and `OrderProcessContext` to hold `BuyOrderUpdate[]` or `SellOrderUpdate[]`. Updated compatibility to `CCListingTemplate.sol` v0.3.8.
- **v0.1.6**: Modified `settleOrders` to fetch live balances, price, and current historical volumes instead of using latest historical data entry for new historical data creation. Uses `volumeBalances` and `prices` functions from `listingContract` for live data.
- **v0.1.5**: Updated to reflect `CCSettlementRouter.sol` v0.1.2, where `settleOrders` handles `HistoricalData` struct from `getHistoricalDataView`. Assigned struct to a variable and accessed fields explicitly for `ccUpdate`. Ensured compatibility with `CCListingTemplate.sol` v0.3.6, `CCMainPartial.sol` v0.1.5, `CCUniPartial.sol` v0.1.5, `CCSettlementPartial.sol` v0.1.3.
- **v0.1.4**: Updated to reflect `CCSettlementPartial.sol` v0.1.4, where `_processBuyOrder` and `_processSellOrder` were refactored to resolve stack-too-deep errors. Split into helper functions (`_validateOrderParams`, `_computeSwapAmount`, `_executeOrderSwap`, `_prepareUpdateData`, `_applyOrderUpdate`) using `OrderProcessContext` struct, each handling at most 4 variables. Corrected `_computeSwapAmount` to `internal` due to event emissions. Compatible with `CCListingTemplate.sol` v0.2.26, `CCMainPartial.sol` v0.1.1, `CCUniPartial.sol` v0.1.5.
- **v0.1.3**: Added events `NonCriticalPriceOutOfBounds`, `NonCriticalNoPendingOrder`, `NonCriticalZeroSwapAmount` to log non-critical issues in `_processBuyOrder` and `_processSellOrder`.
- **v0.1.2**: Updated to reflect `CCSettlementRouter.sol` v0.1.0, `CCSettlementPartial.sol` v0.1.2, and `CCUniPartial.sol` v0.1.5. Corrected `listingContract.update` to `ccUpdate`.
- **v0.0.13**: Refactored `settleOrders` into `_validateOrder`, `_processOrder`, `_updateOrder` with `OrderContext`.
- **v0.0.12**: Removed `this.` from `_processBuyOrder` and `_processSellOrder` calls.
- **v0.0.11**: Enhanced error logging for token transfers, Uniswap swaps, and approvals.

## Mappings
- None defined directly in `CCSettlementRouter` or `CCSettlementPartial`. Relies on `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`) for order tracking.

## Structs
- **OrderContext** (`CCSettlementRouter`): Contains `orderId` (uint256), `pending` (uint256), `status` (uint8), `buyUpdates` (ICCListing.BuyOrderUpdate[]), `sellUpdates` (ICCListing.SellOrderUpdate[]).
- **OrderProcessContext** (`CCSettlementPartial`): Contains `orderId` (uint256), `pendingAmount` (uint256), `filled` (uint256), `amountSent` (uint256), `makerAddress` (address), `recipientAddress` (address), `status` (uint8), `maxPrice` (uint256), `minPrice` (uint256), `currentPrice` (uint256), `maxAmountIn` (uint256), `swapAmount` (uint256), `buyUpdates` (ICCListing.BuyOrderUpdate[]), `sellUpdates` (ICCListing.SellOrderUpdate[]).
- **PrepOrderUpdateResult** (`CCSettlementPartial`): Contains `tokenAddress` (address), `tokenDecimals` (uint8), `makerAddress` (address), `recipientAddress` (address), `orderStatus` (uint8), `amountReceived` (uint256), `normalizedReceived` (uint256), `amountSent` (uint256), `amountIn` (uint256).

## External Functions
- **settleOrders(address listingAddress, uint256 step, uint256 maxIterations, bool isBuyOrder) → string memory reason** (`CCSettlementRouter`):
  - Iterates over pending orders (`pendingBuyOrdersView` or `pendingSellOrdersView`) from `step` up to `maxIterations`.
  - Validates orders via `_validateOrder`, processes via `_processOrder`, and applies updates via `_updateOrder`.
  - Creates a `HistoricalUpdate` at the start using live data (`volumeBalances`, `prices`, `historicalDataLengthView`, `getHistoricalDataView`) if orders exist.
  - Calls `ccUpdate` for historical data and order updates (prepared in `CCUniPartial.sol`, refined in `CCSettlementPartial.sol`).
  - Returns empty string on success or error reason (e.g., "No orders settled: price out of range, insufficient tokens, or swap failure").
  - **Internal Call Tree**:
    - `_validateOrder` → Fetches order data (`getBuyOrderAmounts`/`getSellOrderAmounts`, `getBuyOrderCore`/`getSellOrderCore`), checks pricing via `_checkPricing`.
    - `_processOrder` → Calls `_processBuyOrder` or `_processSellOrder` (from `CCSettlementPartial`).
    - `_updateOrder` → Applies `ccUpdate` with `buyUpdates` or `sellUpdates`.
  - **Modifiers**: `nonReentrant`, `onlyValidListing`.

## Internal Functions
- **_validateOrder(address listingAddress, uint256 orderId, bool isBuyOrder, ICCListing listingContract) → OrderContext memory context** (`CCSettlementRouter`): Fetches order data and validates pricing.
- **_processOrder(address listingAddress, bool isBuyOrder, ICCListing listingContract, OrderContext memory context) → OrderContext memory** (`CCSettlementRouter`): Calls `_processBuyOrder` or `_processSellOrder`.
- **_updateOrder(ICCListing listingContract, OrderContext memory context, bool isBuyOrder) → (bool success, string memory reason)** (`CCSettlementRouter`): Applies `ccUpdate` with `buyUpdates` or `sellUpdates`, returns success or error reason.
- **_processBuyOrder(address listingAddress, uint256 orderIdentifier, ICCListing listingContract) → ICCListing.BuyOrderUpdate[] memory buyUpdates** (`CCSettlementPartial`):
  - Orchestrates buy order processing via `_validateOrderParams`, `_computeSwapAmount`, `_executeOrderSwap`, `_prepareUpdateData`, `_applyOrderUpdate`.
  - Returns `buyUpdates` for `_updateOrder` in `CCSettlementRouter.sol`.
- **_processSellOrder(address listingAddress, uint256 orderIdentifier, ICCListing listingContract) → ICCListing.SellOrderUpdate[] memory sellUpdates** (`CCSettlementPartial`):
  - Similar to `_processBuyOrder` for sell orders.
- **_validateOrderParams(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, ICCListing listingContract) → OrderProcessContext memory context** (`CCSettlementPartial`): Fetches and validates order data.
- **_computeSwapAmount(address listingAddress, bool isBuyOrder, OrderProcessContext memory context) → OrderProcessContext memory** (`CCSettlementPartial`): Computes `swapAmount` within price and reserve constraints.
- **_executeOrderSwap(address listingAddress, bool isBuyOrder, OrderProcessContext memory context) → OrderProcessContext memory** (`CCSettlementPartial`): Executes Uniswap V2 swap via `_executePartialBuySwap` or `_executePartialSellSwap`.
- **_prepareUpdateData(OrderProcessContext memory context, bool isBuyOrder) → (ICCListing.BuyOrderUpdate[] memory buyUpdates, ICCListing.SellOrderUpdate[] memory sellUpdates)** (`CCSettlementPartial`): Prepares update structs.
- **_applyOrderUpdate(address listingAddress, ICCListing listingContract, OrderProcessContext memory context, bool isBuyOrder) → (ICCListing.BuyOrderUpdate[] memory buyUpdates, ICCListing.SellOrderUpdate[] memory sellUpdates)** (`CCSettlementPartial`): Prepares `buyUpdates` or `sellUpdates` (pure after v0.1.11).
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
- **Status Handling**: If `updateContext.status == 1` (active) and `updateContext.amountIn >= pendingAmount`, status is set to `3` (fully settled). Otherwise, status is set to `2` (partially settled).
- **ccUpdate Call Locations**:
  - **CCSettlementRouter.sol**: Handles all `ccUpdate` calls to `CCListingTemplate.sol`. The `_updateOrder` function applies order updates (`buyUpdates` or `sellUpdates`) for buy or sell orders. The `settleOrders` function applies historical data updates (`historicalUpdates`) at the start of order processing. Updates are prepared in `CCUniPartial.sol` (via `_createBuyOrderUpdates`/`_createSellOrderUpdates`), refined in `CCSettlementPartial.sol` (via `_prepareUpdateData`/`_applyOrderUpdate`, now pure), and applied only in `CCSettlementRouter.sol`.
  - **No Duplicate Calls**: After v0.1.11, `_applyOrderUpdate` is pure, and `ccUpdate` is called once per order in `_updateOrder` and once for historical data in `settleOrders`.
- **State Update (`CCListingTemplate.ccUpdate`)**
    - **Core (`structId = 0`)**: Updates `status`; immutable fields (`maker`, `recipient`) are rewritten with original values.
    - **Pricing (`structId = 1`)**: Immutable fields (`minPrice`/`maxPrice`) are rewritten with original values (a no-op for data, crucial for consistency).
    - **Amounts (`structId = 2`)**: Volatile fields (`pending`, `filled`, `amountSent`) are updated with new values from the swap.
- **Price Impact Protection:** `_computeMaxAmountIn` ensures estimated impact price respects the user's `maxPrice` (for buys) and `minPrice` (for sells).
- **Price Calculation:**
The system consistently uses `listingContract.prices(0)` to fetch the current price, it calculates price as `(balanceB * 1e18) / balanceA`. 
- **Partial Fills Behavior:**
Partial fills occur when the `swapAmount` is limited by `maxAmountIn`, calculated in `_computeMaxAmountIn` (CCSettlementPartial.sol) to respect price bounds and available reserves. For example, with a buy order of 100 tokenB pending, a pool of 1000 tokenA and 500 tokenB (price = 0.5 tokenA/tokenB), and price bounds (max 0.6, min 0.4), `maxAmountIn` is 50 tokenB due to price-adjusted constraints. This results in a swap of 50 tokenB for ~90.59 tokenA, updating `pending = 50`, `filled += 50`, `amountSent = 90.59` and `status = 2` (partially filled) via a single `ccUpdate` call in `_updateOrder` (CCSettlementRouter.sol). 
- **AmountSent Usage:**
`amountSent` tracks the actual tokens a recipient gets after a trade (e.g., tokenA for buy orders) in the `BuyOrderUpdate`/`SellOrderUpdate` structs.
  - **Calculation**: The system checks the recipient’s balance before and after a transfer to record `amountSent` (e.g., ~90.59 tokenA for 50 tokenB after fees).
  - **Partial Fills**: For partial trades (e.g., 50 of 100 tokenB), `amountSent` shows the tokens received each time. Is incremented for each partial fill. 
  - **Application**: Prepared in `CCUniPartial.sol` and applied via one `ccUpdate` call in `CCSettlementRouter.sol`, updating the order’s Amounts struct.
- **Maximum Input Amount:** 
(`maxAmountIn`) ensures that the size of the swap doesn't push the execution price outside the `minPrice`/`maxPrice` boundaries set in the order. This calculation happens in `_computeMaxAmountIn`.
  - **Calculate a Price-Adjusted Amount**: The system first calculates a theoretical maximum amount based on the current market price and the order's pending amount.
  - **Determine the True Maximum**: This is limited by;
    * The **`priceAdjustedAmount`**.
    * The order's actual **`pendingAmount`**.
    * The **`normalizedReserveIn`** (the total amount of the input token available in the Uniswap pool, fetched via `_fetchReserves`).
- **Minimum Output Amount:**
(`amountOutMin`) is used to determine the minimum output expected from the Uniswap v2 swap, as a safeguard against slippage. 
During `_computeSwapImpact` **`expectedAmountOut`** is calculated based on the current pool reserves and the size of the input amount (`denormAmountIn`) and is used directly as the value for the **`denormAmountOutMin`** parameter in the actual Uniswap `swapExactTokensForTokens` call. Slippage cannot exceed order's max/min price bounds. 