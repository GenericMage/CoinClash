# CCLiquidityTemplate Documentation

## Overview
The `CCLiquidityTemplate`, implemented in Solidity (^0.8.2), is part of a decentralized trading platform, managing liquidity deposits, withdrawals, and fee claims. It inherits `ReentrancyGuard` for security and uses `SafeERC20` for token operations, integrating with `ICCAgent` and `ITokenRegistry` for global updates and synchronization. State variables are public, accessed via view functions with unique names, and amounts are normalized to 1e18 for precision across token decimals. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.0.2 (Updated 2025-07-26)

### State Variables
- **`routersSet`**: `bool public` - Tracks if routers are set, prevents re-setting.
- **`listingAddress`**: `address public` - Address of the listing contract.
- **`tokenA`**: `address public` - Address of token A (or ETH if zero).
- **`tokenB`**: `address public` - Address of token B (or ETH if zero).
- **`listingId`**: `uint256 public` - Unique identifier for the listing.
- **`agent`**: `address public` - Address of the agent contract for global updates.
- **`liquidityDetail`**: `LiquidityDetails public` - Stores `xLiquid`, `yLiquid`, `xFees`, `yFees`, `xFeesAcc`, `yFeesAcc`.
- **`activeXLiquiditySlots`**: `uint256[] public` - Array of active xSlot indices.
- **`activeYLiquiditySlots`**: `uint256[] public` - Array of active ySlot indices.

### Mappings
- **`routers`**: `mapping(address => bool)` - Maps addresses to authorized routers.
- **`xLiquiditySlots`**: `mapping(uint256 => Slot)` - Maps slot index to token A slot data.
- **`yLiquiditySlots`**: `mapping(uint256 => Slot)` - Maps slot index to token B slot data.
- **`userIndex`**: `mapping(address => uint256[])` - Maps user address to their slot indices.

### Structs
1. **LiquidityDetails**:
   - `xLiquid`: `uint256` - Normalized liquidity for token A.
   - `yLiquid`: `uint256` - Normalized liquidity for token B.
   - `xFees`: `uint256` - Normalized fees for token A.
   - `yFees`: `uint256` - Normalized fees for token B.
   - `xFeesAcc`: `uint256` - Cumulative fee volume for token A.
   - `yFeesAcc`: `uint256` - Cumulative fee volume for token B.

2. **Slot**:
   - `depositor`: `address` - Address of the slot owner.
   - `recipient`: `address` - Unused recipient address.
   - `allocation`: `uint256` - Normalized liquidity allocation.
   - `dFeesAcc`: `uint256` - Cumulative fees at deposit or last claim (yFeesAcc for xSlots, xFeesAcc for ySlots).
   - `timestamp`: `uint256` - Slot creation timestamp.

3. **UpdateType**:
   - `updateType`: `uint8` - Update type (0=balance, 1=fees, 2=xSlot, 3=ySlot).
   - `index`: `uint256` - Index (0=xFees/xLiquid, 1=yFees/yLiquid, or slot index).
   - `value`: `uint256` - Normalized amount or allocation.
   - `addr`: `address` - Depositor address.
   - `recipient`: `address` - Unused recipient address.

4. **PreparedWithdrawal**:
   - `amountA`: `uint256` - Normalized withdrawal amount for token A.
   - `amountB`: `uint256` - Normalized withdrawal amount for token B.

5. **FeeClaimContext**:
   - `caller`: `address` - User address.
   - `isX`: `bool` - True for token A, false for token B.
   - `liquid`: `uint256` - Total liquidity (xLiquid or yLiquid).
   - `allocation`: `uint256` - Slot allocation.
   - `fees`: `uint256` - Available fees (yFees for xSlots, xFees for ySlots).
   - `dFeesAcc`: `uint256` - Cumulative fees at deposit or last claim.
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
   - **Description**: Computes fee share for a liquidity slot based on accumulated fees since deposit or last claim (`feesAcc` is `yFeesAcc` for xSlots, `xFeesAcc` for ySlots) and liquidity proportion, capped at available fees (`yFees` for xSlots, `xFees` for ySlots).

