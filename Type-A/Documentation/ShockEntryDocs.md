
# ShockEntry Contract Documentation

## Overview
The `ShockEntry` contract, implemented in Solidity (^0.8.2), facilitates multi-hop token swaps via `MultiInitializer`, followed by position creation using `CCSEntryDriver` or `CISEntryDriver`, finalized by `ICCSExecutionDriver` or `ICISExecutionDriver`. It supports up to four listings per hop, handles ERC20 and native tokens, normalizes amounts/prices to 1e18 precision, and ensures secure position creation with leverage, stop-loss, and take-profit settings. It uses `ReentrancyGuard` for security and `Ownable` for administrative control, avoiding `SafeERC20`, inline assembly, and reserved keywords. Public state variables are accessed directly, with mappings tracking user hops and entry details.

- **SPDX License**: BSL 1.1 - Peng Protocol 2025
- **Version**: 0.0.78 (updated 2025-08-13)
- **Change Log**:
  - 2025-08-13: Clarified `executeEntryStalls`, `_continueEntryHops`, and `continueEntryHop` documentation to state that failed `IMultiController.continueHop` calls leave `status = 1`, requiring manual cancellation via `cancelEntryHop`.
  - 2025-08-13: Added `executeEntryStalls` function to globally continue stalled hops without maker restriction.
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
- **Continuation**: `continueEntryHop` and `continueCrossEntryHops`/`continueIsolatedEntryHops` process stalled hops (`entryHopsMargin.status = 1`, `maker = msg.sender`), calling `IMultiController.continueHop` and triggering position creation. `executeEntryStalls` processes stalled hops globally without maker restriction, using `IMultiStorage.totalHops`.
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
- `ccsEntryDriver` (address): Address of `CCSEntryDriver`, set via `setCCSEntryDriver`.
- `cisEntryDriver` (address): Address of `CISEntryDriver`, set via `setCISEntryDriver`.
- `ccsExecutionDriver` (address): Address of `ICCSExecutionDriver`, set via `setCCSExecutionDriver`.
- `cisExecutionDriver` (address): Address of `ICISExecutionDriver`, set via `setCISExecutionDriver`.
- `multiInitializer` (address): Address of `MultiInitializer`, set via `setMultiInitializer`.
- `multiController` (address): Address of `MultiController`, set via `setMultiController`.
- `multiStorage` (address): Address of `MultiStorage`, set via `setMultiStorage`.
- `hopCount` (uint256): Tracks total hops, incremented per hop.
- `userHops` (mapping(address => uint256[])): Maps user addresses to their hop IDs.
- `entryHopsCore` (mapping(uint256 => EntryHopCore)): Stores core hop data (maker, hopId, listingAddress, positionType).
- `entryHopsMargin` (mapping(uint256 => EntryHopMargin)): Stores margin data (initialMargin, excessMargin, leverage, status).
- `entryHopsParams` (mapping(uint256 => EntryHopParams)): Stores position parameters (stopLossPrice, takeProfitPrice, endToken, isCrossDriver, minEntryPrice, maxEntryPrice).
- `hopContexts` (mapping(uint256 => HopContext), private): Stores temporary hop data (maker, hopId, startToken, totalAmount, isCrossDriver).

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
  - `minEntryPrice`, `maxEntryPrice` (uint256): Entry price bounds (1e18 precision).
- **HopParams**:
  - `listings` (address[]): Up to four listing addresses for the hop.
  - `impactPercent` (uint256): Price impact percentage.
  - `startToken`, `endToken` (address): Swap token pair.
  - `settleType` (uint8): 0 (market), 1 (liquid).
  - `maxIterations` (uint256): Max iterations for hop processing.
- **PositionParams**:
  - `listingAddress` (address): Position listing address.
  - `minEntryPrice`, `maxEntryPrice` (uint256): Entry price bounds (1e18 precision).
  - `initialMargin`, `excessMargin` (uint256): Margin amounts (1e18 precision).
  - `leverage` (uint8): Leverage multiplier.
  - `stopLossPrice`, `takeProfitPrice` (uint256): Position bounds (1e18 precision).
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

## Functions

### executeEntryStalls(uint256 maxIterations, bool isCrossDriver)
- **Parameters**:
  - `maxIterations` (uint256): Maximum hops to process.
  - `isCrossDriver` (bool): True for `CCSEntryDriver`, false for `CISEntryDriver`.
