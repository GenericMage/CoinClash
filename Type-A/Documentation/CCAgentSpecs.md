# Cross Chain Contracts Documentation
The System comprises of CCAgent, CCListingLogic, SSLiquidityLogic, CCListingTemplate, SSLiquidityTemplate, CCOrderRouter, CCSettlementRouter CCLiquidityRouter, CSStorage, CCSPositionDriver, CCSExecutionDriver, SIStorage, CISPositionDriver and CISExecutionDriver. 

Together they form an AMM Orderbook Hybrid for leverage trading on the EVM.

## SSLiquidityLogic Contract
The liquidity logic inherits liquidity Template and is used by the CCAgent to deploy new liquidity contracts tied to listing contracts for a unique TokenA and TokenB pair.

### Mappings and Arrays
- None defined in this contract.

### State Variables
- None defined in this contract.

### Functions

#### deploy
- **Parameters:**
  - `salt` (bytes32): Unique salt for deterministic address generation.
- **Actions:**
  - Deploys a new SSLiquidityTemplate contract using the provided salt.
  - Uses create2 opcode via explicit casting to address for deployment.
- **Returns:**
  - `address`: Address of the newly deployed SSLiquidityTemplate contract.

## CCListingLogic Contract
The listing logic inherits CCListingTemplate and is used by the CCAgent to deploy new listing contracts tied to liquidity contracts for a unique TokenA and TokenB pair.

### Mappings and Arrays
- None defined in this contract.

### State Variables
- None defined in this contract.

### Functions

#### deploy
- **Parameters:**
  - `salt` (bytes32): Unique salt for deterministic address generation.
- **Actions:**
  - Deploys a new CCListingTemplate contract using the provided salt.
  - Uses create2 opcode via explicit casting to address for deployment.
- **Returns:**
  - `address`: Address of the newly deployed CCListingTemplate contract.

## CCAgent Contract
The agent manages token listings and global data, enables the creation of unique listings and liquidities for token pairs, verifies Uniswap V2 pair tokens (handling WETH for native ETH), and arbitrates valid listings, templates, and routers.

### Structs
- **GlobalOrder**: Stores order details for a token pair.
  - `orderId` (uint256): Unique order identifier.
  - `isBuy` (bool): True for buy order, false for sell.
  - `maker` (address): Address creating the order.
  - `recipient` (address): Address receiving the order outcome.
  - `amount` (uint256): Order amount.
  - `status` (uint8): Order status (0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled).
  - `timestamp` (uint256): Timestamp of order creation or update.
- **TrendData**: Used for sorting liquidity or volume data.
  - `token` (address): Token or user address for sorting.
  - `timestamp` (uint256): Timestamp of data point.
  - `amount` (uint256): Amount for liquidity or volume.
- **OrderData**: Details of an order for reporting.
  - `orderId` (uint256): Order identifier.
  - `isBuy` (bool): True for buy order, false for sell.
  - `maker` (address): Order creator.
  - `recipient` (address): Order recipient.
  - `amount` (uint256): Order amount.
  - `status` (uint8): Order status.
  - `timestamp` (uint256): Order timestamp.
- **ListingDetails**: Details of a listing contract.
  - `listingAddress` (address): Listing contract address.
  - `liquidityAddress` (address): Associated liquidity contract address.
  - `tokenA` (address): First token in pair.
  - `tokenB` (address): Second token in pair.
  - `listingId` (uint256): Listing ID.

