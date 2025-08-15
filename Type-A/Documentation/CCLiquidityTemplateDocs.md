# CCLiquidityTemplate Documentation

## Overview
The `CCLiquidityTemplate`, implemented in Solidity (^0.8.2), manages liquidity pools, fees, and slot updates in a decentralized trading platform. It integrates with `ICCAgent`, `ITokenRegistry`, `ICCListing`, `IERC20`, and `ICCGlobalizer` for registry updates, token operations, and liquidity globalization. State variables are public, accessed via auto-generated getters or unique view functions, with amounts normalized to 1e18. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation with try-catch for external calls. Reentrancy protection is handled at the router level.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.1.4 (Updated 2025-08-15)

**Changes**:
- v0.1.0: Added `globalizerAddress` state variable, updated `transactToken` and `transactNative` to fetch globalizer address from `ICCAgent.globalizerAddress` and call `ICCGlobalizer.globalizeLiquidity`. Added `userXIndexView`, `userYIndexView`, `getActiveXLiquiditySlots`, `getActiveYLiquiditySlots` view functions. Updated compatibility to include `CCSEntryPartial.sol` (v0.0.18).
- v0.0.20: Initial documentation for `CCLiquidityTemplate.sol` (v0.0.20), covering state, mappings, structs, formulas, and functions.

**Compatibility**:
- CCListingTemplate.sol (v0.0.10)
- CCLiquidityRouter.sol (v0.0.18)
- CCMainPartial.sol (v0.0.10)
- CCGlobalizer.sol (v0.2.1)
- ICCLiquidity.sol (v0.0.4)
- ICCListing.sol (v0.0.7)
- CCSEntryPartial.sol (v0.0.18)

## Interfaces
- **IERC20**: Provides `decimals()` for normalization, `transfer(address, uint256)` for token transfers.
- **ICCListing**: Provides `prices(uint256)` (returns `price`), `volumeBalances(uint256)` (returns `xBalance`, `yBalance`).
- **ICCAgent**: Provides `registryAddress()` (returns `address`), `globalizerAddress()` (returns `address`) for fetching registry and globalizer.
- **ITokenRegistry**: Provides `initializeBalances(address token, address[] memory users)` for balance updates.
- **ICCGlobalizer**: Provides `globalizeLiquidity(address depositor, address token)` for liquidity tracking.

## State Variables
- **`routersSet`**: `bool public` - Tracks if routers are set.
- **`listingAddress`**: `address public` - Listing contract address.
- **`tokenA`**: `address public` - Token A address (ETH if zero).
- **`tokenB`**: `address public` - Token B address (ETH if zero).
- **`listingId`**: `uint256 public` - Listing identifier.
- **`agent`**: `address public` - Agent contract address.
- **`globalizerAddress`**: `address public` - Globalizer contract address, fetched from `ICCAgent`.
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
- **Behavior**: Updates `liquidityDetail`, `xLiquiditySlots`, `yLiquiditySlots`, `userXIndex`, `userYIndex`, `activeXLiquiditySlots`/`activeYLiquiditySlots`, calls `ITokenRegistry.initializeBalances` for `tokenA` or `tokenB`, emits `LiquidityUpdated`.
- **Internal**: Processes `updates` for balances, fees, or slots. Adds/removes slot indices. Fetches registry via `ICCAgent.registryAddress`. Uses try-catch, emits `UpdateRegistryFailed` on failure.
- **Restrictions**: Router-only (`routers[msg.sender]`).
- **Gas**: Loop over `updates`, array resizing, external calls.

### changeSlotDepositor(address depositor, bool isX, uint256 slotIndex, address newDepositor)
- **Behavior**: Transfers slot ownership, updates `userXIndex` or `userYIndex`, emits `SlotDepositorChanged`.
- **Restrictions**: Router-only, `depositor` must be slot owner, valid `newDepositor`.
- **Gas**: Slot update, array adjustments.