- **Behavior**: Globally continues stalled hops (`entryHopsMargin.status = 1`, matching `isCrossDriver`) using `IMultiStorage.totalHops`, up to `maxIterations`, without maker restriction. Calls `_executeEntryStalls` to process hops, invoking `IMultiController.continueHop`, `executePositions`, and `executeEntries`. If `continueHop` fails (e.g., due to liquidity issues), the hop remains pending (`status = 1`), requiring manual cancellation via `cancelEntryHop`.
- **Internal Call Flow**:
  - Calls `_executeEntryStalls(maxIterations, isCrossDriver)`:
    - Validates `multiStorage` is set.
    - Retrieves `totalHopsList` from `IMultiStorage.totalHops`.
    - Iterates up to `maxIterations`, checks `entryHopsMargin.status == 1` and `entryHopsParams.isCrossDriver`.
    - Calls `IMultiController.continueHop(entryHopId, maxIterations)` to progress the hop.
    - On success, sets `entryHopsMargin.status = 2`, calls `ICCSEntryDriver`/`CISEntryDriver.executePositions` and `ICCSExecutionDriver`/`ICISExecutionDriver.executeEntries` based on `isCrossDriver`.
    - On failure, leaves `status = 1`, requiring user-initiated cancellation.
- **Balance Checks**: None directly; handled by `IMultiController.continueHop`.
- **Mappings/Structs Used**:
  - **Mappings**: `entryHopsCore`, `entryHopsMargin`, `entryHopsParams`.
  - **Structs**: `EntryHopCore`, `EntryHopMargin`, `EntryHopParams`.
- **Restrictions**: `nonReentrant`, reverts if `multiStorage` or drivers are not set.
- **Gas Usage Controls**: Bounded by `maxIterations`, minimal external calls (three per hop).

### setMultiStorage(address _multiStorage)
- **Parameters**:
  - `_multiStorage` (address): Address of `MultiStorage`.
- **Behavior**: Sets `multiStorage`, validates non-zero address, restricted to owner.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**: None.
- **Restrictions**: `onlyOwner`, non-zero address.
- **Gas Usage Controls**: Minimal, single state update.

### crossEntryHopToken(address[] memory listings, uint256 impactPercent, address[] memory tokens, uint8 settleType, uint256 maxIterations, PositionParams memory posParams, address maker)
- **Parameters**:
  - `listings` (address[]): Up to four listing addresses for the hop.
  - `impactPercent` (uint256): Price impact percentage.
  - `tokens` (address[]): Array containing `startToken` and `endToken`.
  - `settleType` (uint8): 0 for market, 1 for liquid settlement.
  - `maxIterations` (uint256): Maximum iterations for hop processing.
  - `posParams` (PositionParams): Parameters for position creation (listingAddress, minEntryPrice, maxEntryPrice, initialMargin, excessMargin, leverage, stopLossPrice, takeProfitPrice, positionType).
  - `maker` (address): Address initiating the hop, defaults to `msg.sender` if `address(0)`.
- **Behavior**: Initiates an ERC20 hop for `CCSEntryDriver`, validates inputs, constructs `HopParams`, and calls `_executeEntryHopToken` to process the hop and attempt position creation.
- **Internal Call Flow**:
  - Validates `tokens.length == 2`, sets `hopMaker` (`maker` or `msg.sender`).
  - Constructs `HopParams` from inputs.
  - Calls `_executeEntryHopToken(hopMaker, hopParams, posParams, true, maxIterations)`:
    - `_validateAndSetupHop`: Ensures non-zero addresses (`hopMaker`, `multiInitializer`, `multiController`, `multiStorage`, `ccsEntryDriver`, `ccsExecutionDriver`) and validates `endToken` matches `positionType` via `_validatePositionToken`.
    - `_transferAndApproveTokens`: Transfers `totalAmount` (initialMargin + excessMargin) from `hopMaker` to `ShockEntry` via `IERC20.transferFrom` and approves `MultiInitializer` via `IERC20.approve`.
    - `_initHopContext`: Stores `HopContext` in `hopContexts` with `hopMaker`, `hopCount`, `startToken`, `totalAmount`, `isCrossDriver = true`.
    - `_executeMultihop`: Increments `hopCount`, calls `_storePositionCore`, `_storePositionMargin`, `_storePositionParams` to store hop data, returns `entryHopId`.
    - Updates `userHops[hopMaker]` with `entryHopId`.
    - Calls `IMultiInitializer.hopToken` with up to four `listings`, `impactPercent`, `startToken`, `endToken`, `settleType`, `maxIterations`.
    - Calls `IMultiController.executeStalls(maxIterations)` to process stalled hops, wrapped in `try-catch` to emit `EntryHopCancelled` on failure.
    - Calls `_attemptContinuation(entryHopId, true, maxIterations)`:
      - Calls `IMultiController.continueHop(entryHopId, maxIterations)` to progress the hop.
      - On success, sets `entryHopsMargin.status = 2`, calls `ICCSEntryDriver.executePositions` and `ICCSExecutionDriver.executeEntries`.
      - On failure (e.g., `executeStalls` completed the hop), sets `status = 3` and emits `EntryHopCancelled`. Position creation proceeds if `status = 2`.
    - Emits `EntryHopStarted(hopMaker, entryHopId, entryHopId, true)`.
