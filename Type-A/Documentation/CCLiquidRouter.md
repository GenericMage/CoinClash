# CCLiquidRouter Contract Documentation

## Overview
The `CCLiquidRouter` contract (Solidity ^0.8.2) settles buy/sell orders using `ICCLiquidity`, inheriting `CCLiquidPartial`. It integrates with `ICCListing`, `ICCLiquidity`, `IERC20`, and `IUniswapV2Pair`. Features include a dynamic fee system (min 0.01%, max 10% based on liquidity usage ratio: `normalizedAmountSent / normalizedLiquidity`), user-specific settlement via `makerPendingOrdersView`, and gas-efficient iteration with `step` (starting index for partial batch processing, e.g., step=0 processes from first order, step=10 skips first 10). Uses `ReentrancyGuard`. Fees are deducted from `pendingAmount` (net '

System: Amount transferred), recorded in `xFees`/`yFees`, and incentivize liquidity provision by scaling with usage—higher liquidity reduces fees, encouraging additions to lower slippage. Liquidity updates: for buy orders, `pendingAmount` (tokenB) increases `yLiquid`, `amountOut` (tokenA) decreases `xLiquid`; for sell orders, `pendingAmount` (tokenA) increases `xLiquid`, `amountOut` (tokenB) decreases `yLiquid`. Historical updates capture pre-settlement snapshots to track volumes without double-counting.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.25 (updated 2025-09-24)

**Inheritance Tree:** `CCLiquidRouter` → `CCLiquidPartial` (v0.0.47) → `CCMainPartial` (v0.1.5)

**Compatibility:** `CCListingTemplate.sol` (v0.3.9), `ICCLiquidity.sol` (v0.0.5), `CCMainPartial.sol` (v0.1.5), `CCLiquidPartial.sol` (v0.0.47), `CCLiquidityTemplate.sol` (v0.1.20)

## Mappings
- None defined in `CCLiquidRouter`. Uses `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`, `makerPendingOrdersView`) for order tracking, filtering user-specific pending IDs (e.g., `makerPendingOrdersView(msg.sender)` returns array of uint256 orderIds sorted by creation, enabling `step`-based slicing for gas control).

## Structs
- **HistoricalUpdateContext** (`CCLiquidRouter`): Holds `xBalance`, `yBalance`, `xVolume`, `yVolume` (uint256) for snapshotting live volumes before batch processing.
- **OrderContext** (`CCLiquidPartial`): Holds `listingContract` (ICCListing), `tokenIn`, `tokenOut` (address) for swap direction in `_processSingleOrder`.
- **PrepOrderUpdateResult** (`CCLiquidPartial`): Holds `tokenAddress`, `makerAddress`, `recipientAddress` (address), `tokenDecimals`, `status` (uint8), `amountReceived`, `normalizedReceived`, `amountSent`, `preTransferWithdrawn` (uint256); captures transfer outcomes for `BuyOrderUpdate`/`SellOrderUpdate` in `_prepBuy/SellOrderUpdate`.
- **BuyOrderUpdateContext** (`CCLiquidPartial`): Holds `makerAddress`, `recipient` (address), `status` (uint8), `amountReceived`, `normalizedReceived`, `amountSent`, `preTransferWithdrawn` (uint256) for buy-specific prep in `_prepBuyLiquidUpdates`.
- **SellOrderUpdateContext** (`CCLiquidPartial`): Holds `makerAddress`, `recipient` (address), `status` (uint8), `amountReceived`, `normalizedReceived`, `amountSent`, `preTransferWithdrawn` (uint256) for sell-specific prep in `_prepSellLiquidUpdates`.
- **OrderBatchContext** (`CCLiquidPartial`): Holds `listingAddress` (address), `maxIterations` (uint256), `isBuyOrder` (bool) for batch limits in `_processOrderBatch`.
- **SwapImpactContext** (`CCLiquidPartial`): Holds `reserveIn`, `reserveOut`, `amountInAfterFee`, `price`, `amountOut` (uint256), `decimalsIn`, `decimalsOut` (uint8) for impact calcs in `_computeSwapImpact`.
- **FeeContext** (`CCLiquidPartial`): Holds `feeAmount`, `netAmount`, `liquidityAmount` (uint256), `decimals` (uint8) for usage-based fees in `_computeFee`.
- **OrderProcessingContext** (`CCLiquidPartial`): Holds `maxPrice`, `minPrice`, `currentPrice`, `impactPrice` (uint256) for validation in `_validateOrderPricing`.
- **LiquidityUpdateContext** (`CCLiquidPartial`): Holds `pendingAmount`, `amountOut` (uint256), `tokenDecimals` (uint8), `isBuyOrder` (bool) for updates in `_prepareLiquidityUpdates`.

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

