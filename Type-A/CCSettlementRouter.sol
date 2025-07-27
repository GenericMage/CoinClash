// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.5
// Changes:
// - v0.0.5: Removed SafeERC20 usage, rely on IERC20 from CCMainPartial.sol, no transfer success checks, ensured pre/post balance checks in dependencies.
// - v0.0.4: Removed liquid settlement functions and dependencies from CCSettlementPartial.sol, removed ICCLiquidity interface, retained Uniswap V2 settlement.
// - v0.0.3: Replaced ISSListingTemplate with ICCListing, updated UpdateType references.
// - v0.0.2: Updated settleBuyOrders and settleSellOrders to use Uniswap V2 swaps.
// - v0.0.1: Created CCSettlementRouter.sol, extracted settlement functions from SSRouter.sol v0.0.61, retained setAgent.
// Compatible with ICCListing.sol (v0.0.3), CCMainPartial.sol (v0.0.07), CCUniPartial.sol (v0.0.7).

import "./utils/CCSettlementPartial.sol";

contract CCSettlementRouter is CCSettlementPartial {
    function settleBuyOrders(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Settles multiple buy orders up to maxIterations using Uniswap V2 swaps, collecting updates
        ICCListing listingContract = ICCListing(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.pendingBuyOrdersView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ICCListing.UpdateType[] memory tempUpdates = new ICCListing.UpdateType[](iterationCount * 2);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            uint256 orderIdent = orderIdentifiers[i];
            ICCListing.UpdateType[] memory updates = _processBuyOrder(listingAddress, orderIdent, listingContract);
            if (updates.length == 0) {
                continue;
            }
            for (uint256 j = 0; j < updates.length; j++) {
                tempUpdates[updateIndex++] = updates[j];
            }
        }
        ICCListing.UpdateType[] memory finalUpdates = new ICCListing.UpdateType[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalUpdates[i] = tempUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.update(address(this), finalUpdates);
        }
    }

    function settleSellOrders(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Settles multiple sell orders up to maxIterations using Uniswap V2 swaps, collecting updates
        ICCListing listingContract = ICCListing(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.pendingSellOrdersView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ICCListing.UpdateType[] memory tempUpdates = new ICCListing.UpdateType[](iterationCount * 2);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            uint256 orderIdent = orderIdentifiers[i];
            ICCListing.UpdateType[] memory updates = _processSellOrder(listingAddress, orderIdent, listingContract);
            if (updates.length == 0) {
                continue;
            }
            for (uint256 j = 0; j < updates.length; j++) {
                tempUpdates[updateIndex++] = updates[j];
            }
        }
        ICCListing.UpdateType[] memory finalUpdates = new ICCListing.UpdateType[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalUpdates[i] = tempUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.update(address(this), finalUpdates);
        }
    }
}