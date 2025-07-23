# CCSExecutionDriver Contract Documentation

## Overview
The `CCSExecutionDriver` contract, implemented in Solidity (^0.8.2), manages trading positions for long and short cross margin strategies, inheriting functionality from `CCSExecutionPartial` while integrating with external interfaces (`ISSListing`, `ISSLiquidityTemplate`, `ISSAgent`, `ICSStorage`, `ICCOrderRouter`) for position execution, margin management, and state updates. It uses `IERC20` for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The suite handles position closure, cancellation, margin adjustments, stop-loss/take-profit updates, and hyx-driven operations, with gas optimization and safety mechanisms. State variables are hidden, accessed via view functions, and decimal precision is maintained across tokens. All transfers to or from the listing correctly call the `ISSListing.update` function to reflect changes, as seen in `_transferMarginToListing` and `_updateListingMargin`. The suite supports immediate execution of market orders when `minEntryPrice` and `maxEntryPrice` are zero, aligning with `SSCrossDriver` behavior but using `ICSStorage` for state management. The `pullMargin` function restricts withdrawals to scenarios with no open or pending positions, optimizing gas by removing redundant `_updatePositionLiquidationPrices` calls.

**Inheritance Tree:** `CCSExecutionDriver` → `CCSExecutionPartial` → `ReentrancyGuard`, `Ownable`

**SPDX License:** BSL-1.1 - Peng Protocol 2025

**Version:** 0.0.10 (last updated 2025-07-23)

## State Variables
- **DECIMAL_PRECISION** (uint256, constant, public): Set to 1e18 for normalizing amounts and prices across token decimals (defined in `CCSExecutionPartial`).
- **agentAddress** (address, public): Stores the address of the ISSAgent contract for listing validation (defined in `CCSExecutionPartial`).
- **storageContract** (ICSStorage, public): Reference to the external storage contract for position and margin data (defined in `CCSExecutionPartial`).
- **orderRouter** (ICCOrderRouter, public): Reference to the external order router contract for position activation (defined in `CCSExecutionPartial`).
- **_hyxes** (mapping(address => bool), private): Tracks authorized hyx contracts for delegated operations (defined in `CCSExecutionDriver`).
- **_hyxList** (address[], private): Lists authorized hyx addresses (defined in `CCSExecutionDriver`).

## Mappings
- Defined in `ICSStorage` interface (inlined in `CCSExecutionPartial`):
  - **makerTokenMargin** (mapping(address => mapping(address => uint256))): Tracks normalized margin balances per maker and token.
  - **positionCore1** (mapping(uint256 => PositionCore1)): Stores core position data (positionId, listingAddress, makerAddress, positionType).
  - **positionCore2** (mapping(uint256 => PositionCore2)): Tracks position status (status1 for active, status2 for closed).
  - **priceParams1** (mapping(uint256 => PriceParams1)): Holds price data (minEntryPrice, maxEntryPrice, minPrice, priceAtEntry, leverage).
  - **priceParams2** (mapping(uint256 => PriceParams2)): Stores liquidation price.
  - **marginParams1** (mapping(uint256 => MarginParams1)): Manages margin details (initialMargin, taxedMargin, excessMargin, fee).
  - **marginParams2** (mapping(uint256 => MarginParams2)): Tracks initial loan amount.
  - **exitParams** (mapping(uint256 => ExitParams)): Stores exit conditions (stopLossPrice, takeProfitPrice, exitPrice).
  - **openInterest** (mapping(uint256 => OpenInterest)): Records leverage amount and timestamp.
  - **positionsByType** (mapping(uint8 => uint256[])): Lists position IDs by type (0 for long, 1 for short).
  - **pendingPositions** (mapping(address => mapping(uint8 => uint256[]))): Tracks pending position IDs by listing address and type.
  - **positionToken** (mapping(uint256 => address)): Maps position ID to margin token (tokenA for long, tokenB for short).
  - **longIOByHeight** (mapping(uint256 => uint256)): Tracks long open interest by block height.
  - **shortIOByHeight** (mapping(uint256 => uint256)): Tracks short open interest by block height.

## Structs
- Defined in `ICSStorage` interface (inlined in `CCSExecutionPartial`):
  - **PositionCore1**: Contains `positionId` (uint256), `listingAddress` (address), `makerAddress` (address), `positionType` (uint8: 0 for long, 1 for short).
  - **PositionCore2**: Includes `status1` (bool: active flag), `status2` (uint8: 0 for open, 1 for closed).
  - **PriceParams1**: Stores `minEntryPrice`, `maxEntryPrice`, `minPrice`, `priceAtEntry` (uint256, normalized), `leverage` (uint8).
  - **PriceParams2**: Holds `liquidationPrice` (uint256, normalized).
  - **MarginParams1**: Tracks `initialMargin`, `taxedMargin`, `excessMargin`, `fee` (uint256, normalized).
  - **MarginParams2**: Stores `initialLoan` (uint256, normalized).
  - **ExitParams**: Includes `stopLossPrice`, `takeProfitPrice`, `exitPrice` (uint256, normalized).
  - **OpenInterest**: Contains `leverageAmount` (uint256, normalized), `timestamp` (uint256).