2. **Deficit and Compensation**:
   - **Formula for xPrepOut**:
     ```
     withdrawAmountA = min(amount, xLiquid)
     deficit = amount > withdrawAmountA ? amount - withdrawAmountA : 0
     withdrawAmountB = deficit > 0 ? min((deficit * 1e18) / getPrice(), yLiquid) : 0
     ```
   - **Formula for yPrepOut**:
     ```
     withdrawAmountB = min(amount, yLiquid)
     deficit = amount > withdrawAmountB ? amount - withdrawAmountB : 0
     withdrawAmountA = deficit > 0 ? min((deficit * getPrice()) / 1e18, xLiquid) : 0
     ```
   - **Used in**: `xPrepOut`, `yPrepOut`
   - **Description**: Calculates withdrawal amounts for token A (`xPrepOut`) or token B (`yPrepOut`), compensating any shortfall (`deficit`) in requested liquidity (`amount`) against available liquidity (`xLiquid` or `yLiquid`) by converting the deficit to the opposite token using the current price from `ICCLiquidity.getPrice`, ensuring amounts are normalized and capped by available liquidity.

### External Functions
#### setRouters(address[] memory _routers)
- **Parameters**: `_routers` - Array of router addresses.
- **Behavior**: Sets authorized routers, callable once.
- **Internal Call Flow**: Updates `routers` mapping, sets `routersSet`.
- **Restrictions**: Reverts if `routersSet` is true or `_routers` is empty/invalid.
- **Gas Usage Controls**: Single loop, minimal state writes.

#### setListingId(uint256 _listingId)
- **Parameters**: `_listingId` - Listing ID.
- **Behavior**: Sets `listingId`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `listingId` already set.
- **Gas Usage Controls**: Minimal, single state write.

#### setListingAddress(address _listingAddress)
- **Parameters**: `_listingAddress` - Listing contract address.
- **Behavior**: Sets `listingAddress`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `listingAddress` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### setTokens(address _tokenA, address _tokenB)
- **Parameters**: `_tokenA`, `_tokenB` - Token addresses.
- **Behavior**: Sets `tokenA`, `tokenB`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if tokens already set, same, or both zero.
- **Gas Usage Controls**: Minimal, state writes.

#### setAgent(address _agent)
- **Parameters**: `_agent` - Agent contract address.
- **Behavior**: Sets `agent`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `agent` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### update(address caller, UpdateType[] memory updates)
- **Parameters**:
  - `caller` - User address.
  - `updates` - Array of update structs.
- **Behavior**: Updates liquidity or fees, manages slots.
- **Internal Call Flow**:
  - Processes `updates`:
    - `updateType=0`: Updates `xLiquid` or `yLiquid`.
    - `updateType=1`: Updates `xFees` or `yFees`, emits `FeesUpdated`.
    - `updateType=2`: Updates `xLiquiditySlots`, `activeXLiquiditySlots`, `userIndex`, sets `dFeesAcc` to `yFeesAcc`.
    - `updateType=3`: Updates `yLiquiditySlots`, `activeYLiquiditySlots`, `userIndex`, sets `dFeesAcc` to `xFeesAcc`.
  - Emits `LiquidityUpdated`.
