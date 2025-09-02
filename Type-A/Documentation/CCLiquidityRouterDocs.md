# CCLiquidityRouter Contract Documentation

## Overview
The `CCLiquidityRouter` contract, written in Solidity (^0.8.2), facilitates liquidity management on a decentralized trading platform, handling deposits, withdrawals, fee claims, and depositor changes. It inherits `CCLiquidityPartial` (v0.1.12) and `CCMainPartial` (v0.1.4), interacting with `ICCListing` (v0.0.7), `ICCLiquidity` (v0.0.5), and `CCLiquidityTemplate` (v0.1.18). It uses `ReentrancyGuard` for security and `Ownable` via inheritance. State variables are inherited, accessed via view functions, with amounts normalized to 1e18 decimals.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.1.9 (Updated 2025-09-02)

**Changes**:
- v0.1.9: Updated to reflect `CCLiquidityRouter.sol` (v0.1.2), `CCLiquidityPartial.sol` (v0.1.12) with `updateType` 6/7 for fee claims, `CCLiquidityTemplate.sol` (v0.1.18) with `updateType` 6/7 support. Clarified internal call trees and compatibility.
- v0.1.8: Updated to reflect `CCLiquidityPartial.sol` (v0.1.9) with `_executeWithdrawal` refactored into helper functions (`_validateSlotOwnership`, `_checkLiquidity`, `_updateSlotAllocation`, `_transferPrimaryToken`, `_transferCompensationToken`) and `WithdrawalContext` struct.
- v0.1.7: Updated to reflect `CCLiquidityPartial.sol` (v0.1.8) with compensation logic in `_prepWithdrawal` and `_executeWithdrawal`. Removed `xPrepOut`, `yPrepOut`, `xExecuteOut`, `yExecuteOut`.
- v0.1.6: Updated to reflect `CCLiquidityPartial.sol` (v0.0.19) with partial withdrawal support in `_executeWithdrawal`.
- v0.1.5: Modified `_changeDepositor` to use `updateType` (4 for xSlot, 5 for ySlot) for depositor updates without affecting `xLiquid`/`yLiquid`.
- v0.1.4: Updated `_changeDepositor` to use `ccUpdate` directly, removing `changeSlotDepositor` dependency.
- v0.1.3: Relocated `xPrepOut`, `yPrepOut`, `xExecuteOut`, `yExecuteOut` to `CCLiquidityPartial.sol`, fixed `ParserError` in `xExecuteOut` by renaming `slot reflux` to `slotData`.
- v0.1.2: Added `depositor` parameter to `depositToken` and `depositNativeToken`, renamed `inputAmount` to `outputAmount` in `withdraw`.
- v0.1.1: Added `depositor` parameter for third-party deposits, renamed `inputAmount` to `amount`.
- v0.1.0: Bumped version.
- v0.0.25: Removed invalid try-catch in `depositNativeToken` and `depositToken`.
- v0.0.24: Fixed TypeError by removing `this` from `_depositNative` and `_depositToken`.
- v0.0.23: Removed `listingId` from `FeesClaimed`.

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
2. **Deficit and Compensation** (in `_prepWithdrawal`):
   - **xSlot Withdrawal**:
     ```
     withdrawal.amountA = amount
     if (xLiquid < amount) {
       shortfall = amount - xLiquid
       withdrawal.amountB = (shortfall * prices(0)) / 1e18
     }
     ```
   - **ySlot Withdrawal**:
     ```
     withdrawal.amountB = amount
     if (yLiquid < amount) {
       shortfall = amount - yLiquid
       withdrawal.amountA = (shortfall * 1e18) / prices(0)
     }
     ```
   - **Description**: Calculates primary token withdrawal (`amountA` for xSlot, `amountB` for ySlot). If liquidity (`xLiquid` or `yLiquid`) is insufficient, compensates with the opposite token using `ICCListing.prices(0)` for conversion.
   - **Used in**: `withdraw` via `_prepWithdrawal`.

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

### withdraw(address listingAddress, uint256 outputAmount, uint256 index, bool isX)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `outputAmount`: Normalized amount (1e18) to withdraw.
  - `index`: Slot index in `xLiquiditySlots` or `yLiquiditySlots`.
  - `isX`: True for token A, false for token B.
