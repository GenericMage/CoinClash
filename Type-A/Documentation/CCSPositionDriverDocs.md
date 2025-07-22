# CCSPositionDriver Contract Documentation

## Overview
The `CCSPositionDriver` and `CCSPositionPartial` contracts, implemented in Solidity (^0.8.2), manage trading positions for cross margin strategies, with `CCSPositionDriver` serving as the primary entry point for position creation, closure, and margin adjustments, and `CCSPositionPartial` providing helper functions for position preparation and payout calculations. These contracts derive partial functionality from `SSCrossDriver` and its inherited contracts (`CSDExecutionPartial`, `CSDPositionPartial`, `CSDUtilityPartial`), integrating with external interfaces (`ISSListing`, `ISSLiquidityTemplate`, `ISSAgent`, `ICSStorage`) for listing validation, liquidity checks, and storage management. They use `IERC20` (via `SafeERC20`) for token operations and `ReentrancyGuard` for security. The contracts handle position lifecycle (pending, active, closed), margin transfers to an execution driver, fee calculations, and payout computations, ensuring decimal precision across tokens and robust gas optimization. All state variables are hidden, accessed via view functions in `ICSStorage`, and transfers to the execution driver are managed in `CCSPositionPartial`. Position cancellation is deferred to the execution driver.

**Inheritance Tree for CCSPositionDriver**: `CCSPositionDriver` → `CCSPositionPartial` → `ReentrancyGuard` → `Ownable`  
**SPDX License**: BSL-1.1 - Peng Protocol 2025  
**Version**: 0.0.12 (last updated 2025-07-20)  

## State Variables
- **DECIMAL_PRECISION** (uint256, constant, public): Set to 1e18 for normalizing amounts and prices across token decimals (defined in `CCSPositionPartial`).
- **executionDriver** (address, public): Address of the execution driver contract for margin transfers and position execution, set via `setExecutionDriver` (defined in `CCSPositionPartial`).
- **storageContract** (ICSStorage, public): Reference to the storage contract for managing position data, set via `setStorageContract`.
- **agentAddress** (address, public): Address of the `ISSAgent` contract for listing validation, set via `setAgent`.
- **hyxes** (address[], private): Array of authorized Hyx addresses for restricted operations like `drift`.

## Mappings (Defined in ICSStorage)
- **makerTokenMargin** (mapping(address => mapping(address => uint256))): Tracks normalized (1e18) margin balances per maker and token.
- **makerMarginTokens** (mapping(address => address[])): Lists tokens with non-zero margin balances for each maker.
- **positionCore1** (mapping(uint256 => PositionCore1)): Stores core position data (positionId, listingAddress, makerAddress, positionType).
- **positionCore2** (mapping(uint256 => PositionCore2)): Tracks position status (status1 for active/pending, status2 for open/closed).
- **priceParams1** (mapping(uint256 => PriceParams1)): Holds price data (minEntryPrice, maxEntryPrice, minPrice, priceAtEntry, leverage).
- **priceParams2** (mapping(uint256 => PriceParams2)): Stores liquidation price.
- **marginParams1** (mapping(uint256 => MarginParams1)): Manages margin details (initialMargin, taxedMargin, excessMargin, fee).
- **marginParams2** (mapping(uint256 => MarginParams2)): Tracks initial loan amount.
- **exitParams** (mapping(uint256 => ExitParams)): Stores exit conditions (stopLossPrice, takeProfitPrice, exitPrice).
- **openInterest** (mapping(uint256 => OpenInterest)): Records leverage amount and timestamp.
- **positionsByType** (mapping(uint8 => uint256[])): Lists position IDs by type (0 for long, 1 for short).
- **pendingPositions** (mapping(address => mapping(uint8 => uint256[]))): Tracks pending position IDs by listing and type.
- **positionToken** (mapping(uint256 => address)): Maps position ID to margin token (tokenA for long, tokenB for short).
- **longIOByHeight** (mapping(uint256 => uint256)): Tracks long open interest by block height.
- **shortIOByHeight** (mapping(uint256 => uint256)): Tracks short open interest by block height.
- **historicalInterestTimestamps** (mapping(uint256 => uint256)): Stores timestamps for open interest updates.

