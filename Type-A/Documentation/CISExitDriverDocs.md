# CISExitDriver Contract Documentation

## Overview
The `CISExitDriver` contract, implemented in Solidity (^0.8.2), manages the closure and cancellation of trading positions for long and short isolated margin strategies, inheriting from `CISExitPartial`. It supports single position closure (`closeLongPosition`, `closeShortPosition`), bulk operations (`closeAllLongs`, `closeAllShorts`, `cancelAllLongs`, `cancelAllShorts`), and Hyx-driven closures (`drift`). It integrates with `ISSListing` (equivalent to `ICCListing`), `ISIStorage`, and `ISSAgent` interfaces, using `IERC20` for token operations, `ReentrancyGuard` for protection, and `Ownable` for control. Margins are deducted via `ISIStorage`, and payouts are processed through `ISSListing.ssUpdate`. Positions with zero min/max entry prices are not executed immediately, as execution is handled externally (e.g., `CISExecutionDriver`).

**Inheritance Tree**: `CISExitDriver` → `CISExitPartial` → `ReentrancyGuard` → `Ownable`

**SPDX License**: BSL-1.1 - Peng Protocol 2025

**Versions**
- `CISExitDriver`: 0.0.9 (last updated 2025-08-10)
- `CISExitPartial`: 0.0.13 (last updated 2025-08-10)
- **Documentation**: 0.0.6 (updated 2025-08-10)

**Changes**:
- 2025-08-10: Added `_getCurrentPrice` to resolve undeclared identifier errors; integrated `closeAllLongs`, `closeAllShorts`, `cancelAllLongs`, `cancelAllShorts`, `_closeAllPositions`, `_cancelAllPositions` from `CISExtraDriver` v0.0.1; updated versions and documentation.

## State Variables
- **DECIMAL_PRECISION** (uint256, constant, public, inherited): 1e18 for normalizing amounts/prices.
- **executionDriver** (address, public, inherited): Address for margin transfers, set via `setExecutionDriver`.
- **storageContract** (address, public, inherited): `ISIStorage` address for `SIUpdate`, set via `setStorageContract`.
- **agentAddress** (address, public, inherited): `ISSAgent` address for listing validation, set via `setAgent`.
- **positionIdCounter** (uint256, internal, inherited): Unique position ID counter, initialized to 0.
- **historicalInterestHeight** (uint256, internal, inherited): Tracks interest block height, initialized to 1.
- **hyxes** (address[], private): Authorized Hyx addresses for `drift`, `closeLongPosition`, `closeShortPosition`, managed via `addHyx`/`removeHyx`.

## Mappings
- **pendingEntries** (mapping(uint256 => PendingEntry), internal, inherited): Stores pending position parameters (unused in closure/cancellation).