- **Balance Checks**: Ensures `totalAmount` is transferred via `IERC20.transferFrom`.
- **Mappings/Structs Used**:
  - **Mappings**: `userHops`, `hopContexts`, `entryHopsCore`, `entryHopsMargin`, `entryHopsParams`.
  - **Structs**: `HopParams`, `PositionParams`, `HopContext`, `EntryHopCore`, `EntryHopMargin`, `EntryHopParams`.
- **Restrictions**: `nonReentrant`, `tokens.length == 2`, non-zero addresses, valid token match.
- **Gas Usage Controls**: Bounded by `maxIterations`, split structs, minimal external calls.

### isolatedEntryHopToken(address[] memory listings, uint256 impactPercent, address[] memory tokens, uint8 settleType, uint256 maxIterations, PositionParams memory posParams, address maker)
- **Parameters**: Same as `crossEntryHopToken`.
- **Behavior**: Initiates an ERC20 hop for `CISEntryDriver`, identical to `crossEntryHopToken` but sets `isCrossDriver = false`, using `CISEntryDriver.executePositions` and `ICISExecutionDriver.executeEntries`.
- **Internal Call Flow**: Same as `crossEntryHopToken`, with `isCrossDriver = false`.
- **Balance Checks**: Same as `crossEntryHopToken`.
- **Mappings/Structs Used**: Same as `crossEntryHopToken`.
- **Restrictions**: Same as `crossEntryHopToken`, ensures `cisEntryDriver` and `cisExecutionDriver` are set.
- **Gas Usage Controls**: Same as `crossEntryHopToken`.

### crossEntryHopNative(address[] memory listings, uint256 impactPercent, address[] memory tokens, uint8 settleType, uint256 maxIterations, PositionParams memory posParams, address maker)
- **Parameters**: Same as `crossEntryHopToken`, payable for native tokens.
- **Behavior**: Initiates a native token hop for `CCSEntryDriver`, validates inputs, constructs `HopParams`, and calls `_executeEntryHopNative`.
- **Internal Call Flow**:
  - Validates `tokens.length == 2`, sets `hopMaker`.
  - Constructs `HopParams` from inputs.
  - Calls `_executeEntryHopNative(hopMaker, hopParams, posParams, true, maxIterations)`:
    - `_validateAndSetupHop`: Same as above, ensuring `ccsEntryDriver`, `ccsExecutionDriver`, and `multiStorage` are set.
    - `_transferNative`: Validates `msg.value == totalAmount` and forwards to `MultiInitializer` via low-level call.
    - `_initHopContext`: Stores `HopContext` with `startToken = address(0)`.
    - `_executeMultihop`: Same as above, storing hop data.
    - Updates `userHops[hopMaker]` with `entryHopId`.
    - Calls `IMultiInitializer.hopNative` with `listings`, `impactPercent`, `startToken`, `endToken`, `settleType`, `maxIterations`.
    - Calls `IMultiController.executeStalls(maxIterations)`, wrapped in `try-catch`.
    - Calls `_attemptContinuation(entryHopId, true, maxIterations)`, same as above.
    - Emits `EntryHopStarted(hopMaker, entryHopId, entryHopId, true)`.
- **Balance Checks**: Validates `msg.value == totalAmount`.
- **Mappings/Structs Used**: Same as `crossEntryHopToken`.
- **Restrictions**: `nonReentrant`, `tokens.length == 2`, non-zero addresses, valid token match, correct `msg.value`.
- **Gas Usage Controls**: Same as `crossEntryHopToken`.

