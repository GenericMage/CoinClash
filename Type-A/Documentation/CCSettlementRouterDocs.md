# CCSettlementRouter Contract Documentation

## Overview
The `CCSettlementRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform using Uniswap V2 for order execution. It inherits functionality from `CCSettlementPartial`, which extends `CCUniPartial` and `CCMainPartial`, integrating with external interfaces (`ICCListing`, `IUniswapV2Pair`, `IUniswapV2Router02`, `IERC20`) for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract handles order settlement via `settleOrders`, with gas optimization through `step` and `maxIterations`, robust error handling, and decimal precision for tokens. It avoids reserved keywords, uses explicit casting, and ensures graceful degradation with try-catch returning decoded error reasons. Transfers to/from the listing call `listingContract.ccUpdate` after successful Uniswap V2 swaps, ensuring state consistency. Transfer taxes are handled using `amountInReceived` for buy/sell orders, with post-transfer balance checks, allowance verification (10^50 for high-supply tokens), and `amountOutMin` adjusted to reflect tax-adjusted `amountInReceived`.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.1.18 (updated 2025-09-26)

**Inheritance Tree:** `CCSettlementRouter` → `CCSettlementPartial` → `CCUniPartial` → `CCMainPartial`

**Compatible Contracts:**
- `CCListingTemplate.sol` (v0.3.9)
- `CCMainPartial.sol` (v0.1.5)
- `CCUniPartial.sol` (v0.1.21)
- `CCSettlementPartial.sol` (v0.1.17)

### Changes
- **v0.1.18**: Updated to reflect `CCSettlementRouter.sol` v0.1.10 (patched `_validateOrder` to handle non-reverting `_checkPricing`, emitting `OrderFailed` and skipping invalid orders), `CCSettlementPartial.sol` v0.1.17 (patched `_validateOrderParams` to handle non-reverting `_checkPricing`, emitting `OrderFailed` and skipping invalid orders). Compatible with `CCListingTemplate.sol` v0.3.9.
- **v0.1.17**: Updated to reflect `CCSettlementPartial.sol` v0.1.18 (fixed TypeError by adding `settlementContext` to `_applyOrderUpdate` calls in `_processBuyOrder`/`_processSellOrder`), v0.1.17 (fixed TypeError in `_applyOrderUpdate` using `settlementContext.tokenA/tokenB`, made `_applyOrderUpdate` view), v0.1.16 (added `OrderFailed` event, modified `_checkPricing` to emit instead of revert, updated `_applyOrderUpdate` for `amountSent` and status). Compatible with `CCListingTemplate.sol` v0.3.9.
- **v0.1.16**: Updated to reflect `CCUniPartial.sol` v0.1.20 (moved `_prepBuyOrderUpdate`, `_prepSellOrderUpdate`, `_getTokenAndDecimals`, `uint2str`, `PrepOrderUpdateResult` to resolve declaration errors; patched `_prepareSwapData`/`_prepareSellSwapData` to compute `amountOutMin` using `amountInReceived` from `_prepBuyOrderUpdate`/`_prepSellOrderUpdate` for transfer taxes), `CCSettlementPartial.sol` v0.1.15 (removed moved functions). Compatible with `CCListingTemplate.sol` v0.3.9.
- **v0.1.15**: Updated to reflect `CCUniPartial.sol` v0.1.17 (patched `_executeTokenSwap` to use `amountInReceived`, added allowance check in `_prepareTokenSwap` with 10^50 for high-supply tokens), `CCSettlementPartial.sol` v0.1.14 (patched `_prepBuyOrderUpdate`/`_prepSellOrderUpdate` to use actual contract balance for `amountIn` post-`transactToken`/`transactNative`). Compatible with `CCListingTemplate.sol` v0.3.9.
- **v0.1.14**: Updated to reflect `CCUniPartial.sol` v0.1.16 (modified `_fetchReserves` to use token balances at Uniswap V2 pair address, updated `_computeMaxAmountIn` and `_computeSwapImpact` to handle unusual token decimals with `normalize`/`denormalize`).
- **v0.1.13**: Updated to reflect `CCSettlementRouter.sol` v0.1.9 (refactored `settleOrders` into `_initSettlement`, `_createHistoricalEntry`, `_processOrderBatch` using `SettlementState` struct), `CCSettlementPartial.sol` v0.1.13 (post-`transactToken` balance checks for tax-on-transfer), `CCUniPartial.sol` v0.1.15 (removed `_ensureTokenBalance`, dynamic `maxAmountIn`, streamlined static data). Compatible with `CCListingTemplate.sol` v0.1.12.

## Mappings
- None defined directly in `CCSettlementRouter` or `CCSettlementPartial`. Relies on `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`) for order tracking.

## Structs
- **OrderContext** (`CCSettlementRouter`): Contains `orderId` (uint256), `pending` (uint256), `status` (uint8), `buyUpdates` (ICCListing.BuyOrderUpdate[]), `sellUpdates` (ICCListing.SellOrderUpdate[]).
- **SettlementState** (`CCSettlementRouter`): Contains `listingAddress` (address), `isBuyOrder` (bool), `step` (uint256), `maxIterations` (uint256).
- **OrderProcessContext** (`CCSettlementPartial`): Contains `orderId` (uint256), `pendingAmount` (uint256), `filled` (uint256), `amountSent` (uint256), `makerAddress` (address), `recipientAddress` (address), `status` (uint8), `maxPrice` (uint256), `minPrice` (uint256), `currentPrice` (uint256), `maxAmountIn` (uint256), `swapAmount` (uint256), `buyUpdates` (ICCListing.BuyOrderUpdate[]), `sellUpdates` (ICCListing.SellOrderUpdate[]).
- **PrepOrderUpdateResult** (`CCSettlementPartial`): Contains `tokenAddress` (address), `tokenDecimals` (uint8), `makerAddress` (address), `recipientAddress` (address), `orderStatus` (uint8), `amountReceived` (uint256), `normalizedReceived` (uint256), `amountSent` (uint256), `amountIn` (uint256).

## External Functions
- **settleOrders(address listingAddress, uint256 step, uint256 maxIterations, bool isBuyOrder) → string memory reason** (`CCSettlementRouter`):
  - Iterates pending orders from `step` up to `maxIterations`.
  - Fetches static data via `SettlementContext`.
  - Calls `_initSettlement`, `_createHistoricalEntry`, `_processOrderBatch`.
  - Validates via `_validateOrder`, processes via `_processOrder`, applies via `_updateOrder`.
  - Returns empty string or error reason.
  - **Internal Call Tree**:
    - `_initSettlement` → Fetches order IDs, validates router.
    - `_createHistoricalEntry` → Creates `HistoricalUpdate` using `volumeBalances`, `prices`, `historicalDataLengthView`, `getHistoricalDataView`.
    - `_processOrderBatch` → Iterates orders, calls `_validateOrder`, `_processOrder`, `_updateOrder`.
    - `_validateOrder` → Fetches order data, checks pricing via `_checkPricing`, emits `OrderFailed` and skips invalid orders.
    - `_processOrder` → Calls `_processBuyOrder` or `_processSellOrder`.
    - `_processBuyOrder` → Validates via `_validateOrderParams`, computes swap via `_computeSwapAmount`, executes via `_executeOrderSwap`, applies via `_applyOrderUpdate`.
    - `_processSellOrder` → Similar flow for sell orders.
    - `_executeOrderSwap` → Calls `_executePartialBuySwap` or `_executePartialSellSwap`.
    - `_executePartialBuySwap` → Prepares via `_prepareSwapData`, executes via `_executeBuyTokenSwap` or `_executeBuyETHSwap`.
    - `_executePartialSellSwap` → Prepares via `_prepareSellSwapData`, executes via `_executeSellTokenSwap` or `_executeSellETHSwapInternal`.
    - `_applyOrderUpdate` → Computes `amountSent` with pre/post balance checks, sets status based on pending amount (view).


## Internal Functions
### CCSettlementRouter
- **_validateOrder(address listingAddress, uint256 orderId, bool isBuyOrder, ICCListing listingContract) → OrderContext memory context**: Fetches order data, validates pricing via `_checkPricing`, emits `OrderFailed` and skips invalid orders (v0.1.10).
- **_processOrder(address listingAddress, bool isBuyOrder, ICCListing listingContract, OrderContext memory context, SettlementContext memory settlementContext) → OrderContext memory**: Delegates to `_processBuyOrder` or `_processSellOrder`.
- **_updateOrder(ICCListing listingContract, OrderContext memory context, bool isBuyOrder) → (bool success, string memory reason)**: Applies `ccUpdate` with `buyUpdates` or `sellUpdates`, returns success or error reason.
- **_initSettlement(address listingAddress, bool isBuyOrder, uint256 step, ICCListing listingContract) → (SettlementState memory state, uint256[] memory orderIds)**: Initializes settlement state, fetches order IDs.
- **_createHistoricalEntry(ICCListing listingContract) → ICCListing.HistoricalUpdate[] memory**: Creates historical data entry with live `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`.
- **_processOrderBatch(SettlementState memory state, uint256[] memory orderIds, ICCListing listingContract, SettlementContext memory settlementContext) → uint256 count**: Processes batch of orders, returns count of successful settlements.

### CCSettlementPartial
- **_checkPricing(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, uint256 pendingAmount) → bool**: Emits `OrderFailed` if price is invalid or out of bounds, returns false instead of reverting (v0.1.16).
- **_computeAmountSent(address tokenAddress, address recipientAddress, uint256 amount) → uint256 preBalance**: Computes pre-transfer balance for `amountSent` calculation.
- **_validateOrderParams(address listingAddress, uint256 orderId, bool isBuyOrder, ICCListing listingContract) → OrderProcessContext memory**: Fetches order data, validates pricing via `_checkPricing`, emits `OrderFailed` and skips invalid orders (v0.1.17).
- **_computeSwapAmount(address listingAddress, bool isBuyOrder, OrderProcessContext memory context, SettlementContext memory settlementContext) → OrderProcessContext memory**: Computes `maxAmountIn` and `swapAmount`.
- **_executeOrderSwap(address listingAddress, bool isBuyOrder, OrderProcessContext memory context, SettlementContext memory settlementContext) → OrderProcessContext memory**: Executes swap via `_executePartialBuySwap` or `_executePartialSellSwap`.
- **_extractPendingAmount(OrderProcessContext memory context, bool isBuyOrder) → uint256 pending**: Extracts pending amount from `buyUpdates` or `sellUpdates`.
- **_updateFilledAndStatus(OrderProcessContext memory context, bool isBuyOrder, uint256 pendingAmount) → (ICCListing.BuyOrderUpdate[] memory, ICCListing.SellOrderUpdate[] memory)**: Updates `filled` and `status` for order updates.
- **_prepareUpdateData(OrderProcessContext memory context, bool isBuyOrder) → (ICCListing.BuyOrderUpdate[] memory, ICCListing.SellOrderUpdate[] memory)**: Prepares update data for `ccUpdate`.
- **_applyOrderUpdate(address listingAddress, ICCListing listingContract, OrderProcessContext memory context, bool isBuyOrder, SettlementContext memory settlementContext) → (ICCListing.BuyOrderUpdate[] memory, ICCListing.SellOrderUpdate[] memory)**: Computes `amountSent` with pre/post balance checks, sets status based on pending amount (view, v0.1.17).
- **_processBuyOrder(address listingAddress, uint256 orderIdentifier, ICCListing listingContract, SettlementContext memory settlementContext) → ICCListing.BuyOrderUpdate[] memory**: Orchestrates buy order processing via `_validateOrderParams`, `_computeSwapAmount`, `_executeOrderSwap`, `_applyOrderUpdate`.
- **_processSellOrder(address listingAddress, uint256 orderIdentifier, ICCListing listingContract, SettlementContext memory settlementContext) → ICCListing.SellOrderUpdate[] memory**: Orchestrates sell order processing via `_validateOrderParams`, `_computeSwapAmount`, `_executeOrderSwap`, `_applyOrderUpdate`.

### CCUniPartial
- **_getTokenAndDecimals(address listingAddress, bool isBuyOrder, SettlementContext memory settlementContext) → (address tokenAddress, uint8 tokenDecimals)**: Retrieves token address and decimals from cached `SettlementContext` data, reverts for invalid sell order token addresses.
- **_prepBuyOrderUpdate(address listingAddress, uint256 orderIdentifier, uint256 amountReceived, SettlementContext memory settlementContext) → PrepOrderUpdateResult memory**: Pulls funds via `transactToken`/`transactNative`, uses actual contract balance (`address(this).balance` or `IERC20.balanceOf`) for `amountSent` and `amountIn` to handle tax-on-transfer, returns update data.
- **_prepSellOrderUpdate(address listingAddress, uint256 orderIdentifier, uint256 amountReceived, SettlementContext memory settlementContext) → PrepOrderUpdateResult memory**: Pulls funds via `transactToken`/`transactNative`, uses actual contract balance for `amountSent` and `amountIn` to handle tax-on-transfer, returns update data.
- **_prepareTokenSwap(address tokenIn, address tokenOut, address recipientAddress) → TokenSwapData memory**: Prepares token swap with pre/post balance checks, verifies allowance, and sets 10^50 approval if insufficient for high-supply tokens.
- **_executeTokenSwap(SwapContext memory context, address[] memory path) → TokenSwapData memory**: Executes token-to-token swap using `amountInReceived` (actual received amount post-transfer) to handle transfer taxes.
- **_prepareSwapData(address listingAddress, uint256 orderIdentifier, uint256 amountIn, SettlementContext memory settlementContext) → (SwapContext memory context, address[] memory path)**: Prepares swap data for buy orders, computes `amountOutMin` using `amountInReceived` from `_prepBuyOrderUpdate` to account for transfer taxes.
- **_prepareSellSwapData(address listingAddress, uint256 orderIdentifier, uint256 amountIn, SettlementContext memory settlementContext) → (SwapContext memory context, address[] memory path)**: Prepares swap data for sell orders, computes `amountOutMin` using `amountInReceived` from `_prepSellOrderUpdate` to account for transfer taxes.
- **_computeMaxAmountIn(address listingAddress, uint256 maxPrice, uint256 minPrice, uint256 pendingAmount, bool isBuyOrder, SettlementContext memory settlementContext) → uint256 maxAmountIn**: Computes max input amount with decimal normalization, capped by price bounds, `pendingAmount`, and `normalizedReserveIn` with Uniswap fees.
- **_computeSwapImpact(address listingAddress, uint256 amountIn, bool isBuyOrder, SettlementContext memory settlementContext) → (uint256 price, uint256 amountOut)**: Computes swap impact, calculating `expectedAmountOut` based on `amountIn` (tax-adjusted via `amountInReceived`) and pool reserves.
- **_createBuyOrderUpdates(uint256 orderIdentifier, BuyOrderUpdateContext memory updateContext, uint256 pendingAmount, uint256 filled) → ICCListing.BuyOrderUpdate[] memory**: Creates buy order updates for `ccUpdate`, adjusting `pending`, `filled`, and `status`.
- **_createSellOrderUpdates(uint256 orderIdentifier, SellOrderUpdateContext memory updateContext, uint256 pendingAmount, uint256 filled) → ICCListing.SellOrderUpdate[] memory**: Creates sell order updates for `ccUpdate`, adjusting `pending`, `filled`, and `status`.



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
  
## Token Flow
- **Buy Order**:
  - Pulls `tokenB` or ETH via `transactToken`/`transactNative` to this contract (`_prepBuyOrderUpdate`).
  - Executes `swapExactTokensForTokens` or `swapExactETHForTokens` to recipient (`_executeBuyTokenSwap`/`_executeBuyETHSwap`).
  - `amountReceived` (tokenA) to recipient, tracked via `amountSent`.
- **Sell Order**:
  - Pulls `tokenA` via `transactToken` to this contract (`_prepSellOrderUpdate`).
  - Executes `swapExactTokensForTokens` or `swapExactTokensForETH` to recipient (`_executeSellTokenSwap`/`_executeSellETHSwapInternal`).
  - `amountReceived` (tokenB or ETH) to recipient, tracked via `amountSent`.
  
## Key Interactions
- **Uniswap V2**:
  - **Swap Parameters**:
    - `amountIn`: `denormAmountIn` (from `_prepareSwapData`/`_prepareSellSwapData`, adjusted for taxes via `amountInReceived`).
    - `amountOutMin`: `denormAmountOutMin` from `_computeSwapImpact`.
    - `path`: `[tokenB, tokenA]` (buy), `[tokenA, tokenB]` (sell).
    - `to`: `recipientAddress`.
    - `deadline`: `block.timestamp + 15 minutes`.
  - **Functions**: `swapExactTokensForTokens`, `swapExactETHForTokens`, `swapExactTokensForETH`.
- **ICCListing**:
  - **Data Retrieval**: `getBuyOrderCore`, `getSellOrderCore`, `getBuyOrderAmounts`, `getSellOrderAmounts`, `getBuyOrderPricing`, `getSellOrderPricing`, `prices`, `volumeBalances`, `historicalDataLengthView`, `getHistoricalDataView`, `pendingBuyOrdersView`, `pendingSellOrdersView`, `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `uniswapV2PairView`.
  - **State Updates**: `ccUpdate` for `BuyOrderUpdate`, `SellOrderUpdate`, `HistoricalUpdate`.
  - **Fund Transfers**: `transactToken`, `transactNative` to pull funds to this contract for swaps.
