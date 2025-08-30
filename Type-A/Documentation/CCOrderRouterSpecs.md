# CCOrderRouter Contract Documentation

## Overview
The `CCOrderRouter` contract, implemented in Solidity (`^0.8.2`), serves as a router for creating, canceling, and settling buy/sell orders and long/short liquidation payouts on a decentralized trading platform. It inherits from `CCOrderPartial` (v0.1.3), which extends `CCMainPartial` (v0.1.1), and integrates with `ICCListing` (v0.3.0), `ICCLiquidity` (v0.0.5), and `IERC20` interfaces, using `ReentrancyGuard` for security. The contract handles order creation (`createTokenBuyOrder`, `createNativeBuyOrder`, `createTokenSellOrder`, `createNativeSellOrder`), cancellation (`clearSingleOrder`, `clearOrders`), and liquidation payout settlement (`settleLongLiquid`, `settleShortLiquid`). State variables are hidden, accessed via view functions, with normalized amounts (1e18 decimals) for precision.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.1.1 (Updated 2025-08-30)

**Inheritance Tree:** `CCOrderRouter` → `CCOrderPartial` → `CCMainPartial`

**Compatibility:** `CCListingTemplate.sol` (v0.3.0), `CCOrderPartial.sol` (v0.1.3), `CCMainPartial.sol` (v0.1.1), `ICCLiquidity.sol` (v0.0.5).

## Mappings
- **`payoutPendingAmounts`**: `mapping(address => mapping(uint256 => uint256))` (inherited from `CCOrderPartial`)
  - Tracks pending payout amounts per listing address and order ID, normalized to 1e18 decimals.
  - Updated in `settleSingleLongLiquid`, `settleSingleShortLiquid` by decrementing `payout.required` or `payout.amount`.

## Structs
- **OrderPrep**: Defined in `CCOrderPartial`, contains `maker` (address), `recipient` (address), `amount` (uint256, normalized), `maxPrice` (uint256), `minPrice` (uint256), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256).
- **PayoutContext**: Defined in `CCOrderPartial`, contains `listingAddress` (address), `liquidityAddr` (address), `tokenOut` (address), `tokenDecimals` (uint8), `amountOut` (uint256, denormalized), `recipientAddress` (address).
- **ICCListing.PayoutUpdate**: Contains `payoutType` (uint8, 0=Long, 1=Short), `recipient` (address), `required` (uint256, normalized), `filled` (uint256, normalized), `amountSent` (uint256, normalized).
- **ICCListing.LongPayoutStruct**: Contains `makerAddress` (address), `recipientAddress` (address), `required` (uint256, normalized), `filled` (uint256, normalized), `orderId` (uint256), `status` (uint8).
- **ICCListing.ShortPayoutStruct**: Contains `makerAddress` (address), `recipientAddress` (address), `amount` (uint256, normalized), `filled` (uint256, normalized), `orderId` (uint256), `status` (uint8).
- **ICCListing.UpdateType**: Contains `updateType` (uint8), `structId` (uint8), `index` (uint256), `value` (uint256), `addr` (address), `recipient` (address), `maxPrice` (uint256), `minPrice` (uint256), `amountSent` (uint256).

## Formulas
1. **Payout Amount**:
   - **Formula**: `amountOut = denormalize(payout.required, tokenDecimals)` (long), `amountOut = denormalize(payout.amount, tokenDecimals)` (short).
   - **Used in**: `settleSingleLongLiquid`, `settleSingleShortLiquid`.
2. **Liquidity Check**:
   - **Formula**: `sufficient = isLong ? yAmount >= requiredAmount : xAmount >= requiredAmount`.
   - **Used in**: `_checkLiquidityBalance`.

## External Functions
### createTokenBuyOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**: `listingAddress` (listing contract), `recipientAddress` (order recipient), `inputAmount` (tokenB amount), `maxPrice` (1e18), `minPrice` (1e18).
- **Behavior**: Creates buy order for ERC20 tokenB, transfers tokens to `listingAddress`, calls `_executeSingleOrder`.
- **Internal Call Flow**:
  - Calls `_handleOrderPrep` (normalizes `inputAmount`).
  - Calls `_checkTransferAmountToken` (pre/post balance checks for tokenB).
  - Calls `_executeSingleOrder` (constructs `UpdateType` arrays, calls `ccUpdate`).
- **Balance Checks**: Pre/post balance in `_checkTransferAmountToken` for `amountReceived`, `normalizedReceived`.
- **Restrictions**: `onlyValidListing`, `nonReentrant`, tokenB must be ERC20.

### createNativeBuyOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**: Same as `createTokenBuyOrder`.
- **Behavior**: Creates buy order for native ETH (tokenB), transfers ETH, calls `_executeSingleOrder`.
- **Internal Call Flow**:
  - Calls `_handleOrderPrep`, `_checkTransferAmountNative` (pre/post balance for ETH), `_executeSingleOrder`.
