# CISPositionDriver Contract Documentation

## Overview
The `CISPositionDriver` contract, implemented in Solidity (^0.8.2), manages trading positions for long and short isolated margin strategies, inheriting functionality from `CISPositionPartial`. It integrates with external interfaces (`ISSListing`, `ISSLiquidityTemplate`, `ISSAgent`) and uses `IERC20` for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract supports position creation (`enterLong`, `enterShort`, `drive`), closure (`closeLongPosition`, `closeShortPosition`, `drift`), and Hyx operations, transferring margins to an `executionDriver` and using `SIUpdate` for storage updates, with no immediate execution for zero min/max entry price positions.

**Inheritance Tree:** `CISPositionDriver` → `CISPositionPartial`

**SPDX License:** BSL-1.1 - Peng Protocol 2025

**Version:** 0.0.4 (last updated 2025-07-20)

## State Variables
- **DECIMAL_PRECISION** (uint256, constant, public, inherited): Set to 1e18 for normalizing amounts and prices.
- **executionDriver** (address, public, inherited): Stores the address for margin transfers.
- **storageContract** (address, public, inherited): Stores the address of the storage contract for `SIUpdate`.
- **agentAddress** (address, public, inherited): Stores the address of the `ISSAgent` contract for listing validation.
- **positionIdCounter** (uint256, internal, inherited): Counter for generating unique position IDs, initialized to 0.
- **historicalInterestHeight** (uint256, internal, inherited): Tracks block height for interest updates, initialized to 1.
- **hyxes** (address[], private): Array of authorized Hyx addresses for `drift` operations.

## Mappings
- **pendingEntries** (mapping(uint256 => PendingEntry), internal, inherited): Temporary storage for position entry parameters.

## Structs
- **PositionCoreBase** (inherited): Contains `makerAddress` (address), `listingAddress` (address), `positionId` (uint256), `positionType` (uint8: 0 for long, 1 for short).
- **PositionCoreStatus** (inherited): Tracks `status1` (bool: false for pending, true for executable), `status2` (uint8: 0 for open, 1 for closed, 2 for cancelled).
- **PriceParams** (inherited): Stores `priceMin` (uint256), `priceMax` (uint256), `priceAtEntry` (uint256), `priceClose` (uint256), all normalized to 1e18.
- **MarginParams** (inherited): Holds `marginInitial` (uint256), `marginTaxed` (uint256), `marginExcess` (uint256), all normalized to 1e18.
- **LeverageParams** (inherited): Contains `leverageVal` (uint8), `leverageAmount` (uint256), `loanInitial` (uint256), with amounts normalized to 1e18.
- **RiskParams** (inherited): Stores `priceLiquidation` (uint256), `priceStopLoss` (uint256), `priceTakeProfit` (uint256), all normalized to 1e18.
- **EntryContext** (inherited): Stores `positionId` (uint256), `listingAddress` (address), `minEntryPrice` (uint256), `maxEntryPrice` (uint256), `initialMargin` (uint256), `excessMargin` (uint256), `leverage` (uint8), `positionType` (uint8), `maker` (address), `token` (address).
- **PendingEntry** (inherited): Stores `listingAddr` (address), `tokenAddr` (address), `positionId` (uint256), `positionType` (uint8), `initialMargin` (uint256), `extraMargin` (uint256), `entryPriceStr` (string), `makerAddress` (address), `leverageVal` (uint8), `stopLoss` (uint256), `takeProfit` (uint256), `normInitMargin` (uint256), `normExtraMargin` (uint256).
- **PrepPosition** (inherited): Stores `fee` (uint256), `taxedMargin` (uint256), `leverageAmount` (uint256), `initialLoan` (uint256), `liquidationPrice` (uint256).
- **PayoutUpdate** (in `ISSListing` interface): Stores `payoutType` (uint8), `recipient` (address), `required` (uint256, denormalized).

## Formulas
Formulas are inherited from `CISPositionPartial` and align with `SSIsolatedDriver` specifications.

1. **Fee Calculation**:
   - **Formula**: `fee = (leverageVal - 1) * normMarginInitial / 100`
   - **Used in**: `_finalizeEntryFees` (via `computeFee`).
   - **Description**: Computes fee based on leverage and normalized initial margin.

2. **Taxed Margin**:
   - **Formula**: `marginTaxed = normInitMargin - fee`
   - **Used in**: `_computeEntryParams`.
   - **Description**: Margin after fee deduction.

