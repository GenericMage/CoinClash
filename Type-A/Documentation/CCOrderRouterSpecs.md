# CCOrderRouter Contract Documentation

## Overview
The `CCOrderRouter` contract, implemented in Solidity (`^0.8.2`), serves as a router for creating, canceling, and settling buy/sell orders and long/short payouts on a decentralized trading platform. It inherits functionality from `CCOrderPartial` (v0.0.04), which extends `CCMainPartial` (v0.0.10), and integrates with `ICCListing` (v0.0.7), `ICCLiquidity` (v0.0.4), and `IERC20` interfaces for token operations, using `ReentrancyGuard` for security. The contract handles order creation (`createTokenBuyOrder`, `createNativeBuyOrder`, `createTokenSellOrder`, `createNativeSellOrder`), cancellation (`clearSingleOrder`, `clearOrders`), and payout settlement (`settleLongLiquid`, `settleShortLiquid`, `settleLongPayouts`, `settleShortPayouts`). State variables are hidden, accessed via unique view functions, with normalized amounts (1e18 decimals) for precision.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.11 (Updated 2025-08-01)

**Inheritance Tree:** `CCOrderRouter` → `CCOrderPartial` → `CCMainPartial`

**Compatibility:** `CCListing.sol` (v0.0.3), `CCOrderPartial.sol` (v0.0.04), `CCMainPartial.sol` (v0.0.10), `ICCLiquidity.sol` (v0.0.4), `ICCListing.sol` (v0.0.7).

## Mappings
- **`payoutPendingAmounts`**: `mapping(address => mapping(uint256 => uint256))` (inherited from `CCOrderPartial`)
  - Tracks pending payout amounts per listing address and order ID, normalized to 1e18 decimals.
  - Updated in `settleSingleLongLiquid`, `settleSingleShortLiquid`, `executeLongPayout`, `executeShortPayout` by decrementing `normalizedReceived`.

## Structs
- **OrderPrep**: Defined in `CCOrderPartial`, contains `maker` (address), `recipient` (address), `amount` (uint256, normalized), `maxPrice` (uint256), `minPrice` (uint256), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256).
- **PayoutContext**: Defined in `CCOrderPartial`, contains `listingAddress` (address), `liquidityAddr` (address), `tokenOut` (address), `tokenDecimals` (uint8), `amountOut` (uint256, denormalized), `recipientAddress` (address).
- **ICCListing.PayoutUpdate**: Contains `payoutType` (uint8, 0=Long, 1=Short), `recipient` (address), `required` (uint256, normalized).
- **ICCListing.LongPayoutStruct**: Contains `makerAddress` (address), `recipientAddress` (address), `required` (uint256, normalized), `filled` (uint256, normalized), `orderId` (uint256), `status` (uint8).
- **ICCListing.ShortPayoutStruct**: Contains `makerAddress` (address), `recipientAddress` (address), `amount` (uint256, normalized), `filled` (uint256, normalized), `orderId` (uint256), `status` (uint8).
- **ICCListing.UpdateType**: Contains `updateType` (uint8), `structId` (uint8), `index` (uint256), `value` (uint256), `addr` (address), `recipient` (address), `maxPrice` (uint256), `minPrice` (uint256), `amountSent` (uint256).

## Formulas
1. **Payout Amount**:
   - **Formula**: `amountOut = denormalize(payout.required, tokenDecimals)` (long), `amountOut = denormalize(payout.amount, tokenDecimals)` (short).
   - **Used in**: `settleSingleLongLiquid`, `settleSingleShortLiquid`, `executeLongPayout`, `executeShortPayout`.
2. **Liquidity Check**:
   - **Formula**: `sufficient = isLong ? yAmount >= requiredAmount : xAmount >= requiredAmount`.
   - **Used in**: `_checkLiquidityBalance`.
3. **Transfer Tracking**:
   - **Formula**: `amountReceived = postBalance - preBalance`, `normalizedReceived = normalize(amountReceived, tokenDecimals)`.
   - **Used in**: `_transferNative`, `_transferToken`, `_checkTransferAmountToken`, `_checkTransferAmountNative`.

## External Functions

### createTokenBuyOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `recipientAddress`: Order recipient.
  - `inputAmount`: TokenB amount (denormalized, ERC20).
  - `maxPrice`, `minPrice`: Normalized prices (1e18).
- **Behavior**: Creates buy order for ERC20 tokenB, transfers tokens to `listingAddress`, normalizes amounts, initializes `amountSent=0`.
- **Internal Call Flow**:
  - Calls `_handleOrderPrep` to validate inputs, normalize `inputAmount` (using `decimalsB`).
  - Verifies `tokenB != address(0)`.
  - Calls `_checkTransferAmountToken` to transfer tokens via `IERC20.transferFrom`, checks balances.
  - Calls `_executeSingleOrder` to create order via `listingContract.update`.
- **Balance Checks**: Pre/post balance for `listingAddress` in `_checkTransferAmountToken`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, reverts on invalid inputs or failed transfer.

### createNativeBuyOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**: Same as `createTokenBuyOrder`, for ETH (tokenB).
- **Behavior**: Creates buy order for ETH, transfers ETH via `transactNative`.
- **Internal Call Flow**:
  - Verifies `tokenB == address(0)`, `msg.value == inputAmount`.
  - Uses `_checkTransferAmountNative` to transfer ETH, checks balances.
  - Calls `_executeSingleOrder`.
- **Balance Checks**: Pre/post ETH balance for `listingAddress`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, payable.

### createTokenSellOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**: Same as `createTokenBuyOrder`, for tokenA (ERC20).
- **Behavior**: Creates sell order for ERC20 tokenA, transfers tokens.
- **Internal Call Flow**: Similar to `createTokenBuyOrder`, uses `tokenA`, `decimalsA`.
- **Balance Checks**: Same as `createTokenBuyOrder`.
- **Restrictions**: Same as `createTokenBuyOrder`.

### createNativeSellOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**: Same as `createTokenBuyOrder`, for ETH (tokenA).
- **Behavior**: Creates sell order for ETH, transfers ETH.
- **Internal Call Flow**: Similar to `createNativeBuyOrder`, uses `tokenA`.
- **Balance Checks**: Same as `createNativeBuyOrder`.
- **Restrictions**: Same as `createNativeBuyOrder`.

### clearSingleOrder(address listingAddress, uint256 orderIdentifier, bool isBuyOrder)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `orderIdentifier`: Order ID.
  - `isBuyOrder`: True for buy, false for sell.
- **Behavior**: Cancels order, refunds pending amounts to `recipientAddress`.
- **Internal Call Flow**:
  - Calls `_clearOrderData` to verify maker, refund via `transactToken`/`transactNative`, update status to 0.
- **Balance Checks**: Implicit in `transactToken`/`transactNative`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`, maker-only.

### clearOrders(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `maxIterations`: Maximum orders to process.
- **Behavior**: Cancels pending orders for `msg.sender` up to `maxIterations`.
- **Internal Call Flow**:
  - Fetches `makerPendingOrdersView`, iterates, calls `_clearOrderData` for valid orders.
- **Balance Checks**: Same as `clearSingleOrder`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.

### settleLongLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress`: `ICCListing` contract address.
  - `maxIterations`: Maximum payouts to process.
- **Behavior**: Processes long liquidation payouts (token B) via `ICCLiquidity`.
- **Internal Call Flow**:
  - Fetches `longPayoutByIndexView`, iterates, calls `settleSingleLongLiquid`:
    - Fetches `LongPayoutStruct`, handles zero `required`.
    - Uses `_prepPayoutContext`, `_checkLiquidityBalance`, `_transferNative`/`_transferToken` (with `depositor=msg.sender`).
    - Updates `payoutPendingAmounts`, creates `PayoutUpdate`.
  - Resizes updates, calls `ssUpdate`.
- **Balance Checks**: Pre/post balance in `_transferNative`/`_transferToken`, liquidity check.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.

### settleShortLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongLiquid`.
- **Behavior**: Processes short liquidation payouts (token A) via `ICCLiquidity`.
- **Internal Call Flow**: Similar to `settleLongLiquid`, uses `shortPayoutByIndexView`, `ShortPayoutStruct`.
- **Balance Checks**: Same as `settleLongLiquid`.
- **Restrictions**: Same as `settleLongLiquid`.

### settleLongPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongLiquid`.
- **Behavior**: Executes long payouts (token B) via `listingContract`.
- **Internal Call Flow**:
  - Calls `executeLongPayouts`, iterates `longPayoutByIndexView`, uses `executeLongPayout`:
    - Skips zero `required`, transfers via `_transferNative`/`_transferToken` (no `depositor`).
    - Updates `payoutPendingAmounts`, creates `PayoutUpdate`.
  - Resizes updates, calls `ssUpdate`.
- **Balance Checks**: Pre/post balance in `_transferNative`/`_transferToken`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.

### settleShortPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongLiquid`.
- **Behavior**: Executes short payouts (token A) via `listingContract`.
- **Internal Call Flow**: Similar to `settleLongPayouts`, uses `shortPayoutByIndexView`, `ShortPayoutStruct`.
- **Balance Checks**: Same as `settleLongPayouts`.
- **Restrictions**: Same as `settleLongPayouts`.

### setAgent(address newAgent)
- **Parameters**: `newAgent`: New `ICCAgent` address.
- **Behavior**: Updates `agent` state variable (inherited).
- **Restrictions**: `onlyOwner`, non-zero `newAgent`.

### setUniswapV2Router(address newRouter)
- **Parameters**: `newRouter`: New Uniswap V2 router address.
- **Behavior**: Updates `uniswapV2Router` state variable (inherited).
- **Restrictions**: `onlyOwner`, non-zero `newRouter`.

## View Functions
- **agentView()**: Returns `agent` address (inherited).
- **uniswapV2RouterView()**: Returns `uniswapV2Router` address (inherited).

## Clarifications and Nuances
- **Payout Mechanics**:
  - **Long vs. Short**: Long payouts transfer token B, short payouts transfer token A. Liquidations use `ICCLiquidity`, payouts use `listingContract`.
  - **Zero-Amount Payouts**: Sets status to 3 if `required`/`amount` is zero, returns `PayoutUpdate` with `required=0`.
  - **Depositor Handling**: Liquidation functions pass `msg.sender` as `depositor` in `ICCLiquidity` calls; payout functions do not use `depositor` in `listingContract` calls.
- **Decimal Handling**: Normalizes to 1e18 decimals, denormalizes for transfers using `decimalsA`/`decimalsB`.
- **Security**: `nonReentrant`, try-catch with revert strings, explicit casting, no inline assembly.
- **Gas Optimization**: `maxIterations`, dynamic array resizing, helper functions (`_prepPayoutContext`, `_checkLiquidityBalance`).
- **Limitations**: No liquidity management or fee updates; `uniswapV2Router` settable but unused.