### Mappings and Arrays
- `getListing` (mapping - address, address, address): Maps tokenA to tokenB to the listing address for a trading pair.
- `allListings` (address[]): Array of all listing addresses created.
- `allListedTokens` (address[]): Array of all unique tokens listed.
- `queryByAddress` (mapping - address, uint256[]): Maps a token to an array of listing IDs involving that token.
- `globalLiquidity` (mapping - address, address, address, uint256): Tracks liquidity per user for each tokenA-tokenB pair.
- `totalLiquidityPerPair` (mapping - address, address, uint256): Total liquidity for each tokenA-tokenB pair.
- `userTotalLiquidity` (mapping - address, uint256): Total liquidity contributed by each user across all pairs.
- `listingLiquidity` (mapping - uint256, address, uint256): Liquidity per user for each listing ID.
- `liquidityProviders` (mapping - uint256, address[]): Maps listing ID to an array of users who provided liquidity.
- `historicalLiquidityPerPair` (mapping - address, address, uint256, uint256): Historical liquidity for each tokenA-tokenB pair at specific timestamps.
- `historicalLiquidityPerUser` (mapping - address, address, address, uint256, uint256): Historical liquidity per user for each tokenA-tokenB pair at specific timestamps.
- `globalOrders` (mapping - address, address, uint256, GlobalOrder): Stores order details for each tokenA-tokenB pair by order ID.
- `pairOrders` (mapping - address, address, uint256[]): Array of order IDs for each tokenA-tokenB pair.
- `userOrders` (mapping - address, uint256[]): Array of order IDs created by each user.
- `historicalOrderStatus` (mapping - address, address, uint256, uint256, uint8): Historical status of orders for each tokenA-tokenB pair at specific timestamps.
- `userTradingSummaries` (mapping - address, address, address, uint256): Trading volume per user for each tokenA-tokenB pair.

### State Variables
- `routers` (address[]): Array of router contract addresses, set post-deployment via addRouter.
- `listingLogicAddress` (address): Address of the CCListingLogic contract, set post-deployment.
- `liquidityLogicAddress` (address): Address of the SSLiquidityLogic contract, set post-deployment.
- `registryAddress` (address): Address of the registry contract, set post-deployment.
- `listingCount` (uint256): Counter for the number of listings created, incremented per listing.
- `wethAddress` (address): Address of the WETH contract, set post-deployment via setWETHAddress.

### Functions

#### Setter Functions
- **addRouter**
  - **Parameters:**
    - `router` (address): Address to add to the routers array.
  - **Actions:**
    - Requires non-zero address and that the router does not already exist.
    - Appends the router to the routers array.
    - Emits RouterAdded event.
    - Restricted to owner via onlyOwner modifier.
- **removeRouter**
  - **Parameters:**
    - `router` (address): Address to remove from the routers array.
  - **Actions:**
    - Requires non-zero address and that the router exists.
    - Removes the router by swapping with the last element and popping the array.
    - Emits RouterRemoved event.
    - Restricted to owner via onlyOwner modifier.
- **getRouters**
  - **Actions:**
    - Returns the current routers array.
  - **Returns:**
    - `address[]`: Array of all router addresses.
- **setListingLogic**
  - **Parameters:**
    - `_listingLogic` (address): Address to set as the listing logic contract.
  - **Actions:**
    - Requires non-zero address.
    - Updates listingLogicAddress state variable.
    - Restricted to owner via onlyOwner modifier.
- **setLiquidityLogic**
  - **Parameters:**
    - `_liquidityLogic` (address): Address to set as the liquidity logic contract.
  - **Actions:**
    - Requires non-zero address.
    - Updates liquidityLogicAddress state variable.
    - Restricted to owner via onlyOwner modifier.
- **setRegistry**
  - **Parameters:**
    - `_registryAddress` (address): Address to set as the registry contract.
  - **Actions:**
    - Requires non-zero address.
    - Updates registryAddress state variable.
    - Restricted to owner via onlyOwner modifier.
- **setWETHAddress**
  - **Parameters:**
    - `_wethAddress` (address): Address to set as the WETH contract.
  - **Actions:**
    - Requires non-zero address.
    - Updates wethAddress state variable.
    - Emits WETHAddressSet event.
    - Restricted to owner via onlyOwner modifier.

