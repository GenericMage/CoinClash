# CCLiquidityRouter Contract Documentation

## Overview
The `CCLiquidityRouter` contract, written in Solidity (^0.8.2), facilitates liquidity management on a decentralized trading platform, handling deposits, withdrawals, fee claims, and depositor changes. It inherits `CCLiquidityPartial` (v0.1.33) and `CCMainPartial` (v0.0.10), interacting with `ICCListing` (v0.0.7), `ICCLiquidity` (v0.0.4), and `CCLiquidityTemplate` (v0.0.20). It uses `ReentrancyGuard` for security and `Ownable` via inheritance. State variables are inherited, accessed via view functions, with amounts normalized to 1e18 decimals.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.1.15 (Updated 2025-09-20)

**Changes**:
- v0.1.15: Updated to reflect `CCLiquidityPartial.sol` (v0.1.33) with `_processFeeShare` using `FeeClaimCore` and `FeeClaimDetails` structs, fixing `DeclarationError`. Updated `FeeClaimContext` to `FeeClaimCore` and `FeeClaimDetails` split (v0.1.32). Added `_fetchLiquidityDetails`, `_fetchSlotDetails` for stack optimization. Updated fee share calculation to use `xFeesAcc`/`yFeesAcc` (v0.1.30).
- v0.1.14: Updated to reflect `CCLiquidityPartial.sol` (v0.1.29) with inverted `updateType` in `_executeFeeClaim` for fee subtraction.
- v0.1.13: Updated to reflect `CCLiquidityPartial.sol` (v0.1.28) with `_executeFeeClaim` using `updateType` 8/9 for fee subtraction. Updated `_transferWithdrawalAmount` to revert if compensation transfer fails when `compensationAmount > 0` (v0.1.27).
- v0.1.12: Updated to reflect `CCLiquidityPartial.sol` (v0.1.26) with `_executeWithdrawal` reordered to call `_transferWithdrawalAmount` before `_updateWithdrawalAllocation`.
- v0.1.11: Updated to reflect `CCLiquidityPartial.sol` (v0.1.25) with fixed `listingContract` declarations in `_fetchWithdrawalData` and `_updateWithdrawalAllocation`.
- v0.1.10: Updated to reflect `CCLiquidityPartial.sol` (v0.1.24) with `_executeWithdrawal` refactored into `_fetchWithdrawalData`, `_updateWithdrawalAllocation`, `_transferWithdrawalAmount` to fix stack too deep error. Extended `WithdrawalContext` with `totalAllocationDeduct` and `price`.
- v0.1.9: Updated to reflect `CCLiquidityPartial.sol` (v0.1.23) with `_prepWithdrawal` accepting `compensationAmount`, minimal checks (ownership, allocation), non-reverting behavior, and event emission (`ValidationFailed`, `WithdrawalFailed`, `TransferSuccessful`).
- v0.1.8: Updated to reflect `CCLiquidityRouter.sol` (v0.1.3) with `withdraw` accepting `compensationAmount`.

**Inheritance Tree**: `CCLiquidityRouter` → `CCLiquidityPartial` → `CCMainPartial`

**Compatibility**: CCListingTemplate.sol (v0.0.10), CCMainPartial.sol (v0.0.10), CCLiquidityPartial.sol (v0.1.33), ICCLiquidity.sol (v0.0.4), ICCListing.sol (v0.0.7), CCLiquidityTemplate.sol (v0.0.20).

## Mappings
- **depositStates** (private, `CCLiquidityPartial.sol`): Maps `msg.sender` to `DepositState` for temporary deposit state management (deprecated, retained for compatibility).
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
  - `hasExistingSlot`: True if depositor has an existing slot (unused in v0.1.33).
  - `existingAllocation`: Current slot allocation (unused in v0.1.33).
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
- **FeeClaimCore** (CCLiquidityPartial):
  - `listingAddress`: `ICCListing` address.
  - `depositor`: User address.
  - `liquidityIndex`: Slot index.
  - `isX`: True for token A, false for token B.
  - `liquidityAddr`: `ICCLiquidity` address.
  - `transferToken`: Token to transfer (tokenB for xSlots, tokenA for ySlots).
  - `feeShare`: Calculated fee share (normalized).
