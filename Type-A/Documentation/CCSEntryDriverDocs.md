# CCSEntryDriver Contract Documentation

## Overview
The `CCSEntryDriver` and `CCSEntryPartial` contracts, implemented in Solidity (^0.8.2), manage the creation of trading positions for cross margin strategies. `CCSEntryDriver` serves as the primary entry point for initiating long and short positions, supporting both native ETH and ERC20 tokens, while `CCSEntryPartial` provides helper functions for position preparation, fee calculations, and margin transfers. These contracts derive functionality from `ReentrancyGuard` and `Ownable` (via `CCSEntryPartial`), integrating with external interfaces (`ISSListing`, `ISSLiquidityTemplate`, `ISSAgent`, `ICSStorage`) for listing validation, liquidity checks, and storage management. They use `IERC20` for token operations and handle ETH via `msg.value`. The contracts manage position creation (pending status), margin transfers to an execution driver, and fee calculations, ensuring decimal precision across tokens and gas optimization. All state variables are managed in `ICSStorage`, and position closure or cancellation is deferred to the execution driver.

**Inheritance Tree for CCSEntryDriver**: `CCSEntryDriver` → `CCSEntryPartial` → `ReentrancyGuard` → `Ownable`  
**SPDX License**: BSL-1.1 - Peng Protocol 2025  
**Version**: 0.0.18 (last updated 2025-08-05)  
**Changelog**:
- 2025-08-05: Split `enterLong` into `enterLongNative` and `enterLongToken`, `enterShort` into `enterShortNative` and `enterShortToken`, `drive` into `driveNative` and `driveToken`; split `_transferMarginToListing` and `_updateMakerMargin` into native and token versions; added `receive` function for ETH handling; updated `prepEnterLong` and `prepEnterShort` to use appropriate helpers based on token type (v0.0.17 for `CCSEntryDriver`, v0.0.18 for `CCSEntryPartial`).

## State Variables
- **DECIMAL_PRECISION** (uint256, constant, public): Set to 1e18 for normalizing amounts and prices across token decimals (defined in `CCSEntryPartial`).
- **executionDriver** (address, public): Address of the execution driver contract for margin transfers, set via `setExecutionDriver` (defined in `CCSEntryPartial`).
- **storageContract** (ICSStorage, public): Reference to the storage contract for position data, set via `setStorageContract`.
- **agentAddress** (address, public): Address of the `ISSAgent` contract for listing validation, set via `setAgent`.
- **hyxes** (address[], private): Array of authorized Hyx addresses for restricted operations like `driveNative` and `driveToken`.

## Mappings (Defined in ICSStorage)
- **makerTokenMargin** (mapping(address => mapping(address => uint256))): Tracks normalized (1e18) margin balances per maker and token (including `address(0)` for ETH).
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
- **positionToken** (mapping(uint256 => address)): Maps position ID to margin token (tokenA for long, tokenB for short, or `address(0)` for ETH).
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
- **EntryContext** (CCSEntryPartial): Parameters for position entry: `positionId`, `listingAddress`, `minEntryPrice`, `maxEntryPrice`, `initialMargin`, `excessMargin`, `leverage`, `positionType`, `maker`, `token`.
- **PrepPosition** (CCSEntryPartial): Computed parameters: `fee`, `taxedMargin`, `leverageAmount`, `initialLoan`, `liquidationPrice`.

## Formulas
The following formulas, implemented in `CCSEntryPartial`, drive position entry calculations.

1. **Fee Calculation**:
   - **Formula**: `fee = (initialMargin * (leverage - 1) * DECIMAL_PRECISION) / 100 / DECIMAL_PRECISION`
   - **Used in**: `prepEnterLong`, `prepEnterShort`.
   - **Description**: Computes fee based on leverage and margin, normalized to 1e18.

2. **Taxed Margin**:
   - **Formula**: `taxedMargin = normalizeAmount(token, initialMargin) - fee`
   - **Used in**: `prepEnterLong`, `prepEnterShort`.
   - **Description**: Margin after fee deduction, normalized for token decimals or ETH (18 decimals).

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