#### Listing Functions
- **listToken**
  - **Parameters:**
    - `tokenA` (address): First token in the pair.
    - `tokenB` (address): Second token in the pair.
    - `uniswapV2Pair` (address): Uniswap V2 pair address for the token pair.
  - **Actions:**
    - Checks tokens are not identical and pair isn’t already listed.
    - Verifies at least one router, listingLogicAddress, liquidityLogicAddress, and registryAddress are set.
    - Calls _deployPair to create listing and liquidity contracts.
    - Calls _initializeListing to set up listing contract with routers array, listing ID, liquidity address, tokens, agent, registry, and verifies tokenA/tokenB against uniswapV2Pair tokens, then sets uniswapV2Pair.
    - Calls _initializeLiquidity to set up liquidity contract with routers array, listing ID, listing address, tokens, and agent.
    - Calls _updateState to update mappings and arrays.
    - Emits ListingCreated event.
    - Increments listingCount.
  - **Returns:**
    - `listingAddress` (address): Address of the new listing contract.
    - `liquidityAddress` (address): Address of the new liquidity contract.
- **listNative**
  - **Parameters:**
    - `token` (address): Token to pair with native currency.
    - `isA` (bool): If true, native currency is tokenA; else, tokenB.
    - `uniswapV2Pair` (address): Uniswap V2 pair address for the token pair.
  - **Actions:**
    - Sets nativeAddress to address(0) for native currency.
    - Determines tokenA and tokenB based on isA.
    - Checks tokens are not identical and pair isn’t already listed.
    - Verifies at least one router, listingLogicAddress, liquidityLogicAddress, and registryAddress are set.
    - Calls _deployPair to create listing and liquidity contracts.
    - Calls _initializeListing to set up listing contract with routers array, listing ID, liquidity address, tokens, agent, registry, and verifies tokenA/tokenB against uniswapV2Pair tokens (replacing address(0) with wethAddress for verification), then sets uniswapV2Pair.
    - Calls _initializeLiquidity to set up liquidity contract with routers array, listing ID, listing address, tokens, and agent.
    - Calls _updateState to update mappings and arrays.
    - Emits ListingCreated event.
    - Increments listingCount.
  - **Returns:**
    - `listingAddress` (address): Address of the new listing contract.
    - `liquidityAddress` (address): Address of the new liquidity contract.
- **relistToken**
  - **Parameters:**
    - `tokenA` (address): First token in the pair.
    - `tokenB` (address): Second token in the pair.
    - `uniswapV2Pair` (address): Uniswap V2 pair address for the token pair.
  - **Actions:**
    - Checks tokens are not identical and pair is already listed.
    - Verifies at least one router, listingLogicAddress, liquidityLogicAddress, and registryAddress are set.
    - Calls _deployPair to create new listing and liquidity contracts.
    - Calls _initializeListing to set up new listing contract with routers array, listing ID, liquidity address, tokens, agent, registry, and verifies tokenA/tokenB against uniswapV2Pair tokens, then sets uniswapV2Pair.
    - Calls _initializeLiquidity to set up new liquidity contract with routers array, listing ID, listing address, tokens, and agent.
    - Updates getListing, allListings, and queryByAddress mappings and arrays with new listing address.
    - Emits ListingRelisted event.
    - Increments listingCount.
    - Restricted to owner via onlyOwner modifier.
  - **Returns:**
    - `newListingAddress` (address): Address of the new listing contract.
    - `newLiquidityAddress` (address): Address of the new liquidity contract.
- **relistNative**
  - **Parameters:**
    - `token` (address): Token paired with native currency.
    - `isA` (bool): If true, native currency is tokenA; else, tokenB.
    - `uniswapV2Pair` (address): Uniswap V2 pair address for the token pair.
  - **Actions:**
    - Sets nativeAddress to address(0) for native currency.
    - Determines tokenA and tokenB based on isA.
    - Checks tokens are not identical and pair is already listed.
    - Verifies at least one router, listingLogicAddress, liquidityLogicAddress, and registryAddress are set.
    - Calls _deployPair to create new listing and liquidity contracts.
    - Calls _initializeListing to set up new listing contract with routers array, listing ID, liquidity address, tokens, agent, registry, and verifies tokenA/tokenB against uniswapV2Pair tokens (replacing address(0) with wethAddress for verification), then sets uniswapV2Pair.
    - Calls _initializeLiquidity to set up new liquidity contract with routers array, listing ID, listing address, tokens, and agent.
    - Updates getListing, allListings, and queryByAddress mappings and arrays with new listing address.
    - Emits ListingRelisted event.
    - Increments listingCount.
    - Restricted to owner via onlyOwner modifier.
  - **Returns:**
    - `newListingAddress` (address): Address of the new listing contract.
    - `newLiquidityAddress` (address): Address of the new liquidity contract.

