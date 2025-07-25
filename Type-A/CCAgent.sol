// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.5
// Changes:
// - v0.0.4: Added relistToken and relistNative function to allow owner to replace existing listing for a token pair with updated routers.
// - v0.0.3: Modified _verifyAndSetUniswapV2Pair to recognize WETH in Uniswap V2 pair for native ETH listings while storing address(0) for native ETH.
// - v0.0.2: Added IUniswapV2Pair interface for token verification.
// - v0.0.2: Added _verifyAndSetUniswapV2Pair helper to verify tokenA/tokenB against Uniswap V2 pair and set pair address.
// - v0.0.2: Modified _initializeListing to call _verifyAndSetUniswapV2Pair.
// - v0.0.1: Renamed SSAgent to CCAgent, updated license to BSL 1.1 - Peng禁止

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";

interface ICCListingTemplate {
    function setRouters(address[] memory _routers) external;
    function setListingId(uint256 _listingId) external;
    function setLiquidityAddress(address _liquidityAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setAgent(address _agent) external;
    function setRegistry(address _registryAddress) external;
    function setUniswapV2Pair(address _uniswapV2Pair) external; // Sets Uniswap V2 pair address
    function getTokens() external view returns (address tokenA, address tokenB);
}

interface ISSLiquidityTemplate {
    function setRouters(address[] memory _routers) external;
    function setListingId(uint256 _listingId) external;
    function setListingAddress(address _listingAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setAgent(address _agent) external;
    function getListingAddress(uint256) external view returns (address);
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
    using SafeERC20 for IERC20;

    address[] public routers; // Array of router contract addresses
    address public listingLogicAddress; // CCListingLogic contract address
    address public liquidityLogicAddress; // CCLiquidityLogic contract address
    address public registryAddress; // Registry contract address
    uint256 public listingCount; // Counter for total listings created
    address public wethAddress; // WETH contract address

    mapping(address => mapping(address => address)) public getListing; // tokenA => tokenB => listing address
    address[] public allListings; // Array of all listing addresses
    address[] public allListedTokens; // Array of all unique listed tokens
    mapping(address => uint256[]) public queryByAddress; // token => listing IDs
    mapping(uint256 => address[]) public liquidityProviders; // listingId => array of users providing liquidity

    mapping(address => mapping(address => mapping(address => uint256))) public globalLiquidity; // tokenA => tokenB => user => amount
    mapping(address => mapping(address => uint256)) public totalLiquidityPerPair; // tokenA => tokenB => amount
    mapping(address => uint256) public userTotalLiquidity; // user => total liquidity
    mapping(uint256 => mapping(address => uint256)) public listingLiquidity; // listingId => user => amount
    mapping(address => mapping(address => mapping(uint256 => uint256))) public historicalLiquidityPerPair; // tokenA => tokenB => timestamp => amount
    mapping(address => mapping(address => mapping(address => mapping(uint256 => uint256)))) public historicalLiquidityPerUser; // tokenA => tokenB => user => timestamp => amount

    struct GlobalOrder {
        uint256 orderId; // Unique order identifier
        bool isBuy; // True for buy order, false for sell
        address maker; // Address creating the order
        address recipient; // Address receiving the order outcome
        uint256 amount; // Order amount
        uint8 status; // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
        uint256 timestamp; // Timestamp of order creation or update
    }

    mapping(address => mapping(address => mapping(uint256 => GlobalOrder))) public globalOrders; // tokenA => tokenB => orderId => GlobalOrder
    mapping(address => mapping(address => uint256[])) public pairOrders; // tokenA => tokenB => orderId[]
    mapping(address => uint256[]) public userOrders; // user => orderId[]
    mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => uint8)))) public historicalOrderStatus; // tokenA => tokenB => orderId => timestamp => status
    mapping(address => mapping(address => mapping(address => uint256))) public userTradingSummaries; // user => tokenA => tokenB => volume

    struct TrendData {
        address token; // Token or user address for sorting
        uint256 timestamp; // Timestamp of data point
        uint256 amount; // Amount for liquidity or volume
    }

    struct OrderData {
        uint256 orderId; // Order identifier
        bool isBuy; // True for buy order, false for sell
        address maker; // Order creator
        address recipient; // Order recipient
        uint256 amount; // Order amount
        uint8 status; // Order status
        uint256 timestamp; // Order timestamp
    }

    struct ListingDetails {
        address listingAddress; // Listing contract address
        address liquidityAddress; // Associated liquidity contract address
        address tokenA; // First token in pair
        address tokenB; // Second token in pair
        uint256 listingId; // Listing ID
    }

    event ListingCreated(address indexed tokenA, address indexed tokenB, address listingAddress, address liquidityAddress, uint256 listingId);
    event GlobalLiquidityChanged(uint256 listingId, address tokenA, address tokenB, address user, uint256 amount, bool isDeposit);
    event GlobalOrderChanged(uint256 listingId, address tokenA, address tokenB, uint256 orderId, bool isBuy, address maker, uint256 amount, uint8 status);
    event RouterAdded(address indexed router); // Emitted when a router is added
    event RouterRemoved(address indexed router); // Emitted when a router is removed
    event WETHAddressSet(address indexed weth); // Emitted when WETH address is set
    event ListingRelisted(address indexed tokenA, address indexed tokenB, address oldListingAddress, address newListingAddress, uint256 listingId); // Emitted when a listing is relisted

    // Sets WETH contract address, restricted to owner
    function setWETHAddress(address _wethAddress) external onlyOwner {
        require(_wethAddress != address(0), "Invalid WETH address");
        wethAddress = _wethAddress;
        emit WETHAddressSet(_wethAddress); // Emit event for WETH address setting
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

    // Verifies tokenA and tokenB match Uniswap V2 pair tokens, handling WETH for native ETH, and sets the pair address
    function _verifyAndSetUniswapV2Pair(address listingAddress, address tokenA, address tokenB, address uniswapV2Pair) internal {
        require(uniswapV2Pair != address(0), "Invalid Uniswap V2 pair address");
        require(wethAddress != address(0), "WETH address not set");
        address pairToken0 = IUniswapV2Pair(uniswapV2Pair).token0();
        address pairToken1 = IUniswapV2Pair(uniswapV2Pair).token1();
        // Replace address(0) with wethAddress for verification if tokenA or tokenB is native ETH
        address verifyTokenA = tokenA == address(0) ? wethAddress : tokenA;
        address verifyTokenB = tokenB == address(0) ? wethAddress : tokenB;
        bool isTokenAMatch = (verifyTokenA == pairToken0 && verifyTokenB == pairToken1) || (verifyTokenA == pairToken1 && verifyTokenB == pairToken0);
        require(isTokenAMatch, "Tokens do not match Uniswap V2 pair");
        ICCListingTemplate(listingAddress).setUniswapV2Pair(uniswapV2Pair); // Set Uniswap V2 pair address
    }

    // Deploys listing and liquidity contracts using create2 with provided salt
    function _deployPair(address tokenA, address tokenB, uint256 listingId) internal returns (address listingAddress, address liquidityAddress) {
        bytes32 listingSalt = keccak256(abi.encodePacked(tokenA, tokenB, listingId));
        bytes32 liquiditySalt = keccak256(abi.encodePacked(tokenB, tokenA, listingId));
        listingAddress = ICCListingLogic(listingLogicAddress).deploy(listingSalt);
        liquidityAddress = ISSLiquidityLogic(liquidityLogicAddress).deploy(liquiditySalt);
        return (listingAddress, liquidityAddress);
    }

    // Initializes listing contract with routers, listing ID, liquidity address, tokens, agent, registry, and Uniswap V2 pair
    function _initializeListing(address listingAddress, address liquidityAddress, address tokenA, address tokenB, uint256 listingId, address uniswapV2Pair) internal {
        ICCListingTemplate(listingAddress).setRouters(routers); // Use routers array directly
        ICCListingTemplate(listingAddress).setListingId(listingId);
        ICCListingTemplate(listingAddress).setLiquidityAddress(liquidityAddress);
        ICCListingTemplate(listingAddress).setTokens(tokenA, tokenB);
        ICCListingTemplate(listingAddress).setAgent(address(this));
        ICCListingTemplate(listingAddress).setRegistry(registryAddress);
        _verifyAndSetUniswapV2Pair(listingAddress, tokenA, tokenB, uniswapV2Pair); // Verify and set Uniswap V2 pair
    }

    // Initializes liquidity contract with routers, listing ID, listing address, tokens, and agent
    function _initializeLiquidity(address listingAddress, address liquidityAddress, address tokenA, address tokenB, uint256 listingId) internal {
        ISSLiquidityTemplate(liquidityAddress).setRouters(routers); // Use routers array directly
        ISSLiquidityTemplate(liquidityAddress).setListingId(listingId);
        ISSLiquidityTemplate(liquidityAddress).setListingAddress(listingAddress);
        ISSLiquidityTemplate(liquidityAddress).setTokens(tokenA, tokenB);
        ISSLiquidityTemplate(liquidityAddress).setAgent(address(this));
    }

    // Updates state mappings and arrays for new listing
    function _updateState(address tokenA, address tokenB, address listingAddress, uint256 listingId) internal {
        getListing[tokenA][tokenB] = listingAddress;
        allListings.push(listingAddress);
        if (!tokenExists(tokenA)) allListedTokens.push(tokenA);
        if (!tokenExists(tokenB)) allListedTokens.push(tokenB);
        queryByAddress[tokenA].push(listingId);
        queryByAddress[tokenB].push(listingId);
    }

    // Adds a router address to the routers array, restricted to owner
    function addRouter(address router) external onlyOwner {
        require(router != address(0), "Invalid router address");
        require(!routerExists(router), "Router already exists");
        routers.push(router);
        emit RouterAdded(router); // Emit event for router addition
    }

    // Removes a router address from the routers array, restricted to owner
    function removeRouter(address router) external onlyOwner {
        require(router != address(0), "Invalid router address");
        require(routerExists(router), "Router does not exist");
        for (uint256 i = 0; i < routers.length; i++) {
            if (routers[i] == router) {
                routers[i] = routers[routers.length - 1]; // Move last element to current position
                routers.pop(); // Remove last element
                break;
            }
        }
        emit RouterRemoved(router); // Emit event for router removal
    }

    // Returns the current list of routers
    function getRouters() external view returns (address[] memory) {
        return routers; // Returns the entire routers array
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

    // Lists a new token pair, deploying listing and liquidity contracts
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
        _updateState(tokenA, tokenB, listingAddress, listingCount);

        emit ListingCreated(tokenA, tokenB, listingAddress, liquidityAddress, listingCount);
        listingCount++;
        return (listingAddress, liquidityAddress);
    }

    // Lists a token paired with native currency
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
        _updateState(tokenA, tokenB, listingAddress, listingCount);

        emit ListingCreated(tokenA, tokenB, listingAddress, liquidityAddress, listingCount);
        listingCount++;
        return (listingAddress, liquidityAddress);
    }

    // Relists an existing token pair, replacing the old listing with a new one, restricted to owner
    function relistToken(address tokenA, address tokenB, address uniswapV2Pair) external onlyOwner returns (address newListingAddress, address newLiquidityAddress) {
        require(tokenA != tokenB, "Identical tokens");
        address oldListingAddress = getListing[tokenA][tokenB];
        require(oldListingAddress != address(0), "Pair not listed");
        require(routers.length > 0, "No routers set");
        require(listingLogicAddress != address(0), "Listing logic not set");
        require(liquidityLogicAddress != address(0), "Liquidity logic not set");
        require(registryAddress != address(0), "Registry not set");

        // Deploy new listing and liquidity contracts
        (newListingAddress, newLiquidityAddress) = _deployPair(tokenA, tokenB, listingCount);
        _initializeListing(newListingAddress, newLiquidityAddress, tokenA, tokenB, listingCount, uniswapV2Pair);
        _initializeLiquidity(newListingAddress, newLiquidityAddress, tokenA, tokenB, listingCount);
        
        // Update state with new listing
        getListing[tokenA][tokenB] = newListingAddress;
        allListings.push(newListingAddress);
        queryByAddress[tokenA].push(listingCount);
        queryByAddress[tokenB].push(listingCount);

        emit ListingRelisted(tokenA, tokenB, oldListingAddress, newListingAddress, listingCount);
        listingCount++;
        return (newListingAddress, newLiquidityAddress);
    }

    // Relists an existing native ETH pair, replacing the old listing with a new one, restricted to owner
    function relistNative(address token, bool isA, address uniswapV2Pair) external onlyOwner returns (address newListingAddress, address newLiquidityAddress) {
        address nativeAddress = address(0);
        address tokenA = isA ? nativeAddress : token;
        address tokenB = isA ? token : nativeAddress;

        require(tokenA != tokenB, "Identical tokens");
        address oldListingAddress = getListing[tokenA][tokenB];
        require(oldListingAddress != address(0), "Pair not listed");
        require(routers.length > 0, "No routers set");
        require(listingLogicAddress != address(0), "Listing logic not set");
        require(liquidityLogicAddress != address(0), "Liquidity logic not set");
        require(registryAddress != address(0), "Registry not set");

        // Deploy new listing and liquidity contracts
        (newListingAddress, newLiquidityAddress) = _deployPair(tokenA, tokenB, listingCount);
        _initializeListing(newListingAddress, newLiquidityAddress, tokenA, tokenB, listingCount, uniswapV2Pair);
        _initializeLiquidity(newListingAddress, newLiquidityAddress, tokenA, tokenB, listingCount);

        // Update state with new listing
        getListing[tokenA][tokenB] = newListingAddress;
        allListings.push(newListingAddress);
        queryByAddress[tokenA].push(listingCount);
        queryByAddress[tokenB].push(listingCount);

        emit ListingRelisted(tokenA, tokenB, oldListingAddress, newListingAddress, listingCount);
        listingCount++;
        return (newListingAddress, newLiquidityAddress);
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

    // Updates global liquidity state for a user and emits event
    function globalizeLiquidity(
        uint256 listingId,
        address tokenA,
        address tokenB,
        address user,
        uint256 amount,
        bool isDeposit
    ) external {
        require(tokenA != address(0) && tokenB != address(0), "Invalid tokens");
        require(user != address(0), "Invalid user");
        require(listingId < listingCount, "Invalid listing ID");

        // Retrieve listing address from caller (liquidity contract)
        address listingAddress;
        try ISSLiquidityTemplate(msg.sender).getListingAddress(listingId) returns (address _listingAddress) {
            listingAddress = _listingAddress;
        } catch {
            revert("Failed to retrieve listing address");
        }
        require(listingAddress != address(0), "Invalid listing address");

        // Verify listing validity and details
        (bool isValid, ListingDetails memory details) = isValidListing(listingAddress);
        require(isValid, "Invalid listing");
        require(details.listingId == listingId, "Listing ID mismatch");
        require(details.tokenA == tokenA && details.tokenB == tokenB, "Token mismatch");

        // Ensure caller is the associated liquidity contract
        require(details.liquidityAddress == msg.sender, "Caller is not liquidity contract");

        _updateGlobalLiquidity(listingId, tokenA, tokenB, user, amount, isDeposit);
    }

    // Updates liquidity mappings and tracks providers
    function _updateGlobalLiquidity(
        uint256 listingId,
        address tokenA,
        address tokenB,
        address user,
        uint256 amount,
        bool isDeposit
    ) internal {
        if (isDeposit) {
            // Add liquidity to mappings
            globalLiquidity[tokenA][tokenB][user] += amount;
            totalLiquidityPerPair[tokenA][tokenB] += amount;
            userTotalLiquidity[user] += amount;
            listingLiquidity[listingId][user] += amount;
            // Track new liquidity provider
            if (listingLiquidity[listingId][user] == amount) {
                liquidityProviders[listingId].push(user);
            }
        } else {
            // Validate sufficient liquidity before withdrawal
            require(globalLiquidity[tokenA][tokenB][user] >= amount, "Insufficient user liquidity");
            require(totalLiquidityPerPair[tokenA][tokenB] >= amount, "Insufficient pair liquidity");
            require(userTotalLiquidity[user] >= amount, "Insufficient total liquidity");
            require(listingLiquidity[listingId][user] >= amount, "Insufficient listing liquidity");
            // Subtract liquidity from mappings
            globalLiquidity[tokenA][tokenB][user] -= amount;
            totalLiquidityPerPair[tokenA][tokenB] -= amount;
            userTotalLiquidity[user] -= amount;
            listingLiquidity[listingId][user] -= amount;
        }
        // Update historical liquidity records
        historicalLiquidityPerPair[tokenA][tokenB][block.timestamp] = totalLiquidityPerPair[tokenA][tokenB];
        historicalLiquidityPerUser[tokenA][tokenB][user][block.timestamp] = globalLiquidity[tokenA][tokenB][user];
        emit GlobalLiquidityChanged(listingId, tokenA, tokenB, user, amount, isDeposit);
    }

    // Updates global order state and emits event
    function globalizeOrders(
        uint256 listingId,
        address tokenA,
        address tokenB,
        uint256 orderId,
        bool isBuy,
        address maker,
        address recipient,
        uint256 amount,
        uint8 status
    ) external {
        require(tokenA != address(0) && tokenB != address(0), "Invalid tokens");
        require(maker != address(0), "Invalid maker");
        require(listingId < listingCount, "Invalid listing ID");
        require(getListing[tokenA][tokenB] == msg.sender, "Not listing contract");
        GlobalOrder storage order = globalOrders[tokenA][tokenB][orderId];
        if (order.maker == address(0) && status != 0) {
            order.orderId = orderId;
            order.isBuy = isBuy;
            order.maker = maker;
            order.recipient = recipient;
            order.amount = amount;
            order.status = status;
            order.timestamp = block.timestamp;
            pairOrders[tokenA][tokenB].push(orderId);
            userOrders[maker].push(orderId);
        } else {
            order.amount = amount;
            order.status = status;
            order.timestamp = block.timestamp;
        }
        historicalOrderStatus[tokenA][tokenB][orderId][block.timestamp] = status;
        if (amount > 0) {
            userTradingSummaries[maker][tokenA][tokenB] += amount;
        }
        emit GlobalOrderChanged(listingId, tokenA, tokenB, orderId, isBuy, maker, amount, status);
    }

    // Returns liquidity trend for a token pair
    function getPairLiquidityTrend(
        address tokenA,
        bool focusOnTokenA,
        uint256 startTime,
        uint256 endTime
    ) external view returns (uint256[] memory timestamps, uint256[] memory amounts) {
        if (endTime < startTime || tokenA == address(0)) {
            return (new uint256[](0), new uint256[](0));
        }
        TrendData[] memory temp = new TrendData[](endTime - startTime + 1);
        uint256 count = 0;
        if (focusOnTokenA) {
            for (uint256 t = startTime; t <= endTime; t++) {
                uint256 amount = historicalLiquidityPerPair[tokenA][allListedTokens[0]][t];
                if (amount > 0) {
                    temp[count] = TrendData(address(0), t, amount);
                    count++;
                }
            }
        } else {
            for (uint256 i = 0; i < allListedTokens.length; i++) {
                address tokenB = allListedTokens[i];
                for (uint256 t = startTime; t <= endTime; t++) {
                    uint256 amount = historicalLiquidityPerPair[tokenB][tokenA][t];
                    if (amount > 0) {
                        temp[count] = TrendData(address(0), t, amount);
                        count++;
                    }
                }
            }
        }
        timestamps = new uint256[](count);
        amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            timestamps[i] = temp[i].timestamp;
            amounts[i] = temp[i].amount;
        }
    }

    // Returns liquidity trend for a user across tokens
    function getUserLiquidityTrend(
        address user,
        bool focusOnTokenA,
        uint256 startTime,
        uint256 endTime
    ) external view returns (address[] memory tokens, uint256[] memory timestamps, uint256[] memory amounts) {
        if (endTime < startTime || user == address(0)) {
            return (new address[](0), new uint256[](0), new uint256[](0));
        }
        TrendData[] memory temp = new TrendData[]((endTime - startTime + 1) * allListedTokens.length);
        uint256 count = 0;
        for (uint256 i = 0; i < allListedTokens.length; i++) {
            address tokenA = allListedTokens[i];
            address pairToken = focusOnTokenA ? allListedTokens[0] : tokenA;
            for (uint256 t = startTime; t <= endTime; t++) {
                uint256 amount = historicalLiquidityPerUser[tokenA][pairToken][user][t];
                if (amount > 0) {
                    temp[count] = TrendData(focusOnTokenA ? tokenA : pairToken, t, amount);
                    count++;
                }
            }
        }
        tokens = new address[](count);
        timestamps = new uint256[](count);
        amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            tokens[i] = temp[i].token;
            timestamps[i] = temp[i].timestamp;
            amounts[i] = temp[i].amount;
        }
    }

    // Returns user's liquidity across token pairs
    function getUserLiquidityAcrossPairs(address user, uint256 maxIterations)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory amounts)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxPairs = maxIterations < allListedTokens.length ? maxIterations : allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;
        for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
            address tokenA = allListedTokens[i];
            uint256 amount = globalLiquidity[tokenA][allListedTokens[0]][user];
            if (amount > 0) {
                temp[count] = TrendData(tokenA, 0, amount);
                count++;
            }
        }
        tokenAs = new address[](count);
        tokenBs = new address[](count);
        amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            tokenAs[i] = temp[i].token;
            tokenBs[i] = allListedTokens[0];
            amounts[i] = temp[i].amount;
        }
    }

    // Returns top liquidity providers for a listing
    function getTopLiquidityProviders(uint256 listingId, uint256 maxIterations)
        external view returns (address[] memory users, uint256[] memory amounts)
    {
        // Validate input parameters
        require(maxIterations > 0, "Invalid maxIterations");
        require(listingId < listingCount, "Invalid listing ID");

        // Limit iteration to maxIterations or available providers
        uint256 maxLimit = maxIterations < liquidityProviders[listingId].length ? maxIterations : liquidityProviders[listingId].length;
        TrendData[] memory temp = new TrendData[](maxLimit);
        uint256 count = 0;

        // Collect non-zero liquidity providers
        for (uint256 i = 0; i < liquidityProviders[listingId].length && count < maxLimit; i++) {
            address user = liquidityProviders[listingId][i];
            uint256 amount = listingLiquidity[listingId][user];
            if (amount > 0) {
                temp[count] = TrendData(user, 0, amount);
                count++;
            }
        }

        // Sort providers by liquidity amount in descending order
        _sortDescending(temp, count);

        // Prepare return arrays
        users = new address[](count);
        amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            users[i] = temp[i].token;
            amounts[i] = temp[i].amount;
        }
    }

    // Returns user's liquidity share for a token pair
    function getUserLiquidityShare(address user, address tokenA, address tokenB)
        external view returns (uint256 share, uint256 total)
    {
        total = totalLiquidityPerPair[tokenA][tokenB];
        uint256 userAmount = globalLiquidity[tokenA][tokenB][user];
        share = total > 0 ? (userAmount * 1e18) / total : 0;
    }

    // Returns pairs with liquidity above a threshold
    function getAllPairsByLiquidity(uint256 minLiquidity, bool focusOnTokenA, uint256 maxIterations)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory amounts)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxPairs = maxIterations < allListedTokens.length ? maxIterations : allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;
        if (focusOnTokenA) {
            for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
                address tokenA = allListedTokens[i];
                uint256 amount = totalLiquidityPerPair[tokenA][allListedTokens[0]];
                if (amount >= minLiquidity) {
                    temp[count] = TrendData(tokenA, 0, amount);
                    count++;
                }
            }
        } else {
            for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
                address tokenA = allListedTokens[i];
                uint256 amount = totalLiquidityPerPair[tokenA][allListedTokens[0]];
                if (amount >= minLiquidity) {
                    temp[count] = TrendData(tokenA, 0, amount);
                    count++;
                }
            }
        }
        tokenAs = new address[](count);
        tokenBs = new address[](count);
        amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            tokenAs[i] = temp[i].token;
            tokenBs[i] = allListedTokens[0];
            amounts[i] = temp[i].amount;
        }
    }

    // Returns order activity for a token pair within a time range
    function getOrderActivityByPair(
        address tokenA,
        address tokenB,
        uint256 startTime,
        uint256 endTime
    ) external view returns (uint256[] memory orderIds, OrderData[] memory orders) {
        if (endTime < startTime || tokenA == address(0) || tokenB == address(0)) {
            return (new uint256[](0), new OrderData[](0));
        }
        uint256[] memory pairOrderIds = pairOrders[tokenA][tokenB];
        OrderData[] memory temp = new OrderData[](pairOrderIds.length);
        uint256 count = 0;
        for (uint256 i = 0; i < pairOrderIds.length; i++) {
            GlobalOrder memory order = globalOrders[tokenA][tokenB][pairOrderIds[i]];
            if (order.timestamp >= startTime && order.timestamp <= endTime) {
                temp[count] = OrderData(
                    order.orderId,
                    order.isBuy,
                    order.maker,
                    order.recipient,
                    order.amount,
                    order.status,
                    order.timestamp
                );
                count++;
            }
        }
        orderIds = new uint256[](count);
        orders = new OrderData[](count);
        for (uint256 i = 0; i < count; i++) {
            orderIds[i] = temp[i].orderId;
            orders[i] = temp[i];
        }
    }

    // Returns user's trading profile across token pairs
    function getUserTradingProfile(address user)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory volumes)
    {
        uint256 maxPairs = allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;
        for (uint256 i = 0; i < allListedTokens.length; i++) {
            address tokenA = allListedTokens[i];
            uint256 volume = userTradingSummaries[user][tokenA][allListedTokens[0]];
            if (volume > 0) {
                temp[count] = TrendData(tokenA, 0, volume);
                count++;
            }
        }
        tokenAs = new address[](count);
        tokenBs = new address[](count);
        volumes = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            tokenAs[i] = temp[i].token;
            tokenBs[i] = allListedTokens[0];
            volumes[i] = temp[i].amount;
        }
    }

    // Returns top traders by volume for a listing
    function getTopTradersByVolume(uint256 listingId, uint256 maxIterations)
        external view returns (address[] memory traders, uint256[] memory volumes)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxLimit = maxIterations < allListings.length ? maxIterations : allListings.length;
        TrendData[] memory temp = new TrendData[](maxLimit);
        uint256 count = 0;
        for (uint256 i = 0; i < allListings.length && count < maxLimit; i++) {
            address trader = allListings[i];
            address tokenA;
            for (uint256 j = 0; j < allListedTokens.length; j++) {
                if (getListing[allListedTokens[j]][allListedTokens[0]] == trader) {
                    tokenA = allListedTokens[j];
                    break;
                }
            }
            if (tokenA != address(0)) {
                uint256 volume = userTradingSummaries[trader][tokenA][allListedTokens[0]];
                if (volume > 0) {
                    temp[count] = TrendData(trader, 0, volume);
                    count++;
                }
            }
        }
        _sortDescending(temp, count);
        traders = new address[](count);
        volumes = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            traders[i] = temp[i].token;
            volumes[i] = temp[i].amount;
        }
    }

    // Returns pairs with order volume above a threshold
    function getAllPairsByOrderVolume(uint256 minVolume, bool focusOnTokenA, uint256 maxIterations)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory volumes)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxPairs = maxIterations < allListedTokens.length ? maxIterations : allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;
        if (focusOnTokenA) {
            for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
                address tokenA = allListedTokens[i];
                uint256 volume = 0;
                uint256[] memory orderIds = pairOrders[tokenA][allListedTokens[0]];
                for (uint256 j = 0; j < orderIds.length; j++) {
                    volume += globalOrders[tokenA][allListedTokens[0]][orderIds[j]].amount;
                }
                if (volume >= minVolume) {
                    temp[count] = TrendData(tokenA, 0, volume);
                    count++;
                }
            }
        } else {
            for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
                address tokenA = allListedTokens[i];
                uint256 volume = 0;
                uint256[] memory orderIds = pairOrders[tokenA][allListedTokens[0]];
                for (uint256 j = 0; j < orderIds.length; j++) {
                    volume += globalOrders[tokenA][allListedTokens[0]][orderIds[j]].amount;
                }
                if (volume >= minVolume) {
                    temp[count] = TrendData(tokenA, 0, volume);
                    count++;
                }
            }
        }
        tokenAs = new address[](count);
        tokenBs = new address[](count);
        volumes = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            tokenAs[i] = temp[i].token;
            tokenBs[i] = allListedTokens[0];
            volumes[i] = temp[i].amount;
        }
    }

    // Sorts TrendData array in descending order by amount
    function _sortDescending(TrendData[] memory data, uint256 length) internal pure {
        for (uint256 i = 0; i < length; i++) {
            for (uint256 j = i + 1; j < length; j++) {
                if (data[i].amount < data[j].amount) {
                    TrendData memory temp = data[i];
                    data[i] = data[j];
                    data[j] = temp;
                }
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