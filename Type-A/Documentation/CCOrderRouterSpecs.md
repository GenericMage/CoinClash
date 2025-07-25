# CCOrderRouter Contract Documentation

## Overview
The `CCOrderRouter` contract, implemented in Solidity (`^0.8.2`), serves as a streamlined router for creating and canceling buy and sell orders on a decentralized trading platform. It inherits functionality from `CCOrderPartial`, which extends `CCMainPartial`, and integrates with external interfaces (`ICCListing`, `IERC20`) for token operations, `ReentrancyGuard` for reentrancy protection, and `SafeERC20` for secure token transfers. The contract focuses on order creation (`createTokenBuyOrder`, `createNativeBuyOrder`, `createTokenSellOrder`, `createNativeSellOrder`) and cancellation (`clearSingleOrder`, `clearOrders`), leveraging inherited functions for order preparation and execution. State variables are hidden, accessed via view functions with unique names, and decimal precision is maintained across tokens. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.5 (updated 2025-07-25)

**Inheritance Tree:** `CCOrderRouter` → `CCOrderPartial` → `CCMainPartial`

## Mappings
- None defined directly in `CCOrderRouter`. Inherits mappings indirectly via `CCOrderPartial` and `CCMainPartial`, but relies on `ICCListing` view functions (e.g., `makerPendingOrdersView`) for order tracking.

## Structs
- **OrderPrep**: Contains `maker` (address), `recipient` (address), `amount` (uint256, normalized), `maxPrice` (uint256), `minPrice` (uint256), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256). Defined in `CCOrderPartial.sol`.

## External Functions

### createTokenBuyOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `recipientAddress` (address): Order recipient.
  - `inputAmount` (uint256): Input amount (denormalized, tokenB, ERC20).
  - `maxPrice` (uint256): Maximum price (normalized).
  - `minPrice` (uint256): Minimum price (normalized).
- **Behavior**: Creates a buy order for ERC20 tokenB, transferring tokens to the listing contract, normalizing amounts, and initializing `amountSent=0`.
- **Internal Call Flow**:
  - Calls `_handleOrderPrep` (inherited) to validate inputs and create `OrderPrep` struct, normalizing `inputAmount` using `listingContract.decimalsB`.
  - Verifies `tokenB != address(0)` (ERC20 requirement).
  - Calls `_checkTransferAmountToken` to transfer `inputAmount` in tokenB from `msg.sender` to `listingAddress` via `IERC20.safeTransferFrom`, with pre/post balance checks.
  - Calls `_executeSingleOrder` (inherited) to fetch `getNextOrderId`, create `UpdateType[]` for pending order status, pricing, and amounts (with `amountSent=0`), and invoke `listingContract.update`.
  - Transfer destination: `listingAddress`.
- **Balance Checks**:
  - Pre-balance check captures `listingAddress` balance before transfer.
  - Post-balance check ensures `postBalance > preBalance`, computes `amountReceived`, and normalizes to `normalizedReceived`.
- **Mappings/Structs Used**:
  - **Structs**: `OrderPrep`, `UpdateType` (from `ICCListing`).
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Reverts if `maker`, `recipient`, or `amount` is invalid, `tokenB` is native, or transfer fails (`"No tokens received"`).
- **Gas Usage Controls**: Single transfer, minimal array updates (3 `UpdateType` elements).

### createNativeBuyOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**: Same as `createTokenBuyOrder`, but for native ETH input (tokenB).
- **Behavior**: Creates a buy order for native ETH, transferring ETH to the listing contract, normalizing amounts, and initializing `amountSent=0`.
- **Internal Call Flow**:
  - Similar to `createTokenBuyOrder`, using `_checkTransferAmountNative` to verify `msg.value == inputAmount` and transfer ETH via `listingContract.transactNative`.
  - Verifies `tokenB == address(0)` (native ETH requirement).
  - Calls `_executeSingleOrder` for order creation.
- **Balance Checks**: Same as `createTokenBuyOrder`, with ETH balance checks.
- **Mappings/Structs Used**: Same as `createTokenBuyOrder`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Reverts if `tokenB` is not native, `msg.value != inputAmount` (`"Incorrect ETH amount"`), or transfer fails (`"No ETH received"`).
- **Gas Usage Controls**: Same as `createTokenBuyOrder`.

### createTokenSellOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**: Same as `createTokenBuyOrder`, but for sell orders with tokenA input (ERC20).
- **Behavior**: Creates a sell order for ERC20 tokenA, transferring tokens to the listing contract, normalizing amounts, and initializing `amountSent=0`.
- **Internal Call Flow**:
  - Similar to `createTokenBuyOrder`, using tokenA and `listingContract.decimalsA` for normalization.
  - Verifies `tokenA != address(0)` (ERC20 requirement).
  - Calls `_checkTransferAmountToken` for tokenA transfer.
  - Calls `_executeSingleOrder` for sell-specific `UpdateType[]`.
- **Balance Checks**: Same as `createTokenBuyOrder`.
- **Mappings/Structs Used**: Same as `createTokenBuyOrder`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Reverts if `tokenA` is native or transfer fails.
- **Gas Usage Controls**: Same as `createTokenBuyOrder`.

### createNativeSellOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**: Same as `createTokenBuyOrder`, but for sell orders with native ETH input (tokenA).
- **Behavior**: Creates a sell order for native ETH, transferring ETH to the listing contract, normalizing amounts, and initializing `amountSent=0`.
- **Internal Call Flow**:
  - Similar to `createNativeBuyOrder`, using tokenA and `_checkTransferAmountNative`.
  - Verifies `tokenA == address(0)` (native ETH requirement).
  - Calls `_executeSingleOrder` for sell-specific `UpdateType[]`.
- **Balance Checks**: Same as `createNativeBuyOrder`.
- **Mappings/Structs Used**: Same as `createTokenBuyOrder`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Reverts if `tokenA` is not native or transfer fails.
- **Gas Usage Controls**: Same as `createTokenBuyOrder`.

### clearSingleOrder(address listingAddress, uint256 orderIdentifier, bool isBuyOrder)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `orderIdentifier` (uint256): Order ID.
  - `isBuyOrder` (bool): True for buy, false for sell.
- **Behavior**: Cancels a single order, refunding pending amounts to `recipientAddress`, restricted to the order’s maker via `_clearOrderData`.
- **Internal Call Flow**:
  - Calls `_clearOrderData` (inherited):
    - Retrieves order data via `getBuyOrderCore` or `getSellOrderCore`, and `getBuyOrderAmounts` or `getSellOrderAmounts` (including `amountSent`).
    - Verifies `msg.sender` is the maker, reverts if not (`"Only maker can cancel"`).
    - Refunds pending amount via `listingContract.transactToken` (ERC20) or `transactNative` (ETH), using denormalized amount based on `decimalsB` (buy) or `decimalsA` (sell).
    - Sets status to 0 (cancelled) via `listingContract.update` with `UpdateType[]`.
  - Transfer destination: `recipientAddress`.
- **Balance Checks**:
  - `_clearOrderData` uses conditional checks for refund transfers (no try-catch, returns bool), reverting if transfer fails (`"Token refund failed"`, `"Native refund failed"`).
- **Mappings/Structs Used**:
  - **Structs**: `UpdateType` (from `ICCListing`).
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Reverts if `msg.sender` is not the maker, refund fails, or order is not pending (status != 1 or 2).
- **Gas Usage Controls**: Single transfer and update, minimal array (1 `UpdateType`).

### clearOrders(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Cancels pending buy and sell orders for `msg.sender` up to `maxIterations`, refunding pending amounts to `recipientAddress`.
- **Internal Call Flow**:
  - Fetches `orderIds` via `listingContract.makerPendingOrdersView(msg.sender)`.
  - Iterates up to `maxIterations`:
    - For each `orderId`, checks if `msg.sender` is the maker via `getBuyOrderCore` or `getSellOrderCore`.
    - Calls `_clearOrderData` for valid orders, refunding pending amounts (tokenB for buy, tokenA for sell) and setting status to 0.
  - Transfer destination: `recipientAddress`.
- **Balance Checks**:
  - Same as `clearSingleOrder`, handled by `_clearOrderData` with conditional checks.
- **Mappings/Structs Used**:
  - **Structs**: `UpdateType` (from `ICCListing`).
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Skips orders where `msg.sender` is not the maker or if order is not pending.
  - Reverts if refund fails in `_clearOrderData`.
- **Gas Usage Controls**: `maxIterations` limits iteration, minimal updates per order (1 `UpdateType`).

### setAgent(address newAgent)
- **Parameters**:
  - `newAgent` (address): New ICCAgent address.
