# Multihopper Contract Documentation

## Overview
The `Multihopper` system, implemented in Solidity (^0.8.2), facilitates multi-step token swaps across up to four listings, supporting market and liquid order settlements with price impact controls. It integrates with `ISSListing`, `ICCRouter`, and `ISSAgent` interfaces, uses `IERC20` for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The system is split into three contracts (`MultiStorage.sol`, `MultiInitializer.sol`, `MultiController.sol`) to reduce deployment overhead and improve modularity. It manages hop creation, execution, continuation, and cancellation, with gas optimization, robust decimal handling, and accurate refund tracking via `refundedPending` in `CancelPrepData`. State variables are public, accessed directly, and mappings ensure efficient hop tracking.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.53 (last updated 2025-08-11, enhanced function details)

**Compatible Contracts:**
- `SSRouter` v0.0.61
- `SSListingTemplate` v0.0.10

## Clarifications
- **Path-Finding Mechanism**: `computeRoute` (`MultiInitializer.sol`) precomputes a valid token path, ensuring `startToken` connects to `endToken`, reverting if no valid path exists.
- **Usage of amountSent**: Tracks output token amount from a hop step, used as `principal` for the next step in `executeStalls` and `processHopStep`.
- **Usage of filled**: Tracks settled input token amount, refunded in input token via `_handleFilledOrSent` during cancellation if `amountSent` is zero.
- **Field Conflicts**: Avoids conflicts with `SSListingTemplate` by mapping `getBuyOrderAmounts`/`getSellOrderAmounts` to `StallData` explicitly.
- **Listing Validation**: `onlyValidListing` modifier and `validateHopRequest` ensure listings are registered via `ISSAgent.getListing`.
- **Hop Cancellation Refunds**: Refunds `pending` in input token via `_handlePending`, `amountSent` or `filled` in output token via `_handleFilledOrSent`. `refundedPending` tracks actual refunded amounts, updating `hopID.principalAmount`.
- **Balance Checks**: `_checkTransfer` verifies transfers with pre/post balance checks, supporting native and ERC20 tokens with normalization.
- **Single Listing Route**: Validates `listing1` and token pair for single-step swaps.
- **maxIterations Usage**: Stored in `StalledHop` for settlements, separate from `maxIterations` in `continueHop` and `executeStalls`.
- **File Split**: `MultiStorage.sol` (state, cancellation), `MultiInitializer.sol` (initiation), `MultiController.sol` (execution), reducing contract size.
- **SafeERC20 Removal**: Uses `IERC20` with balance checks, avoiding external dependencies.

## State Variables
- **nextHopId** (uint256, public, `MultiStorage.sol`): Tracks next hop ID.
- **settlementRouters** (SettlementRouter[], public, `MultiStorage.sol`): Stores settlement router addresses and types.
- **liquidRouters** (LiquidRouter[], public, `MultiStorage.sol`): Stores liquid router addresses and types.
- **agent** (address, public, `MultiStorage.sol`): Stores ISSAgent address.
- **totalHops** (uint256[], public, `MultiStorage.sol`): Global hop IDs.
- **hopsByAddress** (mapping(address => uint256[]), public, `MultiStorage.sol`): Maps maker to hop IDs.
- **hopID** (mapping(uint256 => StalledHop), public, `MultiStorage.sol`): Stores hop details.
- **mux** (address[], public, `MultiStorage.sol`): Stores mux addresses.
- **multiStorage** (MultiStorage, public, `MultiInitializer.sol`, `MultiController.sol`): Reference to `MultiStorage` contract.

