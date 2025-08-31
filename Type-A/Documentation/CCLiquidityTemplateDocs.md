# CCLiquidityTemplate Documentation

## Overview
The `CCLiquidityTemplate`, implemented in Solidity (^0.8.2), manages liquidity pools, fees, and slot updates in a decentralized trading platform. It integrates with `ICCAgent`, `ITokenRegistry`, `ICCListing`, `IERC20`, and `ICCGlobalizer` for registry updates, token operations, and liquidity globalization. State variables are public, accessed via auto-generated getters or unique view functions, with amounts normalized to 1e18. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation with try-catch for external calls. Reentrancy protection is handled at the router level.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.1.7 (Updated 2025-08-31)

**Changes**:
- v0.1.7: Removed `xPrepOut`, `xExecuteOut`, `yPrepOut`, `yExecuteOut`, moved to `CCLiquidityPartial.sol` (v0.1.4). Renamed `update` to `ccUpdate` to align with `CCLiquidityPartial.sol` and avoid call forwarding.
- v0.1.6: Added `resetRouters` function to fetch lister via `ICCAgent.getLister`, restrict to lister, and update `routers` and `routerAddresses` with `ICCAgent.getRouters`.
- v0.1.4: Removed fixed gas limit in `globalizeUpdate` for `ICCAgent.globalizerAddress` and `ITokenRegistry.initializeBalances`. Modified `globalizeUpdate` to emit events (`GlobalizeUpdateFailed`, `UpdateRegistryFailed`) on failure without reverting, ensuring deposits succeed. Consolidated registry update into `globalizeUpdate` for atomicity.
- v0.1.3: Removed duplicate subtraction in `transactToken` and `transactNative`, as liquidity updates are handled via `ccUpdate`. Updated balance checks to use `xLiquid`/`yLiquid`, excluding fees.
- v0.1.2: Integrated `update` calls with `updateType == 0` for subtraction. Maintained fee segregation.

**Compatibility**:
- CCListingTemplate.sol (v0.0.10)
- CCLiquidityRouter.sol (v0.0.25)
- CCMainPartial.sol (v0.1.3)
- CCGlobalizer.sol (v0.2.1)
- ICCLiquidity.sol (v0.0.5)
- ICCListing.sol (v0.0.7)
- CCSEntryPartial.sol (v0.0.18)

## Interfaces
- **IERC20**: Provides `decimals()` for normalization, `transfer(address, uint256)` for token transfers.
- **ICCListing**: Provides `prices(uint256)` (returns `price`), `volumeBalances(uint256)` (returns `xBalance`, `yBalance`), `decimalsA()`, `decimalsB()`, `tokenA()`, `tokenB()`.
- **ICCAgent**: Provides `registryAddress()`, `globalizerAddress()`, `getLister(address)` (returns lister address), `getRouters()` (returns router addresses).
- **ITokenRegistry**: Provides `initializeBalances(address token, address[] memory users)` for balance updates.
- **ICCGlobalizer**: Provides `globalizeLiquidity(address depositor, address token)` for liquidity tracking.

## State Variables
- **`routersSet`**: `bool public` - Tracks if routers are set.
- **`listingAddress`**: `address public` - Listing contract address.
- **`tokenA`**: `address public` - Token A address (ETH if zero).
- **`tokenB`**: `address public` - Token B address (ETH if zero).
- **`listingId`**: `uint256 public` - Listing identifier.
- **`agent`**: `address public` - Agent contract address.
- **`liquidityDetail`**: `LiquidityDetails public` - Stores `xLiquid`, `yLiquid`, `xFees`, `yFees`, `xFeesAcc`, `yFeesAcc`.
- **`activeXLiquiditySlots`**: `uint256[] public` - Active xSlot indices.
- **`activeYLiquiditySlots`**: `uint256[] public` - Active ySlot indices.
- **`routerAddresses`**: `address[] public` - Authorized router addresses.

