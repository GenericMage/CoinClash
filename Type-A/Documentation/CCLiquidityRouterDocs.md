# CCLiquidityRouter Contract Documentation

## Overview
The `CCLiquidityRouter` contract, implemented in Solidity (`^0.8.2`), serves as a specialized router for managing liquidity operations and payouts on a decentralized trading platform. It inherits functionality from `SSSettlementPartial`, which extends `SSOrderPartial` and `SSMainPartial`, and integrates with external interfaces (`ISSListingTemplate`, `ISSLiquidityTemplate`, `IERC20`) for token operations, `ReentrancyGuard` for reentrancy protection, and `SafeERC20` for secure token transfers. The contract focuses on liquidity management (`deposit`, `withdraw`, `claimFees`, `changeDepositor`) and payout settlement (`settleLongPayouts`, `settleShortPayouts`, `settleLongLiquid`, `settleShortLiquid`), leveraging inherited functions for payout processing. State variables are hidden, accessed via view functions with unique names, and decimal precision is maintained across tokens. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.2 (updated 2025-07-16)

**Inheritance Tree:** `CCLiquidityRouter` → `SSSettlementPartial` → `SSOrderPartial` → `SSMainPartial`

## Mappings
- None defined directly in `CCLiquidityRouter`. Inherits mappings indirectly via `SSSettlementPartial`, `SSOrderPartial`, and `SSMainPartial`, but relies on `ISSListingTemplate` and `ISSLiquidityTemplate` view functions (e.g., `liquidityAddressView`, `routers`, `longPayoutByIndexView`, `shortPayoutByIndexView`) for liquidity and payout tracking.

## Structs
- **PreparedWithdrawal**: Contains fields defined in `ISSLiquidityTemplate` for withdrawal preparation (e.g., amount, token, recipient). Used in `withdraw`.
- **PayoutUpdate**: Contains `index` (uint256, payout order ID), `amount` (uint256, denormalized), `recipient` (address). Defined in `ISSListingTemplate`. Used in `settleLongLiquid` and `settleShortLiquid`.

## External Functions

### deposit(address listingAddress, bool isTokenA, uint256 inputAmount, address user)
- **Parameters**:
  - `listingAddress` (address): Listing contract address; must match `_listingAddress` in `liquidityContract`.
  - `isTokenA` (bool): True for tokenA (e.g., LINK), false for tokenB (e.g., USD) or ETH (address(0)).
  - `inputAmount` (uint256): Deposit amount (denormalized).
  - `user` (address): User depositing liquidity; must be non-zero.
- **Behavior**: Deposits ERC-20 tokens or ETH to the liquidity pool on behalf of `user`, transferring tokens from `msg.sender` to `this`, then to `liquidityAddr`, updating `_xLiquiditySlots` or `_yLiquiditySlots` and `_liquidityDetail`.
- **Internal Call Flow**:
  - Validates `isTokenA` to select tokenA or tokenB via `listingContract.tokenA()` or `tokenB()`.
  - For ETH (tokenAddress == address(0)):
    - Checks `msg.value == inputAmount`.
    - Calls `liquidityContract.deposit` with value transfer.
  - For ERC-20 tokens:
    - Transfers tokens via `IERC20.safeTransferFrom` from `msg.sender` to `this`, with pre/post balance checks.
    - Approves `liquidityAddr` and calls `liquidityContract.deposit(user, tokenAddress, receivedAmount)`.
  - `liquidityContract.deposit`:
    - Validates `token` as `_tokenA` or `_tokenB`.
    - Transfers tokens to `liquidityContract`, normalizes amount, and updates slots via `update`.
    - Calls `globalizeUpdate` (to `ISSAgent.globalizeLiquidity`) and `updateRegistry` (to `ITokenRegistry.initializeBalances`).
  - Transfer destinations: `this` (from `msg.sender`), `liquidityAddr` (from `this` or ETH value).
- **Balance Checks**:
  - Pre/post balance checks for ERC-20 tokens ensure `postBalance > preBalance`, computing `receivedAmount` to handle fee-on-transfer tokens.
  - ETH deposits verify `msg.value == inputAmount`.
