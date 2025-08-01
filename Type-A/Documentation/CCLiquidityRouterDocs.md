# CCLiquidityRouter Contract Documentation

## Overview
The `CCLiquidityRouter` contract, written in Solidity (^0.8.2), facilitates user interactions for liquidity management on a decentralized trading platform. It handles deposits, withdrawals, and fee claims, inheriting `CCLiquidityPartial` (v0.0.17) and `CCMainPartial` (v0.0.10). It interacts with `ICCListing` (v0.0.7), `ICCLiquidity` (v0.0.4), and `CCLiquidityTemplate` (v0.0.20) interfaces, using `ReentrancyGuard` for security and `Ownable` via inheritance. State variables are hidden, accessed via inherited view functions, with normalized amounts (1e18 decimals).

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.0.25 (Updated 2025-08-01)

**Inheritance Tree**: `CCLiquidityRouter` → `CCLiquidityPartial` → `CCMainPartial`

**Compatibility**: CCListingTemplate.sol (v0.0.10), CCMainPartial.sol (v0.0.10), CCLiquidityPartial.sol (v0.0.17), ICCLiquidity.sol (v0.0.4), ICCListing.sol (v0.0.7), CCLiquidityTemplate.sol (v0.0.20).

## Mappings
- None directly defined. Inherited from `CCLiquidityTemplate` via `CCLiquidityPartial`:
  - `routers`: Maps router addresses to authorization status.
  - `xLiquiditySlots`, `yLiquiditySlots`: Map indices to `Slot` structs.
  - `userIndex`: Maps user addresses to slot indices.

## Structs
- **DepositContext** (CCLiquidityPartial):
  - `listingAddress`: `ICCListing` address.
  - `depositor`: User address.
  - `inputAmount`: Input amount (denormalized).
  - `isTokenA`: True for token A, false for token B.
  - `tokenAddress`: Token address (or zero for ETH).
  - `liquidityAddr`: `ICCLiquidity` address.
  - `xAmount`, `yAmount`: Liquidity pool amounts.
  - `receivedAmount`: Actual received amount after transfers.
  - `normalizedAmount`: Normalized amount (1e18).
  - `index`: Slot index for `xLiquiditySlots` or `yLiquiditySlots`.
- **FeeClaimContext** (CCLiquidityPartial):
  - `listingAddress`: `ICCListing` address.
  - `depositor`: User address.
  - `liquidityIndex`: Slot index.
  - `isX`: True for token A, false for token B.
  - `liquidityAddr`: `ICCLiquidity` address.
  - `xBalance`: Listing volume balance.
  - `xLiquid`, `yLiquid`: Liquidity amounts from `liquidityDetail`.
  - `xFees`, `yFees`: Available fees from `liquidityDetail`.
  - `liquid`: Relevant liquidity (`xLiquid` or `yLiquid`).
  - `fees`: Relevant fees (`yFees` for xSlots, `xFees` for ySlots).
  - `allocation`: Slot allocation.
  - `dFeesAcc`: Cumulative fees at deposit/claim.
  - `transferToken`: Token to transfer (tokenB for xSlots, tokenA for ySlots).
  - `feeShare`: Calculated fee share (normalized).
- **ICCLiquidity.PreparedWithdrawal**:
  - `amountA`: Normalized token A amount to withdraw.
  - `amountB`: Normalized token B amount to withdraw.
- **ICCLiquidity.Slot**:
  - `depositor`: Slot owner address.
  - `recipient`: Unused (reserved).
  - `allocation`: Normalized liquidity contribution.
  - `dFeesAcc`: Cumulative fees at deposit/claim.
  - `timestamp`: Slot creation timestamp.
- **ICCLiquidity.UpdateType**:
  - `updateType`: Update type (0=balance, 1=fees, 2=xSlot, 3=ySlot).
  - `index`: Index (0=xFees/xLiquid, 1=yFees/yLiquid, or slot).
  - `value`: Normalized amount.
  - `addr`: Depositor address.
  - `recipient`: Unused (reserved).

