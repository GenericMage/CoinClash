// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.57
// Change Log:
// - 2025-08-13: Added tokenPath to HopPrepState struct and updated initPrepState and buildListingArrays to use it.
// - 2025-08-13: Replaced ISSAgent.getListing with ICCAgent.isValidListing for listing validation.
// - 2025-08-13: Fixed onlyValidListing modifier usage in hopNative and hopToken.
// - 2025-08-13: Changed listing parameters to listingAddresses array in hopNative, hopToken, and related functions.
// - 2025-08-13: Replaced startToken and endToken with tokenPath array.
// - 2025-08-12: Added multiController state variable with owner-only setter.
// - 2025-08-12: Modified _createHopOrderNative and _createHopOrderToken to transfer principal to MultiController.
// - 2025-08-12: Updated pre/post balance checks to use received amount for hop creation.

import "./imports/ReentrancyGuard.sol";
import "./imports/IERC20.sol";

interface ISSListing {
    struct UpdateType {
        string field;
        uint256 value;
    }
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function getNextOrderId() external view returns (uint256);
    function getBuyOrderCore(uint256 orderId) external view returns (address makerAddress, address recipient, uint8 status);
    function getSellOrderCore(uint256 orderId) external view returns (address makerAddress, address recipient, uint8 status);
    function getBuyOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent);
    function getSellOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent);
    function update(UpdateType[] memory updates) external;
}

interface ICCAgent {
    struct ListingDetails {
        address listingAddress;
        address liquidityAddress;
        address tokenA;
        address tokenB;
        uint256 listingId;
    }
    function isValidListing(address listingAddress) external view returns (bool isValid, ListingDetails memory details);
}

interface MultiStorage {
    struct StalledHop {
        uint8 stage;
        address currentListing;
        uint256 orderID;
        uint256 minPrice;
        uint256 maxPrice;
        address hopMaker;
        address[] remainingListings;
        uint256 principalAmount;
        address[] tokenPath;
        uint8 settleType;
        uint8 hopStatus;
        uint256 maxIterations;
    }
    struct HopUpdateType {
        string field;
        uint256 value;
    }
    struct CancelPrepData {
        uint256 hopId;
        address listing;
        bool isBuy;
        address outputToken;
        address inputToken;
        uint256 pending;
        uint256 filled;
        uint8 status;
        uint256 receivedAmount;
        address recipient;
        uint256 refundedPending;
    }
    struct CancelBalanceData {
        address token;
        uint256 balanceBefore;
        uint256 balanceAfter;
    }
    struct HopExecutionParams {
        address[] listingAddresses;
        uint256[] impactPricePercents;
        address[] tokenPath;
        uint8 settleType;
        uint256 maxIterations;
        uint256 numListings;
    }
    struct HopPrepData {
        uint256 hopId;
        uint256[] indices;
        bool[] isBuy;
        address currentToken;
        uint256 principal;
        address maker;
        bool isNative;
    }
    struct SettlementRouter {
        address router;
        uint8 routerType;
    }
    struct LiquidRouter {
        address router;
        uint8 routerType;
    }
    function agent() external view returns (address);
    function hopID(uint256 hopId) external view returns (StalledHop memory);
    function hopsByAddress(address user) external view returns (uint256[] memory);
    function totalHops() external view returns (uint256[] memory);
    function nextHopId() external view returns (uint256);
    function settlementRouters() external view returns (SettlementRouter[] memory);
    function liquidRouters() external view returns (LiquidRouter[] memory);
    function MHUpdate(uint256 hopId, StalledHop memory hopData, uint256[] memory userHops, bool addToTotalHops) external;
    function updateHopField(uint256 hopId, string memory field, uint256 value) external;
    function cancelHop(uint256 hopId) external;
    function cancelAll(uint256 maxIterations) external;
}

