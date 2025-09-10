// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.3
// Changes:
// - v0.1.4: Modified _updateOrder to call ccUpdate for each UpdateType separately, ensuring one struct per call.
// - v0.1.3: Modified settleOrders to fetch live balances, price, and current historical volumes instead of using latest historical data entry for new historical data creation. Uses volumeBalances and prices functions from listingContract for live data.
// - v0.1.2: Adjusted settleOrders to create new historical data entry as listing only increases volumes of latest entry on order updates. 
// - v0.1.1: Fixed TypeError by replacing `listingContract.update` with `listingContract.ccUpdate` in `_updateOrder` to align with CCSettlementPartial.sol v0.1.3 and CCUniPartial.sol v0.1.5. Ensured `context.updates` is converted to `updateType`, `updateSort`, `updateData` arrays for `ccUpdate`. Compatible with CCListingTemplate.sol v0.1.12, CCMainPartial.sol v0.1.1, CCUniPartial.sol v0.1.5, CCSettlementPartial.sol v0.1.3.
// - v0.1.0: Bumped version
// - v0.0.13: Refactored settleOrders to resolve stack-too-deep error per "do x64" instruction. Split into helper functions (_validateOrder, _processOrder, _updateOrder) with OrderContext struct (orderId, pending, status, updates) to manage at most 4 variables per function. Ensured compatibility with CCListingTemplate.sol v0.1.12 and maintained detailed error logging for failed token transfers, Uniswap swap failures, and approvals.
// - v0.0.12: Fixed TypeError by removing `this.` from `_processBuyOrder` and `_processSellOrder` calls in `settleOrders`, as they are internal functions inherited from CCSettlementPartial.sol. Ensured compatibility with CCListingTemplate.sol v0.1.12 and maintained detailed error logging.
// - v0.0.11: Fixed TypeError by removing `this.` from `_processBuyOrder` and `_processSellOrder` calls in `settleOrders`, as they are internal functions inherited from CCSettlementPartial.sol. Ensured compatibility with CCListingTemplate.sol v0.1.12 and maintained detailed error logging.
// Compatible with CCListingTemplate.sol (v0.1.12), CCMainPartial.sol (v0.1.1), CCUniPartial.sol (v0.1.5), CCSettlementPartial.sol (v0.1.3).

import "./utils/CCSettlementPartial.sol";

