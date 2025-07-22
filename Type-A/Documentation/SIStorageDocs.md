# SIStorage Contract Documentation

## Overview
The `SIStorage` contract, implemented in Solidity (^0.8.2), serves as a storage layer for trading positions in the isolated margin strategy system, extracting and managing position-related state variables and view functions from `SSIsolatedDriver.sol`, `SSDPositionPartial.sol`, and `SSDUtilityPartial.sol`. It integrates with external interfaces (`ISSListing`, `ISSAgent`, `ISSLiquidityTemplate`) and uses `IERC20` for token operations and `Ownable` for administrative control, focusing on storing position data, tracking open interest, and providing view functions without handling execution logic like position creation, closure, or margin transfers.

**SPDX License:** BSL-1.1 - Peng Protocol 2025

**Version:** 0.0.3 (last updated 2025-07-20)

## State Variables
- **DECIMAL_PRECISION** (uint256, constant, public): Set to 1e18 for normalizing amounts and prices across token decimals.
- **agent** (address, public): Stores the address of the ISSAgent contract for listing validation.
- **historicalInterestHeight** (uint256, public): Tracks the current block height for open interest updates, initialized to 1.
- **positionCount** (uint256, public): Counter for tracking the total number of positions, initialized to 1.
- **muxes** (mapping(address => bool), public): Tracks authorized mux contracts for external position updates.

## Mappings
- **positionCoreBase** (mapping(uint256 => PositionCoreBase)): Stores core position data (maker address, listing address, position ID, position type).
- **positionCoreStatus** (mapping(uint256 => PositionCoreStatus)): Tracks position status (pending/executable, open/closed/cancelled).
- **priceParams** (mapping(uint256 => PriceParams)): Holds price data (minimum/maximum entry prices, entry price, close price).
- **marginParams** (mapping(uint256 => MarginParams)): Manages margin details (initial margin, taxed margin, excess margin).
- **leverageParams** (mapping(uint256 => LeverageParams)): Stores leverage details (leverage value, leverage amount, initial loan).
- **riskParams** (mapping(uint256 => RiskParams)): Contains risk parameters (liquidation price, stop-loss price, take-profit price).
- **pendingPositions** (mapping(address => mapping(uint8 => uint256[]))): Tracks pending position IDs by listing address and position type (0 for long, 1 for short).
- **positionsByType** (mapping(uint8 => uint256[])): Stores position IDs by type (0 for long, 1 for short).
- **positionToken** (mapping(uint256 => address)): Maps position ID to margin token (tokenA for long, tokenB for short).
- **longIOByHeight** (mapping(uint256 => uint256)): Tracks long open interest by block height.
- **shortIOByHeight** (mapping(uint256 => uint256)): Tracks short open interest by block height.
- **historicalInterestTimestamps** (mapping(uint256 => uint256)): Stores timestamps for open interest updates.

## Structs
- **PositionCoreBase**: Contains `makerAddress` (address), `listingAddress` (address), `positionId` (uint256), `positionType` (uint8: 0 for long, 1 for short).
- **PositionCoreStatus**: Tracks `status1` (bool: false for pending, true for executable), `status2` (uint8: 0 for open, 1 for closed, 2 for cancelled).
- **PriceParams**: Stores `priceMin` (uint256), `priceMax` (uint256), `priceAtEntry` (uint256), `priceClose` (uint256), all normalized to 1e18.
- **MarginParams**: Holds `marginInitial` (uint256), `marginTaxed` (uint256), `marginExcess` (uint256), all normalized to 1e18.
- **LeverageParams**: Contains `leverageVal` (uint8), `leverageAmount` (uint256), `loanInitial` (uint256), with amounts normalized to 1e18.
- **RiskParams**: Stores `priceLiquidation` (uint256), `priceStopLoss` (uint256), `priceTakeProfit` (uint256), all normalized to 1e18.

## External Functions

### setAgent(address newAgentAddress)
- **Parameters**:
  - `newAgentAddress` (address): New ISSAgent address.
- **Behavior**: Updates the `agent` state variable for listing validation.
- **Internal Call Flow**: Directly updates `agent`. No internal or external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **agent** (state variable): Stores the ISSAgent address.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `newAgentAddress` is zero ("Invalid agent address").
- **Gas Usage Controls**: Minimal gas due to single state write.