## Mappings
- **`routers`**: `mapping(address => bool) public` - Authorized routers.
- **`xLiquiditySlots`**: `mapping(uint256 => Slot) public` - Token A slot data.
- **`yLiquiditySlots`**: `mapping(uint256 => Slot) public` - Token B slot data.
- **`userXIndex`**: `mapping(address => uint256[]) public` - User xSlot indices.
- **`userYIndex`**: `mapping(address => uint256[]) public` - User ySlot indices.

## Structs
1. **LiquidityDetails**:
   - `xLiquid`: Normalized token A liquidity.
   - `yLiquid`: Normalized token B liquidity.
   - `xFees`: Normalized token A fees.
   - `yFees`: Normalized token B fees.
   - `xFeesAcc`: Cumulative token A fee volume.
   - `yFeesAcc`: Cumulative token B fee volume.

2. **Slot**:
   - `depositor`: Slot owner.
   - `recipient`: Address receiving withdrawals.
   - `allocation`: Normalized liquidity allocation.
   - `dFeesAcc`: Cumulative fees at deposit (`yFeesAcc` for xSlots, `xFeesAcc` for ySlots).
   - `timestamp`: Slot creation timestamp.

3. **UpdateType**:
   - `updateType`: Update type (0=balance, 1=fees, 2=xSlot, 3=ySlot).
   - `index`: Index (0=xFees/xLiquid, 1=yFees/yLiquid, or slot).
   - `value`: Normalized amount/allocation.
   - `addr`: Depositor address.
   - `recipient`: Recipient address for withdrawals.

4. **PreparedWithdrawal**:
   - `amountA`: Normalized token A withdrawal.
   - `amountB`: Normalized token B withdrawal.

## Internal Functions
### globalizeUpdate(address depositor, address token, bool isX, uint256 amount)
- **Behavior**: Fetches globalizer via `ICCAgent.globalizerAddress`, calls `ICCGlobalizer.globalizeLiquidity`, fetches registry via `ICCAgent.registryAddress`, calls `ITokenRegistry.initializeBalances` with `depositor` as a single-user array. Emits `GlobalizeUpdateFailed` or `UpdateRegistryFailed` on failure but does not revert, ensuring deposits succeed. Handles globalization and registry updates atomically.
- **Parameters**:
  - `depositor`: Address of the user depositing liquidity.
  - `token`: Token address (tokenA or tokenB, or zero for ETH).
  - `isX`: True if updating xSlot (tokenA), false for ySlot (tokenB).
  - `amount`: Normalized liquidity amount (1e18 precision).
- **Used in**: `ccUpdate` (for x/y slot deposits), `transactToken`, `transactNative` (for withdrawals).
- **Gas**: Two external calls (`globalizerAddress`, `globalizeLiquidity`) and two registry calls (`registryAddress`, `initializeBalances`), all with try-catch.
- **Call Tree**: Calls `ICCAgent.globalizerAddress`, `ICCGlobalizer.globalizeLiquidity`, `ICCAgent.registryAddress`, `ITokenRegistry.initializeBalances`.

### ccUpdate(address depositor, UpdateType[] memory updates)
- **Behavior**: Updates liquidity and slot details for `xLiquiditySlots` or `yLiquiditySlots`, adjusts `xLiquid`, `yLiquid`, `xFees`, `yFees`, updates `userXIndex` or `userYIndex`, calls `globalizeUpdate` for registry updates, emits `LiquidityUpdated` or `FeesUpdated`.
- **Parameters**:
  - `depositor`: Address associated with the update.
  - `updates`: Array of `UpdateType` structs specifying balance, fee, or slot updates.
- **Internal Call Flow**:
  - Iterates `updates`, handling:
    - `updateType == 0`: Updates `xLiquid` (`index == 0`) or `yLiquid` (`index == 1`).
    - `updateType == 1`: Updates `xFees` (`index == 0`) or `yFees` (`index == 1`), emits `FeesUpdated`.
    - `updateType == 2`: Updates `xLiquiditySlots`, adds/removes from `activeXLiquiditySlots`, `userXIndex`, calls `globalizeUpdate` for tokenA.
    - `updateType == 3`: Updates `yLiquiditySlots`, adds/removes from `activeYLiquiditySlots`, `userYIndex`, calls `globalizeUpdate` for tokenB.