contract MultiInitializer is ReentrancyGuard {
    MultiStorage public multiStorage;
    address public multiController;

    struct OrderUpdateData {
        address listing;
        address recipient;
        uint256 inputAmount;
        uint256 priceLimit;
        address inputToken;
    }

    struct HopPrepState {
        uint256 numListings;
        address[] listingAddresses;
        uint256[] impactPricePercents;
        uint256 hopId;
        uint256[] indices;
        bool[] isBuy;
        address[] tokenPath;
    }

    event HopStarted(uint256 indexed hopId, address indexed maker, uint256 numListings);

    modifier onlyValidListing(address listingAddress) {
        require(multiStorage.agent() != address(0), "Agent contract not set");
        (bool isValid, ) = ICCAgent(multiStorage.agent()).isValidListing(listingAddress);
        require(listingAddress == address(0) || isValid, "Listing not registered");
        _;
    }

    function setMultiStorage(address storageAddress) external onlyOwner {
        // Sets MultiStorage contract address
        require(storageAddress != address(0), "Invalid storage address");
        multiStorage = MultiStorage(storageAddress);
    }

    function setMultiController(address controllerAddress) external onlyOwner {
        // Sets MultiController contract address
        require(controllerAddress != address(0), "Invalid controller address");
        multiController = controllerAddress;
    }

    function getTokenDecimals(address token) internal view returns (uint8 decimals) {
        // Returns token decimals, defaults to 18 for native
        if (token == address(0)) return 18;
        decimals = IERC20(token).decimals();
        require(decimals <= 18, "Token decimals exceed 18");
    }

    function denormalizeForToken(uint256 amount, address token) internal view returns (uint256 denormalizedAmount) {
        // Converts normalized amount to token-specific decimals
        if (token == address(0)) return amount;
        uint256 decimals = IERC20(token).decimals();
        require(decimals <= 18, "Token decimals exceed 18");
        denormalizedAmount = amount * (10 ** decimals);
    }

    function normalizeForToken(uint256 amount, address token) internal view returns (uint256 normalizedAmount) {
        // Converts token amount to normalized value
        if (token == address(0)) return amount;
        uint256 decimals = IERC20(token).decimals();
        require(decimals <= 18, "Token decimals exceed 18");
        normalizedAmount = amount / (10 ** decimals);
    }

    function _createHopOrderNative(OrderUpdateData memory orderData, address sender) internal returns (uint256 orderId) {
        // Creates a native order on the listing, transfers to MultiController
        require(orderData.listing != address(0), "Listing address cannot be zero");
        require(orderData.recipient != address(0), "Recipient address cannot be zero");
        require(orderData.inputAmount > 0, "Input amount must be positive");
        require(multiController != address(0), "Controller not set");
        ISSListing listingContract = ISSListing(orderData.listing);
        orderId = listingContract.getNextOrderId();
        uint256 rawAmount = orderData.inputAmount;
        uint256 balanceBefore = address(multiController).balance;
        (bool success, ) = payable(multiController).call{value: rawAmount}("");
        require(success, "Native transfer to controller failed");
        uint256 balanceAfter = address(multiController).balance;
        uint256 transferredAmount = balanceAfter - balanceBefore;
        require(transferredAmount == rawAmount, "Native transferred amount mismatch");
        MultiStorage.HopUpdateType[] memory hopUpdates = new MultiStorage.HopUpdateType[](4);
        setOrderStatus(hopUpdates, 0);
        setOrderAmount(hopUpdates, 1, orderData.inputToken == listingContract.tokenB() ? "buyAmount" : "sellAmount", transferredAmount);
        setOrderPrice(hopUpdates, 2, orderData.inputToken == listingContract.tokenB() ? "buyPrice" : "sellPrice", orderData.priceLimit);
        setOrderRecipient(hopUpdates, 3, orderData.recipient);
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](hopUpdates.length);
        for (uint256 i = 0; i < hopUpdates.length; i++) {
            updates[i] = ISSListing.UpdateType({ field: hopUpdates[i].field, value: hopUpdates[i].value });
        }
        try listingContract.update(updates) {
            // Order created successfully
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Native order creation failed: ", reason)));
        }
    }

    function _createHopOrderToken(OrderUpdateData memory orderData, address sender) internal returns (uint256 orderId) {
        // Creates a token order on the listing, transfers to MultiController
        require(orderData.listing != address(0), "Listing address cannot be zero");
        require(orderData.recipient != address(0), "Recipient address cannot be zero");
        require(orderData.inputAmount > 0, "Input amount must be positive");
        require(orderData.inputToken != address(0), "Invalid token address");
        require(multiController != address(0), "Controller not set");
        ISSListing listingContract = ISSListing(orderData.listing);
        orderId = listingContract.getNextOrderId();
        uint256 rawAmount = denormalizeForToken(orderData.inputAmount, orderData.inputToken);
        bool success = IERC20(orderData.inputToken).transferFrom(sender, multiController, rawAmount);
        require(success, "Token transfer to controller failed");
        uint256 balanceBefore = IERC20(orderData.inputToken).balanceOf(multiController);
        success = IERC20(orderData.inputToken).approve(orderData.listing, rawAmount);
        require(success, "Token approval for listing failed");
        success = IERC20(orderData.inputToken).transferFrom(multiController, orderData.listing, rawAmount);
        require(success, "Token transfer from controller failed");
        uint256 balanceAfter = IERC20(orderData.inputToken).balanceOf(orderData.listing);
        uint256 transferredAmount = balanceAfter - balanceBefore;
        require(transferredAmount == rawAmount, "Token transferred amount mismatch");
        MultiStorage.HopUpdateType[] memory hopUpdates = new MultiStorage.HopUpdateType[](4);
        setOrderStatus(hopUpdates, 0);
        setOrderAmount(hopUpdates, 1, orderData.inputToken == listingContract.tokenB() ? "buyAmount" : "sellAmount", transferredAmount);
        setOrderPrice(hopUpdates, 2, orderData.inputToken == listingContract.tokenB() ? "buyPrice" : "sellPrice", orderData.priceLimit);
        setOrderRecipient(hopUpdates, 3, orderData.recipient);
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](hopUpdates.length);
        for (uint256 i = 0; i < hopUpdates.length; i++) {
            updates[i] = ISSListing.UpdateType({ field: hopUpdates[i].field, value: hopUpdates[i].value });
        }
        try listingContract.update(updates) {
            // Order created successfully
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Token order creation failed: ", reason)));
        }
    }

    function _checkTransferNative(address to, uint256 amount) internal returns (uint256 transferredAmount) {
        // Transfers native currency and checks balance
        require(to != address(0), "Recipient address cannot be zero");
        require(amount > 0, "Transfer amount must be positive");
        uint256 balanceBefore = address(to).balance;
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "Native transfer failed");
        uint256 balanceAfter = address(to).balance;
        require(balanceAfter > balanceBefore, "Native transfer did not increase balance");
        transferredAmount = balanceAfter - balanceBefore;
    }

    function _checkTransferToken(address token, address from, address to, uint256 amount) internal returns (uint256 transferredAmount) {
        // Transfers ERC20 token and checks balance
        require(token != address(0), "Invalid token address");
        require(to != address(0), "Recipient address cannot be zero");
        require(amount > 0, "Transfer amount must be positive");
        uint256 balanceBefore = IERC20(token).balanceOf(to);
        bool success = IERC20(token).transferFrom(from, to, amount);
        require(success, "ERC20 transfer failed");
        uint256 balanceAfter = IERC20(token).balanceOf(to);
        require(balanceAfter > balanceBefore, "Token transfer did not increase balance");
        transferredAmount = balanceAfter - balanceBefore;
    }

    function computeRoute(address[] memory listingAddresses, address[] memory tokenPath)
        internal view returns (uint256[] memory indices, bool[] memory isBuy)
    {
        // Computes trading route through tokenPath
        require(listingAddresses.length > 0, "No listings provided");
        require(listingAddresses.length <= 4, "Too many listings, max 4");
        require(tokenPath.length >= 2, "Token path must include at least start and end tokens");
        require(tokenPath[0] != tokenPath[tokenPath.length - 1], "Start and end tokens cannot be identical");
        indices = new uint256[](listingAddresses.length);
        isBuy = new bool[](listingAddresses.length);
        address currentToken = tokenPath[0];
        uint256 pathLength = 0;
        for (uint256 i = 0; i < listingAddresses.length; i++) {
            require(listingAddresses[i] != address(0), "Listing address cannot be zero");
            ISSListing listing = ISSListing(listingAddresses[i]);
            address tokenA = listing.tokenA();
            address tokenB = listing.tokenB();
            require(tokenA != address(0) && tokenB != address(0), "Invalid token pair in listing");
            if (currentToken == tokenA && pathLength < tokenPath.length - 1 && tokenPath[pathLength + 1] == tokenB) {
                indices[pathLength] = i;
                isBuy[pathLength] = false;
                currentToken = tokenB;
                pathLength++;
            } else if (currentToken == tokenB && pathLength < tokenPath.length - 1 && tokenPath[pathLength + 1] == tokenA) {
                indices[pathLength] = i;
                isBuy[pathLength] = true;
                currentToken = tokenA;
                pathLength++;
            }
            if (currentToken == tokenPath[tokenPath.length - 1]) break;
        }
        require(currentToken == tokenPath[tokenPath.length - 1], "No valid route through tokenPath");
        uint256[] memory resizedIndices = new uint256[](pathLength);
        bool[] memory resizedIsBuy = new bool[](pathLength);
        for (uint256 i = 0; i < pathLength; i++) {
            resizedIndices[i] = indices[i];
            resizedIsBuy[i] = isBuy[i];
        }
        return (resizedIndices, resizedIsBuy);
    }

    function validateHopRequest(
        address[] memory listingAddresses,
        uint256 impactPercent,
        uint256 maxIterations
    ) internal view {
        // Validates hop request parameters
        require(multiStorage.agent() != address(0), "Agent contract not set");
        require(listingAddresses.length > 0, "At least one listing required");
        require(listingAddresses.length <= 4, "Too many listings, max 4");
        require(maxIterations > 0, "Max iterations must be positive");
        require(impactPercent <= 1000, "Impact percent exceeds 1000");
        require(listingAddresses[0] != address(0), "First listing cannot be zero address");
        (bool isValid, ) = ICCAgent(multiStorage.agent()).isValidListing(listingAddresses[0]);
        require(isValid, "First listing not registered");
        for (uint256 i = 1; i < listingAddresses.length; i++) {
            if (listingAddresses[i] == address(0) && i < listingAddresses.length - 1 && listingAddresses[i + 1] != address(0)) {
                revert("Invalid listing sequence: zero address in middle");
            }
            if (listingAddresses[i] != address(0)) {
                (bool valid, ) = ICCAgent(multiStorage.agent()).isValidListing(listingAddresses[i]);
                require(valid, "Listing not registered");
            }
        }
    }

    function initializeHopData(
        address[] memory listingAddresses,
        uint256 impactPercent,
        address[] memory tokenPath,
        uint8 settleType,
        uint256 maxIterations,
        uint256[] memory indices,
        uint256 hopId,
        address maker
    ) internal {
        // Initializes hop data in MultiStorage
        address[] memory orderedListings = new address[](indices.length);
        for (uint256 i = 0; i < indices.length; i++) {
            orderedListings[i] = listingAddresses[indices[i]];
        }
        MultiStorage.StalledHop memory hopData = MultiStorage.StalledHop({
            stage: 0,
            currentListing: orderedListings[0],
            orderID: 0,
            minPrice: 0,
            maxPrice: 0,
            hopMaker: maker,
            remainingListings: orderedListings,
            principalAmount: tokenPath[0] == address(0) ? msg.value : impactPercent,
            tokenPath: tokenPath,
            settleType: settleType,
            hopStatus: 1,
            maxIterations: maxIterations
        });
        uint256[] memory userHops = multiStorage.hopsByAddress(maker);
        uint256[] memory newUserHops = new uint256[](userHops.length + 1);
        for (uint256 i = 0; i < userHops.length; i++) {
            newUserHops[i] = userHops[i];
        }
        newUserHops[userHops.length] = hopId;
        multiStorage.MHUpdate(hopId, hopData, newUserHops, true);
    }

    function initPrepState(
        address[] memory listingAddresses,
        uint256 impactPercent,
        address[] memory tokenPath,
        uint8 settleType,
        uint256 maxIterations
    ) internal view returns (HopPrepState memory state) {
        // Initializes prep state for hop
        state.numListings = listingAddresses.length;
        state.hopId = multiStorage.nextHopId();
        state.listingAddresses = listingAddresses;
        state.impactPricePercents = new uint256[](state.numListings);
        state.tokenPath = tokenPath;
        for (uint256 i = 0; i < state.numListings; i++) {
            state.impactPricePercents[i] = impactPercent;
        }
        require(settleType <= 1, "Invalid settle type");
        require(multiStorage.agent() != address(0), "Agent contract not set");
        validateHopRequest(listingAddresses, impactPercent, maxIterations);
    }

    function checkRouters() internal view returns (bool hasValidRouter) {
        // Checks for valid routers
        MultiStorage.SettlementRouter[] memory settlementRouters = multiStorage.settlementRouters();
        MultiStorage.LiquidRouter[] memory liquidRouters = multiStorage.liquidRouters();
        for (uint256 i = 0; i < settlementRouters.length; i++) {
            if (settlementRouters[i].routerType == 1 && settlementRouters[i].router != address(0)) {
                return true;
            }
        }
        for (uint256 i = 0; i < liquidRouters.length; i++) {
            if (liquidRouters[i].routerType == 2 && liquidRouters[i].router != address(0)) {
                return true;
            }
        }
        return false;
    }

    function buildListingArrays(HopPrepState memory state) internal view {
        // Builds listing arrays and computes route
        (state.indices, state.isBuy) = computeRoute(state.listingAddresses, state.tokenPath);
    }

    function finalizePrepData(
        HopPrepState memory state,
        address[] memory tokenPath,
        uint256 principal,
        address maker,
        bool isNative
    ) internal view returns (MultiStorage.HopPrepData memory prepData) {
        // Finalizes prep data for hop execution
        prepData = MultiStorage.HopPrepData({
            hopId: state.hopId,
            indices: state.indices,
            isBuy: state.isBuy,
            currentToken: tokenPath[0],
            principal: principal,
            maker: maker,
            isNative: isNative
        });
    }

    function prepHop(
        address[] memory listingAddresses,
        uint256 impactPercent,
        address[] memory tokenPath,
        uint8 settleType,
        uint256 maxIterations,
        address maker,
        bool isNative
    ) internal view returns (MultiStorage.HopPrepData memory prepData) {
        // Prepares hop data for execution
        require(checkRouters(), "No valid routers configured");
        HopPrepState memory state = initPrepState(listingAddresses, impactPercent, tokenPath, settleType, maxIterations);
        buildListingArrays(state);
        prepData = finalizePrepData(state, tokenPath, isNative ? msg.value : impactPercent, maker, isNative);
    }

    function updateHopListings(
        MultiStorage.HopExecutionParams memory params,
        address[] memory listingAddresses,
        uint256 impactPercent
    ) internal pure {
        // Updates hop listings in execution params
        params.numListings = listingAddresses.length;
        params.listingAddresses = new address[](listingAddresses.length);
        params.impactPricePercents = new uint256[](listingAddresses.length);
        for (uint256 i = 0; i < listingAddresses.length; i++) {
            params.listingAddresses[i] = listingAddresses[i];
            params.impactPricePercents[i] = impactPercent;
        }
    }

    function updateHopTokens(
        MultiStorage.HopExecutionParams memory params,
        address[] memory tokenPath
    ) internal pure {
        // Updates token addresses in execution params
        params.tokenPath = tokenPath;
    }

    function updateHopSettings(
        MultiStorage.HopExecutionParams memory params,
        uint8 settleType,
        uint256 maxIterations
    ) internal pure {
        // Updates settle type and max iterations in execution params
        params.settleType = settleType;
        params.maxIterations = maxIterations;
    }

    function prepareHopExecution(
        address[] memory listingAddresses,
        uint256 impactPercent,
        address[] memory tokenPath,
        uint8 settleType,
        uint256 maxIterations,
        MultiStorage.HopPrepData memory prepData
    ) internal returns (MultiStorage.HopExecutionParams memory params) {
        // Prepares execution parameters and initializes hop
        updateHopListings(params, listingAddresses, impactPercent);
        updateHopTokens(params, tokenPath);
        updateHopSettings(params, settleType, maxIterations);
        initializeHopData(listingAddresses, impactPercent, tokenPath, settleType, maxIterations, prepData.indices, prepData.hopId, prepData.maker);
    }

    function hopNative(
        address[] memory listingAddresses,
        uint256 impactPercent,
        address[] memory tokenPath,
        uint8 settleType,
        uint256 maxIterations
    ) external payable nonReentrant onlyValidListing(listingAddresses[0]) {
        // Initiates a native hop
        require(msg.sender != address(0), "Caller cannot be zero address");
        require(tokenPath[0] == address(0), "Start token must be native");
        require(tokenPath[0] != tokenPath[tokenPath.length - 1], "Start and end tokens cannot be identical");
        require(impactPercent <= 1000, "Impact percent exceeds 1000");
        require(settleType <= 1, "Invalid settle type");
        require(maxIterations > 0, "Max iterations must be positive");
        require(msg.value > 0, "Native amount must be positive");
        for (uint256 i = 1; i < listingAddresses.length; i++) {
            (bool isValid, ) = ICCAgent(multiStorage.agent()).isValidListing(listingAddresses[i]);
            require(listingAddresses[i] == address(0) || isValid, "Invalid listing");
        }
        MultiStorage.HopPrepData memory prepData = prepHop(listingAddresses, impactPercent, tokenPath, settleType, maxIterations, msg.sender, true);
        MultiStorage.HopExecutionParams memory params = prepareHopExecution(listingAddresses, impactPercent, tokenPath, settleType, maxIterations, prepData);
        emit HopStarted(prepData.hopId, msg.sender, params.numListings);
    }

    function hopToken(
        address[] memory listingAddresses,
        uint256 impactPercent,
        address[] memory tokenPath,
        uint8 settleType,
        uint256 maxIterations
    ) external nonReentrant onlyValidListing(listingAddresses[0]) {
        // Initiates a token hop
        require(msg.sender != address(0), "Caller cannot be zero address");
        require(tokenPath[0] != address(0), "Start token must be ERC20");
        require(tokenPath[0] != tokenPath[tokenPath.length - 1], "Start and end tokens cannot be identical");
        require(impactPercent <= 1000, "Impact percent exceeds 1000");
        require(settleType <= 1, "Invalid settle type");
        require(maxIterations > 0, "Max iterations must be positive");
        require(impactPercent > 0, "Token amount must be positive");
        for (uint256 i = 1; i < listingAddresses.length; i++) {
            (bool isValid, ) = ICCAgent(multiStorage.agent()).isValidListing(listingAddresses[i]);
            require(listingAddresses[i] == address(0) || isValid, "Invalid listing");
        }
        MultiStorage.HopPrepData memory prepData = prepHop(listingAddresses, impactPercent, tokenPath, settleType, maxIterations, msg.sender, false);
        MultiStorage.HopExecutionParams memory params = prepareHopExecution(listingAddresses, impactPercent, tokenPath, settleType, maxIterations, prepData);
        emit HopStarted(prepData.hopId, msg.sender, params.numListings);
    }

    function setOrderStatus(MultiStorage.HopUpdateType[] memory updates, uint256 index) internal pure {
        // Sets order status in updates array
        require(index < updates.length, "Invalid update index");
        updates[index] = MultiStorage.HopUpdateType({ field: "status", value: uint256(1) });
    }

    function setOrderAmount(MultiStorage.HopUpdateType[] memory updates, uint256 index, string memory orderType, uint256 amount) internal pure {
        // Sets order amount in updates array
        require(index < updates.length, "Invalid update index");
        updates[index] = MultiStorage.HopUpdateType({ field: orderType, value: amount });
    }

    function setOrderPrice(MultiStorage.HopUpdateType[] memory updates, uint256 index, string memory priceType, uint256 price) internal pure {
        // Sets order price in updates array
        require(index < updates.length, "Invalid update index");
        updates[index] = MultiStorage.HopUpdateType({ field: priceType, value: price });
    }

    function setOrderRecipient(MultiStorage.HopUpdateType[] memory updates, uint256 index, address recipient) internal pure {
        // Sets order recipient in updates array
        require(index < updates.length, "Invalid update index");
        updates[index] = MultiStorage.HopUpdateType({ field: "recipient", value: uint256(uint160(recipient)) });
    }
}