### isolatedEntryHopNative(address[] memory listings, uint256 impactPercent, address[] memory tokens, uint8 settleType, uint256 maxIterations, PositionParams memory posParams, address maker)
- **Parameters**: Same as `crossEntryHopNative`.
- **Behavior**: Initiates a native token hop for `CISEntryDriver`, identical to `crossEntryHopNative` but sets `isCrossDriver = false`, using `CISEntryDriver.executePositions` and `ICISExecutionDriver.executeEntries`.
- **Internal Call Flow**: Same as `crossEntryHopNative`, with `isCrossDriver = false`.
- **Balance Checks**: Same as `crossEntryHopNative`.
- **Mappings/Structs Used**: Same as `crossEntryHopToken`.
- **Restrictions**: Same as `crossEntryHopNative`, ensures `cisEntryDriver` and `cisExecutionDriver` are set.
- **Gas Usage Controls**: Same as `crossEntryHopToken`.

### continueEntryHop(uint256 entryHopId, bool isCrossDriver)
- **Parameters**:
  - `entryHopId` (uint256): Specific hop to continue.
  - `isCrossDriver` (bool): True for `CCSEntryDriver`, false for `CISEntryDriver`.
- **Behavior**: Allows the `maker` to continue a specific stalled hop, restricted to `entryHopsCore.maker`, calling `_continueEntryHops` with `maxIterations = 1`. If `IMultiController.continueHop` fails, the hop remains pending (`status = 1`), requiring manual cancellation via `cancelEntryHop`.
- **Internal Call Flow**:
  - Checks `entryHopsCore[entryHopId].maker == msg.sender`.
  - Calls `_continueEntryHops(1, isCrossDriver)` to process the hop, validating `status == 1`, `isCrossDriver`, and `maker` match.
  - Calls `IMultiController.continueHop`, `executePositions`, and `executeEntries` as above.
- **Balance Checks**: None directly; handled by `IMultiController.continueHop`.
- **Mappings/Structs Used**:
  - **Mappings**: `entryHopsCore`, `entryHopsMargin`, `entryHopsParams`.
  - **Structs**: `EntryHopCore`, `EntryHopMargin`, `EntryHopParams`.
- **Restrictions**: `nonReentrant`, restricted to `maker`, valid drivers.
- **Gas Usage Controls**: Fixed `maxIterations = 1`, minimal external calls.

### cancelEntryHop(uint256 entryHopId, bool isCrossDriver)
- **Parameters**:
  - `entryHopId` (uint256): Specific hop to cancel.
  - `isCrossDriver` (bool): True for `CCSEntryDriver`, false for `CISEntryDriver`.
- **Behavior**: Allows the `maker` to cancel a specific hop, restricted to `entryHopsCore.maker`, calling `_cancelEntryHop` to refund via `IMultiController.cancelHop`, which uses `MultiStorage.cancelHop`, and `_refundMaker`.
- **Internal Call Flow**:
  - Calls `_cancelEntryHop(entryHopId, isCrossDriver)`:
    - Validates `entryHopsMargin.status == 1`, `entryHopsParams.isCrossDriver`, and `entryHopsCore.maker == msg.sender`.
    - Calls `IMultiController.cancelHop`, which triggers `MultiStorage.cancelHop` to process refunds.
    - Refunds via `_refundMaker` using `context.startToken` and `refundedAmount`.
    - Sets `entryHopsMargin.status = 3`, emits `EntryHopCancelled`.
- **Balance Checks**: Ensures `refundedAmount` transfer via `_refundMaker`.
- **Mappings/Structs Used**:
  - **Mappings**: `entryHopsCore`, `entryHopsMargin`, `entryHopsParams`, `hopContexts`.
  - **Structs**: `EntryHopCore`, `EntryHopMargin`, `EntryHopParams`, `HopContext`.
- **Restrictions**: `nonReentrant`, restricted to `maker`, valid `status`, driver match.
- **Gas Usage Controls**: Minimal, two external calls.

### setMultiInitializer(address _multiInitializer)
- **Parameters**:
  - `_multiInitializer` (address): Address of `MultiInitializer`.
- **Behavior**: Sets `multiInitializer`, validates non-zero address, restricted to owner.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**: None.
- **Restrictions**: `onlyOwner`, non-zero address.
- **Gas Usage Controls**: Minimal, single state update.

### setMultiController(address _multiController)
- **Parameters**:
  - `_multiController` (address): Address of `MultiController`.