## Formulas
Formulas align with `SSCrossDriver` specifications, adapted for `ICSStorage` updates:

1. **Fee Calculation**:
   - **Formula**: `fee = (initialMargin * (leverage - 1) * DECIMAL_PRECISION) / 100 / DECIMAL_PRECISION`
   - **Used in**: `prepEnterLong`, `prepEnterShort` (referenced but not implemented here).
   - **Description**: Computes fee based on leverage and margin, normalized.

2. **Taxed Margin**:
   - **Formula**: `taxedMargin = normalizeAmount(token, initialMargin) - fee`
   - **Used in**: `prepEnterLong`, `prepEnterShort` (referenced).
   - **Description**: Margin after fee deduction, normalized.

3. **Leverage Amount**:
   - **Formula**: `leverageAmount = normalizeAmount(token, initialMargin) * leverage`
   - **Used in**: `prepEnterLong`, `prepEnterShort` (referenced).
   - **Description**: Leveraged position size, normalized.

4. **Initial Loan (Long)**:
   - **Formula**: `initialLoan = leverageAmount / minPrice`
   - **Used in**: `_computeLoanAndLiquidationLong`.
   - **Description**: Loan for long positions based on minimum entry price.

5. **Initial Loan (Short)**:
   - **Formula**: `initialLoan = leverageAmount * minPrice`
   - **Used in**: `_computeLoanAndLiquidationShort`.
   - **Description**: Loan for short positions based on minimum entry price.

6. **Liquidation Price (Long)**:
   - **Formula**: `liquidationPrice = marginRatio < minPrice ? minPrice - marginRatio : 0`, where `marginRatio = makerTokenMargin[maker][tokenA] / leverageAmount`
   - **Used in**: `_computeLoanAndLiquidationLong`, `_updateLiquidationPrices`.
   - **Description**: Liquidation price for long positions, adjusted for margins.

7. **Liquidation Price (Short)**:
   - **Formula**: `liquidationPrice = minPrice + marginRatio`, where `marginRatio = makerTokenMargin[maker][tokenB] / leverageAmount`
   - **Used in**: `_computeLoanAndLiquidationShort`, `_updateLiquidationPrices`.
   - **Description**: Liquidation price for short positions, adjusted for margins.

8. **Payout (Long)**:
   - **Formula**: `payout = baseValue > initialLoan ? baseValue - initialLoan : 0`, where `baseValue = (taxedMargin + totalMargin + leverageAmount) / currentPrice`
   - **Used in**: `_computePayoutLong`, `_prepCloseLong`.
   - **Description**: Payout for long position closure in tokenB, normalized.

9. **Payout (Short)**:
   - **Formula**: `payout = profit + (taxedMargin + totalMargin) * currentPrice / DECIMAL_PRECISION`, where `profit = (priceAtEntry - currentPrice) * initialMargin * leverage`
   - **Used in**: `_computePayoutShort`, `_prepCloseShort`.
   - **Description**: Payout for short position closure in tokenA, normalized.

## External Functions
Functions are implemented in `CCSExecutionDriver` unless specified, with internal helpers in `CCSExecutionPartial`. All align with `SSCrossDriver` execution functions, adapted for `ICSStorage` and hyx instead of mux.

### setAgent(address newAgentAddress)
- **Contract**: `CCSExecutionPartial`
- **Parameters**: `newAgentAddress` (address): New ISSAgent address.
- **Behavior**: Updates `agentAddress` for listing validation.
- **Internal Call Flow**: Validates `newAgentAddress` is non-zero, assigns to `agentAddress`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **State Variable**: `agentAddress`.
- **Restrictions**: `onlyOwner`, reverts if `newAgentAddress` is zero (`"Invalid agent address"`).
- **Gas Usage Controls**: Minimal gas, single state write.

### setOrderRouter(address newOrderRouter)
- **Contract**: `CCSExecutionPartial`
- **Parameters**: `newOrderRouter` (address): New ICCOrderRouter address.
- **Behavior**: Updates `orderRouter` for position activation, callable post-deployment by owner.
- **Internal Call Flow**: Validates `newOrderRouter` is non-zero, assigns to `orderRouter` with explicit casting to `ICCOrderRouter`. No external calls or transfers.
- **Mappings/Structs Used**:
  - **State Variable**: `orderRouter`.
- **Restrictions**: `onlyOwner`, reverts if `newOrderRouter` is zero (`"Invalid order router address"`).
- **Gas Usage Controls**: Minimal gas, single state write.