- **FeeClaimDetails** (CCLiquidityPartial):
  - `xLiquid`, `yLiquid`: Liquidity amounts from `liquidityDetailsView`.
  - `xFees`, `yFees`: Available fees from `liquidityDetailsView`.
  - `xFeesAcc`, `yFeesAcc`: Cumulative fees from `liquidityDetailsView`.
  - `allocation`: Slot allocation.
  - `dFeesAcc`: Cumulative fees at deposit/claim.
- **WithdrawalContext** (CCLiquidityPartial):
  - `listingAddress`: `ICCListing` address.
  - `depositor`: User address.
  - `index`: Slot index.
  - `isX`: True for token A, false for token B.
  - `primaryAmount`: Normalized amount to withdraw (token A for xSlot, token B for ySlot).
  - `compensationAmount`: Normalized compensation amount (token B for xSlot, token A for ySlot).
  - `currentAllocation`: Slot allocation.
  - `tokenA`, `tokenB`: Token addresses from `ICCListing`.
  - `totalAllocationDeduct`: Total allocation to deduct (primary + converted compensation).
  - `price`: Current price (tokenB/tokenA, normalized to 1e18) from `ICCListing.prices(0)`.
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
  - `updateType`: Update type (0=balance, 1=fees addition, 2=xSlot, 3=ySlot, 4=xSlot depositor, 5=ySlot depositor, 6=xSlot dFeesAcc, 7=ySlot dFeesAcc, 8=xFees subtraction, 9=yFees subtraction).

## Formulas
1. **Fee Share** (in `_calculateFeeShare`):
   - **Formula**:
     ```
     feesAcc = isX ? yFeesAcc : xFeesAcc
     contributedFees = feesAcc > dFeesAcc ? feesAcc - dFeesAcc : 0
     liquidityContribution = isX ? xLiquid : yLiquid
     liquidityContribution = liquidityContribution > 0 ? (allocation * 1e18) / liquidityContribution : 0
     feeShare = (contributedFees * liquidityContribution) / 1e18
     feeShare = feeShare > (isX ? yFees : xFees) ? (isX ? yFees : xFees) : feeShare
     ```
   - **Description**: Computes fee share based on slot `allocation` and liquidity contribution. Uses `xFeesAcc`/`yFeesAcc` (v0.1.30) for accurate fee tracking.

## External Functions
### depositNativeToken(address listingAddress, address depositor, uint256 amount, bool isTokenA)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `depositor`: Address receiving slot credit.
  - `amount`: ETH amount (matches `msg.value`).
  - `isTokenA`: True for token A, false for token B.
- **Behavior**: Deposits ETH to `CCLiquidityTemplate` for `depositor`, supports zero-balance initialization. Normalizes to 1e18 decimals, updates slot via `ccUpdate`.
- **Internal Call Flow**:
  - `_depositNative` (CCLiquidityPartial):
    - Calls `_validateDeposit`: Initializes `DepositContext`, fetches `liquidityAddressView`, `tokenA`, `tokenB`, `liquidityAmounts`.
    - Calls `_executeNativeTransfer`: Transfers ETH to `CCLiquidityTemplate`, performs pre/post balance checks, normalizes amount.
    - Calls `_updateDeposit`: Updates `xLiquiditySlots`/`yLiquiditySlots` and `xLiquid`/`yLiquid` via `ICCLiquidity.ccUpdate` (updateType=2 for xSlot, 3 for ySlot).
- **Balance Checks**: Pre/post balances in `_executeNativeTransfer`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, requires `msg.value == amount`.
- **Gas**: One `ccUpdate` call, one ETH transfer.
- **Interactions**: Calls `ICCListing` for `liquidityAddressView`, `tokenA`, `tokenB`; `ICCLiquidity` for `liquidityAmounts`, `getActiveXLiquiditySlots`, `getActiveYLiquiditySlots`, `ccUpdate`.
- **Events**: `DepositReceived`, `DepositFailed`, `TransferFailed`.