- **Balance Checks**: Pre/post balance in `_checkTransferAmountNative`.
- **Restrictions**: `onlyValidListing`, `nonReentrant`, tokenB must be native.

### createTokenSellOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**: Same as `createTokenBuyOrder`.
- **Behavior**: Creates sell order for ERC20 tokenA, transfers tokens, calls `_executeSingleOrder`.
- **Internal Call Flow**: Similar to `createTokenBuyOrder`, targets tokenA.
- **Balance Checks**: Pre/post balance in `_checkTransferAmountToken`.
- **Restrictions**: `onlyValidListing`, `nonReentrant`, tokenA must be ERC20.

### createNativeSellOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**: Same as `createTokenBuyOrder`.
- **Behavior**: Creates sell order for native ETH (tokenA), transfers ETH, calls `_executeSingleOrder`.
- **Internal Call Flow**: Similar to `createNativeBuyOrder`, targets tokenA.
- **Balance Checks**: Pre/post balance in `_checkTransferAmountNative`.
- **Restrictions**: `onlyValidListing`, `nonReentrant`, tokenA must be native.

### clearSingleOrder(address listingAddress, uint256 orderIdentifier, bool isBuyOrder)
- **Parameters**: `listingAddress` (listing contract), `orderIdentifier` (order ID), `isBuyOrder` (true for buy, false for sell).
- **Behavior**: Cancels a single order, refunds pending amounts via `_clearOrderData`.
- **Internal Call Flow**:
  - Calls `_clearOrderData` (validates maker, refunds via `transactNative`/`transactToken`, updates status via `ccUpdate`).
- **Restrictions**: `onlyValidListing`, `nonReentrant`.

### clearOrders(address listingAddress, uint256 maxIterations)
- **Parameters**: `listingAddress` (listing contract), `maxIterations` (maximum orders to process).
- **Behavior**: Cancels multiple orders for `msg.sender` up to `maxIterations`.
- **Internal Call Flow**:
  - Calls `makerPendingOrdersView`, iterates orders, checks maker via `getBuyOrderCore`/`getSellOrderCore`, calls `_clearOrderData`.
- **Restrictions**: `onlyValidListing`, `nonReentrant`.

### settleLongLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: `listingAddress` (listing contract), `maxIterations` (maximum payouts to process).
- **Behavior**: Settles long liquidation payouts (tokenB) via liquidity pool.
- **Internal Call Flow**:
  - Calls `longPayoutByIndexView`, iterates, uses `settleSingleLongLiquid`:
    - Checks `payout.required`, uses `_prepPayoutContext`, `_checkLiquidityBalance`, `_transferNative`/`_transferToken` (pre/post balance).
    - Updates `payoutPendingAmounts`, creates `PayoutUpdate` (`filled=payout.required`, `amountSent=normalizedReceived`).
  - Resizes updates, calls `ssUpdate`.
- **Balance Checks**: Pre/post balance in `_transferNative`/`_transferToken`.
- **Restrictions**: `nonReentrant`, `onlyValidListing`.

### settleShortLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongLiquid`.
- **Behavior**: Settles short liquidation payouts (tokenA) via liquidity pool.
- **Internal Call Flow**: Similar to `settleLongLiquid`, uses `shortPayoutByIndexView`, `ShortPayoutStruct`.
- **Balance Checks**: Same as `settleLongLiquid`.
- **Restrictions**: Same as `settleLongLiquid`.

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
  - **Long vs. Short**: Long payouts transfer tokenB, short payouts transfer tokenA, both via liquidity pool (`ICCLiquidity`).
  - **Zero-Amount Payouts**: Sets status to 3 if `required`/`amount` is zero, returns `PayoutUpdate` with `required=0`, `filled=0`, `amountSent=0`.
  - **Depositor Handling**: Liquidation functions pass `msg.sender` as `depositor` in `ICCLiquidity` calls.
- **Decimal Handling**: Normalizes to 1e18 decimals, denormalizes for transfers using `decimalsA`/`decimalsB`.
- **Security**: `nonReentrant`, try-catch with revert strings, explicit casting, no inline assembly.
- **Gas Optimization**: `maxIterations`, dynamic array resizing, helper functions (`_prepPayoutContext`, `_checkLiquidityBalance`).
- **Limitations**: No liquidity management or fee updates; `uniswapV2Router` settable but unused.
- **Balance Checks**: Pre/post balance checks in `_checkTransferAmountToken`, `_checkTransferAmountNative`, `_transferNative`, `_transferToken` ensure accurate `amountReceived` and `normalizedReceived` for tax-affected transfers.