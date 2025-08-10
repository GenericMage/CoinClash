# CISExecutionDriver Contract Documentation

## Overview
The `CISExecutionDriver` contract, implemented in Solidity (^0.8.2), manages pending trading positions for long and short isolated margin strategies, inheriting from `CISExecutionPartial`. It integrates with external interfaces (`ISSListing`, `ISSLiquidityTemplate`, `ISSAgent`, `ICCOrderRouter`, `IERC20`) for listing validation, liquidity management, order routing, and token operations. It supports pending position execution and stop-loss/take-profit updates, using `ReentrancyGuard` for reentrancy protection and `Ownable` for administrative control. Immediate execution occurs for zero min/max entry price positions.
Satoshi be praised. 

**Inheritance Tree:** `CISExecutionDriver` → `CISExecutionPartial`

**SPDX License:** BSL-1.1 - Peng Protocol 2025

**Version:** 0.0.8 (last updated 2025-08-09)

## State Variables
- **DECIMAL_PRECISION** (uint256, constant, public): Set to 1e18 for normalizing amounts and prices.
- **_agentAddress** (address, private): Stores the ISSAgent contract address, set via `setAgent`.
- **_historicalInterestHeight** (uint256, private): Tracks block height for open interest, initialized to 1, accessible via `getHistoricalInterestHeightView`.
- **_storageContract** (ISIStorage, internal): Reference to the storage contract, set in constructor.
- **orderRouter** (ICCOrderRouter, public): Reference to the order router contract, set via `setOrderRouter`, accessible via `getOrderRouterView`.

## Mappings
- Inherited from `ISIStorage` (via `_storageContract`):
  - **positionCoreBase** (uint256 => PositionCoreBase): Stores core position data (maker address, listing address, position ID, position type).
  - **positionCoreStatus** (uint256 => PositionCoreStatus): Tracks position status (status1: pending/executable, status2: open/closed/cancelled).
  - **priceParams** (uint256 => PriceParams): Holds price data (min/max entry prices, entry price, close price).
  - **marginParams** (uint256 => MarginParams): Manages margin details (initial, taxed, excess).
  - **leverageParams** (uint256 => LeverageParams): Stores leverage details (value, amount, initial loan).
  - **riskParams** (uint256 => RiskParams): Contains risk parameters (liquidation, stop-loss, take-profit prices).
  - **pendingPositions** (address => uint8 => uint256[]): Tracks pending position IDs by listing address and type (0: long, 1: short).
  - **positionsByType** (uint8 => uint256[]): Stores position IDs by type (0: long, 1: short).
  - **positionToken** (uint256 => address): Maps position ID to margin token (tokenA: long, tokenB: short).
  - **longIOByHeight** (uint256 => uint256): Tracks long open interest by block height.
  - **shortIOByHeight** (uint256 => uint256): Tracks short open interest by block height.

## Structs
- From `CISExecutionPartial`:
  - **PendingPositionData**: Holds `coreBase`, `coreStatus`, `price`, `risk`, `margin`, `tokenA`, `tokenB`, `balanceA`, `balanceB`, `marginAmount` for pending position processing.
- From `ISIStorage`:
  - **PositionCoreBase**: Contains `makerAddress` (address), `listingAddress` (address), `positionId` (uint256), `positionType` (uint8: 0 for long, 1 for short).
  - **PositionCoreStatus**: Tracks `status1` (bool: false for pending, true for executable), `status2` (uint8: 0 for open, 1 for closed, 2 for cancelled).
  - **PriceParams**: Stores `priceMin`, `priceMax`, `priceAtEntry`, `priceClose` (uint256, normalized to 1e18).
  - **MarginParams**: Holds `marginInitial`, `marginTaxed`, `marginExcess` (uint256, normalized to 1e18).
  - **LeverageParams**: Contains `leverageVal` (uint8), `leverageAmount`, `loanInitial` (uint256, normalized to 1e18).
  - **RiskParams**: Stores `priceLiquidation`, `priceStopLoss`, `priceTakeProfit` (uint256, normalized to 1e18).
  - **CoreParams**, **TokenAndInterestParams**, **PositionArrayParams**: Used in `SIUpdate` for state updates.
