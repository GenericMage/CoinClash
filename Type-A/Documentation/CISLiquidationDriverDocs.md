# CISLiquidationDriver Contract Documentation

## Overview
The `CISLiquidationDriver` contract, implemented in Solidity (^0.8.2), manages liquidation and margin operations for isolated margin trading positions, inheriting from `CISLiquidationPartial`. It integrates with external interfaces (`ISSListing`, `ISSAgent`, `ISIStorage`) for listing validation, position management, and state updates. It uses `IERC20` for token operations and `ReentrancyGuard` for reentrancy protection. The suite handles position liquidation, excess margin addition (ERC20 and native ETH), and margin withdrawal, with gas optimization and safety mechanisms. All transfers to/from listings use `ISSListing.update` or `ssUpdate`, and state updates use `ISIStorage.SIUpdate` with explicit struct initialization.

**Inheritance Tree**: `CISLiquidationDriver` → `CISLiquidationPartial` → `ReentrancyGuard`

**SPDX License**: BSL-1.1 - Peng Protocol 2025

**Version**: 0.0.3 (last updated 2025-08-10)
- 2025-08-10: Split `addExcessMargin` into `addExcessTokenMargin` (ERC20) and `addExcessNativeMargin` (ETH). Removed duplicated interfaces (`IERC20`, `ISIStorage`) from `CISLiquidationDriver.sol`. Fixed TypeError by removing `view` from `_computePayoutLong`, `_computePayoutShort`, `_validateExcessMargin`.
- 2025-08-08: Initial creation, segregated from `CISExecutionDriver` v0.0.5.

## State Variables
- **DECIMAL_PRECISION** (uint256, constant, public): Set to 1e18 for normalizing amounts and prices across token decimals (in `CISLiquidationPartial`).
- **_agentAddress** (address, private): Stores `ISSAgent` contract address for listing validation, set via `setAgent` (in `CISLiquidationPartial`).
- **_storageContract** (ISIStorage, internal): Reference to the storage contract, set in constructor (in `CISLiquidationPartial`).
- **_historicalInterestHeight** (uint256, private): Tracks block height for open interest updates, initialized to 1 (in `CISLiquidationPartial`).

## Mappings
- Defined in `ISIStorage` interface (inlined in `CISLiquidationPartial`):
  - **positionCoreBase** (mapping(uint256 => PositionCoreBase)): Stores core position data (makerAddress, listingAddress, positionId, positionType).
  - **positionCoreStatus** (mapping(uint256 => PositionCoreStatus)): Tracks position status (status1, status2).
  - **priceParams** (mapping(uint256 => PriceParams)): Holds price data (priceMin, priceMax, priceAtEntry, priceClose).
  - **marginParams** (mapping(uint256 => MarginParams)): Manages margin details (marginInitial, marginTaxed, marginExcess).
  - **leverageParams** (mapping(uint256 => LeverageParams)): Stores leverage details (leverageVal, leverageAmount, loanInitial).
  - **riskParams** (mapping(uint256 => RiskParams)): Contains risk parameters (priceLiquidation, priceStopLoss, priceTakeProfit).
  - **pendingPositions** (mapping(address => mapping(uint8 => uint256[]))): Tracks pending position IDs by listing address and type (0 for long, 1 for short).
  - **positionsByType** (mapping(uint8 => uint256[])): Stores position IDs by type (0 for long, 1 for short).
  - **positionToken** (mapping(uint256 => address)): Maps position ID to margin token (tokenA for long, tokenB for short, address(0) for ETH).
  - **longIOByHeight** (mapping(uint256 => uint256)): Tracks long open interest by block height.
  - **shortIOByHeight** (mapping(uint256 => uint256)): Tracks short open interest by block height.

