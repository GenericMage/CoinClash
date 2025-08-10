# SIStorage Contract Documentation

## Overview
The `SIStorage` contract, implemented in Solidity (^0.8.2), serves as a storage layer for trading positions in the isolated margin strategy system. It extracts and manages position-related state variables and view functions from `SSIsolatedDriver.sol`, `SSDPositionPartial.sol`, and `SSDUtilityPartial.sol`. The contract integrates with external interfaces (`ISSListing`, `ISSAgent`, `ISSLiquidityTemplate`) and uses `IERC20` for token operations and `Ownable` for administrative control. It focuses on storing position data, tracking open interest, and providing view functions without handling execution logic like position creation, closure, or margin transfers.

**SPDX License:** BSL-1.1 - Peng Protocol 2025

**Version:** 0.0.4 (last updated 2025-08-07)

**Recent Changes:**
- **2025-08-07**: Replaced hyphen-delimited strings in `SIUpdate` with structured arrays (`CoreParams`, `PriceParams`, `MarginParams`, `LeverageParams`, `RiskParams`, `TokenAndInterestParams`, `PositionArrayParams`). Added `ErrorLogged` event and detailed error messages for better debugging. Restructured `SIUpdate` for early input validation. Removed `SafeERC20`, imported `IERC20`. Added try-catch for external calls in `PositionHealthView`, `AggregateMarginByToken`, `LiquidationRiskCount`, and `normalizePrice` for graceful degradation.


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
- **CoreParams**: Used in `SIUpdate` for core position data: `makerAddress` (address), `listingAddress` (address), `corePositionId` (uint256), `positionType` (uint8), `status1` (bool), `status2` (uint8).
- **TokenAndInterestParams**: Used in `SIUpdate` for token and interest: `token` (address), `longIO` (uint256), `shortIO` (uint256), `timestamp` (uint256).
- **PositionArrayParams**: Used in `SIUpdate` for array updates: `listingAddress` (address), `positionType` (uint8), `addToPending` (bool), `addToActive` (bool).

## External Functions

### setAgent(address newAgentAddress)
- **Parameters**:
  - `newAgentAddress` (address): New ISSAgent address.
- **Behavior**: Updates the `agent` state variable for listing validation. Emits `ErrorLogged` if invalid.
- **Internal Call Flow**: Directly updates `agent`. No internal or external calls, transfers, or balance checks.
- **Mappings/Structs Used**: `agent` (state variable).
- **Restrictions**: Restricted to `onlyOwner`. Reverts if `newAgentAddress` is zero ("setAgent: invalid agent address - zero address").
- **Gas Usage Controls**: Minimal gas due to single state write.

### addMux(address mux)
- **Parameters**:
  - `mux` (address): Address of the mux contract to authorize.
- **Behavior**: Adds a mux to the authorized list, enabling `SIUpdate` and `removePositionIndex` calls. Emits `MuxAdded` or `ErrorLogged` if invalid.
- **Internal Call Flow**: Validates `mux != address(0)` and `!muxes[mux]`. Sets `muxes[mux] = true`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**: `muxes`.
- **Restrictions**: Restricted to `onlyOwner`. Reverts if `mux` is zero ("Invalid mux address: zero address") or already authorized ("Mux already authorized").
- **Gas Usage Controls**: Minimal gas due to single mapping update.

### removeMux(address mux)
- **Parameters**:
  - `mux` (address): Address of the mux contract to deauthorize.
- **Behavior**: Removes a mux from the authorized list. Emits `MuxRemoved` or `ErrorLogged` if invalid.
- **Internal Call Flow**: Validates `muxes[mux]`. Sets `muxes[mux] = false`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**: `muxes`.
- **Restrictions**: Restricted to `onlyOwner`. Reverts if `mux` is not authorized ("Mux not authorized").
- **Gas Usage Controls**: Minimal gas due to single mapping update.

### getMuxesView()
- **Parameters**: None.
- **Behavior**: Returns an array of authorized mux addresses.
- **Internal Call Flow**: Iterates over a fixed range (0 to 999) to count and collect addresses where `muxes[address] == true`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**: `muxes`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, fixed iteration limit (1000) for gas safety.

### SIUpdate(uint256 positionId, CoreParams coreData, PriceParams priceData, MarginParams marginData, LeverageParams leverageData, RiskParams riskData, TokenAndInterestParams tokenData, PositionArrayParams arrayData)
- **Parameters**:
  - `positionId` (uint256): Position ID to update.
  - `coreData` (CoreParams): Core position data (makerAddress, listingAddress, corePositionId, positionType, status1, status2).
  - `priceData` (PriceParams): Price parameters (priceMin, priceMax, priceAtEntry, priceClose).
  - `marginData` (MarginParams): Margin parameters (marginInitial, marginTaxed, marginExcess).
  - `leverageData` (LeverageParams): Leverage parameters (leverageVal, leverageAmount, loanInitial).
  - `riskData` (RiskParams): Risk parameters (priceLiquidation, priceStopLoss, priceTakeProfit).
  - `tokenData` (TokenAndInterestParams): Token and interest data (token, longIO, shortIO, timestamp).
  - `arrayData` (PositionArrayParams): Array updates (listingAddress, positionType, addToPending, addToActive).