- **Mappings/Structs Used**: None in `CCLiquidityRouter`; `liquidityContract` uses `UpdateType`, `_xLiquiditySlots`, `_yLiquiditySlots`, `_liquidityDetail`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing` (uses `ISSAgent.validateListing`).
  - Requires router registration in `liquidityContract.routers(address(this))`.
  - Reverts if `user` is zero, `listingAddress` is invalid, token is invalid, `msg.value` mismatches for ETH, or deposit fails (`"Deposit failed"`).
- **Gas Usage Controls**: Single transfer and call, minimal state writes, try-catch for external calls.
- **External Dependencies**: `liquidityContract.deposit` calls `ISSAgent.globalizeLiquidity` and `ITokenRegistry.initializeBalances`, handled with try-catch.

### withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX)
- **Parameters**:
  - `listingAddress` (address): Listing contract address; must match `_listingAddress` in `liquidityContract`.
  - `inputAmount` (uint256): Withdrawal amount (denormalized).
  - `index` (uint256): Slot index in `_xLiquiditySlots` or `_yLiquiditySlots`.
  - `isX` (bool): True for tokenA (e.g., LINK), false for tokenB (e.g., USD) or ETH.
- **Behavior**: Withdraws liquidity from the pool for `msg.sender`, restricted to the slot’s depositor, preparing withdrawal with `xPrepOut` or `yPrepOut` (compensating with the opposite token if needed using `ISSListingTemplate.getPrice`), then executing via `xExecuteOut` or `yExecuteOut`.
- **Internal Call Flow**:
  - Validates `msg.sender` as non-zero.
  - Calls `xPrepOut` or `yPrepOut` with `msg.sender` to prepare `PreparedWithdrawal`:
    - Validates `msg.sender` as slot depositor and `inputAmount` against slot allocation.
    - Fetches price via `ISSListingTemplate.getPrice` for compensation.
  - Calls `xExecuteOut` or `yExecuteOut` with `msg.sender`:
    - Updates slot allocation via `update` (1 `UpdateType`).
    - Transfers tokens via `IERC20.safeTransfer` or ETH value transfer.
    - Calls `globalizeUpdate` (to `ISSAgent.globalizeLiquidity`) and `updateRegistry` (to `ITokenRegistry.initializeBalances`).
  - Transfer destination: `msg.sender` (withdrawn tokens or ETH).
- **Balance Checks**: None in `CCLiquidityRouter`; `liquidityContract` checks liquidity availability and uses try-catch for price and external calls.
- **Mappings/Structs Used**: `PreparedWithdrawal`, `UpdateType` in `liquidityContract`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract.routers(address(this))`.
  - Reverts if `msg.sender` is zero, not the slot depositor, `listingAddress` is invalid, `inputAmount` exceeds allocation, price fetch fails, or transfers fail (`"Withdrawal preparation failed"`, `"Withdrawal execution failed"`).
- **Gas Usage Controls**: Two external calls (prep, execute), minimal updates (1 `UpdateType`), try-catch for external calls.
- **External Dependencies**: `liquidityContract` calls `ISSListingTemplate.getPrice`, `ISSAgent.globalizeLiquidity`, and `ITokenRegistry.initializeBalances`, handled with try-catch.

### claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount)
- **Parameters**:
  - `listingAddress` (address): Listing contract address; must match `_listingAddress` in `liquidityContract`.
  - `liquidityIndex` (uint256): Slot index in `_xLiquiditySlots` or `_yLiquiditySlots`.
  - `isX` (bool): True for tokenA slot (e.g., LINK, claims yFees in tokenB), false for tokenB slot (e.g., USD/ETH, claims xFees in tokenA).
  - `volumeAmount` (uint256): Unused (legacy parameter, volume fetched from `volumeBalanceView`).
- **Behavior**: Claims fees for the slot for `msg.sender`, restricted to the slot’s depositor, converting fees to the provider’s token value (xSlots claim yFees in tokenB/ETH, ySlots claim xFees in tokenA) using `ISSListingTemplate.getPrice`, transferring the converted amount to `msg.sender`.
- **Internal Call Flow**:
  - Validates `msg.sender` as non-zero and `listingAddress`.
  - Calls `liquidityContract.claimFees(msg.sender, listingAddress, liquidityIndex, isX, volumeAmount)`:
    - Validates `msg.sender` as the slot depositor.
    - Fetches volume via `ISSListingTemplate.volumeBalanceView` and price via `ISSListingTemplate.getPrice`.
    - Calls `_processFeeClaim` with `FeeClaimContext`:
      - Computes fee share based on slot allocation and volume.
      - Updates fees and slot via `update` (2 `UpdateType`).
      - Transfers converted fees via `IERC20.safeTransfer` or ETH value transfer.
  - Transfer destination: `msg.sender` (converted fee amount or ETH).