## Structs
- **SettlementRouter** (`MultiStorage.sol`): `router` (address), `routerType` (uint8, 1 = SettlementRouter).
- **LiquidRouter** (`MultiStorage.sol`): `router` (address), `routerType` (uint8, 2 = LiquidRouter).
- **HopUpdateType** (`MultiStorage.sol`): `field` (string), `value` (uint256).
- **StalledHop** (`MultiStorage.sol`): `stage` (uint8), `currentListing` (address), `orderID` (uint256), `minPrice` (uint256), `maxPrice` (uint256), `hopMaker` (address), `remainingListings` (address[]), `principalAmount` (uint256), `startToken` (address), `endToken` (address), `settleType` (uint8), `hopStatus` (uint8), `maxIterations` (uint256).
- **CancelPrepData** (`MultiStorage.sol`): `hopId` (uint256), `listing` (address), `isBuy` (bool), `outputToken` (address), `inputToken` (address), `pending` (uint256), `filled` (uint256), `status` (uint8), `receivedAmount` (uint256), `recipient` (address), `refundedPending` (uint256).
- **CancelBalanceData** (`MultiStorage.sol`): `token` (address), `balanceBefore` (uint256), `balanceAfter` (uint256).
- **OrderUpdateData** (`MultiStorage.sol`, `MultiInitializer.sol`): `listing` (address), `recipient` (address), `inputAmount` (uint256), `priceLimit` (uint256), `inputToken` (address).
- **HopExecutionParams** (`MultiStorage.sol`, `MultiInitializer.sol`): `listingAddresses` (address[]), `impactPricePercents` (uint256[]), `startToken` (address), `endToken` (address), `settleType` (uint8), `maxIterations` (uint256), `numListings` (uint256).
- **HopRouteData** (`MultiStorage.sol`): `listings` (address[]), `isBuy` (bool[]).
- **HopOrderDetails** (`MultiStorage.sol`): `pending` (uint256), `filled` (uint256), `status` (uint8), `amountSent` (uint256), `recipient` (address).
- **HopPrepState** (`MultiInitializer.sol`): `numListings` (uint256), `listingAddresses` (address[]), `impactPricePercents` (uint256[]), `hopId` (uint256), `indices` (uint256[]), `isBuy` (bool[]).
- **StallData** (`MultiController.sol`): `hopId` (uint256), `listing` (address), `orderId` (uint256), `isBuy` (bool), `pending` (uint256), `filled` (uint256), `status` (uint8), `amountSent` (uint256), `hopMaker` (address).
- **HopExecutionData** (`MultiController.sol`): `listing` (address), `isBuy` (bool), `recipient` (address), `priceLimit` (uint256), `principal` (uint256), `inputToken` (address), `settleType` (uint8), `maxIterations` (uint256), `updates` (HopUpdateType[]).
- **OrderParams** (`MultiController.sol`): `listing` (address), `principal` (uint256), `impactPercent` (uint256), `index` (uint256), `numListings` (uint256), `maxIterations` (uint256), `settleType` (uint8).
- **HopPrepData** (`MultiController.sol`): `hopId` (uint256), `indices` (uint256[]), `isBuy` (bool[]), `currentToken` (address), `principal` (uint256), `maker` (address), `isNative` (bool).

## Formulas
1. **Price Impact**:
   - **Formula**: `impactPrice = (newXBalance * 1e18) / newYBalance`
   - **Used in**: `_validatePriceImpact` (`MultiController.sol`).
   - **Description**: Ensures trade price within `currentPrice * (10000 ± impactPercent) / 10000`.
2. **Amount Out**:
   - **Formula**: `amountOut = isBuy ? (inputAmount * xBalance) / yBalance : (inputAmount * yBalance) / xBalance`
   - **Used in**: `_validatePriceImpact` (`MultiController.sol`).
3. **Normalized Amount**:
   - **Formula**: `normalizedAmount = amount / (10 ** decimals)`
   - **Used in**: `normalizeForToken` (`MultiInitializer.sol`, `MultiController.sol`).
4. **Denormalized Amount**:
   - **Formula**: `rawAmount = normalizedAmount * (10 ** decimals)`
   - **Used in**: `denormalizeForToken` (`MultiInitializer.sol`, `MultiController.sol`).

## External Functions

### setMultiStorage(address storageAddress)
- **Files**: `MultiInitializer.sol`, `MultiController.sol`
- **Parameters**:
  - `storageAddress` (address): Address of the `MultiStorage` contract. Must be non-zero.