## Structs
- Defined in `ISIStorage` interface (inlined in `CISLiquidationPartial`):
  - **PositionCoreBase**: Contains `makerAddress` (address), `listingAddress` (address), `positionId` (uint256), `positionType` (uint8: 0 for long, 1 for short).
  - **PositionCoreStatus**: Tracks `status1` (bool), `status2` (uint8: 0 for open, 1 for closed).
  - **PriceParams**: Stores `priceMin`, `priceMax`, `priceAtEntry`, `priceClose` (uint256, normalized).
  - **MarginParams**: Holds `marginInitial`, `marginTaxed`, `marginExcess` (uint256, normalized).
  - **LeverageParams**: Contains `leverageVal` (uint8), `leverageAmount`, `loanInitial` (uint256, normalized).
  - **RiskParams**: Stores `priceLiquidation`, `priceStopLoss`, `priceTakeProfit` (uint256, normalized).
  - **CoreParams**, **TokenAndInterestParams**, **PositionArrayParams**: Used in `SIUpdate` for state updates.
- From `ISSListing` (inlined in `CISLiquidationPartial`):
  - **UpdateType**: Stores `updateType` (uint8), `structId` (uint8), `index` (uint256), `value` (uint256), `addr` (address), `recipient` (address), `maxPrice`, `minPrice`, `amountSent` (uint256).
  - **PayoutUpdate**: Stores `payoutType` (uint8), `recipient` (address), `required` (uint256, denormalized).

## Formulas
Formulas are implemented in `CISLiquidationPartial` for liquidation and margin calculations, derived from `CISExecutionDriver` v0.0.5.

1. **Fee Calculation**:
   - **Formula**: `fee = (initialMargin * (leverage - 1) * DECIMAL_PRECISION) / 100 / DECIMAL_PRECISION`
   - **Used in**: `_computeFee` (called indirectly via `_updateMarginAndInterest`).
   - **Description**: Computes fee based on leverage and normalized initial margin.

2. **Initial Loan (Long)**:
   - **Formula**: `initialLoan = leverageAmount / minPrice`
   - **Used in**: `_computeLoanAndLiquidationLong`.
   - **Description**: Loan for long positions based on minimum price.

3. **Initial Loan (Short)**:
   - **Formula**: `initialLoan = leverageAmount * minPrice`
   - **Used in**: `_computeLoanAndLiquidationShort`.
   - **Description**: Loan for short positions based on minimum price.

4. **Liquidation Price (Long)**:
   - **Formula**: `liquidationPrice = marginRatio < minPrice ? minPrice - marginRatio : 0`, where `marginRatio = marginInitial / leverageAmount`
   - **Used in**: `_computeLoanAndLiquidationLong`.
   - **Description**: Liquidation price for long positions.

5. **Liquidation Price (Short)**:
   - **Formula**: `liquidationPrice = minPrice + marginRatio`
   - **Used in**: `_computeLoanAndLiquidationShort`.
   - **Description**: Liquidation price for short positions.

6. **Payout (Long)**:
   - **Formula**: `payout = baseValue > loanInitial ? baseValue - loanInitial : 0`, where `baseValue = (taxedMargin + excessMargin + leverageAmount) / currentPrice`
   - **Used in**: `_computePayoutLong`.
   - **Description**: Payout for long position closure in tokenB.

7. **Payout (Short)**:
   - **Formula**: `payout = profit + (taxedMargin + excessMargin) * currentPrice / DECIMAL_PRECISION`, where `profit = (priceAtEntry - currentPrice) * initialMargin * leverageVal`
   - **Used in**: `_computePayoutShort`.
   - **Description**: Payout for short position closure in tokenA.

## External Functions
Functions are implemented in `CISLiquidationDriver` unless specified, with helpers in `CISLiquidationPartial`. All align with `CISExecutionDriver` v0.0.5 for liquidation and margin management.

### setAgent(address newAgentAddress)
- **Contract**: `CISLiquidationPartial`
- **Parameters**: `newAgentAddress` (address): New ISSAgent address.
- **Behavior**: Updates `_agentAddress` for listing validation.
- **Internal Call Flow**: Validates `newAgentAddress != address(0)`, assigns to `_agentAddress`. Emits `ErrorLogged` on failure. No external calls or transfers.
- **Mappings/Structs Used**: None.
- **Restrictions**: `onlyOwner`, reverts if `newAgentAddress` is zero (`"Invalid agent address"`).
- **Gas Usage Controls**: Minimal, single state write.