6.  **Fee Calculation**:
    * **Formula**:
        * `usagePercent = (normalize(amountOut, decimalsOut) * 1e18) / normalize(outputLiquidity, decimalsOut)`.
        * `feePercent = usagePercent / 10`.
        * `feePercent = max(1e14, min(1e17, feePercent))` (clamped between 0.01% and 10%).
        * `feeAmount = (pendingAmount * feePercent) / 1e18`; `netAmount = pendingAmount - feeAmount`.
    * **Used in**: `_computeFee` (called by `_processSingleOrder` → `_executeOrderWithFees`).
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
  - `listingAddress` (address): Target `ICCListing` for tokenA/tokenB pair; validated via `onlyValidListing` (checks `ICCAgent.isValidListing` for non-zero liquidity/token mismatch).
  - `maxIterations` (uint256): Caps processed orders per call (e.g., 5 for gas ~500k); prevents DoS.
  - `step` (uint256): Offset into `makerPendingOrdersView` array (e.g., step=0 starts at index 0, step=5 resumes from 5th order).
- **Behavior**: User-initiated batch settlement of pending buy orders (tokenB in for tokenA out). Filters `msg.sender`'s orders; skips if none or `step >= length`. Ensures `yBalance > 0` (volumeBalances); snapshots history if orders exist. Processes via `_processOrderBatch`, building `BuyOrderUpdate[]` for `ccUpdate` (status: 3 if fully filled via `preTransferWithdrawn >= pendingAmount`, 2 partial, 0 cancelled on skip/failure). Partial fills complete existing (status 2 from e.g., `CCListingTemplate`), but new orders assume full `pendingAmount`.
- **Internal Call Flow**:
  - `onlyValidListing` → `makerPendingOrdersView(msg.sender)` → check length/step/yBalance.
  - If orders: `_createHistoricalUpdate` (fetches `volumeBalances(0)`, `prices(0)`, last `HistoricalData` for volumes; `ccUpdate` with `HistoricalUpdate`).
  - `_processOrderBatch(true, step)`: `_collectOrderIdentifiers` (slices array from `step`, limits to `maxIterations`) → loop: `getBuyOrderAmounts` (pendingAmount) → if >0: `_processSingleOrder`:
    - `getBuyOrderCore/Pricing` → `_validateOrderPricing` (`_computeCurrentPrice`, `_computeSwapImpact` for impactPrice).
    - Liquidity check: `liquidityAmounts` vs. normalize(pendingAmount, decimalsB), normalize(amountOut, decimalsA).
    - `_computeFee` (usage ratio: `amountSent/liquidityAmount`) → `_prepBuyOrderUpdate` (pre/post balance for `amountSent` tokenA to recipient; `preTransferWithdrawn` from maker tokenB).
    - `_executeOrderWithFees`: Emit `FeeDeducted`; `_computeSwapAmount`; `_prepareLiquidityUpdates` (transfer pendingAmount to liquidity, single `ccUpdate`s for yLiquid+/xLiquid-/yFees+); snapshot `HistoricalUpdate` (current volumes, no increment); `executeSingleBuyLiquid` (`_prepBuyLiquidUpdates` → `_createBuyOrderUpdates` → `ccUpdate` with updates).
- **Emits**: `NoPendingOrders` (no orders/invalid step), `InsufficientBalance` (yBalance=0 or liquidity short), `UpdateFailed` (batch fail), `PriceOutOfBounds` (pricing skip), `FeeDeducted` (per order).
- **Graceful Degradation**: Non-reverting skips (e.g., pricing/liquidity issues emit events, return false in `_processSingleOrder`); try-catch in `ccUpdate` emits `UpdateFailed` reason.
- **Note**: `amountSent` tracks cumulative tokenA to recipient; interacts with `CCListingTemplate` for order creation, `CCLiquidityTemplate` for fee accrual.