### getOrderRouter()
- **Contract**: `CCSExecutionPartial`
- **Parameters**: None.
- **Behavior**: Returns the current `orderRouter` address.
- **Internal Call Flow**: Returns `address(orderRouter)`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **State Variable**: `orderRouter`.
- **Restrictions**: None, view function.
- **Gas Usage Controls**: Minimal gas, single read.

### addHyx(address hyx)
- **Contract**: `CCSExecutionDriver`
- **Parameters**: `hyx` (address): Hyx contract to authorize.
- **Behavior**: Authorizes a hyx contract for delegated operations, emits `HyxAdded`.
- **Internal Call Flow**: Validates `hyx` is non-zero and not authorized, sets `_hyxes[hyx] = true`, adds to `_hyxList`. No external calls or transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `_hyxes`, `_hyxList`.
- **Restrictions**: `onlyOwner`, reverts if `hyx` is zero (`"Invalid hyx address"`) or already authorized (`"Hyx already added"`).
- **Gas Usage Controls**: Minimal gas, single mapping and array update.

### removeHyx(address hyx)
- **Contract**: `CCSExecutionDriver`
- **Parameters**: `hyx` (address): Hyx contract to remove.
- **Behavior**: Revokes hyx authorization, emits `HyxRemoved`.
- **Internal Call Flow**: Validates `hyx` is authorized, sets `_hyxes[hyx] = false`, removes from `_hyxList` using pop-and-swap. No external calls or transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `_hyxes`, `_hyxList`.
- **Restrictions**: `onlyOwner`, reverts if `hyx` is not authorized (`"Hyx not found"`).
- **Gas Usage Controls**: Minimal gas, pop-and-swap for array.

### getHyxes()
- **Contract**: `CCSExecutionDriver`
- **Parameters**: None.
- **Behavior**: Returns array of authorized hyx addresses.
- **Internal Call Flow**: Returns `_hyxList`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `_hyxList`.
- **Restrictions**: None, view function.
- **Gas Usage Controls**: Minimal gas, array read.

### addExcessMargin(address listingAddress, bool tokenA, uint256 amount, address maker)
- **Contract**: `CCSExecutionDriver`
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `tokenA` (bool): True for tokenA, false for tokenB.
  - `amount` (uint256): Margin to add (denormalized).
  - `maker` (address): Margin owner.
- **Behavior**: Adds margin to `maker`’s balance, transfers to `listingAddress`, updates liquidation prices for all relevant positions, and records interest. No event emitted.
- **Internal Call Flow**:
  - Validates inputs (`amount > 0`, `maker`, `listingAddress` non-zero).
  - Calls `ISSAgent.isValidListing` (input: `listingAddress`, returns: `isValid`).
  - Selects token via `ISSListing.tokenA` or `tokenB`.
  - `_transferMarginToListing` transfers `amount` to `listingAddress` using `IERC20.transferFrom` (input: `address(this)`, `listingAddress`, `amount`, returns: `bool success`), with pre/post balance checks, followed by `_updateListingMargin` calling `ISSListing.update` (input: `UpdateType[]`, returns: none).
  - `_updateMakerMargin` updates `makerTokenMargin`, `makerMarginTokens`.
  - `_updatePositionLiquidationPrices` iterates `positionCount`, updating `priceParams2.liquidationPrice` for all positions of `maker` with matching `positionToken` and `listingAddress` using `_computeLoanAndLiquidationLong` or `_computeLoanAndLiquidationShort`.
  - `_updateHistoricalInterest` updates `longIOByHeight` (positionType = 0).
- **Balance Checks**:
  - **Pre-Balance Check**: `IERC20.balanceOf(listingAddress)` before transfer.
  - **Post-Balance Check**: `balanceAfter - balanceBefore == amount`.
