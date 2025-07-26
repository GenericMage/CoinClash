# CCSettlementRouter Contract Documentation

## Overview
The `CCSettlementRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform using Uniswap V2 for order execution. It inherits functionality from `CCSettlementPartial`, which extends `CCUniPartial` and `CCMainPartial`, and integrates with external interfaces (`ICCListing`, `IUniswapV2Pair`, `IUniswapV2Router02`, `IERC20`) for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract handles order settlement (`settleBuyOrders`, `settleSellOrders`) via Uniswap V2 swaps, with robust gas optimization and safety mechanisms. State variables are hidden, accessed via view functions with unique names, and decimal precision is maintained across tokens. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation. All transfers to or from the listing correctly call `listingContract.update` after successful Uniswap V2 swaps, ensuring state consistency.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.4 (updated 2025-07-26)

**Inheritance Tree:** `CCSettlementRouter` → `CCSettlementPartial` → `CCUniPartial` → `CCMainPartial`

## Mappings
- None defined directly in `CCSettlementRouter`. Relies on `ICCListing` view functions (e.g., `pendingBuyOrdersView`, `pendingSellOrdersView`) for order tracking.

## Structs
- **PrepOrderUpdateResult**: Contains `tokenAddress` (address), `tokenDecimals` (uint8), `makerAddress` (address), `recipientAddress` (address), `orderStatus` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, denormalized).
- **MaxAmountInContext**: Contains `reserveIn` (uint256), `decimalsIn` (uint8), `normalizedReserveIn` (uint256), `currentPrice` (uint256).
- **BuySwapContext**: Contains `listingContract` (ICCListing), `makerAddress` (address), `recipientAddress` (address), `status` (uint8), `tokenIn` (address), `tokenOut` (address), `decimalsIn` (uint8), `decimalsOut` (uint8), `denormAmountIn` (uint256), `denormAmountOutMin` (uint256), `price` (uint256), `expectedAmountOut` (uint256).
- **SellSwapContext**: Same as `BuySwapContext` for sell orders.
- **SwapImpactContext**: Contains `reserveIn` (uint256), `reserveOut` (uint256), `decimalsIn` (uint8), `decimalsOut` (uint8), `normalizedReserveIn` (uint256), `normalizedReserveOut` (uint256), `amountInAfterFee` (uint256), `price` (uint256), `amountOut` (uint256).

## Formulas
The formulas below govern Uniswap V2 swaps and price calculations, as implemented in `CCUniPartial.sol`. Simpler formulas like `principal / price = output` for buys and `principal * price = output` for sells are not compatible, as they ignore Uniswap V2's constant product formula, price impact, and 0.3% fee.

1. **Price Impact**:
   - **Formula**: `price = (inputAmount * 1e18) / amountOut`
   - **Used in**: `_computeSwapImpact`, `_checkPricing`, `_prepareSwapData`, `_prepareSellSwapData`.
   - **Description**: Calculates post-swap price using Uniswap V2 reserves after applying 0.3% fee. In `_computeSwapImpact`:
     - Fetches reserves via `IUniswapV2Pair.getReserves`.
     - Normalizes reserves to 18 decimals using `normalize`.
     - Computes `amountInAfterFee = (inputAmount * 997) / 1000`.
     - Computes `amountOut = (amountInAfterFee * normalizedReserveOut) / (normalizedReserveIn + amountInAfterFee)`.
     - Calculates `price = (inputAmount * 1e18) / amountOut`.
   - **Usage**:
     - **Pricing Validation**: In `_checkPricing`, compares `price` against order’s `maxPrice` and `minPrice`.
     - **Swap Preparation**: In `_prepareSwapData` and `_prepareSellSwapData`, computes `expectedAmountOut` and `denormAmountOutMin` for Uniswap V2 swaps.

2. **Buy Order Output**:
   - **Formula**: `amountOut = (amountInAfterFee * normalizedReserveOut) / (normalizedReserveIn + amountInAfterFee)`
   - **Used in**: `_executePartialBuySwap`, `_executeBuyTokenSwap`, `_executeBuyETHSwap`.
   - **Description**: Computes tokenA output for buy orders, applying Uniswap V2 constant product formula with 0.3% fee.

3. **Sell Order Output**:
   - **Formula**: Same as buy order output, with `tokenIn = tokenA`, `tokenOut = tokenB`.
   - **Used in**: `_executePartialSellSwap`, `_executeSellTokenSwap`, `_executeSellETHSwap`.
   - **Description**: Computes tokenB output for sell orders, using Uniswap V2 formula.

4. **Max Amount In**:
   - **Formula**: `maxAmountIn = (normalizedReserveIn * maxImpactPercent) / (100 * 2)`
   - **Used in**: `_computeMaxAmountIn`, `_processBuyOrder`, `_processSellOrder`.
   - **Description**: Calculates maximum input amount based on price constraints:
     - For buy: `maxImpactPercent = (maxPrice * 100e18 / currentPrice - 100e18) / 1e18`.
     - For sell: `maxImpactPercent = (currentPrice * 100e18 / minPrice - 100e18) / 1e18`.
     - Ensures `maxAmountIn <= pendingAmount`.

## External Functions

### settleBuyOrders(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Settles pending buy orders up to `maxIterations` using Uniswap V2 swaps, transferring tokenA to recipients, tracking `amountSent` (tokenA), and calling `listingContract.update` after successful swaps.
- **Internal Call Flow**:
  - Fetches `orderIdentifiers` via `pendingBuyOrdersView`.
  - Iterates up to `maxIterations`:
    - Calls `_processBuyOrder` for each order:
      - Fetches `(pendingAmount, filled, amountSent)` via `getBuyOrderAmounts`.
      - Validates pricing via `_checkPricing`, using `_computeSwapImpact` to ensure `price` is within `maxPrice` and `minPrice`.
      - Computes `maxAmountIn` via `_computeMaxAmountIn`, uses `swapAmount = min(maxAmountIn, pendingAmount)`.
      - Executes swap via `_executePartialBuySwap`, using `_executeBuyETHSwap` (if `tokenIn == address(0)`) or `_executeBuyTokenSwap`.
      - Creates `UpdateType[]` with `amountSent` and updated status (3 if fully filled, 2 if partial).
  - Collects updates in `tempUpdates`, resizes to `finalUpdates`, and applies via `listingContract.update`.
- **Balance Checks**:
  - Pre/post balance checks in `_executeBuyETHSwap` and `_executeBuyTokenSwap` ensure `amountReceived > 0`.
- **Mappings/Structs Used**:
  - **Structs**: `BuySwapContext`, `ICCListing.UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Skips orders with zero pending amount, invalid pricing, or failed swaps.