- **Behavior**: Withdraws liquidity from `CCLiquidityTemplate` for `msg.sender`, supports partial withdrawals and compensation if liquidity is insufficient.
- **Internal Call Flow**:
  - `_prepWithdrawal` (CCLiquidityPartial):
    - Validates `msg.sender` as slot owner via `getXSlotView` or `getYSlotView`.
    - Checks `xLiquid`/`yLiquid` and slot `allocation` via `liquidityDetailsView`, `getXSlotView`, `getYSlotView`.
    - Uses `ICCListing.prices(0)` to calculate compensation (`amountB` for `isX=true`, `amountA` for `isX=false`) if liquidity insufficient.
    - Sets `PreparedWithdrawal` with `amountA` or `amountB`.
  - `_executeWithdrawal` (CCLiquidityPartial):
    - Calls `_validateSlotOwnership`: Verifies slot ownership, updates `WithdrawalContext.currentAllocation`.
    - Calls `_checkLiquidity`: Validates `xLiquid` or `yLiquid` against `primaryAmount`, emits `WithdrawalFailed` on failure.
    - Calls `_updateSlotAllocation`: Updates slot allocation via `ICCLiquidity.ccUpdate`, reduces `currentAllocation`.
    - Calls `_transferPrimaryToken`: Transfers primary token (token A for xSlot, token B for ySlot) via `transactNative` or `transactToken`.
    - Calls `_transferCompensationToken`: Transfers compensation token (token B for xSlot, token A for ySlot) if needed, emits `CompensationCalculated`.
- **Balance Checks**: `xLiquid`/`yLiquid` and slot `allocation` in `_prepWithdrawal` and `_executeWithdrawal`, implicit checks in `transactToken`/`transactNative`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Single `ccUpdate` call, up to two transfers for compensation.
- **Interactions**: Calls `ICCListing` for `liquidityAddressView`, `tokenA`, `tokenB`, `prices`; `ICCLiquidity` for `liquidityDetailsView`, `getXSlotView`, `getYSlotView`, `ccUpdate`, `transactToken`, `transactNative`.
- **Events**: `WithdrawalFailed`, `CompensationCalculated`.

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
- **_validateDeposit**: Initializes `DepositContext`, validates inputs, fetches liquidity details.
- **_executeTokenTransfer**: Handles ERC20 transfers with pre/post balance checks.
- **_executeNativeTransfer**: Handles ETH transfers with pre/post balance checks.
- **_depositToken**: Orchestrates token deposit via `_validateDeposit`, `_executeTokenTransfer`, `_updateDeposit`.
- **_depositNative**: Orchestrates ETH deposit via `_validateDeposit`, `_executeNativeTransfer`, `_updateDeposit`.
- **_updateDeposit**: Updates liquidity and slot via `ccUpdate`.
- **_prepWithdrawal**: Prepares withdrawal with compensation calculation.
- **_validateSlotOwnership**: Verifies slot ownership, updates `WithdrawalContext`.
- **_checkLiquidity**: Ensures sufficient liquidity, emits `WithdrawalFailed` on failure.
- **_updateSlotAllocation**: Updates slot allocation via `ccUpdate`.
- **_transferPrimaryToken**: Transfers primary token.
- **_transferCompensationToken**: Transfers compensation token, emits `CompensationCalculated`.
- **_validateFeeClaim**: Validates fee claim parameters, creates `FeeClaimContext`.
- **_calculateFeeShare**: Computes fee share using formula.
- **_executeFeeClaim**: Updates fees and `dFeesAcc`, transfers fees.
- **_processFeeShare**: Orchestrates fee claim via `_validateFeeClaim`, `_calculateFeeShare`, `_executeFeeClaim`.

## Clarifications and Nuances
- **Token Flow**:
  - **Deposits**: `msg.sender` → `CCLiquidityRouter` → `CCLiquidityTemplate`. Slot assigned to `depositor`. Pre/post balance checks handle tax-on-transfer tokens.
  - **Withdrawals**: `CCLiquidityTemplate` → `msg.sender`. Partial withdrawals supported; compensation uses `prices(0)` for dual-token withdrawals if liquidity insufficient.
  - **Fees**: `CCLiquidityTemplate` → `msg.sender`, `feeShare` based on `allocation` and `liquid`.
- **Decimal Handling**: Normalizes to 1e18 using `normalize`, denormalizes for transfers using `IERC20.decimals` or 18 for ETH.
- **Security**:
  - `nonReentrant` prevents reentrancy.
  - Try-catch ensures graceful degradation with detailed events.
  - No `virtual`/`override`, explicit casting, no inline assembly.
- **Gas Optimization**:
  - Structs (`DepositContext`, `FeeClaimContext`, `WithdrawalContext`) reduce stack usage.
  - Early validation minimizes gas on failures.
- **Error Handling**: Detailed errors (`InsufficientAllowance`, `WithdrawalFailed`) and events aid debugging.
- **Router Validation**: `CCLiquidityTemplate` validates `routers[msg.sender]`.
- **Pool Validation**: Supports deposits in any pool state.
- **Limitations**: Payouts handled in `CCOrderRouter`.
