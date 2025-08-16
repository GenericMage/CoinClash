// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.2.3
// Changes:
// - v0.2.3: Refactored view functions (getAllUserOrders, getAllUserTokenOrders, getAllTokenOrders, getAllListingOrders, getAllUserLiquidity, getAllUserTokenLiquidity, getAllTokenLiquidity, getAllTemplateLiquidity) into internal call trees per "do x64". Added private structs (OrderData, SlotData) and helper functions to manage data, ensuring no function handles >4 variables. Fixed "stack too deep" in getAllUserTokenLiquidity.
// - v0.2.2: Modified view functions to return OrderGroup/SlotGroup structs for hyphen-delimited readability on Etherscan.
// - v0.2.1: Added liquidity view functions with step/maxIterations for gas efficiency. Uses ICCLiquidityTemplate for slot data.
// - v0.2.0: Simplified contract, removed unused mappings/arrays. Added globalizeOrders, globalizeLiquidity. Restricted calls via agent.
// - v0.1.5: Removed step/maxIterations from token view functions.
// - v0.1.4: Removed maxIterations/step from getAllMakerActiveOrders, getAllMakerOrders.
// - v0.1.3: Fixed parser error in globalizeOrders, added helpers.
// - v0.1.2: Refactored view functions with count/collect helpers.
// - v0.1.1: Added globalizeOrders, mappings, arrays, view functions.
// - v0.1.0: Initial globalizeLiquidity implementation.

import "../imports/Ownable.sol";

interface IERC20 {
    function decimals() external view returns (uint8);
}

interface ICCLiquidityTemplate {
    function listingAddress() external view returns (address);
    function userIndexView(address user) external view returns (uint256[] memory indices);
    function getXSlotView(uint256 index) external view returns (Slot memory slot);
    function getYSlotView(uint256 index) external view returns (Slot memory slot);
    function activeXLiquiditySlotsView() external view returns (uint256[] memory slots);
    function activeYLiquiditySlotsView() external view returns (uint256[] memory slots);
    struct Slot {
        address depositor;
        address recipient;
        uint256 allocation;
        uint256 dFeesAcc;
        uint256 timestamp;
    }
}

interface ICCListingTemplate {
    function makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations) external view returns (uint256[] memory orderIds);
    function makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations) external view returns (uint256[] memory orderIds);
    function pendingBuyOrdersView() external view returns (uint256[] memory orderIds);
    function pendingSellOrdersView() external view returns (uint256[] memory orderIds);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
}

interface ICCAgent {
    function isValidListing(address listingAddress) external view returns (bool isValid, ListingDetails memory details);
    struct ListingDetails {
        address listingAddress;
        address liquidityAddress;
        address tokenA;
        address tokenB;
        uint256 listingId;
    }
}