### executeExits(address listingAddress, uint256 maxIterations)
- **Contract**: `CISLiquidationDriver`
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Processes active positions, closing those triggered by liquidation, stop-loss, or take-profit. Payouts in tokenB (long) or tokenA (short). Emits `PositionClosed`.
- **Internal Call Flow**:
  - Validates `listingAddress != address(0)` and `ISSAgent.isValidListing`.
  - Calls `_executeExits`:
    - Iterates `positionsByType[positionType]` (0 for long, 1 for short) up to `maxIterations` and `gasleft() >= 50000`.
    - For each position, calls `_processActivePosition`:
      - Validates `positionCoreBase` (`positionId`, `listingAddress`) and `positionCoreStatus` (`status2 == 0`).
      - Updates `riskParams.priceLiquidation` via `_updateLiquidationPrice`.
      - Checks liquidation (`currentPrice <= priceLiquidation` for long, `>=` for short), stop-loss (`priceStopLoss > 0` and `currentPrice <= priceStopLoss` for long, `>=` for short), or take-profit (`priceTakeProfit > 0` and `currentPrice >= priceTakeProfit` for long, `<=` for short).
      - If triggered, computes payout via `_computePayoutLong` or `_computePayoutShort`, removes position via `removePositionIndex`, and emits `PositionClosed`.
- **Balance Checks**: None, as payouts are handled by `ISSListing.ssUpdate`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `priceParams`, `marginParams`, `leverageParams`, `riskParams`, `positionsByType`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `MarginParams`, `LeverageParams`, `RiskParams`, `PayoutUpdate`.
- **Restrictions**: `nonReentrant`, reverts if `listingAddress` is zero (`"Invalid listing address"`) or invalid (`"Invalid listing"`).
- **Gas Usage Controls**: `maxIterations`, `gasleft() >= 50000`, pop-and-swap for arrays.

### addExcessTokenMargin(uint256 positionId, uint256 amount, address token)
- **Contract**: `CISLiquidationDriver`
- **Parameters**:
  - `positionId` (uint256): Position ID.
  - `amount` (uint256): Margin to add (denormalized).
  - `token` (address): Margin token (tokenA for long, tokenB for short).
- **Behavior**: Adds excess ERC20 margin to an open position, transfers to listing, updates margin and interest, and recalculates liquidation price. Emits `ExcessMarginAdded`.
- **Internal Call Flow**:
  - Validates `positionId` in `positionCoreBase`, `status2 == 0`, `makerAddress == msg.sender`, `amount > 0`, `token == positionToken[positionId]`.
  - Normalizes `amount` via `normalizeAmount` (`IERC20.decimals`).
  - Calls `_validateExcessMargin` (`normalizedAmount <= leverageAmount`).
  - Transfers margin via `_transferExcessMargin` (`IERC20.transferFrom`, checks balances).
  - Updates `marginParams.marginExcess` and `longIOByHeight`/`shortIOByHeight` via `_updateMarginAndInterest` (calls `ISSListing.update`).
  - Updates `riskParams.priceLiquidation` via `_updateLiquidationPrice`.
- **Balance Checks**:
  - **Pre-Balance Check**: `IERC20.balanceOf(msg.sender)` (implicit in `transferFrom`).
  - **Post-Balance Check**: `IERC20.balanceOf(listingAddress)` in `_transferExcessMargin`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `marginParams`, `leverageParams`, `riskParams`, `positionToken`, `longIOByHeight`, `shortIOByHeight`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `MarginParams`, `LeverageParams`, `RiskParams`, `UpdateType`.
- **Restrictions**: `nonReentrant`, reverts if `amount == 0`, position is invalid/closed, caller is not maker, or token mismatches.
- **Gas Usage Controls**: Minimal, single position update.

### addExcessNativeMargin(uint256 positionId)
- **Contract**: `CISLiquidationDriver`
- **Parameters**:
  - `positionId` (uint256): Position ID.
