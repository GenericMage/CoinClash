# CISEntryDriver Contract Documentation

## Overview
The `CISEntryDriver` contract, implemented in Solidity (^0.8.2), manages the creation of trading positions for long and short isolated margin strategies, inheriting functionality from `CISEntryPartial`. It integrates with external interfaces (`ISSListing`, `ISSLiquidityTemplate`, `ISSAgent`, `ISIStorage`) and uses `IERC20` for token operations and `ReentrancyGuard` for protection. The contract supports position creation (`enterLongNative`, `enterLongToken`, `enterShortNative`, `enterShortToken`, `driveNative`, `driveToken`) and Hyx management (`addHyx`, `removeHyx`, `getHyxes`), transferring margins (native or ERC20) to an `executionDriver` and using `SIUpdate` for storage updates. Positions with zero `minEntryPrice` and `maxEntryPrice` remain pending.

**Inheritance Tree:** `CISEntryDriver` → `CISEntryPartial` → `ReentrancyGuard`

**SPDX License:** BSL-1.1 - Peng Protocol 2025

**Version:** 0.0.3 (last updated 2025-08-08)

## State Variables
- **DECIMAL_PRECISION** (uint256, constant, public, inherited): Set to 1e18 for normalizing amounts and prices.
- **executionDriver** (address, public, inherited): Stores the address for margin transfers.
- **storageContract** (address, public, inherited): Stores the address of the storage contract for `SIUpdate`.
- **agentAddress** (address, public, inherited): Stores the address of the `ISSAgent` contract for listing validation.
- **positionIdCounter** (uint256, internal, inherited): Counter for generating unique position IDs, initialized to 0.
- **historicalInterestHeight** (uint256, internal, inherited): Tracks block height for interest updates, initialized to 1.
- **hyxes** (address[], private): Array of authorized Hyx addresses for `drive` operations.

## Mappings
- **pendingEntries** (mapping(uint256 => PendingEntry), internal, inherited): Temporary storage for position entry parameters.

## Structs
- **PositionCoreBase** (inherited): Contains `makerAddress` (address), `listingAddress` (address), `positionId` (uint256), `positionType` (uint8: 0 for long, 1 for short).
- **PositionCoreStatus** (inherited): Tracks `status1` (bool: false for pending, true for executable), `status2` (uint8: 0 for open, 1 for closed, 2 for cancelled).
- **PriceParams** (inherited): Stores `priceMin` (uint256), `priceMax` (uint256), `priceAtEntry` (uint256), `priceClose` (uint256), all normalized to 1e18.
- **MarginParams** (inherited): Holds `marginInitial` (uint256), `marginTaxed` (uint256), `marginExcess` (uint256), all normalized to 1e18.
- **LeverageParams** (inherited): Contains `leverageVal` (uint8), `leverageAmount` (uint256), `loanInitial` (uint256), with amounts normalized to 1e18.
- **RiskParams** (inherited): Stores `priceLiquidation` (uint256), `priceStopLoss` (uint256), `priceTakeProfit` (uint256), all normalized to 1e18.
- **TokenAndInterestParams** (inherited): Stores `token` (address), `longIO` (uint256), `shortIO` (uint256), `timestamp` (uint256).
- **PositionArrayParams** (inherited): Stores `listingAddress` (address), `positionType` (uint8), `addToPending` (bool), `addToActive` (bool).
- **EntryContext** (inherited): Stores `positionId` (uint256), `listingAddress` (address), `minEntryPrice` (uint256), `maxEntryPrice` (uint256), `initialMargin` (uint256), `excessMargin` (uint256), `leverage` (uint8), `positionType` (uint8), `maker` (address), `token` (address).
- **PendingEntry** (inherited): Stores `listingAddr` (address), `tokenAddr` (address), `positionId` (uint256), `positionType` (uint8), `initialMargin` (uint256), `extraMargin` (uint256), `entryPriceStr` (string), `makerAddress` (address), `leverageVal` (uint8), `stopLoss` (uint256), `takeProfit` (uint256), `normInitMargin` (uint256), `normExtraMargin` (uint256).
- **PrepPosition** (inherited): Stores `fee` (uint256), `taxedMargin` (uint256), `leverageAmount` (uint256), `initialLoan` (uint256), `liquidationPrice` (uint256).
- **EntryParams** (inherited): Stores `listingAddress` (address), `minEntryPrice` (uint256), `maxEntryPrice` (uint256), `initialMargin` (uint256), `excessMargin` (uint256), `leverage` (uint8), `stopLossPrice` (uint256), `takeProfitPrice` (uint256), `positionType` (uint8), `maker` (address), `isNative` (bool).

