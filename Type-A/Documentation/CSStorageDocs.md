# CSStorage Contract Documentation

## Overview
The `CSStorage` contract, implemented in Solidity (^0.8.2), serves as a storage and view layer for trading position data, derived from `SSCrossDriver` but focused solely on position storage and retrieval. It integrates with external interfaces (`ISSListing`, `ISSAgent`) and uses `IERC20` for token operations and `Ownable` for administrative control. The contract manages position data updates by authorized mux contracts via `CSUpdate`, supports view functions for querying position and margin details, and ensures decimal precision across tokens. State variables and mappings are accessed directly as public, with no additional view functions, and operations adhere to gas optimization and safety mechanisms.

**Inheritance Tree:** `CSStorage` → `Ownable`

**SPDX License:** BSL-1.1 - Peng Protocol 2025

**Version:** 0.0.11 (last updated 2025-08-05)

## State Variables
- **DECIMAL_PRECISION** (uint256, constant, public): Set to 1e18 for normalizing amounts and prices across token decimals.
- **agentAddress** (address, public): Stores the address of the ISSAgent contract for listing validation.
- **positionCount** (uint256, public): Tracks the total number of positions created, used to generate unique position IDs.

## Mappings
- **makerTokenMargin** (mapping(address => mapping(address => uint256))): Tracks margin balances per maker and token, normalized to 1e18.
- **makerMarginTokens** (mapping(address => address[])): Lists tokens with non-zero margin balances for each maker.
- **positionCore1** (mapping(uint256 => PositionCore1)): Stores core position data (positionId, listingAddress, makerAddress, positionType).
- **positionCore2** (mapping(uint256 => PositionCore2)): Tracks position status (status1 for active, status2 for closed).
- **priceParams1** (mapping(uint256 => PriceParams1)): Holds price-related data (minEntryPrice, maxEntryPrice, minPrice, priceAtEntry, leverage).
- **priceParams2** (mapping(uint256 => PriceParams2)): Stores liquidation price for each position.
- **marginParams1** (mapping(uint256 => MarginParams1)): Manages margin details (initialMargin, taxedMargin, excessMargin, fee).
- **marginParams2** (mapping(uint256 => MarginParams2)): Tracks initial loan amount for each position.
- **exitParams** (mapping(uint256 => ExitParams)): Stores exit conditions (stopLossPrice, takeProfitPrice, exitPrice).
- **openInterest** (mapping(uint256 => OpenInterest)): Records leverage amount and timestamp for each position.
- **positionsByType** (mapping(uint8 => uint256[])): Lists position IDs by type (0 for long, 1 for short).
- **pendingPositions** (mapping(address => mapping(uint8 => uint256[]))): Tracks pending position IDs by listing address and position type.
- **positionToken** (mapping(uint256 => address)): Maps position ID to margin token (tokenA for long, tokenB for short).
- **longIOByHeight** (mapping(uint256 => uint256)): Tracks long open interest by block height.
- **shortIOByHeight** (mapping(uint256 => uint256)): Tracks short open interest by block height.
- **historicalInterestTimestamps** (mapping(uint256 => uint256)): Stores timestamps for open interest updates.
- **muxes** (mapping(address => bool)): Tracks authorized mux contracts for position updates.

