# CCLiquidityRouter Contract Documentation

## Overview
The `CCLiquidityRouter`, implemented in Solidity (^0.8.2), manages liquidity deposits, withdrawals, fee claims, and long/short liquidation payouts on a decentralized trading platform. It inherits `CCLiquidityPartial`, which extends `CCMainPartial`, and integrates with `ICCListing`, `ICCLiquidityTemplate`, `IERC20`, and `ICCAgent` for token operations, liquidity management, and listing validation. It uses `ReentrancyGuard` for security and `Ownable` for administrative control. State variables are hidden, accessed via view functions with unique names, and amounts are normalized to 1e18 for precision. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation. All transfers call `listingContract.ssUpdate` or `update` after successful operations.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.0.6 (Updated 2025-07-29)

**Inheritance Tree**: `CCLiquidityRouter` → `CCLiquidityPartial` → `CCMainPartial`

**Compatibility**: CCListingTemplate.sol (v0.0.6), CCMainPartial.sol (v0.0.9), CCLiquidityPartial.sol (v0.0.10), CCLiquidityTemplate.sol (v0.0.2), CCAgent.sol.

## Mappings
- **`payoutPendingAmounts`**: `mapping(address => mapping(uint256 => uint256))` - Tracks pending payout amounts per listing and order ID (inherited from `CCLiquidityPartial`).
- Relies on `ICCListing` view functions (e.g., `longPayoutByIndexView`, `shortPayoutByIndexView`) for payout tracking.

## Structs
- **PayoutContext**: Contains `listingAddress` (address), `liquidityAddr` (address), `tokenOut` (address), `tokenDecimals` (uint8), `amountOut` (uint256, denormalized), `recipientAddress` (address).
- **ICCListing.PayoutUpdate**: Contains `payoutType` (uint8, 0=Long, 1=Short), `recipient` (address), `required` (uint256, normalized).
- **ICCListing.LongPayoutStruct**: Contains `makerAddress` (address), `recipientAddress` (address), `required` (uint256), `filled` (uint256), `orderId` (uint256), `status` (uint8).
- **ICCListing.ShortPayoutStruct**: Contains `makerAddress` (address), `recipientAddress` (address), `amount` (uint256), `filled` (uint256), `orderId` (uint256), `status` (uint8).
- **ICCLiquidityTemplate.PreparedWithdrawal**: Contains `amountA` (uint256, normalized), `amountB` (uint256, normalized).
- **ICCLiquidityTemplate.Slot**: Contains `depositor` (address), `recipient` (address), `allocation` (uint256, normalized), `dFeesAcc` (uint256), `timestamp` (uint256).
- **ICCLiquidityTemplate.UpdateType**: Contains `updateType` (uint8, 0=balance, 1=fees, 2=xSlot, 3=ySlot), `index` (uint256), `value` (uint256, normalized), `addr` (address), `recipient` (address).

## Formulas
1. **Payout Amount**:
   - **Formula**: `amountOut = denormalize(payout.required, tokenDecimals)` (long), `amountOut = denormalize(payout.amount, tokenDecimals)` (short).
   - **Used in**: `settleSingleLongLiquid`, `settleSingleShortLiquid`, `executeLongPayout`, `executeShortPayout`.
   - **Description**: Denormalizes payout amounts (`required` for long, `amount` for short) to token decimals for transfer.

2. **Liquidity Check**:
   - **Formula**: `sufficient = isLong ? yAmount >= requiredAmount : xAmount >= requiredAmount`.
   - **Used in**: `_checkLiquidityBalance`.
   - **Description**: Verifies sufficient liquidity (`xAmount` or `yAmount` from `liquidityAmounts`) for payout amounts.

3. **Transfer Tracking**:
   - **Formula**: `amountReceived = postBalance - preBalance`, `normalizedReceived = normalize(amountReceived, tokenDecimals)`.
   - **Used in**: `_transferNative`, `_transferToken`.
   - **Description**: Tracks actual tokens/ETH received by recipient, normalized for updates.

## External Functions
### depositNativeToken(address listingAddress, uint256 inputAmount, bool isTokenA)
- **Parameters**:
  - `listingAddress`: Listing contract address.
  - `inputAmount`: ETH amount (18 decimals).
  - `isTokenA`: True for token A, false for token B.
- **Behavior**: Deposits ETH to liquidity pool via `ICCLiquidityTemplate.depositNative`, supports zero-balance pool initialization.
- **Internal Call Flow**:
  - Validates `msg.value == inputAmount`, `tokenAddress == address(0)`, `routers(address(this))`.
  - Checks `liquidityAmounts` for zero-balance or valid side deposit.
  - Calls `depositNative` with try-catch.
