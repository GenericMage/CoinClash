 # ShockEntry Contract Documentation

## Overview
The `ShockEntry` contract, implemented in Solidity (^0.8.2), facilitates multi-hop token swaps via `MultiInitializer`, followed by position creation using `CCSEntryDriver` or `CISEntryDriver`, finalized by `ICCSExecutionDriver` or `ICISExecutionDriver`. It supports up to four listings per hop, handles ERC20 and native tokens, normalizes amounts/prices to 1e18 precision, and ensures secure position creation with leverage, stop-loss, and take-profit settings. It uses `ReentrancyGuard` for security and `Ownable` for administrative control, avoiding `SafeERC20`, inline assembly, and reserved keywords. Public state variables are accessed directly, with mappings tracking user hops and entry details.

- **SPDX License**: BSL 1.1 - Peng Protocol 2025
- **Version**: 0.0.82 (updated 2025-08-13)
- **Change Log**:
  - 2025-08-13: Updated for `listings` array, `tokenPath`, refactored `_executeHop` to improve gas efficiency.
  - 2025-08-13: Clarified `executeEntryStalls`, `_continueEntryHops`, and `continueEntryHop` documentation to state that failed `IMultiController.continueHop` calls leave `status = 1`, requiring manual cancellation via `cancelEntryHop`.
  - 2025-08-13: Added `multiStorage` state variable and `setMultiStorage` function, corrected cancellation flow to reflect `MultiStorage` handling.
  - 2025-08-12: Consolidated cancellation functions, added maker restrictions.
- **Compatible Contracts**:
  - `MultiInitializer` v0.0.44
  - `MultiController` v0.0.44
  - `MultiStorage` v0.0.49
  - `CCSEntryDriver` v0.0.61
  - `CISEntryDriver` v0.0.61
  - `ICCSExecutionDriver`
  - `ICISExecutionDriver`
  - `ISSListingTemplate` v0.0.10

## Clarifications
- **Token Flow**: ERC20 tokens are transferred from `msg.sender` to `ShockEntry` via `IERC20.transferFrom`, approved for `MultiInitializer`, swapped to `endToken`, and used for position creation. Native tokens are sent via `msg.value` and forwarded to `MultiInitializer`. Refunds on cancellation are processed via `MultiStorage.cancelHop`, called by `MultiController.cancelHop`, with funds returned to `ShockEntry` and then to the `maker` via `_refundMaker`.
- **Hop Execution**: `_executeEntryHopToken`/`_executeEntryHopNative` initiate hops via `MultiInitializer.hopToken`/`hopNative`, store details in split `EntryHop` structs, call `IMultiController.executeStalls` to process stalled hops, and attempt continuation via `_attemptContinuation`. If `executeStalls` completes the hop (`MultiStorage.hopID.hopStatus = 2`), `continueHop` may revert, but `try-catch` ensures graceful degradation.
- **Position Creation**: On successful hop (`hopStatus = 2`), `_attemptContinuation` calls `executePositions` on the entry driver (`CCSEntryDriver`/`CISEntryDriver`) and `executeEntries` on the execution driver (`ICCSExecutionDriver`/`ICISExecutionDriver`).
- **Continuation**: `continueEntryHop`, `continueCrossEntryHops`, and `continueIsolatedEntryHops` process stalled hops (`entryHopsMargin.status = 1`, `maker = msg.sender`), calling `IMultiController.continueHop` and triggering position creation. `executeEntryStalls` processes stalled hops globally without maker restriction, using `IMultiStorage.totalHops`.
- **Cancellation**: `cancelEntryHop` cancels a hop, restricted to the `maker`, calling `IMultiController.cancelHop`, which uses `MultiStorage.cancelHop` to process refunds, returned to `ShockEntry` and sent to the `maker` via `_refundMaker`, updating `status = 3`.
- **Maker Flexibility**: `crossEntryHopToken`/`Native` and `isolatedEntryHopToken`/`Native` allow a `maker` address, defaulting to `msg.sender` if `address(0)`.
- **Decimal Handling**: Amounts/prices are normalized to 1e18 using `IERC20.decimals` for ERC20 tokens; native tokens use raw values.
- **Hop Lifecycle**: Hops are pending (1), completed (2), or cancelled (3) in `entryHopsMargin.status`, with `MultiStorage.hopID.hopStatus` indicating stalled (1) or completed (2).
- **Stalling Stages**:
  - **Multihop**: Stalls if `hopStatus = 1` (e.g., liquidity issues).
  - **Pre-Position Creation**: Rare, as `continueHop` typically completes the hop.
  - **Position Creation Pre-Entry**: Post-`driveToken`/`driveNative`, pending `executeEntries`, resolved by continuation functions.