## External Functions (CCSEntryDriver)
Functions handle position creation, leveraging `CCSEntryPartial` for computations and `ICSStorage` for state updates via `CSUpdate`. Each function is detailed with parameters, behavior, internal call flow, restrictions, and gas controls.

### setStorageContract(address _storageContract)
- **Parameters**:
  - `_storageContract` (address): Address of the ICSStorage contract.
- **Behavior**: Sets the `storageContract` variable to the provided address.
- **Internal Call Flow**: Validates `_storageContract` is non-zero and assigns to `storageContract`. No external calls or transfers.
- **Mappings/Structs Used**: None.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `_storageContract` is zero (`"Invalid storage contract address"`).
- **Gas Usage Controls**: Minimal gas for single state write.

### setAgent(address newAgentAddress)
- **Parameters**:
  - `newAgentAddress` (address): New ISSAgent address.
- **Behavior**: Updates `agentAddress` for listing validation.
- **Internal Call Flow**: Assigns `newAgentAddress` to `agentAddress`. No external calls or transfers.
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

### enterLongNative(address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `minEntryPrice` (uint256): Minimum entry price (denormalized).
  - `maxEntryPrice` (uint256): Maximum entry price (denormalized).
  - `excessMargin` (uint256): Additional margin (denormalized, ETH).
  - `leverage` (uint8): Leverage multiplier (2–100).
  - `stopLossPrice` (uint256): Stop-loss price (denormalized).
  - `takeProfitPrice` (uint256): Take-profit price (denormalized).
- **Behavior**: Creates a pending long position for `msg.sender` using native ETH (`msg.value` for initial margin). Emits `PositionEntered`.
- **Internal Call Flow**:
  - Calls `_initiateEntry` with `msg.sender`, `msg.value` as `initialMargin`, and `positionType = 0`, which:
    - Generates `positionId` via `storageContract.positionCount() + 1`.
    - Calls `_prepareEntryContext` to initialize `EntryContext`.
    - Calls `_validateEntry`:
      - Validates `initialMargin > 0`, `leverage` (2–100), and listing via `ISSAgent.isValidListing`.
      - Sets `maker` and `token` (`address(0)` for ETH or tokenA via `ISSListing.tokenA()`).
    - Calls `_computeEntryParams`:
      - Invokes `prepEnterLong` (CCSEntryPartial):
        - Validates inputs and fetches `tokenA`.
        - Calls `_parseEntryPriceInternal` to normalize prices and fetch `currentPrice` via `ISSListing.prices`.
        - Computes `fee`, `taxedMargin`, `leverageAmount` using `computeFee` and `normalizeAmount`.
        - Calls `_updateMakerMarginNative` to update `makerTokenMargin` for ETH via `CSUpdate`.
        - Calls `_computeLoanAndLiquidationLong` for `initialLoan` and `liquidationPrice`.
        - Calls `_checkLiquidityLimitLong` to verify tokenB liquidity via `ISSLiquidityTemplate.liquidityDetailsView`.
        - Calls `_transferMarginToListingNative` to transfer fee to `liquidityAddress` and margins to `executionDriver` via ETH transfers, with pre/post balance checks for ERC20 fees.
        - Calls `ISSLiquidityTemplate.addFees`.
    - Calls `_storeEntryData`:
      - Invokes `_prepCoreParams`, `_prepPriceParams`, `_prepMarginParams`, `_prepExitAndInterestParams`, `_prepMakerMarginParams`, `_prepPositionArrayParams`, each calling `CSUpdate`.
  - Increments `positionCount` via `CSUpdate`.
  - Transfer destinations: `liquidityAddress` (fee), `executionDriver` (margins), refunds excess ETH to `maker`.
