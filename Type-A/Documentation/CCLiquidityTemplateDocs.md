# CCLiquidityTemplate Documentation

## Overview
The `CCLiquidityTemplate`, implemented in Solidity (^0.8.2), manages liquidity pools, fees, slot updates, and payout functionality in a decentralized trading platform. It integrates with `ICCAgent`, `ITokenRegistry`, `ICCListing`, `IERC20`, and `ICCGlobalizer` for registry updates, token operations, and liquidity globalization. State variables are public, accessed via getters or view functions, with amounts normalized to 1e18. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation with try-catch for external calls. Reentrancy protection is handled at the router level.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.1.15 (Updated 2025-09-02)

**Changes**:
- v0.1.15: Removed unnecessary checks in `ccUpdate`.
- v0.1.14: Modified `ccUpdate` to skip allocation check for new slots (`slot.depositor == address(0)`) for `updateType` 2 and 3, allowing deposits to initialize slots with zero allocation.
- v0.1.13: Updated `ccUpdate` for `updateType` 2 and 3 to adjust `xLiquid`/`yLiquid` by allocation difference, preventing liquidity inflation during withdrawals. Added validation for `slot.allocation >= u.value`.
- v0.1.12: Added `updateType` 4 (xSlot depositor change) and 5 (ySlot depositor change) to `ccUpdate` to update only depositor address without modifying `xLiquid`/`yLiquid`.
- v0.1.11: Hid `routerAddresses` as `routerAddressesView` is preferred.
- v0.1.10: Removed `updateLiquidity` as `ccUpdate` is sufficient.
- v0.1.9: Removed redundant `globalizeUpdate` call from `ssUpdate`.
- v0.1.8: Added payout functionality (`ssUpdate`, `PayoutUpdate`, `LongPayoutStruct`, `ShortPayoutStruct`, `longPayout`, `shortPayout`, `longPayoutByIndex`, `shortPayoutByIndex`, `userPayoutIDs`, `activeLongPayouts`, `activeShortPayouts`, `activeUserPayoutIDs`, `PayoutOrderCreated`, `PayoutOrderUpdated`, `removePendingOrder`, `getNextPayoutID`, and view functions) from `CCListingTemplate.sol`.
- v0.1.7: Removed `xPrepOut`, `xExecuteOut`, `yPrepOut`, `yExecuteOut`, moved to `CCLiquidityPartial.sol` (v0.1.4). Renamed `update` to `ccUpdate` to align with `CCLiquidityPartial.sol` and avoid call forwarding.
- v0.1.6: Added `resetRouters` function to fetch lister via `ICCAgent.getLister`, restrict to lister, and update `routers` and `routerAddresses` with `ICCAgent.getRouters`.
- v0.1.4: Removed fixed gas limit in `globalizeUpdate` for `ICCAgent.globalizerAddress` and `ITokenRegistry.initializeBalances`. Modified `globalizeUpdate` to emit events (`GlobalizeUpdateFailed`, `UpdateRegistryFailed`) on failure without reverting, ensuring deposits succeed. Consolidated registry update into `globalizeUpdate` for atomicity.
- v0.1.3: Removed duplicate subtraction in `transactToken` and `transactNative`, as liquidity updates are handled via `ccUpdate`. Updated balance checks to use `xLiquid`/`yLiquid`, excluding fees.
- v0.1.2: Integrated `update` calls with `updateType == 0` for subtraction. Maintained fee segregation.

**Compatibility**:
- CCListingTemplate.sol (v0.0.10)
- CCLiquidityRouter.sol (v0.0.25)
- CCMainPartial.sol (v0.1.5)
- CCGlobalizer.sol (v0.2.1)
- ICCLiquidity.sol (v0.0.4)
- ICCListing.sol (v0.0.7)
- CCSEntryPartial.sol (v0.0.18)
- CCLiquidityPartial.sol (v0.1.6)

## Interfaces
- **IERC20**: Provides `decimals()`, `transfer(address, uint256)`, `balanceOf(address)`.
- **ICCListing**: Provides `prices(uint256)` (returns `price`), `volumeBalances(uint256)` (returns `xBalance`, `yBalance`), `tokenA()`, `tokenB()`, `decimalsA()`, `decimalsB()`.
- **ICCAgent**: Provides `registryAddress()`, `globalizerAddress()`, `getLister(address)`, `getRouters()`.
- **ITokenRegistry**: Provides `initializeBalances(address token, address[] memory users)`.
- **ICCGlobalizer**: Provides `globalizeLiquidity(address depositor, address token)`.

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
- **`routerAddresses`**: `address[] private` - Authorized router addresses.
- **`nextPayoutId`**: `uint256 private` - Tracks next payout ID.

