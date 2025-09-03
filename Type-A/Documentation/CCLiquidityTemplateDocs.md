# CCLiquidityTemplate Documentation

## Overview
The `CCLiquidityTemplate`, implemented in Solidity (^0.8.2), manages liquidity pools, fees, slot updates, and payout functionality in a decentralized trading platform. It integrates with `ICCAgent`, `ITokenRegistry`, `ICCListing`, `IERC20`, and `ICCGlobalizer` for registry updates, token operations, and liquidity globalization. State variables are public, accessed via getters or view functions, with amounts normalized to 1e18. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation with try-catch for external calls.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.1.19 (Updated 2025-09-03)

**Changes**:
- v0.1.19: Updated documentation to include all functions, clarified internal call trees, and addressed view functions comprehensively.
- v0.1.18: Added `updateType` 6 (xSlot dFeesAcc update) and 7 (ySlot dFeesAcc update) in `ccUpdate` to update `dFeesAcc` without modifying allocation or liquidity. Updated payout documentation.
- v0.1.17: Removed `xLiquid`/`yLiquid` reduction in `transactToken` and `transactNative` to prevent double reduction, as `ccUpdate` handles liquidity adjustments.
- v0.1.16: Added `updateType` 4 (xSlot depositor change) and 5 (ySlot depositor change) in `ccUpdate` to update depositor and `userXIndex`/`userYIndex`. Emits `SlotDepositorChanged`.
- v0.1.15: Removed unnecessary checks in `ccUpdate`.
- v0.1.14: Skipped allocation check for new slots in `ccUpdate` for `updateType` 2 and 3.
- v0.1.13: Updated `ccUpdate` for `updateType` 2 and 3 to adjust `xLiquid`/`yLiquid` by allocation difference.
- v0.1.12: Added `updateType` 4 and 5 to `ccUpdate` for depositor changes.
- v0.1.11: Hid `routerAddresses` as `routerAddressesView` is preferred.
- v0.1.10: Removed `updateLiquidity` as `ccUpdate` is sufficient.
- v0.1.8: Added payout functionality (`ssUpdate`, `PayoutUpdate`, `LongPayoutStruct`, `ShortPayoutStruct`, etc.) from `CCListingTemplate.sol`.

**Compatibility**:
- CCListingTemplate.sol (v0.3.6)
- CCLiquidityRouter.sol (v0.1.2)
- CCMainPartial.sol (v0.1.4)
- CCGlobalizer.sol (v0.2.1)
- ICCLiquidity.sol (v0.0.5)
- ICCListing.sol (v0.0.7)
- CCSEntryPartial.sol (v0.0.18)

## State Variables
- `routersSet`: `bool public` - Tracks if routers are set.
- `listingAddress`: `address public` - Listing contract address.
- `tokenA`: `address public` - Token A address (ETH if zero).
- `tokenB`: `address public` - Token B address (ETH if zero).
- `listingId`: `uint256 public` - Listing identifier.
- `agent`: `address public` - Agent contract address.
- `liquidityDetail`: `LiquidityDetails public` - Stores `xLiquid`, `yLiquid`, `xFees`, `yFees`, `xFeesAcc`, `yFeesAcc`.
- `activeXLiquiditySlots`: `uint256[] public` - Active xSlot indices.
- `activeYLiquiditySlots`: `uint256[] public` - Active ySlot indices.
- `routerAddresses`: `address[] private` - Authorized router addresses.
- `nextPayoutId`: `uint256 private` - Tracks next payout ID.

## Mappings
- `routers`: `mapping(address => bool) public` - Authorized routers.
- `xLiquiditySlots`: `mapping(uint256 => Slot) private` - Token A slot data.
- `yLiquiditySlots`: `mapping(uint256 => Slot) private` - Token B slot data.
- `userXIndex`: `mapping(address => uint256[]) private` - User xSlot indices.
- `userYIndex`: `mapping(address => uint256[]) private` - User ySlot indices.
- `longPayout`: `mapping(uint256 => LongPayoutStruct) private` - Long payout details.
- `shortPayout`: `mapping(uint256 => ShortPayoutStruct) private` - Short payout details.
- `userPayoutIDs`: `mapping(address => uint256[]) private` - Payout order IDs per user.
- `activeUserPayoutIDs`: `mapping(address => uint256[]) private` - Active payout order IDs per user.

## Arrays
- `longPayoutByIndex`: `uint256[] private` - Tracks all long payout order IDs.
- `shortPayoutByIndex`: `uint256[] private` - Tracks all short payout order IDs.
- `activeLongPayouts`: `uint256[] private` - Tracks active long payout order IDs (status = 1).
- `activeShortPayouts`: `uint256[] private` - Tracks active short payout order IDs (status = 1).

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
   - `updateType`: Update type (0=balance, 1=fees, 2=xSlot, 3=ySlot, 4=xSlot depositor change, 5=ySlot depositor change, 6=xSlot dFeesAcc, 7=ySlot dFeesAcc).
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
   - `amountSent`: Normalized amount of token A sent.
   - `orderId`: Payout order ID.
   - `status`: 0=cancelled, 1=pending, 2=partially filled, 3=filled.
