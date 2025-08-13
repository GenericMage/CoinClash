# ShockExit Contract Documentation

## Overview
The `ShockExit` contract, implemented in Solidity (^0.8.2), facilitates position closure via `CCSExitDriver` or `CISExitDriver`, followed by multi-hop token swaps using `MultiInitializer` and `MultiController`. It supports up to four listings for token swaps, handles payout settlement, and ensures secure execution with reentrancy protection via `ReentrancyGuard` and administrative control via `Ownable`. State variables are public, mappings track user hops and exit details, and the contract avoids `SafeERC20`, uses explicit casting, and employs `try-catch` for external calls.

**SPDX License:** BSL-1.1 - Peng Protocol 2025

**Version:** 0.0.74 (updated 2025-08-13)

**Compatible Contracts:**
- `MultiInitializer` v0.0.44
- `MultiController` v0.0.44
- `MultiStorage` v0.0.44
- `CCSExitDriver` v0.0.61
- `CISExitDriver` v0.0.61
- `CCSLiquidationDriver` v0.0.61
- `CISLiquidationDriver` v0.0.61
- `CCListingTemplate` v0.0.10

**Changelog:**
- v0.0.74: Updated to use `listingAddresses` array, added `tokenPath` for start/end tokens, refactored `_executeHop` for efficiency, added `actualAmount` to `ExitHopTokens`.
- v0.0.64: Split `getExitHopDetails` into `_getExitHopCore`, `_getExitHopTokens`, `_getExitHopStatus` to resolve stack-too-deep error.
- v0.0.63: Removed `view` from `_validateInputs` to allow `ErrorLogged` emissions.
- v0.0.62: Refactored `_executeExitHop` with helper functions to reduce stack usage.
- v0.0.59–0.0.61: Added native token support, improved error handling.

## Clarifications
- **Position Closure**: Closes positions via `CCSExitDriver` or `CISExitDriver` (`drift`), verifies payout settlement via `CCListingTemplate`, and initiates multi-hop swaps.
- **Hop Execution**: Supports ERC20 and native token swaps with up to four listings via `listingAddresses`. Uses `tokenPath` for start/end tokens. `maxIterations` limits gas usage.
- **Payout Handling**: Verifies payout completion before multihop initiation, tracks `actualAmount` received.
- **Continuation**: Processes pending hops, updating status to completed (2) or cancelled (3).
- **Error Handling**: Uses `try-catch` for external calls, emitting `ErrorLogged` with decoded reasons.
- **Maker Flexibility**: `maker` defaults to `msg.sender` if `address(0)`.
- **Decimal Handling**: Relies on `CCListingTemplate.decimalsA`/`decimalsB` for token decimals.
- **Hop Status**: Tracks initializing (0), pending (1), completed (2), or cancelled (3) in `exitHopsStatus.status`.
- **Gas Optimization**: Uses `maxIterations`, helper functions, no inline assembly.

## State Variables
- **ccsExitDriver** (address, public): `CCSExitDriver` address for cross-driver position closure.
- **cisExitDriver** (address, public): `CISExitDriver` address for isolated-driver position closure.
- **ccsLiquidationDriver** (address, public): `CCSLiquidationDriver` address for cross-driver payout settlement.
- **cisLiquidationDriver** (address, public): `CISLiquidationDriver` address for isolated-driver payout settlement.
- **multiInitializer** (address, public): `MultiInitializer` address for initiating multi-hop swaps.
- **multiController** (address, public): `MultiController` address for continuing hops.
- **multiStorage** (address, public): `MultiStorage` address for hop data storage.
- **hopCount** (uint256, public): Total number of exit hops created.
- **userHops** (mapping(address => uint256[]), public): Maps user addresses to their hop IDs.
- **exitHopsCore** (mapping(uint256 => ExitHopCore), public): Stores core hop details (maker, multihopId, positionId, listingAddress).
- **exitHopsTokens** (mapping(uint256 => ExitHopTokens), public): Stores token details (startToken, endToken, payoutOrderId, actualAmount).
- **exitHopsStatus** (mapping(uint256 => ExitHopStatus), public): Stores status details (positionType, settleType, status, isCrossDriver).

## Structs
- **ExitHopCore**:
  - `maker` (address): Address initiating the hop, defaults to `msg.sender` if `address(0)`.
  - `multihopId` (uint256): ID of the hop in `MultiInitializer`.
  - `positionId` (uint256): ID of the position being closed.
  - `listingAddress` (address): Address of the listing for position closure.
