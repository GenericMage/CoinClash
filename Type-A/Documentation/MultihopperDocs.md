# Multihopper Contract Documentation

## Overview
The `Multihopper` system, implemented in Solidity (^0.8.2), facilitates multi-step token swaps across up to four listings, supporting market and liquid order settlements with price impact controls. It integrates with `ISSListing`, `ICCRouter`, and `ISSAgent` interfaces, uses `IERC20` for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The system is split into three contracts (`MultiStorage.sol`, `MultiInitializer.sol`, `MultiController.sol`) to reduce deployment overhead and improve modularity. It manages hop creation, execution, continuation, and cancellation, with gas optimization, robust decimal handling, and accurate refund tracking via `refundedPending` in `CancelPrepData`. State variables are public, accessed directly, and mappings ensure efficient hop tracking.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.53 (last updated 2025-08-12, corrected `hopNative`/`hopToken` call tree, clarified principal transfers)

**Compatible Contracts:**
- `SSRouter` v0.0.61
- `SSListingTemplate` v0.0.10

## Clarifications
- **Path-Finding Mechanism**: `computeRoute` (`MultiInitializer.sol`) precomputes a valid token path, ensuring `startToken` connects to `endToken`, reverting if no valid path exists.
- **Usage of amountSent**: Tracks output token amount from a hop step, used as `principal` for the next step in `executeStalls` and `processHopStep` (`MultiController.sol`).
- **Usage of filled**: Tracks settled input token amount, refunded in input token via `_handleFilledOrSent` during cancellation if `amountSent` is zero.
- **Field Conflicts**: Avoids conflicts with `SSListingTemplate` by mapping `getBuyOrderAmounts`/`getSellOrderAmounts` to `StallData` explicitly.
- **Listing Validation**: `onlyValidListing` modifier and `validateHopRequest` ensure listings are registered via `ISSAgent.getListing`.
- **Hop Cancellation Refunds**: Refunds `pending` in input token via `_handlePending`, `amountSent` or `filled` in output token via `_handleFilledOrSent`. `refundedPending` tracks actual refunded amounts, updating `hopID.principalAmount`.
- **Balance Checks**: `_checkTransfer` verifies transfers with pre/post balance checks, uses the exact amount recieved, supporting native and ERC20 tokens with normalization.
- **Single Listing Route**: Validates `listing1` and token pair for single-step swaps.
- **maxIterations Usage**: Stored in `StalledHop` for settlements, separate from `maxIterations` in `continueHop` and `executeStalls`.
- **File Split**: `MultiStorage.sol` (state, cancellation), `MultiInitializer.sol` (initiation), `MultiController.sol` (execution), reducing contract size.
- **SafeERC20 Removal**: Uses `IERC20` with balance checks, avoiding external dependencies.
- **Principal Transfers**: `hopNative`/`hopToken` transfer principal to `multiController`, then to listings in `MultiController.sol`. Pre/post balance checks ensure accurate transfers.
- **Multihopper as a Router**: `MultiController` is supposed to be a registered router in CCAgent, which sets it in listing addresses, thereby allowing it to call `update` to create orders directly. 

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
- **multiController** (address, public, `MultiInitializer.sol`): Stores MultiController address for principal transfers.

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

### setMultiController(address controllerAddress)
- **File**: `MultiInitializer.sol`
- **Parameters**:
  - `controllerAddress` (address): Address of the `MultiController` contract. Must be non-zero.
- **Behavior**: Sets the `multiController` state variable for principal transfers. Restricted to owner. Reverts if `controllerAddress` is zero.
- **Internal Call Tree**:
  - Validates `controllerAddress != address(0)` ("Invalid controller address").
  - Assigns `multiController = controllerAddress`.
  - No external calls.
