# CCLiquidityTemplate Documentation

## Overview
The `CCLiquidityTemplate`, implemented in Solidity (^0.8.2), manages liquidity pools, fees, and slot updates in a decentralized trading platform. It integrates with `ICCAgent`, `ITokenRegistry`, `ICCListing`, and `IERC20` for global updates and token operations. State variables are public, accessed via unique view functions, with amounts normalized to 1e18. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation with try-catch for external calls. Reentrancy protection is handled at the router level.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.0.20 (Updated 2025-08-01)

**Compatibility**:
- CCListingTemplate.sol (v0.0.10)
- CCLiquidityRouter.sol (v0.0.25)
- CCMainPartial.sol (v0.0.10)
- ICCLiquidity.sol (v0.0.4)
- ICCListing.sol (v0.0.7)

### State Variables
- **`routersSet`**: `bool public` - Tracks if routers are set.
- **`listingAddress`**: `address public` - Listing contract address.
- **`tokenA`**: `address public` - Token A address (or ETH if zero).
- **`tokenB`**: `address public` - Token B address (or ETH if zero).
- **`listingId`**: `uint256 public` - Listing identifier.
- **`agent`**: `address public` - Agent contract address.
- **`liquidityDetail`**: `LiquidityDetails public` - Stores `xLiquid`, `yLiquid`, `xFees`, `yFees`, `xFeesAcc`, `yFeesAcc`.
- **`activeXLiquiditySlots`**: `uint256[] public` - Active xSlot indices.
- **`activeYLiquiditySlots`**: `uint256[] public` - Active ySlot indices.
- **`routerAddresses`**: `address[] public` - Registered router addresses.

### Mappings
- **`routers`**: `mapping(address => bool)` - Authorized routers.
- **`xLiquiditySlots`**: `mapping(uint256 => Slot)` - Token A slot data.
- **`yLiquiditySlots`**: `mapping(uint256 => Slot)` - Token B slot data.
- **`userIndex`**: `mapping(address => uint256[])` - User slot indices.

### Structs
1. **LiquidityDetails**:
   - `xLiquid`: Normalized token A liquidity.
   - `yLiquid`: Normalized token B liquidity.
   - `xFees`: Normalized token A fees.
   - `yFees`: Normalized token B fees.
   - `xFeesAcc`: Cumulative token A fee volume.
   - `yFeesAcc`: Cumulative token B fee volume.

2. **Slot**:
   - `depositor`: Slot owner.
   - `recipient`: Unused (reserved).
   - `allocation`: Normalized liquidity allocation.
   - `dFeesAcc`: Cumulative fees at deposit/claim (`yFeesAcc` for xSlots, `xFeesAcc` for ySlots).
   - `timestamp`: Slot creation timestamp.

3. **UpdateType**:
   - `updateType`: Update type (0=balance, 1=fees, 2=xSlot, 3=ySlot).
   - `index`: Index (0=xFees/xLiquid, 1=yFees/yLiquid, or slot).
   - `value`: Normalized amount/allocation.
   - `addr`: Depositor.
   - `recipient`: Unused (reserved).

4. **PreparedWithdrawal**:
   - `amountA`: Normalized token A withdrawal.
   - `amountB`: Normalized token B withdrawal.

### Formulas
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

### External Functions
#### setRouters(address[] memory _routers)
- **Behavior**: Sets routers, stores in `routers` and `routerAddresses`, callable once.
- **Restrictions**: Reverts if `routersSet` or `_routers` invalid/empty.
- **Gas**: Single loop, array push.

#### setListingId(uint256 _listingId)
- **Behavior**: Sets `listingId`, callable once.
- **Restrictions**: Reverts if `listingId` set.
- **Gas**: Single write.

#### setListingAddress(address _listingAddress)
- **Behavior**: Sets `listingAddress`, callable once.
- **Restrictions**: Reverts if `listingAddress` set or invalid.
- **Gas**: Single write.

