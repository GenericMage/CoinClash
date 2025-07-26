The system remains intact since the previous markdown version, with intentional structural changes in `CCLiquidityRouter.sol` (v0.0.7) and `CCLiquidityPartial.sol` (v0.0.7) reflected in the updated documentation.



# CCLiquidityRouter Contract Documentation

## Overview
The `CCLiquidityRouter` contract, implemented in Solidity (`^0.8.2`), serves as a specialized router for managing liquidity operations and payouts on a decentralized trading platform. It inherits functionality from `CCLiquidityPartial`, which extends `CCMainPartial`, and integrates with external interfaces (`ICCListing`, `ICCLiquidityTemplate`, `IERC20`) for token operations, `ReentrancyGuard` for reentrancy protection, and `SafeERC20` for secure token transfers. The contract focuses on liquidity management (`depositNativeToken`, `depositToken`, `withdraw`, `claimFees`, `changeDepositor`) and payout settlement (`settleLongLiquid`, `settleShortLiquid`, `settleLongPayouts`, `settleShortPayouts`). State variables are hidden, accessed via view functions with unique names, and decimal precision is maintained across tokens. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.7 (updated 2025-07-26)

**Inheritance Tree:** `CCLiquidityRouter` → `CCLiquidityPartial` → `CCMainPartial`

## Mappings
- **payoutPendingAmounts** (address => uint256 => uint256): Tracks pending payout amounts per listing and order ID, defined in `CCLiquidityPartial`. Accessed indirectly via `settleSingleLongLiquid` and `settleSingleShortLiquid`.

## Structs
- **PreparedWithdrawal**: Defined in `ICCLiquidityTemplate`, contains `amountA` and `amountB` (normalized withdrawal amounts). Used in `withdraw`.
- **PayoutUpdate**: Defined in `ICCListing`, contains `payoutType` (0=Long, 1=Short), `recipient` (address), `required` (uint256, normalized). Used in `settleLongLiquid`, `settleShortLiquid`, `settleLongPayouts`, `settleShortPayouts`.
- **PayoutContext**: Defined in `CCLiquidityPartial`, contains `listingAddress`, `liquidityAddr`, `tokenOut`, `tokenDecimals`, `amountOut`, `recipientAddress`. Used in payout functions.

## External Functions

### depositNativeToken(address listingAddress, uint256 inputAmount)
- **Parameters**:
  - `listingAddress` (address): Listing contract address; must match `_listingAddress` in `liquidityContract`.
  - `inputAmount` (uint256): ETH deposit amount (denormalized).
- **Behavior**: Deposits ETH to the liquidity pool for `msg.sender`, transferring `msg.value` to `liquidityAddr`, updating `_xLiquiditySlots` or `_yLiquiditySlots` via `ICCLiquidityTemplate.depositNative`.
- **Internal Call Flow**:
  - Validates `msg.value == inputAmount` and router registration.
  - Calls `liquidityContract.depositNative(msg.sender, inputAmount)` with value transfer:
    - Validates token as `_tokenA` or `_tokenB` (ETH as address(0)).
    - Normalizes amount, updates slots via `update`, calls `globalizeUpdate` and `updateRegistry`.
  - Transfer destination: `liquidityAddr` (ETH value).
- **Balance Checks**: Verifies `msg.value == inputAmount`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires `liquidityContract.routers(address(this))`.
  - Reverts if `msg.value` mismatches, listing is invalid, or deposit fails (`"Native deposit failed"`).
- **Gas Usage Controls**: Single external call, try-catch for robustness.
- **External Dependencies**: `depositNative` calls `ISSAgent.globalizeLiquidity`, `ITokenRegistry.initializeBalances`.

### depositToken(address listingAddress, address tokenAddress, uint256 inputAmount)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `tokenAddress` (address): ERC-20 token address (tokenA or tokenB).
  - `inputAmount` (uint256): Token deposit amount (denormalized).
- **Behavior**: Deposits ERC-20 tokens to the liquidity pool for `msg.sender`, transferring tokens from `msg.sender` to `this`, then to `liquidityAddr`, updating `_xLiquiditySlots` or `_yLiquiditySlots`.
- **Internal Call Flow**:
  - Validates `tokenAddress` as `tokenA` or `tokenB`, not address(0).
  - Transfers tokens via `IERC20.safeTransferFrom`, checks pre/post balance for `receivedAmount`.
  - Approves `liquidityAddr`, calls `liquidityContract.depositToken(msg.sender, tokenAddress, receivedAmount)`:
    - Normalizes amount, updates slots, calls `globalizeUpdate` and `updateRegistry`.
  - Transfer destinations: `this` (from `msg.sender`), `liquidityAddr` (from `this`).
- **Balance Checks**: Pre/post balance checks ensure `receivedAmount > 0`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires `liquidityContract.routers(address(this))`.
  - Reverts if token is invalid, listing is invalid, no tokens received, or deposit fails (`"Token deposit failed"`).
- **Gas Usage Controls**: Single transfer and call, try-catch for external calls.
- **External Dependencies**: `depositToken` calls `ISSAgent.globalizeLiquidity`, `ITokenRegistry.initializeBalances`.

### withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `inputAmount` (uint256): Withdrawal amount (denormalized).
  - `index` (uint256): Slot index in `_xLiquiditySlots` or `_yLiquiditySlots`.
  - `isX` (bool): True for tokenA slot, false for tokenB slot (or ETH).
- **Behavior**: Withdraws liquidity for `msg.sender`, restricted to slot’s depositor, using `xPrepOut`/`yPrepOut` to prepare `PreparedWithdrawal`, then `xExecuteOut`/`yExecuteOut` to transfer tokens/ETH.
- **Internal Call Flow**:
  - Validates `msg.sender` as non-zero, router registration.
  - Calls `xPrepOut` or `yPrepOut`:
    - Validates `msg.sender` as depositor, `inputAmount` against allocation.
    - Fetches price via `ICCListing.getPrice` for compensation.
  - Calls `xExecuteOut` or `yExecuteOut`:
    - Updates slot allocation via `update`.
    - Transfers tokens via `IERC20.safeTransfer` or ETH.
  - Transfer destination: `msg.sender`.
- **Balance Checks**: Handled by `liquidityContract` with try-catch.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires `liquidityContract.routers(address(this))`.
  - Reverts if `msg.sender` is zero, not depositor, listing is invalid, or calls fail (`"Withdrawal preparation failed"`, `"Withdrawal execution failed"`).
- **Gas Usage Controls**: Two external calls, minimal updates, try-catch.
- **External Dependencies**: Calls `ICCListing.getPrice`, `ISSAgent.globalizeLiquidity`, `ITokenRegistry.initializeBalances`.

### claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `liquidityIndex` (uint256): Slot index in `_xLiquiditySlots` or `_yLiquiditySlots`.
  - `isX` (bool): True for tokenA slot (claims tokenB fees), false for tokenB slot (claims tokenA fees).
  - `volumeAmount` (uint256): Unused, volume fetched from `volumeBalances`.
- **Behavior**: Claims fees for `msg.sender`, restricted to slot’s depositor, converting fees using `ICCListing.getPrice`, transferring to `msg.sender`.
- **Internal Call Flow**:
  - Validates `msg.sender`, router registration.
  - Calls `liquidityContract.claimFees`:
    - Validates `msg.sender` as depositor.
    - Fetches volume via `ICCListing.volumeBalances`, price via `ICCListing.getPrice`.
    - Updates fees, slot via `update`, transfers converted fees.
  - Transfer destination: `msg.sender`.
- **Balance Checks**: Handled by `liquidityContract` with try-catch.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires `liquidityContract.routers(address(this))`.
  - Reverts if `msg.sender` is zero, not depositor, listing is invalid, or calls fail (`"Claim fees failed"`).
- **Gas Usage Controls**: Two external calls, minimal updates, try-catch.
- **External Dependencies**: Calls `ICCListing.volumeBalances`, `ICCListing.getPrice`.

### changeDepositor(address listingAddress, bool isX, uint256 slotIndex, address newDepositor)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `isX` (bool): True for tokenA slot, false for tokenB slot.
  - `slotIndex` (uint256): Slot index in `_xLiquiditySlots` or `_yLiquiditySlots`.
  - `newDepositor` (address): New slot owner.
- **Behavior**: Changes slot depositor for `msg.sender`, restricted to current depositor, updating `_userIndex`.
- **Internal Call Flow**:
  - Validates `msg.sender`, `newDepositor` as non-zero.
  - Calls `liquidityContract.changeSlotDepositor`:
    - Validates `msg.sender` as depositor, updates slot and `_userIndex`.
- **Balance Checks**: None, handled by `liquidityContract`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires `liquidityContract.routers(address(this))`.
  - Reverts if `msg.sender` or `newDepositor` is zero, not depositor, or listing is invalid (`"Failed to change depositor"`).
- **Gas Usage Controls**: Single external call, minimal array operations.
- **External Dependencies**: None beyond `changeSlotDepositor`.

### settleLongLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Settles long liquidation payouts, transferring tokenB (or ETH) to holders, up to `maxIterations`.
- **Internal Call Flow**:
  - Iterates `longPayoutByIndexView` up to `maxIterations`.
  - Calls `settleSingleLongLiquid`:
    - Fetches payout via `getLongPayout`, checks liquidity via `_checkLiquidityBalance`.
    - Transfers via `_transferNative` or `_transferToken`.
    - Updates `payoutPendingAmounts`, creates `PayoutUpdate`.
  - Resizes updates, applies via `listingContract.ssUpdate`.
- **Balance Checks**: Try-catch ensures transfer success, returns empty array on failure.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires `liquidityContract.routers(address(this))`.
  - Skips zero-amount payouts.
- **Gas Usage Controls**: `maxIterations` limits loops, dynamic array resizing, try-catch.
- **External Dependencies**: Calls `liquidityContract.transactNative/Token`, `listingContract.ssUpdate`.

### settleShortLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongLiquid`.
- **Behavior**: Settles short liquidation payouts, transferring tokenA to holders, up to `maxIterations`.
- **Internal Call Flow**: Uses `shortPayoutByIndexView`, `settleSingleShortLiquid`.
- **Balance Checks**: Same as `settleLongLiquid`.
- **Restrictions**: Same as `settleLongLiquid`.
- **Gas Usage Controls**: Same as `settleLongLiquid`.
- **External Dependencies**: Same as `settleLongLiquid`.

### settleLongPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongLiquid`.
- **Behavior**: Executes long payouts, transferring tokenB (or ETH) to holders, up to `maxIterations`.
- **Internal Call Flow**:
  - Calls `executeLongPayouts`:
    - Iterates `longPayoutByIndexView`, calls `executeLongPayout`.
    - Transfers via `_transferNative` or `_transferToken`.
    - Updates `payoutPendingAmounts`, applies via `ssUpdate`.
- **Balance Checks**: Same as `settleLongLiquid`.
- **Restrictions**: Same as `settleLongLiquid`.
- **Gas Usage Controls**: Same as `settleLongLiquid`.
- **External Dependencies**: Same as `settleLongLiquid`.

### settleShortPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongPayouts`.
- **Behavior**: Executes short payouts, transferring tokenA to holders, up to `maxIterations`.
- **Internal Call Flow**: Uses `shortPayoutByIndexView`, `executeShortPayout`.
- **Balance Checks**: Same as `settleLongLiquid`.
- **Restrictions**: Same as `settleLongLiquid`.
- **Gas Usage Controls**: Same as `settleLongLiquid`.
- **External Dependencies**: Same as `settleLongLiquid`.

## Clarifications and Nuances

### Token Handling and Decimal Normalization
- **Normalization**: Uses `normalize` and `denormalize` from `CCMainPartial` to handle token amounts (18 decimals internally). Fetches decimals via `ICCListing.decimalsA/B` or 18 for ETH.
- **ETH Handling**: Supports ETH when `tokenA` or `tokenB` is address(0), using `msg.value` for deposits and value transfers for withdrawals/payouts.
- **Fee Conversion**: `claimFees` converts fees using `ICCListing.getPrice` (xSlots claim tokenB fees, ySlots claim tokenA fees).

### Liquidity Management
- **Deposits**: Allows any `msg.sender` to deposit for `msg.sender`, no depositor restriction.
- **Withdrawals**: Restricts to `msg.sender` as slot depositor, compensates with opposite token if needed.
- **Fee Claims**: Restricts to `msg.sender` as slot depositor, uses `volumeBalances` and `getPrice`.
- **Depositor Changes**: Restricts to `msg.sender` as slot depositor.

### Payout Processing
- **Long Payouts**: Output tokenB (or ETH), no `amountSent`.
- **Short Payouts**: Output tokenA, no `amountSent`.
- **Graceful Degradation**: Zero-amount payouts return empty `PayoutUpdate[]`.

### Gas Optimization
- **Max Iterations**: Limits loops in payout functions.
- **Dynamic Arrays**: Resizes `tempUpdates` to `finalUpdates` for non-zero updates.
- **Minimal Updates**: Single `PayoutUpdate` per payout.

### Security Measures
- **Reentrancy Protection**: `nonReentrant` on all external functions.
- **Listing Validation**: `onlyValidListing` uses `ICCAgent.getListing` for integrity.
- **Router Restriction**: Requires `liquidityContract.routers(address(this))`.
- **Safe Transfers**: Uses `SafeERC20.safeTransferFrom`, try-catch for external calls.
- **Balance Checks**: Pre/post balance checks in `depositToken`, `msg.value` checks for ETH.
- **Depositor Restriction**: Enforces `msg.sender` as depositor for `withdraw`, `claimFees`, `changeDepositor`.

### Limitations and Assumptions
- **No Order Creation/Settlement**: Focuses on liquidity and payouts, unlike `CCOrderRouter`.
- **ETH Support**: Assumes `tokenA` or `tokenB` can be address(0) for ETH.
- **Fee Volume**: `volumeAmount` in `claimFees` is unused, uses `volumeBalances`.
- **No Direct State**: Relies on `liquidityContract` and `listingContract` for state.

### Differences from SSRouter
- **Scope**: Focused on liquidity and payouts, omits order creation/settlement.
- **Inheritance**: Uses `CCLiquidityPartial` for payouts, unlike `CCOrderRouter`’s `SSOrderPartial`.
- **Functionality**: Includes liquidity functions and payouts, excludes order management.
- **Gas Efficiency**: Lighter than `SSRouter`, heavier than `CCOrderRouter`.

## Additional Details
- **Decimal Handling**: Uses `normalize`/`denormalize` for precision, `decimalsA/B` for tokens, 18 for ETH.
- **Events**: Relies on `listingContract` and `liquidityContract` events.
- **Safety**:
  - Explicit casting for interfaces.
  - No inline assembly, high-level Solidity.
  - Try-catch for external calls.
  - Hidden state variables accessed via view functions.
  - Avoids reserved keywords, unnecessary virtual/override.
  - Graceful degradation with empty array returns.
