# CCLiquidityRouter Contract Documentation

## Overview
The `CCLiquidityRouter` contract, written in Solidity (^0.8.2), facilitates liquidity management on a decentralized trading platform. It handles deposits, withdrawals, fee claims, and long/short liquidation payouts, interacting with `ICCListing` and `ICCLiquidity` interfaces for listing and liquidity operations. Inheriting `CCLiquidityPartial` (which extends `CCMainPartial`), it leverages `ReentrancyGuard` for security and `Ownable` (via `ReentrancyGuard`) for administrative control. State variables are hidden, accessed via uniquely named view functions, and amounts are normalized to 1e18 decimals for precision. The contract avoids reserved keywords, uses explicit casting, and employs try-catch blocks for external calls, emitting detailed revert reasons for graceful degradation.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.0.8 (Updated 2025-07-31)

**Inheritance Tree**: `CCLiquidityRouter` → `CCLiquidityPartial` → `CCMainPartial`

**Compatibility**: `CCListingTemplate.sol` (v0.0.10), `CCMainPartial.sol` (v0.0.10), `CCLiquidityPartial.sol` (v0.0.11), `CCLiquidityTemplate.sol` (v0.0.16), `ICCLiquidity.sol` (v0.0.4), `ICCListing.sol` (v0.0.7), `CCAgent.sol` (v0.0.5).

## Design Principles
- **Modularity**: Separates concerns via inheritance (`CCLiquidityPartial` for payout logic, `CCMainPartial` for utilities).
- **Security**: Uses `nonReentrant` modifier, try-catch for external calls, and explicit interface casting.
- **Precision**: Normalizes amounts to 1e18 decimals, denormalizes for token-specific transfers.
- **Gas Efficiency**: Employs `maxIterations` for loops, dynamic array resizing, and helper functions.
- **Error Handling**: Captures revert reasons in try-catch blocks, emits events like `DepositTokenFailed` and `DepositNativeFailed`.

## Mappings
- **`payoutPendingAmounts`**: `mapping(address => mapping(uint256 => uint256))` (inherited from `CCLiquidityPartial`)
  - Tracks pending payout amounts per listing address and order ID, updated in `settleSingleLongLiquid`, `settleSingleShortLiquid`, `executeLongPayout`, and `executeShortPayout`.
  - Normalized to 1e18 decimals, decremented by `normalizedReceived` after successful transfers.
  - Accessed indirectly via `ICCListing` view functions (`longPayoutByIndexView`, `shortPayoutByIndexView`).

## Structs
- **PayoutContext** (in `CCLiquidityPartial`):
  - Fields: `listingAddress` (address), `liquidityAddr` (address), `tokenOut` (address), `tokenDecimals` (uint8), `amountOut` (uint256, denormalized), `recipientAddress` (address).
  - Purpose: Encapsulates payout data for `settleSingleLongLiquid`, `settleSingleShortLiquid`, `executeLongPayout`, and `executeShortPayout`.
- **ICCListing.PayoutUpdate**:
  - Fields: `payoutType` (uint8, 0=Long, 1=Short), `recipient` (address), `required` (uint256, normalized).
  - Purpose: Updates payout states in `ssUpdate` calls.
- **ICCListing.LongPayoutStruct**:
  - Fields: `makerAddress` (address), `recipientAddress` (address), `required` (uint256, normalized), `filled` (uint256, normalized), `orderId` (uint256), `status` (uint8).
  - Purpose: Tracks long payout details, fetched via `getLongPayout`.
- **ICCListing.ShortPayoutStruct**:
  - Fields: `makerAddress` (address), `recipientAddress` (address), `amount` (uint256, normalized), `filled` (uint256, normalized), `orderId` (uint256), `status` (uint8).
  - Purpose: Tracks short payout details, fetched via `getShortPayout`.
- **ICCLiquidity.PreparedWithdrawal**:
  - Fields: `amountA` (uint256, normalized), `amountB` (uint256, normalized).
  - Purpose: Returned by `xPrepOut`/`yPrepOut` for withdrawal preparation.
- **ICCLiquidity.Slot**:
  - Fields: `depositor` (address), `recipient` (address, unused), `allocation` (uint256, normalized), `dFeesAcc` (uint256), `timestamp` (uint256).
  - Purpose: Represents liquidity slot ownership and fee accumulation.
- **ICCLiquidity.UpdateType**:
  - Fields: `updateType` (uint8, 0=balance, 1=fees, 2=xSlot, 3=ySlot), `index` (uint256), `value` (uint256, normalized), `addr` (address), `recipient` (address, unused).
  - Purpose: Updates liquidity pool states via `update`.

