# CCLiquidRouter Contract Documentation

## Overview
The `CCLiquidRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform using `ICCLiquidity` for liquid settlement. It inherits from `CCLiquidPartial`, which extends `CCMainPartial`, and integrates with `ICCListing`, `ICCLiquidity`, `IERC20`, and `IUniswapV2Pair` for token operations and reserve data. It uses `ReentrancyGuard` (including `Ownable`) for security. The contract handles liquid settlement via `settleBuyLiquid` and `settleSellLiquid`, ensuring _

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.13 (updated 2025-08-21)

**Inheritance Tree:** `CCLiquidRouter` → `CCLiquidPartial` → `CCMainPartial`

**Compatibility:** CCListingTemplate.sol (v0.1.8), ICCLiquidity.sol (v0.0.4), CCMainPartial.sol (v0.0.14), CCLiquidPartial.sol (v0.0.17), CCLiquidityRouter.sol (v0.0.27), CCLiquidityTemplate.sol (v0.1.1).

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
   - **Formula**: `price = listingContract.prices(0)`
   - **Used in**: `_computeCurrentPrice`, `_processSingleOrder`.
   - **Description**: Fetches price from `ICCListing.prices(0)`, ensuring settlement price is within `minPrice` and `maxPrice`. Validates non-zero price.
   - **Usage**: Ensures settlement price aligns with listing template in `_processSingleOrder`.

2. **Swap Impact**:
   - **Formula**:
     - `amountInAfterFee = (inputAmount * 997) / 1000` (0.3% Uniswap V2 fee).
     - `amountOut = (amountInAfterFee * normalizedReserveOut) / (normalizedReserveIn + amountInAfterFee)`.
     - `price = ((normalizedReserveIn + amountInAfterFee) * 1e18) / (normalizedReserveOut - amountOut)`.
   - **Used in**: `_computeSwapImpact`, `_processSingleOrder`, `_checkPricing`.
   - **Description**: Calculates output and hypothetical price impact for buy (input tokenB, output tokenA) or sell (input tokenA, output tokenB) orders using `balanceOf` for Uniswap V2 LP reserves, ensuring `minPrice <= price <= maxPrice`.
   - **Usage**: Restricts settlement if price impact exceeds bounds; emits `PriceOutOfBounds` for graceful degradation.

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
- **Behavior**: Settles up to `maxIterations` pending buy orders by transferring principal (tokenB) to the liquidity contract via `ICCListing.transactToken` or `transactNative`, and settlement (tokenA) to recipients via `ICCLiquidity.transactToken` or `transactNative`. Checks liquidity via `listingVolumeBalancesView` (yBalance). Emits `NoPendingOrders` or `InsufficientBalance` and returns if no orders or insufficient yBalance. Updates liquidity with tokenB via `ICCLiquidity.update` and calls `listingContract.update`. Ensures price impact (`_computeSwapImpact`) and current price (`_computeCurrentPrice`) are within `minPrice` and `maxPrice`.
- **Internal Call Flow**:
  - Checks `pendingBuyOrdersView` for orders; emits `NoPendingOrders` if empty.
  - Fetches `(xBalance, yBalance, xVolume, yVolume)` via `listingVolumeBalancesView`; emits `InsufficientBalance` if `yBalance == 0`.
  - Calls `_processOrderBatch`:
    - Creates `OrderBatchContext` (`listingAddress`, `maxIterations`, `isBuyOrder = true`).
    - Calls `_collectOrderIdentifiers` to fetch `orderIdentifiers` via `pendingBuyOrdersView`.
    - Iterates up to `iterationCount`:
      - Fetches `(pendingAmount, , )` via `getBuyOrderAmounts`.
      - Calls `_processSingleOrder`:
        - Fetches `(maxPrice, minPrice)` via `getBuyOrderPricing`.
        - Computes `currentPrice` via `_computeCurrentPrice` (uses `prices(0)`).
        - Computes `impactPrice`, `amountOut` via `_computeSwapImpact` (uses `balanceOf` reserves).
        - If `minPrice <= {currentPrice, impactPrice} <= maxPrice`, calls `executeSingleBuyLiquid`:
          - Fetches `(pendingAmount, , )` via `getBuyOrderAmounts`.
          - Calls `_prepBuyLiquidUpdates`:
            - Validates pricing via `_checkPricing`; emits `PriceOutOfBounds` if invalid.
            - Calls `_prepareLiquidityTransaction` to compute `amountOut` and check `yAmount` (tokenB liquidity).
            - Calls `_prepBuyOrderUpdate`:
              - Transfers principal (tokenB) to liquidity contract via `listingContract.transactToken` or `transactNative` with pre/post balance checks.
              - Transfers settlement (tokenA) to recipient via `liquidityContract.transactToken` or `transactNative`, capturing actual amount sent.
              - Returns `UpdateType[]` via `_createBuyOrderUpdates` (sets `addr = makerAddress` for registry update).
          - Updates liquidity via `ICCLiquidity.update` with `depositor = address(this)`.
        - Else, emits `PriceOutOfBounds` and returns empty `UpdateType[]`.
    - Resizes updates via `_finalizeUpdates` and calls `listingContract.update` if updates exist.
- **Graceful Degradation**: Returns without reverting if no orders, insufficient balance, or price out of bounds, emitting appropriate events.

### settleSellLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyLiquid`.
- **Behavior**: Settles sell orders by transferring principal (tokenA) to the liquidity contract via `ICCListing.transactToken` or `transactNative`, and settlement (tokenB) to recipients via `ICCLiquidity.transactToken` or `transactNative`. Checks liquidity via `listingVolumeBalancesView` (xBalance). Emits `NoPendingOrders` or `InsufficientBalance` and returns if no orders or insufficient xBalance. Updates liquidity with tokenA and calls `listingContract.update`. Uses `executeSingleSellLiquid`, `_prepSellLiquidUpdates`.
- **Internal Call Flow**: Mirrors `settleBuyLiquid`, with `isBuyOrder = false`, using `getSellOrderAmounts`, `getSellOrderPricing`, `_prepSellLiquidUpdates` (sets `addr = makerAddress` for registry update), and checking `xBalance`.
- **Graceful Degradation**: Same as `settleBuyLiquid`, with events for no orders or insufficient balance.