- **ExitHopTokens**:
  - `startToken` (address): Token received from position closure.
  - `endToken` (address): Expected final token after multi-hop swap.
  - `payoutOrderId` (uint256): Order ID from `CCListingTemplate` for payout tracking.
  - `actualAmount` (uint256): Actual amount received from payout (1e18 precision).
- **ExitHopStatus**:
  - `positionType` (uint8): 0 for long, 1 for short position.
  - `settleType` (uint8): 0 for market settlement, 1 for liquidation.
  - `status` (uint8): 0=initializing, 1=pending, 2=completed, 3=cancelled.
  - `isCrossDriver` (bool): True for `CCSExitDriver`, false for `CISExitDriver`.
- **HopParams**:
  - `listingAddresses` (address[]): Array of up to 4 listing addresses for multi-hop swaps.
  - `tokenPath` (address[]): Array of start/end tokens for the swap.
  - `impactPercent` (uint256): Maximum price impact percentage for swaps.
  - `settleType` (uint8): 0 for market, 1 for liquidation settlement.
  - `maxIterations` (uint256): Maximum iterations for gas control.
- **PositionParams**:
  - `listingAddress` (address): Address of the listing for position closure.
  - `positionId` (uint256): ID of the position being closed.
  - `positionType` (uint8): 0 for long, 1 for short.
- **ExitHopData** (internal):
  - `exitHopId` (uint256): Unique ID of the exit hop.
  - `payoutSettled` (bool): Indicates if payout is settled.
  - `multihopId` (uint256): ID of the multi-hop in `MultiInitializer`.
  - `listingAddress` (address): Listing address for position closure.

## Events
- **ExitHopStarted(address indexed maker, uint256 indexed exitHopId, uint256 multihopId, bool isCrossDriver)**: Emitted when a hop is initiated.
- **ExitHopCompleted(uint256 indexed exitHopId)**: Emitted when a hop is completed.
- **ExitHopCancelled(uint256 indexed exitHopId, string reason)**: Emitted when a hop is cancelled or fails.
- **ErrorLogged(string reason)**: Emitted for errors in external calls or validations.

## External Functions

### setMultiStorage(address _multiStorage)
- **Parameters**:
  - `_multiStorage` (address): Address of `MultiStorage` contract.
- **Returns**: None.
- **Behavior**: Sets `multiStorage` address, used by `_executeExitHop`, `_continueExitHops`, and `_executeGlobalExitHops` for hop data retrieval. Reverts with `ErrorLogged("MultiStorage address cannot be zero")` if `_multiStorage` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `multiStorage` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_multiStorage`.
- **Restrictions**: `onlyOwner`.

### setMultiInitializer(address _multiInitializer)
- **Parameters**:
  - `_multiInitializer` (address): Address of `MultiInitializer` contract.
- **Returns**: None.
- **Behavior**: Sets `multiInitializer` address, used by `_initMultihop` to initiate hops. Reverts with `ErrorLogged("MultiInitializer address cannot be zero")` if `_multiInitializer` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `multiInitializer` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_multiInitializer`.
- **Restrictions**: `onlyOwner`.

### setMultiController(address _multiController)
- **Parameters**:
  - `_multiController` (address): Address of `MultiController` contract.
