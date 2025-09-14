/*
 SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025

 Version: 0.0.25
Changes: 
- v0.0.25: Updated settleBuyLiquid, settleSellLiquid, and _createHistoricalUpdate to use CCListingTemplate.sol v0.3.9 ccUpdate with BuyOrderUpdate, SellOrderUpdate, BalanceUpdate, HistoricalUpdate structs. Removed array-based updates.
 - v0.0.24: Modified settleBuyLiquid, settleSellLiquid in CCLiquidRouter.sol to call ccUpdate separately for each ICCListing.UpdateType struct.
 - v0.0.23: Modified settleBuyLiquid and settleSellLiquid to use makerPendingOrdersView for msg.sender's orders. I
 - v0.0.22: Refactored settleBuy/SellLiquid to resolve "Stack too deep" error. Moved historical data update logic to _createHistoricalUpdate helper function using HistoricalUpdateContext struct with ≤4 variables. 
 - v0.0.21: Updated settleBuyLiquid and settleSellLiquid to create a new historical data entry using live data from listingContract.volumeBalances(0) and listingContract.prices(0) before processing orders.
 - v0.0.20: Replaced listingContract.update(updates) with listingContract.ccUpdate(updateType, updateSort, updateData) in settleBuyLiquid and settleSellLiquid to align with CCListingTemplate.sol v0.3.0 and CCLiquidPartial.sol v0.0.28. Converted updates to three arrays for ccUpdate.
 - v0.0.19: Updated compatibility with CCLiquidPartial.sol v0.0.25, which removes listingContract.update() from _prepBuyOrderUpdate and _prepSellOrderUpdate, ensuring single update in _processOrderBatch. Aligned with fixed liquidity balance updates in _processSingleOrder using differences. Compatible with CCListingTemplate.sol v0.2.0, CCMainPartial.sol v0.0.14, CCLiquidityTemplate.sol v0.1.3, CCLiquidPartial.sol v0.0.25.
 - v0.0.18: Removed duplicate _processOrderBatch function to resolve TypeError, relying on CCLiquidPartial.sol implementation. Removed redundant UpdateFailed event.
 - v0.0.17: Fixed _processOrderBatch to correctly decrease liquidity by adjusting ICCLiquidity.UpdateType value calculation.
 - v0.0.16: Updated _processOrderBatch to pass step parameter to _collectOrderIdentifiers.
 - v0.0.15: Added step parameter to settleBuyLiquid and settleSellLiquid for gas-efficient settlement.
 - v0.0.14: Updated compatibility with CCLiquidPartial.sol v0.0.20.
 - v0.0.13: Updated compatibility with CCLiquidPartial.sol v0.0.19.
 - v0.0.12: Added try-catch in settleBuyLiquid and settleSellLiquid for UpdateFailed reasons.
 - v0.0.11: Fixed tuple destructuring in settleBuyLiquid and settleSellLiquid.
 - v0.0.10: Updated to use prices(0) for price calculation.
 - v0.0.9: Updated compatibility with CCLiquidPartial.sol v0.0.12.
 - v0.0.8: Moved _getSwapReserves and _computeSwapImpact to CCLiquidPartial.sol.
 - v0.0.7: Refactored settleBuyLiquid and settleSellLiquid to use helper functions.
 - v0.0.6: Updated to use depositor in ICCLiquidity.update call.
 - v0.0.5: Removed duplicated ICCListing interface.
 - v0.0.4: Updated ICCListing interface for liquidityAddressView compatibility.
 - v0.0.3: Added price impact restrictions in settleBuyLiquid and settleSellLiquid.
 - v0.0.2: Removed SafeERC20 usage, used IERC20 from CCMainPartial.
 - v0.0.1: Created CCLiquidRouter.sol from CCSettlementRouter.sol.
*/

pragma solidity ^0.8.2;

import "./utils/CCLiquidPartial.sol";