- **Gas Optimization**: Uses `maxIterations`, split structs, and helper functions (`_validateAndSetupHop`, `_transferAndApproveTokens`, `_executeMultihop`, `_attemptContinuation`) to reduce stack usage and gas costs.
- **Safety**: Explicit casting, `try-catch` for external calls, no reserved keywords, and maker-only restrictions ensure secure operation.

## State Variables
- **ccsEntryDriver** (address, public): Address of `CCSEntryDriver`, set via `setCCSEntryDriver`.
- **cisEntryDriver** (address, public): Address of `CISEntryDriver`, set via `setCISEntryDriver`.
- **ccsExecutionDriver** (address, public): Address of `ICCSExecutionDriver`, set via `setCCSExecutionDriver`.
- **cisExecutionDriver** (address, public): Address of `ICISExecutionDriver`, set via `setCISExecutionDriver`.
- **multiInitializer** (address, public): Address of `MultiInitializer`, set via `setMultiInitializer`.
- **multiController** (address, public): Address of `MultiController`, set via `setMultiController`.
- **multiStorage** (address, public): Address of `MultiStorage`, set via `setMultiStorage`.
- **hopCount** (uint256, public): Tracks total hops, incremented per hop.
- **userHops** (mapping(address => uint256[]), public): Maps user addresses to their hop IDs.
- **entryHopsCore** (mapping(uint256 => EntryHopCore), public): Stores core hop data (maker, hopId, listingAddress, positionType).
- **entryHopsMargin** (mapping(uint256 => EntryHopMargin), public): Stores margin data (initialMargin, excessMargin, leverage, status).
- **entryHopsParams** (mapping(uint256 => EntryHopParams), public): Stores position parameters (stopLossPrice, takeProfitPrice, endToken, isCrossDriver, minEntryPrice, maxEntryPrice).
- **hopContexts** (mapping(uint256 => HopContext), private): Stores temporary hop data (maker, hopId, startToken, totalAmount, isCrossDriver).

## Structs
- **EntryHopCore**:
  - `maker` (address): Hop initiator.
  - `hopId` (uint256): Unique hop identifier.
  - `listingAddress` (address): Position listing address.
  - `positionType` (uint8): 0 for long, 1 for short.
- **EntryHopMargin**:
  - `initialMargin` (uint256): Initial margin amount (1e18 precision).
  - `excessMargin` (uint256): Excess margin amount (1e18 precision).
  - `leverage` (uint8): Leverage multiplier.
  - `status` (uint8): 1 (pending), 2 (completed), 3 (cancelled).
- **EntryHopParams**:
  - `stopLossPrice` (uint256): Stop-loss price (1e18 precision).
  - `takeProfitPrice` (uint256): Take-profit price (1e18 precision).
  - `endToken` (address): Final token after swap.
  - `isCrossDriver` (bool): True for `CCSEntryDriver`, false for `CISEntryDriver`.
  - `minEntryPrice` (uint256): Minimum entry price (1e18 precision).
  - `maxEntryPrice` (uint256): Maximum entry price (1e18 precision).
- **HopParams**:
  - `listings` (address[]): Up to four listing addresses for the hop.
  - `tokenPath` (address[]): Start and end tokens for the swap.
  - `impactPercent` (uint256): Price impact percentage.
  - `settleType` (uint8): 0 (market), 1 (liquid).
  - `maxIterations` (uint256): Max iterations for hop processing.