#### Liquidity Management Functions
- **globalizeLiquidity**
  - **Parameters:**
    - `listingId` (uint256): ID of the listing.
    - `tokenA` (address): First token in the pair.
    - `tokenB` (address): Second token in the pair.
    - `user` (address): User providing or removing liquidity.
    - `amount` (uint256): Liquidity amount to add or remove.
    - `isDeposit` (bool): True for deposit, false for withdrawal.
  - **Actions:**
    - Validates non-zero tokens, user, and valid listingId.
    - Retrieves listing address from caller (liquidity contract) via ISSLiquidityTemplate.
    - Verifies listing validity and details via isValidListing.
    - Confirms caller is the associated liquidity contract.
    - Calls _updateGlobalLiquidity to adjust liquidity mappings.
    - Emits GlobalLiquidityChanged event.
- **_updateGlobalLiquidity** (Internal)
  - **Parameters:**
    - `listingId` (uint256): ID of the listing.
    - `tokenA` (address): First token in the pair.
    - `tokenB` (address): Second token in the pair.
    - `user` (address): User providing or removing liquidity.
    - `amount` (uint256): Liquidity amount to add or remove.
    - `isDeposit` (bool): True for deposit, false for withdrawal.
  - **Actions:**
    - If isDeposit, adds amount to globalLiquidity, totalLiquidityPerPair, userTotalLiquidity, and listingLiquidity, and appends user to liquidityProviders if their liquidity was previously zero.
    - If not isDeposit, checks sufficient liquidity, then subtracts amount from mappings.
    - Updates historicalLiquidityPerPair and historicalLiquidityPerUser with current timestamp.
    - Emits GlobalLiquidityChanged event.

#### Order Management Functions
- **globalizeOrders**
  - **Parameters:**
    - `listingId` (uint256): ID of the listing.
    - `tokenA` (address): First token in the pair.
    - `tokenB` (address): Second token in the pair.
    - `orderId` (uint256): Unique order identifier.
    - `isBuy` (bool): True if buy order, false if sell.
    - `maker` (address): Address creating the order.
    - `recipient` (address): Address receiving the order outcome.
    - `amount` (uint256): Order amount.
    - `status` (uint8): Order status (0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled).
  - **Actions:**
    - Validates non-zero tokens, maker, and valid listingId.
    - Checks caller is the listing contract via getListing.
    - If new order (maker is zero and status not cancelled), initializes GlobalOrder struct and adds orderId to pairOrders and userOrders.
    - If existing order, updates amount, status, and timestamp.
    - Updates historicalOrderStatus with current timestamp.
    - Adds amount to userTradingSummaries if non-zero.
    - Emits GlobalOrderChanged event.

#### View Functions
- **isValidListing**
  - **Parameters:**
    - `listingAddress` (address): Address to check.
  - **Actions:**
    - Iterates allListings to find matching address.
    - If found, retrieves tokenA and tokenB via ICCListingTemplate.getTokens.
    - Retrieves liquidity address via ICCListing.liquidityAddressView.
    - Constructs ListingDetails struct with listingAddress, liquidityAddress, tokenA, tokenB, and listingId.
  - **Returns:**
    - `isValid` (bool): True if listing is valid.
    - `details` (ListingDetails): Struct with listingAddress, liquidityAddress, tokenA, tokenB, and listingId.
- **getPairLiquidityTrend**
  - **Parameters:**
    - `tokenA` (address): Token to focus on.
    - `focusOnTokenA` (bool): If true, tracks tokenA liquidity; else, tokenB.
    - `startTime` (uint256): Start timestamp for trend.
    - `endTime` (uint256): End timestamp for trend.
  - **Actions:**
    - Validates time range and non-zero tokenA.
    - If focusOnTokenA, checks historicalLiquidityPerPair for tokenA with first listed token.
    - Else, checks all tokenB pairings with tokenA.
    - Collects non-zero amounts into TrendData array.
    - Returns timestamps and amounts arrays.
  - **Returns:**
    - `timestamps` (uint256[]): Timestamps with liquidity changes.
    - `amounts` (uint256[]): Corresponding liquidity amounts.
