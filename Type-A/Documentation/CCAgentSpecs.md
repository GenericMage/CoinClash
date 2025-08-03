### CCAgent - Liquidity/ListingLogic Contracts Documentation

The System comprises `CCAgent`, `CCListingLogic`, `SSLiquidityLogic`, `CCListingTemplate`, `SSLiquidityTemplate`, `CCOrderRouter`, `CCSettlementRouter`, `CCLiquidityRouter`, `CSStorage`, `CCSPositionDriver`, `CCSExecutionDriver`, `SIStorage`, `CISPositionDriver`, and `CISExecutionDriver`. Together they form an AMM Orderbook Hybrid for leverage trading on the EVM.

## CCLiquidityLogic Contract

The liquidity logic inherits `SSLiquidityTemplate` and is used by the `CCAgent` to deploy new liquidity contracts tied to listing contracts for a unique `tokenA` and `tokenB` pair.

### Mappings and Arrays

- None defined in this contract.

### State Variables

- None defined in this contract.

### Functions

#### deploy

- **Parameters**:
  - `salt` (bytes32): Unique salt for deterministic address generation.
- **Actions**:
  - Deploys a new `SSLiquidityTemplate` contract using the provided salt.
  - Uses create2 opcode via explicit casting to address for deployment.
- **Returns**:
  - `address`: Address of the newly deployed `SSLiquidityTemplate` contract.

## CCListingLogic Contract

The listing logic inherits `CCListingTemplate` and is used by the `CCAgent` to deploy new listing contracts tied to liquidity contracts for a unique `tokenA` and `tokenB` pair.

### Mappings and Arrays

- None defined in this contract.

### State Variables

- None defined in this contract.

### Functions

#### deploy

- **Parameters**:
  - `salt` (bytes32): Unique salt for deterministic address generation.
- **Actions**:
  - Deploys a new `CCListingTemplate` contract using the provided salt.
  - Uses create2 opcode via explicit casting to address for deployment.
- **Returns**:
  - `address`: Address of the newly deployed `CCListingTemplate` contract.

## CCAgent Contract

The agent manages token listings, enables the creation of unique listings and liquidities for token pairs, verifies Uniswap V2 pair tokens (handling WETH for native ETH), and arbitrates valid listings, templates, and routers.

### Structs

- **ListingDetails**: Details of a listing contract.
  - `listingAddress` (address): Listing contract address.
  - `liquidityAddress` (address): Associated liquidity contract address.
  - `tokenA` (address): First token in pair.
  - `tokenB` (address): Second token in pair.
  - `listingId` (uint256): Listing ID.

### Mappings and Arrays

- `getListing` (mapping - address => address => address): Maps `tokenA` to `tokenB` to the listing address for a trading pair.
- `allListings` (address[]): Array of all listing addresses created.
- `allListedTokens` (address[]): Array of all unique tokens listed.
- `queryByAddress` (mapping - address => uint256[]): Maps a token to an array of listing IDs involving that token.
- `getLister` (mapping - address => address): Maps listing address to the lister’s address.
- `listingsByLister` (mapping - address => uint256[]): Maps a lister to an array of their listing IDs.

### State Variables

- `routers` (address[]): Array of router contract addresses, set post-deployment via `addRouter`.
- `listingLogicAddress` (address): Address of the `CCListingLogic` contract, set post-deployment.
- `liquidityLogicAddress` (address): Address of the `SSLiquidityLogic` contract, set post-deployment.
- `registryAddress` (address): Address of the registry contract, set post-deployment.
- `listingCount` (uint256): Counter for the number of listings created, incremented per listing.
- `wethAddress` (address): Address of the WETH contract, set post-deployment via `setWETHAddress`.
- `globalizerAddress` (address): Address of the globalizer contract, set post-deployment via `setGlobalizerAddress`.

### Functions

#### Setter Functions

- **addRouter**
  - **Parameters**:
    - `router` (address): Address to add to the routers array.
  - **Actions**:
    - Requires non-zero address and that the router does not already exist.
    - Appends the router to the `routers` array.
    - Emits `RouterAdded` event.
    - Restricted to owner via `onlyOwner` modifier.
