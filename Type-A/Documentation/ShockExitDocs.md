# ShockExit Contract Documentation

## Overview
The `ShockExit` contract, implemented in Solidity (^0.8.2), facilitates position closure via `CCSExitDriver` or `CISExitDriver`, followed by multi-hop token swaps using `MultiInitializer` and `MultiController`. It supports up to four listings for token swaps, handles payout settlement, and ensures secure execution with reentrancy protection via `ReentrancyGuard` and administrative control via `Ownable`. State variables are public, and mappings track user hops and exit details. The contract avoids `SafeERC20`, uses explicit casting, and employs `try-catch` for external calls, per the style guide.

**SPDX License:** BSL-1.1 - Peng Protocol 2025

**Version:** 0.0.64 (last updated 2025-08-13)

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
- v0.0.64: Split `getExitHopDetails` into `_getExitHopCore`, `_getExitHopTokens`, `_getExitHopStatus` to resolve stack-too-deep error.
- v0.0.63: Removed `view` from `_validateInputs` to allow `ErrorLogged` emissions.
- v0.0.62: Refactored `_executeExitHop` with helper functions to reduce stack usage.
- v0.0.59–0.0.61: Added native token support, improved error handling.

## Clarifications
- **Position Closure**: Closes positions via `CCSExitDriver` or `CISExitDriver` (`drift`), verifies payout settlement via `CCListingTemplate`, and initiates multi-hop swaps.
- **Hop Execution**: Supports ERC20 and native token swaps with up to four listings. `maxIterations` limits gas usage.
- **Payout Handling**: Verifies payout completion before multihop initiation.
- **Continuation**: Processes pending hops, updating status to completed or cancelled.
- **Error Handling**: Uses `try-catch` for external calls, emitting `ErrorLogged` with decoded reasons.
- **Maker Flexibility**: `maker` defaults to `msg.sender` if `address(0)`.
- **Decimal Handling**: Relies on `CCListingTemplate.decimalsA`/`decimalsB`.
- **Hop Status**: Tracks initializing (0), pending (1), completed (2), or cancelled (3).
- **Gas Optimization**: Uses `maxIterations`, helper functions, no inline assembly.

## State Variables
- **ccsExitDriver** (address, public): `CCSExitDriver` address.
- **cisExitDriver** (address, public): `CISExitDriver` address.
- **ccsLiquidationDriver** (address, public): `CCSLiquidationDriver` address.
- **cisLiquidationDriver** (address, public): `CISLiquidationDriver` address.
- **multiInitializer** (address, public): `MultiInitializer` address.
- **multiController** (address, public): `MultiController` address.
- **multiStorage** (address, public): `MultiStorage` address.
- **hopCount** (uint256, public): Total exit hops.
- **userHops** (mapping(address => uint256[]), public): User hop IDs.
- **exitHopsCore** (mapping(uint256 => ExitHopCore), public): Core hop details.
- **exitHopsTokens** (mapping(uint256 => ExitHopTokens), public): Token details.
- **exitHopsStatus** (mapping(uint256 => ExitHopStatus), public): Status details.

## Structs
- **ExitHopCore**: `maker` (address), `multihopId` (uint256), `positionId` (uint256), `listingAddress` (address).
- **ExitHopTokens**: `startToken` (address), `endToken` (address), `payoutOrderId` (uint256).
- **ExitHopStatus**: `positionType` (uint8, 0=long, 1=short), `settleType` (uint8, 0=market, 1=liquid), `status` (uint8, 0=initializing, 1=pending, 2=completed, 3=cancelled), `isCrossDriver` (bool).
- **HopParams**: `listingAddresses` (address[]), `startToken` (address), `endToken` (address), `impactPercent` (uint256), `settleType` (uint8), `maxIterations` (uint256).
- **PositionParams**: `listingAddress` (address), `positionId` (uint256), `positionType` (uint8).
- **ExitHopData**: Internal, `exitHopId` (uint256), `payoutSettled` (bool), `multihopId` (uint256), `listingAddress` (address).

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

### setMultiInitializer(address _multiInitializer)
- **Parameters**:
  - `_multiInitializer` (address): Address of `MultiInitializer` contract.
