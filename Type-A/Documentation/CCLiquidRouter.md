# CCLiquidRouter Contract Documentation

## Overview
The `CCLiquidRouter` contract (Solidity ^0.8.2) settles buy/sell orders using `ICCLiquidity`, inheriting `CCLiquidPartial`. It integrates with `ICCListing`, `ICCLiquidity`, `IERC20`, and `IUniswapV2Pair`. Features include a dynamic fee system (min 0.01%, max 10% based on liquidity usage ratio: `normalizedAmountSent / normalizedLiquidity`), user-specific settlement via `makerPendingOrdersView`, and gas-efficient iteration with `step` (starting index for partial batch processing, e.g., step=0 processes from first order, step=10 skips first 10). Uses `ReentrancyGuard`. Fees are deducted from `pendingAmount` (net '

System: Amount transferred), recorded in `xFees`/`yFees`, and incentivize liquidity provision by scaling with usage—higher liquidity reduces fees, encouraging additions to lower slippage. Liquidity updates: for buy orders, `pendingAmount` (tokenB) increases `yLiquid`, `amountOut` (tokenA) decreases `xLiquid`; for sell orders, `pendingAmount` (tokenA) increases `xLiquid`, `amountOut` (tokenB) decreases `yLiquid`. Historical updates capture pre-settlement snapshots to track volumes without double-counting.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.26 (updated 2025-09-26)

**Inheritance Tree:** `CCLiquidRouter` → `CCLiquidPartial` (v0.0.47) → `CCMainPartial` (v0.1.5)

**Compatibility:** `CCListingTemplate.sol` (v0.3.9), `ICCLiquidity.sol` (v0.0.5), `CCMainPartial.sol` (v0.1.5), `CCLiquidPartial.sol` (v0.0.47), `CCLiquidityTemplate.sol` (v0.1.20)

## Mappings
- None defined in `CCLiquidRouter`. Uses `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`, `makerPendingOrdersView`) for order tracking, filtering user-specific pending IDs (e.g., `makerPendingOrdersView(msg.sender)` returns array of uint256 orderIds sorted by creation, enabling `step`-based slicing for gas control).

## Structs
- **HistoricalUpdateContext** (`CCLiquidRouter`): Stores `xBalance`, `yBalance`, `xVolume`, `yVolume` (uint256) for volume snapshots.
- **OrderContext** (`CCLiquidPartial`): Holds `listingContract` (ICCListing), `tokenIn`, `tokenOut` (address) for swap direction.
- **PrepOrderUpdateResult** (`CCLiquidPartial`): Includes `tokenAddress`, `makerAddress`, `recipientAddress` (address), `tokenDecimals`, `status` (uint8), `amountReceived`, `normalizedReceived`, `amountSent`, `preTransferWithdrawn` (uint256).
- **BuyOrderUpdateContext** (`CCLiquidPartial`): Holds `makerAddress`, `recipient` (address), `status` (uint8), `amountReceived`, `normalizedReceived`, `amountSent`, `preTransferWithdrawn` (uint256) for buy orders.
- **SellOrderUpdateContext** (`CCLiquidPartial`): Mirrors `BuyOrderUpdateContext` for sell orders.
- **OrderBatchContext** (`CCLiquidPartial`): Stores `listingAddress` (address), `maxIterations` (uint256), `isBuyOrder` (bool) for batch limits.
- **SwapImpactContext** (`CCLiquidPartial`): Holds `reserveIn`, `reserveOut`, `amountInAfterFee`, `price`, `amountOut` (uint256), `decimalsIn`, `decimalsOut` (uint8).
- **FeeContext** (`CCLiquidPartial`): Includes `feeAmount`, `netAmount`, `liquidityAmount` (uint256), `decimals` (uint8).
- **OrderProcessingContext** (`CCLiquidPartial`): Holds `maxPrice`, `minPrice`, `currentPrice`, `impactPrice` (uint256).
- **LiquidityUpdateContext** (`CCLiquidPartial`): Includes `pendingAmount`, `amountOut` (uint256), `tokenDecimals` (uint8), `isBuyOrder` (bool).
- **FeeCalculationContext** (`CCLiquidPartial`, v0.0.48): Stores `outputLiquidityAmount`, `normalizedAmountSent`, `normalizedLiquidity` (uint256), `outputDecimals` (uint8).

## Formulas
Formulas in `CCLiquidPartial.sol` (v0.0.47) govern settlement, pricing, and fees, ensuring normalized 18-decimal precision.