- **Balance Checks**: None in `CCLiquidityRouter`; `liquidityContract` uses try-catch for volume and price fetches.
- **Mappings/Structs Used**: `UpdateType`, `FeeClaimContext` in `liquidityContract`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract.routers(address(this))`.
  - Reverts if `msg.sender` is zero, not the slot depositor, `listingAddress` is invalid, volume fetch fails, or price is zero (`"Price cannot be zero"`).
- **Gas Usage Controls**: Two external calls (volume, price), minimal updates (2 `UpdateType`), try-catch for robustness.
- **External Dependencies**: `liquidityContract` calls `ISSListingTemplate.volumeBalanceView` and `ISSListingTemplate.getPrice`, handled with try-catch.

### changeDepositor(address listingAddress, bool isX, uint256 slotIndex, address newDepositor)
- **Parameters**:
  - `listingAddress` (address): Listing contract address; must match `_listingAddress` in `liquidityContract`.
  - `isX` (bool): True for tokenA slot (e.g., LINK), false for tokenB slot (e.g., USD/ETH).
  - `slotIndex` (uint256): Slot index in `_xLiquiditySlots` or `_yLiquiditySlots`.
  - `newDepositor` (address): New slot owner; must be non-zero.
- **Behavior**: Changes the depositor for a liquidity slot for `msg.sender`, restricted to the slot’s depositor, updating `_userIndex` in `liquidityContract`.
- **Internal Call Flow**:
  - Validates `msg.sender` and `newDepositor` as non-zero.
  - Calls `liquidityContract.changeSlotDepositor(msg.sender, isX, slotIndex, newDepositor)`:
    - Validates `msg.sender` as the slot depositor and `newDepositor` as non-zero.
    - Updates slot depositor and `_userIndex`.
- **Balance Checks**: None, handled by `liquidityContract`.
- **Mappings/Structs Used**: None in `CCLiquidityRouter`; `liquidityContract` uses `_userIndex`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract.routers(address(this))`.
  - Reverts if `msg.sender` or `newDepositor` is zero, `msg.sender` is not the slot depositor, `listingAddress` is invalid, or slot allocation is zero (`"Invalid slot"`).
- **Gas Usage Controls**: Minimal, single external call and array operations.
- **External Dependencies**: None beyond `liquidityContract.changeSlotDepositor`.

### settleLongLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Settles long position liquidations, transferring tokenB (e.g., USD/ETH) to holders, up to `maxIterations`.
- **Internal Call Flow**:
  - Iterates `longPayoutByIndexView[]` up to `maxIterations`.
  - Calls `settleSingleLongLiquid` (inherited):
    - Fetches payout details via `longPayoutDetailsView`.
    - Transfers `amount` via `liquidityContract.transact`.
    - Creates `PayoutUpdate[]` with payout details.
  - Collects updates in `tempPayoutUpdates`, resizing to `finalPayoutUpdates` for non-zero updates.
  - Applies `finalPayoutUpdates[]` via `listingContract.ssUpdate`.
  - Transfer destination: `recipient` (tokenB or ETH).
- **Balance Checks**:
  - Try-catch in `settleSingleLongLiquid` ensures transfer success, returning empty array on failure.
- **Mappings/Structs Used**:
  - **Structs**: `PayoutUpdate` (from `ISSListingTemplate`).
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract.routers(address(this))`.
  - Skips orders with zero amount.
- **Gas Usage Controls**: `maxIterations` limits iteration, dynamic array resizing, try-catch for robustness.
- **External Dependencies**: `liquidityContract.transact` and `listingContract.ssUpdate`.

### settleShortLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongLiquid`.
- **Behavior**: Settles short position liquidations, transferring tokenA (e.g., LINK) to holders, up to `maxIterations`.
- **Internal Call Flow**:
  - Similar to `settleLongLiquid`, using `shortPayoutByIndexView[]` and `settleSingleShortLiquid` (inherited).