- **PositionParams**:
  - `listingAddress` (address): Position listing address.
  - `minEntryPrice` (uint256): Minimum entry price (1e18 precision).
  - `maxEntryPrice` (uint256): Maximum entry price (1e18 precision).
  - `initialMargin` (uint256): Initial margin amount (1e18 precision).
  - `excessMargin` (uint256): Excess margin amount (1e18 precision).
  - `leverage` (uint8): Leverage multiplier.
  - `stopLossPrice` (uint256): Stop-loss price (1e18 precision).
  - `takeProfitPrice` (uint256): Take-profit price (1e18 precision).
  - `positionType` (uint8): 0 (long), 1 (short).
- **HopContext**:
  - `maker` (address): Hop initiator.
  - `hopId` (uint256): Hop identifier.
  - `startToken` (address): Initial token (`address(0)` for native).
  - `totalAmount` (uint256): Total margin (1e18 precision).
  - `isCrossDriver` (bool): Driver selection flag.

## Events
- **EntryHopStarted(address indexed maker, uint256 indexed entryHopId, uint256 hopId, bool isCrossDriver)**: Emitted when a hop is initiated.
- **EntryHopCancelled(uint256 indexed entryHopId, uint256 refundedAmount, string reason)**: Emitted on hop cancellation or failure.

## External Functions

### setMultiInitializer(address _multiInitializer)
- **Parameters**:
  - `_multiInitializer` (address): Address of `MultiInitializer` contract.
- **Returns**: None.
- **Behavior**: Sets `multiInitializer` address, used by `_executeMultihop` to initiate hops. Reverts with `ErrorLogged("MultiInitializer address cannot be zero")` if `_multiInitializer` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `multiInitializer` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_multiInitializer`.

### setMultiController(address _multiController)
- **Parameters**:
  - `_multiController` (address): Address of `MultiController` contract.
- **Returns**: None.
- **Behavior**: Sets `multiController` address, used by `_attemptContinuation` and continuation functions. Reverts with `ErrorLogged("MultiController address cannot be zero")` if `_multiController` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `multiController` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_multiController`.

### setMultiStorage(address _multiStorage)
- **Parameters**:
  - `_multiStorage` (address): Address of `MultiStorage` contract.