- **Returns**: None.
- **Behavior**: Sets `multiController` address, used by `_continueExitHops` and `_executeGlobalExitHops` for hop continuation. Reverts with `ErrorLogged("MultiController address cannot be zero")` if `_multiController` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `multiController` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_multiController`.
- **Restrictions**: `onlyOwner`.

### setCCSExitDriver(address _ccsExitDriver)
- **Parameters**:
  - `_ccsExitDriver` (address): Address of `CCSExitDriver` contract.
- **Returns**: None.
- **Behavior**: Sets `ccsExitDriver` address, used by `_callDriver` for position closure in cross-driver hops. Reverts with `ErrorLogged("CCSExitDriver address cannot be zero")` if `_ccsExitDriver` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `ccsExitDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_ccsExitDriver`.
- **Restrictions**: `onlyOwner`.

### setCISExitDriver(address _cisExitDriver)
- **Parameters**:
  - `_cisExitDriver` (address): Address of `CISExitDriver` contract.
- **Returns**: None.
- **Behavior**: Sets `cisExitDriver` address, used by `_callDriver` for position closure in isolated-driver hops. Reverts with `ErrorLogged("CISExitDriver address cannot be zero")` if `_cisExitDriver` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `cisExitDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_cisExitDriver`.
- **Restrictions**: `onlyOwner`.

### setCCSLiquidationDriver(address _ccsLiquidationDriver)
- **Parameters**:
  - `_ccsLiquidationDriver` (address): Address of `CCSLiquidationDriver` contract.
- **Returns**: None.
- **Behavior**: Sets `ccsLiquidationDriver` address, used by `_callLiquidation` for payout settlement in cross-driver hops. Reverts with `ErrorLogged("CCSLiquidationDriver address cannot be zero")` if `_ccsLiquidationDriver` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `ccsLiquidationDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_ccsLiquidationDriver`.
- **Restrictions**: `onlyOwner`.

### setCISLiquidationDriver(address _cisLiquidationDriver)
- **Parameters**:
  - `_cisLiquidationDriver` (address): Address of `CISLiquidationDriver` contract.
- **Returns**: None.
- **Behavior**: Sets `cisLiquidationDriver` address, used by `_callLiquidation` for payout settlement in isolated-driver hops. Reverts with `ErrorLogged("CISLiquidationDriver address cannot be zero")` if `_cisLiquidationDriver` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `cisLiquidationDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_cisLiquidationDriver`.
- **Restrictions**: `onlyOwner`.

### crossExitHopToken(address[] memory listingAddresses, uint256 impactPercent, address[] memory tokenPath, uint8 settleType, uint256 maxIterations, address listingAddress, uint256[2] memory positionParams, address maker)
- **Parameters**:
  - `listingAddresses` (address[]): Array of up to 4 listing addresses for multi-hop swaps.
  - `impactPercent` (uint256): Maximum price impact percentage for swaps.
  - `tokenPath` (address[]): Array of start/end tokens for the swap.
  - `settleType` (uint8): 0 for market, 1 for liquidation settlement.
  - `maxIterations` (uint256): Maximum iterations for gas control.
  - `listingAddress` (address): Address of the listing for position closure.
  - `positionParams` (uint256[2]): [positionId, positionType] where positionType is 0 (long) or 1 (short).
  - `maker` (address): Address initiating the hop, defaults to `msg.sender` if `address(0)`.
- **Returns**: None.
- **Behavior**: Initiates a cross-driver exit hop with ERC20 tokens:
  - Validates inputs via `_validateHopParams` (non-zero addresses, valid `settleType`, `listingAddresses` length ≤ 4, `tokenPath` length = 2).
  - Calls `_executeExitHop` with `isCrossDriver=true`, which:
    - Initializes hop via `_initExitHop`, incrementing `hopCount` and storing data in `exitHopsCore`, `exitHopsTokens`, `exitHopsStatus`.
    - Calls `CCSExitDriver.drift` to close the position.
    - Verifies payout via `CCListingTemplate.getLongPayout` or `getShortPayout`, storing `actualAmount`.
    - Calls `CCSLiquidationDriver.executeExits` to settle payout.
    - Initiates multi-hop swap via `MultiInitializer.hopToken` setting the ShockExit maker as the multihop maker (recipient).
    - Emits `ExitHopStarted` on success, or `ExitHopCancelled` and `ErrorLogged` on failure.
- **Internal Calls**: `_executeExitHop`, `_validateHopParams`, `_initExitHop`, `_callDriver`, `_checkPayout`, `_callLiquidation`, `_initMultihop`.
- **External Calls**:
  - `CCSExitDriver.drift(positionId, maker)`
  - `CCListingTemplate.getNextOrderId(listingAddress)`
  - `CCListingTemplate.getLongPayout(payoutOrderId)` or `getShortPayout(payoutOrderId)`
  - `CCSLiquidationDriver.executeExits(listingAddress, maxIterations)`
  - `MultiInitializer.hopToken(listingAddresses, impactPercent, tokenPath, actualAmount)`
- **Events**: `ExitHopStarted`, `ExitHopCancelled`, `ErrorLogged`.
- **Gas Controls**: `maxIterations`, `nonReentrant`, helper functions to reduce stack usage.
- **Restrictions**: None.

### crossExitHopNative(address[] memory listingAddresses, uint256 impactPercent, address[] memory tokenPath, uint8 settleType, uint256 maxIterations, address listingAddress, uint256[2] memory positionParams, address maker)
- **Parameters**: Same as `crossExitHopToken`, with native tokens sent via `msg.value`.
- **Returns**: None.
- **Behavior**: Initiates a cross-driver exit hop with native tokens:
  - Similar to `crossExitHopToken`, but calls `MultiInitializer.hopNative` with `msg.value`.
  - Validates `msg.value > 0` and `tokenPath[0] == address(0)` for native token.
  - Follows same flow: validates inputs, closes position, settles payout, initiates hop.
- **Internal Calls**: `_executeExitHop`, `_validateHopParams`, `_initExitHop`, `_callDriver`, `_checkPayout`, `_callLiquidation`, `_initMultihop`.
- **External Calls**:
  - `CCSExitDriver.drift(positionId, maker)`
  - `CCListingTemplate.getNextOrderId(listingAddress)`
  - `CCListingTemplate.getLongPayout(payoutOrderId)` or `getShortPayout(payoutOrderId)`
  - `CCSLiquidationDriver.executeExits(listingAddress, maxIterations)`
  - `MultiInitializer.hopNative(listingAddresses, impactPercent, tokenPath, actualAmount)`
- **Events**: `ExitHopStarted`, `ExitHopCancelled`, `ErrorLogged`.
- **Gas Controls**: `maxIterations`, `nonReentrant`, helper functions.
- **Restrictions**: Payable, requires `msg.value > 0`.

### isolatedExitHopToken(address[] memory listingAddresses, uint256 impactPercent, address[] memory tokenPath, uint8 settleType, uint256 maxIterations, address listingAddress, uint256[2] memory positionParams, address maker)
- **Parameters**: Same as `crossExitHopToken`.
- **Returns**: None.
- **Behavior**: Initiates an isolated-driver exit hop with ERC20 tokens:
  - Same flow as `crossExitHopToken`, but uses `CISExitDriver` and `CISLiquidationDriver`.
  - Calls `_executeExitHop` with `isCrossDriver=false`.
- **Internal Calls**: `_executeExitHop`, `_validateHopParams`, `_initExitHop`, `_callDriver`, `_checkPayout`, `_callLiquidation`, `_initMultihop`.
- **External Calls**:
  - `CISExitDriver.drift(positionId, maker)`
  - `CCListingTemplate.getNextOrderId(listingAddress)`
  - `CCListingTemplate.getLongPayout(payoutOrderId)` or `getShortPayout(payoutOrderId)`
  - `CISLiquidationDriver.executeExits(listingAddress, maxIterations)`
  - `MultiInitializer.hopToken(listingAddresses, impactPercent, tokenPath, actualAmount)`
- **Events**: `ExitHopStarted`, `ExitHopCancelled`, `ErrorLogged`.
- **Gas Controls**: `maxIterations`, `nonReentrant`, helper functions.
- **Restrictions**: None.

### isolatedExitHopNative(address[] memory listingAddresses, uint256 impactPercent, address[] memory tokenPath, uint8 settleType, uint256 maxIterations, address listingAddress, uint256[2] memory positionParams, address maker)
- **Parameters**: Same as `crossExitHopNative`.
- **Returns**: None.
- **Behavior**: Initiates an isolated-driver exit hop with native tokens:
  - Same flow as `crossExitHopNative`, but uses `CISExitDriver` and `CISLiquidationDriver`.
  - Calls `_executeExitHop` with `isCrossDriver=false`.
- **Internal Calls**: `_executeExitHop`, `_validateHopParams`, `_initExitHop`, `_callDriver`, `_checkPayout`, `_callLiquidation`, `_initMultihop`.
- **External Calls**:
  - `CISExitDriver.drift(positionId, maker)`
  - `CCListingTemplate.getNextOrderId(listingAddress)`
  - `CCListingTemplate.getLongPayout(payoutOrderId)` or `getShortPayout(payoutOrderId)`
  - `CISLiquidationDriver.executeExits(listingAddress, maxIterations)`
  - `MultiInitializer.hopNative(listingAddresses, impactPercent, tokenPath, actualAmount)`
- **Events**: `ExitHopStarted`, `ExitHopCancelled`, `ErrorLogged`.
- **Gas Controls**: `maxIterations`, `nonReentrant`, helper functions.
- **Restrictions**: Payable, requires `msg.value > 0`.

### continueCrossExitHops(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum hops to process for gas control.
- **Returns**: None.
- **Behavior**: Processes pending `CCSExitDriver` hops for `msg.sender` up to `maxIterations`. Calls `_continueExitHops` with `user=msg.sender`, `isCrossDriver=true`, which:
  - Validates `multiController`, `multiStorage`, `maxIterations > 0`, `user != address(0)`.
  - Iterates `userHops[msg.sender]`, checking `status == 1` and `isCrossDriver == true`.
  - Calls `MultiController.continueHop` with `exitHopsCore[hopId].multihopId`.
  - Checks `MultiController.getHopOrderDetails` for `status == 2` (completed), updating `exitHopsStatus.status` to 2 and emitting `ExitHopCompleted`.
  - On failure, emits `ErrorLogged` and `ExitHopCancelled`, setting `status` to 3.
- **Internal Calls**: `_continueExitHops`, `uint2str` (for error logging).
- **External Calls**:
  - `MultiController.continueHop(multihopId, maxIterations)`
  - `MultiController.getHopOrderDetails(multihopId)`
- **Events**: `ExitHopCompleted`, `ExitHopCancelled`, `ErrorLogged`.
- **Gas Controls**: `maxIterations`, `nonReentrant`.
- **Restrictions**: None.

### continueIsolatedExitHops(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum hops to process for gas control.
- **Returns**: None.
- **Behavior**: Processes pending `CISExitDriver` hops for `msg.sender` up to `maxIterations`. Calls `_continueExitHops` with `user=msg.sender`, `isCrossDriver=false`, which:
  - Validates inputs and iterates `userHops[msg.sender]`.
  - Calls `MultiController.continueHop` and checks completion as in `continueCrossExitHops`.
  - Updates status and emits events.
- **Internal Calls**: `_continueExitHops`, `uint2str`.
- **External Calls**:
  - `MultiController.continueHop(multihopId, maxIterations)`
  - `MultiController.getHopOrderDetails(multihopId)`
- **Events**: `ExitHopCompleted`, `ExitHopCancelled`, `ErrorLogged`.
- **Gas Controls**: `maxIterations`, `nonReentrant`.
- **Restrictions**: None.

### executeCrossExitHops(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum hops to process globally for gas control.
- **Returns**: None.
- **Behavior**: Processes all pending `CCSExitDriver` hops up to `maxIterations`. Calls `_executeGlobalExitHops` with `isCrossDriver=true`, which:
  - Validates `multiController`, `multiStorage`, `maxIterations > 0`.
  - Iterates `exitHopsStatus` from 0 to `hopCount`, checking `status == 1` and `isCrossDriver == true`.
  - Calls `MultiController.continueHop` and checks `MultiController.getHopOrderDetails` for completion (status == 2).
  - Updates `exitHopsStatus.status` to 2 and emits `ExitHopCompleted` on success, or emits `ErrorLogged` and `ExitHopCancelled` on failure, setting `status` to 3.
- **Internal Calls**: `_executeGlobalExitHops`, `uint2str`.
- **External Calls**:
  - `MultiController.continueHop(multihopId, maxIterations)`
  - `MultiController.getHopOrderDetails(multihopId)`
- **Events**: `ExitHopCompleted`, `ExitHopCancelled`, `ErrorLogged`.
- **Gas Controls**: `maxIterations`, `nonReentrant`.
- **Restrictions**: None.

### executeIsolatedExitHops(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum hops to process globally for gas control.
- **Returns**: None.
- **Behavior**: Processes all pending `CISExitDriver` hops up to `maxIterations`. Calls `_executeGlobalExitHops` with `isCrossDriver=false`, which:
  - Validates inputs and iterates `exitHopsStatus`.
  - Calls `MultiController.continueHop` and checks completion as in `executeCrossExitHops`.
  - Updates status and emits events.
- **Internal Calls**: `_executeGlobalExitHops`, `uint2str`.
- **External Calls**:
  - `MultiController.continueHop(multihopId, maxIterations)`
  - `MultiController.getHopOrderDetails(multihopId)`
- **Events**: `ExitHopCompleted`, `ExitHopCancelled`, `ErrorLogged`.
- **Gas Controls**: `maxIterations`, `nonReentrant`.
- **Restrictions**: None.

### getExitHopDetails(uint256 exitHopId)
- **Parameters**:
  - `exitHopId` (uint256): ID of the exit hop to query.
- **Returns**:
  - `maker` (address): Hop initiator.
  - `multihopId` (uint256): `MultiInitializer` hop ID.
  - `positionId` (uint256): Position ID closed.
  - `listingAddress` (address): Listing address for position closure.
  - `positionType` (uint8): 0 for long, 1 for short.
  - `payoutOrderId` (uint256): Payout order ID from `CCListingTemplate`.
  - `startToken` (address): Token received from position closure.
  - `endToken` (address): Expected end token from multihop.
  - `settleType` (uint8): 0 for market, 1 for liquidation.
  - `status` (uint8): 0=initializing, 1=pending, 2=completed, 3=cancelled.
  - `isCrossDriver` (bool): True for `CCSExitDriver`, false for `CISExitDriver`.
  - `actualAmount` (uint256): Actual amount received (1e18 precision).
- **Behavior**: Retrieves details of an exit hop using helper functions to reduce stack usage:
  - Calls `_getExitHopCore` for `maker`, `multihopId`, `positionId`, `listingAddress` from `exitHopsCore`.
  - Calls `_getExitHopTokens` for `startToken`, `endToken`, `payoutOrderId`, `actualAmount` from `exitHopsTokens`.
  - Calls `_getExitHopStatus` for `positionType`, `settleType`, `status`, `isCrossDriver` from `exitHopsStatus`.
- **Internal Calls**: `_getExitHopCore`, `_getExitHopTokens`, `_getExitHopStatus`.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas, helper functions reduce stack.
- **Restrictions**: None.

### getUserExitHops(address user)
- **Parameters**:
  - `user` (address): User address to query.
- **Returns**:
  - `uint256[]`: Array of hop IDs for the user.
- **Behavior**: Returns `userHops[user]`, an array of exit hop IDs associated with the user.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.
- **Restrictions**: None.

### multiStorageView()
- **Parameters**: None.
- **Returns**:
  - `address`: `multiStorage` address.
- **Behavior**: Returns `multiStorage` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.
- **Restrictions**: None.

### multiInitializerView()
- **Parameters**: None.
- **Returns**:
  - `address`: `multiInitializer` address.
- **Behavior**: Returns `multiInitializer` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.
- **Restrictions**: None.

### multiControllerView()
- **Parameters**: None.
- **Returns**:
  - `address`: `multiController` address.
- **Behavior**: Returns `multiController` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.
- **Restrictions**: None.

### ccsExitDriverView()
- **Parameters**: None.
- **Returns**:
  - `address`: `ccsExitDriver` address.
- **Behavior**: Returns `ccsExitDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.
- **Restrictions**: None.