## Structs
- **PositionCore1**: Contains `positionId` (uint256), `listingAddress` (address), `makerAddress` (address), `positionType` (uint8: 0 for long, 1 for short).
- **PositionCore2**: Includes `status1` (bool: active flag), `status2` (uint8: 0 for open, 1 for closed).
- **PriceParams1**: Stores `minEntryPrice`, `maxEntryPrice`, `minPrice`, `priceAtEntry` (uint256, normalized), `leverage` (uint8).
- **PriceParams2**: Holds `liquidationPrice` (uint256, normalized).
- **MarginParams1**: Tracks `initialMargin`, `taxedMargin`, `excessMargin`, `fee` (uint256, normalized).
- **MarginParams2**: Stores `initialLoan` (uint256, normalized).
- **ExitParams**: Includes `stopLossPrice`, `takeProfitPrice`, `exitPrice` (uint256, normalized).
- **OpenInterest**: Contains `leverageAmount` (uint256, normalized), `timestamp` (uint256).
- **CoreParams**: Defines `positionId` (uint256), `listingAddress` (address), `makerAddress` (address), `positionType` (uint8), `status1` (bool), `status2` (uint8) for `CSUpdate`.
- **PriceParams**: Includes `minEntryPrice`, `maxEntryPrice`, `minPrice`, `priceAtEntry`, `leverage`, `liquidationPrice` (uint256, uint8) for `CSUpdate`.
- **MarginParams**: Tracks `initialMargin`, `taxedMargin`, `excessMargin`, `fee`, `initialLoan` (uint256) for `CSUpdate`.
- **ExitAndInterestParams**: Stores `stopLossPrice`, `takeProfitPrice`, `exitPrice`, `leverageAmount`, `timestamp` (uint256) for `CSUpdate`.
- **MakerMarginParams**: Contains `token`, `maker`, `marginToken` (address), `marginAmount` (uint256) for `CSUpdate`.
- **PositionArrayParams**: Includes `listingAddress` (address), `positionType` (uint8), `addToPending`, `addToActive` (bool) for `CSUpdate`.
- **HistoricalInterestParams**: Stores `longIO`, `shortIO`, `timestamp` (uint256) for `CSUpdate`.

## External Functions
Each function details its parameters, behavior, internal call flow (including external call inputs/returns), restrictions, and gas controls. Mappings and structs are explained in context.

### setAgent(address newAgentAddress)
- **Parameters**:
  - `newAgentAddress` (address): New ISSAgent address.