- **getUserLiquidityTrend**
  - **Parameters:**
    - `user` (address): User to track.
    - `focusOnTokenA` (bool): If true, tracks tokenA; else, tokenB.
    - `startTime` (uint256): Start timestamp for trend.
    - `endTime` (uint256): End timestamp for trend.
  - **Actions:**
    - Validates time range and non-zero user.
    - Iterates allListedTokens, checks historicalLiquidityPerUser for non-zero amounts.
    - Collects data into TrendData array.
    - Returns tokens, timestamps, and amounts arrays.
  - **Returns:**
    - `tokens` (address[]): Tokens involved in liquidity.
    - `timestamps` (uint256[]): Timestamps with liquidity changes.
    - `amounts` (uint256[]): Corresponding liquidity amounts.
- **getUserLiquidityAcrossPairs**
  - **Parameters:**
    - `user` (address): User to track.
    - `maxIterations` (uint256): Maximum pairs to check.
  - **Actions:**
    - Validates non-zero maxIterations.
    - Limits pairs to maxIterations or allListedTokens length.
    - Iterates allListedTokens, collects non-zero globalLiquidity amounts.
    - Returns tokenAs, tokenBs, and amounts arrays.
  - **Returns:**
    - `tokenAs` (address[]): First tokens in pairs.
    - `tokenBs` (address[]): Second tokens in pairs.
    - `amounts` (uint256[]): Liquidity amounts.
- **getTopLiquidityProviders**
  - **Parameters:**
    - `listingId` (uint256): Listing ID to analyze.
    - `maxIterations` (uint256): Maximum users to return.
  - **Actions:**
    - Validates non-zero maxIterations and valid listingId.
    - Limits to maxIterations or liquidityProviders length for the listing.
    - Collects non-zero listingLiquidity amounts into TrendData array.
    - Sorts in descending order via _sortDescending.
    - Returns users and amounts arrays.
  - **Returns:**
    - `users` (address[]): Top liquidity providers.
    - `amounts` (uint256[]): Corresponding liquidity amounts.
- **getUserLiquidityShare**
  - **Parameters:**
    - `user` (address): User to check.
    - `tokenA` (address): First token in pair.
    - `tokenB` (address): Second token in pair.
  - **Actions:**
    - Retrieves total liquidity for the pair from totalLiquidityPerPair.
    - Gets user’s liquidity from globalLiquidity.
    - Calculates share as (userAmount * 1e18) / total if total is non-zero.
  - **Returns:**
    - `share` (uint256): User’s share of liquidity (scaled by 1e18).
    - `total` (uint256): Total liquidity for the pair.
- **getAllPairsByLiquidity**
  - **Parameters:**
    - `minLiquidity` (uint256): Minimum liquidity threshold.
    - `focusOnTokenA` (bool): If true, focuses on tokenA; else, tokenB.
    - `maxIterations` (uint256): Maximum pairs to return.
  - **Actions:**
    - Validates non-zero maxIterations.
    - Limits to maxIterations or allListedTokens length.
    - Collects pairs with totalLiquidityPerPair >= minLiquidity into TrendData array.
    - Returns tokenAs, tokenBs, and amounts arrays.
  - **Returns:**
    - `tokenAs` (address[]): First tokens in pairs.
    - `tokenBs` (address[]): Second tokens in pairs.
    - `amounts` (uint256[]): Liquidity amounts.
- **getOrderActivityByPair**
  - **Parameters:**
    - `tokenA` (address): First token in pair.
    - `tokenB` (address): Second token in pair.
    - `startTime` (uint256): Start timestamp for activity.
    - `endTime` (uint256): End timestamp for activity.
  - **Actions:**
    - Validates time range and non-zero tokens.
    - Retrieves order IDs from pairOrders.
    - Filters globalOrders by timestamp range, constructs OrderData array.
    - Returns orderIds and orders arrays.
  - **Returns:**
    - `orderIds` (uint256[]): IDs of orders in the range.
    - `orders` (OrderData[]): Array of order details.