- **Balance Checks**: None, assumes normalized input.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `yLiquiditySlots`, `activeXLiquiditySlots`, `activeYLiquiditySlots`, `userIndex`, `liquidityDetail`.
  - **Structs**: `UpdateType`, `LiquidityDetails`, `Slot`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`.
- **Gas Usage Controls**: Dynamic array resizing, loop over `updates`, no external calls.

#### changeSlotDepositor(address caller, bool isX, uint256 slotIndex, address newDepositor)
- **Parameters**:
  - `caller` - User address.
  - `isX` - True for token A, false for token B.
  - `slotIndex` - Slot index.
  - `newDepositor` - New depositor address.
- **Behavior**: Transfers slot ownership to `newDepositor`.
- **Internal Call Flow**:
  - Updates `xLiquiditySlots` or `yLiquiditySlots`, adjusts `userIndex`.
  - Emits `SlotDepositorChanged`.
- **Balance Checks**: Verifies slot `allocation` is non-zero.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `yLiquiditySlots`, `userIndex`.
  - **Structs**: `Slot`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, caller must be current depositor.
- **Gas Usage Controls**: Single slot update, array adjustments.

#### depositToken(address caller, address token, uint256 amount)
- **Parameters**:
  - `caller` - User address.
  - `token` - Token A or B.
  - `amount` - Denormalized amount.
- **Behavior**: Deposits ERC20 tokens to liquidity pool, creates new slot.
- **Internal Call Flow**:
  - Performs pre/post balance checks, transfers via `SafeERC20.transferFrom`.
  - Normalizes `amount`, creates `UpdateType` for slot allocation (sets `dFeesAcc`).
  - Calls `update`, `globalizeUpdate`, `updateRegistry`.
  - Emits `DepositReceived`.
- **Balance Checks**: Pre/post balance for tokens.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `yLiquiditySlots`, `activeXLiquiditySlots`, `activeYLiquiditySlots`, `userIndex`, `liquidityDetail`.
  - **Structs**: `UpdateType`, `LiquidityDetails`, `Slot`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, valid token, non-zero address.
- **Gas Usage Controls**: Single transfer, minimal updates, try-catch for external calls.

#### depositNative(address caller, uint256 amount)
- **Parameters**:
  - `caller` - User address.
  - `amount` - Denormalized ETH amount.
- **Behavior**: Deposits ETH to liquidity pool, creates new slot.
- **Internal Call Flow**:
  - Validates `msg.value` equals `amount`.
  - Normalizes `amount`, creates `UpdateType` for slot allocation (sets `dFeesAcc`).
  - Calls `update`, `globalizeUpdate`, `updateRegistry`.
  - Emits `DepositReceived`.
- **Balance Checks**: Verifies `msg.value` matches `amount`.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `yLiquiditySlots`, `activeXLiquiditySlots`, `activeYLiquiditySlots`, `userIndex`, `liquidityDetail`.
  - **Structs**: `UpdateType`, `LiquidityDetails`, `Slot`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, one token must be ETH.
- **Gas Usage Controls**: Minimal, no external transfer, try-catch for external calls.

#### xPrepOut(address caller, uint256 amount, uint256 index) returns (PreparedWithdrawal memory)
- **Parameters**:
  - `caller` - User address.
  - `amount` - Normalized amount.
  - `index` - Slot index.
- **Behavior**: Prepares token A withdrawal, calculates compensation in token B if there is a shortfall.
- **Internal Call Flow**:
  - Checks `xLiquid` and slot `allocation` in `xLiquiditySlots`.
  - Calculates `withdrawAmountA` as the minimum of requested `amount` and available `xLiquid`.
  - Computes `deficit` as any shortfall (`amount - withdrawAmountA`).
  - If `deficit` exists, fetches `ICCLiquidity.getPrice` to convert `deficit` to token B (`withdrawAmountB = (deficit * 1e18) / getPrice()`), capped by `yLiquid`.
  - Returns `PreparedWithdrawal` with `amountA` and `amountB`, or default if `currentPrice` is zero.
- **Balance Checks**: Verifies slot `allocation`.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `liquidityDetail`.
  - **Structs**: `PreparedWithdrawal`, `LiquidityDetails`, `Slot`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, valid slot.
- **Gas Usage Controls**: Minimal, single external call to `getPrice`.

#### xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal)
- **Parameters**:
  - `caller` - User address.
  - `index` - Slot index.
  - `withdrawal` - Withdrawal amounts (`amountA`, `amountB`).
- **Behavior**: Executes token A withdrawal, transfers tokens/ETH via `transactToken` or `transactNative`.
- **Internal Call Flow**:
  - Updates `xLiquiditySlots`, `liquidityDetail` via `update`.
  - Transfers `amountA` (token A) and `amountB` (token B) using `transactToken` (ERC20) or `transactNative` (ETH).
  - Calls `globalizeUpdate`, `updateRegistry` for both tokens.
- **Balance Checks**: Verifies `xLiquid`, `yLiquid` in `transact*`.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `activeXLiquiditySlots`, `userIndex`, `liquidityDetail`.
  - **Structs**: `PreparedWithdrawal`, `UpdateType`, `LiquidityDetails`, `Slot`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, valid slot.
- **Gas Usage Controls**: Two transfers via `transact*`, minimal updates, try-catch in `transact*`.

#### yPrepOut(address caller, uint256 amount, uint256 index) returns (PreparedWithdrawal memory)
- **Parameters**: Same as `xPrepOut`.
- **Behavior**: Prepares token B withdrawal, calculates compensation in token A if there is a shortfall.
- **Internal Call Flow**:
  - Checks `yLiquid` and slot `allocation` in `yLiquiditySlots`.
  - Calculates `withdrawAmountB` as the minimum of requested `amount` and available `yLiquid`.
  - Computes `deficit` as any shortfall (`amount - withdrawAmountB`).
  - If `deficit` exists, fetches `ICCLiquidity.getPrice` to convert `deficit` to token A (`withdrawAmountA = (deficit * getPrice()) / 1e18`), capped by `xLiquid`.
  - Returns `PreparedWithdrawal` with `amountA` and `amountB`, or default if `currentPrice` is zero.
- **Balance Checks**: Verifies slot `allocation`.
- **Mappings/Structs Used**: `yLiquiditySlots`, `liquidityDetail`, `PreparedWithdrawal`, `Slot`.
- **Restrictions**: Same as `xPrepOut`.
- **Gas Usage Controls**: Same as `xPrepOut`.

#### yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal)
- **Parameters**: Same as `xExecuteOut`.
- **Behavior**: Executes token B withdrawal, transfers tokens/ETH via `transactToken` or `transactNative`.
- **Internal Call Flow**:
  - Updates `yLiquiditySlots`, `liquidityDetail` via `update`.
  - Transfers `amountB` (token B) and `amountA` (token A) using `transactToken` or `transactNative`.
  - Calls `globalizeUpdate`, `updateRegistry` for both tokens.
- **Balance Checks**: Verifies `yLiquid`, `xLiquid` in `transact*`.
- **Mappings/Structs Used**: `yLiquiditySlots`, `activeYLiquiditySlots`, `userIndex`, `liquidityDetail`, `PreparedWithdrawal`, `UpdateType`, `Slot`.
- **Restrictions**: Same as `xExecuteOut`.
- **Gas Usage Controls**: Same as `xExecuteOut`.

#### claimFees(address caller, address _listingAddress, uint256 liquidityIndex, bool isX, uint256 volume)
- **Parameters**:
  - `caller` - User address.
  - `_listingAddress` - Listing contract address.
  - `liquidityIndex` - Slot index.
  - `isX` - True for token A, false for token B.
  - `volume` - Ignored (for compatibility).
- **Behavior**: Claims fees (yFees for xSlots, xFees for ySlots), resets `dFeesAcc` to current `yFeesAcc` (xSlots) or `xFeesAcc` (ySlots).
- **Internal Call Flow**:
  - Validates listing via `ICCLiquidity.volumeBalances`.
  - Creates `FeeClaimContext` to optimize stack usage (~7 variables).
  - Calls `_processFeeClaim`, which:
    - Fetches slot data (`xLiquiditySlots` or `yLiquiditySlots`).
    - Calls `_claimFeeShare` to compute `feeShare` using `contributedFees = feesAcc - dFeesAcc` and liquidity proportion.
    - Updates `xFees`/`yFees` and slot allocation via `update`.
    - Resets `dFeesAcc` to `yFeesAcc` (xSlots) or `xFeesAcc` (ySlots).
    - Transfers fees via `transactToken`.
    - Emits `FeesClaimed` with fee amounts.
- **Balance Checks**: Verifies `xBalance` (from `volumeBalances`), `allocation`.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `yLiquiditySlots`, `liquidityDetail`.
  - **Structs**: `FeeClaimContext`, `UpdateType`, `LiquidityDetails`, `Slot`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, caller must be depositor, valid listing address.
- **Gas Usage Controls**: Single transfer, struct-based stack optimization, try-catch in `transactToken`.

#### transactToken(address caller, address token, uint256 amount, address recipient)
- **Parameters**:
  - `caller` - User address.
  - `token` - Token A or B.
  - `amount` - Denormalized amount.
- **Behavior**: Transfers ERC20 tokens, updates liquidity (`xLiquid` or `yLiquid`).
- **Internal Call Flow**:
  - Normalizes `amount` using `IERC20.decimals`.
  - Checks `xLiquid` (token A) or `yLiquid` (token B).
  - Transfers via `SafeERC20.safeTransfer`.
  - Updates `liquidityDetail`, emits `LiquidityUpdated`.
- **Balance Checks**: Pre-transfer liquidity check for `xLiquid` or `yLiquid`.
- **Mappings/Structs Used**:
  - **Mappings**: `liquidityDetail`.
  - **Structs**: `LiquidityDetails`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, valid ERC20 token.
- **Gas Usage Controls**: Single transfer, minimal state updates.

#### transactNative(address caller, uint256 amount, address recipient)
- **Parameters**:
  - `caller` - User address.
  - `amount` - Denormalized ETH amount.
  - `recipient` - Recipient address.
- **Behavior**: Transfers ETH, updates liquidity (`xLiquid` or `yLiquid`).
- **Internal Call Flow**:
  - Normalizes `amount` (18 decimals).
  - Checks `xLiquid` (tokenA=0) or `yLiquid` (tokenB=0).
  - Transfers via low-level `call`.
  - Updates `liquidityDetail`, emits `LiquidityUpdated`.
- **Balance Checks**: Pre-transfer liquidity check for `xLiquid` or `yLiquid`.
- **Mappings/Structs Used**:
  - **Mappings**: `liquidityDetail`.
  - **Structs**: `LiquidityDetails`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, one token must be ETH.
- **Gas Usage Controls**: Single transfer, minimal state updates, try-catch for `call`.

#### addFees(address caller, bool isX, uint256 fee)
- **Parameters**:
  - `caller` - User address.
  - `isX` - True for token A, false for token B.
  - `fee` - Normalized fee amount.
- **Behavior**: Adds fees to `xFees`/`yFees` and increments `xFeesAcc`/`yFeesAcc`.
- **Internal Call Flow**:
  - Increments `xFeesAcc` (isX=true) or `yFeesAcc` (isX=false).
  - Creates `UpdateType` to update `xFees` or `yFees`.
  - Calls `update`, emits `FeesUpdated`.
- **Balance Checks**: None, assumes normalized input.
- **Mappings/Structs Used**:
  - **Mappings**: `liquidityDetail`.
  - **Structs**: `UpdateType`, `LiquidityDetails`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`.