#### setTokens(address _tokenA, address _tokenB)
- **Behavior**: Sets `tokenA`, `tokenB`, callable once.
- **Restrictions**: Reverts if tokens set, same, both zero, or invalid decimals.
- **Gas**: State writes, `IERC20.decimals` calls.

#### setAgent(address _agent)
- **Behavior**: Sets `agent`, callable once.
- **Restrictions**: Reverts if `agent` set or invalid.
- **Gas**: Single write.

#### update(address depositor, UpdateType[] memory updates)
- **Behavior**: Updates `liquidityDetail`, `xLiquiditySlots`, `yLiquiditySlots`, `userIndex`, calls `updateRegistry`, emits `LiquidityUpdated`.
- **Internal**: Processes `updates` for balances, fees, or slots, updates `activeXLiquiditySlots`/`activeYLiquiditySlots`.
- **Restrictions**: Router-only (`routers[msg.sender]`).
- **Gas**: Loop over `updates`, array resizing, `updateRegistry` call.

#### updateRegistry(address depositor, bool isX)
- **Behavior**: Updates `ITokenRegistry` for token balances, emits `UpdateRegistryFailed` on failure.
- **Internal**: Fetches `registryAddress` from `ICCAgent` (1,000,000 gas), calls `initializeBalances` (1,000,000 gas).
- **Restrictions**: Router-only.
- **Gas**: Two external calls with try-catch.

#### changeSlotDepositor(address depositor, bool isX, uint256 slotIndex, address newDepositor)
- **Behavior**: Transfers slot ownership, updates `userIndex`, emits `SlotDepositorChanged`.
- **Restrictions**: Router-only, `depositor` must be slot owner.
- **Gas**: Slot update, array adjustments.

#### addFees(address depositor, bool isX, uint256 fee)
- **Behavior**: Adds fees to `xFees`/`yFees`, increments `xFeesAcc`/`yFeesAcc`, emits `FeesUpdated`.
- **Internal**: Creates `UpdateType`, calls `update`.
- **Restrictions**: Router-only.
- **Gas**: Single `update` call.

#### transactToken(address depositor, address token, uint256 amount, address recipient)
- **Behavior**: Transfers ERC20 tokens, updates `xLiquid`/`yLiquid`, calls `globalizeUpdate`, emits `TransactFailed` or `LiquidityUpdated`.
- **Internal**: Normalizes amount, checks liquidity, uses `IERC20.transfer`.
- **Restrictions**: Router-only, valid token.
- **Gas**: Single transfer, `globalizeUpdate` call.

#### transactNative(address depositor, uint256 amount, address recipient)
- **Behavior**: Transfers ETH, updates `xLiquid`/`yLiquid`, calls `globalizeUpdate`, emits `TransactFailed` or `LiquidityUpdated`.
- **Internal**: Normalizes amount, checks liquidity, uses low-level `call`.
- **Restrictions**: Router-only, one token must be ETH.
- **Gas**: Single transfer, `globalizeUpdate` call.

#### globalizeUpdate(address depositor, bool isX, uint256 amount, bool isDeposit)
- **Behavior**: Updates `ICCAgent` with liquidity changes, emits `GlobalizeUpdateFailed` on failure.
- **Internal**: Normalizes amount, calls `ICCAgent.globalizeLiquidity` (1,000,000 gas).
- **Restrictions**: Router-only.
- **Gas**: Single external call with try-catch.

#### updateLiquidity(address depositor, bool isX, uint256 amount)
- **Behavior**: Deducts liquidity from `xLiquid` or `yLiquid`, emits `LiquidityUpdated`.
- **Restrictions**: Router-only.
- **Gas**: Single update.

#### xPrepOut(address depositor, uint256 amount, uint256 index) returns (PreparedWithdrawal memory)
- **Behavior**: Prepares token A withdrawal, compensates with token B if shortfall, uses formula above.
- **Internal**: Checks `xLiquid`, `allocation`, uses `ICCListing.prices(0)`.
- **Restrictions**: Router-only, `depositor` must be slot owner.
- **Gas**: Single `prices` call.

