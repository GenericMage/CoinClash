# CCOrderRouter Contract Documentation

## Overview
The `CCOrderRouter` contract, implemented in Solidity (`^0.8.2`), serves as a router for creating, canceling, and settling buy/sell orders and long/short liquidation payouts on a decentralized trading platform. It inherits from `CCOrderPartial` (v0.1.9), which extends `CCMainPartial` (v0.1.5), and integrates with `ICCListing` (v0.1.5), `ICCLiquidity` (v0.0.5), and `IERC20` interfaces, using `ReentrancyGuard` for security. The contract handles order creation (`createTokenBuyOrder`, `createNativeBuyOrder`, `createTokenSellOrder`, `createNativeSellOrder`), cancellation (`clearSingleOrder`, `clearOrders`), and liquidation payout settlement (`settleLongLiquid`, `settleShortLiquid`). State variables are hidden, accessed via view functions, with normalized amounts (1e18 decimals) for precision.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.1.5 (Updated 2025-09-11)

**Inheritance Tree:** `CCOrderRouter` → `CCOrderPartial` → `CCMainPartial`

**Compatibility:** `CCListingTemplate.sol` (v0.3.10), `CCOrderPartial.sol` (v0.1.9), `CCMainPartial.sol` (v0.1.5), `ICCLiquidity.sol` (v0.0.5), `CCLiquidityTemplate.sol` (v0.1.9).

## Mappings
- **`payoutPendingAmounts`**: `mapping(address => mapping(uint256 => uint256))` (inherited from `CCOrderPartial`)
  - Tracks pending payout amounts per listing address and order ID, normalized to 1e18 decimals.
  - Updated in `settleSingleLongLiquid`, `settleSingleShortLiquid` by decrementing `payout.required` or `payout.amount`.

## Structs
- **OrderPrep**: Defined in `CCOrderPartial`, contains `maker` (address), `recipient` (address), `amount` (uint256, normalized), `maxPrice` (uint256), `minPrice` (uint256), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256).
- **PayoutContext**: Defined in `CCOrderPartial`, contains `listingAddress` (address), `liquidityAddr` (address), `tokenOut` (address), `tokenDecimals` (uint8), `amountOut` (uint256, denormalized), `recipientAddress` (address).
- **ICCLiquidity.PayoutUpdate**: Contains `payoutType` (uint8, 0=Long, 1=Short), `recipient` (address), `orderId` (uint256), `required` (uint256, normalized), `filled` (uint256, normalized), `amountSent` (uint256, normalized).
- **ICCLiquidity.LongPayoutStruct**: Contains `makerAddress` (address), `recipientAddress` (address), `required` (uint256, normalized), `filled` (uint256, normalized), `amountSent` (uint256, normalized), `orderId` (uint256), `status` (uint8).
- **ICCLiquidity.ShortPayoutStruct**: Contains `makerAddress` (address), `recipientAddress` (address), `amount` (uint256, normalized), `filled` (uint256, normalized), `amountSent` (uint256, normalized), `orderId` (uint256), `status` (uint8).
- **ICCListing.BuyOrderUpdate**: Contains `structId` (uint8, 0=Core, 1=Pricing, 2=Amounts), `orderId` (uint256), `makerAddress` (address), `recipientAddress` (address), `status` (uint8), `maxPrice` (uint256), `minPrice` (uint256), `pending` (uint256), `filled` (uint256), `amountSent` (uint256).
- **ICCListing.SellOrderUpdate**: Same fields as `BuyOrderUpdate`.

## Formulas
1. **Payout Amount**:
   - **Formula**: `amountOut = denormalize(payout.required, tokenDecimals)` (long), `amountOut = denormalize(payout.amount, tokenDecimals)` (short).
   - **Used in**: `settleSingleLongLiquid`, `settleSingleShortLiquid`.
2. **Liquidity Check**:
   - **Formula**: `sufficient = isLong ? yAmount >= requiredAmount : xAmount >= requiredAmount`.
   - **Used in**: `_checkLiquidityBalance`.
3. **Filled Update**:
   - **Formula**: `filled = payout.filled + payout.required` (long), `filled = payout.filled + payout.amount` (short).
   - **Used in**: `settleSingleLongLiquid`, `settleSingleShortLiquid`.

## External Functions
### createTokenBuyOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**: `listingAddress` (listing contract), `recipientAddress` (order recipient), `inputAmount` (tokenB amount), `maxPrice` (1e18), `minPrice` (1e18).
- **Behavior**: Creates buy order for ERC20 tokenB, transfers tokens to `listingAddress`, calls `_executeSingleOrder`.
- **Internal Call Flow**:
  - `_handleOrderPrep`: Validates inputs, normalizes `inputAmount` to 1e18 decimals.
  - `_checkTransferAmountToken`: Performs pre/post balance checks for tokenB, returns `amountReceived`, `normalizedReceived`.
  - `_executeSingleOrder`: Splits into three `ICCListing.BuyOrderUpdate` calls (Core, Pricing, Amounts structs), calls `ICCListing.ccUpdate`.