- **Return Values**: None.
- **Balance Checks**: None.
- **Gas Controls**: Minimal gas, single state update.
- **Error Handling**:
  - Reverts if `controllerAddress == address(0)` ("Invalid controller address").
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
- **Behavior**: Initiates a native currency hop, transferring `msg.value` to `multiController`. Validates listings, token path, and stores hop in `hopID`, updates `hopsByAddress` and `totalHops`. Emits `HopStarted(hopId, msg.sender, numListings)`. Protected by `nonReentrant` and `onlyValidListing`.
- **Internal Call Tree**:
  - `validateHopRequest`: Checks listings, `settleType`, `maxIterations`, calls `ISSAgent.getListing`.
  - `computeRoute`: Calls `ISSListing.tokenA`, `tokenB` to build path, returns indices and `isBuy` flags.
  - `prepHop`: Constructs `HopPrepState`, validates routers via `checkRouters`.
  - `prepareHopExecution`: Initializes `HopExecutionParams`, calls `initializeHopData`.
  - `_createHopOrderNative`: Transfers `msg.value` to `multiController`, calls `_checkTransferNative` for pre/post balance checks.
  - `MHUpdate`: Updates `hopID`, `hopsByAddress`, `totalHops` via `MultiStorage.sol`.
- **Return Values**: None.
- **Balance Checks**:
  - Pre: `address(multiController).balance` in `_createHopOrderNative`.
  - Post: `balanceAfter - balanceBefore == rawAmount`.
- **Gas Controls**: Up to 4 listings, pop-and-swap for arrays.
- **Error Handling**:
  - Reverts if `listing1 == address(0)` ("Invalid listing").
  - Reverts if `settleType > 1` ("Invalid settle type").
  - Reverts if `maxIterations == 0` ("Max iterations must be positive").
  - Reverts if `impactPercent > 1000` ("Impact percent exceeds 1000").
  - Reverts if token path invalid ("No valid route from startToken to endToken").
  - Reverts if native transfer fails ("Native transfer failed").

### hopToken(address listing1, address listing2, address listing3, address listing4, uint256 impactPercent, address startToken, address endToken, uint8 settleType, uint256 maxIterations)
- **File**: `MultiInitializer.sol`
- **Parameters**: Same as `hopNative`, except `startToken` is ERC20 (non-zero).
- **Behavior**: Initiates an ERC20 token hop, transferring tokens from `msg.sender` to `multiController`. Validates listings, token path, and stores hop in `hopID`, updates `hopsByAddress` and `totalHops`. Emits `HopStarted(hopId, msg.sender, numListings)`. Protected by `nonReentrant` and `onlyValidListing`.
- **Internal Call Tree**:
  - Same as `hopNative`, except `_createHopOrderToken`:
    - Calls `IERC20.transferFrom(msg.sender, multiController, amount)`.
    - Calls `_checkTransferToken` for pre/post balance checks.
- **Return Values**: None.
- **Balance Checks**:
  - Pre: `IERC20.balanceOf(multiController)` in `_createHopOrderToken`.
  - Post: `balanceAfter - balanceBefore == rawAmount`.
- **Gas Controls**: Same as `hopNative`.
- **Error Handling**:
  - Same as `hopNative`, plus:
  - Reverts if `startToken == address(0)` ("Invalid token address").
  - Reverts if token transfer fails ("Token transfer to controller failed").

### continueHop(uint256 hopId, uint256 maxIterations)
- **File**: `MultiController.sol`
- **Parameters**:
  - `hopId` (uint256): Hop ID to continue. Must be < `nextHopId` and `hopStatus == 1`.
  - `maxIterations` (uint256): Max hop steps. Must be > 0.