- **removeRouter**
  - **Parameters**:
    - `router` (address): Address to remove from the routers array.
  - **Actions**:
    - Requires non-zero address and that the router exists.
    - Removes the router by swapping with the last element and popping the array.
    - Emits `RouterRemoved` event.
    - Restricted to owner via `onlyOwner` modifier.
- **getRouters**
  - **Actions**:
    - Returns the current `routers` array.
  - **Returns**:
    - `address[]`: Array of all router addresses.
- **setListingLogic**
  - **Parameters**:
    - `_listingLogic` (address): Address to set as the listing logic contract.
  - **Actions**:
    - Requires non-zero address.
    - Updates `listingLogicAddress` state variable.
    - Restricted to owner via `onlyOwner` modifier.
- **setLiquidityLogic**
  - **Parameters**:
    - `_liquidityLogic` (address): Address to set as the liquidity logic contract.
  - **Actions**:
    - Requires non-zero address.
    - Updates `liquidityLogicAddress` state variable.
    - Restricted to owner via `onlyOwner` modifier.
- **setRegistry**
  - **Parameters**:
    - `_registryAddress` (address): Address to set as the registry contract.
  - **Actions**:
    - Requires non-zero address.
    - Updates `registryAddress` state variable.
    - Restricted to owner via `onlyOwner` modifier.
- **setWETHAddress**
  - **Parameters**:
    - `_wethAddress` (address): Address to set as the WETH contract.
  - **Actions**:
    - Requires non-zero address.
    - Updates `wethAddress` state variable.
    - Emits `WETHAddressSet` event.
    - Restricted to owner via `onlyOwner` modifier.
- **setGlobalizerAddress**
  - **Parameters**:
    - `_globalizerAddress` (address): Address to set as the globalizer contract.
  - **Actions**:
    - Requires non-zero address.
    - Updates `globalizerAddress` state variable.
    - Emits `GlobalizerAddressSet` event.
    - Restricted to owner via `onlyOwner` modifier.

#### Listing Functions
- **listToken**
  - **Parameters**:
    - `tokenA` (address): First token in the pair.
    - `tokenB` (address): Second token in the pair.
    - `uniswapV2Pair` (address): Uniswap V2 pair address for the token pair.
  - **Actions**:
    - Checks tokens are not identical and pair isn’t already listed.
    - Verifies at least one router, `listingLogicAddress`, `liquidityLogicAddress`, and `registryAddress` are set.
    - Calls `_deployPair` to create listing and liquidity contracts.
    - Calls `_initializeListing` to set up listing contract with `routers` array, listing ID, liquidity address, tokens, agent, registry, Uniswap V2 pair, and `globalizerAddress` if set.
    - Calls `_initializeLiquidity` to set up liquidity contract with `routers` array, listing ID, listing address, tokens, and agent.
    - Calls `_updateState` to update mappings and arrays, storing `msg.sender` as lister.
    - Emits `ListingCreated` event with lister address.
    - Increments `listingCount`.
  - **Returns**:
    - `listingAddress` (address): Address of the new listing contract.
    - `liquidityAddress` (address): Address of the new liquidity contract.
- **listNative**
  - **Parameters**:
    - `token` (address): Token to pair with native currency.
    - `isA` (bool): If true, native currency is `tokenA`; else, `tokenB`.
    - `uniswapV2Pair` (address): Uniswap V2 pair address for the token pair.
  - **Actions**:
    - Sets `nativeAddress` to `address(0)` for native currency.
    - Determines `tokenA` and `tokenB` based on `isA`.
    - Checks tokens are not identical and pair isn’t already listed.
    - Verifies at least one router, `listingLogicAddress`, `liquidityLogicAddress`, and `registryAddress` are set.
    - Calls `_deployPair` to create listing and liquidity contracts.
    - Calls `_initializeListing` to set up listing contract with `routers` array, listing ID, liquidity address, tokens, agent, registry, Uniswap V2 pair, and `globalizerAddress` if set.
    - Calls `_initializeLiquidity` to set up liquidity contract with `routers` array, listing ID, listing address, tokens, and agent.
    - Calls `_updateState` to update mappings and arrays, storing `msg.sender` as lister.
    - Emits `ListingCreated` event with lister address.
    - Increments `listingCount`.
  - **Returns**:
    - `listingAddress` (address): Address of the new listing contract.
    - `liquidityAddress` (address): Address of the new liquidity contract.