6. **ShortPayoutStruct**:
   - `makerAddress`: Payout creator.
   - `recipientAddress`: Payout recipient.
   - `amount`: Normalized token A amount required.
   - `filled`: Normalized amount filled.
   - `amountSent`: Normalized amount of token B sent.
   - `orderId`: Payout order ID.
   - `status`: 0=cancelled, 1=pending, 2=partially filled, 3=filled.
7. **PayoutUpdate**:
   - `payoutType`: 0=long, 1=short.
   - `recipient`: Payout recipient.
   - `orderId`: Explicit order ID.
   - `required`: Amount required.
   - `filled`: Amount filled.
   - `amountSent`: Amount of opposite token sent.

## External Functions and Internal Call Trees
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

### setRouters(address[] memory _routers)
- **Purpose**: Sets router addresses, callable once.
- **Parameters**: `_routers`: Array of router addresses.
- **Restrictions**: Reverts if routers set or no valid routers provided.
- **Internal Call Tree**: None.
- **Gas**: Loop over `_routers`, array push.
- **Callers**: External setup.

### resetRouters()
- **Purpose**: Resets `routers` and `routerAddresses` to `ICCAgent.getRouters()`, restricted to lister.
- **Parameters**: None.
- **Restrictions**: Reverts if `msg.sender != ICCAgent.getLister(listingAddress)` or no routers available.
- **Internal Call Tree**: `ICCAgent.getLister`, `ICCAgent.getRouters`.
- **Gas**: Loop over `routerAddresses` to clear, loop over new routers, array operations.
- **Callers**: Lister via external call.

### ccUpdate(address depositor, UpdateType[] memory updates)
- **Purpose**: Updates liquidity, slots, fees, or depositors, adjusts `xLiquid`, `yLiquid`, `xFees`, `yFees`, updates `userXIndex` or `userYIndex`, calls `globalizeUpdate`, emits `LiquidityUpdated`, `FeesUpdated`, or `SlotDepositorChanged`.
- **Parameters**: `depositor`: Address for update. `updates`: Array of `UpdateType` structs.
- **Restrictions**: Router-only (`routers[msg.sender]`).
- **Internal Call Flow**:
  - Iterates `updates`:
    - `updateType == 0`: Sets `xLiquid` (`index == 0`) or `yLiquid` (`index == 1`).
    - `updateType == 1`: Adds to `xFees` (`index == 0`) or `yFees` (`index == 1`), emits `FeesUpdated`.
    - `updateType == 2`: Updates `xLiquiditySlots`, adjusts `xLiquid`, updates `activeXLiquiditySlots`, `userXIndex`, calls `globalizeUpdate` (tokenA).
    - `updateType == 3`: Updates `yLiquiditySlots`, adjusts `yLiquid`, updates `activeYLiquiditySlots`, `userYIndex`, calls `globalizeUpdate` (tokenB).
    - `updateType == 4`: Updates `xLiquiditySlots` depositor, updates `userXIndex`, emits `SlotDepositorChanged`.
    - `updateType == 5`: Updates `yLiquiditySlots` depositor, updates `userYIndex`, emits `SlotDepositorChanged`.
    - `updateType == 6`: Updates `xLiquiditySlots.dFeesAcc` for fee claims.
    - `updateType == 7`: Updates `yLiquiditySlots.dFeesAcc` for fee claims.
  - Calls `globalizeUpdate`: Invokes `ICCGlobalizer.globalizeLiquidity` and `ITokenRegistry.initializeBalances`.
- **Internal Call Tree**: `globalizeUpdate` (`ICCAgent.globalizerAddress`, `ICCGlobalizer.globalizeLiquidity`, `ICCAgent.registryAddress`, `ITokenRegistry.initializeBalances`).
- **Gas**: Loop over `updates`, array operations, `globalizeUpdate` calls.
- **Callers**: `CCLiquidityPartial.sol` (`_updateDeposit`, `_executeWithdrawal`, `_executeFeeClaim`, `_changeDepositor`).

### ssUpdate(PayoutUpdate[] calldata updates)
- **Purpose**: Manages long (tokenB) and short (tokenA) payouts, updates `longPayout`, `shortPayout`, arrays, emits `PayoutOrderCreated` or `PayoutOrderUpdated`.
- **Parameters**: `updates`: Array of `PayoutUpdate` structs.
- **Restrictions**: Router-only (`routers[msg.sender]`).
- **Internal Call Flow**:
  - Iterates `updates`:
    - Validates `recipient`, `payoutType`, `required`/`filled`.
    - For `payoutType == 0` (long): Sets/updates `longPayout`, `longPayoutByIndex`, `activeLongPayouts`, `userPayoutIDs`, `activeUserPayoutIDs`, emits events.
    - For `payoutType == 1` (short): Sets/updates `shortPayout`, `shortPayoutByIndex`, `activeShortPayouts`, `userPayoutIDs`, `activeUserPayoutIDs`, emits events.
    - Calls `removePendingOrder` for cancelled or filled orders.
    - Increments `nextPayoutId` for new payouts.