- **Behavior**: Sets the `multiStorage` state variable, enabling interaction with `MultiStorage.sol`. Restricted to contract owner. Reverts if `storageAddress` is zero.
- **Internal Call Tree**:
  - Validates `storageAddress != address(0)` ("Invalid storage address").
  - Assigns `multiStorage = MultiStorage(storageAddress)`.
  - No external calls or state changes beyond `multiStorage`.
- **Return Values**: None.
- **Balance Checks**: None.
- **Gas Controls**: Minimal gas, single state update.
- **Error Handling**:
  - Reverts if `storageAddress == address(0)` ("Invalid storage address").
  - Reverts if caller is not owner ("Ownable: caller is not the owner").

### addMux(address muxAddress)
- **File**: `MultiStorage.sol`
- **Parameters**:
  - `muxAddress` (address): Address to add to `mux` array. Must be non-zero and not already in `mux`.
- **Behavior**: Adds `muxAddress` to the `mux` array for external contract integration. Restricted to owner. Emits `MuxAdded(muxAddress)`.
- **Internal Call Tree**:
  - Validates `muxAddress != address(0)` ("Invalid mux address").
  - Checks `mux` array for duplicates.
  - Appends `muxAddress` to `mux`.
  - No external calls.
- **Return Values**: None.
- **Balance Checks**: None.
- **Gas Controls**: Minimal gas, single array append.
- **Error Handling**:
  - Reverts if `muxAddress == address(0)` ("Invalid mux address").
  - Reverts if `muxAddress` already exists ("Mux already exists").
  - Reverts if caller is not owner ("Ownable: caller is not the owner").

### removeMux(address muxAddress)
- **File**: `MultiStorage.sol`
- **Parameters**:
  - `muxAddress` (address): Address to remove from `mux` array. Must exist in `mux`.
- **Behavior**: Removes `muxAddress` from `mux` array using pop-and-swap. Restricted to owner. Emits `MuxRemoved(muxAddress)`.
- **Internal Call Tree**:
  - Validates `muxAddress != address(0)` ("Invalid mux address").
  - Searches `mux` for `muxAddress`.
  - Uses pop-and-swap to remove `muxAddress`.
  - No external calls.
- **Return Values**: None.
- **Balance Checks**: None.
- **Gas Controls**: Bounded by `mux` array length, pop-and-swap minimizes gas.
- **Error Handling**:
  - Reverts if `muxAddress == address(0)` ("Invalid mux address").
  - Reverts if `muxAddress` not found ("Mux not found").
  - Reverts if caller is not owner ("Ownable: caller is not the owner").

### setAgent(address newAgent)
- **File**: `MultiStorage.sol`
- **Parameters**:
  - `newAgent` (address): Address of the `ISSAgent` contract. Must be non-zero.
- **Behavior**: Sets the `agent` state variable for listing validation. Restricted to owner. Emits `AgentSet(newAgent)`.
- **Internal Call Tree**:
  - Validates `newAgent != address(0)` ("Invalid agent address").
  - Assigns `agent = newAgent`.
  - No external calls.
- **Return Values**: None.
- **Balance Checks**: None.
- **Gas Controls**: Minimal gas, single state update.
- **Error Handling**:
  - Reverts if `newAgent == address(0)` ("Invalid agent address").
  - Reverts if caller is not owner ("Ownable: caller is not the owner").

### addSettlementRouter(address router, uint8 routerType)
- **File**: `MultiStorage.sol`
- **Parameters**:
  - `router` (address): Settlement router address. Must be non-zero.
  - `routerType` (uint8): Router type (1 = SettlementRouter). Must be 1.
- **Behavior**: Adds or updates a settlement router in `settlementRouters`. Restricted to owner. Emits `SettlementRouterAdded(router, routerType)`.
- **Internal Call Tree**:
  - Validates `router != address(0)` ("Invalid router address").
  - Validates `routerType == 1` ("Invalid router type").
  - Checks `settlementRouters` for conflicts.
  - Updates or appends `SettlementRouter(router, routerType)`.
  - No external calls.