## Formulas
1. **Payout Amount**:
   - **Formula**: `amountOut = denormalize(payout.required, tokenDecimals)` (long), `amountOut = denormalize(payout.amount, tokenDecimals)` (short).
   - **Used in**: `settleSingleLongLiquid`, `settleSingleShortLiquid`, `executeLongPayout`, `executeShortPayout`.
   - **Description**: Converts normalized amounts (1e18 decimals) to token-specific decimals for transfers, ensuring accurate payouts.

2. **Liquidity Check**:
   - **Formula**: `sufficient = isLong ? yAmount >= requiredAmount : xAmount >= requiredAmount`.
   - **Used in**: `_checkLiquidityBalance`.
   - **Description**: Verifies liquidity pool balances (`xAmount` for token A, `yAmount` for token B) against required payout amounts, preventing failed transfers.

3. **Transfer Tracking**:
   - **Formula**: `amountReceived = postBalance - preBalance`, `normalizedReceived = normalize(amountReceived, tokenDecimals)`.
   - **Used in**: `_transferNative`, `_transferToken`.
   - **Description**: Calculates actual tokens/ETH received by the recipient, normalized to 1e18 decimals for consistent state updates.

## External Functions
### depositNativeToken(address listingAddress, uint256 inputAmount, bool isTokenA)
- **Parameters**:
  - `listingAddress`: Address of the `ICCListing` contract.
  - `inputAmount`: ETH amount (18 decimals).
  - `isTokenA`: True for token A, false for token B.
- **Behavior**: Deposits ETH to the liquidity pool via `ICCLiquidity.depositNative`, supporting zero-balance pool initialization.
- **Internal Call Flow**:
  - Validates `msg.value == inputAmount`, `tokenAddress == address(0)` (via `listingContract.tokenA`/`tokenB`), and `isRouter(address(this))`.
  - Fetches `liquidityAmounts` to ensure zero-balance or valid side deposit (`xAmount` for token A, `yAmount` for token B).
  - Calls `depositNative` with `depositor=msg.sender`, using try-catch to capture revert reasons.
  - Emits `DepositNativeFailed` with `depositor`, `amount`, and `reason` on failure.
- **Balance Checks**: Verifies `msg.value` matches `inputAmount`, checks `xAmount`/`yAmount` for valid deposits.
- **Depositor Handling**: Passes `msg.sender` as `depositor` to `depositNative`, ensuring the caller's identity is recorded.
- **Restrictions**: `nonReentrant`, `onlyValidListing` (checks `ICCAgent.getListing`), requires router registration.
- **Gas Usage Controls**: Single external call, minimal state updates.

### depositToken(address listingAddress, uint256 inputAmount, bool isTokenA)
- **Parameters**: Same as `depositNativeToken`, with `inputAmount` in token decimals.
- **Behavior**: Deposits ERC20 tokens via `IERC20.transferFrom` and `ICCLiquidity.depositToken`, supporting zero-balance initialization.
- **Internal Call Flow**:
  - Validates `tokenAddress != address(0)`, `isRouter(address(this))`, and `IERC20.allowance`.
  - Transfers tokens from `msg.sender` to `this`, verifies received amount (`postBalance - preBalance`).
  - Approves tokens for `liquidityAddr`, calls `depositToken` with `depositor=msg.sender`.
  - Emits `TransferFailed` on `transferFrom` failure, `DepositTokenFailed` on `depositToken` failure.
- **Balance Checks**: Pre/post balance for `this`, allowance check to prevent underflow.
- **Depositor Handling**: Uses `msg.sender` as `depositor` in `depositToken`, ensuring accurate ownership tracking.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, requires router registration.
- **Gas Usage Controls**: Two external calls (`transferFrom`, `depositToken`), try-catch for both.

### withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX)
- **Parameters**:
  - `listingAddress`: Address of the `ICCListing` contract.
  - `inputAmount`: Normalized amount (1e18 decimals).
  - `index`: Slot index for withdrawal.
  - `isX`: True for token A, false for token B.
- **Behavior**: Withdraws liquidity via `xPrepOut`/`yPrepOut` and `xExecuteOut`/`yExecuteOut`.
- **Internal Call Flow**:
  - Validates `isRouter(address(this))` and `msg.sender != address(0)`.
  - Calls `xPrepOut`/`yPrepOut` with `depositor=msg.sender` to prepare withdrawal, returns `PreparedWithdrawal`.
  - Calls `xExecuteOut`/`yExecuteOut` with `depositor=msg.sender`, using try-catch for revert reasons.