- **Returns**: None.
- **Behavior**: Sets `multiInitializer` address, used by `_initMultihop` to initiate hops. Reverts with `ErrorLogged("MultiInitializer address cannot be zero")` if `_multiInitializer` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `multiInitializer` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_multiInitializer`.

### setMultiController(address _multiController)
- **Parameters**:
  - `_multiController` (address): Address of `MultiController` contract.
- **Returns**: None.
- **Behavior**: Sets `multiController` address, used by `_continueExitHops` and `_executeGlobalExitHops` for hop continuation. Reverts with `ErrorLogged("MultiController address cannot be zero")` if `_multiController` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `multiController` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_multiController`.

### setCCSExitDriver(address _ccsExitDriver)
- **Parameters**:
  - `_ccsExitDriver` (address): Address of `CCSExitDriver` contract.
- **Returns**: None.
- **Behavior**: Sets `ccsExitDriver` address, used by `_callDriver` for position closure in cross-driver hops. Reverts with `ErrorLogged("CCSExitDriver address cannot be zero")` if `_ccsExitDriver` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `ccsExitDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_ccsExitDriver`.

### setCISExitDriver(address _cisExitDriver)
- **Parameters**:
  - `_cisExitDriver` (address): Address of `CISExitDriver` contract.
- **Returns**: None.
- **Behavior**: Sets `cisExitDriver` address, used by `_callDriver` for position closure in isolated-driver hops. Reverts with `ErrorLogged("CISExitDriver address cannot be zero")` if `_cisExitDriver` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `cisExitDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_cisExitDriver`.

### setCCSLiquidationDriver(address _ccsLiquidationDriver)
- **Parameters**:
  - `_ccsLiquidationDriver` (address): Address of `CCSLiquidationDriver` contract.
- **Returns**: None.
- **Behavior**: Sets `ccsLiquidationDriver` address, used by `_callLiquidation` for payout settlement in cross-driver hops. Reverts with `ErrorLogged("CCSLiquidationDriver address cannot be zero")` if `_ccsLiquidationDriver` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `ccsLiquidationDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_ccsLiquidationDriver`.

### setCISLiquidationDriver(address _cisLiquidationDriver)
- **Parameters**:
  - `_cisLiquidationDriver` (address): Address of `CISLiquidationDriver` contract.
