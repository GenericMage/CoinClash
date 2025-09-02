# CCLiquidityRouter Contract Documentation

## Overview
The `CCLiquidityRouter` contract, written in Solidity (^0.8.2), facilitates liquidity management on a decentralized trading platform, handling deposits, withdrawals, fee claims, and depositor changes. It inherits `CCLiquidityPartial` (v0.1.4) and `CCMainPartial` (v0.1.3), interacting with `ICCListing` (v0.0.7), `ICCLiquidity` (v0.0.5), and `CCLiquidityTemplate` (v0.1.8). It uses `ReentrancyGuard` for security and `Ownable` via inheritance. State variables are inherited, accessed via view functions, with amounts normalized to 1e18 decimals.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.1.5 (Updated 2025-09-01)

**Changes**:
- v0.1.5: Modified `_changeDepositor` to use new `updateType` (4 for xSlot, 5 for ySlot) to update only depositor address without affecting xLiquid/yLiquid. Ensures correct slot depositor change and prevents unintended liquidity increase.
- v0.1.4: Updated to reflect `CCLiquidityTemplate.sol` (v0.1.8) removal of `changeSlotDepositor`, with `_changeDepositor` in `CCLiquidityPartial.sol` (v0.1.4) now using `ccUpdate` directly for depositor changes, avoiding call forwarding.
- v0.1.3: Updated to reflect `CCLiquidityPartial.sol` (v0.1.4) changes, including relocation of `xPrepOut`, `xExecuteOut`, `yPrepOut`, `yExecuteOut` to `CCLiquidityPartial.sol` and renaming of `update` to `ccUpdate`. Fixed `ParserError` in `xExecuteOut` by renaming `slot reflux` to `slotData`.
- v0.1.2: Added `depositor` parameter to `depositToken` and `depositNativeToken`, renamed `inputAmount` to `outputAmount` in `withdraw`.
- v0.1.1: Added `depositor` parameter to support third-party deposits, renamed `inputAmount` to `amount`.
- v0.1.0: Bumped version.
- v0.0.25: Removed invalid try-catch in `depositNativeToken` and `depositToken`, updated compatibility.
- v0.0.24: Fixed TypeError by removing `this` from `_depositNative` and `_depositToken` calls.
- v0.0.23: Updated for `CCLiquidityPartial.sol` (v0.0.17), removed `listingId` from `FeesClaimed`.

**Inheritance Tree**: `CCLiquidityRouter` → `CCLiquidityPartial` → `CCMainPartial`

**Compatibility**: CCListingTemplate.sol (v0.0.10), CCMainPartial.sol (v0.1.3), CCLiquidityPartial.sol (v0.1.4), ICCLiquidity.sol (v0.0.5), ICCListing.sol (v0.0.7), CCLiquidityTemplate.sol (v0.1.8).

## Mappings
- **depositStates** (private, `CCLiquidityPartial.sol`): Maps `msg.sender` to `DepositState` for temporary deposit state management (unused in v0.1.4, retained for compatibility).
- Inherited from `CCLiquidityTemplate` via `CCLiquidityPartial`:
  - `routers`: Maps router addresses to authorization status.
  - `xLiquiditySlots`, `yLiquiditySlots`: Map indices to `Slot` structs.
  - `userXIndex`, `userYIndex`: Map user addresses to slot indices.

## Structs
- **DepositState** (CCLiquidityPartial, private, deprecated):
  - `listingAddress`: `ICCListing` address.
  - `depositor`: User address for deposits.
  - `inputAmount`: Input amount (denormalized).
  - `isTokenA`: True for token A, false for token B.
  - `tokenAddress`: Token address (or zero for ETH).
  - `liquidityAddr`: `ICCLiquidity` address.
  - `xAmount`, `yAmount`: Liquidity pool amounts.
  - `receivedAmount`: Actual amount after transfers.
  - `normalizedAmount`: Normalized amount (1e18).
  - `index`: Slot index for `xLiquiditySlots` or `yLiquiditySlots`.
  - `hasExistingSlot`: True if depositor has an existing slot (unused in v0.1.4).
  - `existingAllocation`: Current slot allocation (unused in v0.1.4).
- **DepositContext** (CCLiquidityPartial):
  - `listingAddress`: `ICCListing` address.
  - `depositor`: Address receiving slot credit.
  - `inputAmount`: Input amount (denormalized).
  - `isTokenA`: True for token A, false for token B.
  - `tokenAddress`: Token address (or zero for ETH).
  - `liquidityAddr`: `ICCLiquidity` address.
  - `xAmount`, `yAmount`: Liquidity pool amounts.
  - `receivedAmount`: Actual amount after transfers.
  - `normalizedAmount`: Normalized amount (1e18).
  - `index`: Slot index for `xLiquiditySlots` or `yLiquiditySlots`.