contract CCSettlementRouter is CCSettlementPartial {
    struct OrderContext {
        uint256 orderId;
        uint256 pending;
        uint8 status;
        ICCListing.UpdateType[] updates;
    }

    function _validateOrder(
        address listingAddress,
        uint256 orderId,
        bool isBuyOrder,
        ICCListing listingContract
    ) internal view returns (OrderContext memory context) {
        // Validates order details and pricing
        context.orderId = orderId;
        (context.pending, , ) = isBuyOrder ? listingContract.getBuyOrderAmounts(orderId) : listingContract.getSellOrderAmounts(orderId);
        (, , context.status) = isBuyOrder ? listingContract.getBuyOrderCore(orderId) : listingContract.getSellOrderCore(orderId);
        if (context.pending == 0 || context.status != 1) {
            return context;
        }
        if (!_checkPricing(listingAddress, orderId, isBuyOrder, context.pending)) {
            context.pending = 0; // Mark invalid for pricing
        }
    }

    function _processOrder(
        address listingAddress,
        bool isBuyOrder,
        ICCListing listingContract,
        OrderContext memory context
    ) internal returns (OrderContext memory) {
        // Processes buy or sell order
        if (context.pending == 0 || context.status != 1) {
            return context;
        }
        context.updates = isBuyOrder
            ? _processBuyOrder(listingAddress, context.orderId, listingContract)
            : _processSellOrder(listingAddress, context.orderId, listingContract);
        return context;
    }

    function _updateOrder(
        ICCListing listingContract,
        OrderContext memory context
    ) internal returns (bool success, string memory reason) {
        if (context.updates.length == 0) {
            return (false, "");
        }
        for (uint256 i = 0; i < context.updates.length; i++) {
            uint8[] memory updateType = new uint8[](1);
            uint8[] memory updateSort = new uint8[](1);
            uint256[] memory updateData = new uint256[](1);
            updateType[0] = context.updates[i].updateType;
            updateSort[0] = context.updates[i].structId;
            if (context.updates[i].structId == 0) {
                updateData[0] = uint256(bytes32(abi.encode(context.updates[i].addr, context.updates[i].recipient, uint8(context.updates[i].value))));
            } else if (context.updates[i].structId == 1) {
                updateData[0] = uint256(bytes32(abi.encode(context.updates[i].maxPrice, context.updates[i].minPrice)));
            } else if (context.updates[i].structId == 2) {
                updateData[0] = uint256(bytes32(abi.encode(context.updates[i].value, context.updates[i].amountSent)));
            }
            try listingContract.ccUpdate(updateType, updateSort, updateData) {
                (, , context.status) = listingContract.getBuyOrderCore(context.orderId);
                if (context.status == 0 || context.status == 3) {
                    return (false, "");
                }
            } catch Error(string memory updateReason) {
                return (false, string(abi.encodePacked("Update failed for order ", uint2str(context.orderId), ": ", updateReason)));
            } catch {
                return (false, string(abi.encodePacked("Update failed for order ", uint2str(context.orderId), ": Unexpected error")));
            }
        }
        return (true, "");
    }

        // Iterates over pending orders, validates, processes, and updates via Uniswap swap
        function settleOrders(
        address listingAddress,
        uint256 step,
        uint256 maxIterations,
        bool isBuyOrder
    ) external nonReentrant onlyValidListing(listingAddress) returns (string memory reason) {
        ICCListing listingContract = ICCListing(listingAddress);
        if (uniswapV2Router == address(0)) {
            return "Missing Uniswap V2 router address";
        }
        uint256[] memory orderIds = isBuyOrder ? listingContract.pendingBuyOrdersView() : listingContract.pendingSellOrdersView();
        if (orderIds.length == 0 || step >= orderIds.length) {
            return "No pending orders or invalid step";
        }
        // Modified: Create new historical data entry using live data
        if (orderIds.length > 0) {
            // Fetch live balances and price
            (uint256 xBalance, uint256 yBalance) =  listingContract.volumeBalances(0);
            uint256 price = listingContract.prices(0);
             // Fetch current historical volumes
             uint256 historicalLength = listingContract.historicalDataLengthView();
             uint256 xVolume = 0;
            uint256 yVolume = 0;
            if (historicalLength > 0) {
                ICCListing.HistoricalData memory historicalData = listingContract.getHistoricalDataView(historicalLength - 1);
                xVolume = historicalData.xVolume;
                yVolume = historicalData.yVolume;
            }
            // Prepare ccUpdate for new historical data entry with live data
            uint8[] memory updateType = new uint8[](1);
            uint8[] memory updateSort = new uint8[](1);
            uint256[] memory updateData = new uint256[](1);
            updateType[0] = 3; // Historical update
            updateSort[0] = 0; // Historical struct
            updateData[0] = uint256(bytes32(abi.encode(
                price,
                xBalance,
                yBalance,
                xVolume,
                yVolume,
                block.timestamp
            )));
            try listingContract.ccUpdate(updateType, updateSort, updateData) {
                // Historical data entry created successfully with live data
            } catch Error(string memory updateReason) {
                return string(abi.encodePacked("Failed to create historical data entry: ", updateReason));
            }
        }
        uint256 count = 0;
        for (uint256 i = step; i < orderIds.length && count < maxIterations; i++) {
            OrderContext memory context = _validateOrder(listingAddress, orderIds[i], isBuyOrder, listingContract);
            if (context.pending == 0 || context.status != 1) {
                continue;
            }
            context = _processOrder(listingAddress, isBuyOrder, listingContract, context);
            (bool success, string memory updateReason) = _updateOrder(listingContract, context);
            if (!success && bytes(updateReason).length > 0) {
                return updateReason;
            }
            if (success) {
                count++;
            }
        }
        if (count == 0) {
            return "No orders settled: price out of range, insufficient tokens, or swap failure";
        }
        return "";
    }
    }