- **Returns**: None.
- **Behavior**: Sets `cisLiquidationDriver` address, used by `_callLiquidation` for payout settlement in isolated-driver hops. Reverts with `ErrorLogged("CISLiquidationDriver address cannot be zero")` if `_cisLiquidationDriver` is `address(0)`. Restricted to owner via `onlyOwner`. Updates `cisLiquidationDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: Emits `ErrorLogged` on invalid input.
- **Gas Controls**: Minimal, checks only `_cisLiquidationDriver`.

### crossExitHopToken(address[] memory listings, uint256 impactPercent, address[2] memory tokens, uint8 settleType, uint256 maxIterations, address listingAddress, uint256[2] memory positionParams, address maker)
- **Parameters**:
  - `listings` (address[]): Array of up to 4 listing addresses for multi-hop swaps.
  - `impactPercent` (uint256): Maximum price impact percentage for swaps.
  - `tokens` (address[2]): `[startToken, endToken]` for the swap.
  - `settleType` (uint8): 0 for market, 1 for liquid settlement.
  - `maxIterations` (uint256): Maximum hops to process for gas control.
  - `listingAddress` (address): Address of the listing for position closure.
  - `positionParams` (uint256[2]): `[positionId, positionType]` (0=long, 1=short).
  - `maker` (address): Address owning the hop; defaults to `msg.sender` if `address(0)`.
- **Returns**: None.
- **Behavior**: Initiates an ERC20-based position closure using `CCSExitDriver` followed by a multi-hop swap via `MultiInitializer`. Validates inputs (`multiInitializer`, `ccsExitDriver`, `ccsLiquidationDriver`, `multiStorage`, `listings.length <= 4`, `settleType <= 1`, `maxIterations > 0`, `positionParams[1] <= 1`). Calls `_executeExitHop` with `isCrossDriver=true`, `isNative=false`, which:
  - Validates inputs via `_validateInputs`, checking non-zero `maker`, `listingAddress`, `tokens`, and `listings` entries.
  - Initializes hop via `_initExitHop`, storing data in `exitHopsCore`, `exitHopsTokens`, `exitHopsStatus`, and `userHops`.
  - Calls `CCSExitDriver.drift` via `_callDriver` to close the position, storing `payoutOrderId` from `CCListingTemplate.getNextOrderId`.
  - Verifies payout via `_checkPayout` using `CCListingTemplate.getLongPayout` or `getShortPayout` (status == 3).
  - Executes `CCSLiquidationDriver.executeExits` via `_callLiquidation` for payout settlement.
  - Initiates swap via `_initMultihop`, calling `MultiInitializer.hopToken` with `listings`, `impactPercent`, `tokens`, `settleType`, and `maxIterations`.
  - Emits `ExitHopStarted` on success, or `ExitHopCancelled` and `ErrorLogged` on failure.
- **Internal Calls**: `_executeExitHop` (calls `_validateInputs`, `_initExitHop`, `_callDriver`, `_checkPayout`, `_callLiquidation`, `_initMultihop`).
- **External Calls**:
  - `CCSExitDriver.drift(positionId, maker)`
  - `CCListingTemplate.getNextOrderId`
  - `CCListingTemplate.getLongPayout` or `getShortPayout`
  - `CCSLiquidationDriver.executeExits(listingAddress, maxIterations)`
  - `MultiInitializer.hopToken(...)`
- **Events**: `ExitHopStarted`, `ExitHopCancelled`, `ErrorLogged`.
- **Gas Controls**: `maxIterations`, `nonReentrant`, helper functions reduce stack usage.

### crossExitHopNative(address[] memory listings, uint256 impactPercent, address[2] memory tokens, uint8 settleType, uint256 maxIterations, address listingAddress, uint256[2] memory positionParams, address maker)
- **Parameters**:
  - `listings` (address[]): Array of up to 4 listing addresses for multi-hop swaps.
  - `impactPercent` (uint256): Maximum price impact percentage for swaps.
  - `tokens` (address[2]): `[startToken, endToken]` for the swap.
  - `settleType` (uint8): 0 for market, 1 for liquid settlement.
  - `maxIterations` (uint256): Maximum hops to process for gas control.
  - `listingAddress` (address): Address of the listing for position closure.
  - `positionParams` (uint256[2]): `[positionId, positionType]` (0=long, 1=short).
  - `maker` (address): Address owning the hop; defaults to `msg.sender` if `address(0)`.
- **Returns**: None.
- **Behavior**: Initiates a native token-based position closure using `CCSExitDriver` followed by a multi-hop swap via `MultiInitializer`. Validates inputs (`multiInitializer`, `ccsExitDriver`, `ccsLiquidationDriver`, `multiStorage`, `listings.length <= 4`, `settleType <= 1`, `maxIterations > 0`, `positionParams[1] <= 1`, `msg.value > 0`). Calls `_executeExitHop` with `isCrossDriver=true`, `isNative=true`, which:
  - Validates inputs via `_validateInputs`.
  - Initializes hop via `_initExitHop`.
  - Calls `CCSExitDriver.drift` via `_callDriver`.
  - Verifies payout via `_checkPayout`.
  - Executes `CCSLiquidationDriver.executeExits` via `_callLiquidation`.
  - Initiates swap via `_initMultihop`, calling `MultiInitializer.hopNative` with `msg.value`.
  - Emits `ExitHopStarted` or `ExitHopCancelled`/`ErrorLogged` on failure.
- **Internal Calls**: `_executeExitHop` (calls `_validateInputs`, `_initExitHop`, `_callDriver`, `_checkPayout`, `_callLiquidation`, `_initMultihop`).
- **External Calls**:
  - `CCSExitDriver.drift(positionId, maker)`
  - `CCListingTemplate.getNextOrderId`
  - `CCListingTemplate.getLongPayout` or `getShortPayout`
  - `CCSLiquidationDriver.executeExits(listingAddress, maxIterations)`
  - `MultiInitializer.hopNative(...)`
- **Events**: `ExitHopStarted`, `ExitHopCancelled`, `ErrorLogged`.
- **Gas Controls**: `maxIterations`, `nonReentrant`, helper functions.

### isolatedExitHopToken(address[] memory listings, uint256 impactPercent, address[2] memory tokens, uint8 settleType, uint256 maxIterations, address listingAddress, uint256[2] memory positionParams, address maker)
- **Parameters**:
  - `listings` (address[]): Array of up to 4 listing addresses for multi-hop swaps.
  - `impactPercent` (uint256): Maximum price impact percentage for swaps.
  - `tokens` (address[2]): `[startToken, endToken]` for the swap.
  - `settleType` (uint8): 0 for market, 1 for liquid settlement.
  - `maxIterations` (uint256): Maximum hops to process for gas control.
  - `listingAddress` (address): Address of the listing for position closure.
  - `positionParams` (uint256[2]): `[positionId, positionType]` (0=long, 1=short).
  - `maker` (address): Address owning the hop; defaults to `msg.sender` if `address(0)`.
- **Returns**: None.
- **Behavior**: Initiates an ERC20-based position closure using `CISExitDriver` followed by a multi-hop swap via `MultiInitializer`. Validates inputs (`multiInitializer`, `cisExitDriver`, `cisLiquidationDriver`, `multiStorage`, `listings.length <= 4`, `settleType <= 1`, `maxIterations > 0`, `positionParams[1] <= 1`). Calls `_executeExitHop` with `isCrossDriver=false`, `isNative=false`, which:
  - Validates inputs via `_validateInputs`.
  - Initializes hop via `_initExitHop`.
  - Calls `CISExitDriver.drift` via `_callDriver`.
  - Verifies payout via `_checkPayout`.
  - Executes `CISLiquidationDriver.executeExits` via `_callLiquidation`.
  - Initiates swap via `_initMultihop`, calling `MultiInitializer.hopToken`.
  - Emits `ExitHopStarted` or `ExitHopCancelled`/`ErrorLogged`.
- **Internal Calls**: `_executeExitHop` (calls `_validateInputs`, `_initExitHop`, `_callDriver`, `_checkPayout`, `_callLiquidation`, `_initMultihop`).
- **External Calls**:
  - `CISExitDriver.drift(positionId, maker)`
  - `CCListingTemplate.getNextOrderId`
  - `CCListingTemplate.getLongPayout` or `getShortPayout`
  - `CISLiquidationDriver.executeExits(listingAddress, maxIterations)`
  - `MultiInitializer.hopToken(...)`
- **Events**: `ExitHopStarted`, `ExitHopCancelled`, `ErrorLogged`.
- **Gas Controls**: `maxIterations`, `nonReentrant`, helper functions.

### isolatedExitHopNative(address[] memory listings, uint256 impactPercent, address[2] memory tokens, uint8 settleType, uint256 maxIterations, address listingAddress, uint256[2] memory positionParams, address maker)
- **Parameters**:
  - `listings` (address[]): Array of up to 4 listing addresses for multi-hop swaps.
  - `impactPercent` (uint256): Maximum price impact percentage for swaps.
  - `tokens` (address[2]): `[startToken, endToken]` for the swap.
  - `settleType` (uint8): 0 for market, 1 for liquid settlement.
  - `maxIterations` (uint256): Maximum hops to process for gas control.
  - `listingAddress` (address): Address of the listing for position closure.
  - `positionParams` (uint256[2]): `[positionId, positionType]` (0=long, 1=short).
  - `maker` (address): Address owning the hop; defaults to `msg.sender` if `address(0)`.
- **Returns**: None.
- **Behavior**: Initiates a native token-based position closure using `CISExitDriver` followed by a multi-hop swap via `MultiInitializer`. Validates inputs (`multiInitializer`, `cisExitDriver`, `cisLiquidationDriver`, `multiStorage`, `listings.length <= 4`, `settleType <= 1`, `maxIterations > 0`, `positionParams[1] <= 1`, `msg.value > 0`). Calls `_executeExitHop` with `isCrossDriver=false`, `isNative=true`, which:
  - Validates inputs via `_validateInputs`.
  - Initializes hop via `_initExitHop`.
  - Calls `CISExitDriver.drift` via `_callDriver`.
  - Verifies payout via `_checkPayout`.
  - Executes `CISLiquidationDriver.executeExits` via `_callLiquidation`.
  - Initiates swap via `_initMultihop`, calling `MultiInitializer.hopNative`.
  - Emits `ExitHopStarted` or `ExitHopCancelled`/`ErrorLogged`.
- **Internal Calls**: `_executeExitHop` (calls `_validateInputs`, `_initExitHop`, `_callDriver`, `_checkPayout`, `_callLiquidation`, `_initMultihop`).
- **External Calls**:
  - `CISExitDriver.drift(positionId, maker)`
  - `CCListingTemplate.getNextOrderId`
  - `CCListingTemplate.getLongPayout` or `getShortPayout`
  - `CISLiquidationDriver.executeExits(listingAddress, maxIterations)`
  - `MultiInitializer.hopNative(...)`
- **Events**: `ExitHopStarted`, `ExitHopCancelled`, `ErrorLogged`.
- **Gas Controls**: `maxIterations`, `nonReentrant`, helper functions.

### continueCrossExitHops(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum hops to process for gas control.
- **Returns**: None.
- **Behavior**: Processes pending `CCSExitDriver` hops for `msg.sender` up to `maxIterations`. Calls `_continueExitHops` with `user=msg.sender`, `isCrossDriver=true`, which:
  - Validates `multiController`, `multiStorage`, `maxIterations > 0`, `user != address(0)`.
  - Iterates `userHops[msg.sender]`, checking `status == 1` and `isCrossDriver`.
  - Calls `MultiController.continueHop` with `exitHopsCore[hopId].multihopId`.
  - Checks `MultiController.getHopOrderDetails` for `status == 2` (completed), updating `exitHopsStatus.status` to 2 and emitting `ExitHopCompleted`.
  - On failure, emits `ErrorLogged` and `ExitHopCancelled`, setting `status` to 3.
- **Internal Calls**: `_continueExitHops` (calls `uint2str` for error logging).
- **External Calls**:
  - `MultiController.continueHop(multihopId, maxIterations)`
  - `MultiController.getHopOrderDetails(multihopId)`
- **Events**: `ExitHopCompleted`, `ExitHopCancelled`, `ErrorLogged`.
- **Gas Controls**: `maxIterations`, `nonReentrant`.

### continueIsolatedExitHops(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum hops to process for gas control.
- **Returns**: None.
- **Behavior**: Processes pending `CISExitDriver` hops for `msg.sender` up to `maxIterations`. Calls `_continueExitHops` with `user=msg.sender`, `isCrossDriver=false`, which:
  - Validates inputs and iterates `userHops[msg.sender]`.
  - Calls `MultiController.continueHop` and checks completion.
  - Updates status and emits events as in `continueCrossExitHops`.
- **Internal Calls**: `_continueExitHops` (calls `uint2str`).
- **External Calls**:
  - `MultiController.continueHop(multihopId, maxIterations)`
  - `MultiController.getHopOrderDetails(multihopId)`
- **Events**: `ExitHopCompleted`, `ExitHopCancelled`, `ErrorLogged`.
- **Gas Controls**: `maxIterations`, `nonReentrant`.

### executeCrossExitHops(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum hops to process globally for gas control.
- **Returns**: None.
- **Behavior**: Processes all pending `CCSExitDriver` hops up to `maxIterations`. Calls `_executeGlobalExitHops` with `isCrossDriver=true`, which:
  - Validates `multiController`, `multiStorage`, `maxIterations > 0`.
  - Iterates `exitHopsStatus` from 0 to `hopCount`, checking `status == 1` and `isCrossDriver`.
  - Calls `MultiController.continueHop` and checks `MultiController.getHopOrderDetails` for completion (status == 2).
  - Updates `exitHopsStatus.status` to 2 and emits `ExitHopCompleted` on success, or emits `ErrorLogged` and `ExitHopCancelled` on failure, setting `status` to 3.
- **Internal Calls**: `_executeGlobalExitHops` (calls `uint2str`).
- **External Calls**:
  - `MultiController.continueHop(multihopId, maxIterations)`
  - `MultiController.getHopOrderDetails(multihopId)`
- **Events**: `ExitHopCompleted`, `ExitHopCancelled`, `ErrorLogged`.
- **Gas Controls**: `maxIterations`, `nonReentrant`.

### executeIsolatedExitHops(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum hops to process globally for gas control.
- **Returns**: None.
- **Behavior**: Processes all pending `CISExitDriver` hops up to `maxIterations`. Calls `_executeGlobalExitHops` with `isCrossDriver=false`, which:
  - Validates inputs and iterates `exitHopsStatus`.
  - Calls `MultiController.continueHop` and checks completion as in `executeCrossExitHops`.
  - Updates status and emits events.
- **Internal Calls**: `_executeGlobalExitHops` (calls `uint2str`).
- **External Calls**:
  - `MultiController.continueHop(multihopId, maxIterations)`
  - `MultiController.getHopOrderDetails(multihopId)`
- **Events**: `ExitHopCompleted`, `ExitHopCancelled`, `ErrorLogged`.
- **Gas Controls**: `maxIterations`, `nonReentrant`.

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
  - `settleType` (uint8): 0 for market, 1 for liquid.
  - `status` (uint8): 0=initializing, 1=pending, 2=completed, 3=cancelled.
  - `isCrossDriver` (bool): True for `CCSExitDriver`, false for `CISExitDriver`.
- **Behavior**: Retrieves details of an exit hop using helper functions to reduce stack usage:
  - Calls `_getExitHopCore` for `maker`, `multihopId`, `positionId`, `listingAddress` from `exitHopsCore`.
  - Calls `_getExitHopTokens` for `startToken`, `endToken`, `payoutOrderId` from `exitHopsTokens`.
  - Calls `_getExitHopStatus` for `positionType`, `settleType`, `status`, `isCrossDriver` from `exitHopsStatus`.
- **Internal Calls**: `_getExitHopCore`, `_getExitHopTokens`, `_getExitHopStatus`.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas, helper functions reduce stack.

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

### multiStorageView()
- **Parameters**: None.
- **Returns**:
  - `address`: `multiStorage` address.
- **Behavior**: Returns `multiStorage` state variable.
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

### ccsExitDriverView()
- **Parameters**: None.
- **Returns**:
  - `address`: `ccsExitDriver` address.
- **Behavior**: Returns `ccsExitDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.