- **Mappings/Structs Used**:
  - **Mappings**: `makerTokenMargin`, `makerMarginTokens`, `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `longIOByHeight`, `positionToken`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `PriceParams1`, `PriceParams2`.
- **Restrictions**: `nonReentrant`, reverts if `amount == 0`, `maker` or `listingAddress` is zero, listing is invalid, or transfer fails.
- **Gas Usage Controls**: Single transfer, pop-and-swap, full iteration for liquidation prices.

### pullMargin(address listingAddress, bool tokenA, uint256 amount)
- **Contract**: `CCSExecutionDriver`
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `tokenA` (bool): True for tokenA, false for tokenB.
  - `amount` (uint256): Margin to withdraw (denormalized).
- **Behavior**: Withdraws margin from `msg.sender`’s balance if no open or pending positions exist for the specified token and listing, transfers to `msg.sender`, records interest. No liquidation price update is performed, as the restriction ensures no relevant positions exist.
- **Internal Call Flow**:
  - `_validateAndNormalizePullMargin` validates inputs, checks listing, normalizes `amount`, ensures `normalizedAmount <= makerTokenMargin`.
  - Iterates `positionCount` to ensure no open or pending positions (`status2 == 0`) exist for `msg.sender` with matching `positionToken` and `listingAddress`, reverting if any are found (`"Cannot pull margin with open positions"`).
  - `_reduceMakerMargin` deducts `normalizedAmount` from `makerTokenMargin`, calls `removeToken` if zero.
  - `_executeMarginPayout` calls `ISSListing.ssUpdate` (input: `PayoutUpdate[]`, returns: none) to transfer `amount` to `msg.sender`.
  - `_updateHistoricalInterest` updates `shortIOByHeight` (positionType = 1).
- **Balance Checks**:
  - **Pre-Balance Check**: `normalizedAmount <= makerTokenMargin[msg.sender][token]`.
  - **Post-Balance Check**: None, handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `makerTokenMargin`, `makerMarginTokens`, `positionCore1`, `positionCore2`, `positionToken`, `shortIOByHeight`.
  - **Structs**: `PositionCore1`, `PositionCore2`.
- **Restrictions**: `nonReentrant`, reverts if `amount == 0`, listing is invalid, margin is insufficient, or open/pending positions exist for the token and listing.
- **Gas Usage Controls**: Minimal updates, pop-and-swap, full iteration for position check.

### updateSL(uint256 positionId, uint256 newStopLossPrice)
- **Contract**: `CCSExecutionDriver`
- **Parameters**:
  - `positionId` (uint256): Position ID.
  - `newStopLossPrice` (uint256): New stop-loss price (denormalized).
- **Behavior**: Updates stop-loss price, emits `StopLossUpdated`.
- **Internal Call Flow**:
  - Validates position in `positionCore1`, not closed (`positionCore2.status2 == 0`), owned by `msg.sender`.
  - Normalizes prices via `normalizePrice`, fetches `currentPrice` via `ISSListing.prices` (input: `listingAddress`, returns: `currentPrice`).
  - Calls `_updateSL` to set `exitParams.stopLossPrice` via `ICSStorage.CSUpdate`.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `exitParams`, `positionToken`, `priceParams1`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `ExitParams`, `PriceParams1`.
- **Restrictions**: `nonReentrant`, reverts if position is invalid, closed, not owned, or `newStopLossPrice` is invalid.
- **Gas Usage Controls**: Minimal gas, single `CSUpdate`.

### updateTP(uint256 positionId, uint256 newTakeProfitPrice)
- **Contract**: `CCSExecutionDriver`
- **Parameters**:
  - `positionId` (uint256): Position ID.
  - `newTakeProfitPrice` (uint256): New take-profit price (denormalized).
- **Behavior**: Updates take-profit price, emits `TakeProfitUpdated`.
- **Internal Call Flow**:
  - Validates position, not closed, owned by `msg.sender`.
  - Normalizes prices, fetches `currentPrice` via `ISSListing.prices`.
  - Validates `newTakeProfitPrice` (`> priceAtEntry` for long, `< priceAtEntry` for short, or `0`).
  - Calls `_updateTP` to set `exitParams.takeProfitPrice` via `CSUpdate`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: Same as `updateSL`.
- **Restrictions**: `nonReentrant`, reverts if position is invalid, closed, not owned, or `newTakeProfitPrice` is invalid.
- **Gas Usage Controls**: Minimal gas, single `CSUpdate`.

### closeLongPosition(uint256 positionId)
- **Contract**: `CCSExecutionDriver`
- **Parameters**:
  - `positionId` (uint256): Position ID to close.
- **Behavior**: Closes a single active long position, pays out in tokenB, updates liquidation prices for remaining positions, emits `PositionClosed`.
- **Internal Call Flow**:
  - Validates position in `positionCore1`, active (`status1 == true`), not closed (`status2 == 0`), owned by `msg.sender`.
  - Calls `_prepCloseLong`:
    - `_computePayoutLong` calculates payout in tokenB.
    - Updates `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `marginParams1`, `marginParams2`, `exitParams`, `openInterest`, `makerTokenMargin` via `CSUpdate`.
  - Calls `removePositionIndex` to update `positionsByType` and `pendingPositions`.
  - Calls `_updatePositionLiquidationPrices` to update `priceParams2.liquidationPrice` for remaining positions of `msg.sender` with matching `positionToken` (tokenA) and `listingAddress`.
  - Calls `ISSListing.ssUpdate` (input: `PayoutUpdate[]`, returns: none) for tokenB payout to `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `makerTokenMargin[maker][tokenA] >= taxedMargin + excessMargin`.
  - **Post-Balance Check**: None, handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `marginParams1`, `marginParams2`, `exitParams`, `openInterest`, `makerTokenMargin`, `makerMarginTokens`, `positionToken`, `positionsByType`, `pendingPositions`, `priceParams1`, `priceParams2`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `MarginParams1`, `MarginParams2`, `ExitParams`, `OpenInterest`, `PriceParams1`, `PriceParams2`.
- **Restrictions**: `nonReentrant`, reverts if position is invalid, closed, not active, or not owned.
- **Gas Usage Controls**: Minimal gas, single position processing, full iteration for liquidation prices.

### closeShortPosition(uint256 positionId)
- **Contract**: `CCSExecutionDriver`
- **Parameters**:
  - `positionId` (uint256): Position ID to close.
- **Behavior**: Closes a single active short position, pays out in tokenA, updates liquidation prices for remaining positions, emits `PositionClosed`.
- **Internal Call Flow**:
  - Validates position in `positionCore1`, active (`status1 == true`), not closed (`status2 == 0`), owned by `msg.sender`.
  - Calls `_prepCloseShort`:
    - `_computePayoutShort` calculates payout in tokenA.
    - Updates `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `marginParams1`, `marginParams2`, `exitParams`, `openInterest`, `makerTokenMargin` via `CSUpdate`.
  - Calls `removePositionIndex` to update `positionsByType` and `pendingPositions`.
  - Calls `_updatePositionLiquidationPrices` to update `priceParams2.liquidationPrice` for remaining positions of `msg.sender` with matching `positionToken` (tokenB) and `listingAddress`.
  - Calls `ISSListing.ssUpdate` (input: `PayoutUpdate[]`, returns: none) for tokenA payout to `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `makerTokenMargin[maker][tokenB] >= taxedMargin + excessMargin`.
  - **Post-Balance Check**: None, handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `marginParams1`, `marginParams2`, `exitParams`, `openInterest`, `makerTokenMargin`, `makerMarginTokens`, `positionToken`, `positionsByType`, `pendingPositions`, `priceParams1`, `priceParams2`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `MarginParams1`, `MarginParams2`, `ExitParams`, `OpenInterest`, `PriceParams1`, `PriceParams2`.
- **Restrictions**: `nonReentrant`, reverts if position is invalid, closed, not active, or not owned.
- **Gas Usage Controls**: Minimal gas, single position processing, full iteration for liquidation prices.

### closeAllLongs(uint256 maxIterations)
- **Contract**: `CCSExecutionDriver`
- **Parameters**:
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Closes all active long positions for `msg.sender`, pays out in tokenB, updates liquidation prices for remaining positions, emits `AllLongsClosed` and `PositionClosed` per position.
- **Internal Call Flow**:
  - Iterates `positionCount` up to `maxIterations`, processing long, active, non-closed positions owned by `msg.sender`.
  - Calls `_prepCloseLong`:
    - `_computePayoutLong` calculates payout in tokenB.
    - Updates `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `marginParams1`, `marginParams2`, `exitParams`, `openInterest`, `makerTokenMargin` via `CSUpdate`.
  - Calls `removePositionIndex` to update `positionsByType` and `pendingPositions`.
  - Calls `_updatePositionLiquidationPrices` to update `priceParams2.liquidationPrice` for remaining positions of `msg.sender` with matching `positionToken` (tokenA) and `listingAddress`.
  - Calls `ISSListing.ssUpdate` (input: `PayoutUpdate[]`, returns: none) for tokenB payout to `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `makerTokenMargin[maker][tokenA] >= taxedMargin + excessMargin`.
  - **Post-Balance Check**: None, handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `marginParams1`, `marginParams2`, `exitParams`, `openInterest`, `makerTokenMargin`, `makerMarginTokens`, `positionToken`, `positionsByType`, `pendingPositions`, `priceParams1`, `priceParams2`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `MarginParams1`, `MarginParams2`, `ExitParams`, `OpenInterest`, `PriceParams1`, `PriceParams2`.
- **Restrictions**: `nonReentrant`, skips non-matching positions.
- **Gas Usage Controls**: `maxIterations`, `gasleft() >= 50000`, pop-and-swap.

### cancelAllLongs(uint256 maxIterations)
- **Contract**: `CCSExecutionDriver`
- **Parameters**:
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Cancels all pending long positions for `msg.sender`, returns margins in tokenA, emits `AllLongsCancelled` and `PositionCancelled` per position.
- **Internal Call Flow**:
  - Iterates `positionCount` up to `maxIterations`, processing pending long positions.
  - Calls `_prepareCancelPosition` to validate position and compute `token`, `listingAddress`, `marginAmount`, `denormalizedAmount`.
  - Calls `_updatePositionParams` to update `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `exitParams`, `openInterest` via `CSUpdate`.
  - Calls `_updateMarginAndIndex` to update `makerTokenMargin` and `removePositionIndex`.
  - Calls `_executeCancelPosition` to transfer margin to `listingAddress` via `_transferMarginToListing`, update listing via `_updateListingMargin`, pay out via `_executeMarginPayout`, and emit `PositionCancelled`.
