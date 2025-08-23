# CCLiquidityTemplate Documentation

## Overview
The `CCLiquidityTemplate`, implemented in Solidity (^0.8.2), manages liquidity pools, fees, and slot updates in a decentralized trading platform. It integrates with `ICCAgent`, `ITokenRegistry`, `ICCListing`, `IERC20`, and `ICCGlobalizer` for registry updates, token operations, and liquidity globalization. State variables are public, accessed via auto-generated getters or unique view functions, with amounts normalized to 1e18. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation with try-catch for external calls. Reentrancy protection is handled at the router level.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.1.3 (Updated 2025-08-23)

**Changes**:
- v0.1.3: Removed duplicate subtraction in `transactToken` and `transactNative`, as `xExecuteOut`/`yExecuteOut` handle subtraction via `update`. Updated balance checks to use `xLiquid`/`yLiquid` instead of total contract balance, ensuring fees are excluded. Maintained compatibility with `CCGlobalizer.sol` v0.2.1, `CCSEntryPartial.sol` v0.0.18.
- v0.1.2: Integrated `update` calls with `updateType == 0` for subtraction. No new `updateType` added. Maintained fee segregation and compatibility with `CCGlobalizer.sol` v0.2.1, `CCSEntryPartial.sol` v0.0.18.
- v0.1.1: Added `globalizeUpdate` internal function to encapsulate globalization calls, extracted from `transactToken` and `transactNative`. Integrated into `update` for deposits via liquidity router. Removed `globalizerAddress` state variable, updated `transactToken` and `transactNative` to fetch globalizer address from `ICCAgent.globalizerAddress`. Ensured `depositToken` globalization via `update`.
- v0.1.0: Added `globalizerAddress`, updated `transactToken` and `transactNative` to fetch globalizer and call `ICCGlobalizer.globalizeLiquidity`. Added `userXIndexView`, `userYIndexView`, `getActiveXLiquiditySlots`, `getActiveYLiquiditySlots`. Updated compatibility with `CCSEntryPartial.sol` (v0.0.18).
- v0.0.20: Initial documentation for `CCLiquidityTemplate.sol` (v0.0.20).

**Compatibility**:
- CCListingTemplate.sol (v0.0.10)
- CCLiquidityRouter.sol (v0.0.25)
- CCMainPartial.sol (v0.0.10)
- CCGlobalizer.sol (v0.2.1)
- ICCLiquidity.sol (v0.0.4)
- ICCListing.sol (v0.0.7)
- CCSEntryPartial.sol (v0.0.18)

## Interfaces
- **IERC20**: Provides `decimals()` for normalization, `transfer(address, uint256)` for token transfers.
- **ICCListing**: Provides `prices(uint256)` (returns `price`), `volumeBalances(uint256)` (returns `xBalance`, `yBalance`).
- **ICCAgent**: Provides `registryAddress()` (returns `address`), `globalizerAddress()` (returns `address`).
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

## Formulas
1. **Deficit and Compensation**:
   - **xPrepOut**:
     ```
     withdrawAmountA = min(amount, xLiquid)
     deficit = amount > withdrawAmountA ? amount - withdrawAmountA : 0
     withdrawAmountB = deficit > 0 ? min((deficit * 1e18) / prices(0), yLiquid) : 0
     ```
   - **yPrepOut**:
     ```
     withdrawAmountB = min(amount, yLiquid)
     deficit = amount > withdrawAmountB ? amount - withdrawAmountB : 0
     withdrawAmountA = deficit > 0 ? min((deficit * prices(0)) / 1e18, xLiquid) : 0
     ```
   - **Description**: Calculates withdrawal amounts, compensating shortfalls using `ICCListing.prices(0)` (price of token B in token A, 1e18 precision), capped by available liquidity.
   - **Used in**: `xPrepOut`, `yPrepOut`.

## Internal Functions
### globalizeUpdate(address depositor, address token, bool isX, uint256 amount)
- **Behavior**: Fetches globalizer via `ICCAgent.globalizerAddress`, calls `ICCGlobalizer.globalizeLiquidity`, emits `GlobalizeUpdateFailed` on failure.
- **Used in**: `update`, `transactToken`, `transactNative` for slot updates and withdrawals.
- **Gas**: Two external calls with try-catch.

## External Functions
### setRouters(address[] memory _routers)
- **Behavior**: Sets routers, stores in `routers` and `routerAddresses`, callable once.
- **Restrictions**: Reverts if `routersSet` or `_routers` invalid/empty.
- **Gas**: Single loop, array push.
- **Call Tree**: None.

### setListingId(uint256 _listingId)
- **Behavior**: Sets `listingId`, callable once.
- **Restrictions**: Reverts if `listingId` set.
- **Gas**: Single write.
- **Call Tree**: None.

### setListingAddress(address _listingAddress)
- **Behavior**: Sets `listingAddress`, callable once.
- **Restrictions**: Reverts if `listingAddress` set or invalid.
- **Gas**: Single write.
- **Call Tree**: None.

### setTokens(address _tokenA, address _tokenB)
- **Behavior**: Sets `tokenA`, `tokenB`, callable once.
- **Restrictions**: Reverts if tokens set, same, or both zero.
- **Gas**: State writes, `IERC20.decimals` calls.
- **Call Tree**: Calls `IERC20.decimals` for normalization.

### setAgent(address _agent)
- **Behavior**: Sets `agent`, callable once.
- **Restrictions**: Reverts if `agent` set or invalid.
- **Gas**: Single write.
- **Call Tree**: None.