### addFees(address depositor, bool isX, uint256 fee)
- **Behavior**: Adds fees to `xFees`/`yFees` via `update`, emits `FeesUpdated`.
- **Restrictions**: Router-only, non-zero fee.
- **Gas**: Single `update` call.

### transactToken(address depositor, address token, uint256 amount, address recipient)
- **Behavior**: Transfers ERC20 tokens via `IERC20.transfer`, updates `xLiquid`/`yLiquid`, fetches globalizer via `ICCAgent.globalizerAddress`, calls `ICCGlobalizer.globalizeLiquidity`, emits `TransactFailed` or `GlobalizeUpdateFailed` on failure.
- **Restrictions**: Router-only, valid token, non-zero amount.
- **Gas**: Single transfer, external calls.

### transactNative(address depositor, uint256 amount, address recipient)
- **Behavior**: Transfers ETH via low-level `call`, updates `xLiquid`/`yLiquid`, fetches globalizer via `ICCAgent.globalizerAddress`, calls `ICCGlobalizer.globalizeLiquidity`, emits `TransactFailed` or `GlobalizeUpdateFailed` on failure.
- **Restrictions**: Router-only, non-zero amount.
- **Gas**: Single transfer, external calls.

### updateLiquidity(address depositor, bool isX, uint256 amount)
- **Behavior**: Reduces `xLiquid` (if `isX`) or `yLiquid`, emits `LiquidityUpdated`.
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
- **Globalization**: In `transactToken` and `transactNative`, fetches globalizer via `ICCAgent.globalizerAddress`, calls `ICCGlobalizer.globalizeLiquidity(depositor, tokenA/tokenB)` for x/y slots.
</xaiArtifact>

### Task 2: Do 128 bits (Generate Interface File)
<xaiArtifact artifact_id="f2d93b7f-131c-4d06-8776-b8f0ae9d6f23" artifact_version_id="28e1aeb6-73ad-4220-b9e1-4a7f1d7ad4ab" title="ICCLiquidityTemplate.sol" contentType="text/solidity">
/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Version: 0.0.1
 Changes:
 - v0.0.1: Initial interface for CCLiquidityTemplate.sol v0.0.22, capturing state variables, mappings, structs, and functions with brief comments.
*/

pragma solidity ^0.8.2;

interface ICCLiquidityTemplate {
    // State variable: Tracks if routers are set
    function routersSet() external view returns (bool);

    // State variable: Listing contract address
    function listingAddress() external view returns (address);

    // State variable: Token A address (ETH if zero)
    function tokenA() external view returns (address);

    // State variable: Token B address (ETH if zero)
    function tokenB() external view returns (address);

    // State variable: Listing identifier
    function listingId() external view returns (uint256);

    // State variable: Agent contract address
    function agent() external view returns (address);

    // State variable: Globalizer contract address
    function globalizerAddress() external view returns (address);

    // Struct: Stores liquidity and fee details
    struct LiquidityDetails {
        uint256 xLiquid; // Normalized token A liquidity
        uint256 yLiquid; // Normalized token B liquidity
        uint256 xFees; // Normalized token A fees
        uint256 yFees; // Normalized token B fees
        uint256 xFeesAcc; // Cumulative token A fee volume
        uint256 yFeesAcc; // Cumulative token B fee volume
    }

    // Struct: Represents a liquidity slot
    struct Slot {
        address depositor; // Slot owner
        address recipient; // Address receiving withdrawals
        uint256 allocation; // Normalized liquidity allocation
        uint256 dFeesAcc; // Cumulative fees at deposit
        uint256 timestamp; // Slot creation timestamp
    }

    // Struct: Defines update parameters
    struct UpdateType {
        uint8 updateType; // 0=balance, 1=fees, 2=xSlot, 3=ySlot
        uint256 index; // Index for fees, liquidity, or slot
        uint256 value; // Normalized amount/allocation
        address addr; // Depositor address
        address recipient; // Recipient address for withdrawals
    }

