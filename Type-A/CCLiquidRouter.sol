// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.16
// Changes:
// - v0.0.16: Updated _processOrderBatch to pass step parameter to _collectOrderIdentifiers, ensuring gas-efficient settlement. Aligned with CCLiquidPartial.sol v0.0.22 fixes for liquidity updates, output token validation, and amountSent calculation. Compatible with CCListingTemplate.sol v0.1.12, CCMainPartial.sol v0.0.14, CCLiquidityTemplate.sol v0.1.1, CCLiquidPartial.sol v0.0.22.
// - v0.0.15: Added step parameter to settleBuyLiquid and settleSellLiquid for gas-efficient settlement.
// - v0.0.14: Updated compatibility with CCLiquidPartial.sol v0.0.20.
// - v0.0.13: Updated compatibility with CCLiquidPartial.sol v0.0.19.
// - v0.0.12: Added try-catch in settleBuyLiquid and settleSellLiquid for UpdateFailed reasons.
// - v0.0.11: Fixed tuple destructuring in settleBuyLiquid and settleSellLiquid.
// - v0.0.10: Updated to use prices(0) for price calculation.
// - v0.0.9: Updated compatibility with CCLiquidPartial.sol v0.0.12.
// - v0.0.8: Moved _getSwapReserves and _computeSwapImpact to CCLiquidPartial.sol.
// - v0.0.7: Refactored settleBuyLiquid and settleSellLiquid to use helper functions.
// - v0.0.6: Updated to use depositor in ICCLiquidity.update call.
// - v0.0.5: Removed duplicated ICCListing interface.
// - v0.0.4: Updated ICCListing interface for liquidityAddressView compatibility.
// - v0.0.3: Added price impact restrictions in settleBuyLiquid and settleSellLiquid.
// - v0.0.2: Removed SafeERC20 usage, used IERC20 from CCMainPartial.
// - v0.0.1: Created CCLiquidRouter.sol from CCSettlementRouter.sol.

import "./utils/CCLiquidPartial.sol";

contract CCLiquidRouter is CCLiquidPartial {
    event NoPendingOrders(address indexed listingAddress, bool isBuyOrder);
    event InsufficientBalance(address indexed listingAddress, uint256 required, uint256 available);
    event UpdateFailed(address indexed listingAddress, string reason);

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
            try listingContract.update(updates) {
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
            try listingContract.update(updates) {
            } catch Error(string memory reason) {
                emit UpdateFailed(listingAddress, reason);
            } catch {
                emit UpdateFailed(listingAddress, "Unknown update error");
            }
        }
    }

    function _processOrderBatch(
        address listingAddress,
        uint256 maxIterations,
        bool isBuyOrder,
        uint256 step
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Processes a batch of orders, collecting and executing up to maxIterations starting from step
        OrderBatchContext memory batchContext = OrderBatchContext({
            listingAddress: listingAddress,
            maxIterations: maxIterations,
            isBuyOrder: isBuyOrder
        });
        (uint256[] memory orderIdentifiers, uint256 iterationCount) = _collectOrderIdentifiers(
            batchContext.listingAddress,
            batchContext.maxIterations,
            batchContext.isBuyOrder,
            step
        );
        ICCListing.UpdateType[] memory tempUpdates = new ICCListing.UpdateType[](iterationCount * 3);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            (uint256 pendingAmount, , ) = batchContext.isBuyOrder
                ? ICCListing(listingAddress).getBuyOrderAmounts(orderIdentifiers[i])
                : ICCListing(listingAddress).getSellOrderAmounts(orderIdentifiers[i]);
            if (pendingAmount == 0) continue;
            ICCListing.UpdateType[] memory updates = _processSingleOrder(
                batchContext.listingAddress,
                orderIdentifiers[i],
                batchContext.isBuyOrder,
                pendingAmount
            );
            for (uint256 j = 0; j < updates.length; j++) {
                tempUpdates[updateIndex++] = updates[j];
            }
        }
        return _finalizeUpdates(tempUpdates, updateIndex);
    }
}