## Internal Functions (CCLiquidPartial)
- **_getSwapReserves**: Fetches Uniswap V2 reserves via `balanceOf` (`token0`, `tokenB`) and normalizes to `SwapImpactContext`.
- **_computeCurrentPrice**: Fetches price from `ICCListing.prices(0)`.
- **_computeSwapImpact**: Calculates output and price impact with 0.3% fee using `balanceOf` reserves.
- **_checkPricing**: Validates `impactPrice` within `minPrice` and `maxPrice`.
- **_prepareLiquidityTransaction**: Computes `amountOut`, checks liquidity (`xAmount` for sell, `yAmount` for buy).
- **_prepBuy/SellOrderUpdate**: Handles transfers (principal to liquidity, settlement to recipient) with pre/post balance checks, returns `PrepOrderUpdateResult`.
- **_prepBuy/SellLiquidUpdates**: Validates pricing, computes `amountOut`, prepares `UpdateType[]` with `addr = makerAddress`; emits `PriceOutOfBounds` if invalid.
- **_createBuy/SellOrderUpdates**: Builds `UpdateType[]` for order updates with `addr = makerAddress` for registry updates.
- **_collectOrderIdentifiers**: Fetches order IDs up to `maxIterations`.
- **_processSingleOrder**: Validates prices, executes order, updates liquidity; emits `PriceOutOfBounds` if invalid.
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
  - Graceful degradation with events (`NoPendingOrders`, `InsufficientBalance`, `PriceOutOfBounds`) and revert reasons (e.g., "Invalid pricing").
  - Sets `addr = makerAddress` in `UpdateType` structs for accurate registry updates.

## Limitations and Assumptions
- Relies on `ICCLiquidity` for settlements, not direct Uniswap V2 swaps.
- No order creation, cancellation, payouts, or liquidity management.
- Uses `balanceOf` for Uniswap V2 reserves for price impact, not actual swaps.
- Zero amounts, failed transfers, or invalid prices return empty `UpdateType[]`.
- `depositor` set to `address(this)` in `ICCLiquidity` calls.

## Differences from CCSettlementRouter
- Focuses on `ICCLiquidity`-based settlements, excludes Uniswap V2 swaps.
- Inherits `CCLiquidPartial`, omits `CCUniPartial`, `CCSettlementPartial`.
- Uses helper functions (`_processOrderBatch`, `_processSingleOrder`) for stack management.
- Emits events for graceful degradation (e.g., `NoPendingOrders`, `InsufficientBalance`).