## Structs
- **PositionCore1**: Contains `positionId` (uint256), `listingAddress` (address), `makerAddress` (address), `positionType` (uint8: 0 for long, 1 for short).
- **PositionCore2**: Includes `status1` (bool: true for active, false for pending), `status2` (uint8: 0 for open, 1 for closed).
- **PriceParams1**: Stores `minEntryPrice`, `maxEntryPrice`, `minPrice`, `priceAtEntry` (uint256, normalized), `leverage` (uint8: 2–100).
- **PriceParams2**: Holds `liquidationPrice` (uint256, normalized).
- **MarginParams1**: Tracks `initialMargin`, `taxedMargin`, `excessMargin`, `fee` (uint256, normalized).
- **MarginParams2**: Stores `initialLoan` (uint256, normalized).
- **ExitParams**: Includes `stopLossPrice`, `takeProfitPrice`, `exitPrice` (uint256, normalized).
- **OpenInterest**: Contains `leverageAmount` (uint256, normalized), `timestamp` (uint256).
- **EntryContext** (CCSPositionPartial): Parameters for position entry: `positionId`, `listingAddress`, `minEntryPrice`, `maxEntryPrice`, `initialMargin`, `excessMargin`, `leverage`, `positionType`, `maker`, `token`.
- **PrepPosition** (CCSPositionPartial): Computed parameters: `fee`, `taxedMargin`, `leverageAmount`, `initialLoan`, `liquidationPrice`.

## Formulas
The following formulas, implemented in `CCSPositionPartial`, drive position calculations.

1. **Fee Calculation**:
   - **Formula**: `fee = (initialMargin * (leverage - 1) * DECIMAL_PRECISION) / 100 / DECIMAL_PRECISION`
   - **Used in**: `prepEnterLong`, `prepEnterShort`.
   - **Description**: Computes fee based on leverage and margin, normalized to 1e18.

2. **Taxed Margin**:
   - **Formula**: `taxedMargin = normalizeAmount(token, initialMargin) - fee`
   - **Used in**: `prepEnterLong`, `prepEnterShort`.
   - **Description**: Margin after fee deduction, normalized for token decimals.

3. **Leverage Amount**:
   - **Formula**: `leverageAmount = normalizeAmount(token, initialMargin) * leverage`
   - **Used in**: `prepEnterLong`, `prepEnterShort`.
   - **Description**: Leveraged position size, normalized to 1e18.

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
   - **Used in**: `_computeLoanAndLiquidationLong`.
   - **Description**: Liquidation price for long positions.

7. **Liquidation Price (Short)**:
   - **Formula**: `liquidationPrice = minPrice + marginRatio`, where `marginRatio = makerTokenMargin[maker][tokenB] / leverageAmount`
   - **Used in**: `_computeLoanAndLiquidationShort`.
   - **Description**: Liquidation price for short positions.

8. **Liquidity Limit (Long)**:
   - **Formula**: `initialLoan <= yLiquid * (101 - leverage) / 100`, where `yLiquid` is tokenB liquidity
   - **Used in**: `_checkLiquidityLimitLong`.
   - **Description**: Ensures initial loan does not exceed tokenB liquidity, scaled by leverage.

9. **Liquidity Limit (Short)**:
   - **Formula**: `initialLoan <= xLiquid * (101 - leverage) / 100`, where `xLiquid` is tokenA liquidity
   - **Used in**: `_checkLiquidityLimitShort`.
   - **Description**: Ensures initial loan does not exceed tokenA liquidity, scaled by leverage.

10. **Payout (Long)**:
    - **Formula**: `payout = baseValue > initialLoan ? baseValue - initialLoan : 0`, where `baseValue = (taxedMargin + totalMargin + leverageAmount) / currentPrice`
    - **Used in**: `_computePayoutLong`.
    - **Description**: Payout for long position closure in tokenB, normalized.

11. **Payout (Short)**:
    - **Formula**: `payout = profit + (taxedMargin + totalMargin) * currentPrice / DECIMAL_PRECISION`, where `profit = (priceAtEntry - currentPrice) * initialMargin * leverage`
    - **Used in**: `_computePayoutShort`.
    - **Description**: Payout for short position closure in tokenA, normalized.

12. **Margin Ratio**:
    - **Formula**: `marginRatio = totalMargin * DECIMAL_PRECISION / (initialMargin * leverage)`
    - **Used in**: `PositionHealthView`.
    - **Description**: Position health metric, normalized to 1e18.