- **getUserTradingProfile**
  - **Parameters:**
    - `user` (address): User to profile.
  - **Actions:**
    - Iterates allListedTokens, collects non-zero trading volumes from userTradingSummaries.
    - Returns tokenAs, tokenBs, and volumes arrays.
  - **Returns:**
    - `tokenAs` (address[]): First tokens in pairs.
    - `tokenBs` (address[]): Second tokens in pairs.
    - `volumes` (uint256[]): Trading volumes.
- **getTopTradersByVolume**
  - **Parameters:**
    - `listingId` (uint256): Listing ID to analyze.
    - `maxIterations` (uint256): Maximum traders to return.
  - **Actions:**
    - Validates non-zero maxIterations.
    - Limits to maxIterations or allListings length.
    - Identifies tokenA for each listing, collects non-zero trading volumes from userTradingSummaries.
    - Sorts in descending order via _sortDescending.
    - Returns traders and volumes arrays.
  - **Returns:**
    - `traders` (address[]): Top traders.
    - `volumes` (uint256[]): Corresponding trading volumes.
- **getAllPairsByOrderVolume**
  - **Parameters:**
    - `minVolume` (uint256): Minimum order volume threshold.
    - `focusOnTokenA` (bool): If true, focuses on tokenA; else, tokenB.
    - `maxIterations` (uint256): Maximum pairs to return.
  - **Actions:**
    - Validates non-zero maxIterations.
    - Limits to maxIterations or allListedTokens length.
    - Calculates total volume per pair from globalOrders via pairOrders.
    - Collects pairs with volume >= minVolume into TrendData array.
    - Returns tokenAs, tokenBs, and volumes arrays.
  - **Returns:**
    - `tokenAs` (address[]): First tokens in pairs.
    - `tokenBs` (address[]): Second tokens in pairs.
    - `volumes` (uint256[]): Order volumes.
- **queryByIndex**
  - **Parameters:**
    - `index` (uint256): Index to query.
  - **Actions:**
    - Validates index is within allListings length.
    - Retrieves listing address from allListings array.
  - **Returns:**
    - `address`: Listing address at the index.
- **queryByAddressView**
  - **Parameters:**
    - `target` (address): Token to query.
    - `maxIteration` (uint256): Number of indices to return per step.
    - `step` (uint256): Pagination step.
  - **Actions:**
    - Retrieves indices from queryByAddress mapping.
    - Calculates start and end bounds based on step and maxIteration.
    - Returns a subset of indices for pagination.
  - **Returns:**
    - `uint256[]`: Array of listing IDs for the target token.
- **queryByAddressLength**
  - **Parameters:**
    - `target` (address): Token to query.
  - **Actions:**
    - Retrieves length of queryByAddress array for the target token.
  - **Returns:**
    - `uint256`: Number of listing IDs for the target token.
- **allListingsLength**
  - **Actions:**
    - Retrieves length of allListings array.
  - **Returns:**
    - `uint256`: Total number of listings.
- **allListedTokensLength**
  - **Actions:**
    - Retrieves length of allListedTokens array.
  - **Returns:**
    - `uint256`: Total number of listed tokens.

# **Additional Details**

- **Relisting Behavior**:
- Purpose : `relistToken` and `relistNative` allow the admin/owner to replace a token pair listing with a new one to update routers or Uniswap V2 pair.

- Replacement : 
  - Deploys new `CCListingTemplate` and `SSLiquidityTemplate` contracts with a new `listingId`.
  - Updates `getListing` mapping with the new listing address, appends to `allListings`, and adds `listingId` to `queryByAddress`.
  - Old listing remains on-chain but is no longer referenced in `getListing`.
- Data Impact: 
  - Liquidity and orders tied to the old listing are not transferred; users must interact with the new listing.
  - Historical data (`historicalLiquidityPerPair`, `historicalLiquidityPerUser`, `historicalOrderStatus`) is preserved.
- **Event**: Emits `ListingRelisted` with old and new listing addresses, token pair, and new `listingId`.
