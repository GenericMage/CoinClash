# CCLiquidityTemplate Documentation

## Overview
The `CCLiquidityTemplate`, implemented in Solidity (^0.8.2), manages liquidity deposits, withdrawals, and fee claims in a decentralized trading platform. It inherits `ReentrancyGuard` for security, integrates with `ICCAgent` and `ITokenRegistry` for global updates, and uses `IERC20` import for token operations. State variables are public, accessed via unique view functions, and amounts are normalized to 1e18 for precision. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation with try-catch for external calls.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.0.12 (Updated 2025-07-29)

**Changes**:
- **v0.0.12**: Added explicit gas limit of 1,000,000 to `globalizeLiquidity` and `registryAddress` calls in `globalizeUpdate` and `updateRegistry` functions.
- **v0.0.11**: Fixed typo in `yPrepOut`, corrected `withrawAmountA` to `withdrawAmountA`.
- **v0.0.10**: Made `updateRegistry` and `globalizeUpdate` external to resolve TypeError.

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

### Mappings
- **`routers`**: `mapping(address => bool)` - Authorized routers.
- **`xLiquiditySlots`**: `mapping(uint256 => Slot)` - Token A slot data.
- **`yLiquiditySlots`**: `mapping(uint256 => Slot)` - Token B slot data.
- **`userIndex`**: `mapping(address => uint256[])` - User slot indices.

### Structs
1. **LiquidityDetails**:
   - `xLiquid`: `uint256` - Normalized token A liquidity.
   - `yLiquid`: `uint256` - Normalized token B liquidity.
   - `xFees`: `uint256` - Normalized token A fees.
   - `yFees`: `uint256` - Normalized token B fees.
   - `xFeesAcc`: `uint256` - Cumulative token A fee volume.
   - `yFeesAcc`: `uint256` - Cumulative token B fee volume.

2. **Slot**:
   - `depositor`: `address` - Slot owner.
   - `recipient`: `address` - Unused (reserved for future use).
   - `allocation`: `uint256` - Normalized liquidity allocation.
   - `dFeesAcc`: `uint256` - Cumulative fees at deposit/claim (`yFeesAcc` for xSlots, `xFeesAcc` for ySlots).
   - `timestamp`: `uint256` - Slot creation timestamp.

3. **UpdateType**:
   - `updateType`: `uint8` - Update type (0=balance, 1=fees, 2=xSlot, 3=ySlot).
   - `index`: `uint256` - Index (0=xFees/xLiquid, 1=yFees/yLiquid, or slot index).
   - `value`: `uint256` - Normalized amount/allocation.
   - `addr`: `address` - Depositor.
   - `recipient`: `address` - Unused (reserved for future use).

4. **PreparedWithdrawal**:
   - `amountA`: `uint256` - Normalized token A withdrawal.
   - `amountB`: `uint256` - Normalized token B withdrawal.

5. **FeeClaimContext**:
   - `caller`: `address` - User address.
   - `isX`: `bool` - True for token A, false for token B.
   - `liquid`: `uint256` - Total liquidity (`xLiquid` or `yLiquid`).
   - `allocation`: `uint256` - Slot allocation.
   - `fees`: `uint256` - Available fees (`yFees` for xSlots, `xFees` for ySlots).
   - `dFeesAcc`: `uint256` - Cumulative fees at deposit/claim.
   - `liquidityIndex`: `uint256` - Slot index.

### Formulas
1. **Fee Share**:
   - **Formula**: 
     ```
     contributedFees = feesAcc - dFeesAcc
     liquidityContribution = (allocation * 1e18) / liquid
     feeShare = (contributedFees * liquidityContribution) / 1e18
     feeShare = feeShare > fees ? fees : feeShare
     ```
   - **Used in**: `_claimFeeShare`
   - **Description**: Computes fee share based on accumulated fees since deposit/claim (`feesAcc` is `yFeesAcc` for xSlots, `xFeesAcc` for ySlots), capped at available fees.

2. **Deficit and Compensation**:
   - **Formula for xPrepOut**:
     ```
     withdrawAmountA = min(amount, xLiquid)
     deficit = amount > withdrawAmountA ? amount - withdrawAmountA : 0
     withdrawAmountB = deficit > 0 ? min((deficit * 1e18) / prices(0), yLiquid) : 0
     ```
   - **Formula for yPrepOut**:
     ```
     withdrawAmountB = min(amount, yLiquid)
     deficit = amount > withdrawAmountB ? amount - withdrawAmountB : 0
     withdrawAmountA = deficit > 0 ? min((deficit * prices(0)) / 1e18, xLiquid) : 0
     ```
   - **Used in**: `xPrepOut`, `yPrepOut`
   - **Description**: Calculates withdrawal amounts, compensating shortfalls using `ICCListing.prices(0)`, capped by available liquidity.

