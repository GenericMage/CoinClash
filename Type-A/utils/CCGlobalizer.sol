// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.2.1
// Changes:
// - v0.2.1: Added liquidity view functions: getAllUserLiquidity, getAllUserTokenLiquidity, getAllTokenLiquidity, getAllTemplateLiquidity with step/maxIterations for gas efficiency. Uses ICCLiquidityTemplate for slot data.
// - v0.2.0: Simplified contract, removed unused mappings/arrays. Added globalizeOrders with makerTokensByListing, globalizeLiquidity with depositorTokensByLiquidity. Restricted calls to valid listings/liquidity templates via agent. Added view functions with step/maxIterations. Ensured non-reverting behavior.
// - v0.1.5: Removed step/maxIterations from token view functions to reduce stack usage.
// - v0.1.4: Removed maxIterations/step from getAllMakerActiveOrders, getAllMakerOrders.
// - v0.1.3: Fixed parser error in globalizeOrders, added helper functions.
// - v0.1.2: Refactored view functions with count/collect helpers.
// - v0.1.1: Added globalizeOrders, mappings, arrays, view functions.
// - v0.1.0: Initial implementation with globalizeLiquidity.

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

    // Returns all user order IDs across listings
    function getAllUserOrders(address user, uint256 step, uint256 maxIterations) external view returns (address[] memory listings, uint256[] memory orderIds) {
        uint256 length = makerListings[user].length;
        if (step >= length) return (new address[](0), new uint256[](0));
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        uint256 totalOrders = 0;

        // Count total orders
        for (uint256 i = step; i < step + limit; i++) {
            address listing = makerListings[user][i];
            uint256[] memory buyIds = ICCListingTemplate(listing).makerPendingBuyOrdersView(user, 0, type(uint256).max);
            uint256[] memory sellIds = ICCListingTemplate(listing).makerPendingSellOrdersView(user, 0, type(uint256).max);
            totalOrders += buyIds.length + sellIds.length;
        }

        // Collect orders
        listings = new address[](totalOrders);
        orderIds = new uint256[](totalOrders);
        uint256 index = 0;
        for (uint256 i = step; i < step + limit && index < totalOrders; i++) {
            address listing = makerListings[user][i];
            uint256[] memory buyIds = ICCListingTemplate(listing).makerPendingBuyOrdersView(user, 0, type(uint256).max);
            uint256[] memory sellIds = ICCListingTemplate(listing).makerPendingSellOrdersView(user, 0, type(uint256).max);
            for (uint256 j = 0; j < buyIds.length && index < totalOrders; j++) {
                listings[index] = listing;
                orderIds[index] = buyIds[j];
                index++;
            }
            for (uint256 j = 0; j < sellIds.length && index < totalOrders; j++) {
                listings[index] = listing;
                orderIds[index] = sellIds[j];
                index++;
            }
        }
    }

    // Returns user order IDs for a specific token
    function getAllUserTokenOrders(address user, address token, uint256 step, uint256 maxIterations) external view returns (address[] memory listings, uint256[] memory orderIds) {
        uint256 length = makerListings[user].length;
        if (step >= length) return (new address[](0), new uint256[](0));
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        uint256 totalOrders = 0;

        // Count total orders for token
        for (uint256 i = step; i < step + limit; i++) {
            address listing = makerListings[user][i];
            if (isInArray(makerTokensByListing[user][listing], token)) {
                uint256[] memory buyIds = ICCListingTemplate(listing).makerPendingBuyOrdersView(user, 0, type(uint256).max);
                uint256[] memory sellIds = ICCListingTemplate(listing).makerPendingSellOrdersView(user, 0, type(uint256).max);
                totalOrders += buyIds.length + sellIds.length;
            }
        }

        // Collect orders
        listings = new address[](totalOrders);
        orderIds = new uint256[](totalOrders);
        uint256 index = 0;
        for (uint256 i = step; i < step + limit && index < totalOrders; i++) {
            address listing = makerListings[user][i];
            if (isInArray(makerTokensByListing[user][listing], token)) {
                uint256[] memory buyIds = ICCListingTemplate(listing).makerPendingBuyOrdersView(user, 0, type(uint256).max);
                uint256[] memory sellIds = ICCListingTemplate(listing).makerPendingSellOrdersView(user, 0, type(uint256).max);
                for (uint256 j = 0; j < buyIds.length && index < totalOrders; j++) {
                    listings[index] = listing;
                    orderIds[index] = buyIds[j];
                    index++;
                }
                for (uint256 j = 0; j < sellIds.length && index < totalOrders; j++) {
                    listings[index] = listing;
                    orderIds[index] = sellIds[j];
                    index++;
                }
            }
        }
    }

    // Returns all order IDs for a token
    function getAllTokenOrders(address token, uint256 step, uint256 maxIterations) external view returns (address[] memory listings, uint256[] memory orderIds) {
        uint256 length = tokenListings[token].length;
        if (step >= length) return (new address[](0), new uint256[](0));
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        uint256 totalOrders = 0;

        // Count total orders
        for (uint256 i = step; i < step + limit; i++) {
            address listing = tokenListings[token][i];
            uint256[] memory buyIds = ICCListingTemplate(listing).pendingBuyOrdersView();
            uint256[] memory sellIds = ICCListingTemplate(listing).pendingSellOrdersView();
            totalOrders += buyIds.length + sellIds.length;
        }

        // Collect orders
        listings = new address[](totalOrders);
        orderIds = new uint256[](totalOrders);
        uint256 index = 0;
        for (uint256 i = step; i < step + limit && index < totalOrders; i++) {
            address listing = tokenListings[token][i];
            uint256[] memory buyIds = ICCListingTemplate(listing).pendingBuyOrdersView();
            uint256[] memory sellIds = ICCListingTemplate(listing).pendingSellOrdersView();
            for (uint256 j = 0; j < buyIds.length && index < totalOrders; j++) {
                listings[index] = listing;
                orderIds[index] = buyIds[j];
                index++;
            }
            for (uint256 j = 0; j < sellIds.length && index < totalOrders; j++) {
                listings[index] = listing;
                orderIds[index] = sellIds[j];
                index++;
            }
        }
    }

    // Returns all order IDs for a listing
    function getAllListingOrders(address listing, uint256 step, uint256 maxIterations) external view returns (uint256[] memory orderIds) {
        uint256[] memory buyIds = ICCListingTemplate(listing).pendingBuyOrdersView();
        uint256[] memory sellIds = ICCListingTemplate(listing).pendingSellOrdersView();
        uint256 length = buyIds.length + sellIds.length;
        if (step >= length) return new uint256[](0);
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        orderIds = new uint256[](limit);
        uint256 index = 0;

        for (uint256 i = step; i < step + limit && i < buyIds.length; i++) {
            orderIds[index] = buyIds[i];
            index++;
        }
        for (uint256 i = step; i < step + limit && i < sellIds.length && index < limit; i++) {
            orderIds[index] = sellIds[i];
            index++;
        }
    }

    // Returns all user liquidity slot indices across templates
    function getAllUserLiquidity(address user, uint256 step, uint256 maxIterations) external view returns (address[] memory templates, uint256[] memory slotIndices, bool[] memory isX) {
        uint256 length = depositorLiquidityTemplates[user].length;
        if (step >= length) return (new address[](0), new uint256[](0), new bool[](0));
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        uint256 totalSlots = 0;

        // Count total slots
        for (uint256 i = step; i < step + limit; i++) {
            address template = depositorLiquidityTemplates[user][i];
            uint256[] memory indices = ICCLiquidityTemplate(template).userIndexView(user);
            totalSlots += indices.length;
        }

        // Collect slots
        templates = new address[](totalSlots);
        slotIndices = new uint256[](totalSlots);
        isX = new bool[](totalSlots);
        uint256 index = 0;
        for (uint256 i = step; i < step + limit && index < totalSlots; i++) {
            address template = depositorLiquidityTemplates[user][i];
            uint256[] memory indices = ICCLiquidityTemplate(template).userIndexView(user);
            for (uint256 j = 0; j < indices.length && index < totalSlots; j++) {
                ICCLiquidityTemplate.Slot memory slot = ICCLiquidityTemplate(template).getXSlotView(indices[j]);
                if (slot.depositor == user && slot.allocation > 0) {
                    templates[index] = template;
                    slotIndices[index] = indices[j];
                    isX[index] = true;
                    index++;
                } else {
                    slot = ICCLiquidityTemplate(template).getYSlotView(indices[j]);
                    if (slot.depositor == user && slot.allocation > 0) {
                        templates[index] = template;
                        slotIndices[index] = indices[j];
                        isX[index] = false;
                        index++;
                    }
                }
            }
        }
    }

    // Returns user liquidity slot indices for a specific token
    function getAllUserTokenLiquidity(address user, address token, uint256 step, uint256 maxIterations) external view returns (address[] memory templates, uint256[] memory slotIndices, bool[] memory isX) {
        uint256 length = depositorLiquidityTemplates[user].length;
        if (step >= length) return (new address[](0), new uint256[](0), new bool[](0));
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        uint256 totalSlots = 0;

        // Count total slots for token
        for (uint256 i = step; i < step + limit; i++) {
            address template = depositorLiquidityTemplates[user][i];
            if (isInArray(depositorTokensByLiquidity[user][template], token)) {
                uint256[] memory indices = ICCLiquidityTemplate(template).userIndexView(user);
                totalSlots += indices.length;
            }
        }

        // Collect slots
        templates = new address[](totalSlots);
        slotIndices = new uint256[](totalSlots);
        isX = new bool[](totalSlots);
        uint256 index = 0;
        for (uint256 i = step; i < step + limit && index < totalSlots; i++) {
            address template = depositorLiquidityTemplates[user][i];
            if (isInArray(depositorTokensByLiquidity[user][template], token)) {
                uint256[] memory indices = ICCLiquidityTemplate(template).userIndexView(user);
                for (uint256 j = 0; j < indices.length && index < totalSlots; j++) {
                    ICCLiquidityTemplate.Slot memory slot = ICCLiquidityTemplate(template).getXSlotView(indices[j]);
                    if (slot.depositor == user && slot.allocation > 0) {
                        templates[index] = template;
                        slotIndices[index] = indices[j];
                        isX[index] = true;
                        index++;
                    } else {
                        slot = ICCLiquidityTemplate(template).getYSlotView(indices[j]);
                        if (slot.depositor == user && slot.allocation > 0) {
                            templates[index] = template;
                            slotIndices[index] = indices[j];
                            isX[index] = false;
                            index++;
                        }
                    }
                }
            }
        }
    }

    // Returns all liquidity slot indices for a token
    function getAllTokenLiquidity(address token, uint256 step, uint256 maxIterations) external view returns (address[] memory templates, uint256[] memory slotIndices, bool[] memory isX) {
        uint256 length = tokenLiquidityTemplates[token].length;
        if (step >= length) return (new address[](0), new uint256[](0), new bool[](0));
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        uint256 totalSlots = 0;

        // Count total slots
        for (uint256 i = step; i < step + limit; i++) {
            address template = tokenLiquidityTemplates[token][i];
            uint256[] memory xSlots = ICCLiquidityTemplate(template).activeXLiquiditySlotsView();
            uint256[] memory ySlots = ICCLiquidityTemplate(template).activeYLiquiditySlotsView();
            totalSlots += xSlots.length + ySlots.length;
        }

        // Collect slots
        templates = new address[](totalSlots);
        slotIndices = new uint256[](totalSlots);
        isX = new bool[](totalSlots);
        uint256 index = 0;
        for (uint256 i = step; i < step + limit && index < totalSlots; i++) {
            address template = tokenLiquidityTemplates[token][i];
            uint256[] memory xSlots = ICCLiquidityTemplate(template).activeXLiquiditySlotsView();
            uint256[] memory ySlots = ICCLiquidityTemplate(template).activeYLiquiditySlotsView();
            for (uint256 j = 0; j < xSlots.length && index < totalSlots; j++) {
                ICCLiquidityTemplate.Slot memory slot = ICCLiquidityTemplate(template).getXSlotView(xSlots[j]);
                if (slot.allocation > 0) {
                    templates[index] = template;
                    slotIndices[index] = xSlots[j];
                    isX[index] = true;
                    index++;
                }
            }
            for (uint256 j = 0; j < ySlots.length && index < totalSlots; j++) {
                ICCLiquidityTemplate.Slot memory slot = ICCLiquidityTemplate(template).getYSlotView(ySlots[j]);
                if (slot.allocation > 0) {
                    templates[index] = template;
                    slotIndices[index] = ySlots[j];
                    isX[index] = false;
                    index++;
                }
            }
        }
    }

    // Returns all liquidity slot indices for a template
    function getAllTemplateLiquidity(address template, uint256 step, uint256 maxIterations) external view returns (uint256[] memory slotIndices, bool[] memory isX) {
        uint256[] memory xSlots = ICCLiquidityTemplate(template).activeXLiquiditySlotsView();
        uint256[] memory ySlots = ICCLiquidityTemplate(template).activeYLiquiditySlotsView();
        uint256 length = xSlots.length + ySlots.length;
        if (step >= length) return (new uint256[](0), new bool[](0));
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        slotIndices = new uint256[](limit);
        isX = new bool[](limit);
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
    }

    // Helper to check if an address is in an array
    function isInArray(address[] memory array, address element) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == element) return true;
        }
        return false;
    }
}