### addMux(address mux)
- **Parameters**:
  - `mux` (address): Address of the mux contract to authorize.
- **Behavior**: Adds a mux contract to the authorized list, enabling it to call `SIUpdate` or `removePositionIndex`. Emits `MuxAdded`.
- **Internal Call Flow**: Validates `mux != address(0)` and `!muxes[mux]`. Sets `muxes[mux] = true`. Emits `MuxAdded`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `muxes`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `mux` is zero ("Invalid mux address") or already authorized ("Mux already exists").
- **Gas Usage Controls**: Minimal gas due to single mapping update.

### removeMux(address mux)
- **Parameters**:
  - `mux` (address): Address of the mux contract to deauthorize.
- **Behavior**: Removes a mux contract from the authorized list. Emits `MuxRemoved`.
- **Internal Call Flow**: Validates `muxes[mux]`. Sets `muxes[mux] = false`. Emits `MuxRemoved`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `muxes`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `mux` is not authorized ("Mux does not exist").
- **Gas Usage Controls**: Minimal gas due to single mapping update.

### getMuxesView()
- **Parameters**: None.
- **Behavior**: Returns an array of authorized mux addresses.
- **Internal Call Flow**: Iterates over a fixed range (0 to 999) to count and collect addresses where `muxes[address] == true`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `muxes`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, fixed iteration limit (1000) for gas safety.

### SIUpdate(uint256 positionId, string coreParams, string priceData, string marginData, string leverageAndRiskParams, string tokenAndInterestParams, string positionArrayParams)
- **Parameters**:
  - `positionId` (uint256): Position ID to update.
  - `coreParams` (string): Encoded core position data (makerAddress, listingAddress, positionId, positionType, status1, status2).
  - `priceData` (string): Encoded price parameters (priceMin, priceMax, priceAtEntry, priceClose).
  - `marginData` (string): Encoded margin parameters (marginInitial, marginTaxed, marginExcess).
  - `leverageAndRiskParams` (string): Encoded leverage and risk parameters (leverageVal, leverageAmount, loanInitial, priceLiquidation, priceStopLoss, priceTakeProfit).
  - `tokenAndInterestParams` (string): Encoded token and interest data (token, longIO, shortIO, timestamp).
  - `positionArrayParams` (string): Encoded array updates (listingAddress, positionType, addToPending, addToActive).
- **Behavior**: Updates position data for an authorized mux without validation, parsing encoded strings to update respective mappings. Does not handle transfers or execution logic.
- **Internal Call Flow**: Restricted by `onlyMux`. Calls `parseCoreParams`, `parsePriceParams`, `parseMarginParams`, `parseLeverageAndRiskParams`, `parseTokenAndInterest`, and `parsePositionArrays` to decode and store data in respective mappings. Increments `historicalInterestHeight` and updates `positionCount` if needed. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `priceParams`, `marginParams`, `leverageParams`, `riskParams`, `positionToken`, `pendingPositions`, `positionsByType`, `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps`, `positionCount`, `historicalInterestHeight`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `MarginParams`, `LeverageParams`, `RiskParams`.
- **Restrictions**:
  - Restricted to `onlyMux`.
  - No validation; assumes valid input from authorized muxes.
- **Gas Usage Controls**: Minimal gas with single mapping updates per parameter set; array operations use push.

### removePositionIndex(uint256 positionId, uint8 positionType, address listingAddress)
- **Parameters**:
  - `positionId` (uint256): Position ID to remove.
  - `positionType` (uint8): 0 for long, 1 for short.
  - `listingAddress` (address): Listing contract address.
- **Behavior**: Removes a position from `pendingPositions` or `positionsByType` arrays for an authorized mux, typically after closure or cancellation.
- **Internal Call Flow**: Restricted by `onlyMux`. Iterates `pendingPositions[listingAddress][positionType]` and `positionsByType[positionType]`, using pop-and-swap to remove `positionId`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `pendingPositions`, `positionsByType`.
- **Restrictions**:
  - Restricted to `onlyMux`.
