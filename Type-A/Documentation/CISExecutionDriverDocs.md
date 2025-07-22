# CISExecutionDriver Contract Documentation

## Overview
The `CISExecutionDriver` contract, implemented in Solidity (^0.8.2), manages trading positions for long and short isolated margin strategies, inheriting functionality from `CISExecutionPartial` and integrating with external interfaces (`ISSListing`, `ISSLiquidityTemplate`, `ISSAgent`, `ICCOrderRouter`) for listing validation, liquidity management, and order routing. It supports position closure, cancellation, margin adjustments, stop-loss/take-profit updates, and hyx operations, with immediate execution for zero min/max entry price positions and order creation during pending position execution, using `IERC20` for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control.

**Inheritance Tree:** `CISExecutionDriver` → `CISExecutionPartial`

**SPDX License:** BSL-1.1 - Peng Protocol 2025

**Version:** 0.0.5 (last updated 2025-07-22)

## State Variables
- **DECIMAL_PRECISION** (uint256, constant, public): Set to 1e18 for normalizing amounts and prices across token decimals.
- **agentAddress** (address, private): Stores the address of the ISSAgent contract for listing validation, set via `setAgent`.
- **historicalInterestHeight** (uint256, private): Tracks block height for open interest updates, initialized to 1, accessible via `getHistoricalInterestHeightView`.
- **storageContract** (ISIStorage, internal): Reference to the storage contract, set in constructor, accessed via inheritance.
- **orderRouter** (ICCOrderRouter, public): Reference to the order router contract, set via `setOrderRouter`, accessible via `getOrderRouterView`.
- **hyxes** (mapping(address => bool), private): Tracks authorized hyx addresses for external position management.
- **hyxList** (address[], private): Array of authorized hyx addresses, accessible via `getHyxesView`.

## Mappings
- **hyxes** (mapping(address => bool)): Tracks authorized hyx contracts, updated via `addHyx` and `removeHyx`.
- Inherited from `ISIStorage` (via `storageContract`):
  - **positionCoreBase** (mapping(uint256 => PositionCoreBase)): Stores core position data (maker address, listing address, position ID, position type).
  - **positionCoreStatus** (mapping(uint256 => PositionCoreStatus)): Tracks position status (status1: pending/executable, status2: open/closed/cancelled).
  - **priceParams** (mapping(uint256 => PriceParams)): Holds price data (minimum/maximum entry prices, entry price, close price).
  - **marginParams** (mapping(uint256 => MarginParams)): Manages margin details (initial margin, taxed margin, excess margin).
  - **leverageParams** (mapping(uint256 => LeverageParams)): Stores leverage details (leverage value, leverage amount, initial loan).
  - **riskParams** (mapping(uint256 => RiskParams)): Contains risk parameters (liquidation price, stop-loss price, take-profit price).
  - **pendingPositions** (mapping(address => mapping(uint8 => uint256[]))): Tracks pending position IDs by listing address and position type (0 for long, 1 for short).
  - **positionsByType** (mapping(uint8 => uint256[])): Stores position IDs by type (0 for long, 1 for short).
  - **positionToken** (mapping(uint256 => address)): Maps position ID to margin token (tokenA for long, tokenB for short).
  - **longIOByHeight** (mapping(uint256 => uint256)): Tracks long open interest by block height.
  - **shortIOByHeight** (mapping(uint256 => uint256)): Tracks short open interest by block height.

## Structs
- Inherited from `ISIStorage`:
  - **PositionCoreBase**: Contains `makerAddress` (address), `listingAddress` (address), `positionId` (uint256), `positionType` (uint8: 0 for long, 1 for short).
  - **PositionCoreStatus**: Tracks `status1` (bool: false for pending, true for executable), `status2` (uint8: 0 for open, 1 for closed, 2 for cancelled).
  - **PriceParams**: Stores `priceMin` (uint256), `priceMax` (uint256), `priceAtEntry` (uint256), `priceClose` (uint256), all normalized to 1e18.
  - **MarginParams**: Holds `marginInitial` (uint256), `marginTaxed` (uint256), `marginExcess` (uint256), all normalized to 1e18.
  - **LeverageParams**: Contains `leverageVal` (uint8), `leverageAmount` (uint256), `loanInitial` (uint256), with amounts normalized to 1e18.
  - **RiskParams**: Stores `priceLiquidation` (uint256), `priceStopLoss` (uint256), `priceTakeProfit` (uint256), all normalized to 1e18.
