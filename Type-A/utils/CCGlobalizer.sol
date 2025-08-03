// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.5
// Changes:
// - v0.1.5: Removed step and maxIterations from token-related view functions (getAllTokenOrders, getAllActiveTokenOrders, viewActiveMakersByToken) to reduce stack usage, returning data directly. Fixed stack too deep errors in collectTokenOrders, collectActiveMakersOrders.
// - v0.1.4: Removed maxIterations and step from getAllMakerActiveOrders, getAllMakerOrders. Extracted token array updates to updateTokenArrays. Ensured only original mappings/arrays are public.
// - v0.1.3: Fixed parser error in globalizeOrders. Refactored globalizeOrders with clearOrderData, updateBuyOrderData, updateSellOrderData helpers and private mappings privateMakerOrders, privateTokenOrders.
// - v0.1.2: Refactored view functions to use count and collect helpers.
// - v0.1.1: Added globalizeOrders, mappings, arrays, and view functions.
// - v0.1.0: Initial implementation with globalizeLiquidity.

import "../imports/Ownable.sol";

interface IERC20 {
    function decimals() external view returns (uint8);
}

interface ICCLiquidityTemplate {
    function userXIndexView(address user) external view returns (uint256[] memory indices);
    function userYIndexView(address user) external view returns (uint256[] memory indices);
    function getXSlotView(uint256 index) external view returns (Slot memory slot);
    function getYSlotView(uint256 index) external view returns (Slot memory slot);
    function listingAddress() external view returns (address);
    struct Slot {
        address depositor;
        address recipient;
        uint256 allocation;
        uint256 dFeesAcc;
        uint256 timestamp;
    }
}