- **Balance Checks**: Implicit in `xPrepOut`/`yPrepOut` (handled by `ICCLiquidity`).
- **Depositor Handling**: Passes `msg.sender` as `depositor` to ensure only the owner withdraws.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, requires router registration.
- **Gas Usage Controls**: Two external calls, minimal state changes.

### claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount)
- **Parameters**:
  - `listingAddress`: Address of the `ICCListing` contract.
  - `liquidityIndex`: Slot index for fee claim.
  - `isX`: True for token A, false for token B.
  - `volumeAmount`: Ignored for compatibility (no impact on logic).
- **Behavior**: Claims accumulated fees via `ICCLiquidity.claimFees`.
- **Internal Call Flow**:
  - Validates `isRouter(address(this))` and `msg.sender != address(0)`.
  - Calls `claimFees` with `depositor=msg.sender`, using try-catch to capture revert reasons.
- **Balance Checks**: Implicit in `claimFees` (handled by `ICCLiquidity`).
- **Depositor Handling**: Uses `msg.sender` as `depositor` to ensure only the slot owner claims fees.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, requires router registration.
- **Gas Usage Controls**: Single external call, no complex loops.

### changeDepositor(address listingAddress, bool isX, uint256 slotIndex, address newDepositor)
- **Parameters**:
  - `listingAddress`: Address of the `ICCListing` contract.
  - `isX`: True for token A, false for token B.
  - `slotIndex`: Slot index to reassign.
  - `newDepositor`: New owner address.
- **Behavior**: Reassigns slot ownership via `ICCLiquidity.changeSlotDepositor`.
- **Internal Call Flow**:
  - Validates `isRouter(address(this))`, `msg.sender != address(0)`, and `newDepositor != address(0)`.
  - Calls `changeSlotDepositor` with `depositor=msg.sender`, using try-catch for revert reasons.
- **Balance Checks**: None, as ownership transfer does not affect balances.
- **Depositor Handling**: Passes `msg.sender` as `depositor` to verify current ownership, assigns `newDepositor`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, requires router registration.
- **Gas Usage Controls**: Single external call, minimal gas usage.

### settleLongLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress`: Address of the `ICCListing` contract.
  - `maxIterations`: Maximum number of payouts to process.
- **Behavior**: Processes long liquidation payouts (token B) up to `maxIterations` via `ICCLiquidity`.
- **Internal Call Flow**:
  - Fetches `orderIdentifiers` via `longPayoutByIndexView`.
  - Iterates up to `maxIterations`, calling `settleSingleLongLiquid`:
    - Fetches `LongPayoutStruct`, sets status to 3 if `required == 0`, creates `PayoutUpdate` with `required=0`.
    - Builds `PayoutContext` via `_prepPayoutContext`, checks liquidity via `_checkLiquidityBalance`.
    - Transfers token B via `_transferNative`/`_transferToken` with `depositor=msg.sender`.
    - Updates `payoutPendingAmounts`, creates `PayoutUpdate`.
  - Resizes `tempUpdates` to `finalUpdates`, calls `listingContract.ssUpdate` (no `depositor`).
- **Balance Checks**: Pre/post balance in `_transferNative`/`_transferToken`, liquidity check in `_checkLiquidityBalance`.
- **Depositor Handling**: Passes `msg.sender` as `depositor` in `_transferNative`/`_transferToken` for `ICCLiquidity` calls, not used in `ssUpdate`.
- **Mappings/Structs Used**: `payoutPendingAmounts`, `PayoutContext`, `ICCListing.PayoutUpdate`, `ICCListing.LongPayoutStruct`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, requires router registration.
- **Gas Usage Controls**: `maxIterations` limits loop iterations, dynamic array resizing for `tempUpdates` and `finalUpdates`.

### settleShortLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongLiquid`.
- **Behavior**: Processes short liquidation payouts (token A) via `ICCLiquidity`.
- **Internal Call Flow**:
  - Fetches `orderIdentifiers` via `shortPayoutByIndexView`.
  - Iterates up to `maxIterations`, calling `settleSingleShortLiquid`:
    - Fetches `ShortPayoutStruct`, sets status to 3 if `amount == 0`, creates `PayoutUpdate` with `required=0`.
    - Builds `PayoutContext`, checks liquidity.
    - Transfers token A via `_transferNative`/`_transferToken` with `depositor=msg.sender`.
    - Updates `payoutPendingAmounts`, creates `PayoutUpdate`.
  - Resizes updates, calls `listingContract.ssUpdate` (no `depositor`).