- **Balance Checks**: Verifies `msg.value`, `xAmount`/`yAmount`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, requires router registration.
- **Gas Usage Controls**: Minimal, single external call.

### depositToken(address listingAddress, uint256 inputAmount, bool isTokenA)
- **Parameters**: Same as `depositNativeToken`, `inputAmount` in token decimals.
- **Behavior**: Deposits ERC20 tokens via `IERC20.transferFrom` and `ICCLiquidityTemplate.depositToken`, supports zero-balance initialization.
- **Internal Call Flow**:
  - Validates `tokenAddress != address(0)`, `routers(address(this))`, allowance.
  - Checks `liquidityAmounts` for zero-balance or valid side deposit.
  - Transfers tokens, verifies received amount, approves, and calls `depositToken`.
- **Balance Checks**: Pre/post balance for `this`, allowance check.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, requires router registration.
- **Gas Usage Controls**: Two transfers, try-catch for `transferFrom` and `depositToken`.

### withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX)
- **Parameters**:
  - `listingAddress`: Listing contract address.
  - `inputAmount`: Normalized amount.
  - `index`: Slot index.
  - `isX`: True for token A, false for token B.
- **Behavior**: Withdraws tokens via `xPrepOut`/`yPrepOut` and `xExecuteOut`/`yExecuteOut`.
- **Internal Call Flow**:
  - Validates `routers(address(this))`, `msg.sender`.
  - Calls `xPrepOut`/`yPrepOut` to prepare withdrawal, then `xExecuteOut`/`yExecuteOut` with try-catch.
- **Balance Checks**: Implicit in `xPrepOut`/`yPrepOut`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, requires router registration.
- **Gas Usage Controls**: Two external calls, minimal updates.

### claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount)
- **Parameters**:
  - `listingAddress`: Listing contract address.
  - `liquidityIndex`: Slot index.
  - `isX`: True for token A, false for token B.
  - `volumeAmount`: Ignored (compatibility).
- **Behavior**: Claims fees via `ICCLiquidityTemplate.claimFees`.
- **Internal Call Flow**:
  - Validates `routers(address(this))`, `msg.sender`.
  - Calls `claimFees` with try-catch.
- **Balance Checks**: Implicit in `claimFees`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, requires router registration.
- **Gas Usage Controls**: Single external call.

### changeDepositor(address listingAddress, bool isX, uint256 slotIndex, address newDepositor)
- **Parameters**:
  - `listingAddress`: Listing contract address.
  - `isX`: True for token A, false for token B.
  - `slotIndex`: Slot index.
  - `newDepositor`: New depositor address.
- **Behavior**: Changes slot depositor via `ICCLiquidityTemplate.changeSlotDepositor`.
- **Internal Call Flow**:
  - Validates `routers(address(this))`, `msg.sender`, `newDepositor`.
  - Calls `changeSlotDepositor` with try-catch.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, requires router registration.
- **Gas Usage Controls**: Single external call.

### settleLongLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress`: Listing contract address.
  - `maxIterations`: Maximum payouts to process.
- **Behavior**: Settles long liquidation payouts up to `maxIterations`, transferring token B via `ICCLiquidityTemplate`.
- **Internal Call Flow**:
  - Fetches `orderIdentifiers` via `longPayoutByIndexView`.
  - Iterates up to `maxIterations`, calls `settleSingleLongLiquid`:
    - Checks `payout.required`, sets status to 3 if zero.
    - Prepares `PayoutContext`, checks liquidity via `_checkLiquidityBalance`.
    - Transfers token B via `_transferNative`/`_transferToken`.
    - Updates `payoutPendingAmounts`, creates `PayoutUpdate`.
  - Resizes updates, calls `listingContract.ssUpdate`.
- **Balance Checks**: Pre/post balance in `_transferNative`/`_transferToken`, liquidity check.
- **Mappings/Structs Used**: `payoutPendingAmounts`, `PayoutContext`, `ICCListing.PayoutUpdate`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, requires router registration.
- **Gas Usage Controls**: `maxIterations`, dynamic array resizing.

### settleShortLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongLiquid`.
- **Behavior**: Settles short liquidation payouts, transferring token A via `ICCLiquidityTemplate`.
- **Internal Call Flow**:
  - Fetches `orderIdentifiers` via `shortPayoutByIndexView`.
  - Iterates up to `maxIterations`, calls `settleSingleShortLiquid`:
    - Checks `payout.amount`, sets status to 3 if zero.
    - Prepares `PayoutContext`, checks liquidity.
    - Transfers token A via `_transferNative`/`_transferToken`.
    - Updates `payoutPendingAmounts`, creates `PayoutUpdate`.
  - Resizes updates, calls `listingContract.ssUpdate`.
