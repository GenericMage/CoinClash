# CCLiquidRouter Contract Documentation

## Overview
The `CCLiquidRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform using `ICCLiquidity` for liquid settlement. It inherits functionality from `CCLiquidPartial`, which extends `CCMainPartial`, and integrates with external interfaces (`ICCListing`, `ICCLiquidity`, `IERC20`) for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract handles liquid settlement (`settleBuyLiquid`, `settleSellLiquid`) via `ICCLiquidity`, with robust gas optimization and safety mechanisms. State variables are hidden, accessed via view functions with unique names, and decimal precision is maintained across tokens. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation. All transfers to or from the listing correctly call `listingContract.update` after successful liquidity transfers, ensuring state consistency.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.2 (updated 2025-07-27)

**Changes:**
- v0.0.2: Removed SafeERC20 usage, used IERC20 from CCMainPartial, removed redundant require success checks for transfers.
- v0.0.1: Created CCLiquidRouter.sol, extracted settleBuyLiquid and settleSellLiquid from CCSettlementRouter.sol.

**Inheritance Tree:** `CCLiquidRouter` → `CCLiquidPartial` → `CCMainPartial`

**Compatibility:** ICCListing.sol (v0.0.3), ICCLiquidity.sol, CCMainPartial.sol (v0.0.07), CCLiquidPartial.sol (v0.0.3).

## Mappings
- None defined directly in `CCLiquidRouter`. Relies on `ICCListing` view functions (e.g., `pendingBuyOrdersView`, `pendingSellOrdersView`) for order tracking.

## Structs
- **OrderContext**: Contains `listingContract` (ICCListing), `tokenIn` (address), `tokenOut` (address), `liquidityAddr` (address).
- **PrepOrderUpdateResult**: Contains `tokenAddress` (address), `tokenDecimals` (uint8), `makerAddress` (address), `recipientAddress` (address), `orderStatus` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, denormalized).
- **BuyOrderUpdateContext**: Contains `makerAddress` (address), `recipient` (address), `status` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, denormalized, tokenA for buy).
- **SellOrderUpdateContext**: Same as `BuyOrderUpdateContext`, with `amountSent` (tokenB for sell).

## Formulas
The formulas below govern liquid settlement calculations in `CCLiquidPartial.sol`. Pricing validation uses a simplified check (`maxPrice >= minPrice`), as Uniswap V2's constant product formula is not used, and `_computeSwapImpact` from `CCUniPartial.sol` is unavailable due to removed dependency.

1. **Price Validation**:
   - **Formula**: `maxPrice >= minPrice`
   - **Used in**: `_checkPricing`, `_prepBuyLiquidUpdates`, `_prepSellLiquidUpdates`.
   - **Description**: Validates order pricing by comparing `maxPrice` and `minPrice` from `getBuyOrderPricing` or `getSellOrderPricing`. Simplified due to lack of `_computeSwapImpact`.
   - **Usage**: Ensures trades meet order price constraints before proceeding with liquidity transfers.

2. **Buy Order Output**:
   - **Formula**: `amountOut = inputAmount` (simplified, assumes external swap logic).
   - **Used in**: `_prepareLiquidityTransaction`, `_prepBuyLiquidUpdates`.
   - **Description**: Computes tokenA output for buy orders, using input amount directly due to simplified logic.

3. **Sell Order Output**:
   - **Formula**: Same as buy order output, with `tokenIn = tokenA`, `tokenOut = tokenB`.
   - **Used in**: `_prepareLiquidityTransaction`, `_prepSellLiquidUpdates`.
   - **Description**: Computes tokenB output for sell orders, using input amount directly.

## External Functions

### settleBuyLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Settles pending buy orders up to `maxIterations` using `ICCLiquidity`, transferring tokenA to recipients, updating liquidity (tokenB), tracking `amountSent` (tokenA), and calling `listingContract.update` after successful transfers.
- **Internal Call Flow**:
  - Fetches `orderIdentifiers` via `pendingBuyOrdersView`.
  - Iterates up to `maxIterations`:
    - Calls `executeSingleBuyLiquid`:
      - Fetches `(pendingAmount, filled, amountSent)` via `getBuyOrderAmounts`.
      - Validates pricing via `_checkPricing` using simplified `maxPrice >= minPrice`.
      - Computes `amountOut`, `tokenIn`, `tokenOut` via `_prepareLiquidityTransaction`.
      - Transfers principal (tokenB) via `_checkAndTransferPrincipal`.
      - Transfers tokenA via `liquidityContract.transactNative` or `transactToken`.
      - Updates liquidity (tokenB) via `_updateLiquidity`.
      - Creates `ICCListing.UpdateType[]` via `_prepBuyLiquidUpdates` and `_createBuyOrderUpdates`.
  - Collects updates in `tempUpdates`, resizes to `finalUpdates`, and applies via `listingContract.update`.
- **Balance Checks**:
  - `_checkAndTransferPrincipal` ensures `amountSent > 0` and `amountReceived > 0` for principal transfer.
  - Pre/post balance checks in `_prepBuyOrderUpdate` and `_prepBuyLiquidUpdates` for tokenA transfer.
- **Mappings/Structs Used**:
  - **Structs**: `OrderContext`, `PrepOrderUpdateResult`, `BuyOrderUpdateContext`, `ICCListing.UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract.routers(address(this))`.
  - Reverts if pricing invalid, transfers fail, or liquidity insufficient.
- **Gas Usage Controls**: `maxIterations` limits iteration, dynamic array resizing.

### settleSellLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyLiquid`.
- **Behavior**: Settles pending sell orders up to `maxIterations` using `ICCLiquidity`, transferring tokenB to recipients, updating liquidity (tokenA), tracking `amountSent` (tokenB), and calling `listingContract.update` after successful transfers.
- **Internal Call Flow**:
  - Fetches `orderIdentifiers` via `pendingSellOrdersView`.
  - Iterates up to `maxIterations`:
    - Calls `executeSingleSellLiquid`:
      - Fetches `(pendingAmount, filled, amountSent)` via `getSellOrderAmounts`.
      - Validates pricing via `_checkPricing` using simplified `maxPrice >= minPrice`.
      - Computes `amountOut`, `tokenIn`, `tokenOut` via `_prepareLiquidityTransaction`.
      - Transfers principal (tokenA) via `_checkAndTransferPrincipal`.
      - Transfers tokenB via `liquidityContract.transactNative` or `transactToken`.
      - Updates liquidity (tokenA) via `_updateLiquidity`.
      - Creates `ICCListing.UpdateType[]` via `_prepSellLiquidUpdates` and `_createSellOrderUpdates`.
  - Collects updates in `tempUpdates`, resizes to `finalUpdates`, and applies via `listingContract.update`.