## Formulas
1. **Fee Calculation**:
   - **Formula**: `fee = (leverageVal - 1) * normMarginInitial / 100`
   - **Used in**: `computeFee`, called by `_finalizeEntryFees`.
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

## External Functions

### setExecutionDriver(address _executionDriver)
- **Parameters**:
  - `_executionDriver` (address): New execution driver address.
- **Behavior**: Updates `executionDriver` for margin transfers.
- **Internal Call Flow**: Directly updates `executionDriver`. No internal or external calls, transfers, or balance checks.
- **Mappings/Structs Used**: `executionDriver`.
- **Restrictions**: Restricted to `onlyOwner`. Reverts if `_executionDriver` is zero (`"Invalid execution driver address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

### setStorageContract(address _storageContract)
- **Parameters**:
  - `_storageContract` (address): New storage contract address.
- **Behavior**: Updates `storageContract` for `SIUpdate` calls.
- **Internal Call Flow**: Directly updates `storageContract`. No internal or external calls, transfers, or balance checks.
- **Mappings/Structs Used**: `storageContract`.
- **Restrictions**: Restricted to `onlyOwner`. Reverts if `_storageContract` is zero (`"Invalid storage address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

### setAgent(address newAgentAddress)
- **Parameters**:
  - `newAgentAddress` (address): New `ISSAgent` address.
- **Behavior**: Updates `agentAddress` for listing validation.
- **Internal Call Flow**: Directly updates `agentAddress`. No internal or external calls, transfers, or balance checks.
- **Mappings/Structs Used**: `agentAddress`.
- **Restrictions**: Restricted to `onlyOwner`. Reverts if `newAgentAddress` is zero (`"Invalid agent address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

### getExecutionDriver()
- **Parameters**: None.
- **Behavior**: Returns the `executionDriver` address.
- **Internal Call Flow**: Returns `executionDriver`. No internal or external calls, transfers, or balance checks.
- **Mappings/Structs Used**: `executionDriver`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### getAgentAddress()
- **Parameters**: None.
- **Behavior**: Returns the `agentAddress`.
- **Internal Call Flow**: Returns `agentAddress`. No internal or external calls, transfers, or balance checks.
- **Mappings/Structs Used**: `agentAddress`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### addHyx(address hyx)
- **Parameters**:
  - `hyx` (address): Address of the Hyx contract to authorize.
- **Behavior**: Adds a Hyx contract to `hyxes`, enabling it to call `drive` variants. Emits `HyxAdded`.
- **Internal Call Flow**: Validates `hyx != address(0)` and ensures `hyx` is not in `hyxes`. Appends `hyx` to `hyxes`. Emits `HyxAdded`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**: `hyxes`.
- **Restrictions**: Restricted to `onlyOwner`. Reverts if `hyx` is zero (`"Invalid Hyx address"`) or already exists (`"Hyx already exists"`).
- **Gas Usage Controls**: Minimal gas due to single array push.

### removeHyx(address hyx)
- **Parameters**:
  - `hyx` (address): Address of the Hyx contract to deauthorize.
- **Behavior**: Removes a Hyx contract from `hyxes`. Emits `HyxRemoved`.
- **Internal Call Flow**: Validates `hyx != address(0)`. Finds `hyx` in `hyxes`, swaps with the last element, and pops. Emits `HyxRemoved`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**: `hyxes`.
- **Restrictions**: Restricted to `onlyOwner`. Reverts if `hyx` is zero (`"Invalid Hyx address"`) or not found (`"Hyx not found"`).
- **Gas Usage Controls**: Minimal gas with pop-and-swap.

### getHyxes()
- **Parameters**: None.
- **Behavior**: Returns the array of authorized Hyx addresses.
- **Internal Call Flow**: Returns `hyxes`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**: `hyxes`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### enterLongNative(address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `minEntryPrice` (uint256): Minimum entry price (normalized).
  - `maxEntryPrice` (uint256): Maximum entry price (normalized).
  - `initialMargin` (uint256): Initial margin (denormalized).
  - `excessMargin` (uint256): Excess margin (denormalized).
  - `leverage` (uint8): Leverage multiplier (2–100).
  - `stopLossPrice` (uint256): Stop-loss price (normalized).
  - `takeProfitPrice` (uint256): Take-profit price (normalized).
- **Behavior**: Creates a pending long position for `msg.sender`, transferring native gas token margins to `executionDriver`, computing fees, loans, and liquidation prices, and storing data via `SIUpdate`. Positions with `minEntryPrice` and `maxEntryPrice` as zero remain pending. Emits `PositionEntered` with `hyx = address(0)`.
- **Internal Call Flow**: Uses `EntryParams` struct. Calls `_initContext` to prepare `EntryContext` (fetches `tokenA` via `ISSListing.tokenA`, normalizes margins with `normalizeAmount` using `IERC20.decimals`), `_validateAndStore` (validates via `_validateEntry` with `ISSAgent.isValidListing`, stores via `_prepareEntryBase`, `_prepareEntryRisk`, `_prepareEntryToken`, `_validateEntryBase`, `_validateEntryRisk`), and `_finalizeEntrySteps` (`_updateEntryCore`, `_updateEntryParams` with `ISSListing.prices`, `_computeEntryParams`, `_validateLeverageLimit` using `ISSLiquidityTemplate.liquidityDetailsView`, `_updateEntryIndexes`, `_finalizeEntry` with native transfer in `_finalizeEntryTransfer` and fee transfer in `_finalizeEntryFees` using `IERC20.transferFrom` for tokenA to `liquidityAddress`, `ISSLiquidityTemplate.addFees` with `isLong = true`, and `_finalizeEntryPosition` with `SIUpdate`). Emits `PositionEntered`.
- **Balance Checks**:
  - **Pre-Balance Check (Fee)**: `IERC20.balanceOf(liquidityAddress)` before fee transfer.
  - **Post-Balance Check (Fee)**: Ensures `balanceAfter - balanceBefore >= denormFee`.
  - **Pre-Balance Check (Margin)**: `address(executionDriver).balance` before native margin transfer.
  - **Post-Balance Check (Margin)**: Ensures `balanceAfter - balanceBefore >= expectedAmount`.
- **Mappings/Structs Used**: `pendingEntries`, `positionIdCounter`, `EntryParams`, `EntryContext`, `PendingEntry`, `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `MarginParams`, `LeverageParams`, `RiskParams`, `TokenAndInterestParams`, `PositionArrayParams`, `PrepPosition`.
- **Restrictions**: Protected by `nonReentrant`. Requires `payable`. Reverts if `listingAddress` is zero (`"Invalid listing address"`), `initialMargin == 0` (`"Initial margin must be positive"`), `leverage` is out of range (`"Invalid leverage"`), `loanInitial` exceeds liquidity (`"Loan exceeds liquidity limit"`), or transfers fail (`"Insufficient native funds"`, `"Native transfer failed"`, `"Fee transfer failed"`).
- **Gas Usage Controls**: Uses `EntryParams` to reduce stack depth, single-element array updates, balance checks, and pop-and-swap.

### enterLongToken(address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice)
- **Parameters**: Same as `enterLongNative`.
- **Behavior**: Creates a pending long position for `msg.sender`, transferring tokenA margins to `executionDriver`. Emits `PositionEntered` with `hyx = address(0)`.
- **Internal Call Flow**: Same as `enterLongNative`, but `_finalizeEntryTransfer` uses `IERC20.transferFrom` for tokenA margins with pre/post balance checks via `IERC20.balanceOf(executionDriver)`.
- **Balance Checks**:
  - **Pre-Balance Check (Fee)**: `IERC20.balanceOf(liquidityAddress)` before fee transfer.
  - **Post-Balance Check (Fee)**: Ensures `balanceAfter - balanceBefore >= denormFee`.
  - **Pre-Balance Check (Margin)**: `IERC20.balanceOf(executionDriver)` before margin transfer.
  - **Post-Balance Check (Margin)**: Ensures `balanceAfter - balanceBefore >= expectedAmount`.
- **Mappings/Structs Used**: Same as `enterLongNative`.
- **Restrictions**: Protected by `nonReentrant`. Reverts with same conditions as `enterLongNative`, plus ERC20-specific transfer errors (`"Margin transfer failed"`).
- **Gas Usage Controls**: Same as `enterLongNative`.

### enterShortNative(address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice)
- **Parameters**: Same as `enterLongNative`.
- **Behavior**: Creates a pending short position for `msg.sender`, transferring native gas token margins to `executionDriver`. Emits `PositionEntered` with `hyx = address(0)`.
- **Internal Call Flow**: Same as `enterLongNative`, with `positionType = 1`. `_prepareEntryContext` uses `ISSListing.tokenB`. `_validateLeverageLimit` checks `xLiquid`. Fee transfer in `_finalizeEntryFees` uses `ISSLiquidityTemplate.addFees` with `isLong = false`.
- **Balance Checks**: Same as `enterLongNative`, for tokenB fees and native margins.
- **Mappings/Structs Used**: Same as `enterLongNative`.
- **Restrictions**: Same as `enterLongNative`.
- **Gas Usage Controls**: Same as `enterLongNative`.

### enterShortToken(address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice)
- **Parameters**: Same as `enterLongNative`.
- **Behavior**: Creates a pending short position for `msg.sender`, transferring tokenB margins to `executionDriver`. Emits `PositionEntered` with `hyx = address(0)`.
- **Internal Call Flow**: Same as `enterLongToken`, with `positionType = 1`. `_prepareEntryContext` uses `ISSListing.tokenB`. `_validateLeverageLimit` checks `xLiquid`. Fee transfer uses `ISSLiquidityTemplate.addFees` with `isLong = false`.
- **Balance Checks**: Same as `enterLongToken`, for tokenB.
- **Mappings/Structs Used**: Same as `enterLongNative`.
- **Restrictions**: Same as `enterLongToken`.
- **Gas Usage Controls**: Same as `enterLongNative`.

### driveNative(address maker, address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice, uint8 positionType)
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
- **Behavior**: Creates a position on behalf of `maker`, transferring native gas token margins to `executionDriver`. Emits `PositionEntered` with `hyx = msg.sender`.
- **Internal Call Flow**: Validates `maker != address(0)` and `positionType <= 1`. Uses `EntryParams` with `maker` and `isNative = true`. Calls `_initContext`, `_validateAndStore`, `_finalizeEntrySteps` as in `enterLongNative`. Emits `PositionEntered` with `hyx = msg.sender`.
- **Balance Checks**: Same as `enterLongNative`.
- **Mappings/Structs Used**: Same as `enterLongNative`.
- **Restrictions**: Protected by `nonReentrant`. Requires `payable`. Reverts if `maker` is zero (`"Invalid maker address"`) or `positionType > 1` (`"Invalid position type"`), plus `enterLongNative` restrictions.
- **Gas Usage Controls**: Same as `enterLongNative`.

### driveToken(address maker, address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice, uint8 positionType)
- **Parameters**: Same as `driveNative`.
- **Behavior**: Creates a position on behalf of `maker`, transferring ERC20 token margins (tokenA for long, tokenB for short) to `executionDriver`. Emits `PositionEntered` with `hyx = msg.sender`.
- **Internal Call Flow**: Same as `driveNative`, with `isNative = false`. `_finalizeEntryTransfer` uses `IERC20.transferFrom` for margins.
- **Balance Checks**: Same as `enterLongToken`.
- **Mappings/Structs Used**: Same as `enterLongNative`.
- **Restrictions**: Protected by `nonReentrant`. Reverts with same conditions as `driveNative`, plus ERC20-specific transfer errors.
- **Gas Usage Controls**: Same as `enterLongNative`.

## Additional Details
- **Decimal Handling**: Uses `DECIMAL_PRECISION` (1e18) for normalization, with `IERC20.decimals()` for token-specific precision (assumes `decimals <= 18`).
- **Market-Based Execution**: Positions with `minEntryPrice` and `maxEntryPrice` as zero remain pending (`priceAtEntry = 0`), deferring execution.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: Uses `EntryParams` to reduce stack depth, pop-and-swap for `hyxes`, single-element updates, and balance checks.
- **Listing Validation**: Uses `ISSAgent.isValidListing` for robust checks.
- **Token Usage**: Long positions use tokenA (or native for `Native` variants); short positions use tokenB (or native). Fees use tokenA for long, tokenB for short.
- **Position Lifecycle**: Pending (`status1 == false`, `status2 == 0`) to executable (`status1 == true`, `status2 == 0`).
- **Events**: Emitted for Hyx operations (`HyxAdded`, `HyxRemoved`) and position entry (`PositionEntered` with `positionId`, `maker`, `positionType`, `minEntryPrice`, `maxEntryPrice`, `hyx`).
- **Hyx Integration**: `hyxes` array authorizes external contracts. `drive` variants create positions for `maker` by any caller.
- **Safety**: Balance checks, explicit casting (e.g., `uint8`, `uint256`, `address(uint160)`), no inline assembly, and modular helpers (`_initContext`, `_validateAndStore`, `_finalizeEntrySteps`) ensure robustness.
- **Storage Updates**: Uses `SIUpdate` for all storage operations, aligning with `ISIStorage`.
- **Native Token Support**: `Native` variants use `msg.value` for margin transfers, with balance checks on `executionDriver`.
