# CCLiquidityRouter Contract Documentation

## Overview
The `CCLiquidityRouter` contract, implemented in Solidity (`^0.8.2`), serves as a specialized router for managing liquidity operations and payouts on a decentralized trading platform. It inherits functionality from `CCLiquidityPartial`, which extends `CCMainPartial`, and integrates with external interfaces (`ICCListing`, `ICCLiquidityTemplate`, `IERC20`) for token operations, `ReentrancyGuard` for reentrancy protection, and `SafeERC20` for secure token transfers. The contract focuses on liquidity management (`depositNativeToken`, `depositToken`, `withdraw`, `claimFees`, `changeDepositor`) and payout settlement (`settleLongLiquid`, `settleShortLiquid`, `settleLongPayouts`, `settleShortPayouts`). State variables are hidden, accessed via view functions with unique names, and decimal precision is maintained across tokens. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.10 (updated 2025-07-27)

**Inheritance Tree:** `CCLiquidityRouter` → `CCLiquidityPartial` → `CCMainPartial`

## Mappings
- **payoutPendingAmounts** (address => uint256 => uint256): Tracks pending payout amounts per listing and order ID, defined in `CCLiquidityPartial`. Accessed indirectly via `settleSingleLongLiquid` and `settleSingleShortLiquid`.

## Structs
- **PreparedWithdrawal**: Defined in `ICCLiquidityTemplate`, contains `amountA` and `amountB` (normalized withdrawal amounts). Used in `withdraw`.
- **PayoutUpdate**: Defined in `ICCListing`, contains `payoutType` (0=Long, 1=Short), `recipient` (address), `required` (uint256, normalized). Used in `settleLongLiquid`, `settleShortLiquid`, `settleLongPayouts`, `settleShortPayouts`.
- **PayoutContext**: Defined in `CCLiquidityPartial`, contains `listingAddress`, `liquidityAddr`, `tokenOut`, `tokenDecimals`, `amountOut`, `recipientAddress`. Used in payout functions.

## External Functions

### depositNativeToken(address listingAddress, uint256 inputAmount, bool isTokenA)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `inputAmount` (uint256): ETH deposit amount (denormalized).
  - `isTokenA` (bool): True if tokenA is ETH, false if tokenB is ETH.
- **Behavior**: Deposits ETH to the liquidity pool for `msg.sender`, transferring `msg.value` to `liquidityAddr`, updating `_xLiquiditySlots` or `_yLiquiditySlots`.
- **Internal Call Flow**:
  - Validates `msg.value == inputAmount`, `tokenAddress == address(0)`, and `listingContract.getListingId() > 0` for pool initialization.
  - Calls `liquidityContract.depositNative` with value transfer.
- **Balance Checks**: Verifies `msg.value == inputAmount`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, requires router registration, valid `liquidityAddr`, non-zero listing ID.
- **Gas Usage Controls**: Single external call, try-catch.
- **External Dependencies**: `ISSAgent.globalizeLiquidity`, `ITokenRegistry.initializeBalances`.

### depositToken(address listingAddress, uint256 inputAmount, bool isTokenA)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `inputAmount` (uint256): Token deposit amount (denormalized).
  - `isTokenA` (bool): True for tokenA, false for tokenB.
- **Behavior**: Deposits ERC-20 tokens to the liquidity pool for `msg.sender`, transferring tokens to `liquidityAddr`.
- **Internal Call Flow**:
  - Validates `tokenAddress != address(0)`, `listingContract.getListingId() > 0`, and `liquidityAddr != address(0)`.
  - Transfers tokens via `safeTransferFrom`, approves `liquidityAddr`, calls `depositToken`.
- **Balance Checks**: Pre/post balance checks for `receivedAmount`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, requires router registration, valid `liquidityAddr`, non-zero listing ID.
- **Gas Usage Controls**: Single transfer and call, try-catch.
- **External Dependencies**: `ISSAgent.globalizeLiquidity`, `ITokenRegistry.initializeBalances`.

### withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `inputAmount` (uint256): Withdrawal amount (denormalized).
  - `index` (uint256): Slot index.
  - `isX` (bool): True for tokenA slot, false for tokenB slot.