- **Behavior**: Sets `multiController`, validates non-zero address, restricted to owner.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**: None.
- **Restrictions**: `onlyOwner`, non-zero address.
- **Gas Usage Controls**: Minimal, single state update.

### setCCSEntryDriver(address _ccsEntryDriver)
- **Parameters**:
  - `_ccsEntryDriver` (address): Address of `CCSEntryDriver`.
- **Behavior**: Sets `ccsEntryDriver`, validates non-zero address, restricted to owner.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**: None.
- **Restrictions**: `onlyOwner`, non-zero address.
- **Gas Usage Controls**: Minimal, single state update.

### setCISEntryDriver(address _cisEntryDriver)
- **Parameters**:
  - `_cisEntryDriver` (address): Address of `CISEntryDriver`.
- **Behavior**: Sets `cisEntryDriver`, validates non-zero address, restricted to owner.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**: None.
- **Restrictions**: `onlyOwner`, non-zero address.
- **Gas Usage Controls**: Minimal, single state update.

### setCCSExecutionDriver(address _ccsExecutionDriver)
- **Parameters**:
  - `_ccsExecutionDriver` (address): Address of `ICCSExecutionDriver`.
- **Behavior**: Sets `ccsExecutionDriver`, validates non-zero address, restricted to owner.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**: None.
- **Restrictions**: `onlyOwner`, non-zero address.
- **Gas Usage Controls**: Minimal, single state update.

### setCISExecutionDriver(address _cisExecutionDriver)
- **Parameters**:
  - `_cisExecutionDriver` (address): Address of `ICISExecutionDriver`.
- **Behavior**: Sets `cisExecutionDriver`, validates non-zero address, restricted to owner.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**: None.
- **Restrictions**: `onlyOwner`, non-zero address.
- **Gas Usage Controls**: Minimal, single state update.

### getEntryHopDetails(uint256 entryHopId)
- **Parameters**:
  - `entryHopId` (uint256): Hop ID to query.
- **Behavior**: Returns `EntryHopCore`, `EntryHopMargin`, `EntryHopParams` for the specified hop.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `entryHopsCore`, `entryHopsMargin`, `entryHopsParams`.
  - **Structs**: `EntryHopCore`, `EntryHopMargin`, `EntryHopParams`.
- **Restrictions**: None, view function.
- **Gas Usage Controls**: Minimal, direct mapping access.

### getUserEntryHops(address user)
- **Parameters**:
  - `user` (address): User address to query.
- **Behavior**: Returns array of hop IDs for the user from `userHops`.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `userHops`.
- **Restrictions**: None, view function.
- **Gas Usage Controls**: Minimal, direct mapping access.

### multiInitializerView()
- **Behavior**: Returns `multiInitializer` address.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**: None.
- **Restrictions**: None, view function.
- **Gas Usage Controls**: Minimal, direct state access.

### multiControllerView()
- **Behavior**: Returns `multiController` address.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**: None.
- **Restrictions**: None, view function.
- **Gas Usage Controls**: Minimal, direct state access.

### multiStorageView()
- **Behavior**: Returns `multiStorage` address.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**: None.
- **Restrictions**: None, view function.
- **Gas Usage Controls**: Minimal, direct state access.

### ccsEntryDriverView()
- **Behavior**: Returns `ccsEntryDriver` address.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**: None.
- **Restrictions**: None, view function.
- **Gas Usage Controls**: Minimal, direct state access.

### cisEntryDriverView()
- **Behavior**: Returns `cisEntryDriver` address.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**: None.
- **Restrictions**: None, view function.
- **Gas Usage Controls**: Minimal, direct state access.

### ccsExecutionDriverView()
- **Behavior**: Returns `ccsExecutionDriver` address.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**: None.
- **Restrictions**: None, view function.
- **Gas Usage Controls**: Minimal, direct state access.

### cisExecutionDriverView()
- **Behavior**: Returns `cisExecutionDriver` address.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**: None.
- **Restrictions**: None, view function.
- **Gas Usage Controls**: Minimal, direct state access.

### _validatePositionToken(address listingAddress, address endToken, uint8 positionType)
- **Parameters**:
  - `listingAddress` (address): Position listing address.
  - `endToken` (address): Final token after swap.
  - `positionType` (uint8): 0 for long, 1 for short.
- **Behavior**: Ensures `endToken` matches `positionType` via `ISSListingTemplate.tokenA`/`tokenB`.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**: None.
- **Restrictions**: Private, reverts on invalid `listingAddress` or token mismatch.
- **Gas Usage Controls**: Minimal, single external call.