3. **Leverage Amount**:
   - **Formula**: `leverageAmount = normInitMargin * leverageVal`
   - **Used in**: `_computeEntryParams`.
   - **Description**: Leveraged position size.

4. **Initial Loan (Long)**:
   - **Formula**: `loanInitial = leverageAmount / minPrice`
   - **Used in**: `_computeEntryParams`.
   - **Description**: Loan for long positions based on minimum entry price.

5. **Initial Loan (Short)**:
   - **Formula**: `loanInitial = leverageAmount * minPrice`
   - **Used in**: `_computeEntryParams`.
   - **Description**: Loan for short positions based on minimum entry price.

6. **Liquidation Price (Long)**:
   - **Formula**: `priceLiquidation = marginRatio < minPrice ? minPrice - marginRatio : 0`, where `marginRatio = (taxedMargin + normExtraMargin) / leverageAmount`
   - **Used in**: `_computeEntryParams`.
   - **Description**: Liquidation price for long positions.

7. **Liquidation Price (Short)**:
   - **Formula**: `priceLiquidation = minPrice + marginRatio`
   - **Used in**: `_computeEntryParams`.
   - **Description**: Liquidation price for short positions.

8. **Liquidity Limit (Long)**:
   - **Formula**: `loanInitial <= yLiquid * (101 - leverageVal) / 100`, where `yLiquid` is tokenB liquidity
   - **Used in**: `_validateLeverageLimit`.
   - **Description**: Ensures initial loan does not exceed tokenB liquidity, scaled by leverage.

9. **Liquidity Limit (Short)**:
   - **Formula**: `loanInitial <= xLiquid * (101 - leverageVal) / 100`, where `xLiquid` is tokenA liquidity
   - **Used in**: `_validateLeverageLimit`.
   - **Description**: Ensures initial loan does not exceed tokenA liquidity, scaled by leverage.

10. **Payout (Long)**:
    - **Formula**: `payout = totalValue > loanInitial ? (totalValue / currentPrice) - loanInitial : 0`, where `totalValue = taxedMargin + excessMargin + leverageAmount`
    - **Used in**: `_computePayoutLong`.
    - **Description**: Payout for long position closure in tokenB.

11. **Payout (Short)**:
    - **Formula**: `payout = profit + (taxedMargin + excessMargin) * currentPrice / DECIMAL_PRECISION`, where `profit = (priceAtEntry - currentPrice) * initialMargin * leverageVal`
    - **Used in**: `_computePayoutShort`.
    - **Description**: Payout for short position closure in tokenA.

## External Functions
Each function details its parameters, behavior, internal call flow (including external call inputs/returns, transfer destinations, and balance checks), restrictions, and gas controls. Mappings and structs are explained in context. Functions align with `SSIsolatedDriver` but use `executionDriver` for margin transfers and `SIUpdate` for storage.

### setExecutionDriver(address _executionDriver)
- **Parameters**:
  - `_executionDriver` (address): New execution driver address.