- **Return Values**: None.
- **Balance Checks**: None.
- **Gas Controls**: Minimal gas, single array update.
- **Error Handling**:
  - Reverts if `router == address(0)` ("Invalid router address").
  - Reverts if `routerType != 1` ("Invalid router type").
  - Reverts if router exists with different type ("Router type conflict").
  - Reverts if caller is not owner ("Ownable: caller is not the owner").

### addLiquidRouter(address router, uint8 routerType)
- **File**: `MultiStorage.sol`
- **Parameters**:
  - `router` (address): Liquid router address. Must be non-zero.
  - `routerType` (uint8): Router type (2 = LiquidRouter). Must be 2.
- **Behavior**: Adds or updates a liquid router in `liquidRouters`. Restricted to owner. Emits `LiquidRouterAdded(router, routerType)`.
- **Internal Call Tree**:
  - Validates `router != address(0)` ("Invalid router address").
  - Validates `routerType == 2` ("Invalid router type").
  - Checks `liquidRouters` for conflicts.
  - Updates or appends `LiquidRouter(router, routerType)`.
  - No external calls.
- **Return Values**: None.
- **Balance Checks**: None.
- **Gas Controls**: Minimal gas, single array update.
- **Error Handling**:
  - Reverts if `router == address(0)` ("Invalid router address").
  - Reverts if `routerType != 2` ("Invalid router type").
  - Reverts if router exists with different type ("Router type conflict").
  - Reverts if caller is not owner ("Ownable: caller is not the owner").

### removeRouter(address router)
- **File**: `MultiStorage.sol`
- **Parameters**:
  - `router` (address): Router address to remove. Must exist in `settlementRouters` or `liquidRouters`.
- **Behavior**: Removes `router` from `settlementRouters` or `liquidRouters` using pop-and-swap. Restricted to owner. Emits `RouterRemoved(router)`.
- **Internal Call Tree**:
  - Validates `router != address(0)` ("Invalid router address").
  - Searches `settlementRouters` and `liquidRouters` for `router`.
  - Uses pop-and-swap to remove `router`.
  - No external calls.
- **Return Values**: None.
- **Balance Checks**: None.
- **Gas Controls**: Bounded by array lengths, pop-and-swap minimizes gas.
- **Error Handling**:
  - Reverts if `router == address(0)` ("Invalid router address").
  - Reverts if `router` not found ("Router not found").
  - Reverts if caller is not owner ("Ownable: caller is not the owner").

### hopNative(address listing1, address listing2, address listing3, address listing4, uint256 impactPercent, address startToken, address endToken, uint8 settleType, uint256 maxIterations)
- **File**: `MultiInitializer.sol`
- **Parameters**:
  - `listing1` (address): First listing address. Must be non-zero and valid via `ISSAgent.getListing`.
  - `listing2`, `listing3`, `listing4` (address): Optional listing addresses (can be zero).
  - `impactPercent` (uint256): Price impact tolerance (scaled to 1000, e.g., 500 = 5%). Must be ≤ 1000.
  - `startToken` (address): Input token (address(0) for native). Must match listing token pair.
  - `endToken` (address): Output token. Must match listing token pair.
  - `settleType` (uint8): Settlement type (0 = market, 1 = liquid). Must be 0 or 1.
  - `maxIterations` (uint256): Max settlement iterations. Must be > 0.
