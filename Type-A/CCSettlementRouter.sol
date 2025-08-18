// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.8
// Changes:
// - v0.0.8: Removed redundant uint2str function to avoid override conflict, inheriting from CCSettlementPartial.sol. Maintained pending amount validation and error logging in settleOrders.
// - v0.0.7: Added validation for pending amounts in settleOrders before calling _processBuyOrder/_processSellOrder. Enhanced error logging in settleOrders with specific revert reasons for failed updates. Added try-catch for listingContract.update to capture and log detailed errors. Added iteration over pending orders with maxIterations check.
// - v0.0.6: Initial implementation of settleOrders function to iterate over pending orders.
// Compatible with CCListingTemplate.sol (v0.1.7), CCMainPartial.sol (v0.0.14), CCUniPartial.sol (v0.0.7), CCSettlementPartial.sol (v0.0.20).

import "./utils/CCSettlementPartial.sol";

contract CCSettlementRouter is CCSettlementPartial {
    function settleOrders(
        address listingAddress,
        uint256 step,
        uint256 maxIterations,
        bool isBuyOrder
    ) external nonReentrant onlyValidListing(listingAddress) {
        // Iterates over pending buy or sell orders, validates price impact, and settles via Uniswap swap
        ICCListing listingContract = ICCListing(listingAddress);
        uint256[] memory orderIds = isBuyOrder ? listingContract.pendingBuyOrdersView() : listingContract.pendingSellOrdersView();
        uint256 count = 0;
        for (uint256 i = step; i < orderIds.length && count < maxIterations; i++) {
            uint256 orderId = orderIds[i];
            (uint256 pending, , ) = isBuyOrder ? listingContract.getBuyOrderAmounts(orderId) : listingContract.getSellOrderAmounts(orderId);
            if (pending == 0) continue;
            if (!_checkPricing(listingAddress, orderId, isBuyOrder, pending)) continue;
            ICCListing.UpdateType[] memory updates = isBuyOrder
                ? _processBuyOrder(listingAddress, orderId, listingContract)
                : _processSellOrder(listingAddress, orderId, listingContract);
            if (updates.length > 0) {
                try listingContract.update(updates) {
                    count++;
                } catch Error(string memory reason) {
                    revert(string(abi.encodePacked("Update failed for order ", uint2str(orderId), ": ", reason)));
                } catch (bytes memory reason) {
                    revert(string(abi.encodePacked("Update failed for order ", uint2str(orderId), ": Unknown error")));
                }
            }
        }
        require(count > 0, "No orders settled");
    }
}