- **Restrictions**: Router-only (`routers[msg.sender]`).
- **Gas**: Loop over `updates`, array operations, `globalizeUpdate` calls.
- **Call Tree**: Calls `globalizeUpdate` (for `ICCAgent.globalizerAddress`, `ICCGlobalizer.globalizeLiquidity`, `ICCAgent.registryAddress`, `ITokenRegistry.initializeBalances`).

## External Functions
### setRouters(address[] memory _routers)
- **Behavior**: Sets routers, stores in `routers` and `routerAddresses`, callable once.
- **Parameters**:
  - `_routers`: Array of router addresses.
- **Restrictions**: Reverts if `routersSet` or `_routers` invalid/empty.
- **Gas**: Single loop, array push.
- **Call Tree**: None.

### resetRouters()
- **Behavior**: Fetches lister via `ICCAgent.getLister(listingAddress)`, restricts to lister (`msg.sender`), fetches routers via `ICCAgent.getRouters`, clears `routers` mapping and `routerAddresses` array, updates with new routers, sets `routersSet` to true.
- **Parameters**: None.
- **Restrictions**: Reverts if `msg.sender` not lister or no routers available in agent.
- **Gas**: Two external calls (`getLister`, `getRouters`), loops for clearing and updating arrays.
- **Call Tree**: Calls `ICCAgent.getLister`, `ICCAgent.getRouters`.

### setListingId(uint256 _listingId)
- **Behavior**: Sets `listingId`, callable once.
- **Parameters**:
  - `_listingId`: Listing identifier.
- **Restrictions**: Reverts if `listingId` set.
- **Gas**: Single assignment.
- **Call Tree**: None.

### setListingAddress(address _listingAddress)
- **Behavior**: Sets `listingAddress`, callable once.
- **Parameters**:
  - `_listingAddress`: Listing contract address.
- **Restrictions**: Reverts if `listingAddress` set or `_listingAddress` invalid.
- **Gas**: Single assignment.
- **Call Tree**: None.

### setTokens(address _tokenA, address _tokenB)
- **Behavior**: Sets `tokenA` and `tokenB`, callable once.
- **Parameters**:
  - `_tokenA`: Token A address (ETH if zero).
  - `_tokenB`: Token B address (ETH if zero).
- **Restrictions**: Reverts if tokens set, identical, or both zero.
- **Gas**: Two assignments.
- **Call Tree**: None.

### setAgent(address _agent)
- **Behavior**: Sets `agent`, callable once.
- **Parameters**:
  - `_agent`: Agent contract address.
- **Restrictions**: Reverts if `agent` set or `_agent` invalid.
- **Gas**: Single assignment.
- **Call Tree**: None.

### transactToken(address depositor, address token, uint256 amount, address recipient)
- **Behavior**: Transfers ERC20 tokens via `IERC20.transfer`, checks `xLiquid`/`yLiquid`, calls `globalizeUpdate`, emits `TransactFailed` on failure.
- **Parameters**:
  - `depositor`: Address initiating the transfer (via router).
  - `token`: Token address (tokenA or tokenB).
  - `amount`: Denormalized transfer amount.
  - `recipient`: Address receiving tokens.
- **Restrictions**: Router-only, valid token, non-zero amount, sufficient `xLiquid`/`yLiquid`.
- **Gas**: Single transfer, `globalizeUpdate` call.
- **Call Tree**: Calls `IERC20.decimals`, `IERC20.transfer`, `globalizeUpdate` (for `ICCAgent.globalizerAddress`, `ICCGlobalizer.globalizeLiquidity`, `ICCAgent.registryAddress`, `ITokenRegistry.initializeBalances`).

### transactNative(address depositor, uint256 amount, address recipient)
- **Behavior**: Transfers ETH via low-level `call`, checks `xLiquid`/`yLiquid`, calls `globalizeUpdate`, emits `TransactFailed` on failure.
- **Parameters**:
  - `depositor`: Address initiating the transfer (via router).
  - `amount`: Denormalized transfer amount (ETH).
  - `recipient`: Address receiving ETH.