- **Behavior**: Continues a stalled hop, processing remaining listings. Creates orders via `ISSListing.update` and settles via `safeSettle`. Updates state and emits `HopContinued(hopId, stage)`. Completes hop if finished (`hopStatus = 2`). Protected by `nonReentrant`.
- **Internal Call Tree**:
  - Validates `hopId < nextHopId()`, `hopStatus == 1`, `hopMaker == msg.sender`.
  - Constructs `HopPrepData` and `HopExecutionParams` from `hopID`.
  - Calls `executeHopSteps`:
    - Calls `computeBuyOrderParams` or `computeSellOrderParams`:
      - Calls `_validatePriceImpact` (computes price impact).
    - Calls `processHopStep`:
      - Calls `_createHopOrderNative` or `_createHopOrderToken` (includes `ISSListing.update`).
      - Calls `safeSettle` (calls `ICCSettlementRouter` or `ICCLiquidRouter`).
      - Calls `checkOrderStatus` (calls `ISSListing.getBuyOrderCore`, `getSellOrderCore`, `getBuyOrderAmounts`, or `getSellOrderAmounts`).
    - Calls `MHUpdate` to update `hopID`, `hopsByAddress`, `totalHops`.
- **Return Values**: None.
- **Balance Checks**:
  - Pre: `address(listing).balance` or `IERC20.balanceOf(listing)` in `_createHopOrderNative/Token`.
  - Post: `balanceAfter - balanceBefore == rawAmount`.
- **Gas Controls**: `maxIterations` for steps, `StalledHop.maxIterations` for settlements, pop-and-swap for arrays.
- **Error Handling**:
  - Reverts if `hopId >= nextHopId()` ("Invalid hop ID").
  - Reverts if `maxIterations == 0` ("Max iterations must be positive").
  - Reverts if `hopStatus != 1` ("Hop is not pending").
  - Reverts if `msg.sender != hopMaker` ("Caller is not hop maker").
  - Reverts on transfer or order failures.

### executeStalls(uint256 maxIterations)
- **File**: `MultiController.sol`
- **Parameters**:
  - `maxIterations` (uint256): Max stalled hops to process. Must be > 0.
- **Behavior**: Processes stalled hops globally, using `StalledHop.maxIterations` for settlements. Creates orders via `ISSListing.update` and settles via `safeSettle`. Emits `StallsPrepared`, `StallsExecuted`, `HopContinued`. Protected by `nonReentrant`.
- **Internal Call Tree**:
  - Validates `maxIterations > 0`.
  - Calls `prepStalls`:
    - Iterates `totalHops` (up to `mmaxIterations`).
    - Calls `checkOrderStatus` for each hop.
    - Returns `StallData[]`.
  - Iterates `StallData[]` (up to `maxIterations`):
    - Constructs `HopPrepData` and `HopExecutionParams`.
    - Calls `executeHopSteps` (same as `continueHop`).
  - Calls `MHUpdate` for state updates.
- **Return Values**: None.
- **Balance Checks**: Same as `continueHop`.
- **Gas Controls**: `maxIterations` for hops and `prepStalls`, `StalledHop.maxIterations` for settlements.
- **Error Handling**:
  - Reverts if `maxIterations == 0` ("Max iterations must be positive").
  - Reverts on transfer or order failures.

## Additional Details
- **Decimal Handling**: Uses `normalizeForToken` and `denormalizeForToken` for tokens with decimals ≤ 18.
- **Reentrancy Protection**: `nonReentrant` on state-changing functions.
- **Gas Optimization**: Uses `maxIterations`, pop-and-swap.
- **Listing Validation**: Via `validateHopRequest` and `onlyValidListing`.
- **Token Flow**: Buy: `tokenB → tokenA`; sell: `tokenA → tokenB`. From `startToken` to `endToken` via `amountSent` in `MultiController.sol`.
- **Hop Lifecycle**: Stalled (`hopStatus = 1`), cancelled/completed (`hopStatus = 2`).
- **Events**: `HopStarted`, `HopContinued`, `HopCanceled`, `AllHopsCanceled`, `StallsPrepared`, `StallsExecuted`, `SettlementRouterAdded`, `LiquidRouterAdded`, `RouterRemoved`, `AgentSet`, `MuxAdded`, `MuxRemoved`.
- **Safety**: Explicit casting, balance checks, no inline assembly.