## Mappings
- **`routers`**: `mapping(address => bool) public` - Authorized routers.
- **`xLiquiditySlots`**: `mapping(uint256 => Slot) public` - Token A slot data.
- **`yLiquiditySlots`**: `mapping(uint256 => Slot) public` - Token B slot data.
- **`userXIndex`**: `mapping(address => uint256[]) public` - User xSlot indices.
- **`userYIndex`**: `mapping(address => uint256[]) public` - User ySlot indices.
- **`longPayout`**: `mapping(uint256 => LongPayoutStruct) public` - Long payout details.
- **`shortPayout`**: `mapping(uint256 => ShortPayoutStruct) public` - Short payout details.
- **`userPayoutIDs`**: `mapping(address => uint256[]) private` - Payout order IDs per user.
- **`activeUserPayoutIDs`**: `mapping(address => uint256[]) private` - Active payout order IDs per user.

## Arrays
- **`longPayoutByIndex`**: `uint256[] private` - Tracks all long payout order IDs.
- **`shortPayoutByIndex`**: `uint256[] private` - Tracks all short payout order IDs.
- **`activeLongPayouts`**: `uint256[] private` - Tracks active long payout order IDs (status = 1).
- **`activeShortPayouts`**: `uint256[] private` - Tracks active short payout order IDs (status = 1).

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
   - `updateType`: Update type (0=balance, 1=fees, 2=xSlot, 3=ySlot, 4=xSlot depositor change, 5=ySlot depositor change).
   - `index`: Index (0=xFees/xLiquid, 1=yFees/yLiquid, or slot).
   - `value`: Normalized amount/allocation.
   - `addr`: Depositor address.
   - `recipient`: Recipient address for withdrawals.

4. **PreparedWithdrawal**:
   - `amountA`: Normalized token A withdrawal.
   - `amountB`: Normalized token B withdrawal.

5. **LongPayoutStruct**:
   - `makerAddress`: Payout creator.
   - `recipientAddress`: Payout recipient.
   - `required`: Normalized token B amount required.
   - `filled`: Normalized amount filled.
   - `amountSent`: Normalized token A amount sent.
   - `orderId`: Payout order ID.
   - `status`: 0 (cancelled), 1 (pending), 2 (partially filled), 3 (filled).

6. **ShortPayoutStruct**:
   - `makerAddress`: Payout creator.
   - `recipientAddress`: Payout recipient.
   - `amount`: Normalized token A amount required.
   - `filled`: Normalized amount filled.
   - `amountSent`: Normalized token B amount sent.
   - `orderId`: Payout order ID.
   - `status`: 0 (cancelled), 1 (pending), 2 (partially filled), 3 (filled).

7. **PayoutUpdate**:
   - `payoutType`: 0 (long, tokenB), 1 (short, tokenA).
   - `recipient`: Payout recipient.
   - `orderId`: Explicit order ID for targeting.
   - `required`: Normalized amount required.
   - `filled`: Normalized amount filled.
   - `amountSent`: Normalized amount of opposite token sent.

## Events
- **`LiquidityUpdated`**: Emitted on `xLiquid` or `yLiquid` updates (`listingId`, `xLiquid`, `yLiquid`).
- **`FeesUpdated`**: Emitted on `xFees` or `yFees` updates (`listingId`, `xFees`, `yFees`).
- **`SlotDepositorChanged`**: Emitted on slot depositor changes (`isX`, `slotIndex`, `oldDepositor`, `newDepositor`).
- **`GlobalizeUpdateFailed`**: Emitted on `globalizeUpdate` failure (`depositor`, `listingId`, `isX`, `amount`, `reason`).
- **`UpdateRegistryFailed`**: Emitted on registry update failure (`depositor`, `isX`, `reason`).
- **`TransactFailed`**: Emitted on transfer failure (`depositor`, `token`, `amount`, `reason`).
- **`PayoutOrderCreated`**: Emitted on new payout creation (`orderId`, `isLong`, `status`).
- **`PayoutOrderUpdated`**: Emitted on payout updates (`orderId`, `isLong`, `filled`, `amountSent`, `status`).

## External Functions
### setRouters(address[] memory _routers)
- **Purpose**: Sets `routers` and `routerAddresses`, callable once.
- **Parameters**: `_routers`: Array of router addresses.
- **Restrictions**: Reverts if `routersSet` or `_routers` empty/invalid.
- **Internal Call Tree**: None.
- **Gas**: Loop over `_routers`, array push.
- **Callers**: External setup (e.g., `CCLiquidityRouter.sol`).

### setListingId(uint256 _listingId)
- **Purpose**: Sets `listingId`, callable once.
- **Parameters**: `_listingId`: Listing identifier.
- **Restrictions**: Reverts if `listingId` set.
- **Internal Call Tree**: None.
- **Gas**: Single assignment.
- **Callers**: External setup.