- **Restrictions**: Router-only, non-zero amount, sufficient `xLiquid`/`yLiquid`.
- **Gas**: Single transfer, `globalizeUpdate` call.
- **Call Tree**: Calls `globalizeUpdate` (for `ICCAgent.globalizerAddress`, `ICCGlobalizer.globalizeLiquidity`, `ICCAgent.registryAddress`, `ITokenRegistry.initializeBalances`).

### updateLiquidity(address depositor, bool isX, uint256 amount)
- **Behavior**: Reduces `xLiquid` (if `isX`) or `yLiquid`, emits `LiquidityUpdated`.
- **Parameters**:
  - `depositor`: Address initiating the update (via router).
  - `isX`: True to reduce `xLiquid`, false for `yLiquid`.
  - `amount`: Normalized amount to subtract.
- **Restrictions**: Router-only, sufficient liquidity.
- **Gas**: Single update.
- **Call Tree**: None.

## View Functions
### getListingAddress(uint256) view returns (address listingAddressReturn)
- **Behavior**: Returns `listingAddress`.

### liquidityAmounts() view returns (uint256 xAmount, uint256 yAmount)
- **Behavior**: Returns `xLiquid`, `yLiquid`.

### liquidityDetailsView(address) view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees)
- **Behavior**: Returns `liquidityDetail` fields for `CCSEntryPartial` compatibility.

### activeXLiquiditySlotsView() view returns (uint256[] memory slots)
- **Behavior**: Returns `activeXLiquiditySlots`.

### activeYLiquiditySlotsView() view returns (uint256[] memory slots)
- **Behavior**: Returns `activeYLiquiditySlots`.

### userXIndexView(address user) view returns (uint256[] memory indices)
- **Behavior**: Returns xSlot indices for `user` from `userXIndex`.

### userYIndexView(address user) view returns (uint256[] memory indices)
- **Behavior**: Returns ySlot indices for `user` from `userYIndex`.

### getActiveXLiquiditySlots() view returns (uint256[] memory slots)
- **Behavior**: Returns `activeXLiquiditySlots`.

### getActiveYLiquiditySlots() view returns (uint256[] memory slots)
- **Behavior**: Returns `activeYLiquiditySlots`.

### getXSlotView(uint256 index) view returns (Slot memory slot)
- **Behavior**: Returns xSlot details.

### getYSlotView(uint256 index) view returns (Slot memory slot)
- **Behavior**: Returns ySlot details.

### routerAddressesView() view returns (address[] memory addresses)
- **Behavior**: Returns `routerAddresses`.

## Additional Details
- **Decimal Handling**: Normalizes to 1e18 using `IERC20.decimals`, denormalizes for transfers.
- **Reentrancy Protection**: Handled by routers (`CCLiquidityRouter`).
- **Gas Optimization**: Dynamic arrays, minimal external calls, try-catch for safety.
- **Token Usage**: xSlots provide token A, claim yFees; ySlots provide token B, claim xFees.
- **Events**: `LiquidityUpdated`, `FeesUpdated`, `SlotDepositorChanged`, `GlobalizeUpdateFailed`, `UpdateRegistryFailed`, `TransactFailed`.
- **Safety**:
  - Explicit casting for interfaces.
  - No inline assembly, high-level Solidity.
  - Try-catch for external calls with detailed revert strings.
  - Public state variables accessed via auto-generated getters or unique view functions.
  - No reserved keywords, no `virtual`/`override`.
- **Router Security**: Only `routers[msg.sender]` can call restricted functions (`ccUpdate`, `transactToken`, `transactNative`, etc.).
- **Fee System**: Cumulative fees (`xFeesAcc`, `yFeesAcc`) never decrease; `dFeesAcc` tracks fees at slot updates.
- **Globalization**: In `ccUpdate`, `transactToken`, `transactNative`, calls `globalizeUpdate` for x/y slot updates or withdrawals, fetching globalizer via `ICCAgent.globalizerAddress`, calling `ICCGlobalizer.globalizeLiquidity(depositor, tokenA/tokenB)`, and registry via `ICCAgent.registryAddress`, calling `ITokenRegistry.initializeBalances`.