- **relistToken**
  - **Parameters**:
    - `tokenA` (address): First token in the pair.
    - `tokenB` (address): Second token in the pair.
    - `uniswapV2Pair` (address): Uniswap V2 pair address for the token pair.
  - **Actions**:
    - Checks tokens are not identical and pair is already listed.
    - Verifies `msg.sender` is the original lister via `getLister`.
    - Verifies at least one router, `listingLogicAddress`, `liquidityLogicAddress`, and `registryAddress` are set.
    - Calls `_deployPair` to create new listing and liquidity contracts.
    - Calls `_initializeListing` to set up new listing contract with `routers` array, listing ID, liquidity address, tokens, agent, registry, Uniswap V2 pair, and `globalizerAddress` if set.
    - Calls `_initializeLiquidity` to set up new liquidity contract with `routers` array, listing ID, listing address, tokens, and agent.
    - Updates `getListing`, `allListings`, `queryByAddress`, `getLister`, and `listingsByLister` with new listing address and `msg.sender` as lister.
    - Emits `ListingRelisted` event with lister address.
    - Increments `listingCount`.
  - **Returns**:
    - `newListingAddress` (address): Address of the new listing contract.
    - `newLiquidityAddress` (address): Address of the new liquidity contract.
- **relistNative**
  - **Parameters**:
    - `token` (address): Token paired with native currency.
    - `isA` (bool): If true, native currency is `tokenA`; else, `tokenB`.
    - `uniswapV2Pair` (address): Uniswap V2 pair address for the token pair.
  - **Actions**:
    - Sets `nativeAddress` to `address(0)` for native currency.
    - Determines `tokenA` and `tokenB` based on `isA`.
    - Checks tokens are not identical and pair is already listed.
    - Verifies `msg.sender` is the original lister via `getLister`.
    - Verifies at least one router, `listingLogicAddress`, `liquidityLogicAddress`, and `registryAddress` are set.
    - Calls `_deployPair` to create new listing and liquidity contracts.
    - Calls `_initializeListing` to set up new listing contract with `routers` array, listing ID, liquidity address, tokens, agent, registry, Uniswap V2 pair, and `globalizerAddress` if set.
    - Calls `_initializeLiquidity` to set up new liquidity contract with `routers` array, listing ID, listing address, tokens, and agent.
    - Updates `getListing`, `allListings`, `queryByAddress`, `getLister`, and `listingsByLister` with new listing address and `msg.sender` as lister.
    - Emits `ListingRelisted` event with lister address.
    - Increments `listingCount`.
  - **Returns**:
    - `newListingAddress` (address): Address of the new listing contract.
    - `newLiquidityAddress` (address): Address of the new liquidity contract.
- **transferLister**
  - **Parameters**:
    - `listingAddress` (address): Address of the listing to transfer lister status.
    - `newLister` (address): Address of the new lister.
  - **Actions**:
    - Verifies `msg.sender` is the current lister via `getLister`.
    - Requires non-zero `newLister` address.
    - Updates `getLister` mapping with `newLister`.
    - Retrieves `listingId` from `allListings` and appends to `listingsByLister` for `newLister`.
    - Emits `ListerTransferred` event.
- **getListingsByLister**
  - **Parameters**:
    - `lister` (address): Address of the lister to query.
    - `maxIteration` (uint256): Number of indices to return per step.
    - `step` (uint256): Pagination step.
  - **Actions**:
    - Retrieves indices from `listingsByLister` mapping.
    - Calculates start and end bounds based on `step` and `maxIteration`.
    - Returns a subset of indices for pagination.
  - **Returns**:
    - `uint256[]`: Array of listing IDs for the lister.