- From `ISSListing`:
  - **UpdateType**: Stores `updateType` (uint8), `structId` (uint8), `index`, `value` (uint256), `addr`, `recipient` (address), `maxPrice`, `minPrice`, `amountSent` (uint256).
  - **PayoutUpdate**: Stores `payoutType` (uint8), `recipient` (address), `required` (uint256, denormalized).

## Formulas
Implemented in `CISExecutionPartial`, unchanged since v0.0.5:
1. **Fee Calculation**: `fee = (leverageVal - 1) * normMarginInitial / 100` (in `_computeFee`).
2. **Leverage Amount**: `leverageAmount = initialMargin * leverageVal`.
3. **Initial Loan (Long)**: `loanInitial = leverageAmount / minPrice`.
4. **Initial Loan (Short)**: `loanInitial = leverageAmount * minPrice`.
5. **Liquidation Price (Long)**: `priceLiquidation = marginRatio < minPrice ? minPrice - marginRatio : 0`, where `marginRatio = marginInitial / leverageAmount`.
6. **Liquidation Price (Short)**: `priceLiquidation = minPrice + marginRatio`.
7. **Payout (Long)**: `payout = baseValue > loanInitial ? baseValue - loanInitial : 0`, where `baseValue = (taxedMargin + excessMargin + leverageAmount) / currentPrice`.
8. **Payout (Short)**: `payout = profit + (taxedMargin + excessMargin) * currentPrice / DECIMAL_PRECISION`, where `profit = (priceAtEntry - currentPrice) * initialMargin * leverageVal`.

## External Functions
### setAgent(address newAgentAddress)
- **Parameters**: `newAgentAddress` (address).
- **Behavior**: Updates `_agentAddress` for listing validation. Emits `ErrorLogged` if zero address.
- **Internal Call Flow**: Validates `newAgentAddress != address(0)`, updates `_agentAddress`.
- **Restrictions**: `onlyOwner`. Reverts if zero address (`"setAgent: Invalid agent address"`).
- **Gas Usage**: Minimal, single state write.

### setOrderRouter(address newOrderRouter)
- **Parameters**: `newOrderRouter` (address).
- **Behavior**: Updates `orderRouter` for order creation. Emits `ErrorLogged` if zero address.
- **Internal Call Flow**: Validates `newOrderRouter != address(0)`, sets `orderRouter` with explicit `ICCOrderRouter` cast.
- **Restrictions**: `onlyOwner`. Reverts if zero address (`"setOrderRouter: Invalid order router address"`).
- **Gas Usage**: Minimal, single state write.

### getOrderRouterView()
- **Parameters**: None.
- **Behavior**: Returns `address(orderRouter)`.
- **Internal Call Flow**: Direct access to `orderRouter`.
- **Restrictions**: None.
- **Gas Usage**: View function, minimal gas.

### getHistoricalInterestHeightView()
- **Parameters**: None.
- **Behavior**: Returns `_historicalInterestHeight`.
- **Internal Call Flow**: Direct access to `_historicalInterestHeight`.
- **Restrictions**: None.
- **Gas Usage**: View function, minimal gas.

### executeEntries(address listingAddress, uint256 maxIterations)
- **Parameters**: `listingAddress` (address), `maxIterations` (uint256).
- **Behavior**: Processes pending positions for a listing, activating within price bounds or with zero min/max prices. Emits `ErrorLogged` for invalid inputs.
- **Internal Call Flow**: Validates `listingAddress != address(0)` and `ISSAgent.isValidListing`. Calls `_executeEntries`: iterates `pendingPositions[listingAddress][positionType]` via `_processPendingPosition` (checks `priceMin <= currentPrice <= priceMax` or zero bounds, updates balances via `ISSListing.update`, sets `status1 = true`, updates `priceAtEntry` via `_updatePriceParams`). Uses `normalizePrice` for prices. Updates `longIOByHeight` or `shortIOByHeight` via `_updateHistoricalInterest`.
- **Mappings/Structs Used**: `positionCoreBase`, `positionCoreStatus`, `priceParams`, `marginParams`, `riskParams`, `pendingPositions`, `positionToken`, `longIOByHeight`, `shortIOByHeight`, `PendingPositionData`, `UpdateType`.
- **Restrictions**: `nonReentrant`. Reverts if `listingAddress` is zero (`"executeEntries: Invalid listing address"`) or invalid (`"executeEntries: Invalid listing"`).
- **Gas Usage**: Controlled by `maxIterations` and `gasleft() >= 50000`.