- **FeeClaimContext** (CCLiquidityPartial):
  - `listingAddress`: `ICCListing` address.
  - `depositor`: User address.
  - `liquidityIndex`: Slot index.
  - `isX`: True for token A, false for token B.
  - `liquidityAddr`: `ICCLiquidity` address.
  - `xBalance`: Listing volume balance.
  - `xLiquid`, `yLiquid`: Liquidity amounts from `liquidityDetailsView`.
  - `xFees`, `yFees`: Available fees from `liquidityDetailsView`.
  - `liquid`: Relevant liquidity (`xLiquid` or `yLiquid`).
  - `fees`: Relevant fees (`yFees` for xSlots, `xFees` for ySlots).
  - `allocation`: Slot allocation.
  - `dFeesAcc`: Cumulative fees at deposit/claim.
  - `transferToken`: Token to transfer (tokenB for xSlots, tokenA for ySlots).
  - `feeShare`: Calculated fee share (normalized).
- **ICCLiquidity.PreparedWithdrawal** (CCMainPartial):
  - `amountA`: Normalized token A amount to withdraw.
  - `amountB`: Normalized token B amount to withdraw.
- **ICCLiquidity.Slot** (CCMainPartial):
  - `depositor`: Slot owner address.
  - `recipient`: Unused (reserved).
  - `allocation`: Normalized liquidity contribution.
  - `dFeesAcc`: Cumulative fees at deposit/claim.
  - `timestamp`: Slot creation timestamp.
- **ICCLiquidity.UpdateType** (CCMainPartial):
  - `updateType`: Update type (0=balance, 1=fees, 2=xSlot, 3=ySlot).
  - `index`: Index (0=xFees/xLiquid, 1=yFees/yLiquid, or slot).
  - `value`: Normalized amount.
  - `addr`: Depositor address.
  - `recipient`: Unused (reserved).

## Formulas
1. **Fee Share** (in `_calculateFeeShare`):
   - **Formula**:
     ```
     contributedFees = fees > dFeesAcc ? fees - dFeesAcc : 0
     liquidityContribution = liquid > 0 ? (allocation * 1e18) / liquid : 0
     feeShare = (contributedFees * liquidityContribution) / 1e18
     feeShare = feeShare > fees ? fees : feeShare
     ```
   - **Description**: Computes fee share based on accumulated fees since deposit/claim (`fees` is `yFees` for xSlots, `xFees` for ySlots), proportional to slot `allocation` relative to pool `liquid`, capped at available fees.
   - **Used in**: `claimFees` via `_processFeeShare`.

2. **Deficit and Compensation** (in `xPrepOut`, `yPrepOut` in `CCLiquidityPartial`):
   - **xPrepOut**:
     ```
     withdrawAmountA = min(amount, xLiquid)
     deficit = amount > withdrawAmountA ? amount - withdrawAmountA : 0
     withdrawAmountB = deficit > 0 ? min((deficit * 1e18) / prices(0), yLiquid) : 0
     ```
   - **yPrepOut**:
     ```
     withdrawAmountB = min(amount, yLiquid)
     deficit = amount > withdrawAmountB ? amount - withdrawAmountB : 0
     withdrawAmountA = deficit > 0 ? min((deficit * prices(0)) / 1e18, xLiquid) : 0
     ```
   - **Description**: Calculates withdrawal amounts, compensating shortfalls using `ICCListing.prices(0)` (price of token B in token A, 1e18 precision), capped by available liquidity (`xLiquid` or `yLiquid`).
   - **Used in**: `withdraw` via `_prepWithdrawal`.

## External Functions
### depositNativeToken(address listingAddress, address depositor, uint256 amount, bool isTokenA)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address, validated by `onlyValidListing`.
  - `depositor`: Address receiving liquidity slot credit.
  - `amount`: ETH amount (denormalized, 18 decimals).
  - `isTokenA`: True for token A, false for token B.
- **Behavior**: Deposits ETH from `msg.sender` (depositInitiator) to `CCLiquidityTemplate` via `_depositNative`, assigning the slot to `depositor`. Creates a new slot using `nextXSlotIDView` or `nextYSlotIDView`.
- **Internal Call Flow**:
  - `_validateDeposit`: Validates inputs, retrieves `tokenAddress`, `liquidityAddr`, `xAmount`, `yAmount`, sets `index` via `activeXLiquiditySlotsView` or `activeYLiquiditySlotsView`.
  - `_executeNativeTransfer`: Validates `msg.value == amount`, transfers ETH from `msg.sender` to `CCLiquidityTemplate`, performs pre/post balance checks.
  - `_updateDeposit`: Creates `UpdateType`, calls `ICCLiquidity.ccUpdate` with `depositor`, emits `DepositReceived` or `DepositFailed`.