## Formulas
1. **Fee Share** (in `_calculateFeeShare`):
   - **Formula**:
     ```
     contributedFees = fees - dFeesAcc
     liquidityContribution = (allocation * 1e18) / liquid
     feeShare = (contributedFees * liquidityContribution) / 1e18
     feeShare = feeShare > fees ? fees : feeShare
     ```
   - **Description**: Computes fee share based on accumulated fees since deposit/claim (`fees` is `yFees` for xSlots, `xFees` for ySlots), proportional to slot `allocation` relative to pool `liquid`, capped at available fees.
   - **Used in**: `claimFees` via `_processFeeShare`.

2. **Deficit and Compensation** (in `xPrepOut`, `yPrepOut` in `CCLiquidityTemplate`):
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
### depositNativeToken(address listingAddress, uint256 inputAmount, bool isTokenA)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `inputAmount`: ETH amount (18 decimals).
  - `isTokenA`: True for token A, false for token B.
- **Behavior**: Deposits ETH to `CCLiquidityTemplate` via `_depositNative`.
- **Internal Call Flow**:
  - `_validateDeposit`: Checks `isRouter`, `tokenAddress==0`, `liquidityAmounts` validity.
  - `_executeNativeTransfer`: Validates `msg.value==inputAmount`, transfers ETH to `CCLiquidityTemplate`, performs pre/post balance checks.
  - `_updateDeposit`: Creates `UpdateType`, calls `ICCLiquidity.update`, emits `DepositReceived` or `DepositFailed`.
- **Balance Checks**: `msg.value==inputAmount`, pre/post balance on `CCLiquidityTemplate` for `receivedAmount`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, payable.
- **Gas**: Low-level `call`, single `update` call.
- **Interactions**: Calls `ICCListing` for token and liquidity addresses, `ICCLiquidity` for updates, transfers ETH to `CCLiquidityTemplate`.

### depositToken(address listingAddress, uint256 inputAmount, bool isTokenA)
- **Parameters**: Same as `depositNativeToken`, for ERC20 tokens.
- **Behavior**: Deposits ERC20 tokens to `CCLiquidityTemplate` via `_depositToken`.
- **Internal Call Flow**:
  - `_validateDeposit`: Checks `tokenAddress!=0`, `isRouter`, `liquidityAmounts` validity.
  - `_executeTokenTransfer`: Checks allowance, calls `IERC20.transferFrom` to `CCLiquidityRouter`, then `IERC20.transfer` to `CCLiquidityTemplate`, performs pre/post balance checks.
  - `_updateDeposit`: Creates `UpdateType`, calls `ICCLiquidity.update`, emits `DepositReceived` or `DepositFailed`.
- **Balance Checks**: Pre/post balance on `CCLiquidityRouter` and `CCLiquidityTemplate`, allowance check.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Two `IERC20` transfers, single `update` call.
- **Interactions**: Calls `IERC20` for transfers, `ICCListing` for addresses, `ICCLiquidity` for updates.

### withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `inputAmount`: Normalized amount (1e18) to withdraw.
  - `index`: Slot index in `xLiquiditySlots` or `yLiquiditySlots`.
  - `isX`: True for token A, false for token B.
- **Behavior**: Withdraws liquidity from `CCLiquidityTemplate` via `_prepWithdrawal` and `_executeWithdrawal`.
- **Internal Call Flow**:
  - `_prepWithdrawal`: Validates `isRouter`, calls `ICCLiquidity.xPrepOut` or `yPrepOut` to calculate `PreparedWithdrawal`.
  - `_executeWithdrawal`: Calls `ICCLiquidity.xExecuteOut` or `yExecuteOut`, updates slots, transfers tokens/ETH via `transactToken` or `transactNative`.
- **Balance Checks**: Implicit in `CCLiquidityTemplate` via `xLiquid`/`yLiquid` checks.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Two external calls, multiple transfers if both tokens withdrawn.
- **Interactions**: Calls `ICCListing` for `liquidityAddr`, `ICCLiquidity` for preparation and execution, transfers from `CCLiquidityTemplate`.

### claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `liquidityIndex`: Slot index.
  - `isX`: True for token A, false for token B.
  - `volumeAmount`: Ignored (reserved).