- **Behavior**: Initiates a native currency hop, creating a multi-step swap. Validates listings, token path, and transfers native currency. Stores hop in `hopID`, updates `hopsByAddress` and `totalHops`. Emits `HopStarted(hopId, msg.sender)`. Protected by `nonReentrant` and `onlyValidListing`.
- **Internal Call Tree**:
  - `validateHopRequest(listing1, listing2, listing3, listing4, startToken, endToken, settleType, maxIterations)`:
    - Checks `listing1 != address(0)`, `settleType <= 1`, `maxIterations > 0`.
    - Calls `ISSAgent.getListing` for non-zero listings.
    - Reverts if listings invalid or token path infeasible.
  - `computeRoute(listing1, listing2, listing3, listing4, startToken, endToken)`:
    - Calls `ISSListing.tokenA` and `tokenB` to build path.
    - Returns `HopPrepState` with listings, indices, and `isBuy` flags.
  - `executeHopSteps(HopExecutionParams, HopPrepState)`:
    - Calls `computeBuyOrderParams` or `computeSellOrderParams` (`MultiController.sol`).
    - Calls `processHopStep`:
      - Calls `_createHopOrderNative`:
        - Calls `_checkTransferNative` (pre/post balance checks).
        - Calls `ISSListing.update` to create order.
      - Calls `safeSettle`:
        - Calls `ICCSettlementRouter.settleBuyOrders` or `settleSellOrders` (if `settleType == 0`).
        - Calls `ICCLiquidRouter.settleBuyLiquid` or `settleSellLiquid` (if `settleType == 1`).
      - Calls `checkOrderStatus`:
        - Calls `ISSListing.getBuyOrderCore`, `getSellOrderCore`, `getBuyOrderAmounts`, or `getSellOrderAmounts`.
    - Calls `this.MHUpdate` (`MultiStorage.sol`) to update `hopID`, `hopsByAddress`, `totalHops`.
- **Return Values**: None.
- **Balance Checks**:
  - Pre: `address(listing).balance` in `_checkTransferNative`.
  - Post: `balanceAfter > balanceBefore` in `_checkTransferNative`.
- **Gas Controls**: `maxIterations` for settlements, up to 4 listings, pop-and-swap for arrays.
- **Error Handling**:
  - Reverts if `listing1 == address(0)` ("Invalid listing").
  - Reverts if `settleType > 1` ("Invalid settle type").
  - Reverts if `maxIterations == 0` ("Max iterations must be positive").
  - Reverts if `impactPercent > 1000` ("Invalid impact percent").
  - Reverts if token path invalid ("Invalid token path").
  - Reverts if native transfer fails ("Native transfer failed").
  - Reverts if order creation fails ("Native order creation failed: <reason>").

### hopToken(address listing1, address listing2, address listing3, address listing4, uint256 impactPercent, address startToken, address endToken, uint8 settleType, uint256 maxIterations)
- **File**: `MultiInitializer.sol`
- **Parameters**:
  - `listing1`, `listing2`, `listing3`, `listing4` (address): Same as `hopNative`.
  - `impactPercent` (uint256): Same as `hopNative`.
  - `startToken` (address): Input token (non-zero for ERC20). Must match listing token pair.
  - `endToken` (address): Same as `hopNative`.
  - `settleType` (uint8): Same as `hopNative`.
  - `maxIterations` (uint256): Same as `hopNative`.
- **Behavior**: Initiates an ERC20 token hop, creating a multi-step swap. Validates listings, token path, and transfers ERC20 tokens. Stores hop in `hopID`, updates `hopsByAddress` and `totalHops`. Emits `HopStarted(hopId, msg.sender)`. Protected by `nonReentrant` and `onlyValidListing`.
- **Internal Call Tree**:
  - Same as `hopNative`, except:
    - Calls `_createHopOrderToken`:
      - Calls `IERC20.transferFrom(msg.sender, this, amount)`.
      - Calls `IERC20.approve(listing, amount)`.
      - Calls `_checkTransferToken` (pre/post balance checks).
      - Calls `ISSListing.update` to create order.
- **Return Values**: None.
- **Balance Checks**:
  - Pre: `IERC20.balanceOf(listing)` in `_checkTransferToken`.
  - Post: `balanceAfter > balanceBefore` in `_checkTransferToken`.
- **Gas Controls**: Same as `hopNative`.
- **Error Handling**:
  - Same as `hopNative`, plus:
  - Reverts if `startToken == address(0)` ("Invalid token address").
  - Reverts if token transfer fails ("Token transfer from sender failed").
  - Reverts if token approval fails ("Token approval for listing failed").
  - Reverts if order creation fails ("Token order creation failed: <reason>").

### continueHop(uint256 hopId, uint256 maxIterations)
- **File**: `MultiController.sol`
- **Parameters**:
  - `hopId` (uint256): Hop ID to continue. Must be < `nextHopId` and `hopStatus == 1`.
  - `maxIterations` (uint256): Max hop steps to process. Must be > 0.