- **Balance Checks**:
  - **Pre-Balance Check**: `makerTokenMargin[maker][tokenA] >= taxedMargin + excessMargin` (implicit in `_prepareCancelPosition`).
  - **Post-Balance Check**: `IERC20.balanceOf(listingAddress)` after transfer in `_transferMarginToListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `marginParams1`, `priceParams1`, `priceParams2`, `exitParams`, `openInterest`, `makerTokenMargin`, `positionToken`, `positionsByType`, `pendingPositions`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `MarginParams1`, `PriceParams1`, `PriceParams2`, `ExitParams`, `OpenInterest`.
- **Restrictions**: `nonReentrant`, skips non-matching positions.
- **Gas Usage Controls**: `maxIterations`, `gasleft() >= 50000`, pop-and-swap.

### closeAllShorts(uint256 maxIterations)
- **Contract**: `CCSExecutionDriver`
- **Parameters**:
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Closes all active short positions for `msg.sender`, pays out in tokenA, updates liquidation prices for remaining positions, emits `AllShortsClosed` and `PositionClosed` per position.
- **Internal Call Flow**:
  - Iterates `positionCount` up to `maxIterations`, processing short, active, non-closed positions owned by `msg.sender`.
  - Calls `_prepCloseShort`:
    - `_computePayoutShort` calculates payout in tokenA.
    - Updates `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `marginParams1`, `marginParams2`, `exitParams`, `openInterest`, `makerTokenMargin` via `CSUpdate`.
  - Calls `removePositionIndex` to update `positionsByType` and `pendingPositions`.
  - Calls `_updatePositionLiquidationPrices` to update `priceParams2.liquidationPrice` for remaining positions of `msg.sender` with matching `positionToken` (tokenB) and `listingAddress`.
  - Calls `ISSListing.ssUpdate` (input: `PayoutUpdate[]`, returns: none) for tokenA payout to `msg.sender`, using `core1.listingAddress` for correct listing interaction.