1. **Current Price**:
   - **Formula**: `price = listingContract.prices(0)`.
   - **Used in**: `_computeCurrentPrice` (called by `_validateOrderPricing` in `_processSingleOrder`), `_createHistoricalUpdate`, `_executeOrderWithFees`.
   - **Description**: Fetches instantaneous price from `ICCListing.prices(0)` with try-catch; must satisfy `minPrice <= price <= maxPrice` for settlement. Integrates with Uniswap V2 reserves for impact-adjusted validation.
   - **Usage**: In external `settleBuy/SellLiquid`, triggers via `_processOrderBatch` → `_processSingleOrder` → `_validateOrderPricing`; emits `PriceOutOfBounds` if invalid, skipping order.

2. **Swap Impact**:
   - **Formula**:
     - `amountInAfterFee = (inputAmount * 997) / 1000` (0.3% Uniswap V2 fee).
     - `normalizedReserveIn/Out = normalize(reserveIn/Out, decimalsIn/Out)`.
     - `amountOut = (amountInAfterFee * normalizedReserveOut) / (normalizedReserveIn + amountInAfterFee)`.
     - `impactPrice = ((normalizedReserveIn + amountInAfterFee) * 1e18) / (normalizedReserveOut - amountOut)` (or max if division by zero).
   - **Used in**: `_computeSwapImpact` (called by `_validateOrderPricing`, "_computeSwapAmount`, `_prepBuy/SellLiquidUpdates` in `_processSingleOrder`).
   - **Description**: Simulates post-fee output and marginal price for buy (tokenB in, tokenA out) or sell (tokenA in, tokenB out) using live `balanceOf` on Uniswap V2 pair; reserves fetched via `_getSwapReserves` (token0-aware for pair ordering).
   - **Usage**: In `_processSingleOrder`, if `impactPrice` outside `[minPrice, maxPrice]`, emits `PriceOutOfBounds` and skips; denormalizes `amountOut` for liquidity checks/transfers.

3. **Buy Order Output**:
   - **Formula**: As in Swap Impact; `amountOut` (tokenA) ≈ `netAmount (tokenB) / impactPrice`, denormalized.
   - **Used in**: `_computeSwapImpact`, `_prepBuyLiquidUpdates` → `_processSingleOrder` → `executeSingleBuyLiquid`.
   - **Description**: Projects tokenA receivable for buy principal (tokenB), factoring 0.3% fee and slippage; used to validate `xLiquid >= normalize(amountOut)` before `_prepareLiquidityUpdates`.

4. **Sell Order Output**:
   - **Formula**: As in Swap Impact; `amountOut` (tokenB) ≈ `netAmount (tokenA) * impactPrice`, denormalized.
   - **Used in**: `_computeSwapImpact`, `_prepSellLiquidUpdates` → `_processSingleOrder` → `executeSingleSellLiquid`.
   - **Description**: Projects tokenB receivable for sell principal (tokenA); validates `yLiquid >= normalize(amountOut)`.

5. **Normalization/Denormalization**:
   - **Formula**:
     - Normalize: `if (decimals == 18) amount; else if (decimals < 18) amount * 10^(18 - decimals); else amount / 10^(decimals - 18)`.
     - Denormalize: `if (decimals == 18) amount; else if (decimals < 18) amount / 10^(18 - decimals); else amount * 10^(decimals - 18)`.
   - **Used in**: Across `_getSwapReserves`, `_computeSwapImpact`, `_computeFee`, `_prepareLiquidityUpdates`, `_prepBuy/SellOrderUpdate`, `_processSingleOrder`.
   - **Description**: Standardizes to 18 decimals for ratio calcs (e.g., fees, reserves); reverses for transfers (`amountOut`, `feeAmount`). Ensures precision across varying token decimals (queried via `decimalsA/B`).

6. **Fee Calculation**:
   - **Formula**:
     - `usagePercent = (normalize(amountOut, decimalsOut) * 1e18) / normalize(outputLiquidity, decimalsOut)`.
     - `feePercent = usagePercent / 10`.
     - `feePercent = max(1e14, min(1e17, feePercent))` (0.01%–10%).
     - `feeAmount = (pendingAmount * feePercent) / 1e18`; `netAmount = pendingAmount - feeAmount`.
   - **Used in**: `_computeFee` (via `_getLiquidityData`, `_computeFeePercent`, `_finalizeFee` in v0.0.48) → `_processSingleOrder` → `_executeOrderWithFees`.
    * **Description**: A dynamic fee is calculated based on the usage of the **output** liquidity pool (i.e., `xLiquid` for buys, `yLiquid` for sells). The fee percentage is **one-tenth** of the liquidity usage percentage, clamped between a **0.01% minimum** and a **10% maximum**. This incentivizes liquidity providers by scaling fees with slippage. For example, if an order requires `amountSent` of 100 from an available `outputLiquidity` of 120, the usage is 83.33%, resulting in an 8.333% fee.
    * **Usage**: The `feeAmount` is deducted from the user's input (`pendingAmount`) before the swap calculation. The fee is then added to the corresponding fee pool (`yFees` for buys, `xFees` for sells).

7. **Liquidity Updates**:
   - **Formula**:
     - Buy: `yLiquid += normalize(pendingAmount)` (index 1, updateType 0), `xLiquid -= normalize(amountOut)` (index 0, updateType 0), `yFees += normalize(feeAmount)` (index 1, updateType 1).
     - Sell: `xLiquid += normalize(pendingAmount)` (index 0, updateType 0), `yLiquid -= normalize(amountOut)` (index 1, updateType 0), `xFees += normalize(feeAmount)` (index 0, updateType 1).
   - **Used in**: `_prepareLiquidityUpdates` (via single `ccUpdate` calls) in `_executeOrderWithFees`.
   - **Description**: Atomic updates via `ICCLiquidity.ccUpdate` (depositor: `address(this)`); validates pre-update `liquidityAmounts()` sufficiency, reverts on failure. Transfers `pendingAmount` to liquidity via `transactToken` (ERC20) or `transactNative` (ETH).

## External Functions

### settleBuyLiquid(address listingAddress, uint256 maxIterations, uint256 step)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address; validated via `onlyValidListing`.
  - `maxIterations`: Limits orders processed per call (e.g., 5 for ~500k gas).
  - `step`: Starting index in `makerPendingOrdersView` array for gas-efficient partial processing.
- **Behavior**: Settles user’s pending buy orders (tokenB in, tokenA out). Checks `msg.sender`’s orders, skips if none or `step >= length`. Validates `yBalance > 0`. Snapshots history if orders exist. Processes via `_processOrderBatch`, building `BuyOrderUpdate[]` for `ccUpdate` (status: 3 if `pending <= 0`, 2 partial, 0 cancelled).
- **Internal Call Flow**:
  - `onlyValidListing` → `makerPendingOrdersView` → check `yBalance`.
  - If orders: `_createHistoricalUpdate` (`volumeBalances(0)`, `prices(0)`, last `HistoricalData`).
  - `_processOrderBatch` → `_collectOrderIdentifiers` → loop: `getBuyOrderAmounts` → `_processSingleOrder`:
    - `_validateOrderPricing` (`_computeCurrentPrice`, `_computeSwapImpact`).
    - Liquidity check: `yLiquid >= normalize(pendingAmount)`, `xLiquid >= normalize(amountOut)`.
    - `_computeFee` (`_getLiquidityData`, `_computeFeePercent`, `_finalizeFee`) → `_prepBuyOrderUpdate` (pre/post balance for `amountSent`).
    - `_executeOrderWithFees`: Emits `FeeDeducted`; updates liquidity (`_prepareLiquidityUpdates`); snapshots history; calls `executeSingleBuyLiquid`.
- **Emits**: `NoPendingOrders`, `InsufficientBalance`, `UpdateFailed`, `PriceOutOfBounds`, `FeeDeducted`.
- **Graceful Degradation**: Skips invalid orders (pricing/liquidity) with events; try-catch in `ccUpdate`.

### settleSellLiquid(address listingAddress, uint256 maxIterations, uint256 step)
- **Parameters**: As above.
- **Behavior**: Settles sell orders (tokenA in, tokenB out). Validates `xBalance > 0`. Mirrors buy logic with `SellOrderUpdate[]`.
- **Internal Call Flow**: Similar to `settleBuyLiquid`, but uses `getSellOrderAmounts/Core/Pricing`, updates `xLiquid+/yLiquid-/xFees+`, calls `executeSingleSellLiquid`.
- **Emits**: As above, sell-specific.
- **Graceful Degradation**: Identical.

## Internal Functions (CCLiquidPartial, v0.0.47)
- **_createBuyOrderUpdates(uint256 orderIdentifier, BuyOrderUpdateContext memory context, uint256 pendingAmount)**:
  - **Behavior**: Prepares `BuyOrderUpdate[]` for `ccUpdate`. Sets `structId=0` (core: maker, recipient, status) and `structId=2` (amounts: pending, filled, amountSent). Status: 3 if `pending <= 0` after subtracting `preTransferWithdrawn`, else 2 (partial). Uses pre/post balance checks from `_prepBuyOrderUpdate` for `amountSent`.
  - **Call Tree**: Called by `_prepBuyLiquidUpdates` → `_executeOrderWithFees` → `_processSingleOrder` → `_processOrderBatch` (from `settleBuyLiquid`).
  - **External Interaction**: Updates `ICCListing` via `ccUpdate` with `BuyOrderUpdate[]`.
- **_createSellOrderUpdates(uint256 orderIdentifier, SellOrderUpdateContext memory context, uint256 pendingAmount)**:
  - **Behavior**: Prepares `SellOrderUpdate[]` for `ccUpdate`. Mirrors buy logic, setting status (3 if `pending <= 0`, else 2) and `amountSent` (from `_prepSellOrderUpdate`).
  - **Call Tree**: Called by `_prepSellLiquidUpdates` → `_executeOrderWithFees` → `_processSingleOrder` → `_processOrderBatch` (from `settleSellLiquid`).
  - **External Interaction**: Updates `ICCListing` via `ccUpdate` with `SellOrderUpdate[]`.
- **_getSwapReserves**: Fetches Uniswap pair reserves; token0-aware.
- **_computeCurrentPrice**: Fetches `prices(0)` with try-catch.
- **_computeSwapImpact**: Calculates `amountOut`, `impactPrice`.
- **_getTokenAndDecimals**: Retrieves token/decimals by order type.
- **_computeAmountSent**: Captures pre-transfer balance.
- **_validateOrderPricing**: Checks price bounds; emits `PriceOutOfBounds`.
- **_computeFee**: Uses `_getLiquidityData`, `_computeFeePercent`, `_finalizeFee` for fees.
- **_computeSwapAmount**: Calculates post-fee `amountOut`.
- **_toSingleUpdateArray**: Wraps `UpdateType` for `ccUpdate`.
- **_prepareLiquidityUpdates**: Transfers input, updates liquidity/fees.
- **_executeOrderWithFees**: Manages fees, liquidity, history; executes single order.
- **_processSingleOrder**: Validates, computes fees, executes; skips non-critical issues.
- **_processOrderBatch**: Loops over order IDs; aggregates success.
- **_finalizeUpdates**: Resizes update arrays.
- **uint2str**: Converts uint to string for errors.

## Internal Functions (CCLiquidRouter)
- **_createHistoricalUpdate**: Snapshot volumes/prices for `HistoricalUpdate`; called pre-batch in settle if orders.

## Security Measures
- **Reentrancy Protection**: `nonReentrant` on settles.
- **Listing Validation**: `onlyValidListing` try-catch `isValidListing`, checks details (non-zero, token diff).
- **Safe Transfers**: Pre/post `balanceOf`/`.balance` in `_prepBuy/SellOrderUpdate` for exact `amountSent`.
Checks exact principal amount transferred from `CCLlistingTemplate` to `CCLiquidityTemplate` before updating `x/yLiquid`.
- **Safety**:
  - Explicit casts (e.g., `ICCListing(listingAddress)`).
  - No assembly; array resize via Solidity.
  - Public state via views; no caps on iterations (user `maxIterations`).
  - Graceful: Events for skips (e.g., `pendingAmount==0` skips in batch), try-catch `ccUpdate` emits reason.
  - No nested self-refs in structs; deps computed first.
  - Fee min/max prevent abuse (e.g., 0% on tiny orders, >10% uncapped).
  - `step` bounds-checked vs. array length.

## Limitations and Assumptions
- Relies on `ICCLiquidity` for updates, not direct swaps; assumes `transact*` handles approvals.
- Completes partials (status 2) but doesn't create; assumes `CCListingTemplate` sets initial pending.
- Reserves via `balanceOf` (not `getReserves` for accuracy in non-pair tokens).
- Zero/failed ops return false, no revert; `amountSent` cumulative, not per-fill.
- Depositor fixed to `this`; `step` user-managed for resumption.
- History per-batch start + per-order in exec (avoids double-volume).
- Fees scale to incentivize liquidity: e.g., doubling pool halves max fee, stabilizing large orders.