## Structs
- **PositionCoreBase** (inherited, `ISIStorage`): `makerAddress` (address), `listingAddress` (address), `positionId` (uint256), `positionType` (uint8: 0=long, 1=short).
- **PositionCoreStatus** (inherited, `ISIStorage`): `status1` (bool: false=pending, true=executable), `status2` (uint8: 0=open, 1=closed, 2=cancelled).
- **PriceParams** (inherited, `ISIStorage`): `priceMin`, `priceMax`, `priceAtEntry`, `priceClose` (uint256, normalized to 1e18).
- **MarginParams** (inherited, `ISIStorage`): `marginInitial`, `marginTaxed`, `marginExcess` (uint256, normalized to 1e18).
- **LeverageParams** (inherited, `ISIStorage`): `leverageVal` (uint8), `leverageAmount`, `loanInitial` (uint256, normalized to 1e18).
- **RiskParams** (inherited, `ISIStorage`): `priceLiquidation`, `priceStopLoss`, `priceTakeProfit` (uint256, normalized to 1e18).
- **CoreParams** (inherited, `ISIStorage`): `makerAddress` (address), `listingAddress` (address), `corePositionId` (uint256), `positionType` (uint8), `status1` (bool), `status2` (uint8).
- **TokenAndInterestParams** (inherited, `ISIStorage`): `token` (address), `longIO`, `shortIO`, `timestamp` (uint256).
- **PositionArrayParams** (inherited, `ISIStorage`): `listingAddress` (address), `positionType` (uint8), `addToPending`, `addToActive` (bool).
- **EntryContext** (inherited): `positionId` (uint256), `listingAddress` (address), `minEntryPrice`, `maxEntryPrice`, `initialMargin`, `excessMargin` (uint256), `leverage`, `positionType` (uint8), `maker`, `token` (address).
- **PendingEntry** (inherited): `listingAddr`, `tokenAddr`, `makerAddress` (address), `positionId`, `initialMargin`, `extraMargin`, `normInitMargin`, `normExtraMargin`, `stopLoss`, `takeProfit` (uint256), `positionType`, `leverageVal` (uint8), `entryPriceStr` (string).
- **PrepPosition** (inherited): `fee`, `taxedMargin`, `leverageAmount`, `initialLoan`, `liquidationPrice` (uint256).
- **PositionData** (inherited): `coreBase` (`PositionCoreBase`), `coreStatus` (`PositionCoreStatus`), `price` (`PriceParams`), `margin` (`MarginParams`), `leverage` (`LeverageParams`), `risk` (`RiskParams`), `token` (address).
- **ListingPayoutUpdate** (`ISSListing`): `payoutType` (uint8), `recipient` (address), `required` (uint256, denormalized).

## Formulas
- **Payout (Long)** (v0.0.10): `payout = totalValue > loanInitial ? (totalValue / currentPrice) - loanInitial : 0`, `totalValue = marginTaxed + marginExcess + leverageAmount` (`_computePayoutLong`).
- **Payout (Short)** (v0.0.10): `payout = profit + (marginTaxed + marginExcess) * currentPrice / DECIMAL_PRECISION`, `profit = (priceAtEntry - currentPrice) * marginInitial * leverageVal` (`_computePayoutShort`).
- Inherited formulas (unused in closure/cancellation): fee, taxed margin, leverage amount, initial loan, liquidation price (from `CISPositionPartial`).

## External Functions (CISExitDriver)
### addHyx(address hyx)
- **Parameters**: `hyx` (address).
- **Behavior**: Adds `hyx` to `hyxes` array. Emits `HyxAdded`.
- **Call Flow**: Validates `hyx != address(0)` (`"Invalid Hyx address"`) and not in `hyxes` (`"Hyx already exists"`). Appends `hyx`.
- **Restrictions**: `onlyOwner`.
- **Gas**: Minimal (array push).

### removeHyx(address hyx)
- **Parameters**: `hyx` (address).
- **Behavior**: Removes `hyx` from `hyxes`. Emits `HyxRemoved`.
- **Call Flow**: Validates `hyx != address(0)` (`"Invalid Hyx address"`). Swaps `hyx` with last element, pops array. Reverts if not found (`"Hyx not found"`).
- **Restrictions**: `onlyOwner`.
- **Gas**: Minimal (pop-and-swap).

### getHyxes()
- **Returns**: `hyxesList` (address[]).
- **Behavior**: Returns `hyxes` array.
- **Call Flow**: Direct array access.
- **Restrictions**: None (view).
- **Gas**: Minimal.

### closeLongPosition(uint256 positionId, address caller)
- **Parameters**: `positionId` (uint256), `caller` (address, position owner).
- **Behavior**: Closes long position, pays tokenB to `msg.sender` via `ISSListing.ssUpdate`. Emits `PositionClosed`.
- **Call Flow**: Validates `positionId` (`ISIStorage.positionCoreBase`), `status2 == 0` (`"Position already closed"`), `caller == makerAddress` (`"Caller does not match maker"`). If `caller != msg.sender`, checks `msg.sender` in `hyxes` (`"Caller is not a Hyx"`). Calls `_finalizeClosePosition` (uses `_getCurrentPrice`, `_computePayoutLong`, `_deductMarginAndRemoveToken`, `_executePayoutUpdate`, `SIUpdate`, `removePositionIndex`). Emits `PositionClosed`.
- **Restrictions**: `nonReentrant`.
- **Gas**: Single position, pop-and-swap.

