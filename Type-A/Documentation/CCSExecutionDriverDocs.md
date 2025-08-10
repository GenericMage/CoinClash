# CCSExecutionDriver Contract Documentation

## Overview
The `CCSExecutionDriver` contract, implemented in Solidity (^0.8.2), manages trading positions for long and short cross margin strategies, inheriting from `CCSExecutionPartial`. It integrates with external interfaces (`ISSListing`, `ISSLiquidityTemplate`, `ICCAgent`, `ICSStorage`, `ICCOrderRouter`) for position execution, stop-loss/take-profit updates, and hyx-driven operations. It uses `IERC20` for token operations, `ReentrancyGuard` for protection, and `Ownable` for administrative control. State variables are hidden, accessed via view functions, and decimal precision is maintained. The contract supports market order execution when `minEntryPrice` and `maxEntryPrice` are zero, aligning with `SSCrossDriver` but using `ICSStorage` for state management.

**Inheritance Tree**: `CCSExecutionDriver` → `CCSExecutionPartial` → `ReentrancyGuard`, `Ownable`

**SPDX License**: BSL-1.1 - Peng Protocol 2025

**Version**: 0.0.17 (last updated 2025-08-06)

**Changes**:
- 2025-08-06: Updated to version 0.0.17. Removed `addExcessMargin`, `pullMargin` (extracted to `CCSLiquidationDriver.sol`), `closeAllLongs`, `closeAllShorts`, `cancelAllLongs`, `cancelAllShorts`, `cancelPosition` (not present, is in other drivers). Updated mappings, structs, and function descriptions to align with `CCSExecutionPartial.sol` (version 0.0.19).

## State Variables
- **DECIMAL_PRECISION** (uint256, constant, public): 1e18 for normalizing amounts/prices (in `CCSExecutionPartial`).
- **agentAddress** (address, public): Stores `ICCAgent` address for listing validation (in `CCSExecutionPartial`).
- **storageContract** (ICSStorage, public): Reference to storage contract (in `CCSExecutionPartial`).
- **orderRouter** (ICCOrderRouter, public): Reference to order router contract (in `CCSExecutionPartial`).
- **_hyxes** (mapping(address => bool), private): Tracks authorized hyx contracts (in `CCSExecutionDriver`).
- **_hyxList** (address[], private): Lists authorized hyx addresses (in `CCSExecutionDriver`).

## Mappings
- Defined in `ICSStorage` (inlined in `CCSExecutionPartial`):
  - **makerTokenMargin** (mapping(address => mapping(address => uint256))): Normalized margin balances per maker/token.
  - **positionCore1** (mapping(uint256 => PositionCore1)): Core position data (positionId, listingAddress, makerAddress, positionType).
  - **positionCore2** (mapping(uint256 => PositionCore2)): Position status (status1, status2).
  - **priceParams1** (mapping(uint256 => PriceParams1)): Price data (minEntryPrice, maxEntryPrice, minPrice, priceAtEntry, leverage).
  - **priceParams2** (mapping(uint256 => PriceParams2)): Liquidation price.
  - **marginParams1** (mapping(uint256 => MarginParams1)): Margin details (initialMargin, taxedMargin, excessMargin, fee).
  - **positionToken** (mapping(uint256 => address)): Maps position ID to margin token.
  - **pendingPositions** (mapping(address => mapping(uint8 => uint256[]))): Pending position IDs by listing and type.
  - **longIOByHeight** (mapping(uint256 => uint256)): Long open interest by block height.
  - **shortIOByHeight** (mapping(uint256 => uint256)): Short open interest by block height.

## Structs
- Defined in `ICSStorage` (inlined in `CCSExecutionPartial`):
  - **PositionCore1**: `positionId` (uint256), `listingAddress` (address), `makerAddress` (address), `positionType` (uint8: 0=long, 1=short).
  - **PositionCore2**: `status1` (bool: active), `status2` (uint8: 0=open, 1=closed).
  - **PriceParams1**: `minEntryPrice`, `maxEntryPrice`, `minPrice`, `priceAtEntry` (uint256, normalized), `leverage` (uint8).
  - **PriceParams2**: `liquidationPrice` (uint256, normalized).
  - **MarginParams1**: `initialMargin`, `taxedMargin`, `excessMargin`, `fee` (uint256, normalized).
  - **ExitParams**: `stopLossPrice`, `takeProfitPrice`, `exitPrice` (uint256, normalized).
  - **OpenInterest**: `leverageAmount`, `timestamp` (uint256, normalized).

