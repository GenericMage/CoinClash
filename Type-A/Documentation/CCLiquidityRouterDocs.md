# CCLiquidityRouter Contract Documentation

## Overview
The `CCLiquidityRouter` contract, written in Solidity (^0.8.2), facilitates liquidity management on a decentralized trading platform, handling deposits, withdrawals, fee claims, and depositor changes. It inherits `CCLiquidityPartial` (v0.1.26) and `CCMainPartial` (v0.0.10), interacting with `ICCListing` (v0.0.7), `ICCLiquidity` (v0.0.4), and `CCLiquidityTemplate` (v0.0.20). It uses `ReentrancyGuard` for security and `Ownable` via inheritance. State variables are inherited, accessed via view functions, with amounts normalized to 1e18 decimals.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.1.12 (Updated 2025-09-09)

**Changes**:
- v0.1.13: Updated to reflect `CCLiquidityPartial.sol` (v0.1.27) with `_transferWithdrawalAmount` modified to revert if compensation transfer fails when `compensationAmount > 0`, ensuring slot allocation updates only after successful transfers.
- v0.1.12: Updated to reflect `CCLiquidityPartial.sol` (v0.1.26) with `_executeWithdrawal` reordered to call `_transferWithdrawalAmount` before `_updateWithdrawalAllocation`.
- v0.1.11: Updated to reflect `CCLiquidityPartial.sol` (v0.1.25) with fixed `listingContract` declarations in `_fetchWithdrawalData` and `_updateWithdrawalAllocation`.
- v0.1.10: Updated to reflect `CCLiquidityPartial.sol` (v0.1.24) with `_executeWithdrawal` refactored into `_fetchWithdrawalData`, `_updateWithdrawalAllocation`, `_transferWithdrawalAmount` to fix stack too deep error. Extended `WithdrawalContext` with `totalAllocationDeduct` and `price`.
- v0.1.9: Updated to reflect `CCLiquidityPartial.sol` (v0.1.23) with `_prepWithdrawal` accepting `compensationAmount`, minimal checks (ownership, allocation), non-reverting behavior, and event emission (`ValidationFailed`, `WithdrawalFailed`, `TransferSuccessful`).
- v0.1.8: Updated to reflect `CCLiquidityRouter.sol` (v0.1.3) with `withdraw` accepting `compensationAmount`.

**Inheritance Tree**: `CCLiquidityRouter` → `CCLiquidityPartial` → `CCMainPartial`

**Compatibility**: CCListingTemplate.sol (v0.3.6), CCMainPartial.sol (v0.1.4), CCLiquidityPartial.sol (v0.1.12), ICCLiquidity.sol (v0.0.5), ICCListing.sol (v0.0.7), CCLiquidityTemplate.sol (v0.1.18).

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
  - `hasExistingSlot`: True if depositor has an existing slot (unused in v0.1.12).
  - `existingAllocation`: Current slot allocation (unused in v0.1.12).
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
  - `xBalance`: Listing volume balance (unused, retained for compatibility).
  - `xLiquid`, `yLiquid`: Liquidity amounts from `liquidityDetailsView`.
  - `xFees`, `yFees`: Available fees from `liquidityDetailsView`.
  - `liquid`: Relevant liquidity (`xLiquid` or `yLiquid`).
  - `fees`: Relevant fees (`yFees` for xSlots, `xFees` for ySlots).
  - `allocation`: Slot allocation.
  - `dFeesAcc`: Cumulative fees at deposit/claim.
  - `transferToken`: Token to transfer (tokenB for xSlots, tokenA for ySlots).
  - `feeShare`: Calculated fee share (normalized).
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
  - `updateType`: Update type (0=balance, 1=fees, 2=xSlot, 3=ySlot, 4=xSlot depositor, 5=ySlot depositor, 6=xSlot dFeesAcc, 7=ySlot dFeesAcc).
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

2. **Compensation Conversion** (in `_prepWithdrawal` and `_updateWithdrawalAllocation`):
   - **Price Source**: Uses `ICCListing.prices(0)` which returns tokenB/tokenA ratio normalized to 1e18.
   - **xSlot Compensation Conversion** (tokenB → tokenA equivalent):
     ```
     convertedCompensation = (compensationAmount * 1e18) / price
     ```
   - **ySlot Compensation Conversion** (tokenA → tokenB equivalent):
     ```
     convertedCompensation = (compensationAmount * price) / 1e18
     ```
   - **Description**: Converts compensation amount to primary token equivalent for allocation validation. For xSlots, converts tokenB compensation to tokenA equivalent by dividing by price. For ySlots, converts tokenA compensation to tokenB equivalent by multiplying by price.
   - **Used in**: `withdraw` via `_prepWithdrawal` and `_updateWithdrawalAllocation`.

