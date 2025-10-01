# CCSettlementRouter Contract Documentation

## Overview
The `CCSettlementRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform using Uniswap V2 for order execution. It inherits functionality from `CCSettlementPartial`, which extends `CCUniPartial` and `CCMainPartial`, integrating with external interfaces (`ICCListing`, `IUniswapV2Pair`, `IUniswapV2Router02`, `IERC20`) for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract handles order settlement via `settleOrders`, with gas optimization through `step` and `maxIterations`, robust error handling, and decimal precision for tokens. It avoids reserved keywords, uses explicit casting, and ensures graceful degradation with try-catch returning decoded error reasons. Transfers to/from the listing call `listingContract.ccUpdate` after successful Uniswap V2 swaps, ensuring state consistency. Transfer taxes are handled using `amountInReceived` for buy/sell orders, with post-transfer balance checks, allowance verification (10^50 for high-supply tokens), and `amountOutMin` adjusted to reflect tax-adjusted `amountInReceived`.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.1.23 (updated 2025-10-01)

**Inheritance Tree:** `CCSettlementRouter` → `CCSettlementPartial` → `CCUniPartial` → `CCMainPartial`

**Compatible Contracts:**
- `CCListingTemplate.sol` (v0.3.9)
- `CCMainPartial.sol` (v0.1.5)
- `CCUniPartial.sol` (v0.1.27)
- `CCSettlementPartial.sol` (v0.1.22)

### Changes
- **v0.1.23**: Updated to reflect `CCUniPartial.sol` v0.1.27 (commented unused `amounts` in try/catch blocks for `_performETHBuySwap`, `_performETHSellSwap`, `_executeTokenSwap` to silence warnings; merged `_createBuyOrderUpdates` and `_createSellOrderUpdates` into `_createOrderUpdates`; simplified `PrepOrderUpdateResult` by removing `normalizedReceived` and `amountIn`; inlined `prepResult` handling in `_executeBuyTokenSwap` and `_executeSellTokenSwap`; removed redundant status checks in `_prepareSwapData` and `_prepareSellSwapData`), `CCSettlementPartial.sol` v0.1.22 (simplified `OrderProcessContext` by removing `maxPrice`, `minPrice`, `currentPrice`, `maxAmountIn`; merged `_updateFilledAndStatus` and `_prepareUpdateData` into `_prepareUpdateData`; inlined `_extractPendingAmount` logic; reduced `_validateOrderParams` checks).
- **v0.1.22**: Updated to reflect `CCSettlementRouter.sol` v0.1.12 (patched `_validateOrder` to set `context.status = 0` when pricing fails, updated `_processOrderBatch` to skip orders with `context.status == 0` to prevent silent failures).
- **v0.1.21**: Updated to reflect `CCSettlementPartial.sol` v0.1.19 (fixed `amountSent` calculation in `_applyOrderUpdate` by capturing `preBalance` before swap in `_executeOrderSwap` and passing it to `_applyOrderUpdate`).
- **v0.1.20**: Updated to reflect `CCUniPartial.sol` v0.1.24 (fixed `_createBuyOrderUpdates` and `_createSellOrderUpdates` to accumulate `amountSent` by adding prior `amountSent` from `getBuyOrderAmounts`/`getSellOrderAmounts`).
- **v0.1.19**: Updated to reflect `CCUniPartial.sol` v0.1.23 (restored `_computeCurrentPrice` to resolve `DeclarationError` in `_prepareSwapData`/`_prepareSellSwapData`), v0.1.22 (removed redundant denormalization in `_prepBuyOrderUpdate`/`_prepSellOrderUpdate`, used pre/post balance checks for `amountSent`). Compatible with `CCListingTemplate.sol` v0.3.9.
- **v0.1.18**: Updated to reflect `CCSettlementRouter.sol` v0.1.10 (patched `_validateOrder` to handle non-reverting `_checkPricing`, emitting `OrderSkipped` and skipping invalid orders), `CCSettlementPartial.sol` v0.1.17 (patched `_validateOrderParams` to handle non-reverting `_checkPricing`, emitting `OrderSkipped` and skipping invalid orders). Compatible with `CCListingTemplate.sol` v0.3.9.
- **v0.1.17**: Updated to reflect `CCSettlementPartial.sol` v0.1.17 (fixed TypeError in `_applyOrderUpdate` using `settlementContext.tokenA/tokenB`, made `_applyOrderUpdate` view), v0.1.16 (added `OrderSkipped` event, modified `_checkPricing` to emit instead of revert, updated `_applyOrderUpdate` for `amountSent` and status). Compatible with `CCListingTemplate.sol` v0.3.9.
- **v0.1.16**: Updated to reflect `CCUniPartial.sol` v0.1.20 (moved `_prepBuyOrderUpdate`, `_prepSellOrderUpdate`, `_getTokenAndDecimals`, `uint2str`, `PrepOrderUpdateResult` to resolve declaration errors; patched `_prepareSwapData`/`_prepareSellSwapData` to compute `amountOutMin` using `amountInReceived` from `_prepBuyOrderUpdate`/`_prepSellOrderUpdate` for transfer taxes), `CCSettlementPartial.sol` v0.1.15 (removed moved functions). Compatible with `CCListingTemplate.sol` v0.3.9.
- **v0.1.15**: Updated to reflect `CCUniPartial.sol` v0.1.17 (patched `_executeTokenSwap` to use `amountInReceived`, added allowance check in `_prepareTokenSwap` with 10^50 for high-supply tokens), `CCSettlementPartial.sol` v0.1.14 (patched `_prepBuyOrderUpdate`/`_prepSellOrderUpdate` to use actual contract balance for `amountIn` post-`transactToken`/`transactNative`). Compatible with `CCListingTemplate.sol` v0.3.9.
- **v0.1.14**: Updated to reflect `CCUniPartial.sol` v0.1.16 (modified `_fetchReserves` to use token balances at Uniswap V2 pair address, updated `_computeMaxAmountIn` and `_computeSwapImpact` to handle unusual token decimals with `normalize`/`denormalize`).
- **v0.1.13**: Updated to reflect `CCSettlementRouter.sol` v0.1.9 (refactored `settleOrders` into `_initSettlement`, `_createHistoricalEntry`, `_processOrderBatch` using `SettlementState` struct), `CCSettlementPartial.sol` v0.1.13 (post-`transactToken` balance checks for tax-on-transfer), `CCUniPartial.sol` v0.1.15 (removed `_ensureTokenBalance`, dynamic `maxAmountIn`, streamlined static data). Compatible with `CCListingTemplate.sol` v0.1.12.

## Mappings
- None defined directly in `CCSettlementRouter` or `CCSettlementPartial`. Relies on `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`) for order tracking.

## Structs
- **OrderContext** (`CCSettlementRouter`): Contains `orderId` (uint256), `pending` (uint256), `status` (uint8), `buyUpdates` (ICCListing.BuyOrderUpdate[]), `sellUpdates` (ICCListing.SellOrderUpdate[]).
- **SettlementState** (`CCSettlementRouter`): Contains `listingAddress` (address), `isBuyOrder` (bool), `step` (uint256), `maxIterations` (uint256).
- **OrderProcessContext** (`CCSettlementPartial`): Contains `orderId` (uint256), `pendingAmount` (uint256), `filled` (uint256), `amountSent` (uint256), `makerAddress` (address), `recipientAddress` (address), `status` (uint8), `swapAmount` (uint256), `buyUpdates` (ICCListing.BuyOrderUpdate[]), `sellUpdates` (ICCListing.SellOrderUpdate[]).
- **PrepOrderUpdateResult** (`CCUniPartial`): Contains `tokenAddress` (address), `tokenDecimals` (uint8), `makerAddress` (address), `recipientAddress` (address), `orderStatus` (uint8), `amountSent` (uint256).

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
    - `_validateOrder` → Fetches order data, checks pricing via `_checkPricing`, emits `OrderSkipped` and sets `context.status = 0` for invalid orders (v0.1.12).
    - `_processOrder` → Calls `_processBuyOrder` or `_processSellOrder`.
    - `_processBuyOrder` → Validates via `_validateOrderParams`, computes swap via `_computeSwapAmount`, captures `preBalance`, executes via `_executeOrderSwap`, applies via `_applyOrderUpdate`.
    - `_processSellOrder` → Similar flow for sell orders.
    - `_executeOrderSwap` → Calls `_executePartialBuySwap` or `_executePartialSellSwap`.
    - `_executePartialBuySwap` → Prepares via `_prepareSwapData`, executes via `_executeBuyTokenSwap` or `_executeBuyETHSwap`.
    - `_executePartialSellSwap` → Prepares via `_prepareSellSwapData`, executes via `_executeSellTokenSwap` or `_executeSellETHSwapInternal`.
    - `_applyOrderUpdate` → Computes `amountSent` with pre/post balance checks, sets status based on pending amount (view).

## Internal Functions
### CCSettlementRouter
- **_validateOrder(address listingAddress, uint256 orderId, bool isBuyOrder, ICCListing listingContract) → OrderContext memory context**: Fetches order data, validates pricing via `_checkPricing`, emits `OrderSkipped` and sets `context.status = 0` for invalid orders (v0.1.12).
- **_processOrder(address listingAddress, bool isBuyOrder, ICCListing listingContract, OrderContext memory context, SettlementContext memory settlementContext) → OrderContext memory**: Delegates to `_processBuyOrder` or `_processSellOrder`.
- **_updateOrder(ICCListing listingContract, OrderContext memory context, bool isBuyOrder) → (bool success, string memory reason)**: Applies `ccUpdate` with `buyUpdates` or `sellUpdates`, returns success or error reason.
- **_initSettlement(address listingAddress, bool isBuyOrder, uint256 step, ICCListing listingContract) → (SettlementState memory state, uint256[] memory orderIds)**: Initializes settlement state, fetches order IDs.
- **_createHistoricalEntry(ICCListing listingContract) → ICCListing.HistoricalUpdate[] memory**: Creates historical data entry with live `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`.
- **_processOrderBatch(SettlementState memory state, uint256[] memory orderIds, ICCListing listingContract, SettlementContext memory settlementContext) → string memory reason**: Iterates orders, skips if `context.status == 0`, calls `_validateOrder`, `_processOrder`, `_updateOrder`.

### CCSettlementPartial
- **_checkPricing(address listingAddress, uint256 orderIdentifier, bool isBuyOrder) → bool**: Validates price bounds, emits `OrderSkipped` if invalid.
- **_computeAmountSent(address tokenAddress, address recipientAddress) → uint256 preBalance**: Captures pre-transfer balance.
- **_validateOrderParams(address listingAddress, uint256 orderId, bool isBuyOrder, ICCListing listingContract) → OrderProcessContext memory context**: Fetches order data, validates status and pending amount, checks pricing.
- **_computeSwapAmount(address listingAddress, bool isBuyOrder, OrderProcessContext memory context, SettlementContext memory settlementContext) → OrderProcessContext memory**: Computes `swapAmount` via `_computeMaxAmountIn`.
- **_executeOrderSwap(address listingAddress, bool isBuyOrder, OrderProcessContext memory context, SettlementContext memory settlementContext) → OrderProcessContext memory**: Executes swap via `_executePartialBuySwap` or `_executePartialSellSwap`.
- **_prepareUpdateData(OrderProcessContext memory context, bool isBuyOrder, uint256 pendingAmount, uint256 preBalance, SettlementContext memory settlementContext) → (ICCListing.BuyOrderUpdate[] memory buyUpdates, ICCListing.SellOrderUpdate[] memory sellUpdates)**: Prepares updates, computes `amountSent`, sets status (v0.1.22).
- **_applyOrderUpdate(OrderProcessContext memory context, bool isBuyOrder, SettlementContext memory settlementContext, uint256 preBalance) → (ICCListing.BuyOrderUpdate[] memory buyUpdates, ICCListing.SellOrderUpdate[] memory sellUpdates)**: Delegates to `_prepareUpdateData` (view).
- **_processBuyOrder(address listingAddress, uint256 orderIdentifier, ICCListing listingContract, SettlementContext memory settlementContext) → ICCListing.BuyOrderUpdate[] memory**: Validates, computes, executes, and applies buy order updates.
- **_processSellOrder(address listingAddress, uint256 orderIdentifier, ICCListing listingContract, SettlementContext memory settlementContext) → ICCListing.SellOrderUpdate[] memory**: Validates, computes, executes, and applies sell order updates.

### CCUniPartial
- **_getTokenAndDecimals(bool isBuyOrder, SettlementContext memory settlementContext) → (address tokenAddress, uint8 tokenDecimals)**: Returns token address and decimals based on order type.
- **_prepBuyOrderUpdate(address listingAddress, uint256 orderIdentifier, uint256 amountReceived, SettlementContext memory settlementContext) → PrepOrderUpdateResult memory**: Prepares buy order update, pulls funds via `transactToken`/`transactNative`.
- **_prepSellOrderUpdate(address listingAddress, uint256 orderIdentifier, uint256 amountReceived, SettlementContext memory settlementContext) → PrepOrderUpdateResult memory**: Prepares sell order update, pulls funds via `transactToken`/`transactNative`.
- **_computeCurrentPrice(address listingAddress) → uint256 price**: Fetches current price from `listingContract.prices(0)`.
- **_computeSwapImpact(uint256 amountIn, bool isBuyOrder, SettlementContext memory settlementContext) → (uint256 price, uint256 amountOut)**: Computes swap impact using Uniswap reserves.
- **_fetchReserves(bool isBuyOrder, SettlementContext memory settlementContext) → ReserveContext memory**: Fetches token reserves from Uniswap pair.
- **_prepareSwapData(address listingAddress, uint256 orderIdentifier, uint256 amountIn, SettlementContext memory settlementContext) → (SwapContext memory context, address[] memory path)**: Prepares buy swap data, computes `amountOutMin`.
- **_prepareSellSwapData(address listingAddress, uint256 orderIdentifier, uint256 amountIn, SettlementContext memory settlementContext) → (SwapContext memory context, address[] memory path)**: Prepares sell swap data, computes `amountOutMin`.
- **_prepareTokenSwap(address tokenIn, address tokenOut, address recipient) → TokenSwapData memory**: Captures pre-swap balances.
- **_performETHBuySwap(SwapContext memory context, address[] memory path) → ETHSwapData memory**: Executes ETH-to-token swap, uses balance checks (v0.1.27: commented `amounts`).
- **_performETHSellSwap(SwapContext memory context, address[] memory path) → ETHSwapData memory**: Executes token-to-ETH swap, uses balance checks (v0.1.27: commented `amounts`).
- **_createOrderUpdates(uint256 orderIdentifier, OrderUpdateContext memory updateContext, uint256 pendingAmount, uint256 filled, bool isBuyOrder) → (ICCListing.BuyOrderUpdate[] memory buyUpdates, ICCListing.SellOrderUpdate[] memory sellUpdates)**: Creates buy or sell order updates (v0.1.27: merged from `_createBuyOrderUpdates`/`_createSellOrderUpdates`).
- **_finalizeTokenSwap(TokenSwapData memory data, SwapContext memory context, uint256 orderIdentifier, uint256 pendingAmount, bool isBuyOrder) → (ICCListing.BuyOrderUpdate[] memory buyUpdates, ICCListing.SellOrderUpdate[] memory sellUpdates)**: Finalizes swap, prepares updates.
- **_executeBuyETHSwap(SwapContext memory context, uint256 orderIdentifier, uint256 pendingAmount) → ICCListing.BuyOrderUpdate[] memory**: Executes ETH buy swap, creates updates.
- **_executeSellETHSwapInternal(SwapContext memory context, uint256 orderIdentifier, uint256 pendingAmount) → ICCListing.SellOrderUpdate[] memory**: Executes sell-to-ETH swap, creates updates.
- **_executeBuyTokenSwap(SwapContext memory context, uint256 orderIdentifier, uint256 pendingAmount) → ICCListing.BuyOrderUpdate[] memory**: Executes token buy swap, inlines `prepResult` (v0.1.27).
- **_executeSellTokenSwap(SwapContext memory context, uint256 orderIdentifier, uint256 pendingAmount, uint256 amountInReceived) → ICCListing.SellOrderUpdate[] memory**: Executes sell token swap, inlines `prepResult` (v0.1.27).
- **_executePartialBuySwap(address listingAddress, uint256 orderIdentifier, uint256 amountIn, uint256 pendingAmount, SettlementContext memory settlementContext) → ICCListing.BuyOrderUpdate[] memory**: Prepares and executes buy swap.
- **_executePartialSellSwap(address listingAddress, uint256 orderIdentifier, uint256 amountIn, uint256 pendingAmount, SettlementContext memory settlementContext) → ICCListing.SellOrderUpdate[] memory**: Prepares and executes sell swap.
- **_computeMaxAmountIn(address listingAddress, uint256 maxPrice, uint256 minPrice, uint256 pendingAmount, bool isBuyOrder, SettlementContext memory settlementContext) → uint256 maxAmountIn**: Computes max input respecting price bounds.
- **_executeTokenSwap(SwapContext memory context, address[] memory path, uint256 amountIn) → TokenSwapData memory**: Executes token-to-token swap, uses balance checks (v0.1.27: commented `amounts`).
- **uint2str(uint256 _i) → string memory str**: Converts uint256 to string for error messages.

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
    - `deadline`: `block.timestamp + 15`.
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
  - Uses `IERC20.balanceOf(uniswapV2Pair)` for `tokenA` and `tokenB` in `_computeSwapImpact`.
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
  - `deadline`: `block.timestamp + 15`.
- **Error Handling**: Try-catch in `transactNative`, `transactToken`, `approve`, `swap`, and `ccUpdate` with decoded reasons (v0.1.5).
- **Status Handling**: Status set to 3 (complete) if `pending <= 0`, else 2 (partially filled).
- **ccUpdate Call Locations**:
  - **CCSettlementRouter.sol**: Handles all `ccUpdate` calls to `CCListingTemplate.sol`. The `_updateOrder` function applies order updates (`buyUpdates` or `sellUpdates`) for buy or sell orders. The `settleOrders` function applies historical data updates (`historicalUpdates`) at the start of order processing. Updates are prepared in `CCUniPartial.sol` (via `_createOrderUpdates`), refined in `CCSettlementPartial.sol` (via `_prepareUpdateData`/`_applyOrderUpdate`, now view), and applied only in `CCSettlementRouter.sol`.
  - **No Duplicate Calls**: After v0.1.11, `_applyOrderUpdate` is view, and `ccUpdate` is called once per order in `_updateOrder` and once for historical data in `settleOrders`.
- **State Update (`CCListingTemplate.ccUpdate`)**:
  - **Core (`structId = 0`)**: Updates `status`; immutable fields (`maker`, `recipient`) are rewritten with original values.
  - **Pricing (`structId = 1`)**: Immutable fields (`minPrice`/`maxPrice`) are rewritten with original values (no-op for data, ensures consistency).
  - **Amounts (`structId = 2`)**: Volatile fields (`pending`, `filled`, `amountSent`) are updated with new values from the swap.
- **Price Impact Protection**: `_computeMaxAmountIn` ensures estimated impact price respects the user's `maxPrice` (for buys) and `minPrice` (for sells).
- **Price Calculation**:
  - Uses `listingContract.prices(0)` to fetch the current price, calculated as `(balanceB * 1e18) / balanceA`.
- **Partial Fills Behavior**:
  - Partial fills occur when `swapAmount` is limited by `maxAmountIn`, calculated in `_computeMaxAmountIn` to respect price bounds and available reserves. For example, with a buy order of 100 tokenB pending, a pool of 1000 tokenA and 500 tokenB (price = 0.5 tokenA/tokenB), and price bounds (max 0.6, min 0.4), `maxAmountIn` is 50 tokenB due to price-adjusted constraints. This results in a swap of 50 tokenB for ~90.59 tokenA, updating `pending = 50`, `filled += 50`, `amountSent = 90.59`, and `status = 2` (partially filled) via a single `ccUpdate` call in `_updateOrder`.
- **AmountSent Usage**:
  - Tracks actual tokens received by the recipient (e.g., tokenA for buys) in `BuyOrderUpdate`/`SellOrderUpdate`.
  - **Calculation**: Uses pre/post balance checks (e.g., ~90.59 tokenA for 50 tokenB after fees).
  - **Partial Fills**: Increments `amountSent` for each partial fill.
  - **Application**: Prepared in `CCUniPartial.sol` (via `_createOrderUpdates`), refined in `CCSettlementPartial.sol` (via `_prepareUpdateData`), applied via one `ccUpdate` call in `CCSettlementRouter.sol`.
- **Maximum Input Amount**:
  - `maxAmountIn` ensures the swap size respects `minPrice`/`maxPrice` bounds, calculated in `_computeMaxAmountIn`.
  - **Calculation**: Uses `priceAdjustedAmount` (based on current price and pending amount), limited by `pendingAmount` and `normalizedReserveIn` (from `_fetchReserves`).
- **Minimum Output Amount**:
  - `amountOutMin` (from `_computeSwapImpact`) ensures slippage does not exceed order price bounds, set as `denormAmountOutMin` in swap calls.
- **Reserve Clarification**:
  - Uses live balances of the Uniswap pair address for `_computeSwapImpact` and `_computeMaxAmountIn`.
- **Partial Fills Continuation**:
  - Supports partial fills and resumes previously partially filled orders until fully filled.
- **Handling Tax-on-Transfer Tokens**:
  - **Pending/Filled**: Based on pre-transfer values to ensure users bear tax costs.
  - **AmountSent**: Based on pre/post transfer balance checks to capture actual settled amounts.
- **Error Handling**:
  - **Graceful Skipping**: Non-critical issues (e.g., invalid price) emit `OrderSkipped` and skip the order, continuing the batch.
  - **Critical Reverts**: System-level failures (e.g., missing Uniswap router, failed `transactToken`/`ccUpdate`) revert to ensure state consistency.