### _transferAndApproveTokens(address hopMaker, address startToken, uint256 totalAmount)
- **Parameters**:
  - `hopMaker` (address): Address initiating the hop.
  - `startToken` (address): Token to transfer.
  - `totalAmount` (uint256): Amount to transfer (1e18 precision).
- **Behavior**: Transfers `totalAmount` from `hopMaker` to `ShockEntry` via `IERC20.transferFrom` and approves `MultiInitializer` via `IERC20.approve`.
- **Internal Call Flow**: None.
- **Balance Checks**: Ensures successful transfer via `IERC20.transferFrom`.
- **Mappings/Structs Used**: None.
- **Restrictions**: Private, reverts on transfer or approval failure.
- **Gas Usage Controls**: Minimal, two external calls.

### _transferNative(address hopMaker, uint256 totalAmount)
- **Parameters**:
  - `hopMaker` (address): Address initiating the hop.
  - `totalAmount` (uint256): Native token amount (1e18 precision).
- **Behavior**: Validates `msg.value == totalAmount` and forwards to `MultiInitializer` via low-level call.
- **Internal Call Flow**: None.
- **Balance Checks**: Validates `msg.value`.
- **Mappings/Structs Used**: None.
- **Restrictions**: Private, reverts on incorrect `msg.value` or failed transfer.
- **Gas Usage Controls**: Minimal, single low-level call.

### _refundMaker(address maker, address token, uint256 amount)
- **Parameters**:
  - `maker` (address): Address to refund.
  - `token` (address): Token to refund (`address(0)` for native).
  - `amount` (uint256): Amount to refund (1e18 precision).
- **Behavior**: Refunds `amount` to `maker` via `IERC20.transfer` (ERC20) or low-level call (native).
- **Internal Call Flow**: None.
- **Balance Checks**: Ensures successful transfer.
- **Mappings/Structs Used**: None.
- **Restrictions**: Private, reverts on failed refund.
- **Gas Usage Controls**: Minimal, single external call.

### _initHopContext(address hopMaker, uint256 hopId, address startToken, uint256 totalAmount, bool isCrossDriver)
- **Parameters**:
  - `hopMaker` (address): Address initiating the hop.
  - `hopId` (uint256): Hop identifier.
  - `startToken` (address): Initial token (`address(0)` for native).
  - `totalAmount` (uint256): Total margin (1e18 precision).
  - `isCrossDriver` (bool): Driver selection flag.
- **Behavior**: Stores `HopContext` in `hopContexts`.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `hopContexts`.
  - **Structs**: `HopContext`.
- **Restrictions**: Private.
- **Gas Usage Controls**: Minimal, single mapping update.

### _storePositionCore(uint256 hopId, address maker, address listingAddress, uint8 positionType)
- **Parameters**:
  - `hopId` (uint256): Hop identifier.
  - `maker` (address): Hop initiator.
  - `listingAddress` (address): Position listing address.
  - `positionType` (uint8): 0 for long, 1 for short.
- **Behavior**: Stores `EntryHopCore` in `entryHopsCore`.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `entryHopsCore`.
  - **Structs**: `EntryHopCore`.
- **Restrictions**: Private.
- **Gas Usage Controls**: Minimal, single mapping update.

### _storePositionMargin(uint256 hopId, uint256 initialMargin, uint256 excessMargin, uint8 leverage)
- **Parameters**:
  - `hopId` (uint256): Hop identifier.
  - `initialMargin` (uint256): Initial margin (1e18 precision).
  - `excessMargin` (uint256): Excess margin (1e18 precision).
  - `leverage` (uint8): Leverage multiplier.
- **Behavior**: Stores `EntryHopMargin` in `entryHopsMargin` with `status = 1`.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `entryHopsMargin`.
  - **Structs**: `EntryHopMargin`.
- **Restrictions**: Private.
- **Gas Usage Controls**: Minimal, single mapping update.

### _storePositionParams(uint256 hopId, uint256 stopLossPrice, uint256 takeProfitPrice, address endToken, bool isCrossDriver, uint256 minEntryPrice, uint256 maxEntryPrice)
- **Parameters**:
  - `hopId` (uint256): Hop identifier.
  - `stopLossPrice`, `takeProfitPrice` (uint256): Position bounds (1e18 precision).
  - `endToken` (address): Final token after swap.
  - `isCrossDriver` (bool): Driver selection flag.
  - `minEntryPrice`, `maxEntryPrice` (uint256): Entry price bounds (1e18 precision).