contract CCLiquidRouter is CCLiquidPartial {
    event NoPendingOrders(address indexed listingAddress, bool isBuyOrder);

    struct HistoricalUpdateContext {
    uint256 xBalance;
    uint256 yBalance;
    uint256 xVolume;
    uint256 yVolume;
}

function _createHistoricalUpdate(address listingAddress, ICCListing listingContract) private {
    // Creates historical data update using live data
    HistoricalUpdateContext memory context;
    (context.xBalance, context.yBalance) = listingContract.volumeBalances(0);
    uint256 historicalLength = listingContract.historicalDataLengthView();
    if (historicalLength > 0) {
        ICCListing.HistoricalData memory historicalData = listingContract.getHistoricalDataView(historicalLength - 1);
        context.xVolume = historicalData.xVolume;
        context.yVolume = historicalData.yVolume;
    }
    ICCListing.HistoricalUpdate memory update = ICCListing.HistoricalUpdate({
        price: listingContract.prices(0),
        xBalance: context.xBalance,
        yBalance: context.yBalance,
        xVolume: context.xVolume,
        yVolume: context.yVolume,
        timestamp: block.timestamp
    });
    ICCListing.BuyOrderUpdate[] memory buyUpdates = new ICCListing.BuyOrderUpdate[](0);
    ICCListing.SellOrderUpdate[] memory sellUpdates = new ICCListing.SellOrderUpdate[](0);
    ICCListing.BalanceUpdate[] memory balanceUpdates = new ICCListing.BalanceUpdate[](0);
    ICCListing.HistoricalUpdate[] memory historicalUpdates = new ICCListing.HistoricalUpdate[](1);
    historicalUpdates[0] = update;
    try listingContract.ccUpdate(buyUpdates, sellUpdates, balanceUpdates, historicalUpdates) {
    } catch Error(string memory reason) {
        emit UpdateFailed(listingAddress, string(abi.encodePacked("Historical update failed: ", reason)));
    }
}

function settleBuyLiquid(address listingAddress, uint256 maxIterations, uint256 step) external onlyValidListing(listingAddress) nonReentrant {
    // Settles buy orders for msg.sender
    ICCListing listingContract = ICCListing(listingAddress);
    uint256[] memory pendingOrders = listingContract.makerPendingOrdersView(msg.sender);
    if (pendingOrders.length == 0 || step >= pendingOrders.length) {
        emit NoPendingOrders(listingAddress, true);
        return;
    }
    (uint256 xBalance, uint256 yBalance) = listingContract.volumeBalances(0);
    if (yBalance == 0) {
        emit InsufficientBalance(listingAddress, 1, yBalance);
        return;
    }
    if (pendingOrders.length > 0) {
        _createHistoricalUpdate(listingAddress, listingContract);
    }
    bool success = _processOrderBatch(listingAddress, maxIterations, true, step);
    if (!success) {
        emit UpdateFailed(listingAddress, "Buy order batch processing failed");
    }
}

function settleSellLiquid(address listingAddress, uint256 maxIterations, uint256 step) external onlyValidListing(listingAddress) nonReentrant {
    // Settles sell orders for msg.sender
    ICCListing listingContract = ICCListing(listingAddress);
    uint256[] memory pendingOrders = listingContract.makerPendingOrdersView(msg.sender);
    if (pendingOrders.length == 0 || step >= pendingOrders.length) {
        emit NoPendingOrders(listingAddress, false);
        return;
    }
    (uint256 xBalance, uint256 yBalance) = listingContract.volumeBalances(0);
    if (xBalance == 0) {
        emit InsufficientBalance(listingAddress, 1, xBalance);
        return;
    }
    if (pendingOrders.length > 0) {
        _createHistoricalUpdate(listingAddress, listingContract);
    }
    bool success = _processOrderBatch(listingAddress, maxIterations, false, step);
    if (!success) {
        emit UpdateFailed(listingAddress, "Sell order batch processing failed");
    }
}
}