#### xExecuteOut(address depositor, uint256 index, PreparedWithdrawal memory withdrawal)
- **Behavior**: Executes token A withdrawal, updates slots, transfers tokens/ETH via `transactToken`/`transactNative`.
- **Restrictions**: Router-only, `depositor` must be slot owner.
- **Gas**: Two transfers, `update` call.

#### yPrepOut(address depositor, uint256 amount, uint256 index) returns (PreparedWithdrawal memory)
- **Behavior**: Prepares token B withdrawal, compensates with token A if shortfall, uses formula above.
- **Internal**: Checks `yLiquid`, `allocation`, uses `ICCListing.prices(0)`.
- **Restrictions**: Router-only, `depositor` must be slot owner.
- **Gas**: Single `prices` call.

#### yExecuteOut(address depositor, uint256 index, PreparedWithdrawal memory withdrawal)
- **Behavior**: Executes token B withdrawal, updates slots, transfers tokens/ETH via `transactToken`/`transactNative`.
- **Restrictions**: Router-only, `depositor` must be slot owner.
- **Gas**: Two transfers, `update` call.

#### getListingAddress(uint256) view returns (address)
- **Behavior**: Returns `listingAddress`.

#### liquidityAmounts() view returns (uint256 xAmount, uint256 yAmount)
- **Behavior**: Returns `xLiquid`, `yLiquid`.

#### liquidityDetailsView() view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, uint256 xFeesAcc, uint256 yFeesAcc)
- **Behavior**: Returns `liquidityDetail` fields.

#### activeXLiquiditySlotsView() view returns (uint256[] memory)
- **Behavior**: Returns `activeXLiquiditySlots`.

#### activeYLiquiditySlotsView() view returns (uint256[] memory)
- **Behavior**: Returns `activeYLiquiditySlots`.

#### userIndexView(address user) view returns (uint256[] memory)
- **Behavior**: Returns `userIndex[user]`.

#### getXSlotView(uint256 index) view returns (Slot memory)
- **Behavior**: Returns `xLiquiditySlots[index]`.

#### getYSlotView(uint256 index) view returns (Slot memory)
- **Behavior**: Returns `yLiquiditySlots[index]`.

#### routerAddressesView() view returns (address[] memory)
- **Behavior**: Returns `routerAddresses`.

### Additional Details
- **Decimal Handling**: Normalizes to 1e18 using `IERC20.decimals`, denormalizes for transfers.
- **Reentrancy Protection**: Handled by routers (`CCLiquidityRouter`).
- **Gas Optimization**: Dynamic arrays, minimal external calls, explicit gas limits (1,000,000 in `globalizeUpdate`, `updateRegistry`).
- **Token Usage**: xSlots provide token A, claim yFees; ySlots provide token B, claim xFees.
- **Events**: `LiquidityUpdated`, `FeesUpdated`, `SlotDepositorChanged`, `GlobalizeUpdateFailed`, `UpdateRegistryFailed`, `TransactFailed`.
- **Safety**:
  - Explicit casting for `ICCListing`, `IERC20`, `ITokenRegistry`, `ICCAgent`.
  - No inline assembly, high-level Solidity.
  - Try-catch for external calls with detailed revert strings.
  - Public state variables accessed via unique view functions.
  - No reserved keywords, no unnecessary `virtual`/`override`.
- **Router Security**: Only `routers[msg.sender]` can call restricted functions.
- **Fee System**: Cumulative fees (`xFeesAcc`, `yFeesAcc`) never decrease; `dFeesAcc` tracks fees at slot updates.
- **Changes from v0.0.19**:
  - v0.0.20: Moved `depositToken`, `depositNative`, `withdraw` (`xPrepOut`, `yPrepOut`, `xExecuteOut`, `yExecuteOut`), `claimFees`, `changeDepositor` to `CCLiquidityRouter.sol` v0.0.25 via `CCLiquidityPartial.sol` v0.0.17. Moved `globalizeUpdate` to `transactToken`/`transactNative`, `updateRegistry` to `update`.