- **Behavior**: Claims fees from `CCLiquidityTemplate` via `_processFeeShare`.
- **Internal Call Flow**:
  - `_validateFeeClaim`: Checks `isRouter`, `xBalance`, slot ownership, liquidity availability.
  - `_calculateFeeShare`: Computes `feeShare` using formula above.
  - `_executeFeeClaim`: Creates `UpdateType` array, calls `ICCLiquidity.update`, transfers fees via `transactToken` or `transactNative`, emits `FeesClaimed`.
- **Balance Checks**: `xBalance`, `xLiquid`/`yLiquid`, `allocation`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Stack-optimized via `FeeClaimContext`, two `update` calls, one transfer.
- **Interactions**: Calls `ICCListing` for balances and addresses, `ICCLiquidity` for updates and transfers.

### changeDepositor(address listingAddress, bool isX, uint256 slotIndex, address newDepositor)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `isX`: True for token A, false for token B.
  - `slotIndex`: Slot index.
  - `newDepositor`: New slot owner address.
- **Behavior**: Reassigns slot ownership via `_changeDepositor`.
- **Internal Call Flow**:
  - `_changeDepositor`: Validates `isRouter`, calls `ICCLiquidity.changeSlotDepositor`, updates `userIndex`.
- **Balance Checks**: Implicit slot validation in `CCLiquidityTemplate`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Single external call.
- **Interactions**: Calls `ICCListing` for `liquidityAddr`, `ICCLiquidity` for slot update.

## Clarifications and Nuances
- **Token Flow**:
  - **Deposits**: User → `CCLiquidityRouter` → `CCLiquidityTemplate`. Pre/post balance checks in `_executeTokenTransfer` and `_executeNativeTransfer` handle tax-on-transfer tokens, updating `receivedAmount`. Normalized amounts recorded via `update`.
  - **Withdrawals**: `CCLiquidityTemplate` → User. `PreparedWithdrawal` handles dual-token withdrawals if liquidity is insufficient, using `prices(0)` for conversion.
  - **Fees**: `CCLiquidityTemplate` → User, with `feeShare` calculated based on slot `allocation` and pool `liquid`.
- **Decimal Handling**: Normalizes to 1e18, denormalizes for transfers using `IERC20.decimals`.
- **Security**:
  - `nonReentrant` prevents reentrancy attacks.
  - Try-catch in `_executeTokenTransfer`, `_executeNativeTransfer`, `_updateDeposit`, `_prepWithdrawal`, `_executeWithdrawal`, `_executeFeeClaim` ensures graceful degradation with `TransferFailed`, `DepositFailed`, or detailed revert strings.
  - Explicit casting, no inline assembly, no reserved keywords, no unnecessary `virtual`/`override`.
- **Gas Optimization**: Uses `DepositContext` and `FeeClaimContext` to reduce stack usage, minimizes external calls.
- **Error Handling**: Reverts propagate through internal calls, with events (`DepositFailed`, `TransferFailed`, `FeesClaimed`) capturing failure reasons.
- **Limitations**: No direct `addFees` usage; payout functionality in `CCOrderRouter`.

## Additional Details
- **Events**: `TransferFailed`, `DepositFailed`, `DepositTokenFailed`, `DepositNativeFailed`, `DepositReceived`, `FeesClaimed`, `SlotDepositorChanged`.
- **Validation**: `onlyValidListing` (via `CCMainPartial`) uses `ICCAgent` for listing validation. `isRouter` ensures authorized access to `CCLiquidityTemplate`.
- **Token Handling**: Supports ETH (address(0)) and ERC20 tokens, with balance checks for tax-on-transfer tokens.
- **State Management**: `CCLiquidityTemplate` holds tokens/ETH and state (`liquidityDetail`, slots), while `CCLiquidityRouter` facilitates user interactions.
- **Changes from v0.0.21**:
  - v0.0.25: Removed invalid `try-catch` in `depositNativeToken` and `depositToken`.
  - v0.0.24: Removed `this` from `_depositNative`/`_depositToken` calls.
  - v0.0.23: Removed `listingId` from `FeeClaimContext` and `FeesClaimed`.
  - v0.0.22: Ensured tokens/ETH transfer to `CCLiquidityTemplate` with balance checks.
