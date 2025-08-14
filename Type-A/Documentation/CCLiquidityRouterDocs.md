# CCLiquidityRouter Contract Documentation

## Overview
The `CCLiquidityRouter` contract, written in Solidity (^0.8.2), facilitates liquidity management on a decentralized trading platform, handling deposits, withdrawals, fee claims, and depositor changes. It inherits `CCLiquidityPartial` (v0.0.24) and `CCMainPartial` (v0.0.14), interacting with `ICCListing` (v0.0.7), `ICCLiquidity` (v0.0.5), and `CCLiquidityTemplate` (v0.1.1). It uses `ReentrancyGuard` for security and `Ownable` via inheritance. State variables are inherited, accessed via view functions, with amounts normalized to 1e18 decimals.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.0.30 (Updated 2025-08-14)

**Inheritance Tree**: `CCLiquidityRouter` → `CCLiquidityPartial` → `CCMainPartial`

**Compatibility**: CCListingTemplate.sol (v0.1.0), CCMainPartial.sol (v0.0.14), CCLiquidityPartial.sol (v0.0.24), ICCLiquidity.sol (v0.0.5), ICCListing.sol (v0.0.7), CCLiquidityTemplate.sol (v0.1.1).

## Mappings
- **depositStates** (private, `CCLiquidityPartial.sol`): Maps `msg.sender` to `DepositState` for temporary deposit state management.
- Inherited from `CCLiquidityTemplate` via `CCLiquidityPartial`:
  - `routers`: Maps router addresses to authorization status.
  - `xLiquiditySlots`, `yLiquiditySlots`: Map indices to `Slot` structs.
  - `userXIndex`, `userYIndex`: Map user addresses to slot indices.

## Structs
- **DepositState** (CCLiquidityPartial, private):
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
  - `hasExistingSlot`: True if depositor has an existing slot (unused in v0.0.24).
  - `existingAllocation`: Current slot allocation (unused in v0.0.24).
- **DepositContext** (CCLiquidityPartial):
  - Fields identical to `DepositState` (excluding `hasExistingSlot`, `existingAllocation`).
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
   - **Used in**: `claimFees`, `queryDepositorFees` via `_processFeeShare`.

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
### depositNativeToken(address listingAddress, address depositor, uint256 inputAmount, bool isTokenA)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address, validated by `onlyValidListing`.
  - `depositor`: Address receiving liquidity slot credit.
  - `inputAmount`: ETH amount (18 decimals).
  - `isTokenA`: True for token A, false for token B.
- **Behavior**: Deposits ETH to `CCLiquidityTemplate` via `_depositNative`. Creates a new slot using `nextXSlotIDView` or `nextYSlotIDView`, skipping existing slot checks and fee claims (v0.0.24).
- **Internal Call Flow**:
  - `_validateInputs`: Checks for zero `listingAddress`, `depositor`, `inputAmount`.
  - `_fetchListingData`: Retrieves `tokenAddress`, `liquidityAddr`, validates `tokenAddress==0` for ETH, fetches `xAmount`, `yAmount`, sets `index` via `nextXSlotIDView`/`nextYSlotIDView`.
  - `_executeNativeTransfer`: Validates `msg.value==inputAmount`, transfers ETH to `CCLiquidityTemplate`, performs pre/post balance checks.
  - `_updateSlot`: Creates `UpdateType`, calls `ICCLiquidity.update`, emits `DepositReceived` or `DepositFailed`.
- **Balance Checks**: `msg.value==inputAmount`, pre/post balance on `CCLiquidityTemplate` for `receivedAmount`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, payable.
- **Gas**: Low-level `call`, single `update` call.
- **Interactions**: Calls `ICCListing` for `tokenA`, `tokenB`, `liquidityAddressView`; `ICCLiquidity` for `liquidityAmounts`, `nextXSlotIDView`, `nextYSlotIDView`, `update`; transfers ETH to `CCLiquidityTemplate`.