### depositToken(address listingAddress, address depositor, uint256 amount, bool isTokenA)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `depositor`: Address receiving slot credit.
  - `amount`: Token amount (denormalized).
  - `isTokenA`: True for token A, false for token B.
- **Behavior**: Deposits ERC20 tokens to `CCLiquidityTemplate` for `depositor`, supports zero-balance initialization. Normalizes to 1e18 decimals, updates slot via `ccUpdate`.
- **Internal Call Flow**:
  - `_depositToken` (CCLiquidityPartial):
    - Calls `_validateDeposit`: Initializes `DepositContext`, fetches `liquidityAddressView`, `tokenA`, `tokenB`, `liquidityAmounts`.
    - Calls `_executeTokenTransfer`: Transfers tokens to `CCLiquidityRouter`, then to `CCLiquidityTemplate`, checks allowance, performs pre/post balance checks, normalizes amount.
    - Calls `_updateDeposit`: Updates `xLiquiditySlots`/`yLiquiditySlots` and `xLiquid`/`yLiquid` via `ICCLiquidity.ccUpdate` (updateType=2 for xSlot, 3 for ySlot).
- **Balance Checks**: Pre/post balances and allowance in `_executeTokenTransfer`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, requires non-zero `tokenAddress`.
- **Gas**: Two `transfer` calls, one `ccUpdate` call.
- **Interactions**: Calls `ICCListing` for `liquidityAddressView`, `tokenA`, `tokenB`; `ICCLiquidity` for `liquidityAmounts`, `getActiveXLiquiditySlots`, `getActiveYLiquiditySlots`, `ccUpdate`; `IERC20` for `allowance`, `balanceOf`, `transfer`, `transferFrom`, `decimals`.
- **Events**: `DepositReceived`, `DepositFailed`, `TransferFailed`, `InsufficientAllowance`.

### withdraw(address listingAddress, uint256 outputAmount, uint256 compensationAmount, uint256 index, bool isX)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `outputAmount`: Primary amount to withdraw (normalized).
  - `compensationAmount`: Compensation amount (normalized).
  - `index`: Slot index.
  - `isX`: True for token A, false for token B.
- **Behavior**: Withdraws tokens from `CCLiquidityTemplate` for `msg.sender`, supports partial withdrawals with compensation. Validates ownership and allocation.
- **Internal Call Flow**:
  - `_prepWithdrawal` (CCLiquidityPartial): Validates `msg.sender` ownership, `allocation`, and total allocation requirement (primary + converted compensation) using `ICCListing.prices(0)`. Returns `PreparedWithdrawal`.
  - `_executeWithdrawal` (CCLiquidityPartial):
    - Calls `_fetchWithdrawalData`: Fetches `liquidityAddressView`, `tokenA`, `tokenB`, slot allocation, price.
    - Calls `_transferWithdrawalAmount`: Transfers primary and compensation amounts via `ICCLiquidity.transactNative` or `transactToken`, denormalizes amounts, tracks success, reverts if primary fails or compensation fails when `compensationAmount > 0`.
    - Calls `_updateWithdrawalAllocation`: Calculates total allocation deduction, updates slot via `ccUpdate`.
- **Balance Checks**: Implicit via `allocation` and `xLiquid`/`yLiquid` in `_prepWithdrawal`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: One `ccUpdate` call, up to two transfers.
- **Interactions**: Calls `ICCListing` for `liquidityAddressView`, `tokenA`, `tokenB`, `prices`; `ICCLiquidity` for `getXSlotView`, `getYSlotView`, `ccUpdate`, `transactNative`, `transactToken`; `IERC20` for `decimals`.
- **Events**: `ValidationFailed`, `CompensationCalculated`, `TransferSuccessful`, `WithdrawalFailed`.

### claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `liquidityIndex`: Slot index.
  - `isX`: True for token A, false for token B.
  - `volumeAmount`: Ignored (reserved).
- **Behavior**: Claims fees from `CCLiquidityTemplate` for `msg.sender` based on slot contribution.
- **Internal Call Flow**:
  - `_processFeeShare` (CCLiquidityPartial):
    - Calls `_validateFeeClaim`: Uses `_fetchLiquidityDetails` and `_fetchSlotDetails` to check slot ownership, liquidity, and fees via `ICCListing.liquidityAddressView`, `ICCLiquidity.liquidityDetailsView`, `getXSlotView` or `getYSlotView`. Returns `FeeClaimCore` and `FeeClaimDetails`.
    - Calls `_calculateFeeShare`: Computes `feeShare` using fee share formula with `xFeesAcc`/`yFeesAcc` (v0.1.30).
    - Calls `_executeFeeClaim`: Creates `UpdateType` array (updateType=9 for xFees subtraction, 8 for yFees subtraction, 6 for xSlot dFeesAcc, 7 for ySlot dFeesAcc), calls `ICCLiquidity.ccUpdate`, transfers fees via `transactToken` or `transactNative`, emits `FeesClaimed`.
- **Balance Checks**: `xLiquid`/`yLiquid`, `allocation`, and `xFees`/`yFees` in `_validateFeeClaim`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Two `ccUpdate` calls, one transfer.
- **Interactions**: Calls `ICCListing` for `liquidityAddressView`, `tokenA`, `tokenB`; `ICCLiquidity` for `liquidityDetailsView`, `getXSlotView`, `getYSlotView`, `ccUpdate`, `transactToken`, `transactNative`; `IERC20` for `decimals`.
- **Events**: `FeesClaimed`, `NoFeesToClaim`, `FeeValidationFailed`.

### changeDepositor(address listingAddress, bool isX, uint256 slotIndex, address newDepositor)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `isX`: True for token A, false for token B.
  - `slotIndex`: Slot index.
  - `newDepositor`: New slot owner address.
- **Behavior**: Reassigns slot ownership from `msg.sender` to `newDepositor`.
- **Internal Call Flow**:
  - `_changeDepositor` (CCLiquidityPartial):
    - Validates `msg.sender` and `newDepositor`, checks slot ownership and `allocation` via `getXSlotView` or `getYSlotView`.
    - Creates `UpdateType` (updateType=4 for xSlot, 5 for ySlot).
    - Calls `ICCLiquidity.ccUpdate` to update slot `depositor` and `userXIndex`/`userYIndex`.
    - Emits `SlotDepositorChanged`.
- **Balance Checks**: Implicit via `allocation` check.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Single `ccUpdate` call.
- **Interactions**: Calls `ICCListing` for `liquidityAddressView`; `ICCLiquidity` for `getXSlotView`, `getYSlotView`, `ccUpdate`.
- **Events**: `SlotDepositorChanged`.