### cisExitDriverView()
- **Parameters**: None.
- **Returns**:
  - `address`: `cisExitDriver` address.
- **Behavior**: Returns `cisExitDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.

### ccsLiquidationDriverView()
- **Parameters**: None.
- **Returns**:
  - `address`: `ccsLiquidationDriver` address.
- **Behavior**: Returns `ccsLiquidationDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.

### cisLiquidationDriverView()
- **Parameters**: None.
- **Returns**:
  - `address`: `cisLiquidationDriver` address.
- **Behavior**: Returns `cisLiquidationDriver` state variable.
- **Internal Calls**: None.
- **External Calls**: None.
- **Events**: None.
- **Gas Controls**: View function, minimal gas.

## Additional Details
- **Interactions**: Interacts with `CCSExitDriver`/`CISExitDriver` (`drift`), `CCSLiquidationDriver`/`CISLiquidationDriver` (`executeExits`), `MultiInitializer` (`hopToken`, `hopNative`), `MultiController` (`continueHop`, `getHopOrderDetails`), and `CCListingTemplate` (`getLongPayout`, `getShortPayout`, `getNextOrderId`).
- **Reentrancy Protection**: `nonReentrant` on state-changing functions.
- **Gas Optimization**: `maxIterations`, helper functions, no inline assembly.
- **Safety**: Explicit casting, no reserved keywords, `try-catch` for external calls, public state variables accessed directly.