- **Balance Checks**: Pre/post balance in `_checkTransferAmountToken` for `amountReceived`, `normalizedReceived`.
- **Restrictions**: `onlyValidListing` (validates via `ICCAgent.isValidListing`), `nonReentrant`, tokenB must be ERC20.
- **Events/Errors**: Reverts on invalid maker, recipient, amount, or transfer failure.

### createNativeBuyOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**: Same as `createTokenBuyOrder`.
- **Behavior**: Creates buy order for native ETH (tokenB), transfers ETH, calls `_executeSingleOrder`.
- **Internal Call Flow**:
  - `_handleOrderPrep`: Normalizes `inputAmount`.
  - `_checkTransferAmountNative`: Checks `msg.value == inputAmount`, performs pre/post balance checks, calls `ICCListing.transactNative`.
  - `_executeSingleOrder`: Constructs `ICCListing.BuyOrderUpdate` arrays (Core, Pricing, Amounts), calls `ccUpdate`.
- **Balance Checks**: Pre/post balance in `_checkTransferAmountNative`.
- **Restrictions**: `onlyValidListing`, `nonReentrant`, tokenB must be native.
- **Events/Errors**: Reverts on incorrect ETH amount or no ETH received.

### createTokenSellOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**: Same as `createTokenBuyOrder`.
- **Behavior**: Creates sell order for ERC20 tokenA, transfers tokens, calls `_executeSingleOrder`.
- **Internal Call Flow**: Similar to `createTokenBuyOrder`, uses `ICCListing.SellOrderUpdate` for tokenA.
- **Balance Checks**: Pre/post balance in `_checkTransferAmountToken`.
- **Restrictions**: `onlyValidListing`, `nonReentrant`, tokenA must be ERC20.
- **Events/Errors**: Reverts on invalid tokenA or transfer failure.

### createNativeSellOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**: Same as `createTokenBuyOrder`.
- **Behavior**: Creates sell order for native ETH (tokenA), transfers ETH, calls `_executeSingleOrder`.
- **Internal Call Flow**: Similar to `createNativeBuyOrder`, uses `ICCListing.SellOrderUpdate` for tokenA.
- **Balance Checks**: Pre/post balance in `_checkTransferAmountNative`.
- **Restrictions**: `onlyValidListing`, `nonReentrant`, tokenA must be native.
- **Events/Errors**: Reverts on incorrect ETH amount or no ETH received.

### clearSingleOrder(address listingAddress, uint256 orderIdentifier, bool isBuyOrder)
- **Parameters**: `listingAddress` (listing contract), `orderIdentifier` (order ID), `isBuyOrder` (true for buy, false for sell).
- **Behavior**: Cancels a single order, refunds pending amounts via `_clearOrderData`.
- **Internal Call Flow**:
  - `_clearOrderData`: Validates maker (`msg.sender`), fetches order details (`getBuyOrderCore`/`getSellOrderCore`, `getBuyOrderAmounts`/`getSellOrderAmounts`), refunds via `ICCListing.transactNative`/`transactToken`, updates status to 0 (cancelled) via `ICCListing.ccUpdate` with `BuyOrderUpdate`/`SellOrderUpdate`.
- **Restrictions**: `onlyValidListing`, `nonReentrant`, maker-only cancellation.
- **Events/Errors**: Reverts if caller is not maker.

### clearOrders(address listingAddress, uint256 maxIterations)
- **Parameters**: `listingAddress` (listing contract), `maxIterations` (maximum orders to process).
- **Behavior**: Cancels multiple orders for `msg.sender` up to `maxIterations`.
- **Internal Call Flow**:
  - Calls `ICCListing.makerPendingOrdersView` to fetch order IDs.
  - Iterates orders, checks maker via `getBuyOrderCore`/`getSellOrderCore`.
  - Calls `_clearOrderData` for each valid order.
- **Restrictions**: `onlyValidListing`, `nonReentrant`.
- **Events/Errors**: Skips non-maker orders, no events emitted for skipped iterations.

### settleLongLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: `listingAddress` (listing contract), `maxIterations` (maximum payouts to process).
- **Behavior**: Settles long liquidation payouts (tokenB) via liquidity pool using active payout IDs.
- **Internal Call Flow**:
  - Calls `ICCLiquidity.activeLongPayoutsView` to fetch active payout IDs.
  - Iterates up to `maxIterations`, calls `settleSingleLongLiquid`:
    - Checks `LongPayoutStruct.required` and `status == 1` (pending).
    - `_prepPayoutContext`: Initializes context (`listingAddress`, `liquidityAddr`, `tokenOut`, `tokenDecimals`, `recipientAddress`).
    - `_checkLiquidityBalance`: Verifies liquidity (`yAmount >= requiredAmount`).
    - `_transferNative`/`_transferToken`: Transfers tokens, uses pre/post balance checks for `amountReceived`, `normalizedReceived`.
    - Calls `ICCLiquidity.ccUpdate` to reduce liquidity balance by `payout.required` (updateType=0, index=1 for yLiquid).
    - Updates `payoutPendingAmounts` (subtracts `payout.required`).
    - Creates `PayoutUpdate` (`payoutType=0`, `orderId`, `required=0`, `filled=payout.filled + payout.required`, `amountSent=normalizedReceived`).
  - Resizes updates array, calls `ICCLiquidity.ssUpdate`.