13. **Distance to Liquidation (Long)**:
    - **Formula**: `distanceToLiquidation = currentPrice > liquidationPrice ? currentPrice - liquidationPrice : 0`
    - **Used in**: `PositionHealthView`.
    - **Description**: Liquidation risk for long positions, normalized.

14. **Distance to Liquidation (Short)**:
    - **Formula**: `distanceToLiquidation = currentPrice < liquidationPrice ? liquidationPrice - currentPrice : 0`
    - **Used in**: `PositionHealthView`.
    - **Description**: Liquidation risk for short positions, normalized.

15. **Estimated Profit/Loss (Long)**:
    - **Formula**: `estimatedProfitLoss = (taxedMargin + totalMargin + leverage * initialMargin) / currentPrice - initialLoan`
    - **Used in**: `PositionHealthView`.
    - **Description**: Profit/loss estimate for long positions, normalized.

16. **Estimated Profit/Loss (Short)**:
    - **Formula**: `estimatedProfitLoss = (priceAtEntry - currentPrice) * initialMargin * leverage + (taxedMargin + totalMargin) * currentPrice / DECIMAL_PRECISION`
    - **Used in**: `PositionHealthView`.
    - **Description**: Profit/loss estimate for short positions, normalized.

## External Functions (CCSPositionDriver)
Functions in `CCSPositionDriver` handle position lifecycle and margin management, leveraging `CCSPositionPartial` for computations and `ICSStorage` for state updates via `CSUpdate`. Each function is detailed with parameters, behavior, internal call flow, restrictions, and gas controls.

### setStorageContract(address _storageContract)
- **Parameters**:
  - `_storageContract` (address): Address of the ICSStorage contract.
- **Behavior**: Sets the `storageContract` variable to the provided address.
- **Internal Call Flow**: Validates `_storageContract` is non-zero and assigns to `storageContract`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**: None.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `_storageContract` is zero (`"Invalid storage address"`).
- **Gas Usage Controls**: Minimal gas for single state write.

### setAgent(address newAgentAddress)
- **Parameters**:
  - `newAgentAddress` (address): New ISSAgent address.
- **Behavior**: Updates `agentAddress` for listing validation.
- **Internal Call Flow**: Assigns `newAgentAddress` to `agentAddress`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**: None.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `newAgentAddress` is zero (`"Invalid agent address"`).
- **Gas Usage Controls**: Minimal gas for single state write.

### addHyx(address hyx)
- **Parameters**:
  - `hyx` (address): Hyx contract to authorize.
- **Behavior**: Adds `hyx` to the `hyxes` array. Emits `HyxAdded`.
- **Internal Call Flow**: Checks for non-zero `hyx` and duplicates, then appends to `hyxes`. No transfers or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: None.
  - **Structs**: None.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `hyx` is zero or already exists.
- **Gas Usage Controls**: Linear search in `hyxes`, O(n) gas, where n is array length.

### removeHyx(address hyx)
- **Parameters**:
  - `hyx` (address): Hyx contract to deauthorize.
- **Behavior**: Removes `hyx` from the `hyxes` array using pop-and-swap. Emits `HyxRemoved`.
- **Internal Call Flow**: Searches for `hyx`, swaps with last element, and pops. No transfers or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: None.
  - **Structs**: None.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `hyx` is zero or not found.
- **Gas Usage Controls**: Linear search and pop-and-swap, O(n) gas.

### getHyxes()
- **Parameters**: None.
- **Behavior**: Returns the `hyxes` array.
- **Internal Call Flow**: Returns `hyxes` directly. No external calls or balance checks.
- **Mappings/Structs Used**: None.
- **Restrictions**: None (view function).
- **Gas Usage Controls**: Minimal gas for array return.

### drive(address maker, address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice, uint8 positionType)
- **Parameters**:
  - `maker` (address): Position owner.
  - `listingAddress` (address): Listing contract address.
  - `minEntryPrice` (uint256): Minimum entry price (denormalized).
  - `maxEntryPrice` (uint256): Maximum entry price (denormalized).
  - `initialMargin` (uint256): Initial margin (denormalized).
  - `excessMargin` (uint256): Additional margin (denormalized).
  - `leverage` (uint8): Leverage multiplier (2–100).
  - `stopLossPrice` (uint256): Stop-loss price (denormalized).
  - `takeProfitPrice` (uint256): Take-profit price (denormalized).
  - `positionType` (uint8): 0 for long, 1 for short.