### depositToken(address listingAddress, address depositor, uint256 inputAmount, bool isTokenA)
- **Parameters**: Same as `depositNativeToken`, for ERC20 tokens.
- **Behavior**: Deposits ERC20 tokens to `CCLiquidityTemplate` via `_depositToken`, creating a new slot (v0.0.24).
- **Internal Call Flow**:
  - `_validateInputs`: Checks for zero `listingAddress`, `depositor`, `inputAmount`.
  - `_fetchListingData`: Retrieves `tokenAddress`, `liquidityAddr`, validates `tokenAddress!=0`, fetches `xAmount`, `yAmount`, sets `index` via `nextXSlotIDView`/`nextYSlotIDView`.
  - `_executeTokenTransfer`: Checks allowance, calls `IERC20.transferFrom` to `CCLiquidityRouter`, then `IERC20.transfer` to `CCLiquidityTemplate`, performs pre/post balance checks.
  - `_updateSlot`: Creates `UpdateType`, calls `ICCLiquidity.update`, emits `DepositReceived` or `DepositFailed`.
- **Balance Checks**: Pre/post balance on `CCLiquidityRouter` and `CCLiquidityTemplate`, allowance check via `IERC20.allowance`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Two `IERC20` transfers, single `update` call.
- **Interactions**: Calls `IERC20` for `allowance`, `transferFrom`, `transfer`, `decimals`; `ICCListing` for `tokenA`, `tokenB`, `liquidityAddressView`; `ICCLiquidity` for `liquidityAmounts`, `nextXSlotIDView`, `nextYSlotIDView`, `update`.

### withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `inputAmount`: Normalized amount (1e18) to withdraw.
  - `index`: Slot index in `xLiquiditySlots` or `yLiquiditySlots`.
  - `isX`: True for token A, false for token B.
- **Behavior**: Withdraws liquidity from `CCLiquidityTemplate` via `_prepWithdrawal` and `_executeWithdrawal`.
- **Internal Call Flow**:
  - `_prepWithdrawal`: Validates `depositor`, calls `ICCLiquidity.xPrepOut` or `yPrepOut` for `PreparedWithdrawal`.
  - `_executeWithdrawal`: Calls `ICCLiquidity.xExecuteOut` or `yExecuteOut`, updates slots, transfers tokens/ETH.
- **Balance Checks**: Implicit in `CCLiquidityTemplate` via `xLiquid`/`yLiquid`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Two external calls, multiple transfers if both tokens withdrawn.
- **Interactions**: Calls `ICCListing` for `liquidityAddressView`; `ICCLiquidity` for `xPrepOut`, `yPrepOut`, `xExecuteOut`, `yExecuteOut`; transfers from `CCLiquidityTemplate`.

### claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `liquidityIndex`: Slot index.
  - `isX`: True for token A, false for token B.
  - `volumeAmount`: Ignored (reserved).
- **Behavior**: Claims fees from `CCLiquidityTemplate` via `_processFeeShare`.
- **Internal Call Flow**:
  - `_validateFeeClaim`: Checks `xBalance`, slot ownership, liquidity availability.
  - `_calculateFeeShare`: Computes `feeShare` using formula above.
  - `_executeFeeClaim`: Creates `UpdateType` array, calls `ICCLiquidity.update`, transfers fees, emits `FeesClaimed`.
- **Balance Checks**: `xBalance`, `xLiquid`/`yLiquid`, `allocation`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Two `update` calls, one transfer.
- **Interactions**: Calls `ICCListing` for `volumeBalances`, `tokenA`, `tokenB`, `liquidityAddressView`; `ICCLiquidity` for `liquidityDetailsView`, `getXSlotView`, `getYSlotView`, `update`, `transactToken`, `transactNative`.

### changeDepositor(address listingAddress, bool isX, uint256 slotIndex, address newDepositor)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `isX`: True for token A, false for token B.
  - `slotIndex`: Slot index.
  - `newDepositor`: New slot owner address.