- **Behavior**: Continues a stalled hop, processing remaining listings. Updates `hopID`, `hopsByAddress`, and `totalHops`. Emits `HopContinued(hopId, stage)`. Completes hop if all steps are executed (`hopStatus = 2`). Protected by `nonReentrant`.
- **Internal Call Tree**:
  - Validates `hopId < this.nextHopId()` ("Invalid hop ID").
  - Validates `maxIterations > 0` ("Max iterations must be positive").
  - Validates `hopStatus == 1` ("Hop is not pending").
  - Validates `hopMaker == msg.sender` ("Caller is not hop maker").
  - Constructs `HopPrepData` and `HopExecutionParams` from `hopID`.
  - Calls `executeHopSteps(HopExecutionParams, HopPrepData)`:
    - Calls `computeBuyOrderParams` or `computeSellOrderParams`:
      - Calls `_validatePriceImpact` (computes price impact).
    - Calls `processHopStep`:
      - Calls `_createHopOrderNative` or `_createHopOrderToken`.
      - Calls `safeSettle`.
      - Calls `checkOrderStatus`.
    - Calls `this.MHUpdate` to update `hopID`, `hopsByAddress`, `totalHops`.
- **Return Values**: None.
- **Balance Checks**: Same as `hopNative` or `hopToken` based on `isNative`.
- **Gas Controls**: `maxIterations` limits hop steps, `StalledHop.maxIterations` for settlements, pop-and-swap for arrays.
- **Error Handling**:
  - Reverts if `hopId >= this.nextHopId()` ("Invalid hop ID").
  - Reverts if `maxIterations == 0` ("Max iterations must be positive").
  - Reverts if `hopStatus != 1` ("Hop is not pending").
  - Reverts if `msg.sender != hopMaker` ("Caller is not hop maker").
  - Reverts on transfer or order failures (same as `hopNative`/`hopToken`).

### executeStalls(uint256 maxIterations)
- **File**: `MultiController.sol`
- **Parameters**:
  - `maxIterations` (uint256): Max stalled hops to process. Must be > 0.
- **Behavior**: Processes up to `maxIterations` stalled hops globally, using `StalledHop.maxIterations` for settlements. Prepares stalls, executes steps, and updates state. Emits `StallsPrepared(0, count)`, `StallsExecuted(0, count)`, `HopContinued(hopId, stage)`. Protected by `nonReentrant`.
- **Internal Call Tree**:
  - Validates `maxIterations > 0` ("Max iterations must be positive").
  - Calls `prepStalls()`:
    - Iterates `this.totalHops()` (capped at 20).
    - Calls `checkOrderStatus` for each hop.
    - Returns `StallData[]` (resized to `count`).
  - Iterates `StallData[]` (up to `maxIterations`):
    - Constructs `HopPrepData` and `HopExecutionParams`.
    - Calls `executeHopSteps` (same as `continueHop`).
  - Calls `this.MHUpdate` for state updates.
- **Return Values**: None.
- **Balance Checks**: Same as `hopNative` or `hopToken` based on `isNative`.
- **Gas Controls**: `maxIterations` limits hops, 20-stall cap in `prepStalls`, `StalledHop.maxIterations` for settlements, pop-and-swap for arrays.
- **Error Handling**:
  - Reverts if `maxIterations == 0` ("Max iterations must be positive").
  - Reverts on transfer or order failures (same as `hopNative`/`hopToken`).

### cancelHop(uint256 hopId)
- **File**: `MultiStorage.sol`
- **Parameters**:
  - `hopId` (uint256): Hop ID to cancel. Must be < `nextHopId`, `hopStatus == 1`, and owned by `msg.sender`.