- **Balance Checks**:
  - **Pre-Balance Check**: `makerTokenMargin[maker][tokenB] >= taxedMargin + excessMargin`.
  - **Post-Balance Check**: None, handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `marginParams1`, `marginParams2`, `exitParams`, `openInterest`, `makerTokenMargin`, `makerMarginTokens`, `positionToken`, `positionsByType`, `pendingPositions`, `priceParams1`, `priceParams2`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `MarginParams1`, `MarginParams2`, `ExitParams`, `OpenInterest`, `PriceParams1`, `PriceParams2`.
- **Restrictions**: `nonReentrant`, skips non-matching positions.
- **Gas Usage Controls**: `maxIterations`, `gasleft() >= 50000`, pop-and-swap.

### cancelAllShorts(uint256 maxIterations)
- **Contract**: `CCSExecutionDriver`
- **Parameters**:
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Cancels all pending short positions for `msg.sender`, returns margins in tokenB, emits `AllShortsCancelled` and `PositionCancelled` per position.
- **Internal Call Flow**:
  - Iterates `positionCount` up to `maxIterations`, processing pending short positions.
  - Calls `_prepareCancelPosition` to validate position and compute `token`, `listingAddress`, `marginAmount`, `denormalizedAmount`.
  - Calls `_updatePositionParams` to update `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `exitParams`, `openInterest` via `CSUpdate`.
  - Calls `_updateMarginAndIndex` to update `makerTokenMargin` and `removePositionIndex`.
  - Calls `_executeCancelPosition` to transfer margin to `listingAddress` via `_transferMarginToListing`, update listing via `_updateListingMargin`, pay out via `_executeMarginPayout`, and emit `PositionCancelled`.
- **Balance Checks**:
  - **Pre-Balance Check**: `makerTokenMargin[maker][tokenB] >= taxedMargin + excessMargin` (implicit in `_prepareCancelPosition`).
  - **Post-Balance Check**: `IERC20.balanceOf(listingAddress)` after transfer in `_transferMarginToListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `marginParams1`, `priceParams1`, `priceParams2`, `exitParams`, `openInterest`, `makerTokenMargin`, `positionToken`, `positionsByType`, `pendingPositions`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `MarginParams1`, `PriceParams1`, `PriceParams2`, `ExitParams`, `OpenInterest`.
- **Restrictions**: `nonReentrant`, skips non-matching positions.
- **Gas Usage Controls**: `maxIterations`, `gasleft() >= 50000`, pop-and-swap.

### cancelPosition(uint256 positionId)
- **Contract**: `CCSExecutionDriver`
- **Parameters**:
  - `positionId` (uint256): Position ID to cancel.