- **Behavior**: Creates a pending position for `maker`, transferring margins to `executionDriver`, computing fees, loans, and liquidation prices, and storing data via `CSUpdate`. Emits `PositionEntered`.
- **Internal Call Flow**:
  - Validates `maker` non-zero, `positionType <= 1`, and `positionId` via `storageContract.positionCount() + 1`.
  - Calls `_prepareEntryContext` to initialize `EntryContext`.
  - Calls `_validateEntry`:
    - Validates `initialMargin > 0`, `leverage` (2–100), and listing via `ISSAgent.getListing` (input: `tokenA`, `tokenB`, returns: `expectedListing`).
    - Sets `maker` and `token` (tokenA for long, tokenB for short via `ISSListing.tokenA()` or `tokenB()`).
  - Calls `_computeEntryParams`:
    - Invokes `prepEnterLong` or `prepEnterShort` (CCSPositionPartial):
      - `_parsePriceParams` normalizes prices and fetches `currentPrice` via `ISSListing.prices` (input: `listingAddress`, returns: `currentPrice`). Sets `priceAtEntry = 0` for pending status.
      - `_calcFeeAndMargin` computes `fee`, `taxedMargin`, `leverageAmount` using `IERC20.decimals` (input: none, returns: `decimals`).
      - `_updateMakerMargin` updates `makerTokenMargin` via `CSUpdate`.
      - `_computeLoanAndLiquidationLong` or `_computeLoanAndLiquidationShort` calculates `initialLoan` and `liquidationPrice`.
      - `_checkLiquidityLimitLong` or `_checkLiquidityLimitShort` verifies liquidity via `ISSLiquidityTemplate.liquidityDetailsView` (input: `this`, returns: `xLiquid, yLiquid`).
      - `_transferMarginToListing` transfers fee to `liquidityAddress` via `IERC20.transfer` (input: `liquidityAddress`, `denormalizedFee`, returns: `bool success`) and margins to `executionDriver` via `IERC20.transferFrom` (input: `msg.sender`, `executionDriver`, `denormalizedAmount`, returns: `bool success`), with pre/post balance checks via `IERC20.balanceOf`.
      - Calls `ISSLiquidityTemplate.addFees` (input: `this`, `isLong`, `denormalizedFee`, returns: none).
  - Calls `_storeEntryData`:
    - Invokes `_prepCoreParams`, `_prepPriceParams`, `_prepMarginParams`, `_prepExitAndInterestParams`, `_prepMakerMarginParams`, `_prepPositionArrayParams`, each calling `CSUpdate` with hyphen-delimited strings for respective parameters.
  - Increments `positionCount` via `CSUpdate`.
  - Transfer destinations: `liquidityAddress` (fee), `executionDriver` (margins).
- **Balance Checks**:
  - **Pre-Balance Check (Fee)**: `IERC20.balanceOf(liquidityAddr)` before fee transfer.
  - **Post-Balance Check (Fee)**: `balanceAfter - balanceBefore == denormalizedFee`.
  - **Pre-Balance Check (Margin)**: `IERC20.balanceOf(executionDriver)` before margin transfer.
  - **Post-Balance Check (Margin)**: `balanceAfter - balanceBefore == denormalizedAmount`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `marginParams1`, `marginParams2`, `exitParams`, `openInterest`, `pendingPositions`, `makerTokenMargin`, `makerMarginTokens`, `positionToken`, `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps`.
  - **Structs**: `EntryContext`, `PrepPosition`, `PositionCore1`, `PositionCore2`, `PriceParams1`, `PriceParams2`, `MarginParams1`, `MarginParams2`, `ExitParams`, `OpenInterest`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `maker` is zero, `positionType > 1`, `initialMargin == 0`, `leverage` out of range, or transfers fail.
- **Gas Usage Controls**: Single-element updates, no loops, pop-and-swap for arrays.