- **Gas Usage Controls**: `maxIterations` limits iteration, dynamic array resizing, try-catch for swaps.

### settleSellOrders(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyOrders`.
- **Behavior**: Settles pending sell orders up to `maxIterations` using Uniswap V2 swaps, transferring tokenB to recipients, tracking `amountSent` (tokenB), and calling `listingContract.update` after successful swaps.
- **Internal Call Flow**:
  - Similar to `settleBuyOrders`, using `pendingSellOrdersView` and `_processSellOrder`.
  - Executes swap via `_executePartialSellSwap`, using `_executeSellETHSwap` (if `tokenOut == address(0)`) or `_executeSellTokenSwap`.
- **Balance Checks**: Same as `settleBuyOrders`.
- **Mappings/Structs Used**:
  - **Structs**: `SellSwapContext`, `ICCListing.UpdateType`.
- **Restrictions**: Same as `settleBuyOrders`.
- **Gas Usage Controls**: Same as `settleBuyOrders`.

### setAgent(address newAgent)
- **Parameters**:
  - `newAgent` (address): New ICCAgent address.
- **Behavior**: Updates `agent` state variable for listing validation, inherited from `CCMainPartial`.
- **Internal Call Flow**: Direct state update, validates `newAgent` is non-zero.
- **Mappings/Structs Used**:
  - **agent** (state variable): Stores ICCAgent address.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `newAgent` is zero (`"Invalid agent address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

### setUniswapV2Router(address newRouter)
- **Parameters**:
  - `newRouter` (address): New Uniswap V2 router address.
- **Behavior**: Updates `uniswapV2Router` state variable for swap operations, inherited from `CCMainPartial`.
- **Internal Call Flow**: Direct state update, validates `newRouter` is non-zero.
- **Mappings/Structs Used**:
  - **uniswapV2Router** (state variable): Stores Uniswap V2 router address.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `newRouter` is zero (`"Invalid router address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

## Clarifications and Nuances

### Uniswap V2 Integration
- **Swap Execution**: `settleBuyOrders` and `settleSellOrders` use Uniswap V2 swaps via `_executePartialBuySwap` and `_executePartialSellSwap`, supporting both token-to-token (`swapExactTokensForTokens`) and ETH-based swaps (`swapExactETHForTokens`, `swapExactTokensForETH`), with `listingContract.update` called after successful swaps.
- **Price Validation**: `_checkPricing` uses `_computeSwapImpact` to ensure swap price stays within `maxPrice` and `minPrice`, accounting for 0.3% Uniswap V2 fee.
- **Path Construction**: Swap paths are constructed with `tokenIn` and `tokenOut` based on order type, ensuring correct token pair ordering per Uniswap V2 pair (`token0`, `token1`).

### Decimal Handling
- **Normalization**: Amounts are normalized to 18 decimals using `normalize` (inherited from `CCMainPartial`) for consistent calculations across tokens with varying decimals (e.g., USDC with 6 decimals, ETH with 18 decimals).
- **Denormalization**: Input and output amounts are denormalized to native token decimals for transfers and swaps, using `denormalize`.
- **ETH Handling**: For ETH swaps (`tokenIn` or `tokenOut == address(0)`), decimals are set to 18, and `msg.value` is used for transfers.

### Order Settlement Mechanics
- **Partial Execution**: `_processBuyOrder` and `_processSellOrder` use `maxAmountIn` to limit swap amounts to `min(maxAmountIn, pendingAmount)`, enabling partial fills when price constraints limit execution.
- **Status Updates**: Orders are updated to status 3 (completed) if `normalizedReceived >= pendingAmount`, otherwise status 2 (partially filled).
- **Amount Tracking**: `amountSent` tracks input tokens transferred (tokenB for buy, tokenA for sell), while `amountReceived` and `normalizedReceived` track output tokens received.

### Gas Optimization
- **Max Iterations**: `maxIterations` limits loop iterations in all settlement functions, preventing gas limit issues.
- **Dynamic Arrays**: `tempUpdates` is oversized (`iterationCount * 2`) and resized to `finalUpdates` to minimize gas while collecting updates.
- **Helper Functions**: Complex logic is split into helpers (e.g., `_prepareSwapData`, `_executeBuyETHSwap`, `_computeSwapImpact`) to reduce stack depth and gas usage.
- **Try-Catch**: External calls (transfers, swaps) use try-catch to handle failures gracefully, returning empty `ICCListing.UpdateType[]` arrays.

### Security Measures
- **Reentrancy Protection**: All external functions use `nonReentrant` modifier.
- **Listing Validation**: `onlyValidListing` ensures `listingAddress` is registered with `ICCAgent`.
- **Safe Transfers**: `SafeERC20.safeTransferFrom` and `safeApprove` are used for token operations, handling non-standard ERC20 tokens.
- **Balance Checks**: Pre/post balance checks in `_executeBuyETHSwap`, `_executeBuyTokenSwap`, `_executeSellETHSwap`, and `_executeSellTokenSwap` ensure transfer success.
- **Router Validation**: Uniswap V2 router and pair addresses are validated as non-zero before use.
- **Safety**:
  - Explicit casting for interfaces (e.g., `ICCListing`, `IUniswapV2Router02`).
  - No inline assembly, using high-level Solidity.
  - Try-catch blocks for external calls (transfers, swaps).
  - Hidden state variables (`agent`, `uniswapV2Router`) accessed via `agentView` and `uniswapV2RouterView`.
  - Avoids reserved keywords and unnecessary virtual/override modifiers.

### Limitations and Assumptions
- **No Order Creation/Cancellation**: Unlike `CCOrderRouter`, `CCSettlementRouter` does not handle order creation (`createBuyOrder`, `createSellOrder`) or cancellation (`clearSingleOrder`, `clearOrders`).
- **No Payouts**: Long and short payout settlement (`settleLongPayouts`, `settleShortPayouts`, `settleLongLiquid`, `settleShortLiquid`) is not supported, handled in `CCCLiquidityRouter`.
- **No Liquidity Settlement**: Liquid settlement (`settleBuyLiquid`, `settleSellLiquid`) removed, handled in `CCLiquidRouter`.
- **No Liquidity Management**: Functions like `deposit`, `withdraw`, `claimFees`, and `changeDepositor` are absent, as `CCSettlementRouter` focuses on Uniswap V2 settlement.
- **Uniswap V2 Dependency**: Relies on a configured `uniswapV2Router` and valid `uniswapV2PairView` from `listingContract`.
- **Zero-Amount Handling**: Zero pending amounts or failed swaps return empty `ICCListing.UpdateType[]` arrays, ensuring no state changes for invalid operations.

### Differences from SSRouter
- **Scope**: `CCSettlementRouter` focuses on Uniswap V2-based settlements, omitting order creation, cancellation, payouts, liquidity management, and liquid settlements present in `SSRouter`.
- **Inheritance**: Inherits `CCSettlementPartial`, `CCUniPartial`, and `CCMainPartial` instead of `SSSettlementPartial` and `SSMainPartial`.
- **Uniswap V2**: Uses Uniswap V2 swaps for `settleBuyOrders` and `settleSellOrders`, unlike `SSRouter`’s internal pool calculations.
- **Functionality**: Lacks `createBuyOrder`, `createSellOrder`, `clearSingleOrder`, `clearOrders`, `deposit`, `withdraw`, `claimFees`, `changeDepositor`, `settleLongPayouts`, `settleShortPayouts`, `settleLongLiquid`, `settleShortLiquid`, `settleBuyLiquid`, `settleSellLiquid`.

## Additional Details
- **Decimal Handling**: Uses `normalize` and `denormalize` from `CCMainPartial` for 1e18 precision, with decimals fetched via `IERC20.decimals` or set to 18 for ETH.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: Uses `maxIterations`, dynamic arrays, helper functions, and try-catch for efficient execution.
- **Listing Validation**: `onlyValidListing` checks `ICCAgent.getListing` for listing integrity.
- **Token Usage**:
  - Buy orders: Input tokenB, output tokenA, `amountSent` tracks tokenA.
  - Sell orders: Input tokenA, output tokenB, `amountSent` tracks tokenB.
- **Events**: Relies on `listingContract` events for logging.
- **Uniswap V2 Input Parameters**:
  - **amountIn**: Set as `context.denormAmountIn`, denormalized from `amountIn` to match input token decimals.
  - **amountOutMin**: Set as `context.denormAmountOutMin`, calculated as `denormalize((amountIn * 1e18) / maxPrice, decimalsOut)`.
  - **path**: Array of `[tokenIn, tokenOut]`: Buy orders use `[tokenB, tokenA]`, sell orders use `[tokenA, tokenB]`.
  - **to**: Set to `context.recipientAddress` from `getBuyOrderCore` or `getSellOrderCore`.
  - **deadline**: Set to `block.timestamp + 300` (5 minutes).
  - **Token Approvals**: Uses `IERC20(tokenIn).safeApprove(uniswapV2Router, denormAmountIn)` for token-to-token swaps.
  - **ETH Transfers**: Uses `listingContract.transactNative{value: denormAmountIn}` for ETH swaps.
  - **Validation**: Checks non-zero `uniswapV2Router`, `uniswapV2PairView`, valid pricing, and non-zero reserves.