- **ICCAgent**: Validates listings via `isValidListing` in `onlyValidListing` modifier.

## Limitations and Assumptions
- **No Order Creation/Cancellation**: Handled by `CCOrderRouter`.
- **No Payouts or Liquidity Settlement**: Handled by `CCCLiquidityRouter` or `CCLiquidRouter`.
- **Uniswap V2 Dependency**: Requires valid `uniswapV2Router` and `uniswapV2PairView`.
- **Zero-Amount Handling**: Returns empty `BuyOrderUpdate[]` or `SellOrderUpdate[]` for zero pending amounts or failed swaps.
- **Decimal Handling**: Uses `normalize`/`denormalize` for 18-decimal precision, assumes `IERC20.decimals` or 18 for ETH.
- **Price Impact**:
  - Uses `IERC20.balanceOf(listingAddress)` for `tokenA` and `tokenB` in `_computeSwapImpact`.
  - Buy: Increases price (via `listingContract.prices(0)`).
  - Sell: Decreases price (via `listingContract.prices(0)`).
- **Pending/Filled**: Uses `amountIn` (pre-transfer: tokenB for buys, tokenA for sells) for `pending` and `filled`, accumulating `filled`.
- **AmountSent**: Uses `amountInReceived` (post-transfer: tokenA for buys, tokenB or ETH for sells) with pre/post balance checks.
- **Historical Data**: Creates a new `HistoricalUpdate` entry at the start of `settleOrders` if pending orders exist, applying latest `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume` via `ccUpdate`.

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
- **Status Handling**: Status set to 3 (complete) if `pending <= 0`, else 2 (partially filled).
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
- **Reserve Clarification:**
Uniswap "reserves" are used in name only. The system fetches live balances of the LP address for `_computeSwapImpact` and `_computeMaxAmountIn `. 
- **Partial Fills Continuation:**
The system is capable of partially filling an order and continuing an order that was previously partially filled, until fully filled. 
- **Handling Tax-on-transfer tokens:**
Certain tokens take a tax on each transfer, which can undercut the order settlement mechanism if not properly handled. The router handles the following fields as follows; 
  - **Pending/Filled** : The router sets these based on the pre-transfer value, this ensures the user pays the cost of the tax.
  - **AmountSent** : The router sets this based on the pre/post transfer relationship, this ensures that the true amount settled after taxes is captured. 
- **Error Handling:**
The system employs a dual error-handling strategy for settlement.
  * **Graceful Skipping**: For non-critical, order-specific issues like an invalid price, the contract emits an `OrderFailed` event and skips that order, allowing the settlement batch to continue processing other valid orders.
  * **Critical Reverts**: For system-level failures, such as a missing Uniswap router address or a failed fund transfer or `ccUpdate ` call failure, the entire transaction reverts to prevent inconsistent states and ensure protocol integrity.