- **Behavior**: Updates position data for an authorized mux without validation, using structured arrays. Emits `ErrorLogged` for invalid inputs.
- **Internal Call Flow**: Restricted by `onlyMux`. Validates `positionId != 0` and `coreData` addresses. Calls `parseCoreParams`, `parsePriceParams`, `parseMarginParams`, `parseLeverageAndRiskParams`, `parseTokenAndInterest`, `parsePositionArrays`. Increments `historicalInterestHeight` and updates `positionCount` if needed. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**: All mappings and structs.
- **Restrictions**: Restricted to `onlyMux`. Reverts if `positionId` is zero ("SIUpdate: position ID cannot be zero") or core data addresses are invalid ("SIUpdate: invalid maker or listing address").
- **Gas Usage Controls**: Minimal gas with single mapping updates; array operations use push.

### removePositionIndex(uint256 positionId, uint8 positionType, address listingAddress)
- **Parameters**:
  - `positionId` (uint256): Position ID to remove.
  - `positionType` (uint8): 0 for long, 1 for short.
  - `listingAddress` (address): Listing contract address.
- **Behavior**: Removes a position from `pendingPositions` or `positionsByType` arrays. Emits `ErrorLogged` for invalid inputs.
- **Internal Call Flow**: Restricted by `onlyMux`. Validates `positionId != 0` and `listingAddress != address(0)`. Uses pop-and-swap to remove `positionId`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**: `pendingPositions`, `positionsByType`.
- **Restrictions**: Reverts if `positionId` is zero ("removePositionIndex: position ID cannot be zero") or `listingAddress` is zero ("removePositionIndex: listing address cannot be zero").
- **Gas Usage Controls**: Pop-and-swap minimizes gas.

### positionByIndex(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID.
- **Behavior**: Returns all position data (core, status, price, margin, leverage, risk, token).
- **Internal Call Flow**: Retrieves data from all mappings. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**: All mappings and structs except `pendingPositions`, `positionsByType`, `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps`.
- **Restrictions**: Reverts if `positionId` is invalid ("positionByIndex: invalid position ID").
- **Gas Usage Controls**: Minimal gas, view function.

### PositionsByTypeView(uint8 positionType, uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `positionType` (uint8): 0 for long, 1 for short.
  - `startIndex` (uint256): Starting index in `positionsByType`.
  - `maxIterations` (uint256): Maximum positions to return.
- **Behavior**: Returns active position IDs from `positionsByType` starting at `startIndex`, up to `maxIterations`.
- **Internal Call Flow**: Validates `positionType <= 1`. Iterates `positionsByType[positionType]`. Returns empty array if `startIndex` exceeds length. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**: `positionsByType`.
- **Restrictions**: Reverts if `positionType > 1` ("PositionsByTypeView: invalid position type").
- **Gas Usage Controls**: View function, `maxIterations` limits gas.

### PositionsByAddressView(address maker, uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `maker` (address): Position owner.
  - `startIndex` (uint256): Starting index.
  - `maxIterations` (uint256): Maximum positions to return.
- **Behavior**: Returns pending position IDs for `maker` starting at `startIndex`, up to `maxIterations`.
- **Internal Call Flow**: Validates `maker != address(0)`. Iterates positions from `startIndex` to `positionCount`, collecting IDs where `makerAddress == maker` and `status1 == false`. Returns empty array if `startIndex` exceeds `positionCount`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**: `positionCoreBase`, `positionCoreStatus`, `positionCount`.
- **Restrictions**: Reverts if `maker` is zero ("PositionsByAddressView: invalid maker address").
- **Gas Usage Controls**: View function, `maxIterations` limits gas.

### TotalActivePositionsView()
- **Parameters**: None.
- **Behavior**: Returns count of active positions (`status1 == true`, `status2 == 0`).
- **Internal Call Flow**: Iterates `positionCoreBase` up to `positionCount`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**: `positionCoreBase`, `positionCoreStatus`, `positionCount`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, bounded by `positionCount`.

### queryInterest(uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `startIndex` (uint256): Starting block height.
  - `maxIterations` (uint256): Maximum entries to return.