interface ICCListingTemplate {
    function liquidityAddressView() external view returns (address);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function globalizerAddressView() external view returns (address);
    function makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations) external view returns (uint256[] memory orderIds);
    function makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations) external view returns (uint256[] memory orderIds);
    function getFullBuyOrderDetails(uint256 orderId) external view returns (
        BuyOrderCore memory core,
        BuyOrderPricing memory pricing,
        BuyOrderAmounts memory amounts
    );
    function getFullSellOrderDetails(uint256 orderId) external view returns (
        SellOrderCore memory core,
        SellOrderPricing memory pricing,
        SellOrderAmounts memory amounts
    );
    struct BuyOrderCore {
        address makerAddress;
        address recipientAddress;
        uint8 status;
    }
    struct BuyOrderPricing {
        uint256 maxPrice;
        uint256 minPrice;
    }
    struct BuyOrderAmounts {
        uint256 pending;
        uint256 filled;
        uint256 amountSent;
    }
    struct SellOrderCore {
        address makerAddress;
        address recipientAddress;
        uint8 status;
    }
    struct SellOrderPricing {
        uint256 maxPrice;
        uint256 minPrice;
    }
    struct SellOrderAmounts {
        uint256 pending;
        uint256 filled;
        uint256 amountSent;
    }
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
    mapping(address => mapping(address => uint256)) public userLiquidityByToken; // token -> user -> liquidity amount
    mapping(address => mapping(address => uint256)) public userLiquidityByPool; // user -> liquidity template -> liquidity amount
    mapping(address => address[]) public userTokens; // user -> tokens provided
    mapping(address => address[]) public userPools; // user -> liquidity templates
    mapping(address => address[]) public usersToToken; // token -> users providing liquidity
    mapping(address => address[]) public poolsToToken; // token -> liquidity templates
    mapping(address => mapping(address => mapping(address => uint256[]))) public makerBuyOrdersByToken; // token -> listing -> maker -> order IDs
    mapping(address => mapping(address => mapping(address => uint256[]))) public makerSellOrdersByToken; // token -> listing -> maker -> order IDs
    mapping(address => mapping(address => mapping(address => uint256[]))) public makerActiveBuyOrdersByToken; // token -> listing -> maker -> active order IDs
    mapping(address => mapping(address => mapping(address => uint256[]))) public makerActiveSellOrdersByToken; // token -> listing -> maker -> active order IDs
    mapping(address => mapping(address => uint256[])) public makerBuyOrdersByListing; // maker -> listing -> order IDs
    mapping(address => mapping(address => uint256[])) public makerSellOrdersByListing; // maker -> listing -> order IDs
    mapping(address => address[]) public makerTokens; // maker -> tokens with orders
    mapping(address => address[]) public makerActiveTokens; // maker -> tokens with active orders
    mapping(address => address[]) public makerListings; // maker -> listings with orders
    mapping(address => address[]) public makerActiveListings; // maker -> listings with active orders
    address[] public makersToTokens; // makers with orders
    address[] public activeMakersToTokens; // makers with active orders
    mapping(address => mapping(address => OrderData[])) private privateMakerOrders; // maker -> listing -> order data
    mapping(address => OrderData[]) private privateTokenOrders; // token -> order data

    struct OrderData {
        address maker;
        address listing;
        address token;
        uint256 orderId;
        uint256 amount;
        bool isBuy;
    }

    event LiquidityGlobalized(address indexed user, address indexed token, address indexed pool, uint256 amount);
    event AgentSet(address indexed agent);
    event OrdersGlobalized(address indexed maker, address indexed listing, address indexed token, uint256[] orderIds, bool isBuy);

    // Temporary storage for maker order collection
    struct TempMakerOrderData {
        address[] tokens;
        address[] listings;
        uint256[] orderIds;
        bool[] isBuy;
        uint256 index;
    }

    // Temporary storage for token order collection
    struct TempOrderData {
        address[] makers;
        address[] listings;
        uint256[] orderIds;
        uint256[] amounts;
        bool[] isBuy;
        uint256 index;
    }

    // Sets agent address, callable once by owner
    function setAgent(address _agent) external onlyOwner {
        require(agent == address(0), "Agent already set");
        require(_agent != address(0), "Invalid agent address");
        agent = _agent;
        emit AgentSet(_agent);
    }

    // Updates user liquidity mappings based on liquidity template slots
    function globalizeLiquidity(address user, address liquidityTemplate) external {
        require(agent != address(0), "Agent not set");
        require(liquidityTemplate != address(0), "Invalid liquidity template");

        // Verify liquidity template via listing address
        address listingAddress;
        try ICCLiquidityTemplate(liquidityTemplate).listingAddress() returns (address addr) {
            listingAddress = addr;
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Listing fetch failed: ", reason)));
        }
        require(listingAddress != address(0), "Invalid listing address");

        (bool isValid, ICCAgent.ListingDetails memory details) = ICCAgent(agent).isValidListing(listingAddress);
        if (!isValid || details.liquidityAddress != liquidityTemplate) {
            revert("Invalid liquidity template");
        }

        // Fetch slot indices
        uint256[] memory xIndices;
        uint256[] memory yIndices;
        try ICCLiquidityTemplate(liquidityTemplate).userXIndexView(user) returns (uint256[] memory indices) {
            xIndices = indices;
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("X indices fetch failed: ", reason)));
        }
        try ICCLiquidityTemplate(liquidityTemplate).userYIndexView(user) returns (uint256[] memory indices) {
            yIndices = indices;
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Y indices fetch failed: ", reason)));
        }

        // Calculate total liquidity for tokens
        address tokenA = details.tokenA;
        address tokenB = details.tokenB;
        uint256 totalX = 0;
        uint256 totalY = 0;

        for (uint256 i = 0; i < xIndices.length; i++) {
            ICCLiquidityTemplate.Slot memory slot;
            try ICCLiquidityTemplate(liquidityTemplate).getXSlotView(xIndices[i]) returns (ICCLiquidityTemplate.Slot memory s) {
                slot = s;
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("X slot fetch failed: ", reason)));
            }
            if (slot.depositor == user) {
                totalX += slot.allocation;
            }
        }

        for (uint256 i = 0; i < yIndices.length; i++) {
            ICCLiquidityTemplate.Slot memory slot;
            try ICCLiquidityTemplate(liquidityTemplate).getYSlotView(yIndices[i]) returns (ICCLiquidityTemplate.Slot memory s) {
                slot = s;
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Y slot fetch failed: ", reason)));
            }
            if (slot.depositor == user) {
                totalY += slot.allocation;
            }
        }

        // Update mappings and arrays
        updateLiquidityMappings(user, liquidityTemplate, tokenA, tokenB, totalX, totalY);
    }

    // Updates order data mappings for buy orders
    function updateBuyOrderData(
        address maker,
        address listing,
        address token,
        uint256[] memory buyOrderIds
    ) internal returns (OrderData[] memory orders) {
        orders = new OrderData[](buyOrderIds.length);
        uint256 index = 0;
        for (uint256 i = 0; i < buyOrderIds.length; i++) {
            (ICCListingTemplate.BuyOrderCore memory core, , ICCListingTemplate.BuyOrderAmounts memory amounts) = ICCListingTemplate(listing).getFullBuyOrderDetails(buyOrderIds[i]);
            if (core.status == 1) {
                orders[index] = OrderData(maker, listing, token, buyOrderIds[i], amounts.pending, true);
                index++;
            }
        }
        // Resize array if not all orders are active
        if (index < buyOrderIds.length) {
            OrderData[] memory resized = new OrderData[](index);
            for (uint256 i = 0; i < index; i++) {
                resized[i] = orders[i];
            }
            orders = resized;
        }
    }

    // Updates order data mappings for sell orders
    function updateSellOrderData(
        address maker,
        address listing,
        address token,
        uint256[] memory sellOrderIds
    ) internal returns (OrderData[] memory orders) {
        orders = new OrderData[](sellOrderIds.length);
        uint256 index = 0;
        for (uint256 i = 0; i < sellOrderIds.length; i++) {
            (ICCListingTemplate.SellOrderCore memory core, , ICCListingTemplate.SellOrderAmounts memory amounts) = ICCListingTemplate(listing).getFullSellOrderDetails(sellOrderIds[i]);
            if (core.status == 1) {
                orders[index] = OrderData(maker, listing, token, sellOrderIds[i], amounts.pending, false);
                index++;
            }
        }
        // Resize array if not all orders are active
        if (index < sellOrderIds.length) {
            OrderData[] memory resized = new OrderData[](index);
            for (uint256 i = 0; i < index; i++) {
                resized[i] = orders[i];
            }
            orders = resized;
        }
    }

    // Clears existing order data for a maker and listing
    function clearOrderData(address maker, address listing, address tokenA, address tokenB) internal {
        delete privateMakerOrders[maker][listing];
        // Remove existing tokenActiveOrders entries for this maker and listing
        for (uint256 i = 0; i < privateTokenOrders[tokenA].length; i++) {
            if (privateTokenOrders[tokenA][i].maker == maker && privateTokenOrders[tokenA][i].listing == listing) {
                privateTokenOrders[tokenA][i] = privateTokenOrders[tokenA][privateTokenOrders[tokenA].length - 1];
                privateTokenOrders[tokenA].pop();
                i--;
            }
        }
        for (uint256 i = 0; i < privateTokenOrders[tokenB].length; i++) {
            if (privateTokenOrders[tokenB][i].maker == maker && privateTokenOrders[tokenB][i].listing == listing) {
                privateTokenOrders[tokenB][i] = privateTokenOrders[tokenB][privateTokenOrders[tokenB].length - 1];
                privateTokenOrders[tokenB].pop();
                i--;
            }
        }
    }

    // Updates token-related arrays for makers
    function updateTokenArrays(address maker, address listing, address token, bool isBuy) internal {
        if (!isInArray(makerTokens[maker], token)) {
            makerTokens[maker].push(token);
        }
        if (!isInArray(makerActiveTokens[maker], token)) {
            makerActiveTokens[maker].push(token);
        }
        if (!isInArray(makerListings[maker], listing)) {
            makerListings[maker].push(listing);
        }
        if (!isInArray(makerActiveListings[maker], listing)) {
            makerActiveListings[maker].push(listing);
        }
        if (!isInArray(makersToTokens, maker)) {
            makersToTokens.push(maker);
        }
        if (!isInArray(activeMakersToTokens, maker)) {
            activeMakersToTokens.push(maker);
        }
    }

    // Updates order mappings for a maker in a listing, fetching pending orders
    function globalizeOrders(address maker, address listing) external {
        require(agent != address(0), "Agent not set");
        require(listing != address(0), "Invalid listing address");

        // Verify listing
        (bool isValid, ICCAgent.ListingDetails memory details) = ICCAgent(agent).isValidListing(listing);
        if (!isValid) {
            revert("Invalid listing");
        }

        // Verify globalizer address
        address globalizer;
        try ICCListingTemplate(listing).globalizerAddressView() returns (address addr) {
            globalizer = addr;
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Globalizer fetch failed: ", reason)));
        }
        require(globalizer == address(this), "Not authorized globalizer");

        uint256 gasBefore = gasleft();
        address tokenA = details.tokenA;
        address tokenB = details.tokenB;
        uint256 maxIterations = 100; // Gas safety limit

        // Fetch pending orders
        uint256[] memory buyOrderIds;
        uint256[] memory sellOrderIds;
        try ICCListingTemplate(listing).makerPendingBuyOrdersView(maker, 0, maxIterations) returns (uint256[] memory ids) {
            buyOrderIds = ids;
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Buy orders fetch failed: ", reason)));
        }
        try ICCListingTemplate(listing).makerPendingSellOrdersView(maker, 0, maxIterations) returns (uint256[] memory ids) {
            sellOrderIds = ids;
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Sell orders fetch failed: ", reason)));
        }

        // Clear existing order data
        clearOrderData(maker, listing, tokenA, tokenB);

        // Update buy orders
        if (buyOrderIds.length > 0) {
            makerBuyOrdersByToken[tokenB][listing][maker] = buyOrderIds;
            makerActiveBuyOrdersByToken[tokenB][listing][maker] = buyOrderIds;
            makerBuyOrdersByListing[maker][listing] = buyOrderIds;
            updateTokenArrays(maker, listing, tokenB, true);
            OrderData[] memory buyOrders = updateBuyOrderData(maker, listing, tokenB, buyOrderIds);
            for (uint256 i = 0; i < buyOrders.length; i++) {
                privateMakerOrders[maker][listing].push(buyOrders[i]);
                privateTokenOrders[tokenB].push(buyOrders[i]);
            }
            emit OrdersGlobalized(maker, listing, tokenB, buyOrderIds, true);
        } else {
            delete makerActiveBuyOrdersByToken[tokenB][listing][maker];
            if (makerActiveBuyOrdersByToken[tokenB][listing][maker].length == 0 && makerActiveSellOrdersByToken[tokenB][listing][maker].length == 0) {
                removeMakerFromActiveTokens(maker, tokenB);
                removeMakerFromActiveListings(maker, listing);
            }
        }

        // Update sell orders
        if (sellOrderIds.length > 0) {
            makerSellOrdersByToken[tokenA][listing][maker] = sellOrderIds;
            makerActiveSellOrdersByToken[tokenA][listing][maker] = sellOrderIds;
            makerSellOrdersByListing[maker][listing] = sellOrderIds;
            updateTokenArrays(maker, listing, tokenA, false);
            OrderData[] memory sellOrders = updateSellOrderData(maker, listing, tokenA, sellOrderIds);
            for (uint256 i = 0; i < sellOrders.length; i++) {
                privateMakerOrders[maker][listing].push(sellOrders[i]);
                privateTokenOrders[tokenA].push(sellOrders[i]);
            }
            emit OrdersGlobalized(maker, listing, tokenA, sellOrderIds, false);
        } else {
            delete makerActiveSellOrdersByToken[tokenA][listing][maker];
            if (makerActiveBuyOrdersByToken[tokenA][listing][maker].length == 0 && makerActiveSellOrdersByToken[tokenA][listing][maker].length == 0) {
                removeMakerFromActiveTokens(maker, tokenA);
                removeMakerFromActiveListings(maker, listing);
            }
        }

        // Update makersToTokens and activeMakersToTokens for no orders case
        if (buyOrderIds.length == 0 && sellOrderIds.length == 0) {
            removeMakerFromActiveMakers(maker);
        }

        if (gasleft() < gasBefore / 10) {
            revert("Gas usage too high");
        }
    }

    // Counts active orders for a maker across tokens and listings
    function countMakerActiveOrders(address maker) internal view returns (uint256 totalOrders) {
        for (uint256 i = 0; i < makerActiveListings[maker].length; i++) {
            address listing = makerActiveListings[maker][i];
            totalOrders += privateMakerOrders[maker][listing].length;
        }
    }

    // Initializes TempMakerOrderData for order collection
    function initMakerOrderData(uint256 totalOrders) internal pure returns (TempMakerOrderData memory data) {
        data.tokens = new address[](totalOrders);
        data.listings = new address[](totalOrders);
        data.orderIds = new uint256[](totalOrders);
        data.isBuy = new bool[](totalOrders);
        data.index = 0;
    }

    // Collects active orders for a maker from mappings
    function collectMakerActiveOrders(
        address maker,
        uint256 totalOrders
    ) internal view returns (
        address[] memory tokens,
        address[] memory listings,
        uint256[] memory orderIds,
        bool[] memory isBuy
    ) {
        TempMakerOrderData memory data = initMakerOrderData(totalOrders);
        for (uint256 i = 0; i < makerActiveListings[maker].length && data.index < totalOrders; i++) {
            address listing = makerActiveListings[maker][i];
            OrderData[] memory orders = privateMakerOrders[maker][listing];
            for (uint256 j = 0; j < orders.length && data.index < totalOrders; j++) {
                data.tokens[data.index] = orders[j].token;
                data.listings[data.index] = orders[j].listing;
                data.orderIds[data.index] = orders[j].orderId;
                data.isBuy[data.index] = orders[j].isBuy;
                data.index++;
            }
        }
        return (data.tokens, data.listings, data.orderIds, data.isBuy);
    }

    // Returns all active orders for a maker across tokens and listings
    function getAllMakerActiveOrders(address maker) external view returns (
        address[] memory tokens,
        address[] memory listings,
        uint256[] memory orderIds,
        bool[] memory isBuy
    ) {
        uint256 totalOrders = countMakerActiveOrders(maker);
        return collectMakerActiveOrders(maker, totalOrders);
    }

    // Counts all orders for a maker across tokens and listings
    function countMakerAllOrders(address maker) internal view returns (uint256 totalOrders) {
        for (uint256 i = 0; i < makerTokens[maker].length; i++) {
            address token = makerTokens[maker][i];
            for (uint256 j = 0; j < makerListings[maker].length; j++) {
                address listing = makerListings[maker][j];
                totalOrders += makerBuyOrdersByToken[token][listing][maker].length;
                totalOrders += makerSellOrdersByToken[token][listing][maker].length;
            }
        }
    }

    // Collects all orders for a maker across tokens and listings
    function collectMakerAllOrders(
        address maker,
        uint256 totalOrders
    ) internal view returns (
        address[] memory tokens,
        address[] memory listings,
        uint256[] memory orderIds,
        bool[] memory isBuy
    ) {
        TempMakerOrderData memory data = initMakerOrderData(totalOrders);
        for (uint256 i = 0; i < makerTokens[maker].length && data.index < totalOrders; i++) {
            address token = makerTokens[maker][i];
            for (uint256 j = 0; j < makerListings[maker].length && data.index < totalOrders; j++) {
                address listing = makerListings[maker][j];
                uint256[] memory buyIds = makerBuyOrdersByToken[token][listing][maker];
                for (uint256 k = 0; k < buyIds.length && data.index < totalOrders; k++) {
                    data.tokens[data.index] = token;
                    data.listings[data.index] = listing;
                    data.orderIds[data.index] = buyIds[k];
                    data.isBuy[data.index] = true;
                    data.index++;
                }
                uint256[] memory sellIds = makerSellOrdersByToken[token][listing][maker];
                for (uint256 k = 0; k < sellIds.length && data.index < totalOrders; k++) {
                    data.tokens[data.index] = token;
                    data.listings[data.index] = listing;
                    data.orderIds[data.index] = sellIds[k];
                    data.isBuy[data.index] = false;
                    data.index++;
                }
            }
        }
        return (data.tokens, data.listings, data.orderIds, data.isBuy);
    }

    // Returns all orders for a maker across tokens and listings
    function getAllMakerOrders(address maker) external view returns (
        address[] memory tokens,
        address[] memory listings,
        uint256[] memory orderIds,
        bool[] memory isBuy
    ) {
        uint256 totalOrders = countMakerAllOrders(maker);
        return collectMakerAllOrders(maker, totalOrders);
    }

    // Counts active orders for a token across makers and listings
    function countActiveTokenOrders(address token) internal view returns (uint256 totalOrders) {
        totalOrders = privateTokenOrders[token].length;
    }

    // Initializes TempOrderData for order collection
    function initTokenOrderData(uint256 totalOrders) internal pure returns (TempOrderData memory data) {
        data.makers = new address[](totalOrders);
        data.listings = new address[](totalOrders);
        data.orderIds = new uint256[](totalOrders);
        data.amounts = new uint256[](totalOrders);
        data.isBuy = new bool[](totalOrders);
        data.index = 0;
    }

    // Collects active orders for a token from mappings
    function collectActiveTokenOrders(
        address token,
        uint256 totalOrders
    ) internal view returns (
        address[] memory makers,
        address[] memory listings,
        uint256[] memory orderIds,
        bool[] memory isBuy
    ) {
        TempOrderData memory data = initTokenOrderData(totalOrders);
        for (uint256 i = 0; i < privateTokenOrders[token].length && data.index < totalOrders; i++) {
            OrderData memory order = privateTokenOrders[token][i];
            data.makers[data.index] = order.maker;
            data.listings[data.index] = order.listing;
            data.orderIds[data.index] = order.orderId;
            data.isBuy[data.index] = order.isBuy;
            data.index++;
        }
        return (data.makers, data.listings, data.orderIds, data.isBuy);
    }

    // Returns all active orders for a token across makers and listings
    function getAllActiveTokenOrders(address token) external view returns (
        address[] memory makers,
        address[] memory listings,
        uint256[] memory orderIds,
        bool[] memory isBuy
    ) {
        uint256 totalOrders = countActiveTokenOrders(token);
        return collectActiveTokenOrders(token, totalOrders);
    }

    // Counts all orders for a token across makers and listings
    function countTokenOrders(address token) internal view returns (uint256 totalOrders) {
        for (uint256 i = 0; i < makersToTokens.length; i++) {
            address maker = makersToTokens[i];
            for (uint256 j = 0; j < makerListings[maker].length; j++) {
                address listing = makerListings[maker][j];
                totalOrders += makerBuyOrdersByToken[token][listing][maker].length;
                totalOrders += makerSellOrdersByToken[token][listing][maker].length;
            }
        }
    }

    // Collects all orders for a token across makers and listings
    function collectTokenOrders(
        address token,
        uint256 totalOrders
    ) internal view returns (
        address[] memory makers,
        address[] memory listings,
        uint256[] memory orderIds,
        bool[] memory isBuy
    ) {
        TempOrderData memory data = initTokenOrderData(totalOrders);
        for (uint256 i = 0; i < makersToTokens.length && data.index < totalOrders; i++) {
            address maker = makersToTokens[i];
            for (uint256 j = 0; j < makerListings[maker].length && data.index < totalOrders; j++) {
                address listing = makerListings[maker][j];
                uint256[] memory buyIds = makerBuyOrdersByToken[token][listing][maker];
                for (uint256 k = 0; k < buyIds.length && data.index < totalOrders; k++) {
                    data.makers[data.index] = maker;
                    data.listings[data.index] = listing;
                    data.orderIds[data.index] = buyIds[k];
                    data.isBuy[data.index] = true;
                    data.index++;
                }
                uint256[] memory sellIds = makerSellOrdersByToken[token][listing][maker];
                for (uint256 k = 0; k < sellIds.length && data.index < totalOrders; k++) {
                    data.makers[data.index] = maker;
                    data.listings[data.index] = listing;
                    data.orderIds[data.index] = sellIds[k];
                    data.isBuy[data.index] = false;
                    data.index++;
                }
            }
        }
        return (data.makers, data.listings, data.orderIds, data.isBuy);
    }

    // Returns all orders for a token across makers and listings
    function getAllTokenOrders(address token) external view returns (
        address[] memory makers,
        address[] memory listings,
        uint256[] memory orderIds,
        bool[] memory isBuy
    ) {
        uint256 totalOrders = countTokenOrders(token);
        return collectTokenOrders(token, totalOrders);
    }

    // Counts active makers and their orders for a token
    function countActiveMakersOrders(address token) internal view returns (uint256 totalOrders) {
        totalOrders = privateTokenOrders[token].length;
    }

    // Collects active makers, their orders, and amounts for a token
    function collectActiveMakersOrders(
        address token,
        uint256 totalOrders
    ) internal view returns (
        address[] memory makers,
        address[] memory listings,
        uint256[] memory orderIds,
        uint256[] memory amounts,
        bool[] memory isBuy
    ) {
        TempOrderData memory data = initTokenOrderData(totalOrders);
        for (uint256 i = 0; i < privateTokenOrders[token].length && data.index < totalOrders; i++) {
            OrderData memory order = privateTokenOrders[token][i];
            data.makers[data.index] = order.maker;
            data.listings[data.index] = order.listing;
            data.orderIds[data.index] = order.orderId;
            data.amounts[data.index] = order.amount;
            data.isBuy[data.index] = order.isBuy;
            data.index++;
        }
        return (data.makers, data.listings, data.orderIds, data.amounts, data.isBuy);
    }

    // Returns active makers, their orders, amounts, and types for a token
    function viewActiveMakersByToken(address token) external view returns (
        address[] memory makers,
        address[] memory listings,
        uint256[] memory orderIds,
        uint256[] memory amounts,
        bool[] memory isBuy
    ) {
        uint256 totalOrders = countActiveMakersOrders(token);
        return collectActiveMakersOrders(token, totalOrders);
    }

    // Internal helper to update liquidity mappings and arrays
    function updateLiquidityMappings(address user, address liquidityTemplate, address tokenA, address tokenB, uint256 totalX, uint256 totalY) internal {
        uint256 gasBefore = gasleft();
        uint256 totalLiquidity = totalX + totalY;
        userLiquidityByPool[user][liquidityTemplate] = totalLiquidity;
        if (totalLiquidity == 0) {
            removeUserPool(user, liquidityTemplate);
        } else {
            if (!isInArray(userPools[user], liquidityTemplate)) {
                userPools[user].push(liquidityTemplate);
            }
        }

        if (tokenA != address(0)) {
            userLiquidityByToken[tokenA][user] = totalX;
            if (totalX == 0) {
                removeUserToken(user, tokenA);
                removeUserFromToken(tokenA, user);
            } else {
                if (!isInArray(userTokens[user], tokenA)) {
                    userTokens[user].push(tokenA);
                }
                if (!isInArray(usersToToken[tokenA], user)) {
                    usersToToken[tokenA].push(user);
                }
                if (!isInArray(poolsToToken[tokenA], liquidityTemplate)) {
                    poolsToToken[tokenA].push(liquidityTemplate);
                }
            }
        }

        if (tokenB != address(0)) {
            userLiquidityByToken[tokenB][user] = totalY;
            if (totalY == 0) {
                removeUserToken(user, tokenB);
                removeUserFromToken(tokenB, user);
            } else {
                if (!isInArray(userTokens[user], tokenB)) {
                    userTokens[user].push(tokenB);
                }
                if (!isInArray(usersToToken[tokenB], user)) {
                    usersToToken[tokenB].push(user);
                }
                if (!isInArray(poolsToToken[tokenB], liquidityTemplate)) {
                    poolsToToken[tokenB].push(liquidityTemplate);
                }
            }
        }

        if (gasleft() < gasBefore / 10) {
            revert("Gas usage too high");
        }

        if (totalX > 0) emit LiquidityGlobalized(user, tokenA, liquidityTemplate, totalX);
        if (totalY > 0) emit LiquidityGlobalized(user, tokenB, liquidityTemplate, totalY);
    }

    // Helper to check if an address is in an array
    function isInArray(address[] memory array, address element) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == element) return true;
        }
        return false;
    }

    // Helper to remove a token from userTokens
    function removeUserToken(address user, address token) internal {
        for (uint256 i = 0; i < userTokens[user].length; i++) {
            if (userTokens[user][i] == token) {
                userTokens[user][i] = userTokens[user][userTokens[user].length - 1];
                userTokens[user].pop();
                break;
            }
        }
    }

    // Helper to remove a user from usersToToken
    function removeUserFromToken(address token, address user) internal {
        for (uint256 i = 0; i < usersToToken[token].length; i++) {
            if (usersToToken[token][i] == user) {
                usersToToken[token][i] = usersToToken[token][usersToToken[token].length - 1];
                usersToToken[token].pop();
                break;
            }
        }
    }

    // Helper to remove a pool from userPools
    function removeUserPool(address user, address pool) internal {
        for (uint256 i = 0; i < userPools[user].length; i++) {
            if (userPools[user][i] == pool) {
                userPools[user][i] = userPools[user][userPools[user].length - 1];
                userPools[user].pop();
                break;
            }
        }
    }

    // Helper to remove a token from makerActiveTokens
    function removeMakerFromActiveTokens(address maker, address token) internal {
        for (uint256 i = 0; i < makerActiveTokens[maker].length; i++) {
            if (makerActiveTokens[maker][i] == token) {
                makerActiveTokens[maker][i] = makerActiveTokens[maker][makerActiveTokens[maker].length - 1];
                makerActiveTokens[maker].pop();
                break;
            }
        }
    }

    // Helper to remove a listing from makerActiveListings
    function removeMakerFromActiveListings(address maker, address listing) internal {
        for (uint256 i = 0; i < makerActiveListings[maker].length; i++) {
            if (makerActiveListings[maker][i] == listing) {
                makerActiveListings[maker][i] = makerActiveListings[maker][makerActiveListings[maker].length - 1];
                makerActiveListings[maker].pop();
                break;
            }
        }
    }

    // Helper to remove a maker from activeMakersToTokens
    function removeMakerFromActiveMakers(address maker) internal {
        for (uint256 i = 0; i < activeMakersToTokens.length; i++) {
            if (activeMakersToTokens[i] == maker) {
                activeMakersToTokens[i] = activeMakersToTokens[activeMakersToTokens.length - 1];
                activeMakersToTokens.pop();
                break;
            }
        }
    }

    // Returns users and their liquidity for a token, up to maxIterations
    function viewProvidersByToken(address token, uint256 maxIterations) external view returns (address[] memory users, uint256[] memory amounts) {
        uint256 length = usersToToken[token].length;
        uint256 limit = maxIterations < length ? maxIterations : length;
        users = new address[](limit);
        amounts = new uint256[](limit);
        for (uint256 i = 0; i < limit; i++) {
            users[i] = usersToToken[token][i];
            amounts[i] = userLiquidityByToken[token][users[i]];
        }
    }

    // Returns user's tokens and liquidity amounts, up to maxIterations
    function getAllUserLiquidity(address user, uint256 maxIterations) external view returns (address[] memory tokens, uint256[] memory amounts) {
        uint256 length = userTokens[user].length;
        uint256 limit = maxIterations < length ? maxIterations : length;
        tokens = new address[](limit);
        amounts = new uint256[](limit);
        for (uint256 i = 0; i < limit; i++) {
            tokens[i] = userTokens[user][i];
            amounts[i] = userLiquidityByToken[tokens[i]][user];
        }
    }

    // Returns total liquidity for a token
    function getTotalTokenLiquidity(address token) external view returns (uint256 total) {
        for (uint256 i = 0; i < usersToToken[token].length; i++) {
            total += userLiquidityByToken[token][usersToToken[token][i]];
        }
    }

    // Returns liquidity template addresses for a token, starting from step, up to maxIterations
    function getTokenPools(address token, uint256 step, uint256 maxIterations) external view returns (address[] memory pools) {
        uint256 length = poolsToToken[token].length;
        if (step >= length) return new address[](0);
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        pools = new address[](limit);
        for (uint256 i = 0; i < limit; i++) {
            pools[i] = poolsToToken[token][step + i];
        }
    }
}