- **Behavior**: Withdraws liquidity for `msg.sender`, using `xPrepOut`/`yPrepOut` and `xExecuteOut`/`yExecuteOut`.
- **Internal Call Flow**:
  - Calls `xPrepOut`/`yPrepOut` to prepare withdrawal, then `xExecuteOut`/`yExecuteOut` to transfer tokens/ETH.
- **Balance Checks**: Handled by `liquidityContract`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, requires router registration, `msg.sender` as depositor.
- **Gas Usage Controls**: Two external calls, try-catch.
- **External Dependencies**: `ICCListing.getPrice`, `ISSAgent.globalizeLiquidity`, `ITokenRegistry.initializeBalances`.

### claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `liquidityIndex` (uint256): Slot index.
  - `isX` (bool): True for tokenA slot, false for tokenB slot.
  - `volumeAmount` (uint256): Ignored, uses `volumeBalances`.
- **Behavior**: Claims fees for `msg.sender`, transferring converted fees.
- **Internal Call Flow**:
  - Calls `liquidityContract.claimFees`, validates depositor, fetches `volumeBalances` and `getPrice`.
- **Balance Checks**: Handled by `liquidityContract`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, requires router registration, `msg.sender` as depositor.
- **Gas Usage Controls**: Two external calls, try-catch.
- **External Dependencies**: `ICCListing.volumeBalances`, `ICCListing.getPrice`.

### changeDepositor(address listingAddress, bool isX, uint256 slotIndex, address newDepositor)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `isX` (bool): True for tokenA slot, false for tokenB slot.
  - `slotIndex` (uint256): Slot index.
  - `newDepositor` (address): New slot owner.
- **Behavior**: Changes slot depositor for `msg.sender`, updating `_userIndex`.
- **Internal Call Flow**:
  - Calls `liquidityContract.changeSlotDepositor`, validates depositor.
- **Balance Checks**: None.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, requires router registration, valid depositors.
- **Gas Usage Controls**: Single external call.
- **External Dependencies**: None.

### settleLongLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Settles long liquidation payouts, transferring tokenB up to `maxIterations`.
- **Internal Call Flow**:
  - Iterates `longPayoutByIndexView`, calls `settleSingleLongLiquid`, updates `payoutPendingAmounts` and `ssUpdate`.
- **Balance Checks**: Try-catch ensures transfer success.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas Usage Controls**: `maxIterations` limits loops, dynamic array resizing, try-catch.
- **External Dependencies**: `transactNative/Token`, `ssUpdate`.

### settleShortLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongLiquid`.
- **Behavior**: Settles short liquidation payouts, transferring tokenA.
- **Internal Call Flow**: Uses `shortPayoutByIndexView`, `settleSingleShortLiquid`.
- **Gas Usage Controls**: Same as `settleLongLiquid`.
- **External Dependencies**: Same as `settleLongLiquid`.

### settleLongPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongLiquid`.
- **Behavior**: Executes long payouts, transferring tokenB.
- **Internal Call Flow**: Calls `executeLongPayouts`, uses `longPayoutByIndexView`.
- **Gas Usage Controls**: Same as `settleLongLiquid`.
- **External Dependencies**: Same as `settleLongLiquid`.

### settleShortPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongPayouts`.
- **Behavior**: Executes short payouts, transferring tokenA.
- **Internal Call Flow**: Uses `shortPayoutByIndexView`.
- **Gas Usage Controls**: Same as `settleLongLiquid`.
- **External Dependencies**: Same as `settleLongLiquid`.

## Additional Details
- **Decimal Handling**: Uses `normalize`/`denormalize` for precision, `decimalsA/B` or 18 for ETH.
- **Security**: `nonReentrant`, `onlyValidListing`, safe transfers, try-catch for external calls.
- **Events**: Relies on `listingContract` and `liquidityContract` events.
- **Compatibility**: `CCMainPartial` (v0.0.6), `CCListing` (v0.0.3), `CCLiquidityTemplate` (v0.0.3).