#### View Functions
- **isValidListing**
  - **Parameters**:
    - `listingAddress` (address): Address to check.
  - **Actions**:
    - Iterates `allListings` to find matching address.
    - If found, retrieves `tokenA` and `tokenB` via `ICCListingTemplate.getTokens`.
    - Retrieves liquidity address via `ICCListing.liquidityAddressView`.
    - Constructs `ListingDetails` struct with `listingAddress`, `liquidityAddress`, `tokenA`, `tokenB`, and `listingId`.
  - **Returns**:
    - `isValid` (bool): True if listing is valid.
    - `details` (ListingDetails): Struct with `listingAddress`, `liquidityAddress`, `tokenA`, `tokenB`, and `listingId`.
- **queryByIndex**
  - **Parameters**:
    - `index` (uint256): Index to query.
  - **Actions**:
    - Validates index is within `allListings` length.
    - Retrieves listing address from `allListings` array.
  - **Returns**:
    - `address`: Listing address at the index.
- **queryByAddressView**
  - **Parameters**:
    - `target` (address): Token to query.
    - `maxIteration` (uint256): Number of indices to return per step.
    - `step` (uint256): Pagination step.
  - **Actions**:
    - Retrieves indices from `queryByAddress` mapping.
    - Calculates start and end bounds based on `step` and `maxIteration`.
    - Returns a subset of indices for pagination.
  - **Returns**:
    - `uint256[]`: Array of listing IDs for the target token.
- **queryByAddressLength**
  - **Parameters**:
    - `target` (address): Token to query.
  - **Actions**:
    - Retrieves length of `queryByAddress` array for the target token.
  - **Returns**:
    - `uint256`: Number of listing IDs for the target token.
- **allListingsLength**
  - **Actions**:
    - Retrieves length of `allListings` array.
  - **Returns**:
    - `uint256`: Total number of listings.
- **allListedTokensLength**
  - **Actions**:
    - Retrieves length of `allListedTokens` array.
  - **Returns**:
    - `uint256`: Total number of listed tokens.

## Additional Details

- **Relisting Behavior**:
  - **Purpose**: `relistToken` and `relistNative` allow the original lister to replace a token pair listing with a new one to update routers, Uniswap V2 pair, or other configurations.
  - **Replacement**:
    - Deploys new `CCListingTemplate` and `SSLiquidityTemplate` contracts with a new `listingId`.
    - Updates `getListing`, `allListings`, `queryByAddress`, `getLister`, and `listingsByLister` with new listing address and lister.
    - Old listing remains in `allListings` but is no longer referenced in `getListing` for the token pair.
  - **User Interaction with Old Listings**:
    - Old listings remain accessible via `CCOrderRouter` functions (e.g., `createTokenBuyOrder`, `createTokenSellOrder`, `clearSingleOrder`, `executeLongPayouts`, `executeShortPayouts`, `settleLongLiquid`, `settleShortLiquid`) because `isValidListing` validates against `allListings`.
    - Users can interact with old listings by explicitly providing their addresses, allowing order creation, cancellation, or payout execution, provided sufficient liquidity and valid order states.
    - New orders for the token pair will use the new listing address via `getListing[tokenA][tokenB]`, potentially causing confusion if users interact with the old listing unintentionally.
  - **Event**: Emits `ListingRelisted` with old and new listing addresses, token pair, new `listingId`, and lister.
- **Globalizer Integration**:
  - The `globalizerAddress` is set in new listing contracts via `setGlobalizerAddress` during `_initializeListing` if defined, enabling integration with a separate globalizer contract for order and liquidity management.
- **Lister Tracking**:
  - `msg.sender` is stored as the lister in `listToken` and `listNative` via `getLister` and `listingsByLister`.
  - `transferLister` allows the current lister to transfer control to a new address, updating `getLister` and `listingsByLister`.
  - `getListingsByLister` provides paginated access to a lister’s listing IDs.