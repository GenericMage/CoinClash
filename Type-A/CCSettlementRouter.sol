// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.4
// Changes:
// - v0.0.4: Removed liquid settlement functions (settleBuyLiquid, settleSellLiquid) and dependencies (_prepBuyLiquidUpdates, _prepSellLiquidUpdates, executeSingleBuyLiquid, executeSingleSellLiquid, _prepareLiquidityTransaction, _checkAndTransferPrincipal, _updateLiquidity) from CCSettlementPartial.sol, removed ICCLiquidity interface, retained Uniswap V2 settlement.
// - v0.0.3: Replaced ISSListingTemplate with ICCListing from CCMainPartial.sol, updated UpdateType references to ICCListing.UpdateType.
// - v0.0.2: Updated settleBuyOrders and settleSellOrders to use Uniswap V2 swaps via _executePartialBuySwap and _executePartialSellSwap.
// - v0.0.1: Created CCSettlementRouter.sol, extracted settlement functions from SSRouter.sol v0.0.61, retained setAgent.
// Compatible with ICCListing.sol (v0.0.3), CCMainPartial.sol (v0.0.06), CCUniPartial.sol (v0.0.6).

import "./utils/CCSettlementPartial.sol";

contract CCSettlementRouter is CCSettlementPartial {
    using SafeERC20 for IERC20;

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