- **Behavior**: Stores `EntryHopParams` in `entryHopsParams`.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `entryHopsParams`.
  - **Structs**: `EntryHopParams`.
- **Restrictions**: Private.
- **Gas Usage Controls**: Minimal, single mapping update.

### _executeMultihop(HopContext memory context, HopParams memory hopParams, PositionParams memory posParams)
- **Parameters**:
  - `context` (HopContext): Temporary hop data.
  - `hopParams` (HopParams): Hop configuration.
  - `posParams` (PositionParams): Position parameters.
- **Behavior**: Increments `hopCount`, stores hop data via `_storePositionCore`, `_storePositionMargin`, `_storePositionParams`, returns `entryHopId`.
- **Internal Call Flow**:
  - `_storePositionCore`
  - `_storePositionMargin`
  - `_storePositionParams`
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `entryHopsCore`, `entryHopsMargin`, `entryHopsParams`.
  - **Structs**: `HopContext`, `HopParams`, `PositionParams`, `EntryHopCore`, `EntryHopMargin`, `EntryHopParams`.
- **Restrictions**: Private.
- **Gas Usage Controls**: Minimal, three mapping updates.

### _attemptContinuation(uint256 entryHopId, bool isCrossDriver, uint256 maxIterations)
- **Parameters**:
  - `entryHopId` (uint256): Hop to continue.
  - `isCrossDriver` (bool): Driver selection flag.
  - `maxIterations` (uint256): Maximum iterations.
- **Behavior**: Calls `IMultiController.continueHop`, sets `status = 2` on success, triggers `executePositions` and `executeEntries`. On failure, sets `status = 3`, emits `EntryHopCancelled`.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `entryHopsMargin`, `entryHopsCore`.
  - **Structs**: `EntryHopMargin`, `EntryHopCore`.
- **Restrictions**: Private, reverts on invalid drivers.
- **Gas Usage Controls**: Bounded by `maxIterations`, three external calls.

### _validateAndSetupHop(address hopMaker, HopParams memory hopParams, PositionParams memory posParams, bool isCrossDriver)
- **Parameters**:
  - `hopMaker` (address): Hop initiator.
  - `hopParams` (HopParams): Hop configuration.
  - `posParams` (PositionParams): Position parameters.
  - `isCrossDriver` (bool): Driver selection flag.
- **Behavior**: Validates non-zero addresses (`hopMaker`, `multiInitializer`, `multiController`, `multiStorage`, drivers) and token compatibility via `_validatePositionToken`.
- **Internal Call Flow**:
  - `_validatePositionToken`
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Structs**: `HopParams`, `PositionParams`.
- **Restrictions**: Private, reverts on invalid addresses or token mismatch.
- **Gas Usage Controls**: Minimal, single external call.

### _executeEntryHopToken(address hopMaker, HopParams memory hopParams, PositionParams memory posParams, bool isCrossDriver, uint256 maxIterations)
- **Parameters**:
  - `hopMaker` (address): Hop initiator.
  - `hopParams` (HopParams): Hop configuration.
  - `posParams` (PositionParams): Position parameters.
  - `isCrossDriver` (bool): Driver selection flag.
  - `maxIterations` (uint256): Maximum iterations.
- **Behavior**: Executes ERC20 hop, calls `IMultiInitializer.hopToken`, `IMultiController.executeStalls`, `_attemptContinuation`, and emits `EntryHopStarted`.
- **Internal Call Flow**:
  - `_validateAndSetupHop`
  - `_transferAndApproveTokens`
  - `_initHopContext`
  - `_executeMultihop`
  - `_attemptContinuation`
- **Balance Checks**: Ensures `totalAmount` transfer via `_transferAndApproveTokens`.
- **Mappings/Structs Used**:
  - **Mappings**: `hopContexts`, `userHops`, `entryHopsCore`, `entryHopsMargin`, `entryHopsParams`.
  - **Structs**: `HopParams`, `PositionParams`, `HopContext`, `EntryHopCore`, `EntryHopMargin`, `EntryHopParams`.
- **Restrictions**: Private, reverts on validation failures.
- **Gas Usage Controls**: Bounded by `maxIterations`, minimal external calls.

