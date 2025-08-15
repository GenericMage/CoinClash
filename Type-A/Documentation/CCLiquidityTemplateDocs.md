# CCLiquidityTemplate Documentation

## Overview
The `CCLiquidityTemplate`, implemented in Solidity (^0.8.2), manages liquidity pools, fees, and slot updates in a decentralized trading platform. It integrates with `ICCAgent`, `ITokenRegistry`, `ICCListing`, `IERC20`, and `ICCGlobalizer` for registry updates, token operations, and liquidity globalization. State variables are public, accessed via auto-generated getters or unique view functions, with amounts normalized to 1e18. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation with try-catch for external calls. Reentrancy protection is handled at the router level.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.1.3 (Updated 2025-08-15)

**Compatibility**:
- CCListingTemplate.sol (v0.1.4)
- CCLiquidityRouter.sol (v0.0.18)
- CCMainPartial.sol (v0.0.14)
- CCGlobalizer.sol (v0.2.0)
- ICCLiquidity.sol (v0.0.4)
- ICCListing.sol (v0.0.7)

## Interfaces
- **IERC20**: Provides `decimals()` for normalization, `transfer(address, uint256)` for token transfers.
- **ICCListing**: Provides `prices(uint256)` (returns `price`), `volumeBalances(uint256)` (returns `xBalance`, `yBalance`), `globalizerAddressView()` (returns `address`).
- **ICCAgent**: Provides `registryAddress()` (returns `address`) for fetching registry.
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
- **`userIndex`**: `mapping(address => uint256[]) private` - User slot indices (accessed via `userXIndexView`/`userYIndexView`).

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

## External Functions
### setRouters(address[] memory _routers)
- **Behavior**: Sets routers, stores in `routers` and `routerAddresses`, callable once.
- **Restrictions**: Reverts if `routersSet` or `_routers` invalid/empty.
- **Gas**: Single loop, array push.

### setListingId(uint256 _listingId)
- **Behavior**: Sets `listingId`, callable once.
- **Restrictions**: Reverts if `listingId` set.
- **Gas**: Single write.

### setListingAddress(address _listingAddress)
- **Behavior**: Sets `listingAddress`, callable once.
- **Restrictions**: Reverts if `listingAddress` set or invalid.
- **Gas**: Single write.

### setTokens(address _tokenA, address _tokenB)
- **Behavior**: Sets `tokenA`, `tokenB`, callable once.
- **Restrictions**: Reverts if tokens set, same, or both zero.
- **Gas**: State writes, `IERC20.decimals` calls.

### setAgent(address _agent)
- **Behavior**: Sets `agent`, callable once.
- **Restrictions**: Reverts if `agent` set or invalid.
- **Gas**: Single write.

### update(address depositor, UpdateType[] memory updates)
- **Behavior**: Updates `liquidityDetail`, `xLiquiditySlots`, `yLiquiditySlots`, `userIndex`, `activeXLiquiditySlots`/`activeYLiquiditySlots`, calls `ITokenRegistry.initializeBalances` for `tokenA` and `tokenB`, calls `ICCGlobalizer.globalizeLiquidity(depositor, tokenA/tokenB)` for x/y slots, emits `LiquidityUpdated`.
- **Internal**: Processes `updates` for balances, fees, or slots. Adds/removes slot indices. Fetches globalizer via `ICCListing.globalizerAddressView`. Uses try-catch, emits `GlobalizeUpdateFailed` or `UpdateRegistryFailed` on failure.
- **Restrictions**: Router-only (`routers[msg.sender]`).
- **Gas**: Loop over `updates`, array resizing, external calls.

### changeSlotDepositor(address depositor, bool isX, uint256 slotIndex, address newDepositor)
- **Behavior**: Transfers slot ownership, updates `userIndex`, calls `globalizeLiquidity` for both depositors, emits `SlotDepositorChanged`.
- **Restrictions**: Router-only, `depositor` must be slot owner, valid `newDepositor`.
- **Gas**: Slot update, array adjustments, two `globalizeLiquidity` calls.