- **Returns**: None.
- **Behavior**: Sets `multiStorage` address, used by `_executeEntryStalls` and cancellation functions. Reverts with `ErrorLogged("MultiStorage address cannot be zero")` if `_multiStorage` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `multiStorage` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_multiStorage`.

### setCCSEntryDriver(address _ccsEntryDriver)
- **Parameters**:
  - `_ccsEntryDriver` (address): Address of `CCSEntryDriver` contract.
- **Returns**: None.
- **Behavior**: Sets `ccsEntryDriver` address, used by `_attemptContinuation` for cross-driver position creation. Reverts with `ErrorLogged("CCSEntryDriver address cannot be zero")` if `_ccsEntryDriver` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `ccsEntryDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_ccsEntryDriver`.

### setCISEntryDriver(address _cisEntryDriver)
- **Parameters**:
  - `_cisEntryDriver` (address): Address of `CISEntryDriver` contract.
- **Returns**: None.
- **Behavior**: Sets `cisEntryDriver` address, used by `_attemptContinuation` for isolated-driver position creation. Reverts with `ErrorLogged("CISEntryDriver address cannot be zero")` if `_cisEntryDriver` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `cisEntryDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_cisEntryDriver`.

### setCCSExecutionDriver(address _ccsExecutionDriver)
- **Parameters**:
  - `_ccsExecutionDriver` (address): Address of `ICCSExecutionDriver` contract.
- **Returns**: None.
- **Behavior**: Sets `ccsExecutionDriver` address, used by `_attemptContinuation` for cross-driver entry execution. Reverts with `ErrorLogged("CCSExecutionDriver address cannot be zero")` if `_ccsExecutionDriver` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `ccsExecutionDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_ccsExecutionDriver`.

### setCISExecutionDriver(address _cisExecutionDriver)
- **Parameters**:
  - `_cisExecutionDriver` (address): Address of `ICISExecutionDriver` contract.
- **Returns**: None.
- **Behavior**: Sets `cisExecutionDriver` address, used by `_attemptContinuation` for isolated-driver entry execution. Reverts with `ErrorLogged("CISExecutionDriver address cannot be zero")` if `_cisExecutionDriver` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `cisExecutionDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_cisExecutionDriver`.

### crossEntryHopToken(address[] memory listings, uint256 impactPercent, address[] memory tokenPath, uint8 settleType, uint256 maxIterations, PositionParams memory posParams, address maker)
- **Parameters**:
  - `listings` (address[]): Up to four listing addresses for the hop.
  - `impactPercent` (uint256): Price impact percentage.
  - `tokenPath` (address[]): Start and end tokens for the swap.
  - `settleType` (uint8): 0 (market), 1 (liquid).
  - `maxIterations` (uint256): Maximum iterations for hop processing.
  - `posParams` (PositionParams): Struct with `listingAddress`, `minEntryPrice`, `maxEntryPrice`, `initialMargin`, `excessMargin`, `leverage`, `stopLossPrice`, `takeProfitPrice`, `positionType`.
  - `maker` (address): Hop initiator, defaults to `msg.sender` if `address(0)`.
- **Returns**: None.
- **Behavior**: Initiates a cross-driver hop with ERC20 tokens. Transfers tokens via `IERC20.transferFrom`, approves for `MultiInitializer`, initiates swap via `hopToken`, calls `executeStalls`, and attempts position creation via `_attemptContinuation`. Emits `EntryHopStarted`. On failure, emits `EntryHopCancelled` with reason.
- **Internal Calls**:
  - `_validateAndSetupHop`: Validates inputs and token compatibility.
  - `_transferAndApproveTokens`: Transfers and approves ERC20 tokens.
  - `_initHopContext`: Initializes temporary hop data.
  - `_executeMultihop`: Stores hop data and increments `hopCount`.
  - `_attemptContinuation`: Calls `continueHop`, `executePositions`, and `executeEntries`.
- **External Calls**:
  - `IERC20.transferFrom`: Transfers tokens from `msg.sender`.
  - `IERC20.approve`: Approves tokens for `MultiInitializer`.
  - `MultiInitializer.hopToken(listings, impactPercent, tokenPath, settleType, maxIterations)`: Initiates swap.
  - `IMultiController.executeStalls`: Processes stalled hops.
  - `CCSEntryDriver.executePositions`: Creates position.
  - `ICCSExecutionDriver.executeEntries`: Finalizes entry.
- **Events**: `EntryHopStarted`, `EntryHopCancelled`.
- **Gas Controls**: Bounded by `maxIterations`, `nonReentrant`, helper functions.

### isolatedEntryHopToken(address[] memory listings, uint256 impactPercent, address[] memory tokenPath, uint8 settleType, uint256 maxIterations, PositionParams memory posParams, address maker)
- **Parameters**: Same as `crossEntryHopToken`.
- **Returns**: None.
- **Behavior**: Initiates an isolated-driver hop with ERC20 tokens. Similar to `crossEntryHopToken`, but uses `CISEntryDriver` and `ICISExecutionDriver` for position creation. Emits `EntryHopStarted` or `EntryHopCancelled`.
- **Internal Calls**: Same as `crossEntryHopToken`.
- **External Calls**: Replaces `CCSEntryDriver`/`ICCSExecutionDriver` with `CISEntryDriver`/`ICISExecutionDriver`.
- **Events**: `EntryHopStarted`, `EntryHopCancelled`.
- **Gas Controls**: Same as `crossEntryHopToken`.

### crossEntryHopNative(address[] memory listings, uint256 impactPercent, address[] memory tokenPath, uint8 settleType, uint256 maxIterations, PositionParams memory posParams, address maker)
- **Parameters**: Same as `crossEntryHopToken`, but accepts native tokens via `msg.value`.
- **Returns**: None.
- **Behavior**: Initiates a cross-driver hop with native tokens. Uses `msg.value` for transfer, calls `MultiInitializer.hopNative`, and follows the same flow as `crossEntryHopToken`. Emits `EntryHopStarted` or `EntryHopCancelled`.
- **Internal Calls**: 
  - Same as `crossEntryHopToken`, but uses `_transferNative` instead of `_transferAndApproveTokens`.
- **External Calls**: Replaces `hopToken` with `MultiInitializer.hopNative(...)`.
- **Events**: `EntryHopStarted`, `EntryHopCancelled`.
- **Gas Controls**: Same as `crossEntryHopToken`.

### isolatedEntryHopNative(address[] memory listings, uint256 impactPercent, address[] memory tokenPath, uint8 settleType, uint256 maxIterations, PositionParams memory posParams, address maker)
- **Parameters**: Same as `crossEntryHopNative`.
- **Returns**: None.
- **Behavior**: Initiates an isolated-driver hop with native tokens. Similar to `crossEntryHopNative`, but uses `CISEntryDriver` and `ICISExecutionDriver`. Emits `EntryHopStarted` or `EntryHopCancelled`.
- **Internal Calls**: Same as `crossEntryHopNative`.
- **External Calls**: Same as `crossEntryHopNative`, with CIS drivers.
- **Events**: `EntryHopStarted`, `EntryHopCancelled`.
- **Gas Controls**: Same as `crossEntryHopToken`.

### continueEntryHop(uint256 entryHopId, bool isCrossDriver)
- **Parameters**:
  - `entryHopId` (uint256): Hop to continue.
  - `isCrossDriver` (bool): True for `CCSEntryDriver`, false for `CISEntryDriver`.
- **Returns**: None.
- **Behavior**: Continues a single pending hop (`status = 1`, `maker = msg.sender`, matching `isCrossDriver`). Calls `IMultiController.continueHop`, updates `status = 2` on success, triggers `executePositions` and `executeEntries`. On failure, leaves `status = 1`, requiring `cancelEntryHop`. Uses `nonReentrant`.
- **Internal Calls**: `_attemptContinuation`.
- **External Calls**:
  - `IMultiController.continueHop(entryHopId, maxIterations)`: Progresses hop.
  - `CCSEntryDriver`/`CISEntryDriver.executePositions`: Creates position.
  - `ICCSExecutionDriver`/`ICISExecutionDriver.executeEntries`: Finalizes entry.
- **Events**: `EntryHopStarted`, `EntryHopCancelled`.
- **Gas Controls**: Bounded by `maxIterations`, `nonReentrant`.

### executeEntryStalls(uint256 maxIterations, bool isCrossDriver)
- **Parameters**:
  - `maxIterations` (uint256): Maximum hops to process.
  - `isCrossDriver` (bool): True for `CCSEntryDriver`, false for `CISEntryDriver`.
- **Returns**: None.
- **Behavior**: Globally continues stalled hops (`entryHopsMargin.status = 1`, matching `isCrossDriver`) using `IMultiStorage.totalHops`, up to `maxIterations`, without maker restriction. Calls `_executeEntryStalls` to process hops, invoking `IMultiController.continueHop`, `executePositions`, and `executeEntries`. On failure, leaves `status = 1`, requiring manual cancellation via `cancelEntryHop`.
- **Internal Calls**: `_executeEntryStalls`.
- **External Calls**:
  - `IMultiStorage.totalHops`: Retrieves total hops.
  - `IMultiController.continueHop`: Progresses hop.
  - `CCSEntryDriver`/`CISEntryDriver.executePositions`: Creates position.
  - `ICCSExecutionDriver`/`ICISExecutionDriver.executeEntries`: Finalizes entry.
- **Events**: `EntryHopStarted`, `EntryHopCancelled`.
- **Gas Controls**: Bounded by `maxIterations`, `nonReentrant`.

### cancelEntryHop(uint256 entryHopId, bool isCrossDriver)
- **Parameters**:
  - `entryHopId` (uint256): Hop to cancel.
  - `isCrossDriver` (bool): True for `CCSEntryDriver`, false for `CISEntryDriver`.
- **Returns**: None.
- **Behavior**: Cancels a pending hop (`status = 1`, `maker = msg.sender`, matching `isCrossDriver`). Calls `IMultiController.cancelHop`, which uses `MultiStorage.cancelHop` to process refunds. Refunds are sent to `maker` via `_refundMaker`, updates `status = 3`, emits `EntryHopCancelled`. Uses `nonReentrant`.
- **Internal Calls**: `_refundMaker`.
- **External Calls**:
  - `IMultiController.cancelHop`: Processes cancellation.
  - `IERC20.transfer` or `payable(maker).transfer`: Refunds tokens.
- **Events**: `EntryHopCancelled`.
- **Gas Controls**: Minimal, two external calls, `nonReentrant`.

### getEntryHopDetails(uint256 entryHopId)
- **Parameters**:
  - `entryHopId` (uint256): Hop ID to query.
- **Returns**:
  - `core` (EntryHopCore): `maker`, `hopId`, `listingAddress`, `positionType`.
  - `margin` (EntryHopMargin): `initialMargin`, `excessMargin`, `leverage`, `status`.
  - `params` (EntryHopParams): `stopLossPrice`, `takeProfitPrice`, `endToken`, `isCrossDriver`, `minEntryPrice`, `maxEntryPrice`.
- **Behavior**: Retrieves hop details from `entryHopsCore`, `entryHopsMargin`, and `entryHopsParams`. Uses helper functions to reduce stack usage.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.

### getUserEntryHops(address user)
- **Parameters**:
  - `user` (address): User address to query.
- **Returns**:
  - `uint256[]`: Array of hop IDs for the user.
- **Behavior**: Returns `userHops[user]`, an array of hop IDs associated with the user.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.

### multiInitializerView()
- **Parameters**: None.
- **Returns**:
  - `address`: `multiInitializer` address.
- **Behavior**: Returns `multiInitializer` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.

### multiControllerView()
- **Parameters**: None.
- **Returns**:
  - `address`: `multiController` address.
- **Behavior**: Returns `multiController` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.

### multiStorageView()
- **Parameters**: None.
- **Returns**:
  - `address`: `multiStorage` address.
- **Behavior**: Returns `multiStorage` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.

### ccsEntryDriverView()
- **Parameters**: None.
- **Returns**:
  - `address`: `ccsEntryDriver` address.
- **Behavior**: Returns `ccsEntryDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.