- **Internal Call Tree**: `removePendingOrder`.
- **Gas**: Loop over `updates`, array operations.
- **Callers**: `CCOrderRouter.sol` for payout settlements.

### transactToken(address depositor, address token, uint256 amount, address recipient)
- **Purpose**: Transfers ERC20 tokens, checks `xLiquid`/`yLiquid`, emits `TransactFailed` on failure.
- **Parameters**: `depositor`, `token` (tokenA or tokenB), `amount` (denormalized), `recipient`.
- **Restrictions**: Router-only, valid token, non-zero amount, sufficient `xLiquid`/`yLiquid`.
- **Internal Call Tree**: `normalize`, `IERC20.decimals`, `IERC20.transfer`, `IERC20.balanceOf`.
- **Gas**: Single transfer, balance check.
- **Callers**: `CCLiquidityPartial.sol` (`_transferPrimaryToken`, `_transferCompensationToken`, `_executeFeeClaim`).

### transactNative(address depositor, uint256 amount, address recipient)
- **Purpose**: Transfers ETH, checks `xLiquid`/`yLiquid`, emits `TransactFailed` on failure.
- **Parameters**: `depositor`, `amount` (denormalized), `recipient`.
- **Restrictions**: Router-only, non-zero amount, sufficient `xLiquid`/`yLiquid`.
- **Internal Call Tree**: `normalize`.
- **Gas**: Single transfer, balance check.
- **Callers**: `CCLiquidityPartial.sol` (`_transferPrimaryToken`, `_transferCompensationToken`, `_executeFeeClaim`).

### getNextPayoutID() view returns (uint256 payoutId)
- **Purpose**: Returns `nextPayoutId`.
- **Parameters**: None.
- **Internal Call Tree**: None.
- **Gas**: Single read.
- **Callers**: External contracts or frontends.

### removePendingOrder(uint256[] storage orders, uint256 orderId) internal
- **Purpose**: Removes order ID from specified array.
- **Parameters**: `orders`: Storage array. `orderId`: ID to remove.
- **Internal Call Tree**: None.
- **Gas**: Linear search, array pop.
- **Callers**: `ssUpdate` for payout cancellations or completions.

## View Functions
- `getListingAddress(uint256)`: Returns `listingAddress`.
- `liquidityAmounts()`: Returns `xLiquid`, `yLiquid`.
- `liquidityDetailsView()`: Returns `xLiquid`, `yLiquid`, `xFees`, `yFees`, `xFeesAcc`, `yFeesAcc`.
- `userXIndexView(address)`: Returns `userXIndex[user]`.
- `userYIndexView(address)`: Returns `userYIndex[user]`.
- `getActiveXLiquiditySlots()`: Returns `activeXLiquiditySlots`.
- `getActiveYLiquiditySlots()`: Returns `activeYLiquiditySlots`.
- `getXSlotView(uint256)`: Returns xSlot details.
- `getYSlotView(uint256)`: Returns ySlot details.
- `routerAddressesView()`: Returns `routerAddresses`.
- `longPayoutByIndexView()`: Returns `longPayoutByIndex`.
- `shortPayoutByIndexView()`: Returns `shortPayoutByIndex`.
- `userPayoutIDsView(address)`: Returns `userPayoutIDs[user]`.
- `activeLongPayoutsView()`: Returns `activeLongPayouts`.
- `activeShortPayoutsView()`: Returns `activeShortPayouts`.
- `activeUserPayoutIDsView(address)`: Returns `activeUserPayoutIDs[user]`.
- `getLongPayout(uint256)`: Returns `longPayout[orderId]`.
- `getShortPayout(uint256)`: Returns `shortPayout[orderId]`.

## Additional Details
- **Decimal Handling**: Normalizes to 1e18 using `IERC20.decimals`, denormalizes for transfers.
- **Reentrancy Protection**: Handled by routers (`CCLiquidityRouter`).
- **Gas Optimization**: Dynamic arrays, minimal external calls, try-catch for safety.
- **Token Usage**: xSlots provide token A, claim yFees; ySlots provide token B, claim xFees. Long payouts (tokenB), short payouts (tokenA).
- **Fee System**: Cumulative fees (`xFeesAcc`, `yFeesAcc`) never decrease; `dFeesAcc` tracks fees at slot updates.
- **Payout System**: Long/short payouts tracked in `longPayout`, `shortPayout`, with active arrays for status=1, historical arrays for all orders.
- **Globalization**: `ccUpdate` calls `globalizeUpdate` for slot updates or withdrawals.
- **Safety**:
  - Explicit casting for interfaces.
  - No inline assembly, high-level Solidity.
  - Try-catch for external calls with detailed revert strings.
  - Public state variables accessed via getters or view functions.
  - No reserved keywords, no `virtual`/`override`.
- **Router Security**: Only `routers[msg.sender]` can call restricted functions.
- **Events**: Comprehensive emission for state changes and failures.