### enterLong(address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice)
- **Parameters**: Same as `drive`, without `maker` or `positionType` (defaults to `msg.sender` and 0).
- **Behavior**: Creates a pending long position for `msg.sender`, using `tokenA` for margins. Emits `PositionEntered`.
- **Internal Call Flow**: Calls `_initiateEntry` with `msg.sender` and `positionType = 0`, which invokes `drive`’s flow.
- **Balance Checks**: Same as `drive`.
- **Mappings/Structs Used**: Same as `drive`.
- **Restrictions**: Protected by `nonReentrant`.
- **Gas Usage Controls**: Same as `drive`.

### enterShort(address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice)
- **Parameters**: Same as `enterLong`, for short positions.
- **Behavior**: Creates a pending short position for `msg.sender`, using `tokenB` for margins. Emits `PositionEntered`.
- **Internal Call Flow**: Calls `_initiateEntry` with `msg.sender` and `positionType = 1`, which invokes `drive`’s flow.
- **Balance Checks**: Same as `drive`.
- **Mappings/Structs Used**: Same as `drive`, with `tokenB` margins and `shortIOByHeight`.
- **Restrictions**: Protected by `nonReentrant`.
- **Gas Usage Controls**: Same as `drive`.

### closeLongPosition(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID to close.
- **Behavior**: Closes a long position, computing payout in tokenB, transferring to `msg.sender`, and updating state via `CSUpdate`. Emits `PositionClosed`.
- **Internal Call Flow**:
  - Validates position via `storageContract.positionCore1`, ensures not closed (`positionCore2.status2 == 0`) and owned by `msg.sender`.
  - Calls `_computePayoutLong` (CCSPositionPartial) for tokenB payout.
  - Calls `_deductMarginAndRemoveToken` to deduct `taxedMargin + excessMargin` from `makerTokenMargin[tokenA]`.
  - Calls `_executePayoutUpdate` to prepare `ISSListing.PayoutUpdate` and invoke `ISSListing.ssUpdate` (input: `this`, `updates`, returns: none).
  - Constructs hyphen-delimited strings for `CSUpdate` (coreParams, priceParams, marginParams, exitAndInterestParams, makerMarginParams).
  - Calls `storageContract.removePositionIndex` and `CSUpdate`.
  - Payout destination: `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `makerTokenMargin[maker][tokenA] >= taxedMargin + excessMargin`.
  - **Post-Balance Check**: None, as payout is handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `marginParams1`, `exitParams`, `makerTokenMargin`, `makerMarginTokens`, `positionToken`, `positionsByType`, `pendingPositions`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `MarginParams1`, `ExitParams`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if position is invalid, closed, or not owned.
- **Gas Usage Controls**: Single position processing, pop-and-swap for arrays.

### closeShortPosition(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID to close.
- **Behavior**: Closes a short position, paying out in tokenA to `msg.sender`. Emits `PositionClosed`.
- **Internal Call Flow**: Similar to `closeLongPosition`, using `_computePayoutShort` for tokenA payout and `tokenB` margins.
- **Balance Checks**:
  - **Pre-Balance Check**: `makerTokenMargin[maker][tokenB] >= taxedMargin + excessMargin`.
  - **Post-Balance Check**: None, as payout is handled by `ISSListing`.
- **Mappings/Structs Used**: Same as `closeLongPosition`, with `tokenB` margins and `tokenA` payouts.
- **Restrictions**: Same as `closeLongPosition`.
- **Gas Usage Controls**: Same as `closeLongPosition`.

### drift(uint256 positionId, address maker)
- **Parameters**:
  - `positionId` (uint256): Position ID to close.
  - `maker` (address): Position owner.
- **Behavior**: Allows authorized Hyx contracts to close a position on behalf of `maker`, sending payout to the caller (`msg.sender`). Emits `PositionClosed`.
- **Internal Call Flow**:
  - Calls `_prepDriftCore` to validate position and ownership.
  - Calls `_prepDriftPayout` to compute payout (tokenB for long, tokenA for short) using `_computePayoutLong` or `_computePayoutShort`.
  - Calls `_prepDriftMargin` to deduct margins via `_deductMarginAndRemoveToken`.
  - Calls `_prepDriftPayoutUpdate` to prepare `ISSListing.PayoutUpdate` and invoke `ISSListing.ssUpdate`.
  - Calls `_prepDriftCSUpdateParams` to prepare hyphen-delimited strings for `CSUpdate`.
  - Calls `_executeDriftCSUpdate` to update state.
  - Calls `storageContract.removePositionIndex`.
  - Payout destination: `msg.sender` (Hyx).
- **Balance Checks**:
  - **Pre-Balance Check**: `makerTokenMargin[maker][positionToken] >= taxedMargin + excessMargin`.
  - **Post-Balance Check**: None, as payout is handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `marginParams1`, `marginParams2`, `exitParams`, `makerTokenMargin`, `makerMarginTokens`, `positionToken`, `positionsByType`, `pendingPositions`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `MarginParams1`, `MarginParams2`, `ExitParams`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyHyx`.
  - Reverts if position is invalid, closed, or `maker` does not match.