- **Balance Checks**: Same as `settleLongLiquid`.
- **Mappings/Structs Used**: Same as `settleLongLiquid`.
- **Restrictions**: Same as `settleLongLiquid`.
- **Gas Usage Controls**: Same as `settleLongLiquid`.
- **External Dependencies**: Same as `settleLongLiquid`.

### settleLongPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Executes long position payouts, transferring tokenB (e.g., USD/ETH) to holders, up to `maxIterations`.
- **Internal Call Flow**:
  - Calls `executeLongPayouts` (inherited):
    - Iterates `longPayoutByIndexView[]` up to `maxIterations`.
    - Calls `settleSingleLongLiquid` for each order.
    - Collects and applies `PayoutUpdate[]` via `listingContract.ssUpdate`.
  - Transfer destination: `recipient` (tokenB or ETH).
- **Balance Checks**: Same as `settleLongLiquid`.
- **Mappings/Structs Used**: Same as `settleLongLiquid`.
- **Restrictions**: Same as `settleLongLiquid`.
- **Gas Usage Controls**: Same as `settleLongLiquid`.
- **External Dependencies**: Same as `settleLongLiquid`.

### settleShortPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongPayouts`.
- **Behavior**: Executes short position payouts, transferring tokenA (e.g., LINK) to holders, up to `maxIterations`.
- **Internal Call Flow**:
  - Calls `executeShortPayouts` (inherited), using `shortPayoutByIndexView[]` and `settleSingleShortLiquid`.
- **Balance Checks**: Same as `settleLongLiquid`.
- **Mappings/Structs Used**: Same as `settleLongLiquid`.
- **Restrictions**: Same as `settleLongLiquid`.
- **Gas Usage Controls**: Same as `settleLongLiquid`.
- **External Dependencies**: Same as `settleLongLiquid`.

### setAgent(address newAgent)
- **Parameters**:
  - `newAgent` (address): New ISSAgent address.