### External Functions
#### setRouters(address[] memory _routers)
- **Behavior**: Sets routers, callable once.
- **Restrictions**: Reverts if `routersSet` or invalid/empty `_routers`.
- **Gas**: Minimal, single loop.

#### setListingId(uint256 _listingId)
- **Behavior**: Sets `listingId`, callable once.
- **Restrictions**: Reverts if `listingId` set.
- **Gas**: Minimal, single write.

#### setListingAddress(address _listingAddress)
- **Behavior**: Sets `listingAddress`, callable once.
- **Restrictions**: Reverts if `listingAddress` set or invalid.
- **Gas**: Minimal, single write.

#### setTokens(address _tokenA, address _tokenB)
- **Behavior**: Sets `tokenA`, `tokenB`, callable once.
- **Restrictions**: Reverts if tokens set, same, both zero, or invalid decimals.
- **Gas**: Minimal, state writes, `IERC20.decimals` calls.

#### setAgent(address _agent)
- **Behavior**: Sets `agent`, callable once.
- **Restrictions**: Reverts if `agent` set or invalid.
- **Gas**: Minimal, single write.

#### update(address caller, UpdateType[] memory updates)
- **Behavior**: Updates liquidity/fees/slots, emits `LiquidityUpdated`.
- **Internal**: Processes `updates` for balances, fees, xSlots, or ySlots.
- **Restrictions**: `nonReentrant`, router-only.
- **Gas**: Loop over `updates`, dynamic array resizing.

#### globalizeUpdate(address caller, bool isX, uint256 amount, bool isDeposit)
- **Behavior**: Updates `ICCAgent` with liquidity changes, emits `GlobalizeUpdateFailed` on failure.
- **Internal**: Normalizes amount, calls `ICCAgent.globalizeLiquidity` with 1,000,000 gas limit.
- **Restrictions**: Reverts if `agent` not set.
- **Gas**: Single external call with try-catch.

#### updateRegistry(address caller, bool isX)
- **Behavior**: Updates `ITokenRegistry` for token balances, emits `UpdateRegistryFailed` on failure.
- **Internal**: Fetches registry from `ICCAgent.registryAddress` with 1,000,000 gas limit, calls `ITokenRegistry.initializeBalances` with 1,000,000 gas limit.
- **Restrictions**: Reverts if `agent` or registry not set.
- **Gas**: Two external calls with try-catch.

#### changeSlotDepositor(address caller, bool isX, uint256 slotIndex, address newDepositor)
- **Behavior**: Transfers slot ownership, emits `SlotDepositorChanged`.
- **Internal**: Updates `xLiquiditySlots`/`yLiquiditySlots`, `userIndex`.
- **Restrictions**: `nonReentrant`, router-only, caller must be depositor.
- **Gas**: Single slot update, array adjustments.

#### depositToken(address caller, address token, uint256 amount)
- **Behavior**: Deposits ERC20 tokens, creates slot, emits `DepositReceived` or `DepositFailed`.
- **Internal**: Pre/post balance checks, `IERC20.transferFrom`, calls `update`, `globalizeUpdate`, `updateRegistry`.
- **Restrictions**: `nonReentrant`, router-only, valid token.
- **Gas**: Single transfer, try-catch for external calls.

#### depositNative(address caller, uint256 amount)
- **Behavior**: Deposits ETH, creates slot, emits `DepositReceived` or `DepositFailed`.
- **Internal**: Validates `msg.value`, calls `update`, `globalizeUpdate`, `updateRegistry`.
- **Restrictions**: `nonReentrant`, router-only, one token must be ETH.
- **Gas**: Minimal, try-catch for external calls.

#### xPrepOut(address caller, uint256 amount, uint256 index) returns (PreparedWithdrawal memory)
- **Behavior**: Prepares token A withdrawal, compensates with token B if shortfall.
- **Internal**: Checks `xLiquid`, `allocation`, uses `ICCListing.prices(0)`.
- **Restrictions**: `nonReentrant`, router-only, valid slot.
- **Gas**: Minimal, single `prices` call.

#### xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal)
- **Behavior**: Executes token A withdrawal, transfers tokens/ETH, emits `DepositFailed` on failure.
- **Internal**: Updates `xLiquiditySlots`, calls `transactToken`/`transactNative`, `globalizeUpdate`, `updateRegistry`.
- **Restrictions**: `nonReentrant`, router-only, valid slot.
- **Gas**: Two transfers, try-catch in `transact*`.

#### yPrepOut(address caller, uint256 amount, uint256 index) returns (PreparedWithdrawal memory)
- **Behavior**: Prepares token B withdrawal, compensates with token A if shortfall.
- **Internal**: Checks `yLiquid`, `allocation`, uses `ICCListing.prices(0)`.
- **Restrictions**: `nonReentrant`, router-only, valid slot.
- **Gas**: Minimal, single `prices` call.

#### yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal)
- **Behavior**: Executes token B withdrawal, transfers tokens/ETH, emits `DepositFailed` on failure.
- **Internal**: Updates `yLiquiditySlots`, calls `transactToken`/`transactNative`, `globalizeUpdate`, `updateRegistry`.
- **Restrictions**: `nonReentrant`, router-only, valid slot.
- **Gas**: Two transfers, try-catch in `transact*`.

#### claimFees(address caller, address _listingAddress, uint256 liquidityIndex, bool isX, uint256 /* volume */)
- **Behavior**: Claims fees, resets `dFeesAcc`, emits `FeesClaimed`.
- **Internal**: Validates listing, uses `_processFeeClaim` with `FeeClaimContext`, updates fees/slots, transfers via `transactToken`.
- **Restrictions**: `nonReentrant`, router-only, valid depositor/listing.
- **Gas**: Single transfer, stack-optimized via struct.
- **Note**: `volume` parameter is unused, reserved for future use.

#### addFees(address caller, bool isX, uint256 fee)
- **Behavior**: Adds fees to `xFees`/`yFees`, increments `xFeesAcc`/`yFeesAcc`.
- **Internal**: Creates `UpdateType`, calls `update`, emits `FeesUpdated`.
- **Restrictions**: `nonReentrant`, router-only.
- **Gas**: Minimal, single update.

#### transactToken(address caller, address token, uint256 amount, address recipient)
- **Behavior**: Transfers ERC20 tokens, updates `xLiquid`/`yLiquid`, emits `TransactFailed` on failure.
- **Internal**: Normalizes amount, checks liquidity, uses `IERC20.transfer`.
- **Restrictions**: `nonReentrant`, router-only, valid token.
- **Gas**: Single transfer, minimal updates.

#### transactNative(address caller, uint256 amount, address recipient)
- **Behavior**: Transfers ETH, updates `xLiquid`/`yLiquid`, emits `TransactFailed` on failure.
- **Internal**: Normalizes amount, checks liquidity, uses low-level `call`.
- **Restrictions**: `nonReentrant`, router-only, one token must be ETH.
- **Gas**: Single transfer, try-catch.

#### updateLiquidity(address caller, bool isX, uint256 amount)
- **Behavior**: Deducts liquidity from `xLiquid` or `yLiquid`, emits `LiquidityUpdated`.
- **Internal**: Checks liquidity balance.
- **Restrictions**: `nonReentrant`, router-only.
- **Gas**: Minimal, single update.

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

### Additional Details
- **Decimal Handling**: Normalizes to 1e18 using `IERC20.decimals`, denormalizes for transfers.
- **Reentrancy Protection**: `nonReentrant` on state-changing functions.
- **Gas Optimization**: Dynamic arrays, minimal external calls, stack-optimized `claimFees`.
- **Token Usage**: xSlots provide token A, claim yFees; ySlots provide token B, claim xFees.
- **Events**: `LiquidityUpdated`, `FeesUpdated`, `FeesClaimed`, `SlotDepositorChanged`, `GlobalizeUpdateFailed`, `UpdateRegistryFailed`, `DepositReceived`, `DepositFailed`, `TransactFailed`.
- **Safety**:
  - Explicit casting for `ICCListing`, `IERC20`, `ITokenRegistry`, `ICCAgent`.
  - No inline assembly, high-level Solidity.
  - Try-catch for external calls with detailed revert strings.
  - Public state variables accessed via unique view functions.
  - Avoids reserved keywords, unnecessary virtual/overrides.
- **Fee System**: Cumulative fees (`xFeesAcc`, `yFeesAcc`) never decrease; `dFeesAcc` tracks fees at deposit/claim.
- **Compatibility**: Aligned with `CCListingTemplate` (v0.0.10), `CCLiquidityRouter` (v0.0.11), `CCMainPartial` (v0.0.7).