### addFees(address depositor, bool isX, uint256 fee)
- **Behavior**: Adds fees to `xFees`/`yFees` via `update`, emits `FeesUpdated`.
- **Restrictions**: Router-only, non-zero fee.
- **Gas**: Single `update` call.

### transactToken(address depositor, address token, uint256 amount, address recipient)
- **Behavior**: Transfers ERC20 tokens via `IERC20.transfer`, emits `TransactFailed` on failure.
- **Restrictions**: Router-only, valid token, non-zero amount.
- **Gas**: Single transfer.

### transactNative(address depositor, uint256 amount, address recipient)
- **Behavior**: Transfers ETH via low-level `call`, emits `TransactFailed` on failure.
- **Restrictions**: Router-only, non-zero amount.
- **Gas**: Single transfer.

### updateLiquidity(address depositor, bool isX, uint256 amount)
- **Behavior**: Adds to `xLiquid` (if `isX`) or `yLiquid`, emits `LiquidityUpdated`.
- **Restrictions**: Router-only.
- **Gas**: Single update.

### xPrepOut(address depositor, uint256 amount, uint256 index) returns (PreparedWithdrawal memory withdrawal)
- **Behavior**: Prepares token A withdrawal, compensates with token B if shortfall, uses formula above.
- **Internal**: Checks `xLiquid`, `allocation`, uses `ICCListing.prices(0)`.
- **Restrictions**: Router-only, `depositor` must be slot owner.
- **Gas**: Single `prices` call.

### xExecuteOut(address depositor, uint256 index, PreparedWithdrawal memory withdrawal)
- **Behavior**: Executes token A withdrawal, updates slots via `update`, transfers tokens/ETH via `transactToken`/`transactNative`.
- **Restrictions**: Router-only, `depositor` must be slot owner.
- **Gas**: Two transfers, `update` call.

### yPrepOut(address depositor, uint256 amount, uint256 index) returns (PreparedWithdrawal memory withdrawal)
- **Behavior**: Prepares token B withdrawal, compensates with token A if shortfall, uses formula above.
- **Internal**: Checks `yLiquid`, `allocation`, uses `ICCListing.prices(0)`.
- **Restrictions**: Router-only, `depositor` must be slot owner.
- **Gas**: Single `prices` call.

### yExecuteOut(address depositor, uint256 index, PreparedWithdrawal memory withdrawal)
- **Behavior**: Executes token B withdrawal, updates slots via `update`, transfers tokens/ETH via `transactToken`/`transactNative`.
- **Restrictions**: Router-only, `depositor` must be slot owner.
- **Gas**: Two transfers, `update` call.

## View Functions
### liquidityAmounts() view returns (uint256 xAmount, uint256 yAmount)
- **Behavior**: Returns `xLiquid`, `yLiquid`.

### liquidityDetailsView() view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, uint256 xFeesAcc, uint256 yFeesAcc)
- **Behavior**: Returns `liquidityDetail` fields.

### getActiveXLiquiditySlots(uint256 maxIterations) view returns (uint256[] memory slots)
- **Behavior**: Returns up to `maxIterations` of `activeXLiquiditySlots`.

### getActiveYLiquiditySlots(uint256 maxIterations) view returns (uint256[] memory slots)
- **Behavior**: Returns up to `maxIterations` of `activeYLiquiditySlots`.

### userXIndexView(address user) view returns (uint256[] memory indices)
- **Behavior**: Returns xSlot indices for `user`.

### userYIndexView(address user) view returns (uint256[] memory indices)
- **Behavior**: Returns ySlot indices for `user`.

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
  - `userIndex` private, accessed via `userXIndexView`/`userYIndexView`.
- **Router Security**: Only `routers[msg.sender]` can call restricted functions.
- **Fee System**: Cumulative fees (`xFeesAcc`, `yFeesAcc`) never decrease; `dFeesAcc` tracks fees at slot updates.
- **Globalization**: In `update`, fetches globalizer via `ICCListing.globalizerAddressView`, calls `ICCGlobalizer.globalizeLiquidity(depositor, tokenA/tokenB)` for x/y slots.