## Internal Functions (CCLiquidityPartial)
- **_validateDeposit**: Initializes `DepositContext`, validates inputs, fetches liquidity amounts.
- **_executeTokenTransfer**: Handles ERC20 transfers with pre/post balance checks.
- **_executeNativeTransfer**: Handles ETH transfers with pre/post balance checks.
- **_depositToken**: Orchestrates token deposit via `_validateDeposit`, `_executeTokenTransfer`, `_updateDeposit`.
- **_depositNative**: Orchestrates ETH deposit via `_validateDeposit`, `_executeNativeTransfer`, `_updateDeposit`.
- **_updateDeposit**: Updates liquidity and slot via `ccUpdate`.
- **_prepWithdrawal**: Validates ownership, allocation, and total allocation requirement (primary + converted compensation) using `prices(0)`. Returns `PreparedWithdrawal`.
- **_fetchWithdrawalData**: Fetches `liquidityAddressView`, `tokenA`, `tokenB`, slot allocation, price.
- **_updateWithdrawalAllocation**: Calculates total allocation deduction including converted compensation, updates slot via `ccUpdate`.
- **_transferWithdrawalAmount**: Transfers primary and compensation amounts via `ICCLiquidity.transactNative` or `transactToken`, denormalizes amounts, tracks transfer success, reverts if primary fails or compensation fails when `compensationAmount > 0`, emits `TransferSuccessful`, `WithdrawalFailed`.
- **_fetchLiquidityDetails**: Fetches `xLiquid`, `yLiquid`, `xFees`, `yFees`, `xFeesAcc`, `yFeesAcc` from `liquidityDetailsView`.
- **_fetchSlotDetails**: Fetches slot `allocation` and `dFeesAcc`, validates ownership.
- **_validateFeeClaim**: Uses `_fetchLiquidityDetails` and `_fetchSlotDetails` to validate fee claim parameters, returns `FeeClaimCore` and `FeeClaimDetails`.
- **_calculateFeeShare**: Computes fee share using `xFeesAcc`/`yFeesAcc` (v0.1.30).
- **_executeFeeClaim**: Updates fees and `dFeesAcc`, transfers fees using `updateType` 8/9 for fee subtraction.
- **_processFeeShare**: Orchestrates fee claim via `_validateFeeClaim`, `_calculateFeeShare`, `_executeFeeClaim`.
- **_changeDepositor**: Updates slot depositor via `ccUpdate` (updateType=4 for xSlot, 5 for ySlot).
- **_uint2str**: Converts uint256 to string for error messages.

## Clarifications and Nuances
- **Token Flow**:
  - **Deposits**: `msg.sender` → `CCLiquidityRouter` → `CCLiquidityTemplate`. Slot assigned to `depositor`. Pre/post balance checks handle tax-on-transfer tokens.
  - **Withdrawals**: `CCLiquidityTemplate` → `msg.sender`. Partial withdrawals supported; `compensationAmount` converted using `prices(0)` for allocation validation, then both primary and compensation tokens transferred. Amounts denormalized to token decimals.
  - **Fees**: `CCLiquidityTemplate` → `msg.sender`, `feeShare` based on `allocation` and `xFeesAcc`/`yFeesAcc` (v0.1.30).
- **Price Integration**: 
  - Uses `ICCListing.prices(0)` which returns tokenB/tokenA price from Uniswap V2 pair balances, normalized to 1e18.
  - Conversion formulas properly handle the price ratio for cross-token allocation validation.
- **Decimal Handling**: Normalizes to 1e18 using `normalize`, denormalizes for transfers using `IERC20.decimals` or 18 for ETH.
- **Security**:
  - `nonReentrant` prevents reentrancy.
  - Try-catch ensures graceful degradation with detailed events.
  - No `virtual`/`override`, explicit casting, no inline assembly.
- **Gas Optimization**:
  - Structs (`DepositContext`, `FeeClaimCore`, `FeeClaimDetails`, `WithdrawalContext`) reduce stack usage.
  - Early validation minimizes gas on failures.
  - Helper functions (`_fetchLiquidityDetails`, `_fetchSlotDetails`, v0.1.32; `_executeWithdrawal` helpers, v0.1.25) optimize stack.
- **Error Handling**: Detailed errors (`InsufficientAllowance`, `WithdrawalFailed`) and events (`ValidationFailed`, `TransferSuccessful`) aid debugging.
- **Router Validation**: `CCLiquidityTemplate` validates `routers[msg.sender]`.
- **Pool Validation**: Supports deposits in any pool state.
- **Withdrawal Logic**: Simplified in v0.1.23+ to validate only ownership and total allocation requirement, with non-reverting behavior and comprehensive event emission.
- **Fee Subtraction**: Uses `updateType` 8/9 in `_executeFeeClaim` to subtract fees from `xFees`/`yFees` (v0.1.28).
- **Limitations**: Payouts handled in `CCOrderRouter`.