- **Balance Checks**: Pre/post balance in `_transferNative`/`_transferToken` for `amountSent`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Events/Errors**: Emits `TransferFailed` on transfer failure, returns empty updates array if insufficient liquidity or transfer fails.

### settleShortLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongLiquid`.
- **Behavior**: Settles short liquidation payouts (tokenA) via liquidity pool using active payout IDs.
- **Internal Call Flow**:
  - Calls `ICCLiquidity.activeShortPayoutsView` to fetch active payout IDs.
  - Iterates up to `maxIterations`, calls `settleSingleShortLiquid`:
    - Checks `ShortPayoutStruct.amount` and `status == 1`.
    - `_prepPayoutContext`: Initializes context for tokenA.
    - `_checkLiquidityBalance`: Verifies liquidity (`xAmount >= amount`).
    - `_transferNative`/`_transferToken`: Transfers tokens, uses pre/post balance checks.
    - Calls `ICCLiquidity.ccUpdate` to reduce liquidity balance by `payout.amount` (updateType=0, index=0 for xLiquid).
    - Updates `payoutPendingAmounts` (subtracts `payout.amount`).
    - Creates `PayoutUpdate` (`payoutType=1`, `orderId`, `required=0`, `filled=payout.filled + payout.amount`, `amountSent=normalizedReceived`).
  - Resizes updates array, calls `ICCLiquidity.ssUpdate`.
- **Balance Checks**: Pre/post balance in `_transferNative`/`_transferToken` for `amountSent`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.
- **Events/Errors**: Emits `TransferFailed` on transfer failure, returns empty updates array if insufficient liquidity or transfer fails.

### setAgent(address newAgent)
- **Parameters**: `newAgent`: New `ICCAgent` address.
- **Behavior**: Updates `agent` state variable (inherited from `CCMainPartial`).
- **Internal Call Flow**: None, directly sets `agent`.
- **Restrictions**: `onlyOwner`, non-zero `newAgent`.
- **Events/Errors**: Reverts on invalid `newAgent`.

### setUniswapV2Router(address newRouter)
- **Parameters**: `newRouter`: New Uniswap V2 router address.
- **Behavior**: Updates `uniswapV2Router` state variable (inherited from `CCMainPartial`).
- **Internal Call Flow**: None, directly sets `uniswapV2Router`.
- **Restrictions**: `onlyOwner`, non-zero `newRouter`.
- **Events/Errors**: Reverts on invalid `newRouter`.

## View Functions
- **agentView()**: Returns `agent` address (inherited from `CCMainPartial`).
- **uniswapV2RouterView()**: Returns `uniswapV2Router` address (inherited from `CCMainPartial`).

## Clarifications and Nuances
- **Payout Mechanics**:
  - **Long vs. Short**: Long payouts transfer tokenB, short payouts transfer tokenA, both via `ICCLiquidity` liquidity pool.
  - **Active Payouts**: Uses `ICCLiquidity.activeLongPayoutsView`/`activeShortPayoutsView` to fetch only pending payouts, improving efficiency.
  - **Zero-Amount Payouts**: If `required`/`amount` is zero or `status != 1`, sets `PayoutUpdate.required=0`, retains existing `filled` and `amountSent`.
  - **Liquidity Updates**: `settleSingleLongLiquid`/`settleSingleShortLiquid` call `ICCLiquidity.ccUpdate` to reduce liquidity balances by the requested amount (`payout.required`/`payout.amount`) to avoid tax on transfer errors.
  - **Amount Handling**: `required` set to 0 post-settlement, `filled` incremented by requested amount, `amountSent` reflects actual transferred amount (post-tax).
- **Decimal Handling**: Normalizes to 1e18 decimals using `normalize`, denormalizes for transfers using `denormalize` with `decimalsA`/`decimalsB`.
- **Security**:
  - Uses `nonReentrant` to prevent reentrancy.
  - Try-catch in `_transferNative`/`_transferToken` with `TransferFailed` event for graceful degradation.
  - Explicit casting, no inline assembly, no reserved keywords per Trenche 1.2.
- **Gas Optimization**:
  - `maxIterations` for user-controlled loop limits.
  - Dynamic array resizing in `settleLongLiquid`/`settleShortLiquid`.
  - Helper functions (`_prepPayoutContext`, `_checkLiquidityBalance`, `_transferNative`, `_transferToken`, `_executeSingleOrder`, `_clearOrderData`) reduce complexity.
- **Limitations**: No direct liquidity management or fee updates; `uniswapV2Router` settable but unused in current implementation.
- **Balance Checks**: Pre/post balance checks in `_checkTransferAmountToken`, `_checkTransferAmountNative`, `_transferNative`, `_transferToken` ensure accurate `amountReceived` and `normalizedReceived` for tax-affected transfers.