- **Gas Usage Controls**: Pop-and-swap minimizes gas for array operations.

### positionByIndex(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID.
- **Behavior**: Returns all position data (core, status, price, margin, leverage, risk, token) for the given `positionId`.
- **Internal Call Flow**: Retrieves data from `positionCoreBase`, `positionCoreStatus`, `priceParams`, `marginParams`, `leverageParams`, `riskParams`, `positionToken`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `priceParams`, `marginParams`, `leverageParams`, `riskParams`, `positionToken`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `MarginParams`, `LeverageParams`, `RiskParams`.
- **Restrictions**: Reverts if `positionId` is invalid ("Invalid position").
- **Gas Usage Controls**: Minimal gas, view function.

### PositionsByTypeView(uint8 positionType, uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `positionType` (uint8): 0 for long, 1 for short.
  - `startIndex` (uint256): Starting index in `positionsByType`.
  - `maxIterations` (uint256): Maximum positions to return.
- **Behavior**: Returns active position IDs from `positionsByType` starting at `startIndex`, up to `maxIterations`.
- **Internal Call Flow**: Iterates `positionsByType[positionType]` from `startIndex` up to `maxIterations`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `positionsByType`.
- **Restrictions**: Reverts if `positionType > 1` ("Invalid position type").
- **Gas Usage Controls**: View function, `maxIterations` limits gas.

### PositionsByAddressView(address maker, uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `maker` (address): Position owner.
  - `startIndex` (uint256): Starting index.
  - `maxIterations` (uint256): Maximum positions to return.
- **Behavior**: Returns pending position IDs for `maker` from all positions, starting at `startIndex`, up to `maxIterations`.
- **Internal Call Flow**: Iterates positions from `startIndex` to `positionCount`, collecting IDs where `positionCoreBase.makerAddress == maker` and `status1 == false`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `positionCount`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, `maxIterations` limits gas.

### TotalActivePositionsView()
- **Parameters**: None.
- **Behavior**: Returns the count of active positions (`status1 == true`, `status2 == 0`) across all positions.
- **Internal Call Flow**: Iterates `positionCoreBase` up to `positionCount`, counting valid active positions. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `positionCount`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, bounded by `positionCount`.

### queryInterest(uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `startIndex` (uint256): Starting block height.
  - `maxIterations` (uint256): Maximum entries to return.
- **Behavior**: Returns open interest (`longIOByHeight`, `shortIOByHeight`) and `historicalInterestTimestamps` from `startIndex` up to `maxIterations`.
- **Internal Call Flow**: Iterates `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps` from `startIndex` up to `maxIterations`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, `maxIterations` limits gas.

### PositionHealthView(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID.
- **Behavior**: Returns `marginRatio`, `distanceToLiquidation`, and `estimatedProfitLoss` for the position, calculated using current price and position parameters.
- **Internal Call Flow**: Retrieves position data from `positionCoreBase`, `marginParams`, `priceParams`, `leverageParams`, `riskParams`, `positionToken`. Calls `ISSListing.prices` (input: `listingAddress`, returns: `uint256`) and `ISSListing.tokenA`/`tokenB` (returns: `address`) for token and price. Normalizes price with `normalizePrice` using `IERC20.decimals`. Calculates `marginRatio` as `(marginTaxed + marginExcess) / (marginInitial * leverageVal)`, `distanceToLiquidation` as the difference from `priceLiquidation`, and `estimatedProfitLoss` using payout formulas (long: `(taxedMargin + excessMargin + leverageVal * marginInitial) / currentPrice - loanInitial`; short: `(priceAtEntry - currentPrice) * marginInitial * leverageVal + (taxedMargin + excessMargin) * currentPrice / DECIMAL_PRECISION`). No transfers or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `marginParams`, `priceParams`, `leverageParams`, `riskParams`, `positionToken`.
  - **Structs**: `PositionCoreBase`, `MarginParams`, `PriceParams`, `LeverageParams`, `RiskParams`.
- **Restrictions**: Reverts if `positionId` is invalid ("Invalid position") or price is zero ("Invalid price").
- **Gas Usage Controls**: View function, minimal gas with single external call.