- **Gas Usage Controls**: Minimal, single update, additional `xFeesAcc`/`yFeesAcc` write.

#### updateLiquidity(address caller, bool isX, uint256 amount)
- **Parameters**:
  - `caller` - User address.
  - `isX` - True for token A, false for token B.
  - `amount` - Normalized amount.
- **Behavior**: Reduces `xLiquid` or `yLiquid` in `liquidityDetail`.
- **Internal Call Flow**:
  - Checks `xLiquid` or `yLiquid` sufficiency.
  - Updates `liquidityDetail`, emits `LiquidityUpdated`.
- **Balance Checks**: Verifies `xLiquid` or `yLiquid` sufficiency.
- **Mappings/Structs Used**:
  - **Mappings**: `liquidityDetail`.
  - **Structs**: `LiquidityDetails`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`.
- **Gas Usage Controls**: Minimal, single state update.

#### getListingAddress(uint256) view returns (address)
- **Behavior**: Returns `listingAddress`.
- **Gas Usage Controls**: Minimal, single state read.

#### liquidityAmounts() view returns (uint256 xAmount, uint256 yAmount)
- **Behavior**: Returns `xLiquid` and `yLiquid` from `liquidityDetail`.
- **Gas Usage Controls**: Minimal, single struct read.

#### liquidityDetailsView() view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, uint256 xFeesAcc, uint256 yFeesAcc)
- **Behavior**: Returns all fields of `liquidityDetail`.
- **Gas Usage Controls**: Minimal, single struct read.

#### activeXLiquiditySlotsView() view returns (uint256[] memory)
- **Behavior**: Returns `activeXLiquiditySlots` array.
- **Gas Usage Controls**: Minimal, array read.

#### activeYLiquiditySlotsView() view returns (uint256[] memory)
- **Behavior**: Returns `activeYLiquiditySlots` array.
- **Gas Usage Controls**: Minimal, array read.

#### userIndexView(address user) view returns (uint256[] memory)
- **Behavior**: Returns `userIndex[user]` array of slot indices.
- **Gas Usage Controls**: Minimal, mapping read.

#### getXSlotView(uint256 index) view returns (Slot memory)
- **Behavior**: Returns `xLiquiditySlots[index]`.
- **Gas Usage Controls**: Minimal, mapping read.

#### getYSlotView(uint256 index) view returns (Slot memory)
- **Behavior**: Returns `yLiquiditySlots[index]`.
- **Gas Usage Controls**: Minimal, mapping read.

### Additional Details
- **Decimal Handling**: Uses `normalize` and `denormalize` (1e18) for amounts, fetched via `IERC20.decimals`.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant` modifier.
- **Gas Optimization**: Dynamic array resizing, minimal external calls, struct-based stack management in `claimFees` (~7 variables).
- **Token Usage**:
  - xSlots: Provide token A liquidity, claim yFees.
  - ySlots: Provide token B liquidity, claim xFees.