### settleSellLiquid(address listingAddress, uint256 maxIterations, uint256 step)
- **Parameters**: Identical to `settleBuyLiquid`.
- **Behavior**: Batch settlement of pending sell orders (tokenA in for tokenB out). Filters `msg.sender`'s orders; skips if none or `step >= length`. Ensures `xBalance > 0`; snapshots history. Builds `SellOrderUpdate[]` for `ccUpdate` (status logic mirrors buy). Complements existing partials.
- **Internal Call Flow**: Mirrors `settleBuyLiquid`, but: xBalance check; `_processOrderBatch(false)`: `getSellOrderAmounts/Core/Pricing`; liquidity vs. normalize(pendingAmount, decimalsA)/normalize(amountOut, decimalsB); `_prepSellOrderUpdate` (`amountSent` tokenB); `_prepareLiquidityUpdates` (xLiquid+/yLiquid-/xFees+); `executeSingleSellLiquid` (`_prepSellLiquidUpdates` → `_createSellOrderUpdates`).
- **Emits**: As `settleBuyLiquid`, but sell-specific.
- **Graceful Degradation**: Identical.
- **Note**: `amountSent` cumulative tokenB; fee scaling incentivizes xLiquid additions to cap at 10%.

## Internal Functions (CCLiquidPartial, v0.0.47)
- **_getSwapReserves**: Builds `SwapImpactContext` from Uniswap pair `balanceOf` (token0/tokenB aware); called in `_computeSwapImpact` for live reserves.
- **_computeCurrentPrice**: Try-catch fetch `prices(0)`; in `_validateOrderPricing` for bounds check.
- **_computeSwapImpact**: Fee-adjusted output/price sim; in validation/swaps for `amountOut`.
- **_getTokenAndDecimals**: Returns token/decimals for direction; in fee/liquidity calcs.
- **_checkPricing** (unused in v0.0.47; legacy): Early bounds check.
- **_computeAmountSent**: Pre-balance snapshot; in `_prepBuy/SellOrderUpdate` for `amountSent` delta.
- **_prepareLiquidityTransaction** (truncated in doc; internal): Simulates out; in legacy paths.
- **_validateOrderPricing**: Builds `OrderProcessingContext`, checks bounds/current vs. impact; emits skip in `_processSingleOrder`.
- **_computeFee**: Ratio-based (`amountSent/liquidityAmount`) with min/max clamps; in `_processSingleOrder` for `FeeContext`.
- **_computeSwapAmount**: Nets `amountOut` post-fee; in `_executeOrderWithFees` for `LiquidityUpdateContext`.
- **_toSingleUpdateArray**: Wraps single `UpdateType`; in `_prepareLiquidityUpdates` for atomic `ccUpdate`.
- **_prepareLiquidityUpdates**: Validates liquidity, transfers input, single `ccUpdate`s for liquid/fees; reverts critical (e.g., update/transfer fail); in `_executeOrderWithFees`.
- **_executeOrderWithFees**: Emits fee, updates liquidity/history, executes single order; reverts on exec fail; core of `_processSingleOrder`.
- **_processSingleOrder**: Full validation/fee/exec flow, skips non-crit; returns success per order in `_processOrderBatch`.
- **_processOrderBatch**: Slices identifiers, loops processing; aggregates success in external settle.
- **_finalizeUpdates**: Resizes update arrays by type; in `_createBuy/SellOrderUpdates` for `ccUpdate`.
- **uint2str**: Utils string for errors; in emits.

## Internal Functions (CCLiquidRouter)
- **_createHistoricalUpdate**: Snapshot volumes/prices for `HistoricalUpdate`; called pre-batch in settle if orders.

## Security Measures
- **Reentrancy Protection**: `nonReentrant` on settles.
- **Listing Validation**: `onlyValidListing` try-catch `isValidListing`, checks details (non-zero, token diff).
- **Safe Transfers**: Pre/post `balanceOf`/`.balance` in `_prepBuy/SellOrderUpdate` for exact `amountSent`.
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