- **Balance Checks**: Same as `settleBuyLiquid`.
- **Mappings/Structs Used**:
  - **Structs**: `OrderContext`, `PrepOrderUpdateResult`, `SellOrderUpdateContext`, `ICCListing.UpdateType`.
- **Restrictions**: Same as `settleBuyLiquid`.
- **Gas Usage Controls**: Same as `settleBuyLiquid`.

### setAgent(address newAgent)
- **Parameters**:
  - `newAgent` (address): New ICCAgent address.
- **Behavior**: Updates `agent` state variable for listing validation, inherited from `CCMainPartial`.
- **Internal Call Flow**: Direct state update, validates `newAgent` is non-zero.
- **Mappings/Structs Used**:
  - **agent** (state variable): Stores ICCAgent address.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `newAgent` is zero (`"Invalid agent address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

## Clarifications and Nuances

### ICCLiquidity Integration
- **Liquid Settlement Process**: `settleBuyLiquid` and `settleSellLiquid` transfer principal from listing to `ICCLiquidity` (`_checkAndTransferPrincipal`), update liquidity (`_updateLiquidity`), transfer output tokens to recipients, and call `listingContract.update` after successful transfers.
- **Router Registration**: Functions interacting with `liquidityContract` require `routers(address(this))` to return true, ensuring only authorized routers can execute liquid settlements.
- **Balance Checks**: `_checkAndTransferPrincipal` verifies principal transfer with pre/post balance checks, handling fee-on-transfer tokens and ETH.

### Decimal Handling
- **Normalization**: Amounts are normalized to 18 decimals using `normalize` (inherited from `CCMainPartial`) for consistent calculations across tokens with varying decimals (e.g., USDC with 6 decimals, ETH with 18 decimals).
- **Denormalization**: Input and output amounts are denormalized to native token decimals for transfers, using `denormalize`.
- **ETH Handling**: For ETH transfers (`tokenIn` or `tokenOut == address(0)`), decimals are set to 18, and `msg.value` is used.

### Order Settlement Mechanics
- **Execution**: Orders are processed fully (status 3) if `normalizedReceived >= pendingAmount`, otherwise skipped with empty `ICCListing.UpdateType[]` arrays.
- **Amount Tracking**: `amountSent` tracks output tokens transferred (tokenA for buy, tokenB for sell), while `amountReceived` and `normalizedReceived` track output tokens received.
- **Pricing**: Simplified `_checkPricing` (`maxPrice >= minPrice`) assumes external price computation due to removed `CCUniPartial.sol` dependency.

### Gas Optimization
- **Max Iterations**: `maxIterations` limits loop iterations in all settlement functions, preventing gas limit issues.
- **Dynamic Arrays**: `tempUpdates` is oversized (`iterationCount * 3`) and resized to `finalUpdates` to minimize gas while collecting updates.
- **Helper Functions**: Complex logic is split into helpers (e.g., `_prepareLiquidityTransaction`, `_checkAndTransferPrincipal`, `_prepBuyLiquidUpdates`) to reduce stack depth and gas usage.

### Security Measures
- **Reentrancy Protection**: All external functions use `nonReentrant` modifier.
- **Listing Validation**: `onlyValidListing` ensures `listingAddress` is registered with `ICCAgent`.
- **Safe Transfers**: IERC20 from `CCMainPartial` is used for token operations, handling non-standard ERC20 tokens. Pre/post balance checks eliminate need for explicit transfer success checks.
- **Balance Checks**: Pre/post balance checks in `_checkAndTransferPrincipal` and `_prepBuy/SellOrderUpdate` ensure transfer success.
- **Router Validation**: Requires `liquidityContract.routers(address(this))` to be true.
- **Safety**:
  - Explicit casting for interfaces (e.g., `ICCListing`, `ICCLiquidity`).
  - No inline assembly, using high-level Solidity.
  - Hidden state variables (`agent`) accessed via `agentView`.
  - Avoids reserved keywords and unnecessary virtual/override modifiers.

### Limitations and Assumptions
- **No Uniswap V2 Integration**: Unlike `CCSettlementRouter`, `CCLiquidRouter` does not use Uniswap V2 swaps, relying solely on `ICCLiquidity` for settlements.
- **No Order Creation/Cancellation**: Does not handle order creation (`createBuyOrder`, `createSellOrder`) or cancellation (`clearSingleOrder`, `clearOrders`).
- **No Payouts**: Long and short payout settlement (`settleLongPayouts`, `settleShortPayouts`, `settleLongLiquid`, `settleShortLiquid`) is not supported.
- **No Liquidity Management**: Functions like `deposit`, `withdraw`, `claimFees`, and `changeDepositor` are absent, as `CCLiquidRouter` focuses on liquid settlement.
- **Simplified Pricing**: `_checkPricing` uses `maxPrice >= minPrice` due to removed `CCUniPartial.sol` dependency, assuming external price computation.
- **Zero-Amount Handling**: Zero pending amounts or failed transfers return empty `ICCListing.UpdateType[]` arrays, ensuring no state changes for invalid operations.

### Differences from CCSettlementRouter
- **Scope**: `CCLiquidRouter` focuses exclusively on liquid settlements (`settleBuyLiquid`, `settleSellLiquid`), omitting Uniswap V2-based settlements (`settleBuyOrders`, `settleSellOrders`), order creation, cancellation, payouts, and liquidity management.
- **Inheritance**: Inherits `CCLiquidPartial` and `CCMainPartial`, excluding `CCUniPartial` and `CCSettlementPartial`.
- **Pricing**: Uses simplified `_checkPricing` without Uniswap V2’s constant product formula or `_computeSwapImpact`.
- **Functionality**: Lacks `settleBuyOrders`, `settleSellOrders`, `setUniswapV2Router`, `createBuyOrder`, `createSellOrder`, `clearSingleOrder`, `clearOrders`, `deposit`, `withdraw`, `claimFees`, `changeDepositor`, `settleLongPayouts`, `settleShortPayouts`, `settleLongLiquid`, and `settleShortLiquid`.

## Additional Details
- **Decimal Handling**: Uses `normalize` and `denormalize` from `CCMainPartial` for 1e18 precision, with decimals fetched via `IERC20.decimals` or set to 18 for ETH.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: Uses `maxIterations`, dynamic arrays, helper functions for efficient execution.
- **Listing Validation**: `onlyValidListing` checks `ICCAgent.getListing` for listing integrity.
- **Token Usage**:
  - Buy orders: Input tokenB, output tokenA, `amountSent` tracks tokenA.
  - Sell orders: Input tokenA, output tokenB, `amountSent` tracks tokenB.
- **Events**: Relies on `listingContract` and `liquidityContract` events for logging.
- **Safety**:
  - Explicit casting for interfaces (e.g., `ICCListing`, `ICCLiquidity`).
  - No inline assembly, using high-level Solidity.
  - Hidden state variables (`agent`) accessed via `agentView`.
  - Avoids reserved keywords and unnecessary virtual/override modifiers.