- From `ISSListing`:
  - **UpdateType**: Stores `updateType` (uint8), `index` (uint8), `value` (uint256), `addr` (address), `recipient` (address).
  - **PayoutUpdate**: Stores `payoutType` (uint8), `recipient` (address), `required` (uint256, denormalized).

## Formulas
Formulas are implemented in `CISExecutionPartial` for position calculations.

1. **Fee Calculation**:
   - **Formula**: `fee = (leverageVal - 1) * normMarginInitial / 100`
   - **Used in**: `_computeFee` (called by `_updateMarginAndInterest` in `addExcessMargin`).
   - **Description**: Computes fee based on leverage and normalized initial margin.

2. **Leverage Amount**:
   - **Formula**: `leverageAmount = initialMargin * leverageVal`
   - **Used in**: `_computeLoanAndLiquidationLong`, `_computeLoanAndLiquidationShort`, `_computePayoutLong`, `_computePayoutShort`.
   - **Description**: Calculates leveraged position size.

3. **Initial Loan (Long)**:
   - **Formula**: `loanInitial = leverageAmount / minPrice`
   - **Used in**: `_computeLoanAndLiquidationLong`.
   - **Description**: Loan for long positions based on minimum entry price.

4. **Initial Loan (Short)**:
   - **Formula**: `loanInitial = leverageAmount * minPrice`
   - **Used in**: `_computeLoanAndLiquidationShort`.
   - **Description**: Loan for short positions based on minimum entry price.

5. **Liquidation Price (Long)**:
   - **Formula**: `priceLiquidation = marginRatio < minPrice ? minPrice - marginRatio : 0`, where `marginRatio = marginInitial / leverageAmount`
   - **Used in**: `_computeLoanAndLiquidationLong`.
   - **Description**: Liquidation price for long positions.

6. **Liquidation Price (Short)**:
   - **Formula**: `priceLiquidation = minPrice + marginRatio`
   - **Used in**: `_computeLoanAndLiquidationShort`.
   - **Description**: Liquidation price for short positions.

7. **Payout (Long)**:
   - **Formula**: `payout = baseValue > loanInitial ? baseValue - loanInitial : 0`, where `baseValue = (taxedMargin + excessMargin + leverageAmount) / currentPrice`
   - **Used in**: `_computePayoutLong`.
   - **Description**: Payout for long position closure in tokenB.

8. **Payout (Short)**:
   - **Formula**: `payout = profit + (taxedMargin + excessMargin) * currentPrice / DECIMAL_PRECISION`, where `profit = (priceAtEntry - currentPrice) * initialMargin * leverageVal`
   - **Used in**: `_computePayoutShort`.
   - **Description**: Payout for short position closure in tokenA.

## External Functions
Each function details its parameters, behavior, internal call flow, restrictions, and gas controls. Mappings and structs are explained in context. Pre/post balance checks are described where applicable.

### setAgent(address newAgentAddress)
- **Parameters**:
  - `newAgentAddress` (address): New ISSAgent address.
