# CCLiquidRouter Contract Documentation

## Overview
The `CCLiquidRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform using `ICCLiquidity` for liquid settlement. It inherits from `CCLiquidPartial`, which extends `CCMainPartial`, and integrates with `ICCListing`, `ICCLiquidity`, `IERC20`, and `IUniswapV2Pair` for token operations and reserve data. It uses `ReentrancyGuard` (including `Ownable`) for security. The contract handles liquid settlement via `settleBuyLiquid` and `settleSellLiquid`, ensuring price impact stays within order bounds. State variables are hidden, accessed via view functions, and decimal precision is maintained. It avoids reserved keywords, uses explicit casting, and ensures graceful degradation with revert reasons. Transfers call `listingContract.update` post-liquidity transfer.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.9 (updated 2025-08-18)

**Inheritance Tree:** `CCLiquidRouter` → `CCLiquidPartial` → `CCMainPartial`

**Compatibility:** CCListingTemplate.sol (v0.1.8), ICCLiquidity.sol (v0.0.4), CCMainPartial.sol (v0.0.14), CCLiquidPartial.sol (v0.0.14), CCLiquidityRouter.sol (v0.0.25), CCLiquidityTemplate.sol (v0.1.1).

## Mappings
- None defined in `CCLiquidRouter`. Uses `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`) for order tracking.

## Structs
- **OrderContext** (`CCLiquidPartial`): Holds `listingContract` (ICCListing), `tokenIn` (address), `tokenOut` (address), `liquidityAddr` (address).
- **PrepOrderUpdateResult** (`CCLiquidPartial`): Holds `tokenAddress` (address), `tokenDecimals` (uint8), `makerAddress` (address), `recipientAddress` (address), `orderStatus` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, denormalized).
- **BuyOrderUpdateContext** (`CCLiquidPartial`): Holds `makerAddress` (address), `recipient` (address), `status` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, tokenA for buy).
- **SellOrderUpdateContext** (`CCLiquidPartial`): Same as `BuyOrderUpdateContext`, with `amountSent` (tokenB for sell).
- **OrderBatchContext** (`CCLiquidPartial`): Holds `listingAddress` (address), `maxIterations` (uint256), `isBuyOrder` (bool).
- **SwapImpactContext** (`CCLiquidPartial`): Holds `reserveIn` (uint256), `reserveOut` (uint256), `decimalsIn` (uint8), `decimalsOut` (uint8), `normalizedReserveIn` (uint256), `normalizedReserveOut` (uint256), `amountInAfterFee` (uint256), `price` (uint256), `amountOut` (uint256).

## Formulas
Formulas in `CCLiquidPartial.sol` govern settlement and price impact calculations.

1. **Current Price**:
   - **Formula**: `price = (normalizedReserveB * 1e18) / normalizedReserveA`
   - **Used in**: `_computeCurrentPrice`, `_processSingleOrder`.
   - **Description**: Computes price as `reserveB / reserveA` (aligned with `CCListingTemplate.sol` v0.1.8) using normalized reserves. Ensures settlement price is within `minPrice` and `maxPrice`.
   - **Usage**: Validates if current price allows settlement in `_processSingleOrder`.

2. **Swap Impact**:
   - **Formula**:
     - `amountInAfterFee = (inputAmount * 997) / 1000` (0.3% Uniswap V2 fee).
     - `amountOut = (amountInAfterFee * normalizedReserveOut) / (normalizedReserveIn + amountInAfterFee)`.
     - `price = (normalizedReserveIn + amountInAfterFee) * 1e18 / (normalizedReserveOut - amountOut)`.
   - **Used in**: `_computeSwapImpact`, `_processSingleOrder`, `_checkPricing`.
   - **Description**: Calculates output and hypothetical price impact for buy (input tokenB, output tokenA) or sell (input tokenA, output tokenB) orders, ensuring `minPrice <= price <= maxPrice`.
   - **Usage**: Restricts settlement if price impact exceeds bounds.

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
   - **Used in**: `_getSwapReserves`, `_computeSwapImpact`, `_prepBuy/SellOrderUpdate`.
   - **Description**: Ensures 18-decimal precision for calculations, reverting to native decimals for transfers.

## External Functions

### settleBuyLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): `ICCListing` contract address for order book.
  - `maxIterations` (uint256): Limits orders processed to control gas.
- **Behavior**: Settles up to `maxIterations` pending buy orders, transferring tokenA to recipients, updating liquidity with tokenB via `ICCLiquidity.update`, and calling `listingContract.update`. Ensures price impact (`_computeSwapImpact`) and current price (`_computeCurrentPrice`) are within `minPrice` and `maxPrice`.
- **Internal Call Flow**:
  - `_processOrderBatch`:
    - Creates `OrderBatchContext` (`listingAddress`, `maxIterations`, `isBuyOrder = true`).
    - Calls `_collectOrderIdentifiers` to fetch `orderIdentifiers` via `pendingBuyOrdersView`.
    - Iterates up to `iterationCount`:
      - Fetches `(pendingAmount, , )` via `getBuyOrderAmounts`.
      - Calls `_processSingleOrder`:
        - Fetches `(maxPrice, minPrice)` via `getBuyOrderPricing`.
        - Computes `currentPrice` via `_computeCurrentPrice`.
        - Computes `impactPrice`, `amountOut` via `_computeSwapImpact`.
        - If `minPrice <= {currentPrice, impactPrice} <= maxPrice`, calls `executeSingleBuyLiquid`:
          - Fetches `(pendingAmount, , )` via `getBuyOrderAmounts`.
          - Calls `_prepBuyLiquidUpdates`:
            - Validates pricing via `_checkPricing`.
            - Calls `_prepareLiquidityTransaction` to compute `amountOut` and check `yAmount` (tokenB liquidity).
            - Calls `_prepBuyOrderUpdate` for transfer (`transactNative` or `transactToken`) with pre/post balance checks.
            - Returns `UpdateType[]` via `_createBuyOrderUpdates`.
          - Updates liquidity via `ICCLiquidity.update` with `depositor = address(this)`.
    - Resizes updates via `_finalizeUpdates` and calls `listingContract.update`.

### settleSellLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyLiquid`.
- **Behavior**: Settles sell orders, transferring tokenB, updating liquidity with tokenA, and calling `listingContract.update`. Uses `executeSingleSellLiquid`, `_prepSellLiquidUpdates`.
- **Internal Call Flow**: Mirrors `settleBuyLiquid`, with `isBuyOrder = false`, using `getSellOrderAmounts`, `getSellOrderPricing`, and `_prepSellLiquidUpdates`.