3. **Total Allocation Deduction**:
   - **Formula**:
     ```
     totalAllocationDeduct = primaryAmount + convertedCompensation
     ```
   - **Description**: Total allocation to deduct from slot, combining primary withdrawal and converted compensation amount.
   - **Used in**: `_updateWithdrawalAllocation` for slot allocation updates.

## External Functions and Internal Call Trees
### depositNativeToken(address listingAddress, address depositor, uint256 amount, bool isTokenA)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `depositor`: Address receiving slot credit.
  - `amount`: ETH amount (denormalized).
  - `isTokenA`: True for token A, false for token B.
- **Behavior**: Deposits ETH to `CCLiquidityTemplate` for `depositor`, assigns a new slot in `xLiquiditySlots` or `yLiquiditySlots`.
- **Internal Call Flow**:
  - `_depositNative` (CCLiquidityPartial):
    - Calls `_validateDeposit`: Verifies `listingAddress`, fetches `tokenA`/`tokenB`, `liquidityAddressView`, and `liquidityAmounts` from `ICCListing` and `ICCLiquidity`. Creates `DepositContext`.
    - Calls `_executeNativeTransfer`: Checks `msg.value == amount`, transfers ETH to `liquidityAddr`, performs pre/post balance checks, normalizes to 1e18.
    - Calls `_updateDeposit`: Creates `UpdateType` (updateType=2 for xSlot, 3 for ySlot), calls `ICCLiquidity.ccUpdate` to update `xLiquid`/`yLiquid`, `xLiquiditySlots`/`yLiquiditySlots`, `userXIndex`/`userYIndex`. Emits `DepositReceived`.
- **Balance Checks**: Pre/post balance checks in `_executeNativeTransfer` ensure correct ETH receipt.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Single `ccUpdate` call, one ETH transfer.
- **Interactions**: Calls `ICCListing` for `tokenA`, `tokenB`, `liquidityAddressView`; `ICCLiquidity` for `liquidityAmounts`, `ccUpdate`, `transactNative`; `IERC20` for `balanceOf`.
- **Events**: `DepositReceived`, `DepositFailed`, `TransferFailed`.

### depositToken(address listingAddress, address depositor, uint256 amount, bool isTokenA)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `depositor`: Address receiving slot credit.
  - `amount`: Token amount (denormalized).
  - `isTokenA`: True for token A, false for token B.
- **Behavior**: Deposits ERC20 tokens to `CCLiquidityTemplate` for `depositor`, assigns a new slot.
- **Internal Call Flow**:
  - `_depositToken` (CCLiquidityPartial):
    - Calls `_validateDeposit`: Same as above.
    - Calls `_executeTokenTransfer`: Checks `IERC20.allowance`, transfers tokens from `msg.sender` to `this`, then to `liquidityAddr`. Performs pre/post balance checks, normalizes to 1e18.
    - Calls `_updateDeposit`: Same as above.
- **Balance Checks**: Pre/post balance checks in `_executeTokenTransfer` handle tax-on-transfer tokens.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Single `ccUpdate` call, two ERC20 transfers.
- **Interactions**: Calls `ICCListing` for `tokenA`, `tokenB`, `liquidityAddressView`; `ICCLiquidity` for `liquidityAmounts`, `ccUpdate`, `transactToken`; `IERC20` for `allowance`, `transferFrom`, `transfer`, `balanceOf`, `decimals`.
- **Events**: `DepositReceived`, `DepositFailed`, `TransferFailed`, `InsufficientAllowance`.

### withdraw(address listingAddress, uint256 outputAmount, uint256 compensationAmount, uint256 index, bool isX)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `outputAmount`: Primary amount to withdraw (normalized to 1e18).
  - `compensationAmount`: Optional compensation amount in opposite token (normalized to 1e18).
  - `index`: Slot index.
  - `isX`: True for xSlot (tokenA), false for ySlot (tokenB).
- **Behavior**: Withdraws tokens from `CCLiquidityTemplate` for `msg.sender`, using `compensationAmount` for dual-token withdrawals. Validates ownership and total allocation (primary + converted compensation), non-reverting with events.
- **Internal Call Flow**:
  - `_prepWithdrawal` (CCLiquidityPartial): Validates `msg.sender` as slot owner, checks total allocation against `outputAmount + converted compensationAmount` using `ICCListing.prices(0)` for conversion. Returns `PreparedWithdrawal` with `amountA` and `amountB`. Emits `ValidationFailed` on failure.
  - `_executeWithdrawal` (CCLiquidityPartial):
    - `_fetchWithdrawalData`: Fetches `liquidityAddressView`, `tokenA`, `tokenB`, slot allocation, and price. Emits `ValidationFailed` on failure.
    - Calls `_transferWithdrawalAmount`: Attempts `transactNative` or `transactToken` for primary and compensation amounts, tracks success, reverts if primary fails or compensation fails when `compensationAmount > 0`, emits `TransferSuccessful` or `WithdrawalFailed`.
        - `_updateWithdrawalAllocation`: Calculates `totalAllocationDeduct` (primary + converted compensation), updates slot via `ccUpdate` (updateType=2 for xSlot, 3 for ySlot). Emits `CompensationCalculated`, `WithdrawalFailed` on failure.
