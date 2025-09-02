# CCLiquidityRouter Contract Documentation

## Overview
The `CCLiquidityRouter` contract, written in Solidity (^0.8.2), facilitates liquidity management on a decentralized trading platform, handling deposits, withdrawals, fee claims, and depositor changes. It inherits `CCLiquidityPartial` (v0.1.8) and `CCMainPartial` (v0.1.4), interacting with `ICCListing` (v0.0.7), `ICCLiquidity` (v0.0.5), and `CCLiquidityTemplate` (v0.1.16). It uses `ReentrancyGuard` for security and `Ownable` via inheritance. State variables are inherited, accessed via view functions, with amounts normalized to 1e18 decimals.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.1.7 (Updated 2025-09-02)

**Changes**:
- v0.1.8: Updated to reflect `CCLiquidityPartial.sol` (v0.1.9) with `_executeWithdrawal` refactored into helper functions (`_validateSlotOwnership`, `_checkLiquidity`, `_updateSlotAllocation`, `_transferPrimaryToken`, `_transferCompensationToken`) and `WithdrawalContext` struct.  Updated compatibility to `CCLiquidityTemplate.sol` (v0.1.16).
- v0.1.7: Updated to reflect `CCLiquidityPartial.sol` (v0.1.8) with compensation logic fully in `_prepWithdrawal` and `_executeWithdrawal`. Removed `xPrepOut`, `yPrepOut`, `xExecuteOut`, `yExecuteOut`. Updated compatibility to `CCLiquidityTemplate.sol` (v0.1.16).
- v0.1.6: Updated to reflect `CCLiquidityPartial.sol` (v0.0.19) with partial withdrawal support in `_executeWithdrawal`. Updated compatibility to `CCLiquidityTemplate.sol` (v0.1.16).
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

**Compatibility**: CCListingTemplate.sol (v0.3.6), CCMainPartial.sol (v0.1.4), CCLiquidityPartial.sol (v0.1.8), ICCLiquidity.sol (v0.0.5), ICCListing.sol (v0.0.7), CCLiquidityTemplate.sol (v0.1.16).

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
  - `hasExistingSlot`: True if depositor has an existing slot (unused in v0.1.8).
  - `existingAllocation`: Current slot allocation (unused in v0.1.8).
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
  - `updateType`: Update type (0=balance, 1=fees, 2=xSlot, 3=ySlot, 4=xSlot depositor, 5=ySlot depositor).
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
   - **Description**: Calculates withdrawal amounts, compensating shortfalls using `ICCListing.prices(0)` (price of token B in token A, 1e18 precision), capped by available liquidity (`xLiquid` or `yLiquid`).
   - **Used in**: `withdraw` via `_prepWithdrawal`.

## External Functions
### depositNativeToken(address listingAddress, address depositor, uint256 amount, bool isTokenA)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address, validated by `onlyValidListing`.
  - `depositor`: Address receiving liquidity slot credit.
  - `amount`: ETH amount (denormalized, 18 decimals).
  - `isTokenA`: True for token A, false for token B.
- **Behavior**: Deposits ETH to `CCLiquidityTemplate` for `depositor`, supports zero-balance initialization.
- **Internal Call Flow**:
  - `_depositNative` (CCLiquidityPartial):
    - Calls `_validateDeposit`: Validates inputs, retrieves `tokenAddress()`, `liquidityAddr`, `xAmount`, `yAmount`, sets `index` via `activeXLiquiditySlotsView` or `activeYLiquiditySlotsView`.
    - Calls `_executeNativeTransfer`: Transfers ETH from `msg.sender` to `CCLiquidityTemplate`, performs pre/post balance checks, normalizes amount.
    - Calls `_updateDeposit`: Creates `UpdateType` (updateType=2 for xSlot, 3 for ySlot), calls `ICCLiquidity.ccUpdate` with `depositor`, emits `DepositReceived` or `DepositFailed`.