### updateSL(uint256 positionId, uint256 newStopLossPrice)
- **Parameters**: `positionId` (uint256), `newStopLossPrice` (uint256, denormalized).
- **Behavior**: Updates stop-loss price for an open position, validating against current price. Emits `StopLossUpdated` or `ErrorLogged`.
- **Internal Call Flow**: Validates `positionId`, `status2 == 0`, `makerAddress == msg.sender`. Normalizes `newStopLossPrice` and `currentPrice` (via `ISSListing.prices` and `normalizePrice`). Checks `newStopLossPrice < currentPrice` (long) or `> currentPrice` (short). Calls `_updateSL` (`ISIStorage.SIUpdate`). Emits `StopLossUpdated`.
- **Mappings/Structs Used**: `positionCoreBase`, `positionCoreStatus`, `riskParams`, `positionToken`, `RiskParams`.
- **Restrictions**: `nonReentrant`. Reverts if invalid position (`"updateSL: Invalid position"`), closed (`"updateSL: Position closed"`), not owned (`"updateSL: Not maker"`), or invalid stop-loss (`"updateSL: Invalid SL for long"` or `"updateSL: Invalid SL for short"`).
- **Gas Usage**: Single state update, minimal gas.

### updateTP(uint256 positionId, uint256 newTakeProfitPrice)
- **Parameters**: `positionId` (uint256), `newTakeProfitPrice` (uint256, denormalized).
- **Behavior**: Updates take-profit price, validating against entry price. Emits `TakeProfitUpdated` or `ErrorLogged`.
- **Internal Call Flow**: Validates `positionId`, `status2 == 0`, `makerAddress == msg.sender`. Normalizes `newTakeProfitPrice` and `currentPrice`. Checks `newTakeProfitPrice > priceAtEntry` (long) or `< priceAtEntry` (short). Calls `_updateTP` (`ISIStorage.SIUpdate`). Emits `TakeProfitUpdated`.
- **Mappings/Structs Used**: `positionCoreBase`, `positionCoreStatus`, `priceParams`, `riskParams`, `positionToken`, `PriceParams`, `RiskParams`.
- **Restrictions**: `nonReentrant`. Reverts if invalid position (`"updateTP: Invalid position"`), closed (`"updateTP: Position closed"`), not owned (`"updateTP: Not maker"`), or invalid take-profit (`"updateTP: Invalid TP for long"` or `"updateTP: Invalid TP for short"`).
- **Gas Usage**: Single state update, minimal gas.

## Additional Details
- **Decimal Handling**: Uses `DECIMAL_PRECISION` (1e18) with `IERC20.decimals` for normalization (`normalizePrice`, `normalizeAmount`).
- **Immediate Execution**: `_processPendingPosition` activates zero-bound positions (`priceMin == 0 && priceMax == 0`), setting `priceAtEntry` to current price.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: Uses `maxIterations`, `gasleft() >= 50000`, and pop-and-swap for arrays.
- **Listing Validation**: `ISSAgent.isValidListing` ensures robust checks.
- **Token Usage**: Long positions use tokenA margins; short positions use tokenB margins.
- **Position Lifecycle**: Pending (`status1 == false`, `status2 == 0`) to executable (`status1 == true`, `status2 == 0`).
- **Events**: `ErrorLogged`, `StopLossUpdated`, `TakeProfitUpdated`.
- **Safety**: Explicit casting, no inline assembly, modular helpers (`_fetchPositionData`, `_validatePosition`, `_updateListingBalances`, `_finalizePosition`).