- **Behavior**: Reassigns slot ownership via `_changeDepositor`.
- **Internal Call Flow**:
  - `_changeDepositor`: Validates `depositor`, `newDepositor`, calls `ICCLiquidity.changeSlotDepositor`, updates `userXIndex`/`userYIndex`.
- **Balance Checks**: Implicit slot validation in `CCLiquidityTemplate`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas**: Single external call.
- **Interactions**: Calls `ICCListing` for `liquidityAddressView`; `ICCLiquidity` for `changeSlotDepositor`.

### queryDepositorFees(address listingAddress, address depositor, uint256 liquidityIndex, bool isX)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `depositor`: User address.
  - `liquidityIndex`: Slot index.
  - `isX`: True for token A, false for token B.
- **Behavior**: Queries pending fees via `_validateFeeClaim` and `_calculateFeeShare`.
- **Internal Call Flow**:
  - `_validateFeeClaim`: Validates inputs, retrieves slot and liquidity data.
  - `_calculateFeeShare`: Computes `feeShare` using formula above.
- **Balance Checks**: `xBalance`, `xLiquid`/`yLiquid`, `allocation`.
- **Restrictions**: `onlyValidListing`.
- **Gas**: View function, multiple external calls for data retrieval.
- **Interactions**: Calls `ICCListing` for `volumeBalances`, `tokenA`, `tokenB`, `liquidityAddressView`; `ICCLiquidity` for `liquidityDetailsView`, `getXSlotView`, `getYSlotView`.

## Clarifications and Nuances
- **Token Flow**:
  - **Deposits**: User → `CCLiquidityRouter` → `CCLiquidityTemplate`. Pre/post balance checks handle tax-on-transfer tokens using `receivedAmount`. Creates new slots using `nextXSlotIDView`/`nextYSlotIDView` (v0.0.24).
  - **Withdrawals**: `CCLiquidityTemplate` → User. `PreparedWithdrawal` handles dual-token withdrawals if liquidity is insufficient, using `prices(0)` for conversion.
  - **Fees**: `CCLiquidityTemplate` → User, with `feeShare` based on `allocation` and `liquid`.
- **Decimal Handling**: Normalizes to 1e18 using `normalize`, denormalizes for transfers using `IERC20.decimals` or 18 for ETH.
- **Security**:
  - `nonReentrant` prevents reentrancy.
  - Try-catch ensures graceful degradation with `TransferFailed`, `DepositFailed`, `SlotUpdateFailed`, etc.
  - No `virtual`/`override`, explicit casting, no inline assembly, no reserved keywords.
- **Gas Optimization**:
  - `DepositState` and `depositStates` mapping reduce stack usage in call tree.
  - Early validation in `_validateInputs`, `_fetchListingData` minimizes gas on failures.
- **Error Handling**: Detailed errors (`InvalidInput`, `InvalidListingState`, `InvalidLiquidityContract`, `SlotUpdateFailed`, `InsufficientAllowance`) and events (`TransferFailed`, `DepositFailed`, `DepositReceived`, `FeesClaimed`, `SlotDepositorChanged`) aid debugging.
- **Router Validation**: `CCLiquidityTemplate` validates `routers[msg.sender]`.
- **Pool Validation**: Allows deposits in any pool state, supporting zero-balance initialization.
- **Multiple Deposits**: Always creates new slots (v0.0.24), simplifying deposit logic.
- **Limitations**: No direct `addFees` usage; payouts handled in `CCOrderRouter`.
- **Silent Revert Fix**: Early validation in `_validateInputs` (zero checks), `_fetchListingData` (token/liquidity address validation), and try-catch in `_executeTokenTransfer`, `_executeNativeTransfer`, `_updateSlot` prevent silent reverts.
- **Call Tree**: `_depositToken` and `_depositNative` split into `_validateInputs`, `_fetchListingData`, `_executeTokenTransfer`, `_executeNativeTransfer`, `_updateSlot`, reducing complexity and stack depth.