- **Balance Checks**: Pre/post balance on `CCLiquidityTemplate`, `msg.value` check in `_executeNativeTransfer`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Single transfer, single `ccUpdate` call.
- **Interactions**: Calls `ICCListing` for `tokenA`, `tokenB`, `liquidityAddressView`; `ICCLiquidity` for `liquidityAmounts`, `activeXLiquiditySlotsView`, `activeYLiquiditySlotsView`, `ccUpdate`.
- **Events**: `DepositReceived`, `DepositFailed`, `TransferFailed`.

### depositToken(address listingAddress, address depositor, uint256 amount, bool isTokenA)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `depositor`: Address receiving slot credit.
  - `amount`: Token amount (denormalized).
  - `isTokenA`: True for token A, false for token B.
- **Behavior**: Deposits ERC20 tokens to `CCLiquidityTemplate` for `depositor`, supports zero-balance initialization.
- **Internal Call Flow**:
  - `_depositToken` (CCLiquidityPartial):
    - Calls `_validateDeposit`: Validates inputs, retrieves `tokenAddress`, `liquidityAddr`, `xAmount`, `yAmount`, sets `index`.
    - Calls `_executeTokenTransfer`: Checks allowance for `msg.sender`, calls `IERC20.transferFrom(msg.sender, address(this), amount)`, then `IERC20.transfer` to `CCLiquidityTemplate`, performs pre/post balance checks.
    - Calls `_updateDeposit`: Creates `UpdateType`, calls `ICCLiquidity.ccUpdate`, emits `DepositReceived` or `DepositFailed`.
- **Balance Checks**: Pre/post balance on `CCLiquidityRouter` and `CCLiquidityTemplate`, allowance check via `IERC20.allowance`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Two `IERC20` transfers, single `ccUpdate` call.
- **Interactions**: Calls `IERC20` for `allowance`, `transferFrom`, `transfer`, `decimals`; `ICCListing` for `tokenA`, `tokenB`, `liquidityAddressView`; `ICCLiquidity` for `liquidityAmounts`, `activeXLiquiditySlotsView`, `activeYLiquiditySlotsView`, `ccUpdate`.
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
    - Checks `xLiquid`/`yLiquid` and slot `allocation` via `liquidityDetail`, `getXSlotView`, `getYSlotView`.
    - Uses `ICCListing.prices(0)` to calculate compensation (`amountB` for `isX=true`, `amountA` for `isX=false`) if liquidity insufficient.
    - Sets `PreparedWithdrawal` with `amountA` or `amountB`.
  - `_executeWithdrawal` (CCLiquidityPartial):
    - Validates `xLiquid`/`yLiquid` and slot `allocation`.
    - Creates `UpdateType` (updateType=2 for xSlot, 3 for ySlot) to reduce slot allocation.
    - Calls `ICCLiquidity.ccUpdate` to update `xLiquid`/`yLiquid` and slot.
    - Transfers primary and compensation tokens/ETH to `msg.sender` via `ICCLiquidity.transactToken` or `transactNative`.
- **Balance Checks**: `xLiquid`/`yLiquid` and slot `allocation` in `_prepWithdrawal` and `_executeWithdrawal`, implicit checks in `transactToken`/`transactNative`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Single `ccUpdate` call, up to two transfers for compensation.
- **Interactions**: Calls `ICCListing` for `liquidityAddressView`, `tokenA`, `tokenB`, `prices`; `ICCLiquidity` for `liquidityDetail`, `getXSlotView`, `getYSlotView`, `ccUpdate`, `transactToken`, `transactNative`.
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
    - Calls `_validateFeeClaim`: Checks `xBalance`, slot ownership, liquidity via `ICCListing.volumeBalances`, `ICCLiquidity.liquidityDetailsView`, `getXSlotView` or `getYSlotView`.
    - Calls `_calculateFeeShare`: Computes `feeShare` using fee share formula.
    - Calls `_executeFeeClaim`: Creates `UpdateType` array (updateType=1 for fees, 2/3 for slot), calls `ICCLiquidity.ccUpdate`, transfers fees via `transactToken` or `transactNative`, emits `FeesClaimed`.