- **Balance Checks**: Same as `settleLongLiquid`.
- **Depositor Handling**: Same as `settleLongLiquid`.
- **Mappings/Structs Used**: `payoutPendingAmounts`, `PayoutContext`, `ICCListing.PayoutUpdate`, `ICCListing.ShortPayoutStruct`.
- **Restrictions**: Same as `settleLongLiquid`.
- **Gas Usage Controls**: Same as `settleLongLiquid`.

### settleLongPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongLiquid`.
- **Behavior**: Executes long payouts (token B) via `listingContract`.
- **Internal Call Flow**:
  - Calls `executeLongPayouts`, iterates `longPayoutByIndexView`, calling `executeLongPayout`:
    - Fetches `LongPayoutStruct`, skips if `required == 0`.
    - Builds `PayoutContext`, transfers token B via `_transferNative`/`_transferToken` (no `depositor` in `listingContract` calls).
    - Updates `payoutPendingAmounts`, creates `PayoutUpdate`.
  - Resizes updates, calls `listingContract.ssUpdate` (no `depositor`).
- **Balance Checks**: Pre/post balance in `_transferNative`/`_transferToken`.
- **Depositor Handling**: No `depositor` in `listingContract` calls (`transactToken`/`transactNative`), unlike liquidation functions.
- **Mappings/Structs Used**: Same as `settleLongLiquid`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Gas Usage Controls**: `maxIterations`, dynamic array resizing.

### settleShortPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongLiquid`.
- **Behavior**: Executes short payouts (token A) via `listingContract`.
- **Internal Call Flow**:
  - Calls `executeShortPayouts`, iterates `shortPayoutByIndexView`, calling `executeShortPayout`:
    - Fetches `ShortPayoutStruct`, skips if `amount == 0`.
    - Builds `PayoutContext`, transfers token A via `_transferNative`/`_transferToken` (no `depositor`).
    - Updates `payoutPendingAmounts`, creates `PayoutUpdate`.
  - Resizes updates, calls `listingContract.ssUpdate` (no `depositor`).
- **Balance Checks**: Same as `settleLongLiquid`.
- **Depositor Handling**: Same as `settleLongPayouts`.
- **Mappings/Structs Used**: Same as `settleLongLiquid`.
- **Restrictions**: Same as `settleLongLiquid`.
- **Gas Usage Controls**: Same as `settleLongLiquid`.

## Clarifications and Nuances
- **Depositor Parameter Handling**:
  - **Purpose**: The `depositor` parameter, replacing `caller` in `ICCLiquidity.sol` (v0.0.4), identifies the user initiating actions (e.g., deposits, withdrawals, fee claims). It is consistently set to `msg.sender` in `CCLiquidityRouter.sol` to ensure actions are tied to the caller.
  - **Usage**: Passed in `depositNative`, `depositToken`, `withdraw`, `claimFees`, and `changeDepositor` to `ICCLiquidity` functions, ensuring ownership validation. In `settleLongLiquid` and `settleShortLiquid`, `depositor=msg.sender` is used in `_transferNative`/`_transferToken` calls to `ICCLiquidity.transactToken`/`transactNative`.
  - **Non-Usage in `addFees`**: The `addFees` function (`ICCLiquidity.addFees(address depositor, bool isX, uint256 fee)`) is not called in `CCLiquidityRouter.sol`. The `depositor` parameter in `addFees` is noted as unused in `ICCLiquidity.sol` but retained for interface consistency, suggesting potential use in other contracts (e.g., `CCLiquidityTemplate.sol`) or future router extensions.
  - **Payout Functions**: `settleLongPayouts` and `settleShortPayouts` use `listingContract` (`transactToken`/`transactNative`) without `depositor`, as `ICCListing` does not require it, unlike `ICCLiquidity` calls in liquidation functions.

- **Non-Usage of `addFees`**:
  - **Context**: `addFees` is defined in `ICCLiquidity` to update fee accumulations (`xFees` or `yFees`) but is not invoked in `CCLiquidityRouter.sol`. This suggests it is intended for other contracts or future functionality (e.g., trade execution updating fees).
  - **Implication**: Fee updates are likely handled by `CCLiquidityTemplate.sol` or other components. The router focuses on user-facing actions (deposits, withdrawals, payouts) and does not directly manage fee accumulation.
  - **Recommendation**: If fee updates are needed, a new function could be added to `CCLiquidityRouter.sol` to call `addFees` during liquidations or trades, passing `msg.sender` as `depositor`.