- **Behavior**: Cancels a single pending position, returns margins to `msg.sender`, emits `PositionCancelled`.
- **Internal Call Flow**:
  - Validates position in `positionCore1`, pending (`status1 == false`), not closed (`status2 == 0`), owned by `msg.sender`.
  - Computes `marginAmount = taxedMargin + excessMargin`, normalizes, transfers to `listingAddress` via `_transferMarginToListing`.
  - Updates `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `marginParams1`, `marginParams2`, `exitParams`, `openInterest`, `makerTokenMargin` via `CSUpdate`.
  - Calls `removePositionIndex`, pays out via `_executeMarginPayout` to `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `makerTokenMargin[maker][positionToken] >= taxedMargin + excessMargin`.
  - **Post-Balance Check**: `IERC20.balanceOf(listingAddress)` after transfer in `_transferMarginToListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `marginParams1`, `priceParams1`, `priceParams2`, `exitParams`, `openInterest`, `makerTokenMargin`, `positionToken`, `positionsByType`, `pendingPositions`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `MarginParams1`, `PriceParams1`, `PriceParams2`, `ExitParams`, `OpenInterest`.
- **Restrictions**: `nonReentrant`, reverts if position is invalid, closed, active, or not owned.
- **Gas Usage Controls**: Minimal gas, single position processing.

### executePositions(address listingAddress, uint256 maxIterations)
- **Contract**: `CCSExecutionDriver`
- **Parameters**:
  - `listingAddress` (address): The address of the listing contract managing the token pair.
  - `maxIterations` (uint256): The maximum number of positions to process in a single transaction to control gas usage.
- **Behavior**: Iterates through pending and active positions for both long and short types, updating liquidation prices for all relevant positions before processing, activating pending positions within price ranges or closing positions due to liquidation, stop-loss, or take-profit triggers, with payouts issued in tokenB for long positions and tokenA for short positions.
- **Internal Call Flow**:
  - Calls `_executePositions` (defined in `CCSExecutionPartial`):
    - **Validation**: Ensures `listingAddress` is non-zero, reverting with `"Invalid listing address"` if not.
    - **Iteration**: Processes long (positionType = 0) and short (positionType = 1) positions in two phases:
      - **Pending Positions**:
       - Retrieves position IDs from `pendingPositions[listingAddress][positionType]`.
       - For each position (up to `maxIterations` and `gasleft() >= 50000`):
       - Calls `_processPendingPosition`:
       - Updates `priceParams2.liquidationPrice` via `_updateLiquidationPrices`, computing liquidation prices using `_computeLoanAndLiquidationLong` or `_computeLoanAndLiquidationShort`.
       - Fetches current price via `_parseEntryPriceInternal` (calls `ISSListing.prices(listingAddress)`), normalizing with `normalizePrice` based on token decimals (tokenB for long, tokenA for short).
       - Checks for liquidation (long: `currentPrice <= liquidationPrice`; short: `currentPrice >= liquidationPrice`):
       - If liquidated, calls `_prepCloseLong` or `_prepCloseShort` to calculate payout, update state (`positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `marginParams1`, `marginParams2`, `exitParams`, `openInterest`, `makerTokenMargin`) via `ICSStorage.CSUpdate`, and calls `removePositionIndex`.
       - Issues payout via `ISSListing.ssUpdate` (input: `PayoutUpdate[]` with `payoutType`, `recipient`, `required`), emitting `PositionClosed`.
       - If not liquidated and within price range (`minEntryPrice <= currentPrice <= maxEntryPrice` or both are zero for market orders):
       - Calls `_createOrderForPosition`:
       - Approves `orderRouter` to spend margin (`taxedMargin + excessMargin`) using `IERC20.approve` (input: `address(orderRouter)`, `denormalizedMargin`, returns: `bool success`).
       - Creates a buy order (short) or sell order (long) via `ICCOrderRouter.createBuyOrder` or `createSellOrder` (input: `listingAddress`, `listingAddress`, `denormalizedMargin`, `0`, `0`), with `orderRouter` handling the margin transfer internally.
       - Calls `_updateExcessTokens` to update listing balances for tokenA and tokenB via `ISSListing.update`.
       - Updates `positionCore2.status1` to true (active) via `CSUpdate`.
       - If market order (`minEntryPrice == 0 && maxEntryPrice == 0`), sets `priceParams1.priceAtEntry` to `currentPrice`.
      - **Active Positions**:
       - Retrieves position IDs from `positionsByType[positionType]`.
       - For each position (up to `maxIterations` and `gasleft() >= 50000`):
       - Calls `_processActivePosition`:
       - Validates position (`positionCore1.listingAddress == listingAddress`, `status2 == 0`).
       - Calls `_prepareActivePositionCheck`:
       - Updates `priceParams2.liquidationPrice` via `_updateLiquidationPrices` for all relevant positions before checking.
       - Checks for liquidation, stop-loss (`stopLossPrice > 0 && (long: currentPrice <= stopLossPrice; short: currentPrice >= stopLossPrice)`), or take-profit (`takeProfitPrice > 0 && (long: currentPrice >= takeProfitPrice; short: currentPrice <= takeProfitPrice)`).
       - If triggered, calls `_prepCloseLong` or `_prepCloseShort` to compute payout and update state.
       - Calls `_executeActivePositionClose`:
       - Calls `removePositionIndex` to update `positionsByType` and `pendingPositions`.
       - Issues payout via `ISSListing.ssUpdate` and emits `PositionClosed`.