- **Gas Usage Controls**: Single position processing, pop-and-swap for arrays.

## External Functions (CCSPositionPartial)
### setExecutionDriver(address _executionDriver)
- **Parameters**:
  - `_executionDriver` (address): Address of the execution driver contract.
- **Behavior**: Sets the `executionDriver` variable for margin transfers and position execution.
- **Internal Call Flow**: Validates `_executionDriver` is non-zero and assigns to `executionDriver`. No external calls or transfers.
- **Mappings/Structs Used**: None.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `_executionDriver` is zero (`"Invalid execution driver address"`).
- **Gas Usage Controls**: Minimal gas for single state write.

### getExecutionDriver()
- **Parameters**: None.
- **Behavior**: Returns the `executionDriver` address.
- **Internal Call Flow**: Returns `executionDriver` directly. No external calls or balance checks.
- **Mappings/Structs Used**: None.
- **Restrictions**: None (view function).
- **Gas Usage Controls**: Minimal gas for single read.

## Nuances and Clarifications
- **Pending Status by Default**: Unlike `SSCrossDriver`, where positions with zero `minEntryPrice` and `maxEntryPrice` execute instantly as market orders, `CCSPositionPartial` sets `priceAtEntry = 0` in `_parseEntryPriceInternal`, ensuring all positions are pending (`status1 = false`, `status2 = 0`) until activated by the execution driver.
- **Execution Driver Integration**: Margins are transferred to `executionDriver` instead of the listing contract, and position cancellation is deferred to the execution driver, removing `cancelPosition` from `CCSPositionDriver`.
- **Storage Contract Dependency**: All state is managed via `ICSStorage`, with `CSUpdate` using hyphen-delimited strings to update mappings (`positionCore1`, `priceParams1`, etc.). This ensures modularity but requires precise string formatting to avoid parsing errors.
- **Token Usage**: Long positions use `tokenA` for margins and `tokenB` for payouts; short positions use `tokenB` for margins and `tokenA` for payouts, consistent with `SSCrossDriver`.
- **Decimal Normalization**: Prices and amounts are normalized to 1e18 using `normalizePrice`, `normalizeAmount`, and `denormalizeAmount`, handling tokens with varying decimals via `IERC20.decimals`.
- **Gas Optimization**: Functions use single-element updates, pop-and-swap for arrays, and avoid loops except in `getHyxes`. The `drift` function is optimized by splitting into helper functions to avoid stack too deep errors.
- **Balance Checks**: Pre/post balance checks in `_transferMarginToListing` ensure accurate transfers to `executionDriver` and `liquidityAddress`. Payouts via `ISSListing.ssUpdate` rely on listing contract validation, omitting post-balance checks in `close` and `drift`.
- **Reentrancy Protection**: All state-changing functions are `nonReentrant`, preventing reentrancy attacks.
- **Listing Updates**: Margin transfers in `CCSPositionPartial` no longer call `ISSListing.update`, as margins are sent to `executionDriver`, which is expected to handle updates.
- **Hyx Restrictions**: The `drift` function is restricted to authorized Hyx contracts, allowing them to close positions on behalf of makers, with payouts sent to the Hyx.
- **Event Emission**: Events (`PositionEntered`, `PositionClosed`, `HyxAdded`, `HyxRemoved`) mirror `SSCrossDriver` but exclude `PositionCancelled` and batch operations like `closeAllPositions` or `cancelAllPositions`.
- **Execution Deferral**: Position execution (activating pending positions or triggering stop-loss/take-profit/liquidation) and cancellation are deferred to the execution driver, unlike `SSCrossDriver`’s `executePositions` and `cancelPosition`.