- **Payout Mechanics**:
  - **Long vs. Short**: Long payouts transfer token B (e.g., USDC for ETH/USDC pair), short payouts transfer token A (e.g., ETH). Liquidations (`settleLong/ShortLiquid`) use `ICCLiquidity`, while payouts (`settleLong/ShortPayouts`) use `listingContract`.
  - **Zero-Amount Payouts**: If `required` (long) or `amount` (short) is zero, the payout status is set to 3 (completed), and a `PayoutUpdate` with `required=0` is returned, ensuring state consistency.
  - **Liquidity Checks**: `_checkLiquidityBalance` ensures sufficient tokens before transfers, preventing failed transactions.

- **Decimal Handling**:
  - **Normalization**: `normalize` converts token amounts to 1e18 decimals for internal calculations (`payoutPendingAmounts`, `PayoutUpdate`).
  - **Denormalization**: `denormalize` converts amounts to token-specific decimals (via `decimalsA`/`decimalsB`) for transfers, supporting tokens with varying decimals (e.g., USDC at 6, ETH at 18).
  - **Accuracy**: Pre/post balance checks in `_transferNative`/`_transferToken` handle fee-on-transfer tokens and ETH edge cases.

- **Gas Optimization**:
  - **Loop Control**: `maxIterations` caps iterations in `settleLong/ShortLiquid` and `settleLong/ShortPayouts`, preventing gas limit issues.
  - **Array Resizing**: Uses `tempUpdates` and `finalUpdates` to dynamically resize arrays, minimizing gas for empty or skipped payouts.
  - **Helper Functions**: `_prepPayoutContext`, `_checkLiquidityBalance`, `_transferNative`, and `_transferToken` reduce code duplication and optimize external call handling.

- **Security Measures**:
  - **Reentrancy Protection**: `nonReentrant` modifier prevents reentrancy attacks on all state-changing functions.
  - **Listing Validation**: `onlyValidListing` uses `ICCAgent.getListing` to verify `listingAddress` against `tokenA` and `tokenB`.
  - **Error Handling**: Try-catch blocks capture revert reasons for all external calls (`transferFrom`, `depositNative`, `depositToken`, `xPrepOut`/`yPrepOut`, `xExecuteOut`/`yExecuteOut`, `claimFees`, `changeSlotDepositor`, `transactToken`/`transactNative`), emitting events like `TransferFailed`, `DepositTokenFailed`, and `DepositNativeFailed`.
  - **Explicit Casting**: Interfaces (`ICCListing`, `ICCLiquidity`, `IERC20`) are explicitly cast to avoid type errors.
  - **No Inline Assembly**: Uses Solidity for array resizing and operations, enhancing readability and safety.
  - **Hidden State Variables**: `payoutPendingAmounts`, `agent`, and `uniswapV2Router` are internal, accessed via view functions (`agentView`, `uniswapV2RouterView`).

- **Limitations**:
  - **No `addFees` Usage**: The router does not update fees, limiting its role to user actions rather than fee management.
  - **No Uniswap V2 Integration**: Relies on `ICCLiquidity` for liquidity operations, with `uniswapV2Router` settable but unused.
  - **Liquidity Dependency**: Payouts fail (return empty updates) if liquidity is insufficient, requiring external liquidity provision.
  - **Ignored Parameter**: `volumeAmount` in `claimFees` is unused, retained for interface compatibility.

## Additional Details
- **Events**:
  - `TransferFailed(address sender, address token, uint256 amount, bytes reason)`: Emitted on failed `transferFrom`, `transactToken`, or `transactNative` (inherited from `CCLiquidityPartial`).
  - `InsufficientAllowance(address sender, address token, uint256 required, uint256 available)`: Emitted on insufficient `IERC20.allowance` (inherited).
  - `DepositTokenFailed(address depositor, address token, uint256 amount, string reason)`: Emitted on failed `depositToken`.
  - `DepositNativeFailed(address depositor, uint256 amount, string reason)`: Emitted on failed `depositNative`.
- **Safety**:
  - Avoids reserved keywords and unnecessary `virtual`/`override`.
  - Uses explicit casting for all interface interactions.
  - Ensures no inline assembly, prioritizing Solidity for clarity.
  - Provides detailed revert strings via try-catch for debugging.
- **Compatibility**: Fully aligned with `CCListingTemplate.sol` (v0.0.10), `CCMainPartial.sol` (v0.0.10), `CCLiquidityPartial.sol` (v0.0.11), `CCLiquidityTemplate.sol` (v0.0.16), `ICCLiquidity.sol` (v0.0.4), `ICCListing.sol` (v0.0.7), `CCAgent.sol` (v0.0.5).
- **Testing Note**: `ICCLiquidity.addFees` is not used.