    // Struct: Defines withdrawal amounts
    struct PreparedWithdrawal {
        uint256 amountA; // Normalized token A withdrawal
        uint256 amountB; // Normalized token B withdrawal
    }

    // State variable: Liquidity details
    function liquidityDetail() external view returns (LiquidityDetails memory);

    // Mapping: Authorized routers
    function routers(address router) external view returns (bool);

    // Mapping: Token A slot data
    function xLiquiditySlots(uint256 index) external view returns (Slot memory);

    // Mapping: Token B slot data
    function yLiquiditySlots(uint256 index) external view returns (Slot memory);

    // Mapping: User xSlot indices
    function userXIndex(address user) external view returns (uint256[] memory);

    // Mapping: User ySlot indices
    function userYIndex(address user) external view returns (uint256[] memory);

    // State variable: Active xSlot indices
    function activeXLiquiditySlots() external view returns (uint256[] memory);

    // State variable: Active ySlot indices
    function activeYLiquiditySlots() external view returns (uint256[] memory);

    // State variable: Authorized router addresses
    function routerAddresses() external view returns (address[] memory);

    // Sets router addresses, callable once
    function setRouters(address[] memory _routers) external;

    // Sets listing ID, callable once
    function setListingId(uint256 _listingId) external;

    // Sets listing address, callable once
    function setListingAddress(address _listingAddress) external;

    // Sets token pair, callable once
    function setTokens(address _tokenA, address _tokenB) external;

    // Sets agent address, callable once
    function setAgent(address _agent) external;

    // Updates liquidity and slot details
    function update(address depositor, UpdateType[] memory updates) external;

    // Transfers slot ownership
    function changeSlotDepositor(address depositor, bool isX, uint256 slotIndex, address newDepositor) external;

    // Adds fees to liquidity details
    function addFees(address depositor, bool isX, uint256 fee) external;

    // Transfers ERC20 tokens and updates liquidity
    function transactToken(address depositor, address token, uint256 amount, address recipient) external;

    // Transfers native ETH and updates liquidity
    function transactNative(address depositor, uint256 amount, address recipient) external;

    // Updates liquidity balance
    function updateLiquidity(address depositor, bool isX, uint256 amount) external;

    // Prepares token A withdrawal
    function xPrepOut(address depositor, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);

    // Executes token A withdrawal
    function xExecuteOut(address depositor, uint256 index, PreparedWithdrawal memory withdrawal) external;

    // Prepares token B withdrawal
    function yPrepOut(address depositor, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);

    // Executes token B withdrawal
    function yExecuteOut(address depositor, uint256 index, PreparedWithdrawal memory withdrawal) external;

    // Returns listing address
    function getListingAddress(uint256) external view returns (address);

    // Returns liquidity amounts
    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount);

    // Returns liquidity details for CCSEntryPartial compatibility
    function liquidityDetailsView(address) external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees);

    // Returns active xLiquidity slots
    function activeXLiquiditySlotsView() external view returns (uint256[] memory);

    // Returns active yLiquidity slots
    function activeYLiquiditySlotsView() external view returns (uint256[] memory);

    // Returns user's xLiquidity slot indices
    function userXIndexView(address user) external view returns (uint256[] memory);

    // Returns user's yLiquidity slot indices
    function userYIndexView(address user) external view returns (uint256[] memory);

    // Returns active xLiquidity slots
    function getActiveXLiquiditySlots() external view returns (uint256[] memory);

    // Returns active yLiquidity slots
    function getActiveYLiquiditySlots() external view returns (uint256[] memory);

    // Returns xLiquidity slot details
    function getXSlotView(uint256 index) external view returns (Slot memory);

    // Returns yLiquidity slot details
    function getYSlotView(uint256 index) external view returns (Slot memory);

    // Returns router addresses
    function routerAddressesView() external view returns (address[] memory);
}