### cisEntryDriverView()
- **Parameters**: None.
- **Returns**:
  - `address`: `cisEntryDriver` address.
- **Behavior**: Returns `cisEntryDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.

### ccsExecutionDriverView()
- **Parameters**: None.
- **Returns**:
  - `address`: `ccsExecutionDriver` address.
- **Behavior**: Returns `ccsExecutionDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.

### cisExecutionDriverView()
- **Parameters**: None.
- **Returns**:
  - `address`: `cisExecutionDriver` address.
- **Behavior**: Returns `cisExecutionDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.

## Additional Details
- **Decimal Handling**: Normalizes amounts to 1e18 precision using `IERC20.decimals` for ERC20 tokens; native tokens use raw values.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant` modifier.
- **Gas Optimization**: Uses `maxIterations` for loop control, split structs for stack management, avoids inline assembly, and optimizes with helper functions.
- **Token Validation**: Ensures `endToken` matches position type via `ISSListingTemplate`.
- **Hop Lifecycle**: Managed by `entryHopsMargin.status` (1=pending, 2=completed, 3=cancelled) and `MultiStorage.hopID.hopStatus` (1=stalled, 2=completed).
- **Safety**: Employs explicit casting, `try-catch` for external calls, avoids reserved keywords, and restricts cancellations to `maker` for secure operation.