### AggregateMarginByToken(address tokenA, address tokenB, uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `tokenA` (address): First token in the pair.
  - `tokenB` (address): Second token in the pair.
  - `startIndex` (uint256): Starting index.
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Returns arrays of maker addresses and their initial margins for positions associated with the token pair, starting at `startIndex`, up to `maxIterations`.
- **Internal Call Flow**: Calls `ISSAgent.getListing` (input: `tokenA`, `tokenB`, returns: `listingAddress`). Iterates `positionsByType[0]` and `positionsByType[1]` up to `maxIterations`, collecting `makerAddress` and `marginInitial` from `positionCoreBase` and `marginParams`. No transfers or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `marginParams`, `positionsByType`.
- **Restrictions**: Reverts if `listingAddress` is zero ("Invalid listing").
- **Gas Usage Controls**: View function, `maxIterations` limits gas.

### OpenInterestTrend(address listingAddress, uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `startIndex` (uint256): Starting index.
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Returns arrays of leverage amounts and timestamps for open positions associated with `listingAddress`, starting at `startIndex`, up to `maxIterations`.
- **Internal Call Flow**: Iterates positions up to `positionCount`, collecting `leverageAmount` from `leverageParams` and `historicalInterestTimestamps` for positions with `status2 == 0` and matching `listingAddress`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `leverageParams`, `historicalInterestTimestamps`, `positionCount`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, `maxIterations` limits gas.

### LiquidationRiskCount(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Returns the count of positions at liquidation risk (within 5% of `priceLiquidation`) for the given `listingAddress`.
- **Internal Call Flow**: Iterates positions up to `positionCount` and `maxIterations`, checking `status2 == 0` and `listingAddress`. Fetches `currentPrice` via `ISSListing.prices` (input: `token`, returns: `uint256`) and `tokenA`/`tokenB` via `ISSListing`. Normalizes price with `normalizePrice`. Counts positions where `currentPrice` is within 5% of `riskParams.priceLiquidation` (long: `currentPrice <= priceLiquidation + threshold`; short: `currentPrice >= priceLiquidation - threshold`). No transfers or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `riskParams`, `positionToken`, `positionCount`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, `maxIterations` limits gas.

## Additional Details
- **Decimal Handling**: Uses `DECIMAL_PRECISION` (1e18) for normalization across token decimals, with `IERC20.decimals()` for token-specific precision (assumes `decimals <= 18`).
- **Execution Deferral**: Unlike `SSIsolatedDriver`, `SIStorage` does not handle position creation (`enterLong`, `enterShort`, `drive`), closure (`closeLongPosition`, `closeShortPosition`, `drift`), cancellation (`cancelPosition`), or margin/risk updates (`addExcessMargin`, `updateSL`, `updateTP`). These are deferred to other contracts, with `SIUpdate` and `removePositionIndex` allowing muxes to update storage directly.
- **Mux Integration**: `muxes` mapping authorizes external contracts to call `SIUpdate` and `removePositionIndex`. `SIUpdate` uses encoded strings to update position data without validation, assuming trusted mux input.
- **Position Lifecycle**: Supports pending (`status1 == false`, `status2 == 0`), executable (`status1 == true`, `status2 == 0`), closed (`status2 == 1`), or cancelled (`status2 == 2`) states, updated via `SIUpdate`.
- **Events**: Emits `MuxAdded`, `MuxRemoved`, and `PositionClosed` (for `SIUpdate` closures).
- **Gas Optimization**: Uses `maxIterations` for view functions, pop-and-swap for array operations in `removePositionIndex`, and fixed iteration limit (1000) in `getMuxesView` for gas safety.
- **Safety**: Employs explicit casting, no inline assembly, and modular parsing functions (`parseCoreParams`, `parsePriceParams`, etc.) for robust updates. No reentrancy protection as state-changing functions (`SIUpdate`, `removePositionIndex`) are restricted to `onlyMux`, and view functions are safe.
- **Listing Validation**: Relies on `ISSAgent.getListing` for token pair validation in view functions like `AggregateMarginByToken`.
- **Token Usage**: Supports tokenA margins for long positions and tokenB margins for short positions, tracked in `positionToken`.