- **Behavior**: Updates `agentAddress` for listing validation.
- **Internal Call Flow**: Validates `newAgentAddress != address(0)`. Updates `_agentAddress`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **State Variable**: `agentAddress`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `newAgentAddress` is zero (`"Invalid agent address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

### setOrderRouter(address newOrderRouter)
- **Parameters**:
  - `newOrderRouter` (address): New ICCOrderRouter address.
- **Behavior**: Updates `orderRouter` for order creation during position execution.
- **Internal Call Flow**: Validates `newOrderRouter != address(0)`. Sets `orderRouter` with explicit casting to `ICCOrderRouter`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **State Variable**: `orderRouter`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `newOrderRouter` is zero (`"Invalid order router address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

### getOrderRouterView()
- **Parameters**: None.
- **Behavior**: Returns the current `orderRouter` address.
- **Internal Call Flow**: Returns `address(orderRouter)`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **State Variable**: `orderRouter`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### getHistoricalInterestHeightView()
- **Parameters**: None.
- **Behavior**: Returns the current `historicalInterestHeight`.
- **Internal Call Flow**: Returns `_historicalInterestHeight`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **State Variable**: `historicalInterestHeight`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### addHyx(address hyx)
- **Parameters**:
  - `hyx` (address): Address of the hyx contract to authorize.
- **Behavior**: Authorizes a hyx contract to interact with execution functions, adding it to `_hyxes` and `_hyxList`. Emits `hyxAdded`.
- **Internal Call Flow**: Validates `hyx != address(0)` and `!_hyxes[hyx]`. Sets `_hyxes[hyx] = true` and appends `hyx` to `_hyxList`. Emits `hyxAdded`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `hyxes`.
  - **State Variable**: `hyxList`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `hyx` is zero (`"Invalid hyx address"`) or already authorized (`"hyx already authorized"`).
- **Gas Usage Controls**: Minimal gas due to single mapping and array update.

### removeHyx(address hyx)
- **Parameters**:
  - `hyx` (address): Address of the hyx contract to deauthorize.
- **Behavior**: Removes a hyx contract from the authorized list, updating `_hyxes` and `_hyxList`. Emits `hyxRemoved`.
- **Internal Call Flow**: Validates `_hyxes[hyx]`. Sets `_hyxes[hyx] = false`. Removes `hyx` from `_hyxList` using pop-and-swap. Emits `hyxRemoved`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `hyxes`.
  - **State Variable**: `hyxList`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `hyx` is not authorized (`"hyx not authorized"`).
- **Gas Usage Controls**: Minimal gas due to single mapping update and array pop-and-swap.

### getHyxesView()
- **Parameters**: None.
- **Behavior**: Returns an array of authorized hyx addresses from `_hyxList`.
- **Internal Call Flow**: Returns `_hyxList`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **State Variable**: `hyxList`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### addExcessMargin(uint256 positionId, uint256 amount, address token)
- **Parameters**:
  - `positionId` (uint256): Position ID.
  - `amount` (uint256): Margin to add (denormalized).
  - `token` (address): Token address (tokenA for long, tokenB for short).
- **Behavior**: Adds excess margin to an open position, transferring to the listing contract, updating margin and interest, and recalculating liquidation price. Emits `ExcessMarginAdded`.
- **Internal Call Flow**: Validates `positionId` in `positionCoreBase`, `status2 == 0`, `makerAddress == msg.sender`, `amount > 0`, and `token == positionToken[positionId]`. Normalizes `amount` with `normalizeAmount` (`IERC20.decimals`). Calls `_validateExcessMargin` (ensures `normalizedAmount <= leverageAmount`), `_transferExcessMargin` (transfers via `IERC20.transferFrom`, input: `msg.sender`, `listingAddress`, `amount`, returns: `bool`), `_updateMarginAndInterest` (updates `marginParams.marginExcess`, calls `_transferMarginToListing` with `ISSListing.update`, updates `longIOByHeight` or `shortIOByHeight` via `_updateHistoricalInterest`), and `_updateLiquidationPrice` (recalculates `riskParams.priceLiquidation` using `_computeLoanAndLiquidationLong` or `_computeLoanAndLiquidationShort`). Pre-balance check (`IERC20.balanceOf(listingAddress)`); post-balance check (`actualAmount >= amount`). Transfer destination is `listingAddress`. Emits `ExcessMarginAdded`.
- **Balance Checks**:
  - **Pre-Balance Check**: `IERC20.balanceOf(listingAddress)` before transfer.
  - **Post-Balance Check**: Verifies `balanceAfter - balanceBefore >= amount`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `marginParams`, `leverageParams`, `riskParams`, `positionToken`, `longIOByHeight`, `shortIOByHeight`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `MarginParams`, `LeverageParams`, `RiskParams`, `UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if position is invalid (`"Invalid position"`), closed (`"Position closed"`), not owned (`"Not maker"`), amount is zero (`"Invalid amount"`), token is invalid (`"Invalid token"`), margin exceeds leverage (`"Excess margin exceeds leverage"`), or transfer fails (`"TransferFrom failed"` or `"Transfer amount mismatch"`).
- **Gas Usage Controls**: Single transfer and array update minimize gas.

### pullMargin(uint256 positionId, uint256 amount)
- **Parameters**:
  - `positionId` (uint256): Position ID.
  - `amount` (uint256): Margin to withdraw (denormalized).
- **Behavior**: Withdraws excess margin from an open position, transferring to `msg.sender`, updating margin and interest, and recalculating liquidation price.
- **Internal Call Flow**: Validates `positionId` in `positionCoreBase`, `status2 == 0`, `makerAddress == msg.sender`, and `amount > 0`. Retrieves `positionToken[positionId]`. Normalizes `amount` with `normalizeAmount`. Ensures `normalizedAmount <= marginParams.marginExcess`. Calls `_updateMarginParams` (reduces `marginExcess`), `_updateLiquidationPrice`, `_executeMarginPayout` (transfers via `ISSListing.ssUpdate`, input: `PayoutUpdate[]` with `recipient = msg.sender`, `required = amount`), and `_updateHistoricalInterest` (reduces `longIOByHeight` or `shortIOByHeight`). No pre/post balance checks as transfers are handled by `ISSListing`. Transfer destination is `msg.sender`.
- **Balance Checks**: None, as transfers are handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `marginParams`, `positionToken`, `longIOByHeight`, `shortIOByHeight`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `MarginParams`, `PayoutUpdate`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if position is invalid (`"Invalid position"`), closed (`"Position closed"`), not owned (`"Not maker"`), amount is zero (`"Invalid amount"`), or insufficient margin (`"Insufficient excess margin"`).
- **Gas Usage Controls**: Minimal updates with pop-and-swap for arrays.

### updateSL(uint256 positionId, uint256 newStopLossPrice)
- **Parameters**:
  - `positionId` (uint256): Position ID.
  - `newStopLossPrice` (uint256): New stop-loss price (normalized).
- **Behavior**: Updates the stop-loss price for an open position, validating against the current price. Emits `StopLossUpdated`.
- **Internal Call Flow**: Validates `positionId` in `positionCoreBase`, `status2 == 0`, and `makerAddress == msg.sender`. Fetches `currentPrice` via `ISSListing.prices` (input: `listingAddress`, returns: `uint256`) and normalizes with `normalizePrice` (`IERC20.decimals`). Validates `newStopLossPrice` (`< currentPrice` for long, `> currentPrice` for short, or zero). Calls `_updateSL` to set `riskParams.priceStopLoss` via `_updateLeverageAndRiskParams` (`ISIStorage.SIUpdate`). Emits `StopLossUpdated`. No transfers or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `riskParams`, `positionToken`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `RiskParams`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if position is invalid (`"Invalid position"`), closed (`"Position closed"`), not owned (`"Not maker"`), or stop-loss is invalid (`"Invalid SL for long"` or `"Invalid SL for short"`).
- **Gas Usage Controls**: Single state update, minimal gas.

### updateTP(uint256 positionId, uint256 newTakeProfitPrice)
- **Parameters**:
  - `positionId` (uint256): Position ID.
  - `newTakeProfitPrice` (uint256): New take-profit price (normalized).
- **Behavior**: Updates the take-profit price for an open position, validating against the entry price. Emits `TakeProfitUpdated`.
- **Internal Call Flow**: Validates `positionId` in `positionCoreBase`, `status2 == 0`, and `makerAddress == msg.sender`. Fetches `currentPrice` via `ISSListing.prices` and normalizes. Validates `newTakeProfitPrice` (`> priceAtEntry` for long, `< priceAtEntry` for short, or zero). Calls `_updateTP` to set `riskParams.priceTakeProfit` via `_updateLeverageAndRiskParams` (`ISIStorage.SIUpdate`). Emits `TakeProfitUpdated`. No transfers or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `priceParams`, `riskParams`, `positionToken`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `RiskParams`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if position is invalid (`"Invalid position"`), closed (`"Position closed"`), not owned (`"Not maker"`), or take-profit is invalid (`"Invalid TP for long"` or `"Invalid TP for short"`).
- **Gas Usage Controls**: Single state update, minimal gas.

### closeAllLongs(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Closes all active long positions for `msg.sender`, transferring payouts in tokenB. Emits `AllLongsClosed` with count of closed positions.
- **Internal Call Flow**: Calls `_closeAllPositions` with `positionType = 0`. Iterates `positionsByType[0]` up to `maxIterations`, checking `status2 == 0`, `status1 == true`, and `makerAddress == msg.sender`. Calls `_prepCloseLong` and `_finalizeClosePosition` (uses `_computePayoutLong`, clears parameters via `_updateCoreParams`, `_updatePositionStatus`, `_updatePriceParams`, `_updateMarginParams`, `_updateLeverageAndRiskParams`, removes position via `removePositionIndex`, transfers payout via `ISSListing.ssUpdate` with `PayoutUpdate`). Updates `longIOByHeight` via `_updateHistoricalInterest`. Emits `PositionClosed` per position and `AllLongsClosed`. Payout destination is `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `status2 == 0` and `status1 == true` per position.
  - **Post-Balance Check**: None, as payouts are handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `priceParams`, `marginParams`, `leverageParams`, `riskParams`, `positionsByType`, `longIOByHeight`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `MarginParams`, `LeverageParams`, `RiskParams`, `PayoutUpdate`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Skips non-matching positions.
- **Gas Usage Controls**: `maxIterations` and `gasleft() >= 50000`. Pop-and-swap optimizes array operations.

### closeAllShorts(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Closes all active short positions for `msg.sender`, transferring payouts in tokenA. Emits `AllShortsClosed` with count of closed positions.
- **Internal Call Flow**: Calls `_closeAllPositions` with `positionType = 1`. Iterates `positionsByType[1]`, using `_prepCloseShort` and `_finalizeClosePosition` (uses `_computePayoutShort`, transfers payout in tokenA). Updates `shortIOByHeight`. Emits `PositionClosed` per position and `AllShortsClosed`. Payout destination is `msg.sender`.
- **Balance Checks**: Same as `closeAllLongs`.
- **Mappings/Structs Used**: Same as `closeAllLongs`, with `shortIOByHeight`.
- **Restrictions**: Same as `closeAllLongs`.
- **Gas Usage Controls**: Same as `closeAllLongs`.

### cancelAllLongs(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Cancels all pending long positions for `msg.sender`, returning margins in tokenA. Emits `AllLongsCancelled` with count of cancelled positions.
- **Internal Call Flow**: Calls `_cancelAllPositions` with `positionType = 0`. Iterates `pendingPositions[msg.sender][0]`, checking `status1 == false`, `status2 == 0`, and `makerAddress == msg.sender`. Calls `_executeCancelPosition` (clears parameters, removes position via `removePositionIndex`, transfers margin via `ISSListing.ssUpdate` with `PayoutUpdate`). Updates `longIOByHeight`. Emits `PositionCancelled` per position and `AllLongsCancelled`. Margin destination is `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `status1 == false` and `status2 == 0` per position.
  - **Post-Balance Check**: None, as transfers are handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `marginParams`, `pendingPositions`, `longIOByHeight`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `MarginParams`, `PayoutUpdate`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Skips non-matching positions.
- **Gas Usage Controls**: Same as `closeAllLongs`.

### cancelAllShorts(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Cancels all pending short positions for `msg.sender`, returning margins in tokenB. Emits `AllShortsCancelled` with count of cancelled positions.
- **Internal Call Flow**: Calls `_cancelAllPositions` with `positionType = 1`. Iterates `pendingPositions[msg.sender][1]`, using `_executeCancelPosition` (transfers margin in tokenB). Updates `shortIOByHeight`. Emits `PositionCancelled` per position and `AllShortsCancelled`. Margin destination is `msg.sender`.
- **Balance Checks**: Same as `cancelAllLongs`.
- **Mappings/Structs Used**: Same as `cancelAllLongs`, with `shortIOByHeight`.
- **Restrictions**: Same as `closeAllLongs`.
- **Gas Usage Controls**: Same as `closeAllLongs`.

### cancelPosition(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID to cancel.
- **Behavior**: Cancels a pending position, returning margins to `msg.sender`. Emits `PositionCancelled`.
- **Internal Call Flow**: Validates `positionId` in `positionCoreBase`, `status1 == false`, `status2 == 0`, and `makerAddress == msg.sender`. Calls `_executeCancelPosition`: clears parameters via `_updateCoreParams`, `_updatePositionStatus` (`status2 = 2`), `_updatePriceParams`, `_updateMarginParams`, `_updateLeverageAndRiskParams`; removes position via `removePositionIndex`; transfers margin via `ISSListing.ssUpdate` with `PayoutUpdate` (uses `positionToken`, `marginTaxed + marginExcess`). Updates `longIOByHeight` or `shortIOByHeight`. Emits `PositionCancelled`. Margin destination is `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `status1 == false` and `status2 == 0`.
  - **Post-Balance Check**: None, as transfers are handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `marginParams`, `positionToken`, `pendingPositions`, `longIOByHeight`, `shortIOByHeight`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `MarginParams`, `PayoutUpdate`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if position is invalid (`"Invalid position"`), closed (`"Position closed"`), executable (`"Position active"`), or not owned (`"Not maker"`).
- **Gas Usage Controls**: Minimal updates with pop-and-swap for arrays.

### executePositions(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Processes pending and active positions for a listing, activating pending positions within price bounds or closing positions based on liquidation, stop-loss, or take-profit triggers. Emits `PositionClosed` for closed positions.
- **Internal Call Flow**: Validates `listingAddress` and checks validity via `ISSAgent.isValidListing`. Calls `_executePositions`: iterates `pendingPositions[listingAddress][positionType]` via `_processPendingPosition` (checks `priceMin <= currentPrice <= priceMax` or zero bounds for immediate execution, calls `_createOrderForPosition` with `ICCOrderRouter.createSellOrder` for long or `createBuyOrder` for short, updates `positionCoreStatus.status1 = true`, `priceParams.priceAtEntry`, and token balances via `_updateExcessTokens`; closes if liquidation triggered). Iterates `positionsByType[positionType]` via `_processActivePosition` (closes if liquidation, stop-loss, or take-profit triggered using `_prepCloseLong` or `_prepCloseShort`). Calls `_updateLiquidationPrice` per position. Removes closed positions via `removePositionIndex`. Updates `longIOByHeight` or `shortIOByHeight`. Payouts go to `makerAddress` via `ISSListing.ssUpdate`. Emits `PositionClosed` for closures.
- **Balance Checks**:
  - **Pre-Balance Check**: `status2 == 0` for pending/active positions.
  - **Post-Balance Check**: None, as payouts are handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `priceParams`, `marginParams`, `leverageParams`, `riskParams`, `positionsByType`, `pendingPositions`, `positionToken`, `longIOByHeight`, `shortIOByHeight`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `MarginParams`, `LeverageParams`, `RiskParams`, `PayoutUpdate`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `listingAddress` is zero (`"Invalid listing address"`) or invalid (`"Invalid listing"`).
- **Gas Usage Controls**: `maxIterations` and `gasleft() >= 50000`. Pop-and-swap optimizes array operations.

## Additional Details
- **Decimal Handling**: Uses `DECIMAL_PRECISION` (1e18) for normalization across token decimals, with `IERC20.decimals()` for token-specific precision (handles `decimals <= 18` and `> 18` via `normalizePrice` and `normalizeAmount`).
- **Immediate Execution**: `_processPendingPosition` supports immediate execution for zero min/max entry price positions (`priceMin == 0 && priceMax == 0`), setting `priceAtEntry` to the current price from `ISSListing.prices` and creating orders via `ICCOrderRouter`.
- **Order Creation**: During `_processPendingPosition`, `_createOrderForPosition` creates orders using `ICCOrderRouter.createSellOrder` (long) or `createBuyOrder` (short) with `marginTaxed + marginExcess`, approving tokens via `IERC20.approve`.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: Uses `maxIterations`, `gasleft() >= 50000`, and pop-and-swap for array operations. No fixed iteration limits except in loops controlled by `maxIterations`.
- **Listing Validation**: Uses `ISSAgent.isValidListing` for robust checks in `executePositions`.
- **Token Usage**: Long positions use tokenA margins, tokenB payouts; short positions use tokenB margins, tokenA payouts.
- **Position Lifecycle**: Pending (`status1 == false`, `status2 == 0`) to executable (`status1 == true`, `status2 == 0`) to closed (`status2 == 1`) or cancelled (`status2 == 2`).
- **Events**: Emitted for hyx operations (`hyxAdded`, `hyxRemoved`), position closure (`PositionClosed`), cancellation (`PositionCancelled`), margin addition (`ExcessMarginAdded`), SL/TP updates (`StopLossUpdated`, `TakeProfitUpdated`), and batch operations (`AllLongsClosed`, `AllLongsCancelled`, `AllShortsClosed`, `AllShortsCancelled`).
- **hyx Integration**: `hyxes` mapping authorizes external contracts for future extensions, though `drive` and `drift` are not implemented in this version (unlike `SSIsolatedDriver`). `addHyx` and `removeHyx` manage authorization.
- **Safety**: Balance checks in `addExcessMargin`, explicit casting (e.g., `uint8`, `uint256`, `address`), no inline assembly, and modular helpers (`_validateExcessMargin`, `_transferExcessMargin`, `_updateMarginAndInterest`, `_updateLiquidationPrice`, `_updateSL`, `_updateTP`, `_bytesToString`) ensure robustness.
- **Proper Listing Updates**: Transfers to/from the listing (e.g., in `_transferExcessMargin`, `_executeMarginPayout`) call `ISSListing.update` or `ISSListing.ssUpdate` to reflect changes.
- **Nuances and Clarifications**:
  - Unlike `SSIsolatedDriver`, `CISExecutionDriver` omits position creation functions (`drive`, `enterLong`, `enterShort`) and `drift`, focusing on position management and execution.
  - Immediate execution of zero-bound entry price positions in `_processPendingPosition` uses the current price from `ISSListing.prices`, creating orders via `ICCOrderRouter` instead of deferring execution.
  - No `nonce` or `positionIdCounter` as position creation is handled externally, with `positionId` managed by `ISIStorage`.
  - No `pendingEntries` mapping or related structs, as position creation is not implemented.
  - `executePositions` processes both pending and active positions in a single call, with immediate order creation for qualifying pending positions.
  - State updates use `ISIStorage.SIUpdate` with encoded strings, avoiding direct tuple access via explicit destructuring in `_bytesToString`.
  - No view functions for querying position arrays (`positionsByTypeView`, `positionsByAddressView`) or interest (`queryInterest`), relying on `ISIStorage` for state access.
  - `CISExecutionDriver` assumes `ISIStorage` handles position data consistency, with `CISExecutionPartial` managing calculations and updates.