- **Balance Checks**: `msg.value == amount`, pre/post balance on `CCLiquidityTemplate` for `receivedAmount`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, payable.
- **Gas**: Low-level `call`, single `ccUpdate` call.
- **Interactions**: Calls `ICCListing` for `tokenA`, `tokenB`, `liquidityAddressView`; `ICCLiquidity` for `liquidityAmounts`, `activeXLiquiditySlotsView`, `activeYLiquiditySlotsView`, `ccUpdate`; transfers ETH to `CCLiquidityTemplate`.

### depositToken(address listingAddress, address depositor, uint256 amount, bool isTokenA)
- **Parameters**: Same as `depositNativeToken`, for ERC20 tokens.
- **Behavior**: Deposits ERC20 tokens from `msg.sender` (depositInitiator) to `CCLiquidityTemplate` via `_depositToken`, assigning the slot to `depositor`. Creates a new slot.
- **Internal Call Flow**:
  - `_validateDeposit`: Validates inputs, retrieves `tokenAddress()`, `liquidityAddr`, `xAmount`, `yAmount`, sets `index` via `activeXLiquiditySlotsView` or `activeYLiquiditySlotsView`.
  - `_executeTokenTransfer`: Checks allowance for `msg.sender`, calls `IERC20.transferFrom(msg.sender, address(this), amount)`, then `IERC20.transfer` to `CCLiquidityTemplate`, performs pre/post balance checks.
  - `_updateDeposit`: Creates `UpdateType`, calls `ICCLiquidity.ccUpdate` with `depositor`, emits `DepositReceived` or `DepositFailed`.
- **Balance Checks**: Pre/post balance on `CCLiquidityRouter` and `CCLiquidityTemplate`, allowance check via `IERC20.allowance` for `msg.sender`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Two `IERC20` transfers, single `ccUpdate` call.
- **Interactions**: Calls `IERC20` for `allowance`, `transferFrom`, `transfer`, `decimals`; `ICCListing` for `tokenA`, `tokenB`, `liquidityAddressView`; `ICCLiquidity` for `liquidityAmounts`, `activeXLiquiditySlotsView`, `activeYLiquiditySlotsView`, `ccUpdate`.

### withdraw(address listingAddress, uint256 outputAmount, uint256 index, bool isX)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `outputAmount`: Normalized amount (1e18) to withdraw.
  - `index`: Slot index in `xLiquiditySlots` or `yLiquiditySlots`.
  - `isX`: True for token A, false for token B.
- **Behavior**: Withdraws liquidity from `CCLiquidityTemplate` for `msg.sender` via `_prepWithdrawal` and `_executeWithdrawal`.
- **Internal Call Flow**:
  - `_prepWithdrawal`: Validates `msg.sender`, calls internal `xPrepOut` or `yPrepOut` (in `CCLiquidityPartial`) to get `PreparedWithdrawal`.
  - `_executeWithdrawal`: Calls internal `xExecuteOut` or `yExecuteOut` (in `CCLiquidityPartial`), which updates slots via `ICCLiquidity.ccUpdate`, transfers tokens/ETH to `msg.sender` via `ICCLiquidity.transactToken` or `transactNative`.
  - `xPrepOut` (internal): Validates `depositor`, checks `xLiquid` and slot `allocation`, calculates `withdrawAmountA` and `withdrawAmountB` using `ICCListing.prices(0)` for compensation if shortfall.
  - `yPrepOut` (internal): Validates `depositor`, checks `yLiquid` and slot `allocation`, calculates `withdrawAmountA` and `withdrawAmountB` using `ICCListing.prices(0)` for compensation if shortfall.
  - `xExecuteOut` (internal): Updates slot via `ICCLiquidity.ccUpdate`, transfers `amountA` (tokenA) and `amountB` (tokenB) via `transactToken` or `transactNative`.
  - `yExecuteOut` (internal): Updates slot via `ICCLiquidity.ccUpdate`, transfers `amountB` (tokenB) and `amountA` (tokenA) via `transactToken` or `transactNative`.
- **Balance Checks**: Implicit in `xPrepOut`/`yPrepOut` via `xLiquid`/`yLiquid` and slot `allocation`, explicit in `transactToken`/`transactNative` via `xLiquid`/`yLiquid`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Two internal calls (`xPrepOut`/`yPrepOut`, `xExecuteOut`/`yExecuteOut`), multiple transfers if both tokens withdrawn.
- **Interactions**: Calls `ICCListing` for `liquidityAddressView`, `prices`, `decimalsA`, `decimalsB`, `tokenA`, `tokenB`; `ICCLiquidity` for `getXSlotView`, `getYSlotView`, `liquidityDetailsView`, `ccUpdate`, `transactToken`, `transactNative`.

### claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `liquidityIndex`: Slot index.
  - `isX`: True for token A, false for token B.
  - `volumeAmount`: Ignored (reserved for future use).
- **Behavior**: Claims fees from `CCLiquidityTemplate` for `msg.sender` via `_processFeeShare`.
- **Internal Call Flow**:
  - `_validateFeeClaim`: Checks `xBalance`, slot ownership, liquidity availability via `ICCListing.volumeBalances`, `ICCLiquidity.liquidityDetailsView`, `getXSlotView` or `getYSlotView`.
  - `_calculateFeeShare`: Computes `feeShare` using the fee share formula.
  - `_executeFeeClaim`: Creates `UpdateType` array, calls `ICCLiquidity.ccUpdate`, transfers fees via `ICCLiquidity.transactToken` or `transactNative`, emits `FeesClaimed`.
- **Balance Checks**: `xBalance`, `xLiquid`/`yLiquid`, `allocation`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Two `ccUpdate` calls, one transfer.
- **Interactions**: Calls `ICCListing` for `volumeBalances`, `tokenA`, `tokenB`, `liquidityAddressView`; `ICCLiquidity` for `liquidityDetailsView`, `getXSlotView`, `getYSlotView`, `ccUpdate`, `transactToken`, `transactNative`.

### changeDepositor(address listingAddress, bool isX, uint256 slotIndex, address newDepositor)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `isX`: True for token A, false for token B.
  - `slotIndex`: Slot index.
  - `newDepositor`: New slot owner address.
- **Behavior**: Reassigns slot ownership from `msg.sender` to `newDepositor` via `_changeDepositor`.
- **Internal Call Flow**:
  - `_changeDepositor`: Validates `msg.sender` and `newDepositor`, checks slot ownership and allocation via `ICCLiquidity.getXSlotView` or `getYSlotView`, creates `UpdateType` array, calls `ICCLiquidity.ccUpdate` to update slot `depositor` and `userXIndex`/`userYIndex`, emits `SlotDepositorChanged`.
- **Balance Checks**: Implicit via `allocation` check in `_changeDepositor`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Single `ccUpdate` call.
- **Interactions**: Calls `ICCListing` for `liquidityAddressView`; `ICCLiquidity` for `getXSlotView`, `getYSlotView`, `ccUpdate`.

## Clarifications and Nuances
- **Token Flow**:
  - **Deposits**: `msg.sender` (depositInitiator) → `CCLiquidityRouter` → `CCLiquidityTemplate`. Slot assigned to `depositor`. Pre/post balance checks handle tax-on-transfer tokens using `receivedAmount`.
  - **Withdrawals**: `CCLiquidityTemplate` → `msg.sender`. `PreparedWithdrawal` handles dual-token withdrawals if liquidity is insufficient, using `prices(0)` for conversion.
  - **Fees**: `CCLiquidityTemplate` → `msg.sender`, with `feeShare`uola based on `allocation` and `liquid`.
- **Decimal Handling**: Normalizes to 1e18 using `normalize`, denormalizes for transfers using `IERC20.decimals` or 18 for ETH.
- **Security**:
  - `nonReentrant` prevents reentrancy.
  - Try-catch ensures graceful degradation with `TransferFailed`, `DepositFailed`, `FeesClaimed`, `SlotDepositorChanged`.
  - No `virtual`/`override`, explicit casting, no inline assembly, no reserved keywords.
- **Gas Optimization**:
  - `DepositContext` reduces stack usage in call tree.
  - Early validation in `_validateDeposit`, `_executeTokenTransfer`, `_executeNativeTransfer` minimizes gas on failures.
- **Error Handling**: Detailed errors (`InsufficientAllowance`, etc.) and events aid debugging.
- **Router Validation**: `CCLiquidityTemplate` validates `routers[msg.sender]` for state-changing functions (`ccUpdate`, `transactToken`, `transactNative`).
- **Pool Validation**: Allows deposits in any pool state, supporting zero-balance initialization.
- **Multiple Deposits**: Always creates new slots, simplifying deposit logic.
- **Limitations**: Payouts handled in `CCOrderRouter`.
- **Call Tree**: `_depositToken` and `_depositNative` split into `_validateDeposit`, `_executeTokenTransfer`, `_executeNativeTransfer`, `_updateDeposit`; `_changeDepositor` uses single `ccUpdate` call, reducing complexity.