- **Behavior**: Updates `agent` state variable for listing validation, inherited from `CCMainPartial`.
- **Internal Call Flow**: Direct state update, validates `newAgent` is non-zero. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **agent** (state variable): Stores ICCAgent address.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `newAgent` is zero (`"Invalid agent address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

## Clarifications and Nuances

### Token Handling and Decimal Normalization
- **Normalization**: The contract normalizes token amounts to 18 decimals using the `normalize` function (inherited from `CCMainPartial`) to ensure consistent precision across tokens with varying decimals (e.g., USDC with 6 decimals, ETH with 18 decimals). For buy orders, `inputAmount` (tokenB) is normalized using `decimalsB`; for sell orders, `inputAmount` (tokenA) uses `decimalsA`.
- **Denormalization**: Refunds in `clearSingleOrder` and `clearOrders` are denormalized to the token’s native decimals (via `denormalize`) to ensure accurate transfers to `recipientAddress`.
- **ETH Handling**: For native ETH (address(0)), `createNativeBuyOrder` and `createNativeSellOrder` check `msg.value == inputAmount` and use `listingContract.transactNative`, ensuring compatibility with ETH-based listings.

### Order Creation Mechanics
- **Input Validation**: `_handleOrderPrep` enforces non-zero `maker`, `recipient`, and `amount`, preventing invalid orders from being processed.
- **Amount Tracking**: `amountReceived` (denormalized) and `normalizedReceived` (normalized to 1e18) are computed in `_checkTransferAmountToken` or `_checkTransferAmountNative` to handle fee-on-transfer tokens or ETH, ensuring the actual received amount is tracked accurately.
- **Order Initialization**: `_executeSingleOrder` initializes orders with `amountSent=0`, as `CCOrderRouter` focuses on order creation, not settlement. Settlement (tracking `amountSent`) is handled by other contracts.

### Order Cancellation
- **Maker Restriction**: Only the order’s maker (`msg.sender == maker`) can cancel orders via `_clearOrderData`, ensuring no unauthorized cancellations.
- **Pending Amount Refunds**: Refunds are issued only for orders with `pending > 0` and status 1 (pending) or 2 (partially filled). The refund amount is denormalized based on token decimals (tokenB for buy, tokenA for sell).
- **Graceful Degradation**: If a refund fails, `_clearOrderData` reverts with `"Token refund failed"` or `"Native refund failed"`, ensuring atomicity.

### Gas Optimization
- **Max Iterations**: `clearOrders` uses `maxIterations` to limit loop iterations, preventing gas limit issues when processing many orders.
- **Minimal Updates**: `clearSingleOrder` and `clearOrders` use a single `UpdateType` for cancellation (status=0), minimizing state writes.
- **Dynamic Arrays**: Arrays like `UpdateType[]` are dynamically sized (e.g., 3 elements in `_executeSingleOrder`, 1 in `_clearOrderData`) to reduce gas costs.

### Security Measures
- **Reentrancy Protection**: All external functions (`createTokenBuyOrder`, `createNativeBuyOrder`, `createTokenSellOrder`, `createNativeSellOrder`, `clearSingleOrder`, `clearOrders`) are protected by `nonReentrant`, preventing reentrancy attacks.
- **Listing Validation**: The `onlyValidListing` modifier ensures `listingAddress` is registered with the `ICCAgent` contract via `checkValidListing`, using `agentView` for validation.
- **Safe Transfers**: `SafeERC20.safeTransferFrom` is used for ERC20 token transfers, handling edge cases like non-standard tokens.
- **Balance Checks**: Pre/post balance checks in `_checkTransferAmountToken` and `_checkTransferAmountNative` ensure transfers are successful, accounting for fee-on-transfer tokens or failed ETH transfers.

### Limitations and Assumptions
- **No Settlement**: `CCOrderRouter` does not handle order settlement (`settleBuyOrders`, `settleSellOrders`, etc.), focusing solely on creation and cancellation. Settlement is handled by another contract (e.g., `CCLiquidityRouter`).
- **No Liquidity Management**: Functions like `deposit`, `withdraw`, `claimFees`, and `changeDepositor` are absent, as `CCOrderRouter` does not interact with liquidity pools (`ICCLiquidityTemplate`).
- **No Payouts**: Long and short payout settlement (`settleLongPayouts`, `settleShortPayouts`) is not supported, as `CCOrderRouter` focuses on order management.
- **Zero-Amount Handling**: `CCOrderRouter` does not deal with payouts, so no zero-amount payout logic exists.

### Differences from SSRouter
- **Scope**: `CCOrderRouter` is a subset of `SSRouter`, focusing only on order creation and cancellation, omitting settlement, liquidity management, and payout processing.
- **Inheritance**: Inherits `CCOrderPartial` and `CCMainPartial`, not `SSSettlementPartial`, reducing scope compared to `SSRouter`.
- **Functionality**: Lacks `settleBuyOrders`, `settleSellOrders`, `settleBuyLiquid`, `settleSellLiquid`, `settleLongPayouts`, `settleShortPayouts`, `settleLongLiquid`, `settleShortLiquid`, `deposit`, `withdraw`, `claimFees`, and `changeDepositor`.
- **Gas Efficiency**: More lightweight due to fewer functions and no complex settlement logic.

## Additional Details
- **Decimal Handling**: Relies on `normalize` and `denormalize` from `CCMainPartial` for consistent precision (1e18). Token decimals are fetched via `IERC20.decimals` or set to 18 for ETH.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant` modifier.
- **Gas Optimization**: Uses `maxIterations` in `clearOrders`, minimal `UpdateType[]` arrays, and efficient balance checks.
- **Listing Validation**: Uses `onlyValidListing` modifier with `ICCAgent.getListing` checks.
- **Token Usage**:
  - Buy orders: Input tokenB (ERC20 or ETH), output tokenA (settlement not handled).
  - Sell orders: Input tokenA (ERC20 or ETH), output tokenB (settlement not handled).
- **Events**: No events defined; relies on `listingContract` events for logging.
- **Safety**:
  - Explicit casting for interfaces (e.g., `ICCListing(listingAddress)`).
  - No inline assembly, using high-level Solidity.
  - Conditional checks in `_clearOrderData` for refund transfers.
  - Hidden state variables (e.g., `agent`) accessed via `agentView`.
  - Avoids reserved keywords and unnecessary virtual/override modifiers.
  - Maker-only cancellation enforced in `_clearOrderData`.