- **Balance Checks**: Same as `settleLongLiquid`.
- **Mappings/Structs Used**: Same as `settleLongLiquid`.
- **Restrictions**: Same as `settleLongLiquid`.
- **Gas Usage Controls**: Same as `settleLongLiquid`.

### settleLongPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongLiquid`.
- **Behavior**: Executes long payouts via `executeLongPayout`, transferring token B via `listingContract`.
- **Internal Call Flow**:
  - Calls `executeLongPayouts`, which iterates `longPayoutByIndexView`, calls `executeLongPayout`:
    - Checks `payout.required`, skips if zero.
    - Prepares `PayoutContext`, transfers token B via `_transferNative`/`_transferToken`.
    - Updates `payoutPendingAmounts`, creates `PayoutUpdate`.
  - Resizes updates, calls `listingContract.ssUpdate`.
- **Balance Checks**: Pre/post balance in `_transferNative`/`_transferToken`.
- **Mappings/Structs Used**: Same as `settleLongLiquid`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas Usage Controls**: `maxIterations`, dynamic array resizing.

### settleShortPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongLiquid`.
- **Behavior**: Executes short payouts via `executeShortPayout`, transferring token A via `listingContract`.
- **Internal Call Flow**:
  - Calls `executeShortPayouts`, which iterates `shortPayoutByIndexView`, calls `executeShortPayout`:
    - Checks `payout.amount`, skips if zero.
    - Prepares `PayoutContext`, transfers token A via `_transferNative`/`_transferToken`.
    - Updates `payoutPendingAmounts`, creates `PayoutUpdate`.
  - Resizes updates, calls `listingContract.ssUpdate`.
- **Balance Checks**: Same as `settleLongLiquid`.
- **Mappings/Structs Used**: Same as `settleLongLiquid`.
- **Restrictions**: Same as `settleLongLiquid`.
- **Gas Usage Controls**: Same as `settleLongLiquid`.

## Clarifications and Nuances
- **ICCLiquidityTemplate Integration**:
  - Used for deposits (`depositNativeToken`, `depositToken`), withdrawals (`withdraw`), fee claims (`claimFees`), and liquidations (`settleLong/ShortLiquid`).
  - Requires `routers(address(this))` for all operations.
  - Balance checks in `_transferNative`/`_transferToken` handle fee-on-transfer tokens and ETH.
- **Payout Mechanics**:
  - Long payouts transfer token B, short payouts transfer token A.
  - `settleLong/ShortLiquid` uses `ICCLiquidityTemplate`, `settleLong/ShortPayouts` uses `listingContract`.
  - Zero-amount payouts set status to 3, return `PayoutUpdate` with `required=0`.
- **Decimal Handling**:
  - Normalizes to 1e18 via `normalize`, denormalizes for transfers via `denormalize`.
  - ETH uses 18 decimals, ERC20 uses `IERC20.decimals`.
- **Gas Optimization**:
  - `maxIterations` limits loops in `settleLong/ShortLiquid`, `settleLong/ShortPayouts`.
  - Dynamic array resizing for `tempUpdates` and `finalUpdates`.
  - Helper functions (`_prepPayoutContext`, `_checkLiquidityBalance`, `_transferNative`/`_transferToken`).
- **Security Measures**:
  - `nonReentrant` on all state-changing functions.
  - `onlyValidListing` checks `ICCAgent.getListing`.
  - Try-catch for external calls (`depositNative`, `depositToken`, `x/yPrepOut`, `x/yExecuteOut`, `claimFees`, `changeSlotDepositor`, `_transferNative`/`_transferToken`).
  - Explicit casting, no inline assembly, hidden state variables accessed via view functions.
- **Limitations**:
  - No direct Uniswap V2 integration; relies on `ICCLiquidityTemplate`.
  - Payouts assume sufficient liquidity, return empty updates if insufficient.
  - `volumeAmount` in `claimFees` ignored for compatibility.

## Additional Details
- **Events**: `TransferFailed`, `InsufficientAllowance` (inherited from `CCLiquidityPartial`).
- **Safety**:
  - Explicit casting for interfaces.
  - No inline assembly.
  - Avoids reserved keywords, unnecessary virtual/override.
- **Compatibility**: Aligned with `CCListingTemplate.sol` (v0.0.6), `CCMainPartial.sol` (v0.0.9), `CCLiquidityPartial.sol` (v0.0.10), `CCLiquidityTemplate.sol` (v0.0.2).
