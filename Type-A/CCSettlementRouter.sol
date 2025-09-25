// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.9
// Changes:
// - v0.1.9: Refactored settleOrders into helper functions (_initSettlement, _createHistoricalEntry, _processOrderBatch) to resolve stack-too-deep error, using SettlementState struct to manage state. 
// - v0.1.8: Restructured settleOrders to fetch static data (tokenA, tokenB, decimalsA, decimalsB, uniswapV2Pair) once via SettlementContext. Ensured transactToken is called via _prepBuyOrderUpdate/_prepSellOrderUpdate. Removed NonCriticalNoPendingOrder, NonCriticalZeroSwapAmount events. Ensured each order’s operations complete before next. Compatible with CCUniPartial.sol v0.1.15, CCSettlementPartial.sol v0.1.12, CCMainPartial.sol v0.1.5.
// - v0.1.7: Added SettlementContext for static data, called _ensureTokenBalance for buy orders, capped maxAmountIn at 50 tokenB.
// - v0.1.6: Modified _updateOrder to use BuyOrderUpdate/SellOrderUpdate structs directly in ccUpdate, removing encoding/decoding.
// - v0.1.5: Updated to fetch live balances, price, and volumes for historical data in settleOrders.
// - v0.1.4: Modified _updateOrder to call ccUpdate per UpdateType.
// - v0.1.3: Used volumeBalances and prices for live data in settleOrders.
// - v0.1.2: Adjusted settleOrders to create new historical data entry.
// - v0.1.1: Fixed TypeError by using ccUpdate in _updateOrder.
// - v0.1.0: Bumped version.
// - v0.0.13: Refactored settleOrders to resolve stack-too-deep error.
// - v0.0.12: Removed `this.` from _processBuyOrder/_processSellOrder calls.
// - v0.0.11: Fixed TypeError by removing `this.` from internal calls.
// Compatible with CCListingTemplate.sol (v0.1.12), CCMainPartial.sol (v0.1.5), CCUniPartial.sol (v0.1.15), CCSettlementPartial.sol (v0.1.12).

import "./utils/CCSettlementPartial.sol";