## Internal Functions (CCLiquidPartial)
- **_getSwapReserves**: Fetches Uniswap V2 reserves (`reserve0`, `reserve1`) and normalizes to `SwapImpactContext`.
- **_computeCurrentPrice**: Computes `reserveB / reserveA` for current price.
- **_computeSwapImpact**: Calculates output and price impact with 0.3% fee.
- **_checkPricing**: Validates `impactPrice` within `minPrice` and `maxPrice`.
- **_prepareLiquidityTransaction**: Computes `amountOut`, checks liquidity (`xAmount` for sell, `yAmount` for buy).
- **_prepBuy/SellOrderUpdate**: Handles transfers with pre/post balance checks, returns `PrepOrderUpdateResult`.
- **_prepBuy/SellLiquidUpdates**: Validates pricing, computes `amountOut`, prepares `UpdateType[]`.
- **_createBuy/SellOrderUpdates**: Builds `UpdateType[]` for order updates.
- **_collectOrderIdentifiers**: Fetches order IDs up to `maxIterations`.
- **_processSingleOrder**: Validates prices, executes order, updates liquidity.
- **_processOrderBatch**: Iterates orders, collects updates.
- **_finalizeUpdates**: Resizes update array.
- **uint2str**: Converts uint to string for revert messages.

## Security Measures
- **Reentrancy Protection**: `nonReentrant` on `settleBuyLiquid`, `settleSellLiquid`.
- **Listing Validation**: `onlyValidListing` uses `ICCAgent.isValidListing` with try-catch.
- **Safe Transfers**: `IERC20` with balance checks in `_prepBuy/SellOrderUpdate`.
- **Safety**:
  - Explicit casting for interfaces.
  - No inline assembly.
  - Hidden state variables (`agent`, `uniswapV2Router`) accessed via `agentView`, `uniswapV2RouterView`.
  - Avoids reserved keywords, `virtual`/`override`.
  - Graceful degradation with revert reasons (e.g., "Invalid pricing").

## Limitations and Assumptions
- Relies on `ICCLiquidity` for settlements, not direct Uniswap V2 swaps.
- No order creation, cancellation, payouts, or liquidity management.
- Uses Uniswap V2 reserves for price impact, not actual swaps.
- Zero amounts or failed transfers return empty `UpdateType[]`.
- `depositor` set to `address(this)` in `ICCLiquidity` calls.

## Differences from CCSettlementRouter
- Focuses on `ICCLiquidity`-based settlements, excludes Uniswap V2 swaps.
- Inherits `CCLiquidPartial`, omits `CCUniPartial`, `CCSettlementPartial`.
- Uses helper functions (`_processOrderBatch`, `_processSingleOrder`) for stack management.
