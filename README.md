## Overview
CoinClash, derived from [ShockSpace](https://github.com/Peng-Protocol/Dexhune-SS/tree/main/ShockSpace) uses Uniswap V2 for order settlement. The system introduces range/limit orders - dynamic fees - historical data, etc to Uniswap v2. 

## System Summary
CoinClash operates via `CCAgent`, to deploy `CCListingTemplate` and `CCLiquidityTemplate` contracts for unique token pairs. `CCListingTemplate` serves as the order book, enabling order creation, cancellation, and settlement via `CCOrderRouter`, `CCSettlementRouter`, and `CCLiquidRouter`. It uses Uniswap V2 for real-time pricing and partial fills, tracking historical data and balances. `CCLiquidityTemplate` manages deposits, withdrawals, fee claims, and payouts, storing liquidity details and slot data. `CCLiquidityRouter` handles deposits, partial withdrawals with compensation, and fee calculations, while `CCLiquidRouter` settles orders using liquidity balances, charging up to 1% fees. `CCGlobalizer` and `TokenRegistry` ensure cross-contract order and balance consistency. Pagination (`maxIterations`, `step`) optimizes queries, and relisting supports system upgrades.

*Pending*: The contracts listed below make up the leverage and multi-hop functionalities. They are still in testing and currently do not work. Existing functionality covers basic swaps and liquidity provision.

* ShockEntry
* ShockExit
* MultiController
* MultiInitializer 
* Multistorage 
* CCS/CISEntryDrivers 
* CCS/CISExitDrivers 
* CCS/CISExecutionDrivers 
* CCS/CISLiquidationDrivers
* CS/SIStorages

# CCAgent

## Description 
The `CCAgent` contract (Solidity ^0.8.2) manages the deployment and initialization of token pair listings and liquidity contracts. It serves as a central hub for creating and tracking token pair listings, ensuring secure deployment using CREATE2 and maintaining state for token pairs, listings, and listers.

## Key Functionality
- **Listing Management**: Deploys listing (`CCListingTemplate`) and liquidity (`CCLiquidityTemplate`) contracts via `CCListingLogic` and `CCLiquidityLogic` using `_deployPair`. Supports token-token (`listToken`) and token-native (`listNative`) pairs, with relisting (`relistToken`, `relistNative`) restricted to original listers.
- **State Tracking**: Maintains mappings (`getListing`, `getLister`, `listingsByLister`) and arrays (`allListings`, `allListedTokens`) for token pairs, listing addresses, and lister details. Updates state via `_updateState`.
- **Initialization**: Configures listing and liquidity contracts with routers, tokens, and Uniswap V2 pair via `_initializeListing` and `_initializeLiquidity`. Verifies token pairs against Uniswap V2 pair using `_verifyAndSetUniswapV2Pair`.
- **Lister Management**: Supports lister transfers (`transferLister`) and paginated queries (`getListingsByLister`, `queryByAddressView`) for listings and tokens, using `maxIterations` for gas control.
- **Validation**: Ensures valid deployments with checks for non-zero addresses, existing routers, and unique token pairs. Emits events (`ListingCreated`, `ListingRelisted`, `ListerTransferred`) for transparency.

## Interactions
- **CCListingLogic**: Deploys listing contracts via `deploy` with CREATE2, ensuring deterministic addresses. Can be updated by owner.
- **CCLiquidityLogic**: Deploys liquidity contracts similarly, linked to listings via `liquidityAddressView`. Can be updated by owner.

## Globalizer Integration
- **CCGlobalizer**: Optionally set via `setGlobalizerAddress`, enabling order and liquidity globalization. Listings call `setGlobalizerAddress` if configured, allowing cross-contract order tracking. Owner sets or resets this address. 

## Token Registry Integration
- **TokenRegistry**: Tracks token balances for users, integrated via `registryAddress`. Used by listings for balance queries, ensuring consistent token data across the system. Owner sets or resets this address. 
## Security
- Restricts critical functions (`setWETHAddress`, `setGlobalizerAddress`) to owner.
- Uses try-catch for external calls, ensuring graceful degradation.
- Validates inputs (e.g., non-zero addresses, token pair uniqueness) to prevent errors.
- Opt-in updates via relisting or router-resets ensure that the system is upgradable and secure. If routers are updated the new addresses can be pushed via `resetRouters` on the `CCListingTemplate` and `CCLiquidityTemplate`, restricted to the original lister. Globalizer and Token Registry cannot be changed on the listing template without relisting. Liquidity template fetches latest Globalizer and Token Registry from Agent. Templates can only be updated by relisting. Agent retains old pairs after relisting and continues to validate them, but `getListing` and other queries return only the latest listing. 

## Notes
- Supports pagination (`maxIterations`, `step`) for efficient queries.
- WETH address required for native ETH pairs, set via `setWETHAddress`.

# CCListingTemplate

## Description 
The `CCListingTemplate` contract (Solidity ^0.8.2) serves as the central order book. The contract ensures secure, normalized (1e18 decimals) handling of token pairs (tokenA, tokenB), with price calculations derived from Uniswap V2 pair balances. Router-only access for write functions.

## Router Interactions
- **CCOrderRouter**: Creates/cancels orders via `ccUpdate`.

- **CCSettlementRouter**: Settles orders using Uniswap v2, respects order max/min price bounds with partial fills and accounts for slippage. Fetches pending orders using; (`pendingBuyOrdersView`, `pendingSellOrdersView`) and updates order states via `ccUpdate`. 

- **CCLiquidRouter**: Settles only the caller's buy/sell orders using liquidity balances (charges a fee up to 1% depending on liquidity usage), transfers principal to liquidity template and updates liquid balances (`xLiquid`, `yLiquid`). 
Only uses listing template for fetching liquidity address via orders via `liquidityAddressView`, fetches orders using `makerPendingOrdersView` and updating order states via `ccUpdate`.

- **CCLiquidityRouter**: Manages deposits - withdrawals - fee claims - and depositor changes on liquidity contract, only uses `liquidityAddressView` on listing template. 

## Key Interactions
- **Order Management**: Tracks buy/sell orders using `makerPendingOrders`, `pendingBuyOrdersView`, and `pendingSellOrdersView`. Stores order details in `BuyOrderCore`, `BuyOrderPricing`, `BuyOrderAmounts`, `SellOrderCore`, `SellOrderPricing`, and `SellOrderAmounts`. Updates are processed via `ccUpdate` with `BuyOrderUpdate` or `SellOrderUpdate` structs, ensuring status (cancelled, pending, partially filled, filled) and amount consistency.
- **Price Calculation**: Computes real-time prices via `prices(0)`, using Uniswap V2 pair balances (`IERC20.balanceOf`) normalized to 1e18. Handles edge cases (e.g., zero balances) by returning minimal price (1).
- **Balance Tracking**: Monitors token balances (`volumeBalances`) for tokenA and tokenB, normalized for consistency, supporting real-time queries for routers.
- **Liquidity Integration**: Interfaces with `ICCLiquidityTemplate` via `liquidityAddressView` to fetch `xLiquid`, `yLiquid`, `xFees`, and `yFees`, enabling liquidity additional data queries on `CCDexlytan`.
- **Historical Data**: Maintains `HistoricalData` array and `_dayStartIndices` for tracking price, balances, and volumes at midnight timestamps, created via `ccUpdate` with `HistoricalUpdate` struct. Historical volumes are updated within `BuyOrderUpdate` or `SellOrderUpdate` using `pending` and `amountSent` changes. 
- **Security**: Restricts updates to validated routers (`routers` mapping, `routerAddressesView`) via `ICCAgent.getRouters`. Uses try-catch for external calls, emitting events (`OrderUpdated`, `BalancesUpdated`, `UpdateFailed`) for graceful degradation.
- **Token Registry and Globalizer**: Supports `TokenRegistry` for global balance storage and `Globalizer` for order globalization, ensuring cross-contract consistency.

# CCLiquidityTemplate

## Description
The `CCLiquidityTemplate` contract (Solidity ^0.8.2) manages liquidity allocations, enabling deposits, withdrawals, fee claims, and payouts.

### Router Interactions
- **CCLiquidityRouter**: Calls `ccUpdate` to adjust liquid balance (`xLiquid`/`yLiquid`) and liquidity slot data during deposit.  
  -  Calls transfer functions (`transactToken`/`transactNative`) during withdrawal, with  `ccUpdate` for liquid balance and slot data updates. 
  - Similar interactions for fee claims
  - Similar interactions for depositor changes. 
  - Fetches `liquidityAddressView`, `liquidityDetailsView`, `getXSlotView`, `getYSlotView`, `userXIndexView`, `userYIndexView`, `liquidityAmounts`, during various operations. 
  
- **CCLiquidRouter**: Similar interactions as `CCLiquidityRouter `. 
  
### Storage and Updates
- **Storage**:
  - `LiquidityDetails`: Stores `xLiquid`, `yLiquid` (liquidity amounts), `xFees`, `yFees` (accumulated fees), `xFeesAcc`, `yFeesAcc` (cumulative fee snapshots).
  - `xLiquiditySlots`, `yLiquiditySlots`: Map slot indices to `Slot` structs (`depositor`, `recipient`, `allocation`, `dFeesAcc`, `timestamp`).
  - `activeXLiquiditySlots`, `activeYLiquiditySlots`: Track active slot indices.
  - `userXIndex`, `userYIndex`: Map user addresses to their slot indices.
  - `longPayout`, `shortPayout`: Store payout details for leverage markets (`makerAddress`, `recipientAddress`, `required`, `filled`, `amountSent`, `orderId`, `status`).
  - `longPayoutByIndex`, `shortPayoutByIndex`, `activeLongPayouts`, `activeShortPayouts`, `userPayoutIDs`, `activeUserPayoutIDs`: Track payout order IDs.
  - `nextPayoutId`: Tracks next payout ID, incremted during payout creation.
  - `routers`, `routerAddresses`: Track authorized routers.
  - `listingAddress`, `tokenA`, `tokenB`, `listingId`, `agent`: Store contract configuration.
- **Updates**: Handles up to (10) update types as follows; 
    - `0`: Sets `xLiquid`/`yLiquid`.
    - `1`: Adds to `xFees`/`yFees`.
    - `2`/`3`: Updates `xSlot`/`ySlot` details (`allocation`, increases or reduces `xLiquid`/`yLiquid`, `userXIndex`/`userYIndex`).
    - `4`/`5`: Changes slot `depositor`.
    - `6`/`7`: Updates slot `dFeesAcc` (Is needed during fee claims to reset a depositor's eligible fees).
    - `8`/`9`: Subtracts from `xFees`/`yFees`.
  - Payouts are created and updated via `ssUpdate`. 
  
### Key Interactions
- **Token Registry and Globalizer**: Same as `CCListingTemplate`, but fetches addresses from `CCAgent`.
- **Security**: Same as `CCListingTemplate`.
  
# CCOrderRouter

## Description 
As seen in `CCListingTemplate`. 

## Interactions
- Segregates ERC20 token order creation; (`createTokenBuyOrder`, `createTokenSellOrder`,) from Native token order creation; (`createNativeBuyOrder`, `createNativeSellOrder`)
- Allows singular order cancelation orders (`clearSingleOrder`), distinct from bulk cancellation; (`clearOrders`). 

## Key Interactions
- **Token/ETH Transfers**: Validates ERC20 transfers and ETH transfers to `CCListingTemplate`, ensuring sufficient allowance and successful transfer before order execution.
- **Validation**: Uses `onlyValidListing` modifier to verify listing via `CCAgent`, ensuring non-zero liquidity address and distinct token pairs.
- **Payout Settlement**: Fetches active payout IDs from `CCLiquidityTemplate` using `activeLongPayoutsView` and `activeShortPayoutsView`, settles payouts using liquidity balance via `transactToken` or `transactNative`, updates liquidity balances using `ccUpdate` at `CCLiquidityTemplate`. 
- **Data Queries**: Retrieves maker orders via `makerPendingOrdersView`, order details via `getBuyOrderCore`, `getSellOrderCore`, `getBuyOrderAmounts`, `getSellOrderAmounts`, and token details via `tokenA`, `tokenB`, `decimalsA`, `decimalsB` on `CCListingTemplate`. 

## Security
- Uses `nonReentrant` modifier to prevent reentrancy.
- Peng `ReentrancyGuard` uses `reentrancyException` with `addRenterer ` and `removeReenterer` restricted to contract owner. 
- Emits `TransferFailed` for failed transfers with reasons.
- Validates inputs (maker, recipient, amount) and token types before processing.
- Ensures normalized amounts for consistency across token decimals.

# CCSettlementRouter

## Description
This is where the magic happens, As seen in `CCListingTemplate`. 

## Key Interactions
- **Order Settlement**: Iterates over pending orders using `pendingBuyOrdersView`/`pendingSellOrdersView` from CCListingTemplate. Processes orders in batches to manage state and avoid stack issues.
- **Order Validation**: Validates orders to ensure non-zero pending amounts and price compliance.
- **Balance Handling**: Uses `transactToken`/`transactNative` to pull funds, checking own balance post-transfer for tax-on-transfer tokens.
- **Update Application**: Applies updates via `ccUpdate` with `BuyOrderUpdate`/`SellOrderUpdate` structs, handling status changes (pending, partially filled, filled).
- **Historical Data**: Creates historical entries in `_createHistoricalEntry`, capturing price and volume data for analytics.
- **Pagination**: Limits processing up to `maxIterations` orders starting from `step`. E.g; if a pending orders array has (5) orders, "2,22,23,24,30", the user or frontend specifies a `step` "2" and `maxIterations` "3" this limits processing to orders "22,23,24". 
- **Security**: Uses `nonReentrant` modifier and try-catch for external calls, reverting with detailed reasons on failure. Emits no events if nonpending orders exist, relying on reverts. 
If orders exist but none are settled due to price bounds or swap failures, returns string "No orders settled: price out of range or swap failure" without emitting events or reverting, ensuring graceful degradation.
- **Partial Fills Behavior:**
Partial fills occur when the `swapAmount` is limited by `maxAmountIn`, calculated in `_computeMaxAmountIn` (CCSettlementPartial.sol) to respect price bounds and available reserves. For example, with a buy order of 100 tokenB pending, a pool of 1000 tokenA and 500 tokenB (price = 0.5 tokenA/tokenB), and price bounds (max 0.6, min 0.4), `maxAmountIn` is 50 tokenB due to price-adjusted constraints. This results in a swap of 50 tokenB for ~90.59 tokenA, updating `pending = 50`, `filled += 50`, `amountSent = 90.59` and `status = 2` (partially filled) via a single `ccUpdate` call in `_updateOrder` (CCSettlementRouter.sol). 
- **AmountSent Usage:**
`amountSent` tracks the actual tokens a recipient gets after a trade (e.g., tokenA for buy orders) in the `BuyOrderUpdate`/`SellOrderUpdate` structs.
  - **Calculation**: The system checks the recipient’s balance before and after a transfer to record `amountSent` (e.g., ~90.59 tokenA for 50 tokenB after fees).
  - **Partial Fills**: For partial trades (e.g., 50 of 100 tokenB), `amountSent` shows the tokens received each time. Is incremented for each partial fill. 
  - **Application**: Prepared in `CCUniPartial.sol` and applied via one `ccUpdate` call, updating the order’s Amounts struct.
- **Maximum Input Amount:** 
(`maxAmountIn`) ensures that the size of the swap doesn't push the execution price outside the `minPrice`/`maxPrice` boundaries set in the order.
  - **Calculate a Price-Adjusted Amount**: The system first calculates a theoretical maximum amount based on the current market price and the order's pending amount.
  - **Determine the True Maximum**: This is limited by;
    * The **`priceAdjustedAmount`**.
    * The order's actual **`pendingAmount`**.
    * The **`normalizedReserveIn`** (the total amount of the input token available in the Uniswap pool).
- **Minimum Output Amount:**
(`amountOutMin`) is used to determine the minimum output expected from the Uniswap v2 swap, as a safeguard against slippage. 
**`expectedAmountOut`** is calculated based on the current pool reserves and the size of the input amount (`denormAmountIn`) and is used directly as the value for the **`denormAmountOutMin`** parameter in the actual Uniswap `swapExactTokensForTokens` call. Slippage cannot exceed order's max/min price bounds.

# CCLiquidRouter

## Description 
As seen in `CCListingTemplate` and `CCLiquidityTemplate`.

## Key Interactions
- **Liquid Settlement**: Uses liquidity balances to settle active or pending orders, restricts settlement using impact price (as seen in `CCSettlementRouter`) for consistency. 
- **Pagination**: as seen in `CCSettlementRouter`.
- **Fee Handling**: Deducts fees (up to 1% if 100% of a liquidity balance is used). Records fees in `CCLiquidityTemplate` using `ccUpdate`. 
- **Liquidity Updates**: Transfers principal to liquidity contract and adjusts `xLiquid`/`yLiquid` using normalized amounts (1e18 decimals) to ensure consistency.
- **Historical Data**: Creates `HistoricalUpdate` entries before processing orders, capturing current `volumeBalances` and `prices(0)` from `CCListingTemplate` for accurate tracking.
- **Security**: Uses `nonReentrant` modifier to prevent reentrancy. Validates listings via `onlyValidListing` modifier.
- **Full Settlement**: Only Executes full settlement of pending or active orders, can settle orders that were previously partially settled but does not create partial settlement. 
- *Listing Balances**: The `volumeBalances` function in `CCListingTemplate` is used  to check available token balances (`xBalance`, `yBalance`) before settling orders. It ensures sufficient balances exists to process buy/sell orders without reverting due to insufficient funds. For buy orders, it verifies `yBalance` (TokenB) is adequate for the principal; for sell orders, it checks `xBalance` (TokenA). 
- *Graceful Degradation**: The system avoids reverts for non-critical failures. Such as;
1. **No Pending Orders**: If `makerPendingOrdersView` returns an empty array or `step` exceeds the array length, the contract emits a `NoPendingOrders` event and returns without reverting.
2. **Insufficient Liquidity**: If `volumeBalances` indicates zero `xBalance` (for sell orders) or `yBalance` (for buy orders), it emits an `InsufficientBalance` event and exits without processing, avoiding a revert.
3. **Invalid Pricing**: If the order's pricing (`impactPrice`) is outside `maxPrice`/`minPrice`, it emits a `PriceOutOfBounds` event, skips the order, and continues processing others, ensuring batch operations proceed.
4. **Zero Pending Amount**: If an order's `pendingAmount` is zero, `_processOrderBatch` skips it without reverting, continuing to the next order.

# CCLiquidityRouter

## Description 
As seen in `CCListingTemplate` and `CCLiquidityTemplate`. 

## Key Interactions
- **Native Handling**: The system splits Native (`depositNativeToken`) and ERC20 (`depositToken`) deposit functions. 
- **Partial Withdrawals**: The system allows a valid depositor to withdraw a part of their allocation while retaining the rest, unclaimed fees are forfeit. 
- **Compensation**: The system allows users to specify a `compensationAmount` during withdrawals,   this is the opposite token from that which the user provided. The system validates ownership and sufficient slot allocation (primary + converted compensation). *converted compensation* is gotten by converting the stated `compensationAmount` to a relative value in the allocation token. Using the current price from `CCListingTemplate` using `prices`. The system limits withdrawals to the slot allocation the user has.
- **Fee Calculation**: Elligible fees are calculated based on liquidity and volume contribution. The contract computes `contributedFees` as `x/yFeesAcc` (total lifetime fees) minus `dFeesAcc` (slot's feeAcc snapshot). The `liquidityContribution` is the slot's `allocation` divided by total liquidity (`xLiquid` or `yLiquid`). The `feeShare` is `contributedFees` multiplied by `liquidityContribution`, capped at available fees.
- **Depositor Changes**: Allows the original depositor to transfer ownership of their slot. 
- **Slot Creation**: Each deposit uses a unique slot, old slots cannot be reused. 
- **Security**: Uses `onlyValidListing` modifier for listing validation via `CCAgent` `isValidListing`. Employs `nonReentrant` to prevent reentrancy attacks. Failures trigger events for graceful degradation.