- **Behavior**: Cancels a stalled hop, refunding `pending` in input token via `_handlePending`, and `amountSent` or `filled` in output token via `_handleFilledOrSent`. Updates `hopID.principalAmount` with `refundedPending`. Sets `hopStatus = 2` and removes from `hopsByAddress`. Emits `HopCanceled(hopId)`. Protected by `nonReentrant`.
- **Internal Call Tree**:
  - Validates `hopId < this.nextHopId()` ("Invalid hop ID").
  - Validates `hopStatus == 1` ("Hop is not pending").
  - Validates `hopMaker == msg.sender` ("Caller is not hop maker").
  - Calls `_prepCancelHopBuy` or `_prepCancelHopSell`:
    - Calls `checkOrderStatus`:
      - Calls `ISSListing.getBuyOrderCore`, `getSellOrderCore`, `getBuyOrderAmounts`, or `getSellOrderAmounts`.
    - Returns `CancelPrepData`.
  - Calls `_executeClearHopOrder`:
    - Calls `ISSListing.update` to set order status.
    - Calls `_handleFilledOrSent`:
      - Calls `_checkTransferToken` or `_checkTransferNative` for output token refund.
    - Calls `_handlePending`:
      - Calls `_checkTransferToken` or `_checkTransferNative` for input token refund.
      - Updates `refundedPending`.
    - Calls `this.updateHopField` to update `principalAmount`.
  - Calls `_finalizeCancel`:
    - Sets `hopStatus = 2`.
    - Removes `hopId` from `hopsByAddress` using pop-and-swap.
    - Calls `this.MHUpdate` for state consistency.
- **Return Values**: None.
- **Balance Checks**:
  - Pre: `IERC20.balanceOf(this)` or `address(this).balance` in `_executeClearHopOrder`.
  - Post: `balanceAfter > balanceBefore` in `_checkTransferToken` or `_checkTransferNative`.
- **Gas Controls**: Single hop processing, pop-and-swap for `hopsByAddress`.
- **Error Handling**:
  - Reverts if `hopId >= this.nextHopId()` ("Invalid hop ID").
  - Reverts if `hopStatus != 1` ("Hop is not pending").
  - Reverts if `msg.sender != hopMaker` ("Caller is not hop maker").
  - Reverts if order not cancellable ("Order not cancellable").
  - Reverts if transfers fail ("ERC20 transfer failed", "Native transfer failed").

### cancelAll(uint256 maxIterations)
- **File**: `MultiStorage.sol`
- **Parameters**:
  - `maxIterations` (uint256): Max hops to cancel. Must be > 0.
- **Behavior**: Cancels up to `maxIterations` stalled hops for `msg.sender`, refunding as in `cancelHop`. Emits `AllHopsCanceled(count)`. Protected by `nonReentrant`.
- **Internal Call Tree**:
  - Validates `maxIterations > 0` ("Max iterations must be positive").
  - Iterates `this.hopsByAddress(msg.sender)` (up to `maxIterations`):
    - Checks `hopID.hopStatus == 1`.
    - Calls `_cancelHop` (same as `cancelHop` internal flow).
  - Calls `this.MHUpdate` for state updates.
- **Return Values**: None.
- **Balance Checks**: Same as `cancelHop`.
- **Gas Controls**: `maxIterations` limits hops, pop-and-swap for `hopsByAddress`.
- **Error Handling**:
  - Reverts if `maxIterations == 0` ("Max iterations must be positive").
  - Reverts on transfer or order failures (same as `cancelHop`).

## Additional Details
- **Decimal Handling**: Uses `normalizeForToken` and `denormalizeForToken` for tokens with decimals ≤ 18.
- **Reentrancy Protection**: `nonReentrant` on state-changing functions.
- **Gas Optimization**: Uses `maxIterations`, pop-and-swap, 20-stall cap.
- **Listing Validation**: Via `validateHopRequest` and `onlyValidListing`.
- **Token Flow**: Buy: `tokenB` → `tokenA`; sell: `tokenA` → `tokenB`.
- **Hop Lifecycle**: Stalled (`hopStatus = 1`), cancelled/completed (`hopStatus = 2`).
- **Events**: `HopStarted`, `HopContinued`, `HopCanceled`, `AllHopsCanceled`, `StallsPrepared`, `StallsExecuted`, `SettlementRouterAdded`, `LiquidRouterAdded`, `RouterRemoved`, `AgentSet`, `MuxAdded`, `MuxRemoved`.
- **Safety**: Explicit casting, balance checks, no inline assembly.