## Formulas
- **Fee Calculation**: `fee = (initialMargin * (leverage - 1) * DECIMAL_PRECISION) / 100 / DECIMAL_PRECISION` (in `_computeFee`).
- **Taxed Margin**: `taxedMargin = normalizeAmount(token, initialMargin) - fee` (referenced).
- **Leverage Amount**: `leverageAmount = normalizeAmount(token, initialMargin) * leverage` (referenced).
- **Initial Loan (Long)**: `initialLoan = leverageAmount / minPrice` (in `_computeLoanAndLiquidationLong`).
- **Initial Loan (Short)**: `initialLoan = leverageAmount * minPrice` (in `_computeLoanAndLiquidationShort`).
- **Liquidation Price (Long)**: `liquidationPrice = marginRatio < minPrice ? minPrice - marginRatio : 0`, where `marginRatio = makerTokenMargin[maker][tokenA] / leverageAmount` (in `_computeLoanAndLiquidationLong`).
- **Liquidation Price (Short)**: `liquidationPrice = minPrice + marginRatio`, where `marginRatio = makerTokenMargin[maker][tokenB] / leverageAmount` (in `_computeLoanAndLiquidationShort`).
- **Payout (Long)**: `payout = (taxedMargin + totalMargin + leverageAmount) / currentPrice > 0 ? baseValue : 0` (in `_computePayoutLong`).
- **Payout (Short)**: `payout = profit + (taxedMargin + totalMargin) * currentPrice / DECIMAL_PRECISION`, where `profit = (priceAtEntry - currentPrice) * initialMargin * leverage` (in `_computePayoutShort`).

## External Functions
### setAgent(address newAgentAddress)
- **Contract**: `CCSExecutionPartial`
- **Parameters**: `newAgentAddress` (address).
- **Behavior**: Updates `agentAddress`. Validates non-zero address.
- **Restrictions**: `onlyOwner`, reverts if zero (`"Agent address cannot be zero"`).
- **Gas**: Minimal, single state write.

### setOrderRouter(address newOrderRouter)
- **Contract**: `CCSExecutionPartial`
- **Parameters**: `newOrderRouter` (address).
- **Behavior**: Updates `orderRouter`. Validates non-zero address.
- **Restrictions**: `onlyOwner`, reverts if zero (`"Order router address cannot be zero"`).
- **Gas**: Minimal, single state write.

### addHyx(address hyx)
- **Contract**: `CCSExecutionDriver`
- **Parameters**: `hyx` (address).
- **Behavior**: Authorizes hyx, emits `HyxAdded`. Validates non-zero, non-authorized address.
- **Restrictions**: `onlyOwner`, reverts if zero (`"Hyx address cannot be zero"`) or authorized (`"Hyx address already authorized"`).
- **Gas**: Minimal, mapping/array update.

### removeHyx(address hyx)
- **Contract**: `CCSExecutionDriver`
- **Parameters**: `hyx` (address).
- **Behavior**: Revokes hyx, emits `HyxRemoved`. Uses pop-and-swap.
- **Restrictions**: `onlyOwner`, reverts if not authorized (`"Hyx address not authorized"`).
- **Gas**: Minimal, array pop-and-swap.

### getHyxes()
- **Contract**: `CCSExecutionDriver`
- **Parameters**: None.
- **Behavior**: Returns `_hyxList`.
- **Restrictions**: View function.
- **Gas**: Minimal, array read.

### updateSL(uint256 positionId, uint256 newStopLossPrice)
- **Contract**: `CCSExecutionDriver`
- **Parameters**: `positionId` (uint256), `newStopLossPrice` (uint256).
- **Behavior**: Updates stop-loss, emits `StopLossUpdated`. Validates position, ownership, and price.
- **Internal Call Flow**: Calls `_updateSL` to set `exitParams.stopLossPrice`.
- **Restrictions**: `nonReentrant`, reverts if invalid position, closed, or not owned.
- **Gas**: Minimal, single state update.

### updateTP(uint256 positionId, uint256 newTakeProfitPrice)
- **Contract**: `CCSExecutionDriver`
- **Parameters**: `positionId` (uint256), `newTakeProfitPrice` (uint256).
- **Behavior**: Updates take-profit, emits `TakeProfitUpdated`. Validates price direction.
- **Internal Call Flow**: Calls `_updateTP` to set `exitParams.takeProfitPrice`.
- **Restrictions**: `nonReentrant`, reverts if invalid position, closed, or not owned.
- **Gas**: Minimal, single state update.

### executeEntries(address listingAddress, uint256 maxIterations)
- **Contract**: `CCSExecutionDriver`
- **Parameters**: `listingAddress` (address), `maxIterations` (uint256).
- **Behavior**: Processes pending positions, activates or liquidates based on price. Emits `PositionClosed` if liquidated.
- **Internal Call Flow**: Calls `_executeEntriesInternal` to process pending positions, create orders, or close positions.
- **Restrictions**: `nonReentrant`, reverts if not authorized hyx or invalid listing.
- **Gas**: Controlled by `maxIterations`, `gasleft() >= 50000`.

## Additional Details
- **Decimal Handling**: Uses `DECIMAL_PRECISION` (1e18) for normalization.
- **Reentrancy**: `nonReentrant` on state-changing functions.
- **Gas Optimization**: `maxIterations`, `gasleft()`, pop-and-swap.
- **Listing Validation**: `ICCAgent.isValidListing` ensures valid listings.
- **Token Usage**: Long positions use tokenA margins, tokenB payouts; short positions use tokenB margins, tokenA payouts.
- **Events**: `StopLossUpdated`, `TakeProfitUpdated`, `PositionClosed`, `HyxAdded`, `HyxRemoved`.
- **Hyx Functionality**: Replaces `mux`, manages delegated operations.