### update(address depositor, UpdateType[] memory updates)
- **Behavior**: Updates `liquidityDetail`, `xLiquiditySlots`, `yLiquiditySlots`, `userXIndex`, `userYIndex`, `activeXLiquiditySlots`/`activeYLiquiditySlots`, calls `ITokenRegistry.initializeBalances` and `globalizeUpdate` for `tokenA` or `tokenB`, emits `LiquidityUpdated`.
- **Internal**: Processes `updates` for balances, fees, or slots. Adds/removes slot indices. Fetches registry via `ICCAgent.registryAddress`. Uses try-catch, emits `UpdateRegistryFailed` on failure.
- **Restrictions**: Router-only (`routers[msg.sender]`).
- **Gas**: Loop over `updates`, array resizing, external calls.
- **Call Tree**: Calls `globalizeUpdate` (for `ICCAgent.globalizerAddress`, `ICCGlobalizer.globalizeLiquidity`), `ICCAgent.registryAddress`, `ITokenRegistry.initializeBalances`.

### changeSlotDepositor(address depositor, bool isX, uint256 slotIndex, address newDepositor)
- **Behavior**: Transfers slot ownership, updates `userXIndex` or `userYIndex`, emits `SlotDepositorChanged`.
- **Restrictions**: Router-only, `depositor` must be slot owner, valid `newDepositor`.
- **Gas**: Slot update, array adjustments.
- **Call Tree**: None.

### transactToken(address depositor, address token, uint256 amount, address recipient)
- **Behavior**: Transfers ERC20 tokens via `IERC20.transfer`, checks `xLiquid`/`yLiquid`, calls `globalizeUpdate`, emits `TransactFailed` on failure.
- **Restrictions**: Router-only, valid token, non-zero amount, sufficient `xLiquid`/`yLiquid`.
- **Gas**: Single transfer, `globalizeUpdate` call.
- **Call Tree**: Calls `IERC20.decimals`, `IERC20.transfer`, `globalizeUpdate` (for `ICCAgent.globalizerAddress`, `ICCGlobalizer.globalizeLiquidity`).

### transactNative(address depositor, uint256 amount, address recipient)
- **Behavior**: Transfers ETH via low-level `call`, checks `xLiquid`/`yLiquid`, calls `globalizeUpdate`, emits `TransactFailed` on failure.
- **Restrictions**: Router-only, non-zero amount, sufficient `xLiquid`/`yLiquid`.
- **Gas**: Single transfer, `globalizeUpdate` call.
- **Call Tree**: Calls `globalizeUpdate` (for `ICCAgent.globalizerAddress`, `ICCGlobalizer.globalizeLiquidity`).

### updateLiquidity(address depositor, bool isX, uint256 amount)
- **Behavior**: Reduces `xLiquid` (if `isX`) or `yLiquid`, emits `LiquidityUpdated`.
- **Restrictions**: Router-only, sufficient liquidity.
- **Gas**: Single update.
- **Call Tree**: None.

### xPrepOut(address depositor, uint256 amount, uint256 index) returns (PreparedWithdrawal memory withdrawal)
- **Behavior**: Prepares token A withdrawal, compensates with token B if shortfall, uses formula above.
- **Internal**: Checks `xLiquid`, `allocation`, uses `ICCListing.prices(0)`.
- **Restrictions**: Router-only, `depositor` must be slot owner.
- **Gas**: Single `prices` call.
- **Call Tree**: Calls `ICCListing.prices`.

### xExecuteOut(address depositor, uint256 index, PreparedWithdrawal memory withdrawal)
- **Behavior**: Executes token A withdrawal, updates slots via `update`, transfers tokens/ETH via `transactToken`/`transactNative`.
- **Restrictions**: Router-only, `depositor` must be slot owner.
- **Gas**: Two transfers, `update` call.
- **Call Tree**: Calls `this.update`, `this.transactToken`/`this.transactNative` (which call `IERC20.decimals`, `IERC20.transfer`, `globalizeUpdate`).

### yPrepOut(address depositor, uint256 amount, uint256 index) returns (PreparedWithdrawal memory withdrawal)
- **Behavior**: Prepares token B withdrawal, compensates with token A if shortfall, uses formula above.
- **Internal**: Checks `yLiquid`, `allocation`, uses `ICCListing.prices(0)`.
- **Restrictions**: Router-only, `depositor` must be slot owner.
- **Gas**: Single `prices` call.
- **Call Tree**: Calls `ICCListing.prices`.

### yExecuteOut(address depositor, uint256 index, PreparedWithdrawal memory withdrawal)
- **Behavior**: Executes token B withdrawal, updates slots via `update`, transfers tokens/ETH via `transactToken`/`transactNative`.
- **Restrictions**: Router-only, `depositor` must be slot owner.
- **Gas**: Two transfers, `update` call.
- **Call Tree**: Calls `this.update`, `this.transactToken`/`this.transactNative` (which call `IERC20.decimals`, `IERC20.transfer`, `globalizeUpdate`).

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
- **Router Security**: Only `routers[msg.sender]` can call restricted functions.
- **Fee System**: Cumulative fees (`xFeesAcc`, `yFeesAcc`) never decrease; `dFeesAcc` tracks fees at slot updates.
- **Globalization**: In `update`, `transactToken`, `transactNative`, calls `globalizeUpdate` for x/y slot updates or withdrawals, fetching globalizer via `ICCAgent.globalizerAddress`, calling `ICCGlobalizer.globalizeLiquidity(depositor, tokenA/tokenB)`.