### closeShortPosition(uint256 positionId, address caller)
- **Parameters**: Same as `closeLongPosition`.
- **Behavior**: Closes short position, pays tokenA to `msg.sender`. Emits `PositionClosed`.
- **Call Flow**: Similar to `closeLongPosition`, uses `_computePayoutShort`, tokenA payout, tokenB margin deduction.
- **Restrictions**: `nonReentrant`.
- **Gas**: Single position, pop-and-swap.

### cancelPosition(uint256 positionId)
- **Parameters**: `positionId` (uint256).
- **Behavior**: Cancels position, returns margin to `msg.sender`. Emits `PositionCancelled`.
- **Call Flow**: Validates `positionId` (`ISIStorage.positionCoreBase`), `status2 == 0` (`"Position already closed"`), `makerAddress == msg.sender` (`"Caller not maker"`). Calls `_executeCancelPosition` (uses `_deductMarginAndRemoveToken`, `SIUpdate`, `removePositionIndex`, `ISSListing.ssUpdate`). Emits `PositionCancelled`.
- **Restrictions**: `nonReentrant`.
- **Gas**: Single position, pop-and-swap.

### drift(uint256 positionId, address maker)
- **Parameters**: `positionId` (uint256), `maker` (address).
- **Behavior**: Closes position for `maker`, pays to `msg.sender` (Hyx). Emits `PositionClosed`.
- **Call Flow**: Validates `positionId`, `status2 == 0`, `makerAddress == maker` (`"Maker mismatch"`). Calls `closeLongPosition` or `closeShortPosition` based on `positionType`. Requires `msg.sender` in `hyxes` (`onlyHyx`).
- **Restrictions**: `nonReentrant`, `onlyHyx`.
- **Gas**: Single position, external call optimized.

### closeAllLongs(address listingAddress, uint256 maxIterations)
- **Parameters**: `listingAddress` (address), `maxIterations` (uint256).
- **Behavior**: Closes all caller-owned long positions for `listingAddress`. Emits `PositionClosed` per position.
- **Call Flow**: Validates `listingAddress != address(0)` (`"closeAllLongs: Invalid listing address"`) and `ISSAgent.isValidListing`. Calls `_closeAllPositions` (positionType=0).
- **Restrictions**: `nonReentrant`.
- **Gas**: Controlled by `maxIterations`, `gasleft() >= 50000`, pop-and-swap.

### closeAllShorts(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `closeAllLongs`.
- **Behavior**: Closes all caller-owned short positions. Emits `PositionClosed`.
- **Call Flow**: Same as `closeAllLongs`, uses `_closeAllPositions` (positionType=1).
- **Restrictions**: `nonReentrant`.
- **Gas**: Same as `closeAllLongs`.

### cancelAllLongs(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `closeAllLongs`.
- **Behavior**: Cancels all caller-owned pending long positions. Emits `PositionCancelled`.
- **Call Flow**: Validates `listingAddress != address(0)` (`"cancelAllLongs: Invalid listing address"`) and `ISSAgent.isValidListing`. Calls `_cancelAllPositions` (positionType=0).
- **Restrictions**: `nonReentrant`.
- **Gas**: Controlled by `maxIterations`, `gasleft() >= 50000`, pop-and-swap.