contract CCGlobalizer is Ownable {
    address public agent;
    mapping(address => mapping(address => address[])) public makerTokensByListing; // maker -> listing -> tokens
    mapping(address => mapping(address => address[])) public depositorTokensByLiquidity; // depositor -> liquidity -> tokens
    mapping(address => address[]) public makerListings; // maker -> listings
    mapping(address => address[]) public depositorLiquidityTemplates; // depositor -> liquidity templates
    mapping(address => address[]) public tokenListings; // token -> listings
    mapping(address => address[]) public tokenLiquidityTemplates; // token -> liquidity templates

    // Structs for grouped output
    struct OrderGroup {
        address listing;
        uint256[] orderIds;
    }
    struct SlotGroup {
        address template;
        uint256[] slotIndices;
        bool[] isX;
    }

    // Private structs for internal data management
    struct OrderData {
        uint256[] buyIds;
        uint256[] sellIds;
        uint256 totalOrders;
    }
    struct SlotData {
        uint256[] slotIndices;
        bool[] isX;
        uint256 totalSlots;
    }

    event AgentSet(address indexed agent);
    event OrdersGlobalized(address indexed maker, address indexed listing, address indexed token);
    event LiquidityGlobalized(address indexed depositor, address indexed liquidity, address indexed token);

    // Sets agent address, callable once by owner
    function setAgent(address _agent) external onlyOwner {
        if (agent != address(0) || _agent == address(0)) return;
        agent = _agent;
        emit AgentSet(_agent);
    }

    // Updates maker order mappings, callable by valid listings
    function globalizeOrders(address maker, address token) external {
        if (agent == address(0)) return;
        (bool isValid, ICCAgent.ListingDetails memory details) = ICCAgent(agent).isValidListing(msg.sender);
        if (!isValid) return;
        if (details.tokenA != token && details.tokenB != token) return;

        // Update mappings and arrays
        if (!isInArray(makerTokensByListing[maker][msg.sender], token)) {
            makerTokensByListing[maker][msg.sender].push(token);
        }
        if (!isInArray(makerListings[maker], msg.sender)) {
            makerListings[maker].push(msg.sender);
        }
        if (!isInArray(tokenListings[token], msg.sender)) {
            tokenListings[token].push(msg.sender);
        }
        emit OrdersGlobalized(maker, msg.sender, token);
    }

    // Updates depositor liquidity mappings, callable by valid liquidity templates
    function globalizeLiquidity(address depositor, address token) external {
        if (agent == address(0)) return;
        address listingAddress;
        try ICCLiquidityTemplate(msg.sender).listingAddress() returns (address addr) {
            listingAddress = addr;
        } catch {
            return;
        }
        (bool isValid, ICCAgent.ListingDetails memory details) = ICCAgent(agent).isValidListing(listingAddress);
        if (!isValid || details.liquidityAddress != msg.sender) return;
        if (details.tokenA != token && details.tokenB != token) return;

        // Update mappings and arrays
        if (!isInArray(depositorTokensByLiquidity[depositor][msg.sender], token)) {
            depositorTokensByLiquidity[depositor][msg.sender].push(token);
        }
        if (!isInArray(depositorLiquidityTemplates[depositor], msg.sender)) {
            depositorLiquidityTemplates[depositor].push(msg.sender);
        }
        if (!isInArray(tokenLiquidityTemplates[token], msg.sender)) {
            tokenLiquidityTemplates[token].push(msg.sender);
        }
        emit LiquidityGlobalized(depositor, msg.sender, token);
    }

    // Helper: Fetches order data for a listing
    function _fetchOrderData(address listing, address user) internal view returns (OrderData memory) {
        uint256[] memory buyIds = ICCListingTemplate(listing).makerPendingBuyOrdersView(user, 0, type(uint256).max);
        uint256[] memory sellIds = ICCListingTemplate(listing).makerPendingSellOrdersView(user, 0, type(uint256).max);
        return OrderData(buyIds, sellIds, buyIds.length + sellIds.length);
    }

    // Helper: Combines order IDs
    function _combineOrderIds(OrderData memory data) internal pure returns (uint256[] memory) {
        uint256[] memory combinedIds = new uint256[](data.totalOrders);
        uint256 index = 0;
        for (uint256 i = 0; i < data.buyIds.length; i++) {
            combinedIds[index] = data.buyIds[i];
            index++;
        }
        for (uint256 i = 0; i < data.sellIds.length; i++) {
            combinedIds[index] = data.sellIds[i];
            index++;
        }
        return combinedIds;
    }

    // Returns all user order IDs grouped by listing
    function getAllUserOrders(address user, uint256 step, uint256 maxIterations) external view returns (OrderGroup[] memory orderGroups) {
        uint256 length = makerListings[user].length;
        if (step >= length) return new OrderGroup[](0);
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        orderGroups = new OrderGroup[](limit);

        for (uint256 i = step; i < step + limit; i++) {
            address listing = makerListings[user][i];
            OrderData memory data = _fetchOrderData(listing, user);
            orderGroups[i - step] = OrderGroup(listing, _combineOrderIds(data));
        }
    }

    // Helper: Counts valid listings for a token
    function _countValidListings(address user, address token, uint256 step, uint256 maxIterations) internal view returns (uint256) {
        uint256 length = makerListings[user].length;
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        uint256 validCount = 0;
        for (uint256 i = step; i < step + limit; i++) {
            if (isInArray(makerTokensByListing[user][makerListings[user][i]], token)) {
                validCount++;
            }
        }
        return validCount;
    }

    // Returns user order IDs for a specific token grouped by listing
    function getAllUserTokenOrders(address user, address token, uint256 step, uint256 maxIterations) external view returns (OrderGroup[] memory orderGroups) {
        uint256 length = makerListings[user].length;
        if (step >= length) return new OrderGroup[](0);
        uint256 validCount = _countValidListings(user, token, step, maxIterations);
        orderGroups = new OrderGroup[](validCount);
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        uint256 index = 0;

        for (uint256 i = step; i < step + limit && index < validCount; i++) {
            address listing = makerListings[user][i];
            if (isInArray(makerTokensByListing[user][listing], token)) {
                OrderData memory data = _fetchOrderData(listing, user);
                orderGroups[index] = OrderGroup(listing, _combineOrderIds(data));
                index++;
            }
        }
    }

    // Helper: Fetches token order data
    function _fetchTokenOrderData(address listing) internal view returns (OrderData memory) {
        uint256[] memory buyIds = ICCListingTemplate(listing).pendingBuyOrdersView();
        uint256[] memory sellIds = ICCListingTemplate(listing).pendingSellOrdersView();
        return OrderData(buyIds, sellIds, buyIds.length + sellIds.length);
    }

    // Returns all order IDs for a token grouped by listing
    function getAllTokenOrders(address token, uint256 step, uint256 maxIterations) external view returns (OrderGroup[] memory orderGroups) {
        uint256 length = tokenListings[token].length;
        if (step >= length) return new OrderGroup[](0);
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        orderGroups = new OrderGroup[](limit);

        for (uint256 i = step; i < step + limit; i++) {
            address listing = tokenListings[token][i];
            OrderData memory data = _fetchTokenOrderData(listing);
            orderGroups[i - step] = OrderGroup(listing, _combineOrderIds(data));
        }
    }

    // Helper: Fetches listing order data
    function _fetchListingOrderData(address listing, uint256 step, uint256 maxIterations) internal view returns (OrderData memory) {
        uint256[] memory buyIds = ICCListingTemplate(listing).pendingBuyOrdersView();
        uint256[] memory sellIds = ICCListingTemplate(listing).pendingSellOrdersView();
        uint256 length = buyIds.length + sellIds.length;
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        uint256[] memory combinedIds = new uint256[](limit);
        uint256 index = 0;

        for (uint256 i = step; i < step + limit && i < buyIds.length && index < limit; i++) {
            combinedIds[index] = buyIds[i];
            index++;
        }
        for (uint256 i = step; i < step + limit && i < sellIds.length && index < limit; i++) {
            combinedIds[index] = sellIds[i];
            index++;
        }
        return OrderData(combinedIds, new uint256[](0), index);
    }

    // Returns all order IDs for a listing
    function getAllListingOrders(address listing, uint256 step, uint256 maxIterations) external view returns (OrderGroup memory orderGroup) {
        OrderData memory data = _fetchListingOrderData(listing, step, maxIterations);
        return OrderGroup(listing, data.buyIds);
    }

    // Helper: Fetches slot data for a template
    function _fetchSlotData(address template, address user) internal view returns (SlotData memory) {
        uint256[] memory indices = ICCLiquidityTemplate(template).userIndexView(user);
        uint256[] memory slotIndices = new uint256[](indices.length);
        bool[] memory isX = new bool[](indices.length);
        uint256 index = 0;

        for (uint256 i = 0; i < indices.length; i++) {
            ICCLiquidityTemplate.Slot memory slot = ICCLiquidityTemplate(template).getXSlotView(indices[i]);
            if (slot.depositor == user && slot.allocation > 0) {
                slotIndices[index] = indices[i];
                isX[index] = true;
                index++;
            } else {
                slot = ICCLiquidityTemplate(template).getYSlotView(indices[i]);
                if (slot.depositor == user && slot.allocation > 0) {
                    slotIndices[index] = indices[i];
                    isX[index] = false;
                    index++;
                }
            }
        }
        uint256[] memory resizedIndices = new uint256[](index);
        bool[] memory resizedIsX = new bool[](index);
        for (uint256 i = 0; i < index; i++) {
            resizedIndices[i] = slotIndices[i];
            resizedIsX[i] = isX[i];
        }
        return SlotData(resizedIndices, resizedIsX, index);
    }

    // Returns all user liquidity slot indices grouped by template
    function getAllUserLiquidity(address user, uint256 step, uint256 maxIterations) external view returns (SlotGroup[] memory slotGroups) {
        uint256 length = depositorLiquidityTemplates[user].length;
        if (step >= length) return new SlotGroup[](0);
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        slotGroups = new SlotGroup[](limit);

        for (uint256 i = step; i < step + limit; i++) {
            address template = depositorLiquidityTemplates[user][i];
            SlotData memory data = _fetchSlotData(template, user);
            slotGroups[i - step] = SlotGroup(template, data.slotIndices, data.isX);
        }
    }

    // Helper: Counts valid templates for a token
    function _countValidTemplates(address user, address token, uint256 step, uint256 maxIterations) internal view returns (uint256) {
        uint256 length = depositorLiquidityTemplates[user].length;
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        uint256 validCount = 0;
        for (uint256 i = step; i < step + limit; i++) {
            if (isInArray(depositorTokensByLiquidity[user][depositorLiquidityTemplates[user][i]], token)) {
                validCount++;
            }
        }
        return validCount;
    }

    // Returns user liquidity slot indices for a specific token grouped by template
    function getAllUserTokenLiquidity(address user, address token, uint256 step, uint256 maxIterations) external view returns (SlotGroup[] memory slotGroups) {
        uint256 length = depositorLiquidityTemplates[user].length;
        if (step >= length) return new SlotGroup[](0);
        uint256 validCount = _countValidTemplates(user, token, step, maxIterations);
        slotGroups = new SlotGroup[](validCount);
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        uint256 index = 0;

        for (uint256 i = step; i < step + limit && index < validCount; i++) {
            address template = depositorLiquidityTemplates[user][i];
            if (isInArray(depositorTokensByLiquidity[user][template], token)) {
                SlotData memory data = _fetchSlotData(template, user);
                slotGroups[index] = SlotGroup(template, data.slotIndices, data.isX);
                index++;
            }
        }
    }

    // Helper: Fetches token slot data
    function _fetchTokenSlotData(address template) internal view returns (SlotData memory) {
        uint256[] memory xSlots = ICCLiquidityTemplate(template).activeXLiquiditySlotsView();
        uint256[] memory ySlots = ICCLiquidityTemplate(template).activeYLiquiditySlotsView();
        uint256[] memory slotIndices = new uint256[](xSlots.length + ySlots.length);
        bool[] memory isX = new bool[](xSlots.length + ySlots.length);
        uint256 index = 0;

        for (uint256 i = 0; i < xSlots.length; i++) {
            ICCLiquidityTemplate.Slot memory slot = ICCLiquidityTemplate(template).getXSlotView(xSlots[i]);
            if (slot.allocation > 0) {
                slotIndices[index] = xSlots[i];
                isX[index] = true;
                index++;
            }
        }
        for (uint256 i = 0; i < ySlots.length; i++) {
            ICCLiquidityTemplate.Slot memory slot = ICCLiquidityTemplate(template).getYSlotView(ySlots[i]);
            if (slot.allocation > 0) {
                slotIndices[index] = ySlots[i];
                isX[index] = false;
                index++;
            }
        }
        uint256[] memory resizedIndices = new uint256[](index);
        bool[] memory resizedIsX = new bool[](index);
        for (uint256 i = 0; i < index; i++) {
            resizedIndices[i] = slotIndices[i];
            resizedIsX[i] = isX[i];
        }
        return SlotData(resizedIndices, resizedIsX, index);
    }

    // Returns all liquidity slot indices for a token grouped by template
    function getAllTokenLiquidity(address token, uint256 step, uint256 maxIterations) external view returns (SlotGroup[] memory slotGroups) {
        uint256 length = tokenLiquidityTemplates[token].length;
        if (step >= length) return new SlotGroup[](0);
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        slotGroups = new SlotGroup[](limit);

        for (uint256 i = step; i < step + limit; i++) {
            address template = tokenLiquidityTemplates[token][i];
            SlotData memory data = _fetchTokenSlotData(template);
            slotGroups[i - step] = SlotGroup(template, data.slotIndices, data.isX);
        }
    }

    // Helper: Fetches template slot data
    function _fetchTemplateSlotData(address template, uint256 step, uint256 maxIterations) internal view returns (SlotData memory) {
        uint256[] memory xSlots = ICCLiquidityTemplate(template).activeXLiquiditySlotsView();
        uint256[] memory ySlots = ICCLiquidityTemplate(template).activeYLiquiditySlotsView();
        uint256 length = xSlots.length + ySlots.length;
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        uint256[] memory slotIndices = new uint256[](limit);
        bool[] memory isX = new bool[](limit);
        uint256 index = 0;

        for (uint256 i = step; i < step + limit && i < xSlots.length && index < limit; i++) {
            ICCLiquidityTemplate.Slot memory slot = ICCLiquidityTemplate(template).getXSlotView(xSlots[i]);
            if (slot.allocation > 0) {
                slotIndices[index] = xSlots[i];
                isX[index] = true;
                index++;
            }
        }
        for (uint256 i = step; i < step + limit && i < ySlots.length && index < limit; i++) {
            ICCLiquidityTemplate.Slot memory slot = ICCLiquidityTemplate(template).getYSlotView(ySlots[i]);
            if (slot.allocation > 0) {
                slotIndices[index] = ySlots[i];
                isX[index] = false;
                index++;
            }
        }
        uint256[] memory resizedIndices = new uint256[](index);
        bool[] memory resizedIsX = new bool[](index);
        for (uint256 i = 0; i < index; i++) {
            resizedIndices[i] = slotIndices[i];
            resizedIsX[i] = isX[i];
        }
        return SlotData(resizedIndices, resizedIsX, index);
    }

    // Returns all liquidity slot indices for a template
    function getAllTemplateLiquidity(address template, uint256 step, uint256 maxIterations) external view returns (SlotGroup memory slotGroup) {
        SlotData memory data = _fetchTemplateSlotData(template, step, maxIterations);
        return SlotGroup(template, data.slotIndices, data.isX);
    }

    // Helper to check if an address is in an array
    function isInArray(address[] memory array, address element) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == element) return true;
        }
        return false;
    }
}