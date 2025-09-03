// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.2
// Changes:
// - v0.1.2: Fixed undeclared uniswapV2Pair in _initializeListing by adding parameter. Removed redundant getLister view function due to public mapping.
// - v0.1.1: Added lister tracking in listToken/listNative, restricted relistToken/relistNative to lister, removed owner-only restriction, added getLister, transferLister, and getListingsByLister functions.
// - v0.1.0: Added setGlobalizerAddress to ICCListingTemplate interface and updated _initializeListing to call setGlobalizerAddress if globalizerAddress is set.

import "./imports/Ownable.sol";

interface ICCListingTemplate {
    function setRouters(address[] memory _routers) external;
    function setListingId(uint256 _listingId) external;
    function setLiquidityAddress(address _liquidityAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setAgent(address _agent) external;
    function setRegistry(address _registryAddress) external;
    function setUniswapV2Pair(address _uniswapV2Pair) external;
    function setGlobalizerAddress(address globalizerAddress_) external;
    function getTokens() external view returns (address tokenA, address tokenB);
}

interface ISSLiquidityTemplate {
    function setRouters(address[] memory _routers) external;
    function setListingId(uint256 _listingId) external;
    function setListingAddress(address _listingAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setAgent(address _agent) external;
}

interface ICCListingLogic {
    function deploy(bytes32 salt) external returns (address);
}

interface ISSLiquidityLogic {
    function deploy(bytes32 salt) external returns (address);
}

interface ICCListing {
    function liquidityAddressView() external view returns (address);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

contract CCAgent is Ownable {
    address[] public routers; // Array of router contract addresses
    address public listingLogicAddress; // CCListingLogic contract address
    address public liquidityLogicAddress; // CCLiquidityLogic contract address
    address public registryAddress; // Registry contract address
    uint256 public listingCount; // Counter for total listings created
    address public wethAddress; // WETH contract address
    address public globalizerAddress; // Address for globalizer contract

    mapping(address tokenA => mapping(address tokenB => address listingAddress)) public getListing; // tokenA => tokenB => listing address
    address[] private allListings; // Array of all listing addresses
    address[] private allListedTokens; // Array of all unique listed tokens
    mapping(address => uint256[]) private queryByAddress; // token => listing IDs
    mapping(address listingAddress  => address lister) public getLister; // listingAddress => lister address
    mapping(address => uint256[]) private listingsByLister; // lister => listing IDs

    struct ListingDetails {
        address listingAddress; // Listing contract address
        address liquidityAddress; // Associated liquidity contract address
        address tokenA; // First token in pair
        address tokenB; // Second token in pair
        uint256 listingId; // Listing ID
    }

    event ListingCreated(address indexed tokenA, address indexed tokenB, address listingAddress, address liquidityAddress, uint256 listingId, address indexed lister);
    event RouterAdded(address indexed router); // Emitted when a router is added
    event RouterRemoved(address indexed router); // Emitted when a router is removed
    event WETHAddressSet(address indexed weth); // Emitted when WETH address is set
    event ListingRelisted(address indexed tokenA, address indexed tokenB, address oldListingAddress, address newListingAddress, uint256 listingId, address indexed lister);
    event GlobalizerAddressSet(address indexed globalizer); // Emitted when globalizer address is set
    event ListerTransferred(address indexed listingAddress, address indexed oldLister, address indexed newLister);

    // Sets WETH contract address, restricted to owner
    function setWETHAddress(address _wethAddress) external onlyOwner {
        require(_wethAddress != address(0), "Invalid WETH address");
        wethAddress = _wethAddress;
        emit WETHAddressSet(_wethAddress);
    }

    // Sets globalizer contract address, restricted to owner
    function setGlobalizerAddress(address _globalizerAddress) external onlyOwner {
        require(_globalizerAddress != address(0), "Invalid globalizer address");
        globalizerAddress = _globalizerAddress;
        emit GlobalizerAddressSet(_globalizerAddress);
    }

    // Checks if a token exists in allListedTokens
    function tokenExists(address token) internal view returns (bool) {
        for (uint256 i = 0; i < allListedTokens.length; i++) {
            if (allListedTokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    // Checks if a router exists in the routers array
    function routerExists(address router) internal view returns (bool) {
        for (uint256 i = 0; i < routers.length; i++) {
            if (routers[i] == router) {
                return true;
            }
        }
        return false;
    }

    // Verifies tokenA and tokenB match Uniswap V2 pair tokens, handling WETH for native ETH
    function _verifyAndSetUniswapV2Pair(address listingAddress, address tokenA, address tokenB, address uniswapV2Pair) internal {
        require(uniswapV2Pair != address(0), "Invalid Uniswap V2 pair address");
        require(wethAddress != address(0), "WETH address not set");
        address pairToken0 = IUniswapV2Pair(uniswapV2Pair).token0();
        address pairToken1 = IUniswapV2Pair(uniswapV2Pair).token1();
        address verifyTokenA = tokenA == address(0) ? wethAddress : tokenA;
        address verifyTokenB = tokenB == address(0) ? wethAddress : tokenB;
        bool isTokenAMatch = (verifyTokenA == pairToken0 && verifyTokenB == pairToken1) || (verifyTokenA == pairToken1 && verifyTokenB == pairToken0);
        require(isTokenAMatch, "Tokens do not match Uniswap V2 pair");
        ICCListingTemplate(listingAddress).setUniswapV2Pair(uniswapV2Pair);
    }

    // Deploys listing and liquidity contracts using create2 with provided salt
    function _deployPair(address tokenA, address tokenB, uint256 listingId) internal returns (address listingAddress, address liquidityAddress) {
        bytes32 listingSalt = keccak256(abi.encodePacked(tokenA, tokenB, listingId));
        bytes32 liquiditySalt = keccak256(abi.encodePacked(tokenB, tokenA, listingId));
        listingAddress = ICCListingLogic(listingLogicAddress).deploy(listingSalt);
        liquidityAddress = ISSLiquidityLogic(liquidityLogicAddress).deploy(liquiditySalt);
        return (listingAddress, liquidityAddress);
    }

    // Initializes listing contract with routers, listing ID, liquidity address, tokens, agent, registry, Uniswap V2 pair, and globalizer
    function _initializeListing(address listingAddress, address liquidityAddress, address tokenA, address tokenB, uint256 listingId, address uniswapV2Pair) internal {
        ICCListingTemplate(listingAddress).setRouters(routers);
        ICCListingTemplate(listingAddress).setListingId(listingId);
        ICCListingTemplate(listingAddress).setLiquidityAddress(liquidityAddress);
        ICCListingTemplate(listingAddress).setTokens(tokenA, tokenB);
        ICCListingTemplate(listingAddress).setAgent(address(this));
        ICCListingTemplate(listingAddress).setRegistry(registryAddress);
        _verifyAndSetUniswapV2Pair(listingAddress, tokenA, tokenB, uniswapV2Pair);
        if (globalizerAddress != address(0)) {
            ICCListingTemplate(listingAddress).setGlobalizerAddress(globalizerAddress);
        }
    }

    // Initializes liquidity contract with routers, listing ID, listing address, tokens, and agent
    function _initializeLiquidity(address listingAddress, address liquidityAddress, address tokenA, address tokenB, uint256 listingId) internal {
        ISSLiquidityTemplate(liquidityAddress).setRouters(routers);
        ISSLiquidityTemplate(liquidityAddress).setListingId(listingId);
        ISSLiquidityTemplate(liquidityAddress).setListingAddress(listingAddress);
        ISSLiquidityTemplate(liquidityAddress).setTokens(tokenA, tokenB);
        ISSLiquidityTemplate(liquidityAddress).setAgent(address(this));
    }

    // Updates state mappings and arrays for new listing
    function _updateState(address tokenA, address tokenB, address listingAddress, uint256 listingId, address lister) internal {
        getListing[tokenA][tokenB] = listingAddress;
        allListings.push(listingAddress);
        if (!tokenExists(tokenA)) allListedTokens.push(tokenA);
        if (!tokenExists(tokenB)) allListedTokens.push(tokenB);
        queryByAddress[tokenA].push(listingId);
        queryByAddress[tokenB].push(listingId);
        getLister[listingAddress] = lister;
        listingsByLister[lister].push(listingId);
    }

    // Adds a router address to the routers array, restricted to owner
    function addRouter(address router) external onlyOwner {
        require(router != address(0), "Invalid router address");
        require(!routerExists(router), "Router already exists");
        routers.push(router);
        emit RouterAdded(router);
    }

    // Removes a router address from the routers array, restricted to owner
    function removeRouter(address router) external onlyOwner {
        require(router != address(0), "Invalid router address");
        require(routerExists(router), "Router does not exist");
        for (uint256 i = 0; i < routers.length; i++) {
            if (routers[i] == router) {
                routers[i] = routers[routers.length - 1];
                routers.pop();
                break;
            }
        }
        emit RouterRemoved(router);
    }

    // Returns the current list of routers
    function getRouters() external view returns (address[] memory) {
        return routers;
    }

    // Sets listing logic contract address, restricted to owner
    function setListingLogic(address _listingLogic) external onlyOwner {
        require(_listingLogic != address(0), "Invalid logic address");
        listingLogicAddress = _listingLogic;
    }

    // Sets liquidity logic contract address, restricted to owner
    function setLiquidityLogic(address _liquidityLogic) external onlyOwner {
        require(_liquidityLogic != address(0), "Invalid logic address");
        liquidityLogicAddress = _liquidityLogic;
    }

    // Sets registry contract address, restricted to owner
    function setRegistry(address _registryAddress) external onlyOwner {
        require(_registryAddress != address(0), "Invalid registry address");
        registryAddress = _registryAddress;
    }

    // Lists a new token pair, deploying listing and liquidity contracts, stores msg.sender as lister
    function listToken(address tokenA, address tokenB, address uniswapV2Pair) external returns (address listingAddress, address liquidityAddress) {
        require(tokenA != tokenB, "Identical tokens");
        require(getListing[tokenA][tokenB] == address(0), "Pair already listed");
        require(routers.length > 0, "No routers set");
        require(listingLogicAddress != address(0), "Listing logic not set");
        require(liquidityLogicAddress != address(0), "Liquidity logic not set");
        require(registryAddress != address(0), "Registry not set");

        (listingAddress, liquidityAddress) = _deployPair(tokenA, tokenB, listingCount);
        _initializeListing(listingAddress, liquidityAddress, tokenA, tokenB, listingCount, uniswapV2Pair);
        _initializeLiquidity(listingAddress, liquidityAddress, tokenA, tokenB, listingCount);
        _updateState(tokenA, tokenB, listingAddress, listingCount, msg.sender);

        emit ListingCreated(tokenA, tokenB, listingAddress, liquidityAddress, listingCount, msg.sender);
        listingCount++;
        return (listingAddress, liquidityAddress);
    }

    // Lists a token paired with native currency, stores msg.sender as lister
    function listNative(address token, bool isA, address uniswapV2Pair) external returns (address listingAddress, address liquidityAddress) {
        address nativeAddress = address(0);
        address tokenA = isA ? nativeAddress : token;
        address tokenB = isA ? token : nativeAddress;

        require(tokenA != tokenB, "Identical tokens");
        require(getListing[tokenA][tokenB] == address(0), "Pair already listed");
        require(routers.length > 0, "No routers set");
        require(listingLogicAddress != address(0), "Listing logic not set");
        require(liquidityLogicAddress != address(0), "Liquidity logic not set");
        require(registryAddress != address(0), "Registry not set");

        (listingAddress, liquidityAddress) = _deployPair(tokenA, tokenB, listingCount);
        _initializeListing(listingAddress, liquidityAddress, tokenA, tokenB, listingCount, uniswapV2Pair);
        _initializeLiquidity(listingAddress, liquidityAddress, tokenA, tokenB, listingCount);
        _updateState(tokenA, tokenB, listingAddress, listingCount, msg.sender);

        emit ListingCreated(tokenA, tokenB, listingAddress, liquidityAddress, listingCount, msg.sender);
        listingCount++;
        return (listingAddress, liquidityAddress);
    }

    // Relists an existing token pair, replacing the old listing, restricted to original lister
    function relistToken(address tokenA, address tokenB, address uniswapV2Pair) external returns (address newListingAddress, address newLiquidityAddress) {
        require(tokenA != tokenB, "Identical tokens");
        address oldListingAddress = getListing[tokenA][tokenB];
        require(oldListingAddress != address(0), "Pair not listed");
        require(getLister[oldListingAddress] == msg.sender, "Not original lister");
        require(routers.length > 0, "No routers set");
        require(listingLogicAddress != address(0), "Listing logic not set");
        require(liquidityLogicAddress != address(0), "Liquidity logic not set");
        require(registryAddress != address(0), "Registry not set");

        (newListingAddress, newLiquidityAddress) = _deployPair(tokenA, tokenB, listingCount);
        _initializeListing(newListingAddress, newLiquidityAddress, tokenA, tokenB, listingCount, uniswapV2Pair);
        _initializeLiquidity(newListingAddress, newLiquidityAddress, tokenA, tokenB, listingCount);
        
        getListing[tokenA][tokenB] = newListingAddress;
        allListings.push(newListingAddress);
        queryByAddress[tokenA].push(listingCount);
        queryByAddress[tokenB].push(listingCount);
        getLister[newListingAddress] = msg.sender;
        listingsByLister[msg.sender].push(listingCount);

        emit ListingRelisted(tokenA, tokenB, oldListingAddress, newListingAddress, listingCount, msg.sender);
        listingCount++;
        return (newListingAddress, newLiquidityAddress);
    }

    // Relists an existing native ETH pair, replacing the old listing, restricted to original lister
    function relistNative(address token, bool isA, address uniswapV2Pair) external returns (address newListingAddress, address newLiquidityAddress) {
        address nativeAddress = address(0);
        address tokenA = isA ? nativeAddress : token;
        address tokenB = isA ? token : nativeAddress;

        require(tokenA != tokenB, "Identical tokens");
        address oldListingAddress = getListing[tokenA][tokenB];
        require(oldListingAddress != address(0), "Pair not listed");
        require(getLister[oldListingAddress] == msg.sender, "Not original lister");
        require(routers.length > 0, "No routers set");
        require(listingLogicAddress != address(0), "Listing logic not set");
        require(liquidityLogicAddress != address(0), "Liquidity logic not set");
        require(registryAddress != address(0), "Registry not set");

        (newListingAddress, newLiquidityAddress) = _deployPair(tokenA, tokenB, listingCount);
        _initializeListing(newListingAddress, newLiquidityAddress, tokenA, tokenB, listingCount, uniswapV2Pair);
        _initializeLiquidity(newListingAddress, newLiquidityAddress, tokenA, tokenB, listingCount);

        getListing[tokenA][tokenB] = newListingAddress;
        allListings.push(newListingAddress);
        queryByAddress[tokenA].push(listingCount);
        queryByAddress[tokenB].push(listingCount);
        getLister[newListingAddress] = msg.sender;
        listingsByLister[msg.sender].push(listingCount);

        emit ListingRelisted(tokenA, tokenB, oldListingAddress, newListingAddress, listingCount, msg.sender);
        listingCount++;
        return (newListingAddress, newLiquidityAddress);
    }

    // Transfers lister status to a new address, restricted to current lister
    function transferLister(address listingAddress, address newLister) external {
        require(getLister[listingAddress] == msg.sender, "Not current lister");
        require(newLister != address(0), "Invalid new lister address");
        address oldLister = getLister[listingAddress];
        getLister[listingAddress] = newLister;
        uint256 listingId;
        for (uint256 i = 0; i < allListings.length; i++) {
            if (allListings[i] == listingAddress) {
                listingId = i;
                break;
            }
        }
        listingsByLister[newLister].push(listingId);
        emit ListerTransferred(listingAddress, oldLister, newLister);
    }

    // Returns paginated listing IDs for a given lister
    function getListingsByLister(address lister, uint256 maxIteration, uint256 step) external view returns (uint256[] memory) {
        uint256[] memory indices = listingsByLister[lister];
        uint256 start = step * maxIteration;
        uint256 end = (step + 1) * maxIteration > indices.length ? indices.length : (step + 1) * maxIteration;
        uint256[] memory result = new uint256[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = indices[i];
        }
        return result;
    }

    // Checks if a listing address is valid and returns its details
    function isValidListing(address listingAddress) public view returns (bool isValid, ListingDetails memory details) {
        isValid = false;
        for (uint256 i = 0; i < allListings.length; i++) {
            if (allListings[i] == listingAddress) {
                isValid = true;
                (address tokenA, address tokenB) = ICCListingTemplate(listingAddress).getTokens();
                address liquidityAddress = ICCListing(listingAddress).liquidityAddressView();
                details = ListingDetails({
                    listingAddress: listingAddress,
                    liquidityAddress: liquidityAddress,
                    tokenA: tokenA,
                    tokenB: tokenB,
                    listingId: i
                });
                break;
            }
        }
    }

    // Returns listing address by index
    function queryByIndex(uint256 index) external view returns (address) {
        require(index < allListings.length, "Invalid index");
        return allListings[index];
    }

    // Returns paginated listing IDs for a token
    function queryByAddressView(address target, uint256 maxIteration, uint256 step) external view returns (uint256[] memory) {
        uint256[] memory indices = queryByAddress[target];
        uint256 start = step * maxIteration;
        uint256 end = (step + 1) * maxIteration > indices.length ? indices.length : (step + 1) * maxIteration;
        uint256[] memory result = new uint256[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = indices[i];
        }
        return result;
    }

    // Returns number of listing IDs for a token
    function queryByAddressLength(address target) external view returns (uint256) {
        return queryByAddress[target].length;
    }

    // Returns total number of listings
    function allListingsLength() external view returns (uint256) {
        return allListings.length;
    }

    // Returns total number of listed tokens
    function allListedTokensLength() external view returns (uint256) {
        return allListedTokens.length;
    }
}