### cisExitDriverView()
- **Parameters**: None.
- **Returns**:
  - `address`: `cisExitDriver` address.
- **Behavior**: Returns `cisExitDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.
- **Restrictions**: None.

### ccsLiquidationDriverView()
- **Parameters**: None.
- **Returns**:
  - `address`: `ccsLiquidationDriver` address.
- **Behavior**: Returns `ccsLiquidationDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.
- **Restrictions**: None.

### cisLiquidationDriverView()
- **Parameters**: None.
- **Returns**:
  - `address`: `cisLiquidationDriver` address.
- **Behavior**: Returns `cisLiquidationDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.
- **Restrictions**: None.

## Internal Functions

### _validateHopParams(address[] memory listingAddresses, address[] memory tokenPath, uint8 settleType, uint256 maxIterations, address listingAddress, uint256[2] memory positionParams, address maker)
- **Parameters**: Same as `crossExitHopToken`.
- **Behavior**: Validates inputs:
  - Checks `listingAddresses` length ≤ 4, `tokenPath` length = 2.
  - Ensures `settleType` is 0 or 1, `maxIterations > 0`.
  - Validates non-zero addresses for `listingAddress`, drivers, `multiInitializer`, `multiController`, `multiStorage`.
  - Verifies `positionParams[1]` (positionType) is 0 or 1.
  - Emits `ErrorLogged` on invalid inputs.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: `ErrorLogged`.
- **Gas Controls**: Minimal, validation only.
- **Restrictions**: Private.

### _initExitHop(address maker, uint256 multihopId, address listingAddress, uint256 positionId, uint8 positionType, uint8 settleType, address startToken, address endToken, uint256 actualAmount, bool isCrossDriver)
- **Parameters**:
  - `maker` (address): Hop initiator.
  - `multihopId` (uint256): Multi-hop ID.
  - `listingAddress` (address): Listing address.
  - `positionId` (uint256): Position ID.
  - `positionType` (uint8): 0=long, 1=short.
  - `settleType` (uint8): 0=market, 1=liquid.
  - `startToken` (address): Start token.
  - `endToken` (address): End token.
  - `actualAmount` (uint256): Actual amount received.
  - `isCrossDriver` (bool): Driver selection.
- **Behavior**: Initializes hop:
  - Increments `hopCount`, assigns `exitHopId`.
  - Stores data in `exitHopsCore`, `exitHopsTokens`, `exitHopsStatus`.
  - Adds `exitHopId` to `userHops[maker]`.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: Minimal, mapping updates.
- **Restrictions**: Private.

### _callDriver(uint256 positionId, address maker, bool isCrossDriver)
- **Parameters**:
  - `positionId` (uint256): Position to close.
  - `maker` (address): Hop initiator.
  - `isCrossDriver` (bool): Driver selection.
- **Behavior**: Calls `drift` on `CCSExitDriver` or `CISExitDriver` based on `isCrossDriver`. Uses `try-catch` to handle failures, emitting `ErrorLogged` on error.
- **Internal Calls**: None.
- **External Calls**: `CCSExitDriver.drift` or `CISExitDriver.drift`.
- **Events**: `ErrorLogged`.
- **Gas Controls**: Minimal, single external call.
- **Restrictions**: Private.

### _checkPayout(address listingAddress, uint256 payoutOrderId, uint8 positionType)
- **Parameters**:
  - `listingAddress` (address): Listing address.
  - `payoutOrderId` (uint256): Payout order ID.
  - `positionType` (uint8): 0=long, 1=short.
- **Behavior**: Verifies payout via `CCListingTemplate.getLongPayout` or `getShortPayout`. Returns `payoutSettled` and `actualAmount`. Emits `ErrorLogged` on failure.
- **Internal Calls**: None.
- **External Calls**: `CCListingTemplate.getLongPayout` or `getShortPayout`.
- **Events**: `ErrorLogged`.
- **Gas Controls**: Minimal, single external call.
- **Restrictions**: Private.

### _callLiquidation(address listingAddress, uint256 maxIterations, bool isCrossDriver)
- **Parameters**:
  - `listingAddress` (address): Listing address.
  - `maxIterations` (uint256): Gas limit.
  - `isCrossDriver` (bool): Driver selection.
- **Behavior**: Calls `executeExits` on `CCSLiquidationDriver` or `CISLiquidationDriver`. Uses `try-catch`, emits `ErrorLogged` on failure.
- **Internal Calls**: None.
- **External Calls**: `CCSLiquidationDriver.executeExits` or `CISLiquidationDriver.executeExits`.
- **Events**: `ErrorLogged`.
- **Gas Controls**: Bounded by `maxIterations`.
- **Restrictions**: Private.

### _initMultihop(address[] memory listingAddresses, uint256 impactPercent, address[] memory tokenPath, uint256 actualAmount, bool isNative)
- **Parameters**:
  - `listingAddresses` (address[]): Listing addresses.
  - `impactPercent` (uint256): Price impact.
  - `tokenPath` (address[]): Start/end tokens.
  - `actualAmount` (uint256): Amount to swap.
  - `isNative` (bool): Native token flag.
- **Behavior**: Calls `MultiInitializer.hopToken` or `hopNative` based on `isNative`. Returns `multihopId`. Emits `ErrorLogged` on failure.
- **Internal Calls**: None.
- **External Calls**: `MultiInitializer.hopToken` or `hopNative`.
- **Events**: `ErrorLogged`.
- **Gas Controls**: Minimal, single external call.
- **Restrictions**: Private.

### _executeExitHop(address maker, address[] memory listingAddresses, address[] memory tokenPath, uint256 impactPercent, uint8 settleType, uint256 maxIterations, address listingAddress, uint256 positionId, uint8 positionType, bool isCrossDriver, bool isNative)
- **Parameters**: Combines `HopParams`, `PositionParams`, and driver/native flags.
- **Behavior**: Orchestrates hop execution:
  - Validates via `_validateHopParams`.
  - Initializes via `_initExitHop`.
  - Closes position via `_callDriver`.
  - Verifies payout via `_checkPayout`.
  - Settles payout via `_callLiquidation`.
  - Initiates hop via `_initMultihop`.
  - Emits `ExitHopStarted` or `ExitHopCancelled` on failure.
- **Internal Calls**: `_validateHopParams`, `_initExitHop`, `_callDriver`, `_checkPayout`, `_callLiquidation`, `_initMultihop`.
- **External Calls**: As per internal calls.
- **Events**: `ExitHopStarted`, `ExitHopCancelled`, `ErrorLogged`.
- **Gas Controls**: `maxIterations`, `nonReentrant`.
- **Restrictions**: Private.

### _continueExitHops(address user, uint256 maxIterations, bool isCrossDriver)
- **Parameters**:
  - `user` (address): User to process hops for.
  - `maxIterations` (uint256): Gas limit.
  - `isCrossDriver` (bool): Driver selection.
- **Behavior**: Iterates `userHops[user]` up to `maxIterations`, processes pending hops (`status == 1`, matching `isCrossDriver`):
  - Calls `MultiController.continueHop`.
  - Checks `MultiController.getHopOrderDetails` for completion.
  - Updates `status` to 2 or 3, emits `ExitHopCompleted` or `ExitHopCancelled`.
- **Internal Calls**: `uint2str`.
- **External Calls**: `MultiController.continueHop`, `MultiController.getHopOrderDetails`.
- **Events**: `ExitHopCompleted`, `ExitHopCancelled`, `ErrorLogged`.
- **Gas Controls**: `maxIterations`.
- **Restrictions**: Private.

### _executeGlobalExitHops(uint256 maxIterations, bool isCrossDriver)
- **Parameters**:
  - `maxIterations` (uint256): Gas limit.
  - `isCrossDriver` (bool): Driver selection.
- **Behavior**: Iterates `exitHopsStatus` up to `hopCount` and `maxIterations`, processes pending hops (`status == 1`, matching `isCrossDriver`):
  - Calls `MultiController.continueHop`.
  - Checks completion, updates `status`, emits events as in `_continueExitHops`.
- **Internal Calls**: `uint2str`.
- **External Calls**: `MultiController.continueHop`, `MultiController.getHopOrderDetails`.
- **Events**: `ExitHopCompleted`, `ExitHopCancelled`, `ErrorLogged`.
- **Gas Controls**: `maxIterations`.
- **Restrictions**: Private.

### _getExitHopCore(uint256 exitHopId)
- **Parameters**:
  - `exitHopId` (uint256): Hop ID.
- **Returns**: `ExitHopCore` (maker, multihopId, positionId, listingAddress).
- **Behavior**: Retrieves `exitHopsCore[exitHopId]`.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: Minimal, mapping access.
- **Restrictions**: Private.

### _getExitHopTokens(uint256 exitHopId)
- **Parameters**:
  - `exitHopId` (uint256): Hop ID.
- **Returns**: `ExitHopTokens` (startToken, endToken, payoutOrderId, actualAmount).
- **Behavior**: Retrieves `exitHopsTokens[exitHopId]`.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: Minimal, mapping access.
- **Restrictions**: Private.

### _getExitHopStatus(uint256 exitHopId)
- **Parameters**:
  - `exitHopId` (uint256): Hop ID.
- **Returns**: `ExitHopStatus` (positionType, settleType, status, isCrossDriver).
- **Behavior**: Retrieves `exitHopsStatus[exitHopId]`.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: Minimal, mapping access.
- **Restrictions**: Private.

### uint2str(uint256 value)
- **Parameters**:
  - `value` (uint256): Number to convert.
- **Returns**: `string`: String representation.
- **Behavior**: Converts `uint256` to string for error logging.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: Minimal, pure function.
- **Restrictions**: Private.

## Additional Details
- **Interactions**: Interacts with:
  - `CCSExitDriver`/`CISExitDriver` (`drift` for position closure).
  - `CCSLiquidationDriver`/`CISLiquidationDriver` (`executeExits` for payout settlement).
  - `MultiInitializer` (`hopToken`, `hopNative` for multi-hop swaps).
  - `MultiController` (`continueHop`, `getHopOrderDetails` for hop continuation).
  - `CCListingTemplate` (`getLongPayout`, `getShortPayout`, `getNextOrderId` for payout verification).
- **Reentrancy Protection**: `nonReentrant` modifier on state-changing functions (`crossExitHopToken`, `crossExitHopNative`, `isolatedExitHopToken`, `isolatedExitHopNative`, `continueCrossExitHops`, `continueIsolatedExitHops`, `executeCrossExitHops`, `executeIsolatedExitHops`).
- **Gas Optimization**: Uses `maxIterations` to limit loops, helper functions to reduce stack depth, avoids inline assembly.
- **Safety**: Explicit casting for all types, `try-catch` for external calls, no reserved keywords, public state variables accessed directly without view functions.
- **Decimal Handling**: Relies on `CCListingTemplate.decimalsA`/`decimalsB` for token decimals, ensuring consistent precision.
- **Hop Lifecycle**: Managed via `exitHopsStatus.status` (0=initializing, 1=pending, 2=completed, 3=cancelled).
- **Error Handling**: All external calls wrapped in `try-catch`, emitting `ErrorLogged` with decoded error strings for graceful degradation.