- **Balance Checks**:
  - **Pre-Balance Check (Fee, if ERC20)**: `IERC20.balanceOf(liquidityAddr)` before fee transfer.
  - **Post-Balance Check (Fee, if ERC20)**: `balanceAfter - balanceBefore == denormalizedFee`.
  - **ETH Transfer Check**: Ensures `msg.value >= denormalizedAmount`, refunds excess via `payable(maker).call`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `marginParams1`, `marginParams2`, `exitParams`, `openInterest`, `pendingPositions`, `makerTokenMargin`, `makerMarginTokens`, `positionToken`, `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps`.
  - **Structs**: `EntryContext`, `PrepPosition`, `PositionCore1`, `PositionCore2`, `PriceParams1`, `PriceParams2`, `MarginParams1`, `MarginParams2`, `ExitParams`, `OpenInterest`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `msg.value == 0`, `leverage` out of range, or transfers fail.
- **Gas Usage Controls**: Single-element updates, pop-and-swap for arrays, no loops except `hyxes` in `onlyHyx`.

### enterLongToken(address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice)
- **Parameters**:
  - Same as `enterLongNative`, except:
    - `initialMargin` (uint256): Initial margin (denormalized, ERC20).
    - `excessMargin` (uint256): Additional margin (denormalized, ERC20).
- **Behavior**: Creates a pending long position for `msg.sender` using ERC20 `tokenA`. Emits `PositionEntered`.
- **Internal Call Flow**: Same as `enterLongNative`, but uses `_transferMarginToListingToken` and `_updateMakerMarginToken` for ERC20 transfers via `IERC20.transferFrom`.
- **Balance Checks**:
  - **Pre-Balance Check (Fee)**: `IERC20.balanceOf(liquidityAddr)` before fee transfer.
  - **Post-Balance Check (Fee)**: `balanceAfter - balanceBefore == denormalizedFee`.
  - **Pre-Balance Check (Margin)**: `IERC20.balanceOf(executionDriver)` before margin transfer.
  - **Post-Balance Check (Margin)**: `balanceAfter - balanceBefore == denormalizedAmount`.
- **Mappings/Structs Used**: Same as `enterLongNative`.
- **Restrictions**: Same as `enterLongNative`.
- **Gas Usage Controls**: Same as `enterLongNative`.

### enterShortNative(address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice)
- **Parameters**: Same as `enterLongNative`.
- **Behavior**: Creates a pending short position for `msg.sender` using native ETH. Emits `PositionEntered`.
- **Internal Call Flow**: Calls `_initiateEntry` with `msg.sender`, `msg.value` as `initialMargin`, and `positionType = 1`, using `prepEnterShort`, `_updateMakerMarginNative`, `_transferMarginToListingNative`, `_computeLoanAndLiquidationShort`, and `_checkLiquidityLimitShort`.
- **Balance Checks**: Same as `enterLongNative`.
- **Mappings/Structs Used**: Same as `enterLongNative`, with `tokenB` margins and `shortIOByHeight`.
- **Restrictions**: Same as `enterLongNative`.
- **Gas Usage Controls**: Same as `enterLongNative`.

### enterShortToken(address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice)
- **Parameters**: Same as `enterLongToken`.
- **Behavior**: Creates a pending short position for `msg.sender` using ERC20 `tokenB`. Emits `PositionEntered`.
- **Internal Call Flow**: Same as `enterShortNative`, but uses `_transferMarginToListingToken` and `_updateMakerMarginToken` for ERC20 transfers.
- **Balance Checks**: Same as `enterLongToken`.
- **Mappings/Structs Used**: Same as `enterLongNative`.
- **Restrictions**: Same as `enterLongNative`.
- **Gas Usage Controls**: Same as `enterLongNative`.

### driveNative(address maker, address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice, uint8 positionType)
- **Parameters**:
  - `maker` (address): Position owner.
  - `positionType` (uint8): 0 for long, 1 for short.
  - Additional parameters same as `enterLongNative`.