- **Behavior**: Returns `longIOByHeight`, `shortIOByHeight`, and `historicalInterestTimestamps` from `startIndex` up to `maxIterations`.
- **Internal Call Flow**: Returns empty arrays if `startIndex` exceeds `positionCount`. Iterates mappings up to `maxIterations`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**: `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, `maxIterations` limits gas.

### PositionHealthView(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID.
- **Behavior**: Returns `marginRatio`, `distanceToLiquidation`, and `estimatedProfitLoss` using current price and position parameters.
- **Internal Call Flow**: Validates `positionId`. Retrieves data from mappings. Calls `ISSListing.prices` and `ISSListing.tokenA`/`tokenB` with try-catch. Normalizes price with `normalizePrice` using `IERC20.decimals`. Calculates `marginRatio` as `(marginTaxed + marginExcess) / (marginInitial * leverageVal)`, `distanceToLiquidation` as difference from `priceLiquidation`, and `estimatedProfitLoss` (long: `(taxedMargin + excessMargin + leverageVal * marginInitial) / currentPrice - loanInitial`; short: `(priceAtEntry - currentPrice) * marginInitial * leverageVal + (taxedMargin + excessMargin) * currentPrice / DECIMAL_PRECISION`). No transfers or balance checks.
- **Mappings/Structs Used**: `positionCoreBase`, `marginParams`, `priceParams`, `leverageParams`, `riskParams`, `positionToken`.
- **Restrictions**: Reverts if `positionId` is invalid ("PositionHealthView: invalid position ID") or price is zero ("PositionHealthView: invalid price returned").
- **Gas Usage Controls**: View function, minimal gas with single external call.

### AggregateMarginByToken(address tokenA, address tokenB, uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `tokenA` (address): First token in the pair.
  - `tokenB` (address): Second token in the pair.
  - `startIndex` (uint256): Starting index.
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Returns maker addresses and initial margins for positions of the token pair, starting at `startIndex`, up to `maxIterations`.
- **Internal Call Flow**: Calls `ISSAgent.getListing` with try-catch. Iterates `positionsByType[0]` and `positionsByType[1]` up to `maxIterations`, collecting `makerAddress` and `marginInitial`. Returns empty arrays if `startIndex` exceeds total positions. No transfers or balance checks.
- **Mappings/Structs Used**: `positionCoreBase`, `marginParams`, `positionsByType`.
- **Restrictions**: Reverts if `listingAddress` is zero ("AggregateMarginByToken: invalid listing address").
- **Gas Usage Controls**: View function, `maxIterations` limits gas.

### OpenInterestTrend(address listingAddress, uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `startIndex` (uint256): Starting index.
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Returns leverage amounts and timestamps for open positions of `listingAddress`, starting at `startIndex`, up to `maxIterations`.
- **Internal Call Flow**: Validates `listingAddress != address(0)`. Iterates positions up to `positionCount`, collecting `leverageAmount` and `historicalInterestTimestamps` for `status2 == 0`. Returns empty arrays if `startIndex` exceeds `positionCount`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**: `positionCoreBase`, `positionCoreStatus`, `leverageParams`, `historicalInterestTimestamps`, `positionCount`.
- **Restrictions**: Reverts if `listingAddress` is zero ("OpenInterestTrend: invalid listing address").
- **Gas Usage Controls**: View function, `maxIterations` limits gas.

### LiquidationRiskCount(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Returns count of positions at liquidation risk (within 5% of `priceLiquidation`) for `listingAddress`.
- **Internal Call Flow**: Validates `listingAddress != address(0)`. Iterates positions up to `positionCount` and `maxIterations`, checking `status2 == 0`. Fetches `currentPrice` via `ISSListing.prices` and `tokenA`/`tokenB` with try-catch. Normalizes price with `normalizePrice`. Counts positions within 5% of `priceLiquidation` (long: `currentPrice <= priceLiquidation + threshold`; short: `currentPrice >= priceLiquidation - threshold`). No transfers or balance checks.
- **Mappings/Structs Used**: `positionCoreBase`, `positionCoreStatus`, `riskParams`, `positionToken`, `positionCount`.
- **Restrictions**: Reverts if `listingAddress` is zero ("LiquidationRiskCount: invalid listing address").
- **Gas Usage Controls**: View function, `maxIterations` limits gas.

## Additional Details
- **Decimal Handling**: Uses `DECIMAL_PRECISION` (1e18) for normalization, with `IERC20.decimals()` for token-specific precision (handles `decimals <= 18` or `> 18`).
- **Execution Deferral**: Defers execution logic (position creation, closure, margin/risk updates) to other contracts. `SIUpdate` and `removePositionIndex` allow muxes to update storage.
- **Mux Integration**: `muxes` authorizes contracts for `SIUpdate` and `removePositionIndex`. `SIUpdate` uses structured arrays for robust updates.
- **Position Lifecycle**: Supports pending (`status1 == false`, `status2 == 0`), executable (`status1 == true`, `status2 == 0`), closed (`status2 == 1`), or cancelled (`status2 == 2`) states.
- **Events**: Emits `MuxAdded`, `MuxRemoved`, `PositionClosed`, and `ErrorLogged` for debugging.
- **Gas Optimization**: Uses `maxIterations`, pop-and-swap in `removePositionIndex`, and fixed iteration (1000) in `getMuxesView`.
- **Safety**: Employs explicit casting, no inline assembly, try-catch for external calls, and modular parsing functions. No reentrancy protection needed due to `onlyMux` restrictions.
- **Listing Validation**: Uses `ISSAgent.getListing` with try-catch for token pair validation.
- **Token Usage**: Tracks tokenA (long) and tokenB (short) margins in `positionToken`.