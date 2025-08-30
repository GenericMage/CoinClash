/*
 SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025

 Version: 0.0.20
 Changes:
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
    event InsufficientBalance(address indexed listingAddress, uint256 required, uint256 available);

    function settleBuyLiquid(address listingAddress, uint256 maxIterations, uint256 step) external onlyValidListing(listingAddress) nonReentrant {
    // Settles multiple buy order liquidations starting from step up to maxIterations
    ICCListing listingContract = ICCListing(listingAddress);
    uint256[] memory pendingOrders = listingContract.pendingBuyOrdersView();
    if (pendingOrders.length == 0 || step >= pendingOrders.length) {
        emit NoPendingOrders(listingAddress, true);
        return;
    }
    (uint256 xBalance, uint256 yBalance,,) = listingContract.listingVolumeBalancesView();
    if (yBalance == 0) {
        emit InsufficientBalance(listingAddress, 1, yBalance);
        return;
    }
    ICCListing.UpdateType[] memory updates = _processOrderBatch(listingAddress, maxIterations, true, step);
    if (updates.length > 0) {
        uint8[] memory updateType = new uint8[](updates.length);
        uint8[] memory updateSort = new uint8[](updates.length);
        uint256[] memory updateData = new uint256[](updates.length);
        for (uint256 i = 0; i < updates.length; i++) {
            updateType[i] = updates[i].updateType;
            updateSort[i] = updates[i].structId;
            updateData[i] = updates[i].value;
        }
        try listingContract.ccUpdate(updateType, updateSort, updateData) {
        } catch Error(string memory reason) {
            emit UpdateFailed(listingAddress, reason);
        } catch {
            emit UpdateFailed(listingAddress, "Unknown update error");
        }
    }
}

function settleSellLiquid(address listingAddress, uint256 maxIterations, uint256 step) external onlyValidListing(listingAddress) nonReentrant {
    // Settles multiple sell order liquidations starting from step up to maxIterations
    ICCListing listingContract = ICCListing(listingAddress);
    uint256[] memory pendingOrders = listingContract.pendingSellOrdersView();
    if (pendingOrders.length == 0 || step >= pendingOrders.length) {
        emit NoPendingOrders(listingAddress, false);
        return;
    }
    (uint256 xBalance, uint256 yBalance,,) = listingContract.listingVolumeBalancesView();
    if (xBalance == 0) {
        emit InsufficientBalance(listingAddress, 1, xBalance);
        return;
    }
    ICCListing.UpdateType[] memory updates = _processOrderBatch(listingAddress, maxIterations, false, step);
    if (updates.length > 0) {
        uint8[] memory updateType = new uint8[](updates.length);
        uint8[] memory updateSort = new uint8[](updates.length);
        uint256[] memory updateData = new uint256[](updates.length);
        for (uint256 i = 0; i < updates.length; i++) {
            updateType[i] = updates[i].updateType;
            updateSort[i] = updates[i].structId;
            updateData[i] = updates[i].value;
        }
        try listingContract.ccUpdate(updateType, updateSort, updateData) {
        } catch Error(string memory reason) {
            emit UpdateFailed(listingAddress, reason);
        } catch {
            emit UpdateFailed(listingAddress, "Unknown update error");
        }
    }
}
}