### setListingAddress(address _listingAddress)
- **Purpose**: Sets `listingAddress`, callable once.
- **Parameters**: `_listingAddress`: Listing contract address.
- **Restrictions**: Reverts if `listingAddress` set or `_listingAddress` invalid.
- **Internal Call Tree**: None.
- **Gas**: Single assignment.
- **Callers**: External setup.

### setTokens(address _tokenA, address _tokenB)
- **Purpose**: Sets `tokenA` and `tokenB`, callable once.
- **Parameters**: `_tokenA`: Token A address (ETH if zero). `_tokenB`: Token B address (ETH if zero).
- **Restrictions**: Reverts if tokens set, identical, or both zero.
- **Internal Call Tree**: None.
- **Gas**: Two assignments.
- **Callers**: External setup.

### setAgent(address _agent)
- **Purpose**: Sets `agent`, callable once.
- **Parameters**: `_agent`: Agent contract address.
- **Restrictions**: Reverts if `agent` set or `_agent` invalid.
- **Internal Call Tree**: None.
- **Gas**: Single assignment.
- **Callers**: External setup.

### resetRouters()
- **Purpose**: Resets `routers` and `routerAddresses` to `ICCAgent.getRouters()`, restricted to lister.
- **Parameters**: None.
- **Restrictions**: Reverts if `msg.sender != ICCAgent.getLister(listingAddress)` or no routers available.
- **Internal Call Tree**: `ICCAgent.getLister`, `ICCAgent.getRouters`.
- **Gas**: Loop over `routerAddresses` to clear, loop over new routers, array operations.
- **Callers**: Lister via external call.

### ccUpdate(address depositor, UpdateType[] memory updates)
- **Purpose**: Updates liquidity and slot details, adjusts `xLiquid`, `yLiquid`, `xFees`, `yFees`, updates `userXIndex` or `userYIndex`, calls `globalizeUpdate`, emits `LiquidityUpdated` or `FeesUpdated`.
- **Parameters**: `depositor`: Address for update. `updates`: Array of `UpdateType` structs.
- **Restrictions**: Router-only (`routers[msg.sender]`).
- **Internal Call Flow**:
  - Iterates `updates`:
    - `updateType == 0`: Sets `xLiquid` (`index == 0`) or `yLiquid` (`index == 1`).
    - `updateType == 1`: Adds to `xFees` (`index == 0`) or `yFees` (`index == 1`), emits `FeesUpdated`.
    - `updateType == 2`: Updates `xLiquiditySlots`, validates allocation, adjusts `xLiquid`, updates `activeXLiquiditySlots`, `userXIndex`, calls `globalizeUpdate` (tokenA).
    - `updateType == 3`: Updates `yLiquiditySlots`, validates allocation, adjusts `yLiquid`, updates `activeYLiquiditySlots`, `userYIndex`, calls `globalizeUpdate` (tokenB).
    - `updateType == 4`: Updates `xLiquiditySlots` depositor, updates `userXIndex`, emits `SlotDepositorChanged`.
    - `updateType == 5`: Updates `yLiquiditySlots` depositor, updates `userYIndex`, emits `SlotDepositorChanged`.
- **Internal Call Tree**: `globalizeUpdate` (`ICCAgent.globalizerAddress`, `ICCGlobalizer.globalizeLiquidity`, `ICCAgent.registryAddress`, `ITokenRegistry.initializeBalances`).
- **Gas**: Loop over `updates`, array operations, `globalizeUpdate` calls.
- **Callers**: `CCLiquidityPartial.sol` (`_updateDeposit`, `_executeWithdrawal`, `_changeDepositor`).

### ssUpdate(PayoutUpdate[] calldata updates)
- **Purpose**: Manages long (tokenB) and short (tokenA) payouts, updates `longPayout`, `shortPayout`, arrays, emits `PayoutOrderCreated` or `PayoutOrderUpdated`.
- **Parameters**: `updates`: Array of `PayoutUpdate` structs.
- **Restrictions**: Router-only (`routers[msg.sender]`).
- **Internal Call Flow**:
  - Iterates `updates`:
    - Validates `recipient`, `payoutType`, `required`/`filled`.
    - For `payoutType == 0` (long): Sets/updates `longPayout`, arrays, emits events.
    - For `payoutType == 1` (short): Sets/updates `shortPayout`, arrays, emits events.
    - Increments `nextPayoutId` for new payouts.
- **Internal Call Tree**: `removePendingOrder`.
- **Gas**: Loop over `updates`, array operations.
- **Callers**: `CCLiquidityRouter.sol` for payout settlements.