- **Balance Checks**: `xBalance`, `xLiquid`/`yLiquid`, `allocation` in `_validateFeeClaim`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Two `ccUpdate` calls, one transfer.
- **Interactions**: Calls `ICCListing` for `volumeBalances`, `tokenA`, `tokenB`, `liquidityAddressView`; `ICCLiquidity` for `liquidityDetailsView`, `getXSlotView`, `getYSlotView`, `ccUpdate`, `transactToken`, `transactNative`; `IERC20` for `decimals`.
- **Events**: `FeesClaimed`, unnamed revert errors.

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
- **Events**: `SlotDepositorChanged`, unnamed revert errors.

## (Some) Internal Functions
- **_validateSlotOwnership** (CCLiquidityPartial, private, view): Validates slot ownership and allocation, updates `WithdrawalContext.currentAllocation`.
- **_checkLiquidity** (CCLiquidityPartial, internal): Checks `xLiquid` or `yLiquid` against `primaryAmount`, emits `WithdrawalFailed` on failure.
- **_updateSlotAllocation** (CCLiquidityPartial, private): Updates slot allocation via `ICCLiquidity.ccUpdate`, reduces `currentAllocation` by `primaryAmount`.
- **_transferPrimaryToken** (CCLiquidityPartial, private): Transfers `primaryAmount` of primary token (token A for xSlot, token B for ySlot) via `transactNative` or `transactToken`.
- **_transferCompensationToken** (CCLiquidityPartial, private): Transfers `compensationAmount` of compensation token (token B for xSlot, token A for ySlot), emits `CompensationCalculated`.

## Clarifications and Nuances
- **Token Flow**:
  - **Deposits**: `msg.sender` → `CCLiquidityRouter` → `CCLiquidityTemplate`. Slot assigned to `depositor`. Pre/post balance checks handle tax-on-transfer tokens.
  - **Withdrawals**: `CCLiquidityTemplate` → `msg.sender`. Partial withdrawals supported; compensation uses `prices(0)` for dual-token withdrawals if liquidity insufficient.
  - **Fees**: `CCLiquidityTemplate` → `msg.sender`, `feeShare` based on `allocation` and `liquid`.
- **Decimal Handling**: Normalizes to 1e18 using `normalize`, denormalizes for transfers using `IERC20.decimals` or 18 for ETH.
- **Security**:
  - `nonReentrant` prevents reentrancy.
  - Try-catch ensures graceful degradation with `TransferFailed`, `DepositFailed`, `WithdrawalFailed`, `FeesClaimed`, `SlotDepositorChanged`.
  - No `virtual`/`override`, explicit casting, no inline assembly, no reserved keywords.
- **Gas Optimization**:
  - `DepositContext`, `FeeClaimContext` reduce stack usage. `WithdrawalContext` and helper functions reduce stack usage in `_executeWithdrawal`.
  - Early validation minimizes gas on failures.
- **Error Handling**: Detailed errors (`InsufficientAllowance`, `WithdrawalFailed`) and events aid debugging. `WithdrawalFailed` emission in `_checkLiquidity` necessitated `internal` visibility.
- **Router Validation**: `CCLiquidityTemplate` validates `routers[msg.sender]` for state-changing functions.
- **Pool Validation**: Supports deposits in any pool state.
- **Limitations**: Payouts handled in `CCOrderRouter`.
- **Call Tree**:
  - `_depositToken`/`_depositNative`: `_validateDeposit` → `_executeTokenTransfer`/`_executeNativeTransfer` → `_updateDeposit`.
  - `withdraw`: `_prepWithdrawal` → `_executeWithdrawal`.
  - `claimFees`: `_validateFeeClaim` → `_calculateFeeShare` → `_executeFeeClaim`.
  - `changeDepositor`: Single `_changeDepositor` call.