- **Events**: `LiquidityUpdated`, `FeesUpdated`, `FeesClaimed`, `SlotDepositorChanged`, `GlobalizeUpdateFailed`, `UpdateRegistryFailed`, `DepositReceived`.
- **Safety**:
  - Explicit casting for interfaces (e.g., `ICCLiquidity`, `IERC20`, `ITokenRegistry`).
  - No inline assembly, uses high-level Solidity.
  - Try-catch for external calls (`transact*`, `globalizeUpdate`, `updateRegistry`, `ICCLiquidity.volumeBalances`, `ICCLiquidity.getPrice`) to handle failures.
  - Public state variables accessed via view functions (e.g., `getXSlotView`, `liquidityDetailsView`).
  - Avoids reserved keywords and unnecessary virtual/override modifiers.
- **Fee System**:
  - Cumulative fees (`xFeesAcc`, `yFeesAcc`) track total fees added, never decrease.
  - `dFeesAcc` stores `yFeesAcc` (xSlots) or `xFeesAcc` (ySlots) at deposit or last claim, reset after claim to track fees since last claim.
  - Fee share based on `contributedFees = feesAcc - dFeesAcc`, proportional to liquidity contribution, capped at available fees.
- **Compatibility**: Aligned with `CCListingTemplate` (v0.0.10), `SSAgent` (v0.0.2).
- **Caller Param**: Functionally unused in `addFees` and `updateLiquidity`, included for router validation.