### transactToken(address depositor, address token, uint256 amount, address recipient)
- **Purpose**: Transfers ERC20 tokens, checks `xLiquid`/`yLiquid`, calls `globalizeUpdate`, emits `TransactFailed` on failure.
- **Parameters**: `depositor`, `token` (tokenA or tokenB), `amount` (denormalized), `recipient`.
- **Restrictions**: Router-only, valid token, non-zero amount, sufficient `xLiquid`/`yLiquid`.
- **Internal Call Tree**: `normalize`, `globalizeUpdate`, `IERC20.decimals`, `IERC20.transfer`, `IERC20.balanceOf`.
- **Gas**: Single transfer, balance check, `globalizeUpdate`.
- **Callers**: `CCLiquidityPartial.sol` (`xExecuteOut`, `yExecuteOut`, `_executeFeeClaim`).

### transactNative(address depositor, uint256 amount, address recipient)
- **Purpose**: Transfers ETH, checks `xLiquid`/`yLiquid`, calls `globalizeUpdate`, emits `TransactFailed` on failure.
- **Parameters**: `depositor`, `amount` (denormalized), `recipient`.
- **Restrictions**: Router-only, non-zero amount, sufficient `xLiquid`/`yLiquid`.
- **Internal Call Tree**: `normalize`, `globalizeUpdate`.
- **Gas**: Single transfer, balance check, `globalizeUpdate`.
- **Callers**: `CCLiquidityPartial.sol` (`xExecuteOut`, `yExecuteOut`, `_executeFeeClaim`).

### getNextPayoutID() view returns (uint256 payoutId)
- **Purpose**: Returns `nextPayoutId`.
- **Parameters**: None.
- **Internal Call Tree**: None.
- **Gas**: Single read.
- **Callers**: External contracts or frontends.

## View Functions
- **getListingAddress(uint256)**: Returns `listingAddress`.
- **liquidityAmounts()**: Returns `xLiquid`, `yLiquid`.
- **liquidityDetailsView(address)**: Returns `xLiquid`, `yLiquid`, `xFees`, `yFees`.
- **activeXLiquiditySlotsView()**: Returns `activeXLiquiditySlots`.
- **activeYLiquiditySlotsView()**: Returns `activeYLiquiditySlots`.
- **userXIndexView(address user)**: Returns `userXIndex[user]`.
- **userYIndexView(address user)**: Returns `userYIndex[user]`.
- **getActiveXLiquiditySlots()**: Returns `activeXLiquiditySlots`.
- **getActiveYLiquiditySlots()**: Returns `activeYLiquiditySlots`.
- **getXSlotView(uint256 index)**: Returns xSlot details.
- **getYSlotView(uint256 index)**: Returns ySlot details.
- **routerAddressesView()**: Returns `routerAddresses`.
- **longPayoutByIndexView()**: Returns `longPayoutByIndex`.
- **shortPayoutByIndexView()**: Returns `shortPayoutByIndex`.
- **userPayoutIDsView(address user)**: Returns `userPayoutIDs[user]`.
- **activeLongPayoutsView()**: Returns `activeLongPayouts`.
- **activeShortPayoutsView()**: Returns `activeShortPayouts`.
- **activeUserPayoutIDsView(address user)**: Returns `activeUserPayoutIDs[user]`.
- **getLongPayout(uint256 orderId)**: Returns `longPayout[orderId]`.
- **getShortPayout(uint256 orderId)**: Returns `shortPayout[orderId]`.

## Additional Details
- **Decimal Handling**: Normalizes to 1e18 using `IERC20.decimals`, denormalizes for transfers.
- **Reentrancy Protection**: Handled by routers (`CCLiquidityRouter`).
- **Gas Optimization**: Dynamic arrays, minimal external calls, try-catch for safety.
- **Token Usage**: xSlots provide token A, claim yFees; ySlots provide token B, claim xFees. Long payouts (tokenB), short payouts (tokenA).
- **Fee System**: Cumulative fees (`xFeesAcc`, `yFeesAcc`) never decrease; `dFeesAcc` tracks fees at slot updates.
- **Payout System**: Long/short payouts tracked in `longPayout`, `shortPayout`, with active arrays for status=1, historical arrays for all orders.
- **Globalization**: In `ccUpdate`, `transactToken`, `transactNative`, calls `globalizeUpdate` for slot updates or withdrawals.
- **Safety**:
  - Explicit casting for interfaces.
  - No inline assembly, high-level Solidity.
  - Try-catch for external calls with detailed revert strings.
  - Public state variables accessed via getters or view functions.
  - No reserved keywords, no `virtual`/`override`.
- **Router Security**: Only `routers[msg.sender]` can call restricted functions.
- **Events**: Comprehensive emission for state changes and failures.