- **Behavior**: Updates `agent` state variable for listing validation, inherited from `SSMainPartial`.
- **Internal Call Flow**: Direct state update, validates `newAgent` is non-zero. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **agent** (state variable): Stores ISSAgent address.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `newAgent` is zero (`"Invalid agent address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

## Clarifications and Nuances

### Token Handling and Decimal Normalization
- **Normalization**: The contract uses `normalize` and `denormalize` (inherited from `SSMainPartial`) to handle token amounts, normalizing to 18 decimals for internal consistency and denormalizing for transfers based on token decimals (via `IERC20.decimals` or 18 for ETH).
- **ETH Handling**: Supports ETH deposits and withdrawals when `tokenAddress == address(0)`, using `msg.value` for deposits and value transfers for withdrawals, with checks to ensure `msg.value == inputAmount`.
- **Fee Conversion**: In `claimFees`, fees are converted using `ISSListingTemplate.getPrice` (xSlots claim yFees in tokenB/ETH, ySlots claim xFees in tokenA), ensuring accurate value transfers.

### Liquidity Management
- **Deposits**: `deposit` allows any valid `user` to deposit via `msg.sender`, with no depositor restriction, enabling flexible liquidity provision.
- **Withdrawals**: `withdraw` restricts actions to `msg.sender` as the slot’s depositor, using `xPrepOut`/`yPrepOut` to compensate with the opposite token if needed, ensuring balanced liquidity removal.
- **Fee Claims**: `claimFees` restricts claims to `msg.sender` as the slot’s depositor, using `volumeBalanceView` and `getPrice` for accurate fee calculations.
- **Depositor Changes**: `changeDepositor` restricts updates to `msg.sender` as the slot’s depositor, ensuring only authorized users can transfer ownership.

### Payout Processing
- **Long Payouts**: Transfer tokenB (e.g., USD/ETH) to holders, used in both `settleLongLiquid` and `settleLongPayouts`.
- **Short Payouts**: Transfer tokenA (e.g., LINK) to holders, used in `settleShortLiquid` and `settleShortPayouts`.
- **Graceful Degradation**: Zero-amount payouts return empty `PayoutUpdate[]` arrays, ensuring no state changes on failure.

### Gas Optimization
- **Max Iterations**: `settleLongLiquid`, `settleShortLiquid`, `settleLongPayouts`, and `settleShortPayouts` use `maxIterations` to limit loop iterations, preventing gas limit issues.
- **Dynamic Arrays**: `tempPayoutUpdates` is resized to `finalPayoutUpdates` to include only non-zero updates, reducing gas costs.
- **Minimal Updates**: Each payout uses a single `PayoutUpdate`, minimizing state writes.

### Security Measures
- **Reentrancy Protection**: All external functions are protected by `nonReentrant`, preventing reentrancy attacks.
- **Listing Validation**: The `onlyValidListing` modifier ensures `listingAddress` is registered with the `ISSAgent` contract, preventing interactions with unverified listings.
- **Router Restriction**: Functions interacting with `liquidityContract` require `routers(address(this))` to be true, ensuring only registered routers can call these functions.
- **Safe Transfers**: `SafeERC20.safeTransferFrom` is used for ERC-20 token transfers, handling non-standard tokens. ETH transfers use value checks.
- **Balance Checks**: Pre/post balance checks in `deposit` for ERC-20 tokens ensure accurate `receivedAmount`. Try-catch blocks handle external call failures (e.g., `deposit`, `withdraw`, `claimFees`).
- **Depositor Restriction**: `withdraw`, `claimFees`, and `changeDepositor` restrict actions to `msg.sender` as the slot’s depositor, preventing unauthorized access.

### Limitations and Assumptions
- **No Order Creation/Settlement**: Unlike `SSRouter` or `CCOrderRouter`, `CCLiquidityRouter` does not handle order creation (`createBuyOrder`, `createSellOrder`) or settlement (`settleBuyOrders`, `settleSellOrders`, `settleBuyLiquid`, `settleSellLiquid`), focusing solely on liquidity and payouts.
- **ETH Support**: Assumes `tokenA` or `tokenB` can be address(0) for ETH, with specific handling for value transfers.
- **Fee Volume**: `volumeAmount` in `claimFees` is unused, relying on `volumeBalanceView` for actual volume data, maintaining compatibility with `SSRouter`.
- **No Direct State**: Relies on `liquidityContract` and `listingContract` for state management, minimizing local storage.

### Differences from SSRouter
- **Scope**: `CCLiquidityRouter` is a subset of `SSRouter`, focusing on liquidity management and payout settlement, omitting order creation and settlement.
- **Inheritance**: Inherits `SSSettlementPartial` for payout functions, unlike `CCOrderRouter`, which inherits `SSOrderPartial` for order management.
- **Functionality**: Includes `deposit`, `withdraw`, `claimFees`, `changeDepositor`, `settleLongLiquid`, `settleShortLiquid`, `settleLongPayouts`, and `settleShortPayouts`, but lacks order-related functions present in `SSRouter`.
- **Gas Efficiency**: More lightweight than `SSRouter` due to focused functionality, but heavier than `CCOrderRouter` due to payout and liquidity operations.

## Additional Details
- **Decimal Handling**: Relies on `normalize` and `denormalize` from `SSMainPartial` for consistent precision (1e18). Token decimals are fetched via `IERC20.decimals` or set to 18 for ETH.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant` modifier.
- **Gas Optimization**: Uses `maxIterations` for payout functions, dynamic arrays for updates, and efficient balance checks in `deposit`.
- **Listing Validation**: Uses `onlyValidListing` modifier with `ISSAgent.validateListing` checks to ensure listing integrity.
- **Token Usage**:
  - Deposits/Withdrawals: Support tokenA (e.g., LINK), tokenB (e.g., USD), or ETH (address(0)).
  - Long payouts: Output tokenB (e.g., USD/ETH), no `amountSent`.
  - Short payouts: Output tokenA (e.g., LINK), no `amountSent`.
- **Events**: No events defined; relies on `listingContract` and `liquidityContract` events for logging.
- **Safety**:
  - Explicit casting for interfaces (e.g., `ISSListingTemplate(listingAddress)`, `ISSLiquidityTemplate(liquidityAddr)`).
  - No inline assembly, using high-level Solidity for safety.
  - Try-catch blocks in `deposit`, `withdraw`, `claimFees`, and payout functions for robust external call handling.
  - Hidden state variables (e.g., `agent`) accessed via `agentView`.
  - Avoids reserved keywords and unnecessary virtual/override modifiers.
  - Depositor-only restrictions in `withdraw`, `claimFees`, and `changeDepositor` prevent unauthorized access.
  - Graceful degradation with empty array returns on failure (e.g., `settleSingleLongLiquid`).