### _executeEntryHopNative(address hopMaker, HopParams memory hopParams, PositionParams memory posParams, bool isCrossDriver, uint256 maxIterations)
- **Parameters**: Same as `_executeEntryHopToken`.
- **Behavior**: Executes native token hop, calls `IMultiInitializer.hopNative`, `IMultiController.executeStalls`, `_attemptContinuation`, and emits `EntryHopStarted`.
- **Internal Call Flow**:
  - `_validateAndSetupHop`
  - `_transferNative`
  - `_initHopContext`
  - `_executeMultihop`
  - `_attemptContinuation`
- **Balance Checks**: Ensures `msg.value` transfer via `_transferNative`.
- **Mappings/Structs Used**: Same as `_executeEntryHopToken`.
- **Restrictions**: Private, reverts on validation or transfer failures.
- **Gas Usage Controls**: Same as `_executeEntryHopToken`.

### _continueEntryHops(uint256 maxIterations, bool isCrossDriver)
- **Parameters**:
  - `maxIterations` (uint256): Maximum hops to process.
  - `isCrossDriver` (bool): Driver selection flag.
- **Behavior**: Iterates `userHops[msg.sender]` up to `maxIterations`, processes pending hops (`status = 1`, matching `isCrossDriver`, `maker = msg.sender`), calls `IMultiController.continueHop`, updates `status = 2` on success, triggers `executePositions` and `executeEntries`. On failure, leaves `status = 1`, requiring manual cancellation via `cancelEntryHop`.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `userHops`, `entryHopsCore`, `entryHopsMargin`, `entryHopsParams`.
  - **Structs**: `EntryHopCore`, `EntryHopMargin`, `EntryHopParams`.
- **Restrictions**: Private, reverts on invalid drivers.
- **Gas Usage Controls**: Bounded by `maxIterations`, minimal external calls.

### _executeEntryStalls(uint256 maxIterations, bool isCrossDriver)
- **Parameters**:
  - `maxIterations` (uint256): Maximum hops to process.
  - `isCrossDriver` (bool): Driver selection flag.
- **Behavior**: Iterates `IMultiStorage.totalHops` up to `maxIterations`, processes pending hops (`status = 1`, matching `isCrossDriver`), calls `IMultiController.continueHop`, updates `status = 2` on success, triggers `executePositions` and `executeEntries`. On failure, leaves `status = 1`, requiring manual cancellation via `cancelEntryHop`.
- **Internal Call Flow**: None.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `entryHopsCore`, `entryHopsMargin`, `entryHopsParams`.
  - **Structs**: `EntryHopCore`, `EntryHopMargin`, `EntryHopParams`.
- **Restrictions**: Private, reverts on invalid `multiStorage` or drivers.
- **Gas Usage Controls**: Bounded by `maxIterations`, minimal external calls (three per hop).

### _cancelEntryHop(uint256 entryHopId, bool isCrossDriver)
- **Parameters**:
  - `entryHopId` (uint256): Hop to cancel.
  - `isCrossDriver` (bool): Driver selection flag.
- **Behavior**: Validates `status = 1`, `isCrossDriver`, and `maker = msg.sender`, calls `IMultiController.cancelHop`, which uses `MultiStorage.cancelHop`, refunds via `_refundMaker`, sets `status = 3`, emits `EntryHopCancelled`.
- **Internal Call Flow**:
  - `_refundMaker`
- **Balance Checks**: Ensures `refundedAmount` transfer via `_refundMaker`.
- **Mappings/Structs Used**:
  - **Mappings**: `entryHopsCore`, `entryHopsMargin`, `entryHopsParams`, `hopContexts`.
  - **Structs**: `EntryHopCore`, `EntryHopMargin`, `EntryHopParams`, `HopContext`.
- **Restrictions**: Private, reverts on non-pending hop, driver mismatch, or unauthorized `msg.sender`.
- **Gas Usage Controls**: Minimal, two external calls.

## Additional Details
- **Decimal Handling**: Normalizes amounts to 1e18 precision using `IERC20.decimals` for ERC20 tokens; native tokens use raw values.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: Uses `maxIterations`, split structs, avoids inline assembly, and optimizes stack depth with helper functions.
- **Token Validation**: Ensures `endToken` matches position type via `ISSListingTemplate`.
- **Hop Lifecycle**: Managed by `entryHopsMargin.status` and `MultiStorage.hopID.hopStatus`.
- **Safety**: Explicit casting, `try-catch` for external calls, no reserved keywords, and maker-only restrictions ensure secure operation.