- **Behavior**: Updates `executionDriver` state variable for margin transfers.
- **Internal Call Flow**: Directly updates `executionDriver`. No internal or external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **State Variable**: `executionDriver`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `_executionDriver` is zero (`"Invalid execution driver address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

### setStorageContract(address _storageContract)
- **Parameters**:
  - `_storageContract` (address): New storage contract address.
- **Behavior**: Updates `storageContract` for `SIUpdate` calls.
- **Internal Call Flow**: Directly updates `storageContract`. No internal or external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **State Variable**: `storageContract`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `_storageContract` is zero (`"Invalid storage address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

### setAgent(address newAgentAddress)
- **Parameters**:
  - `newAgentAddress` (address): New `ISSAgent` address.
- **Behavior**: Updates `agentAddress` for listing validation.
- **Internal Call Flow**: Directly updates `agentAddress`. No internal or external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **State Variable**: `agentAddress`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `newAgentAddress` is zero (`"Invalid agent address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

### getExecutionDriver()
- **Parameters**: None.
- **Behavior**: Returns the `executionDriver` address.
- **Internal Call Flow**: Returns `executionDriver`. No internal or external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **State Variable**: `executionDriver`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### getAgentAddress()
- **Parameters**: None.
- **Behavior**: Returns the `agentAddress`.
- **Internal Call Flow**: Returns `agentAddress`. No internal or external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **State Variable**: `agentAddress`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### addHyx(address hyx)
- **Parameters**:
  - `hyx` (address): Address of the Hyx contract to authorize.
- **Behavior**: Adds a Hyx contract to the authorized list, enabling it to call `drift`. Emits `HyxAdded`.
- **Internal Call Flow**: Validates `hyx != address(0)` and ensures `hyx` is not already in `hyxes`. Appends `hyx` to `hyxes`. Emits `HyxAdded`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Array**: `hyxes`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `hyx` is zero (`"Invalid Hyx address"`) or already authorized (`"Hyx already exists"`).
- **Gas Usage Controls**: Minimal gas due to single array push.

### removeHyx(address hyx)
- **Parameters**:
  - `hyx` (address): Address of the Hyx contract to deauthorize.
- **Behavior**: Removes a Hyx contract from the authorized list. Emits `HyxRemoved`.
- **Internal Call Flow**: Validates `hyx != address(0)`. Finds `hyx` in `hyxes`, swaps with the last element, and pops. Emits `HyxRemoved`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Array**: `hyxes`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `hyx` is zero (`"Invalid Hyx address"`) or not found (`"Hyx not found"`).
- **Gas Usage Controls**: Minimal gas with pop-and-swap.

### getHyxes()
- **Parameters**: None.
- **Behavior**: Returns the array of authorized Hyx addresses.
- **Internal Call Flow**: Returns `hyxes`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Array**: `hyxes`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### enterLong(address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `minEntryPrice` (uint256): Minimum entry price (normalized).
  - `maxEntryPrice` (uint256): Maximum entry price (normalized).
  - `initialMargin` (uint256): Initial margin (denormalized).
  - `excessMargin` (uint256): Excess margin (denormalized).
  - `leverage` (uint8): Leverage multiplier (2–100).
  - `stopLossPrice` (uint256): Stop-loss price (normalized).
  - `takeProfitPrice` (uint256): Take-profit price (normalized).
- **Behavior**: Creates a pending long position for `msg.sender`, transferring margins in tokenA to `executionDriver`, computing fees, loans, and liquidation prices, and storing data via `SIUpdate`. Positions with `minEntryPrice` and `maxEntryPrice` as zero remain pending (`priceAtEntry = 0`). Emits `PositionEntered` with `hyx = address(0)`.
- **Internal Call Flow**: Calls `_initiateEntry` with `positionType = 0`. `_prepareEntryContext` fetches `tokenA` via `ISSListing.tokenA` (input: `listingAddress`, returns: `address`) and normalizes margins with `normalizeAmount` (`IERC20.decimals`, input: none, returns: `uint8`). `_validateEntry` checks `initialMargin > 0`, `leverage` (2–100), and listing via `ISSAgent.getListing` (input: `tokenA`, `tokenB`, returns: `address`). `_prepareEntryBase` increments `positionIdCounter`, stores `PendingEntry`. `_prepareEntryRisk` and `_prepareEntryToken` set parameters. `_validateEntryBase` and `_validateEntryRisk` enforce constraints. `_updateEntryCore`, `_updateEntryParams` (uses `ISSListing.prices` for price data, calls `_computeEntryParams`, `_validateLeverageLimit` with `ISSLiquidityTemplate.liquidityDetailsView`, input: `this`, returns: `xLiquid, yLiquid`), and `_updateEntryIndexes` store data via `SIUpdate` (input: `positionId`, `string` params, returns: `bool`). `_finalizeEntry` calls `_finalizeEntryFees` (transfers fee in tokenA to `liquidityAddress` via `IERC20.safeTransferFrom`, input: `msg.sender`, `liquidityAddress`, `denormFee`, returns: none, with pre/post balance checks via `IERC20.balanceOf(liquidityAddress)`; calls `ISSLiquidityTemplate.addFees`, input: `this`, `true`, `actualFee`), `_finalizeEntryTransfer` (transfers margins to `executionDriver` via `IERC20.safeTransferFrom`, input: `msg.sender`, `executionDriver`, `expectedAmount`, returns: none, with pre/post balance checks via `IERC20.balanceOf(executionDriver)`), and `_finalizeEntryPosition` (updates `SIUpdate`, deletes `pendingEntries`). Emits `PositionEntered` with `hyx = address(0)`.
- **Balance Checks**:
  - **Pre-Balance Check (Fee)**: `IERC20.balanceOf(liquidityAddress)` before fee transfer.
  - **Post-Balance Check (Fee)**: Ensures `balanceAfter - balanceBefore >= denormFee`.
  - **Pre-Balance Check (Margin)**: `IERC20.balanceOf(executionDriver)` before margin transfer.
  - **Post-Balance Check (Margin)**: Ensures `balanceAfter - balanceBefore >= expectedAmount`.
- **Mappings/Structs Used**:
  - **Mappings**: `pendingEntries`, `positionIdCounter`.
  - **Structs**: `EntryContext`, `PendingEntry`, `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `MarginParams`, `LeverageParams`, `RiskParams`, `PrepPosition`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `listingAddress` is zero (`"Invalid listing"`), `initialMargin == 0` (`"Invalid margin"`), `leverage` is out of range (`"Invalid leverage"`), `loanInitial` exceeds liquidity (`"Loan exceeds liquidity limit"`), or transfers fail.
- **Gas Usage Controls**: Single-element array updates, balance checks, and pop-and-swap minimize gas.

### enterShort(address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice)
- **Parameters**: Same as `enterLong`, for short positions.
- **Behavior**: Creates a pending short position, transferring margins in tokenB to `executionDriver`. Emits `PositionEntered` with `hyx = address(0)`.
- **Internal Call Flow**: Mirrors `enterLong`, with `positionType = 1`. `_prepareEntryContext` uses `ISSListing.tokenB`. `_validateLeverageLimit` checks `xLiquid`. Transfers use tokenB for fee (`ISSLiquidityTemplate.addFees` with `isX = false`) and margins. Other steps identical to `enterLong`.
- **Balance Checks**: Same as `enterLong`, for tokenB.
- **Mappings/Structs Used**: Same as `enterLong`.
- **Restrictions**: Same as `enterLong`.
- **Gas Usage Controls**: Same as `enterLong`.

### closeLongPosition(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID to close.
- **Behavior**: Closes a long position, computing payout in tokenB via `ISSListing.ssUpdate`, updating storage, and removing the position index. Emits `PositionClosed`.
- **Internal Call Flow**: Calls `_getPositionByIndex` (uses `storageContract.positionByIndex`, input: `positionId`, returns: `PositionCoreBase`, `PositionCoreStatus`, etc.). Validates `positionId`, `status2 == 0` (`"Position closed"`), and `makerAddress == msg.sender` (`"Not maker"`). Calls `_computePayoutLong` with `ISSListing.prices` (input: `listingAddress`, returns: `uint256`). Calls `_deductMarginAndRemoveToken` (uses `storageContract.AggregateMarginByToken`, updates `SIUpdate` with `tokenAndInterestParams`). Calls `_executePayoutUpdate` (uses `ISSListing.ssUpdate`, input: `PayoutUpdate[]` with `recipient = msg.sender`, returns: none). Calls `_updatePositionStorage` (uses `SIUpdate` with prepared params). Calls `_removePositionIndex` (uses `storageContract.removePositionIndex`, input: `positionId`, `positionType`, `listingAddress`, returns: `bool`). Emits `PositionClosed`.
- **Balance Checks**:
  - **Pre-Balance Check**: `status2 == 0` ensures position is open.
  - **Post-Balance Check**: None, as payout is handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `pendingEntries` (inherited).
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `MarginParams`, `LeverageParams`, `RiskParams`, `PayoutUpdate`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `positionId` is invalid (`"Invalid position"`), closed (`"Position closed"`), or not owned (`"Not maker"`).
- **Gas Usage Controls**: Single position processing with pop-and-swap minimizes gas.

### closeShortPosition(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID to close.
- **Behavior**: Closes a short position, paying out in tokenA via `ISSListing.ssUpdate`. Emits `PositionClosed`.
- **Internal Call Flow**: Similar to `closeLongPosition`, but uses `_computePayoutShort` and tokenA for payout. `_deductMarginAndRemoveToken` uses tokenB for margin deduction.
- **Balance Checks**: Same as `closeLongPosition`.
- **Mappings/Structs Used**: Same as `closeLongPosition`.
- **Restrictions**: Same as `closeLongPosition`.
- **Gas Usage Controls**: Same as `closeLongPosition`.

### drive(address maker, address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice, uint8 positionType)
- **Parameters**:
  - `maker` (address): Position owner.
  - `listingAddress` (address): Listing contract address.
  - `minEntryPrice` (uint256): Minimum entry price (normalized).
  - `maxEntryPrice` (uint256): Maximum entry price (normalized).
  - `initialMargin` (uint256): Initial margin (denormalized).
  - `excessMargin` (uint256): Excess margin (denormalized).
  - `leverage` (uint8): Leverage multiplier (2–100).
  - `stopLossPrice` (uint256): Stop-loss price (normalized).
  - `takeProfitPrice` (uint256): Take-profit price (normalized).
  - `positionType` (uint8): 0 for long, 1 for short.
- **Behavior**: Creates a position on behalf of `maker`, transferring margins to `executionDriver`. Emits `PositionEntered` with `hyx = msg.sender`.
- **Internal Call Flow**: Validates `maker != address(0)` (`"Invalid maker address"`) and `positionType <= 1` (`"Invalid position type"`). Calls `_initiateEntry` with overridden `context.maker = maker`. Other steps identical to `enterLong`/`enterShort`. Emits `PositionEntered` with `hyx = msg.sender`.
- **Balance Checks**: Same as `enterLong`.
- **Mappings/Structs Used**: Same as `enterLong`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `maker` is zero or `positionType > 1`, plus `enterLong` restrictions.
- **Gas Usage Controls**: Same as `enterLong`.

### drift(uint256 positionId, address maker)
- **Parameters**:
  - `positionId` (uint256): Position ID to close.
  - `maker` (address): Position owner.
- **Behavior**: Closes a position for `maker` by an authorized Hyx, paying out to `msg.sender` (Hyx) via `ISSListing.ssUpdate`. Emits `PositionClosed`.
- **Internal Call Flow**: Restricted by `onlyHyx`. Validates `positionId` (`"Invalid position"`), `status2 == 0` (`"Position closed"`), and `makerAddress == maker` (`"Maker mismatch"`). Calls `_prepDriftPayout` (uses `_computePayoutLong` or `_computePayoutShort`). Calls `_deductMarginAndRemoveToken` (uses tokenA for long, tokenB for short). Calls `_prepDriftPayoutUpdate` (uses `ISSListing.ssUpdate` with `recipient = msg.sender`). Calls `_updatePositionStorage` and `_removePositionIndex`. Emits `PositionClosed`.
- **Balance Checks**:
  - **Pre-Balance Check**: `status2 == 0` ensures position is open.
  - **Post-Balance Check**: None, as payout is handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `pendingEntries` (inherited).
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `MarginParams`, `LeverageParams`, `RiskParams`, `PayoutUpdate`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyHyx`.
  - Reverts if `positionId` is invalid, closed, or `maker` does not match.
- **Gas Usage Controls**: Single position processing with pop-and-swap minimizes gas.

## Additional Details
- **Decimal Handling**: Uses `DECIMAL_PRECISION` (1e18) for normalization, with `IERC20.decimals()` for token-specific precision (assumes `decimals <= 18`).
- **Market-Based Execution**: Positions with `minEntryPrice` and `maxEntryPrice` as zero remain pending (`priceAtEntry = 0`), deferring execution.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: Uses pop-and-swap for `hyxes`, single-element updates, and balance checks.
- **Listing Validation**: Uses `ISSAgent.getListing` for robust checks.
- **Token Usage**: Long positions use tokenA margins, tokenB payouts; short positions use tokenB margins, tokenA payouts.
- **Position Lifecycle**: Pending (`status1 == false`, `status2 == 0`) to executable (`status1 == true`, `status2 == 0`) to closed (`status2 == 1`).
- **Events**: Emitted for Hyx operations (`HyxAdded`, `HyxRemoved`), position entry (`PositionEntered` with `positionId`, `maker`, `positionType`, `minEntryPrice`, `maxEntryPrice`, `hyx`), and closure (`PositionClosed` with `positionId`, `maker`, `payout`).
- **Hyx Integration**: `hyxes` array authorizes external contracts. `drive` creates positions for `maker` by any caller; `drift` closes them with payouts to `msg.sender` (Hyx).
- **Safety**: Balance checks, explicit casting (e.g., `uint8`, `uint256`, `address(uint160)`), no inline assembly, and modular helpers (`_prepareEntryContext`, `_computeEntryParams`, etc.) ensure robustness.
- **Storage Updates**: Uses `SIUpdate` for all storage operations, aligning with `SIStorage`.
- **Deferred Implementations**: Functions like `addExcessMargin`, `cancelPosition`, `updateSL`, `updateTP`, `closeAllLongs`, `cancelAllLong`, `closeAllShort`, `cancelAllShort`, `executePositions`, `positionsByTypeView`, `positionsByAddressView`, `positionByIndex`, and `queryInterest` are not implemented, as they are not required by the current specification but can be added later.