- **Behavior**: Adds excess native ETH margin to an open position, transfers to listing, updates margin and interest, and recalculates liquidation price. Emits `ExcessMarginAdded`.
- **Internal Call Flow**:
  - Validates `positionId` in `positionCoreBase`, `status2 == 0`, `makerAddress == msg.sender`, `msg.value > 0`, `positionToken[positionId] == address(0)`.
  - Normalizes `msg.value` (`msg.value * DECIMAL_PRECISION`).
  - Calls `_validateExcessMargin` (`normalizedAmount <= leverageAmount`).
  - Transfers ETH via `call` to `listingAddress`.
  - Updates `marginParams.marginExcess` and `longIOByHeight`/`shortIOByHeight` via `_updateMarginAndInterest` (calls `ISSListing.update`).
  - Updates `riskParams.priceLiquidation` via `_updateLiquidationPrice`.
- **Balance Checks**: None explicit, relies on `call` success for ETH transfer.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `marginParams`, `leverageParams`, `riskParams`, `positionToken`, `longIOByHeight`, `shortIOByHeight`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `MarginParams`, `LeverageParams`, `RiskParams`, `UpdateType`.
- **Restrictions**: `nonReentrant`, reverts if `msg.value == 0`, position is invalid/closed, caller is not maker, or token is not ETH.
- **Gas Usage Controls**: Minimal, single position update.

### pullMargin(uint256 positionId, uint256 amount)
- **Contract**: `CISLiquidationDriver`
- **Parameters**:
  - `positionId` (uint256): Position ID.
  - `amount` (uint256): Margin to withdraw (denormalized).
- **Behavior**: Withdraws excess margin from an open position, updates liquidation price, and pays out to `msg.sender`. No event emitted.
- **Internal Call Flow**:
  - Validates `positionId` in `positionCoreBase`, `status2 == 0`, `makerAddress == msg.sender`, `amount > 0`, `normalizedAmount <= marginExcess`.
  - Updates `marginParams.marginExcess` via `SIUpdate`.
  - Updates `riskParams.priceLiquidation` via `_updateLiquidationPrice`.
  - Pays out via `_executeMarginPayout` (`ISSListing.ssUpdate`).
  - Updates `longIOByHeight`/`shortIOByHeight` via `_updateHistoricalInterest`.
- **Balance Checks**: None, as payouts are handled by `ISSListing.ssUpdate`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `marginParams`, `riskParams`, `positionToken`, `longIOByHeight`, `shortIOByHeight`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `MarginParams`, `RiskParams`, `PayoutUpdate`.
- **Restrictions**: `nonReentrant`, reverts if `amount == 0`, position is invalid/closed, caller is not maker, or insufficient `marginExcess`.
- **Gas Usage Controls**: Minimal, single position update.

## Additional Details
- **Decimal Handling**: Uses `DECIMAL_PRECISION` (1e18) for normalization via `normalizeAmount`, `denormalizeAmount`, `normalizePrice`, handling token decimals (`IERC20.decimals`) and ETH (18 decimals).
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: `maxIterations`, `gasleft() >= 50000`, pop-and-swap for arrays in `removePositionIndex`.
- **Listing Validation**: `ISSAgent.isValidListing` ensures valid listings in `executeExits`.
- **Token Usage**: Long positions use tokenA margins, tokenB payouts; short positions use tokenB margins, tokenA payouts; ETH positions use address(0) as token.
- **Position Lifecycle**: Focuses on active positions (`status1 == true`, `status2 == 0`) to closed (`status2 == 1`).
- **Events**: `PositionClosed`, `ExcessMarginAdded`, `ErrorLogged`.
- **Safety**: Explicit casting, balance checks in `_transferExcessMargin`, no inline assembly, modular helpers (`_validateExcessMargin`, `_updateLiquidationPrice`).
- **Listing Updates**: Transfers to/from listings use `ISSListing.update` (in `_updateMarginAndInterest`) or `ssUpdate` (in `_executeMarginPayout`).
- **Differences from `CISExecutionDriver`**: Omits position creation, batch operations (`closeAllLongs`, `cancelAllLongs`), hyx functions, and SL/TP updates, focusing on liquidation and margin management.