### cancelAllShorts(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `closeAllLongs`.
- **Behavior**: Cancels all caller-owned pending short positions. Emits `PositionCancelled`.
- **Call Flow**: Same as `cancelAllLongs`, uses `_cancelAllPositions` (positionType=1).
- **Restrictions**: `nonReentrant`.
- **Gas**: Same as `cancelAllLongs`.

## Internal Functions (CISExitPartial, Key Additions)
- **_getCurrentPrice(address listingAddress, address token)** (v0.0.13): Fetches current price from `ISSListing.prices(0)`, normalizes via `normalizePrice`. Used in `_computePayoutLong`, `_computePayoutShort`, `_prepPriceParams`. Try-catch for graceful degradation.
- **_fetchPositionData**: Fetches `PositionData` from `ISIStorage.positionByIndex`, reducing stack depth (v0.0.10).
- **_assignPositionData**: Unpacks `PositionData` for `_getPositionByIndex`.
- **_fetchPositionParams**: Prepares `SIUpdate` params, optimized for stack (v0.0.10).
- **_computePayoutLong/Short**: Calculates payouts using `PositionData`, avoids redundant calls (v0.0.10).
- **_deductMarginAndRemoveToken**: Deducts margins via `ISIStorage.AggregateMarginByToken`, updates `SIUpdate`.
- **_executePayoutUpdate**: Processes payouts via `ISSListing.ssUpdate`.
- **_updatePositionStorage**: Incremental `SIUpdate` calls for storage updates (v0.0.8).
- **_finalizeClosePosition**: Closes position, updates storage, processes payout, removes index (v0.0.7).
- **_executeCancelPosition**: Cancels position, returns margin, updates storage (v0.0.7).
- **_closeAllPositions(address listingAddress, uint8 positionType, uint256 maxIterations)** (v0.0.7): Iterates `positionsByType[positionType]`, closes caller-owned positions via `_finalizeClosePosition`. Validates listing, uses `maxIterations`, `gasleft() >= 50000`, pop-and-swap.
- **_cancelAllPositions(address listingAddress, uint8 positionType, uint256 maxIterations)** (v0.0.7): Iterates `pendingPositions[listingAddress][positionType]`, cancels caller-owned positions via `_executeCancelPosition`. Validates listing, uses `maxIterations`, `gasleft() >= 50000`, pop-and-swap.

## Additional Details
- **Decimal Handling**: `DECIMAL_PRECISION` (1e18), `IERC20.decimals()` for normalization (`normalizePrice`, `normalizeAmount`).
- **Market-Based Execution**: Handled externally, `CISExitDriver` focuses on closure/cancellation.
- **Reentrancy Protection**: `nonReentrant` on state-changing functions.
- **Gas Optimization**: Pop-and-swap, `maxIterations`, `gasleft() >= 50000`, x64 refactor (v0.0.6), stack fixes (v0.0.10).
- **Listing Validation**: `ISSAgent.isValidListing` in `_finalizeClosePosition`, `_executeCancelPosition`, `_closeAllPositions`, `_cancelAllPositions`.
- **Token Usage**: Long: tokenA margins, tokenB payouts; Short: tokenB margins, tokenA payouts.
- **Position Lifecycle**: Pending (`status1=false`, `status2=0`) → executable (`status1=true`, `status2=0`) → closed (`status2=1`) or cancelled (`status2=2`).
- **Events**: `HyxAdded`, `HyxRemoved`, `PositionClosed` (`positionId`, `maker`, `payout`), `PositionCancelled` (`positionId`, `maker`, `timestamp`), `ErrorLogged` (`reason`).
- **Hyx Integration**: `hyxes` authorizes `drift`, `closeLongPosition`, `closeShortPosition` for external contracts.
- **Safety**: Balance checks (`status2 == 0`, maker validation), explicit casting, no assembly, try-catch for external calls (`ISIStorage`, `ISSListing`, `ISSAgent`).
- **Storage**: `SIUpdate` via `ISIStorage` for position updates, `ISSListing.ssUpdate` for payouts.