- **Behavior**: Creates a pending position for `maker` using native ETH, restricted to authorized Hyx contracts. Emits `PositionEntered`.
- **Internal Call Flow**: Similar to `enterLongNative`, but sets `context.maker = maker` and validates `maker` non-zero and `positionType <= 1`. Uses `prepEnterLong` or `prepEnterShort` with `_transferMarginToListingNative` and `_updateMakerMarginNative`.
- **Balance Checks**: Same as `enterLongNative`.
- **Mappings/Structs Used**: Same as `enterLongNative`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyHyx`.
  - Reverts if `maker` is zero, `positionType > 1`, or `msg.value == 0`.
- **Gas Usage Controls**: Same as `enterLongNative`.

### driveToken(address maker, address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice, uint8 positionType)
- **Parameters**:
  - `maker` (address): Position owner.
  - `positionType` (uint8): 0 for long, 1 for short.
  - Additional parameters same as `enterLongToken`.
- **Behavior**: Creates a pending position for `maker` using ERC20 tokens, restricted to authorized Hyx contracts. Emits `PositionEntered`.
- **Internal Call Flow**: Similar to `enterLongToken`, but sets `context.maker = maker` and validates `maker` non-zero and `positionType <= 1`. Uses `prepEnterLong` or `prepEnterShort` with `_transferMarginToListingToken` and `_updateMakerMarginToken`.
- **Balance Checks**: Same as `enterLongToken`.
- **Mappings/Structs Used**: Same as `enterLongNative`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyHyx`.
  - Reverts if `maker` is zero or `positionType > 1`.
- **Gas Usage Controls**: Same as `enterLongNative`.

## External Functions (CCSEntryPartial)
### setExecutionDriver(address _executionDriver)
- **Parameters**:
  - `_executionDriver` (address): Address of the execution driver contract.
- **Behavior**: Sets the `executionDriver` variable for margin transfers.
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
- **Pending Status by Default**: Positions are created with `priceAtEntry = 0` in `_parseEntryPriceInternal`, ensuring pending status (`status1 = false`, `status2 = 0`) until activated by the execution driver.
- **Execution Driver Integration**: Margins (ETH or ERC20) are transferred to `executionDriver`. Position execution and cancellation are deferred to the execution driver.
- **Storage Contract Dependency**: All state is managed via `ICSStorage`, with `CSUpdate` using structured parameters for modularity.
- **Token Usage**: Long positions use `tokenA` or ETH for margins; short positions use `tokenB` or ETH. Payouts are deferred to the execution driver.
- **Decimal Normalization**: Prices and amounts are normalized to 1e18 using `normalizePrice`, `normalizeAmount`, and `denormalizeAmount`. ETH uses 18 decimals; ERC20 uses `IERC20.decimals`.
- **ETH Handling**: Native ETH is handled via `msg.value` in `enterLongNative`, `enterShortNative`, and `driveNative`, with `receive` function enabling ETH reception. Excess ETH is refunded.
- **Gas Optimization**: Functions use single-element updates, pop-and-swap for arrays, and avoid loops except in `onlyHyx`. `_storeEntryData` is split into helpers to avoid stack too deep errors.
- **Balance Checks**: Pre/post balance checks in `_transferMarginToListingNative` (ETH) and `_transferMarginToListingToken` (ERC20) ensure accurate transfers to `executionDriver` and `liquidityAddress`.
- **Reentrancy Protection**: All state-changing functions are `nonReentrant`.
- **Listing Updates**: Margin transfers in `CCSEntryPartial` do not call `ISSListing.update`, as margins are sent to `executionDriver`.
- **Hyx Restrictions**: `driveNative` and `driveToken` are restricted to authorized Hyx contracts, allowing them to create positions on behalf of makers.
- **Event Emission**: Emits `PositionEntered`, `HyxAdded`, `HyxRemoved`. Excludes `PositionClosed` and `PositionCancelled` as they are handled by the execution driver.
- **Execution Deferral**: Position execution (activating pending positions or triggering stop-loss/take-profit/liquidation) and cancellation are deferred to the execution driver.