contract CCSettlementRouter is CCSettlementPartial {
	
struct SettlementState {
    address listingAddress;
    bool isBuyOrder;
    uint256 step;
    uint256 maxIterations;
}
    function _validateOrder(
        address listingAddress,
        uint256 orderId,
        bool isBuyOrder,
        ICCListing listingContract
    ) internal returns (OrderContext memory context) {
        // Validates order details and pricing
        context.orderId = orderId;
        (context.pending, , ) = isBuyOrder ? listingContract.getBuyOrderAmounts(orderId) : listingContract.getSellOrderAmounts(orderId);
        (, , context.status) = isBuyOrder ? listingContract.getBuyOrderCore(orderId) : listingContract.getSellOrderCore(orderId);
        if (context.pending == 0 || context.status != 1) {
            revert(string(abi.encodePacked("Invalid order ", uint2str(orderId), ": no pending amount or status")));
        }
        if (!_checkPricing(listingAddress, orderId, isBuyOrder, context.pending)) {
            revert(string(abi.encodePacked("Price out of bounds for order ", uint2str(orderId))));
        }
    }

    function _processOrder(
    address listingAddress,
    bool isBuyOrder,
    ICCListing listingContract,
    OrderContext memory context,
    CCSettlementRouter.SettlementContext memory settlementContext
) internal returns (OrderContext memory) {
    // Processes order; updates prepared in CCUniPartial.sol, refined in CCSettlementPartial.sol, applied via ccUpdate
    if (isBuyOrder) {
        context.buyUpdates = _processBuyOrder(listingAddress, context.orderId, listingContract, settlementContext);
    } else {
        context.sellUpdates = _processSellOrder(listingAddress, context.orderId, listingContract, settlementContext);
    }
    return context;
}

    function _updateOrder(
        ICCListing listingContract,
        OrderContext memory context,
        bool isBuyOrder
    ) internal returns (bool success, string memory reason) {
        // Applies updates via ccUpdate
        if (isBuyOrder && context.buyUpdates.length == 0 || !isBuyOrder && context.sellUpdates.length == 0) {
            return (false, "");
        }
        try listingContract.ccUpdate(
            isBuyOrder ? context.buyUpdates : new ICCListing.BuyOrderUpdate[](0),
            isBuyOrder ? new ICCListing.SellOrderUpdate[](0) : context.sellUpdates,
            new ICCListing.BalanceUpdate[](0),
            new ICCListing.HistoricalUpdate[](0)
        ) {
            (, , context.status) = isBuyOrder
                ? listingContract.getBuyOrderCore(context.orderId)
                : listingContract.getSellOrderCore(context.orderId);
            if (context.status == 0 || context.status == 3) {
                return (false, "");
            }
            return (true, "");
        } catch Error(string memory updateReason) {
            return (false, string(abi.encodePacked("Update failed for order ", uint2str(context.orderId), ": ", updateReason)));
        }
    }

    function _initSettlement(
    address listingAddress,
    bool isBuyOrder,
    uint256 step,
    ICCListing listingContract
) private view returns (SettlementState memory state, uint256[] memory orderIds) {
    // Initializes settlement state and fetches order IDs
    if (uniswapV2Router == address(0)) {
        revert("Missing Uniswap V2 router address");
    }
    state = SettlementState({
        listingAddress: listingAddress,
        isBuyOrder: isBuyOrder,
        step: step,
        maxIterations: 0
    });
    orderIds = isBuyOrder ? listingContract.pendingBuyOrdersView() : listingContract.pendingSellOrdersView();
    if (orderIds.length == 0 || step >= orderIds.length) {
        revert("No pending orders or invalid step");
    }
}

function _createHistoricalEntry(
    ICCListing listingContract
) private returns (ICCListing.HistoricalUpdate[] memory historicalUpdates) {
    // Creates historical data entry
    (uint256 xBalance, uint256 yBalance) = listingContract.volumeBalances(0);
    uint256 price = listingContract.prices(0);
    uint256 xVolume = 0;
    uint256 yVolume = 0;
    uint256 historicalLength = listingContract.historicalDataLengthView();
    if (historicalLength > 0) {
        ICCListing.HistoricalData memory historicalData = listingContract.getHistoricalDataView(historicalLength - 1);
        xVolume = historicalData.xVolume;
        yVolume = historicalData.yVolume;
    }
    historicalUpdates = new ICCListing.HistoricalUpdate[](1);
    historicalUpdates[0] = ICCListing.HistoricalUpdate({
        price: price,
        xBalance: xBalance,
        yBalance: yBalance,
        xVolume: xVolume,
        yVolume: yVolume,
        timestamp: block.timestamp
    });
    try listingContract.ccUpdate(
        new ICCListing.BuyOrderUpdate[](0),
        new ICCListing.SellOrderUpdate[](0),
        new ICCListing.BalanceUpdate[](0),
        historicalUpdates
    ) {} catch Error(string memory updateReason) {
        revert(string(abi.encodePacked("Failed to create historical data entry: ", updateReason)));
    }
}

function _processOrderBatch(
    SettlementState memory state,
    uint256[] memory orderIds,
    ICCListing listingContract,
    SettlementContext memory settlementContext
) private returns (uint256 count) {
    // Processes batch of orders
    count = 0;
    for (uint256 i = state.step; i < orderIds.length && count < state.maxIterations; i++) {
        OrderContext memory context = _validateOrder(state.listingAddress, orderIds[i], state.isBuyOrder, listingContract);
        context = _processOrder(state.listingAddress, state.isBuyOrder, listingContract, context, settlementContext);
        (bool success, string memory updateReason) = _updateOrder(listingContract, context, state.isBuyOrder);
        if (!success && bytes(updateReason).length > 0) {
            revert(updateReason);
        }
        if (success) {
            count++;
        }
    }
}

function settleOrders(
    address listingAddress,
    uint256 step,
    uint256 maxIterations,
    bool isBuyOrder
) external nonReentrant onlyValidListing(listingAddress) returns (string memory reason) {
    // Iterates over pending orders, completes each order fully
    ICCListing listingContract = ICCListing(listingAddress);
    SettlementContext memory settlementContext = SettlementContext({
        tokenA: listingContract.tokenA(),
        tokenB: listingContract.tokenB(),
        decimalsA: listingContract.decimalsA(),
        decimalsB: listingContract.decimalsB(),
        uniswapV2Pair: listingContract.uniswapV2PairView()
    });
    (SettlementState memory state, uint256[] memory orderIds) = _initSettlement(listingAddress, isBuyOrder, step, listingContract);
    state.maxIterations = maxIterations;
    _createHistoricalEntry(listingContract);
    uint256 count = _processOrderBatch(state, orderIds, listingContract, settlementContext);
    if (count == 0) {
        return "No orders settled: price out of range or swap failure";
    }
    return "";
}
}