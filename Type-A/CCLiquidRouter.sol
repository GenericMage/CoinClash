// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.12
// Changes:
// - v0.0.12: Added try-catch in settleBuyLiquid and settleSellLiquid to capture specific UpdateFailed reasons from listingContract.update. Ensured no fetching of settled orders by relying on _processOrderBatch to skip orders with zero pending amount. Compatible with CCLiquidPartial.sol v0.0.18, CCListingTemplate.sol v0.1.12, CCMainPartial.sol v0.0.14.
// - v0.0.11: Fixed TypeError by updating tuple destructuring in settleBuyLiquid and settleSellLiquid to match listingVolumeBalancesView return values (xBalance, yBalance, xVolume, yVolume). Removed duplicate PriceOutOfBounds event, as it is defined in CCLiquidPartial.sol.
// - v0.0.10: Updated settleBuyLiquid and settleSellLiquid to use prices(0) from listing template for price calculation instead of reserves. Retained impact price calculations using balanceOf for Uniswap V2 LP tokens. Added graceful degradation with events for no pending orders, out-of-bounds prices, or insufficient liquidity balance, preventing reverts on minor issues.
// - v0.0.9: Updated compatibility with CCLiquidPartial.sol v0.0.12 to reflect flipped price calculation (reserveB / reserveA) and improved settlement logic using current price when impact price is within bounds. No functional changes to settleBuyLiquid or settleSellLiquid, as logic is handled in CCLiquidPartial.sol.
// - v0.0.8: Moved _getSwapReserves and _computeSwapImpact to CCLiquidPartial.sol to fix DeclarationError in _processSingleOrder (CCLiquidPartial.sol:424). Removed SwapImpactContext struct and IUniswapV2Pair interface as they are now in CCLiquidPartial.sol.
// - v0.0.7: Refactored settleBuyLiquid and settleSellLiquid to address stack-too-deep errors by moving logic to CCLiquidPartial.sol helper functions (_collectOrderIdentifiers, _processOrderBatch, _processSingleOrder, _finalizeUpdates). Uses OrderBatchContext struct for data passing, ensuring no function handles >4 variables.
// - v0.0.6: Updated to use depositor in ICCLiquidity.update call in settleBuyLiquid and settleSellLiquid, aligning with ICCLiquidity.sol v0.0.4 and CCMainPartial.sol v0.0.11. Ensured consistency with ICCListing.sol v0.0.7.
// - v0.0.5: Removed duplicated ICCListing interface, relying on CCMainPartial.sol (v0.0.9) definitions to resolve interface duplication per linearization.
// - v0.0.4: Updated ICCListing interface to remove uint256 parameter from liquidityAddressView for compatibility with CCListingTemplate.sol v0.0.6. Replaced liquidityAddressView(0) with liquidityAddressView() in _getSwapReserves.
// - v0.0.3: Added price impact restrictions in settleBuyLiquid and settleSellLiquid, using Uniswap V2 reserve data to ensure hypothetical price changes stay within order bounds.
// - v0.0.2: Removed SafeERC20 usage, used IERC20 from CCMainPartial, removed redundant require success checks for transfers.
// - v0.0.1: Created CCLiquidRouter.sol, extracted settleBuyLiquid and settleSellLiquid from CCSettlementRouter.sol.
// Compatible with CCListingTemplate.sol (v0.1.12), ICCLiquidity.sol (v0.0.4), CCMainPartial.sol (v0.0.14), CCLiquidPartial.sol (v0.0.18).

import "./utils/CCLiquidPartial.sol";

contract CCLiquidRouter is CCLiquidPartial {
    // Emitted when no pending orders are found
    event NoPendingOrders(address indexed listingAddress, bool isBuyOrder);
    // Emitted when listing has insufficient balance
    event InsufficientBalance(address indexed listingAddress, uint256 required, uint256 available);
    // Emitted when update fails
    event UpdateFailed(address indexed listingAddress, string reason);

    function settleBuyLiquid(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Settles multiple buy order liquidations up to maxIterations, with price impact restrictions
        ICCListing listingContract = ICCListing(listingAddress);
        uint256[] memory pendingOrders = listingContract.pendingBuyOrdersView();
        if (pendingOrders.length == 0) {
            emit NoPendingOrders(listingAddress, true);
            return;
        }
        (uint256 xBalance, uint256 yBalance,,) = listingContract.listingVolumeBalancesView();
        if (yBalance == 0) {
            emit InsufficientBalance(listingAddress, 1, yBalance);
            return;
        }
        ICCListing.UpdateType[] memory updates = _processOrderBatch(listingAddress, maxIterations, true);
        if (updates.length > 0) {
            try listingContract.update(updates) {
            } catch Error(string memory reason) {
                emit UpdateFailed(listingAddress, reason);
            } catch {
                emit UpdateFailed(listingAddress, "Unknown update error");
            }
        }
    }

    function settleSellLiquid(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Settles multiple sell order liquidations up to maxIterations, with price impact restrictions
        ICCListing listingContract = ICCListing(listingAddress);
        uint256[] memory pendingOrders = listingContract.pendingSellOrdersView();
        if (pendingOrders.length == 0) {
            emit NoPendingOrders(listingAddress, false);
            return;
        }
        (uint256 xBalance, uint256 yBalance,,) = listingContract.listingVolumeBalancesView();
        if (xBalance == 0) {
            emit InsufficientBalance(listingAddress, 1, xBalance);
            return;
        }
        ICCListing.UpdateType[] memory updates = _processOrderBatch(listingAddress, maxIterations, false);
        if (updates.length > 0) {
            try listingContract.update(updates) {
            } catch Error(string memory reason) {
                emit UpdateFailed(listingAddress, reason);
            } catch {
                emit UpdateFailed(listingAddress, "Unknown update error");
            }
        }
    }
}