- **Compensation Logic**: For xSlots, primary is tokenA, compensation is tokenB. For ySlots, primary is tokenB, compensation is tokenA. Conversion uses price from listing template.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: One `ccUpdate`, up to two transfers.
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
    - Calls `_validateFeeClaim`: Checks slot ownership, liquidity, and fees via `ICCListing.liquidityAddressView`, `ICCLiquidity.liquidityDetailsView`, `getXSlotView` or `getYSlotView`. Creates `FeeClaimContext`.
    - Calls `_calculateFeeShare`: Computes `feeShare` using fee share formula.
    - Calls `_executeFeeClaim`: Creates `UpdateType` array (updateType=1 for fees, 6 for xSlot dFeesAcc, 7 for ySlot dFeesAcc), calls `ICCLiquidity.ccUpdate`, transfers fees via `transactToken` or `transactNative`, emits `FeesClaimed`.
- **Balance Checks**: `xLiquid`/`yLiquid`, `allocation`, and `fees` in `_validateFeeClaim`.
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
- **_updateWithdrawalAllocation**: Calculates total allocation deduction including converted compensation, updates slot allocation via `ccUpdate`.
- **_transferWithdrawalAmount**: Transfers primary and compensation amounts via `ICCLiquidity.transactNative` or `transactToken`, denormalizes amounts, tracks transfer success, reverts if primary fails or compensation fails when `compensationAmount > 0`, emits `TransferSuccessful`, `WithdrawalFailed`. Used by `_executeWithdrawal`.
- **_validateFeeClaim**: Validates fee claim parameters, creates `FeeClaimContext`.
- **_calculateFeeShare**: Computes fee share using formula.
- **_executeFeeClaim**: Updates fees and `dFeesAcc`, transfers fees.
- **_processFeeShare**: Orchestrates fee claim via `_validateFeeClaim`, `_calculateFeeShare`, `_executeFeeClaim`.
- **_changeDepositor**: Updates slot depositor via `ccUpdate` (updateType=4 for xSlot, 5 for ySlot).
- **_uint2str**: Converts uint256 to string for error messages.

## Clarifications and Nuances
- **Token Flow**:
  - **Deposits**: `msg.sender` → `CCLiquidityRouter` → `CCLiquidityTemplate`. Slot assigned to `depositor`. Pre/post balance checks handle tax-on-transfer tokens.
  - **Withdrawals**: `CCLiquidityTemplate` → `msg.sender`. Partial withdrawals supported; `compensationAmount` converted using `prices(0)` for allocation validation, then both primary and compensation tokens transferred. Amounts denormalized to token decimals.
  - **Fees**: `CCLiquidityTemplate` → `msg.sender`, `feeShare` based on `allocation` and `liquid`.
- **Price Integration**: 
  - Uses `ICCListing.prices(0)` which returns tokenB/tokenA price from Uniswap V2 pair balances, normalized to 1e18.
  - Conversion formulas properly handle the price ratio for cross-token allocation validation.
- **Decimal Handling**: Normalizes to 1e18 using `normalize`, denormalizes for transfers using `IERC20.decimals` or 18 for ETH.
- **Security**:
  - `nonReentrant` prevents reentrancy.
  - Try-catch ensures graceful degradation with detailed events.
  - No `virtual`/`override`, explicit casting, no inline assembly.
- **Gas Optimization**:
  - Structs (`DepositContext`, `FeeClaimContext`, `WithdrawalContext`) reduce stack usage.
  - Early validation minimizes gas on failures.
  - Helper functions in `_executeWithdrawal` (v0.1.24) optimize stack.
- **Error Handling**: Detailed errors (`InsufficientAllowance`, `WithdrawalFailed`) and events (`ValidationFailed`, `TransferSuccessful`) aid debugging.
- **Router Validation**: `CCLiquidityTemplate` validates `routers[msg.sender]`.
- **Pool Validation**: Supports deposits in any pool state.
- **Withdrawal Logic**: Simplified in v0.1.23+ to validate only ownership and total allocation requirement, with non-reverting behavior and comprehensive event emission.
- **Limitations**: Payouts handled in `CCOrderRouter`.