- **Balance Checks**:
  - **Pre-Balance Check**: In `_prepCloseLong` or `_prepCloseShort`, ensures `makerTokenMargin[makerAddress][positionToken] >= taxedMargin + excessMargin`.
  - **Post-Balance Check**: In `_createOrderForPosition`, relies on `orderRouter` to verify sufficient balance during `createBuyOrder` or `createSellOrder`, as approval via `IERC20.approve` ensures `orderRouter` can access `denormalizedMargin`.
  - **Listing Balance Check**: In `_createOrderForPosition`, `_updateExcessTokens` ensures tokenA and tokenB balances are updated via `ISSListing.update`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `exitParams`, `marginParams1`, `marginParams2`, `openInterest`, `makerTokenMargin`, `makerMarginTokens`, `positionToken`, `positionsByType`, `pendingPositions`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `PriceParams1`, `PriceParams2`, `ExitParams`, `MarginParams1`, `MarginParams2`, `OpenInterest`.
- **Restrictions**: 
  - `nonReentrant` modifier prevents reentrancy attacks.
  - Reverts if `listingAddress` is zero (`"Invalid listing address"`).
  - Skips invalid positions (e.g., `positionCore1.positionId == 0` or mismatched `listingAddress`).
- **Gas Usage Controls**:
  - Limits processing with `maxIterations` to prevent gas exhaustion.
  - Checks `gasleft() >= 50000` per iteration to ensure sufficient gas for state updates.
  - Uses pop-and-swap for array operations (e.g., `removePositionIndex`).
- **Events**: Emits `PositionClosed` (from `ICSStorage`) for each closed position, including liquidations or stop-loss/take-profit triggers.

## Additional Details
- **Decimal Handling**: Uses `DECIMAL_PRECISION` (1e18) for normalization via `normalizeAmount`, `denormalizeAmount`, `normalizePrice`.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: `maxIterations`, `gasleft() >= 50000`, pop-and-swap for arrays.
- **Listing Validation**: Uses `ISSAgent.isValidListing` for robust checks.
- **Token Usage**: Long positions use tokenA margins, tokenB payouts; short positions use tokenB margins, tokenA payouts.
- **Position Lifecycle**: Pending (`status1 == false`) to active (`status1 == true`) to closed (`status2 == 1`), with `CSUpdate` calls.
- **Market Orders**: Zero `minEntryPrice` and `maxEntryPrice` in `executePositions` trigger instant activation as market orders, per `_parseEntryPriceInternal`.
- **Events**: `StopLossUpdated`, `TakeProfitUpdated`, `PositionClosed`, `AllLongsClosed`, `AllLongsCancelled`, `AllShortsClosed`, `AllShortsCancelled`, `HyxAdded`, `HyxRemoved`, `PositionCancelled`.
- **Position Activation**: Pending positions are activated by approving `orderRouter` to spend margin and creating buy/sell orders, with market orders (zero `minEntryPrice` and `maxEntryPrice`) activating instantly if not liquidated.
- **Payouts**: Long positions pay out in tokenB, short positions in tokenA, using `ISSListing.ssUpdate` to handle transfers to `positionCore1.makerAddress`.
- **Safety**: Balance checks, explicit casting, no inline assembly, liquidation price updates in `addExcessMargin`, `closeLongPosition`, `closeShortPosition`, and `executePositions`.
- **Hyx Functionality**: Replaces `mux` from `SSCrossDriver`, with `addHyx`, `removeHyx`, `getHyxes` for delegated operations. No equivalent to `drift` or `drive` yet, pending implementation.
- **Listing Updates**: All transfers to/from listing call `ISSListing.update` via `_updateListingMargin`.
- **Stack Optimization**: `_processActivePosition` split into `_prepareActivePositionCheck` and `_executeActivePositionClose`, and `cancelAllLongs`/`cancelAllShorts` split into `_prepareCancelPosition`, `_updatePositionParams`, `_updateMarginAndIndex`, `_executeCancelPosition` to address stack-too-deep errors, maintaining incremental `CSUpdate` usage.
- **Liquidation Price Updates**: Added in version 0.0.10 to `addExcessMargin`, `closeLongPosition`, `closeShortPosition`, and `_executePositions` to ensure accurate liquidation checks for all relevant positions, iterating `positionCount` with matching `maker`, `positionToken`, and `listingAddress`.
- **pullMargin Optimization**: Version 0.0.10 restricts withdrawals to cases with no open or pending positions, removing `_updatePositionLiquidationPrices` call for gas efficiency, as no positions exist to update. Including the call is safe but redundant, incurring unnecessary gas costs.
