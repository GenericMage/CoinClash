# CCSLiquidationDriver Contract Documentation

## Overview
The `CCSLiquidationDriver` contract suite, implemented in Solidity (^0.8.2), manages trading positions for long and short cross margin strategies, inheriting from `CCSLiquidationPartial` and `CCSExtraPartial`. It integrates with `ISSListing`, `ISSLiquidityTemplate`, `ICCAgent`, `ICSStorage`, and `ICCOrderRouter` for position execution, margin management, and state updates. It uses `IERC20` for token operations, `ReentrancyGuard` for protection, and `Ownable` (via `ReentrancyGuard`) for control. The suite handles margin additions, withdrawals, position closures, cancellations, and exits, with gas optimization and safety. State variables are public, accessed directly, and decimal precision is maintained. Transfers to/from listings use `ISSListing.update` or `ssUpdate`. `pullMargin` restricts withdrawals to no open/pending positions, optimizing gas. Derived from `CCSExecutionDriver`, it splits functionality into `CCSExtraDriver` for closures and cancellations.

**Inheritance Tree**: `CCSLiquidationDriver` → `CCSLiquidationPartial` → `ReentrancyGuard`, `Ownable`; `CCSExtraDriver` → `CCSExtraPartial` → `ReentrancyGuard`, `Ownable`

**SPDX License**: BSL-1.1 - Peng Protocol 2025

**Version**: 0.0.25 (last updated 2025-08-07)

## State Variables
- **DECIMAL_PRECISION** (uint256, constant, public): 1e18 for normalizing amounts/prices (`CCSLiquidationPartial`, `CCSExtraPartial`).
- **agentAddress** (address, public): Stores `ICCAgent` address for listing validation (`CCSLiquidationPartial`, `CCSExtraPartial`).
- **storageContract** (ICSStorage, public): Reference to storage contract (`CCSLiquidationPartial`, `CCSExtraPartial`).
- **orderRouter** (ICCOrderRouter, public): Reference to order router (`CCSLiquidationPartial`).
- **_tempPositionData** (mapping(uint256 => PositionCheck), private): Tracks position conditions (`CCSLiquidationPartial`, `CCSExtraPartial`).

## Mappings
- Defined in `ICSStorage` interface:
  - **makerTokenMargin**: Tracks normalized margin per maker/token.
  - **positionCore1**, **positionCore2**: Store position data/status.
  - **priceParams1**, **priceParams2**: Hold price/liquidation data.
  - **marginParams1**, **marginParams2**: Manage margin/loan details.
  - **exitParams**: Store exit conditions.
  - **positionToken**: Maps position ID to margin token.
  - **positionsByType**: Lists position IDs by type.
  - **longIOByHeight**, **shortIOByHeight**: Track open interest by block height.

## Structs
- Defined in `ICSStorage` interface:
  - **PositionCore1**: `positionId`, `listingAddress`, `makerAddress`, `positionType`.
  - **PositionCore2**: `status1` (active), `status2` (closed).
  - **PriceParams1**: `minEntryPrice`, `maxEntryPrice`, `minPrice`, `priceAtEntry`, `leverage`.
  - **PriceParams2**: `liquidationPrice`.
  - **MarginParams1**: `initialMargin`, `taxedMargin`, `excessMargin`, `fee`.
  - **MarginParams2**: `initialLoan`.
  - **ExitParams**: `stopLossPrice`, `takeProfitPrice`, `exitPrice`.
  - **PositionCheck** (local): `shouldLiquidate`, `shouldStopLoss`, `shouldTakeProfit`, `payout`.

## Formulas
- **Fee Calculation**: `fee = (initialMargin * (leverage - 1) * DECIMAL_PRECISION) / 100 / DECIMAL_PRECISION` (`_prepCloseLong`, `_prepCloseShort`).
- **Taxed Margin**: `taxedMargin = normalizeAmount(token, initialMargin) - fee` (referenced).
- **Leverage Amount**: `leverageAmount = normalizeAmount(token, initialMargin) * leverage` (referenced).
- **Initial Loan (Long)**: `initialLoan = leverageAmount / minPrice` (`_computeLoanAndLiquidationLong`).
- **Initial Loan (Short)**: `initialLoan = leverageAmount * minPrice` (`_computeLoanAndLiquidationShort`).
- **Liquidation Price (Long)**: `liquidationPrice = marginRatio < minPrice ? minPrice - marginRatio : 0` (`_computeLoanAndLiquidationLong`).
- **Liquidation Price (Short)**: `liquidationPrice = minPrice + marginRatio` (`_computeLoanAndLiquidationShort`).
- **Payout (Long)**: `payout = (currentPrice * initialLoan) / DECIMAL_PRECISION + excessMargin` (`_prepCloseLong`).
- **Payout (Short)**: `payout = priceAtEntry > currentPrice ? initialMargin + (priceAtEntry - currentPrice) * initialLoan / DECIMAL_PRECISION : initialMargin - (currentPrice - priceAtEntry) * initialLoan / DECIMAL_PRECISION + excessMargin` (`_prepCloseShort`).

## External Functions
- **setAgent(address)** (`CCSLiquidationPartial`, `CCSExtraPartial`): Updates `agentAddress`, `onlyOwner`.
- **addExcessTokenMargin(address, bool, uint256, address)** (`CCSLiquidationDriver`): Adds token margin, updates listing/maker margins, liquidation prices.
- **addExcessNativeMargin(address, bool, address)** (`CCSLiquidationDriver`): Adds native margin (WETH), updates margins/prices.
- **pullMargin(address, bool, uint256)** (`CCSLiquidationDriver`): Withdraws margin if no open/pending positions, uses `_executeMarginPayout`.
- **executeExits(address, uint256)** (`CCSLiquidationDriver`): Processes position exits (liquidation, stop-loss, take-profit).
- **cancelPosition(uint256)**, **cancelAllLongs(uint256)**, **cancelAllShorts(uint256)** (`CCSExtraDriver`): Cancels positions, updates state.
- **closeLongPosition(uint256)**, **closeShortPosition(uint256)**, **closeAllLongs(uint256)**, **closeAllShorts(uint256)** (`CCSExtraDriver`): Closes positions, issues payouts.

## Additional Details
- **Decimal Handling**: Uses `DECIMAL_PRECISION` for normalization.
- **Reentrancy Protection**: `nonReentrant` on state-changing functions.
- **Gas Optimization**: `maxIterations`, `gasleft() >= 50000`, pop-and-swap arrays.
- **Listing Validation**: `ICCAgent.isValidListing`.
- **Token Usage**: Long: tokenA margins, tokenB payouts; short: tokenB margins, tokenA payouts.
- **Events**: `PositionClosed`, `PositionCancelled`, `AllLongsClosed`, `AllShortsClosed`, `AllLongsCancelled`, `AllShortsCancelled`.
- **Safety**: Balance checks, explicit casting, no inline assembly.
- **Changes from CCSExecutionDriver**: Removed hyx functionality, moved closure/cancellation to `CCSExtraDriver`, optimized `pullMargin`, added `_executeMarginPayout`, `_reduceMakerMargin`.
