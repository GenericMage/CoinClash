# CCSettlementRouter Contract Documentation

## Overview
The `CCSettlementRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform using Uniswap V2 for order execution. It inherits functionality from `CCSettlementPartial`, which extends `CCUniPartial` and `CCMainPartial`, integrating with external interfaces (`ICCListing`, `IUniswapV2Pair`, `IUniswapV2Router02`, `IERC20`) for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract handles order settlement via `settleOrders`, with gas optimization through `step` and `maxIterations`, robust error handling, and decimal precision for tokens. It avoids reserved keywords, uses explicit casting, and ensures graceful degradation with try-catch returning decoded error reasons. Transfers to/from the listing call `listingContract.update` after successful Uniswap V2 swaps, ensuring state consistency. Transfer taxes are handled using `amountInReceived`.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.8 (updated 2025-08-18)

**Inheritance Tree:** `CCSettlementRouter` → `CCSettlementPartial` → `CCUniPartial` → `CCMainPartial`

**Compatible Contracts:**
- `CCListingTemplate.sol` (v0.1.7)
- `CCMainPartial.sol` (v0.0.14)
- `CCUniPartial.sol` (v0.0.18)
- `CCSettlementPartial.sol` (v0.0.21)

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
- **Purpose**: Iterates over pending buy or sell orders, validates price impact, processes swaps via Uniswap V2, and updates the listing state.
- **Modifiers**: `nonReentrant`, `onlyValidListing(listingAddress)` (from `CCMainPartial`).
- **Parameters**:
  - `listingAddress`: Address of the `ICCListing` contract.
  - `step`: Starting index for order processing (e.g., if `pendingBuyOrdersView` returns `[10,11,22,23,24]` and `step = 3`, processing starts at index 3, orderId `23`).
  - `maxIterations`: Maximum number of orders to process for gas control.
  - `isBuyOrder`: True for buy orders, false for sell orders.
- **Returns**: None (reverts if no orders are settled).
- **Internal Call Tree**:
  1. **Fetch Orders**: Calls `listingContract.pendingBuyOrdersView()` or `pendingSellOrdersView()` to get `orderIds`.
  2. **Iterate Orders**: Loops from `i = step` to `min(orderIds.length, step + maxIterations)`.
     - Fetches `pending` via `listingContract.getBuyOrderAmounts(orderId)` or `getSellOrderAmounts(orderId)`.
     - Skips if `pending == 0`.
  3. **Validate Pricing**: Calls `_checkPricing(listingAddress, orderId, isBuyOrder, pending)`:
     - Gets `maxPrice`, `minPrice` via `listingContract.getBuyOrderPricing` or `getSellOrderPricing`.
     - Calls `_computeSwapImpact` (from `CCUniPartial`) to get `impactPrice`.
     - Returns `true` if `impactPrice <= maxPrice && impactPrice >= minPrice`.
  4. **Process Order**: Calls `_processBuyOrder` or `_processSellOrder` (from `CCSettlementPartial`):
     - **_processBuyOrder/_processSellOrder**:
       - Fetches `pending`, `filled`, `amountSent` via `getBuyOrderAmounts` or `getSellOrderAmounts`.
       - Returns empty array if `pending == 0` or `currentPrice` (from `_computeCurrentPrice`) is outside `minPrice`/`maxPrice`.
       - Calls `_computeMaxAmountIn` (from `CCUniPartial`) to get `maxAmountIn`.
       - Sets `swapAmount = min(maxAmountIn, pendingAmount)` with validation (`require(swapAmount <= pendingAmount)`).
       - Calls `_executePartialBuySwap` or `_executePartialSellSwap` (from `CCUniPartial`).
     - **_executePartialBuySwap/_executePartialSellSwap**:
       - Calls `_prepareSwapData` or `_prepareSellSwapData` to populate `SwapContext` and `path`.
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
       - Returns `ICCListing.UpdateType[]` with updates for amount received and order status.
  5. **Update Listing**: Calls `listingContract.update(updates)` with try-catch, reverting with decoded error reasons (e.g., `"Update failed for order <orderId>: <reason>"`).
  6. **Validation**: Increments `count` on successful updates, reverts if `count == 0` with `"No orders settled"`.
- **Error Handling**:
  - Reverts if `uniswapV2PairView` is `address(0)` or reserves are zero.
  - Catches errors in `transactNative`, `transactToken`, `approve`, `swap`, and `update` calls, reverting with decoded reasons.
  - Skips invalid orders (zero pending, invalid pricing) without state changes.
- **Gas Optimization**:
  - Uses `step` to skip processed orders.
  - Limits iterations with `maxIterations`.
  - Avoids nested calls during struct initialization.

## Formulas
Uniswap V2 formulas (from `CCUniPartial.sol`):
- **Price Calculation** (`_computeCurrentPrice`):
  - `price = (normalizedReserveB * 1e18) / normalizedReserveA` (updated to reflect flipped price in CCListingTemplate).
  - Uses `normalize(reserve, decimals)` for 1e18 precision.
- **Swap Impact** (`_computeSwapImpact`):
  - `amountInAfterFee = (amountIn * 997) / 1000` (0.3% Uniswap fee).
  - `amountOut = (amountInAfterFee * normalizedReserveOut) / (normalizedReserveIn + amountInAfterFee)`.
  - `price = ((normalizedReserveIn + amountInAfterFee) * 1e18) / (normalizedReserveOut - amountOut)` if `normalizedReserveOut > amountOut`, else `0`.
- **Max Amount In** (`_computeMaxAmountIn`):
  - `maxImpactPercent = isBuyOrder ? (maxPrice * 100e18 / currentPrice - 100e18) / 1e18 : (currentPrice * 100e18 / minPrice - 100e18) / 1e18`.
  - `maxAmountIn = min((normalizedReserveIn * maxImpactPercent) / (100 * 2), pendingAmount)`.
- **Minimum Output**:
  - Buy: `amountOutMin = (expectedAmountOut * 1e18) / maxPrice` (in `_prepareSwapData`).
  - Sell: `amountOutMin = (expectedAmountOut * minPrice) / 1e18` (in `_prepareSellSwapData`).

## Internal Functions
- **_getTokenAndDecimals** (`CCSettlementPartial`): Returns `tokenAddress` and `tokenDecimals` from `listingContract.tokenA()`/`tokenB()` and `decimalsA()`/`decimalsB()`.
- **_checkPricing** (`CCSettlementPartial`): Validates `impactPrice` against `maxPrice`/`minPrice` using `_computeSwapImpact`.
- **_computeAmountSent** (`CCSettlementPartial`): Returns pre-transfer balance for recipient (ETH or token).
- **_prepBuyOrderUpdate/_prepSellOrderUpdate** (`CCSettlementPartial`): Prepares `PrepOrderUpdateResult` with balance checks, calls `transactNative` or `transactToken`.
- **_processBuyOrder/_processSellOrder** (`CCSettlementPartial`): Validates `pendingAmount`, `currentPrice`, and `swapAmount`, calls `_executePartialBuySwap` or `_executePartialSellSwap`.
- **_computeCurrentPrice**, `_computeSwapImpact**, `_fetchReserves**, `_computeImpactPercent**, `_computeMaxAmount**, `_prepareSwapData**, `_prepareSellSwapData**, `_prepareTokenSwap**, `_executeTokenSwap**, `_performETHBuySwap**, `_performETHSellSwap**, `_finalizeTokenSwap**, `_finalizeSellTokenSwap**, `_executeBuyETHSwap**, `_executeSellETHSwapInternal**, `_executeBuyTokenSwap**, `_executeSellTokenSwap**, `_executePartialBuySwap**, `_executePartialSellSwap**, `_createBuyOrderUpdates**, `_createSellOrderUpdates** (`CCUniPartial`): Handle swap logic, balance checks, and update generation.

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
  - Buy: Increases price (`reserveB` increases, `reserveA` decreases).
  - Sell: Decreases price (`reserveA` increases, `reserveB` decreases).

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
- **Error Handling**: Try-catch in `transactNative`, `transactToken`, `approve`, `swap`, and `update` with decoded reasons (updated in `CCUniPartial.sol` v0.0.18).
- **Changes**:
  - `CCSettlementRouter.sol` (v0.0.8): Removed redundant `uint2str`, inherits from `CCSettlementPartial`.
  - `CCSettlementPartial.sol` (v0.0.21): Renamed `amountOut` to `amountReceived`, moved `amountIn <= pending` validation to `_processBuyOrder/_processSellOrder`.
  - `CCUniPartial.sol` (v0.0.18): Updated `_computeCurrentPrice` to `reserveB / reserveA`, adjusted `_computeSwapImpact` for flipped price.