- **Behavior**: Updates `agentAddress` for listing validation in view functions.
- **Internal Call Flow**: Validates `newAgentAddress` is non-zero, assigns to `agentAddress`. No external calls or transfers.
- **Mappings/Structs Used**:
  - **State Variable**: `agentAddress`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `newAgentAddress` is zero (`"Invalid agent address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

### addMux(address mux)
- **Parameters**:
  - `mux` (address): Address of the mux contract to authorize.
- **Behavior**: Authorizes a mux contract to call `CSUpdate`, `removePositionIndex`, and `removeToken`. Emits `MuxAdded`.
- **Internal Call Flow**: Validates `mux` is non-zero and not already authorized, sets `muxes[mux] = true`. No external calls or transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `muxes`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `mux` is zero (`"Invalid mux address"`) or already authorized (`"Mux already exists"`).
- **Gas Usage Controls**: Minimal gas due to single mapping update.

### removeMux(address mux)
- **Parameters**:
  - `mux` (address): Address of the mux contract to remove.
- **Behavior**: Revokes mux authorization, disabling access to `CSUpdate`, `removePositionIndex`, and `removeToken`. Emits `MuxRemoved`.
- **Internal Call Flow**: Validates `mux` is authorized, sets `muxes[mux] = false`. No external calls or transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `muxes`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `mux` is not authorized (`"Mux does not exist"`).
- **Gas Usage Controls**: Minimal gas due to single mapping update.

### getMuxesView()
- **Parameters**: None.
- **Behavior**: Returns an array of authorized mux addresses.
- **Internal Call Flow**: Iterates over a fixed range (0 to 999) to collect addresses where `muxes[address] == true`. No external calls or transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `muxes`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, fixed iteration limit (1000) for gas safety.

### CSUpdate(uint256 positionId, CoreParams memory coreParams, PriceParams memory priceParams, MarginParams memory marginParams, ExitAndInterestParams memory exitAndInterestParams, MakerMarginParams memory makerMarginParams, PositionArrayParams memory positionArrayParams, HistoricalInterestParams memory historicalInterestParams)
- **Parameters**:
  - `positionId` (uint256): Position ID to update.
  - `coreParams` (CoreParams): Core data (positionId, listingAddress, makerAddress, positionType, status1, status2).
  - `priceParams` (PriceParams): Price data (minEntryPrice, maxEntryPrice, minPrice, priceAtEntry, leverage, liquidationPrice).
  - `marginParams` (MarginParams): Margin data (initialMargin, taxedMargin, excessMargin, fee, initialLoan).
  - `exitAndInterestParams` (ExitAndInterestParams): Exit and interest data (stopLossPrice, takeProfitPrice, exitPrice, leverageAmount, timestamp).
  - `makerMarginParams` (MakerMarginParams): Margin and token data (token, maker, marginToken, marginAmount).
  - `positionArrayParams` (PositionArrayParams): Position array data (listingAddress, positionType, addToPending, addToActive).
  - `historicalInterestParams` (HistoricalInterestParams): Interest data (longIO, shortIO, timestamp).
- **Behavior**: Updates position data with validation, using structured parameters. Emits `UpdateFailed` on errors.
- **Internal Call Flow**:
  - Validates `positionId` non-zero.
  - Calls `CSUpdateInternal` with try-catch, emitting `UpdateFailed` with reason on failure.
  - `CSUpdateInternal`:
    - Updates `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps` if non-zero.
    - Calls helpers: `updateCoreParams`, `updatePriceParams`, `updateMarginParams`, `updateExitAndInterest`, `updateMakerMargin`, `updatePositionArrays`.
    - Each helper validates inputs, emits `UpdateFailed` if invalid.
  - No external calls or transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `marginParams1`, `marginParams2`, `exitParams`, `openInterest`, `pendingPositions`, `positionToken`, `makerTokenMargin`, `makerMarginTokens`, `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps`, `positionCount`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `PriceParams1`, `PriceParams2`, `MarginParams1`, `MarginParams2`, `ExitParams`, `OpenInterest`, `CoreParams`, `PriceParams`, `MarginParams`, `ExitAndInterestParams`, `MakerMarginParams`, `PositionArrayParams`, `HistoricalInterestParams`.
- **Restrictions**:
  - Restricted to `onlyMux`.
  - Reverts if called by unauthorized mux (`"Caller is not a mux"`) or `positionId` is zero.
- **Gas Usage Controls**: Uses structured parameters, pop-and-swap for arrays, try-catch for graceful degradation.

### removePositionIndex(uint256 positionId, uint8 positionType, address listingAddress)
- **Parameters**:
  - `positionId` (uint256): Position ID to remove.
  - `positionType` (uint8): 0 for long, 1 for short.
  - `listingAddress` (address): Listing contract address.
- **Behavior**: Removes a position from `pendingPositions` or `positionsByType` using pop-and-swap. Emits `RemovalFailed` on errors.
- **Internal Call Flow**:
  - Calls `removePositionIndexInternal` with try-catch, emitting `RemovalFailed` with reason.
  - `removePositionIndexInternal`:
    - Iterates `pendingPositions[listingAddress][positionType]` or `positionsByType[positionType]` to find and remove `positionId`.
    - Uses pop-and-swap to optimize array updates.
  - No external calls or transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `pendingPositions`, `positionsByType`.
- **Restrictions**:
  - Restricted to `onlyMux`.
  - Reverts if called by unauthorized mux or position not found (`"Position not found in arrays"`).
- **Gas Usage Controls**: Pop-and-swap minimizes gas, single iteration per array.

### removeToken(address maker, address token)
- **Parameters**:
  - `maker` (address): Margin owner.
  - `token` (address): Token to remove from margin list.
- **Behavior**: Removes a token from `makerMarginTokens` if its balance is zero, using pop-and-swap. Emits `RemovalFailed` on errors.
- **Internal Call Flow**:
  - Calls `removeTokenInternal` with try-catch, emitting `RemovalFailed` with reason.
  - `removeTokenInternal`:
    - Iterates `makerMarginTokens[maker]` to find and remove `token`.
  - No external calls or transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `makerMarginTokens`.
- **Restrictions**:
  - Restricted to `onlyMux`.
  - Reverts if called by unauthorized mux or token not found (`"Token not found in maker's list"`).
- **Gas Usage Controls**: Pop-and-swap minimizes gas, single iteration.

### positionByIndex(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID.
- **Behavior**: Returns all position data (core, price, margin, exit, token).
- **Internal Call Flow**: Retrieves data from `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `marginParams1`, `marginParams2`, `exitParams`, `positionToken`. No external calls or transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `marginParams1`, `marginParams2`, `exitParams`, `positionToken`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `PriceParams1`, `PriceParams2`, `MarginParams1`, `MarginParams2`, `ExitParams`.
- **Restrictions**: Reverts if `positionId` is invalid (`"Invalid position"`).
- **Gas Usage Controls**: Minimal gas, view function.

### PositionsByTypeView(uint8 positionType, uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `positionType` (uint8): 0 for long, 1 for short.
  - `startIndex` (uint256): Starting index.
  - `maxIterations` (uint256): Maximum positions to return.
- **Behavior**: Returns position IDs from `positionsByType` starting at `startIndex`, up to `maxIterations`.
- **Internal Call Flow**: Iterates `positionsByType[positionType]` to return up to `maxIterations` IDs. No external calls or transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `positionsByType`.
- **Restrictions**: Reverts if `positionType > 1` (`"Invalid position type"`).
- **Gas Usage Controls**: Uses `maxIterations`, view function, minimal gas.

### PositionsByAddressView(address maker, uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `maker` (address): Position owner.
  - `startIndex` (uint256): Starting index.
  - `maxIterations` (uint256): Maximum positions to return.
- **Behavior**: Returns pending position IDs for `maker` starting at `startIndex`, up to `maxIterations`.
- **Internal Call Flow**: Iterates `positionCount`, filtering by `positionCore1.makerAddress == maker` and `positionCore2.status1 == false`. No external calls or transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`.
  - **Structs**: `PositionCore1`, `PositionCore2`.
- **Restrictions**: None.
- **Gas Usage Controls**: Uses `maxIterations`, view function, low gas.

### TotalActivePositionsView()
- **Parameters**: None.
- **Behavior**: Counts active positions (`status1 == true`, `status2 == 0`).
- **Internal Call Flow**: Iterates `positionCount`, checking `positionCore1` and `positionCore2`. No external calls or transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`.
  - **Structs**: `PositionCore1`, `PositionCore2`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, full iteration, no state changes.

### queryInterest(uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `startIndex` (uint256): Starting block height.
  - `maxIterations` (uint256): Maximum entries to return.
- **Behavior**: Returns open interest (`longIOByHeight`, `shortIOByHeight`) and timestamps (`historicalInterestTimestamps`).
- **Internal Call Flow**: Iterates from `startIndex` to `startIndex + maxIterations`, retrieving data from `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps`. No external calls or transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps`.
- **Restrictions**: None.
- **Gas Usage Controls**: Uses `maxIterations`, view function, low gas.

### makerMarginIndex(address maker, uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `maker` (address): Margin owner.
  - `startIndex` (uint256): Starting index.
  - `maxIterations` (uint256): Maximum tokens to return.
- **Behavior**: Returns tokens and margins for `maker` from `makerMarginTokens` and `makerTokenMargin`.
- **Internal Call Flow**: Iterates `makerMarginTokens[maker]` from `startIndex` up to `maxIterations`, retrieving margins from `makerTokenMargin`. No external calls or transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `makerTokenMargin`, `makerMarginTokens`.
- **Restrictions**: None.
- **Gas Usage Controls**: Uses `maxIterations`, view function, minimal gas.

### PositionHealthView(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID.
- **Behavior**: Returns margin ratio, liquidation distance, and estimated profit/loss.
- **Internal Call Flow**:
  - Retrieves data from `positionCore1`, `marginParams1`, `priceParams1`, `priceParams2`, `positionToken`, `makerTokenMargin`.
  - Calls `ISSListing.tokenA()` or `tokenB()` based on `positionType` to select margin token.
  - Calls `ISSListing.prices(0)` (returns: `currentPrice`) and `normalizePrice` to adjust for token decimals.
  - Computes:
    - `marginRatio = totalMargin * DECIMAL_PRECISION / (initialMargin * leverage)`.
    - `distanceToLiquidation`: `currentPrice - liquidationPrice` (long) or `liquidationPrice - currentPrice` (short), zero if invalid.
    - `estimatedProfitLoss` for long: `(taxedMargin + totalMargin + leverage * initialMargin) / currentPrice - initialLoan`.
    - `estimatedProfitLoss` for short: `(priceAtEntry - currentPrice) * initialMargin * leverage + (taxedMargin + totalMargin) * currentPrice / DECIMAL_PRECISION`.
  - No transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `marginParams1`, `priceParams1`, `priceParams2`, `positionToken`, `makerTokenMargin`.
  - **Structs**: `PositionCore1`, `MarginParams1`, `PriceParams1`, `PriceParams2`.
- **Restrictions**: Reverts if position or price is invalid (`"Invalid position"`, `"Invalid price"`).
- **Gas Usage Controls**: Minimal gas, view function.

### AggregateMarginByToken(address tokenA, address tokenB, uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `tokenA`, `tokenB` (address): Token pair for listing.
  - `startIndex` (uint256): Starting index.
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Returns makers and margins for `tokenB` from a listing’s positions in `positionsByType`.
- **Internal Call Flow**:
  - Calls `ISSAgent.getListing` (input: `tokenA`, `tokenB`, returns: `listingAddress`).
  - Calls `ISSListing.tokenB()` to select margin token.
  - Iterates `positionsByType` for both types (0 and 1), collecting `makerTokenMargin[maker][tokenB]` for non-zero margins.
  - No transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `positionsByType`, `positionCore1`, `makerTokenMargin`.
  - **Structs**: `PositionCore1`.
- **Restrictions**: Reverts if listing is invalid (`"Invalid listing"`).
- **Gas Usage Controls**: Uses `maxIterations`, view function, minimal gas.

### OpenInterestTrend(address listingAddress, uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `startIndex` (uint256): Starting position ID.
  - `maxIterations` (uint256): Maximum positions to return.
- **Behavior**: Returns leverage amounts and timestamps for open positions (`status2 == 0`) in `listingAddress`.
- **Internal Call Flow**: Iterates `positionCount`, filtering by `positionCore1.listingAddress` and `positionCore2.status2 == 0`, retrieving `openInterest.leverageAmount` and `timestamp`. No external calls or transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `openInterest`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `OpenInterest`.
- **Restrictions**: None.
- **Gas Usage Controls**: Uses `maxIterations`, view function, minimal gas.

### LiquidationRiskCount(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Counts positions within 5% of liquidation price for a given listing.
- **Internal Call Flow**:
  - Iterates `positionCount` up to `maxIterations`, filtering by `positionCore1.listingAddress` and `positionCore2.status2 == 0`.
  - Calls `ISSListing.tokenA()` or `tokenB()` based on `positionType`.
  - Calls `ISSListing.prices(0)` (returns: `currentPrice`) and `normalizePrice` to compare `currentPrice` with `priceParams2.liquidationPrice ± 5%`.
  - Increments count for positions at risk.
  - No transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `priceParams2`, `positionToken`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `PriceParams2`.
- **Restrictions**: None.
- **Gas Usage Controls**: Uses `maxIterations`, view function, low gas.

## Additional Details
- **Decimal Handling**: Uses `DECIMAL_PRECISION` (1e18) for normalization via `normalizePrice`, which adjusts prices based on `IERC20.decimals`.
- **Gas Optimization**: Employs `maxIterations` for iteration control, pop-and-swap for array updates, and structured parameters in `CSUpdate` to reduce stack usage.
- **Listing Validation**: Uses `ISSAgent.getListing` in `AggregateMarginByToken` for listing validation.
- **Token Usage**: Long positions use `tokenA` margins, short positions use `tokenB` margins, as retrieved via `ISSListing.tokenA()` or `tokenB()`.
- **Position Lifecycle**: Managed externally by muxes via `CSUpdate`, with `status1` (active) and `status2` (closed) flags.
- **Safety**: Explicit casting, no inline assembly, try-catch for external calls, and structured parameters ensure robustness.
- **Mux Functionality**: Authorized muxes (via `muxes` mapping) update position data through `CSUpdate` and manage position arrays via `removePositionIndex` and `removeToken`.
- **No Transfers**: Unlike `SSCrossDriver`, `CSStorage` focuses solely on storage and retrieval, with no token transfers or payouts.
- **Events**: `MuxAdded`, `MuxRemoved`, `UpdateFailed`, `RemovalFailed` are emitted for administrative and error logging purposes.
