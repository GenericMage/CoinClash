// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.22 (01/10/2025)
// Changes:
// - v0.1.22 (01/10): Simplified OrderProcessContext struct by removing maxPrice, minPrice, currentPrice, maxAmountIn. Merged _updateFilledAndStatus and _prepareUpdateData into a single _prepareUpdateData function to reduce code duplication. Inlined _extractPendingAmount logic into _prepareUpdateData to reduce function calls. Reduced _validateOrderParams by removing redundant checks already handled in _checkPricing.
// - v0.1.21 (01/10): Removed unused prepResult, listingAddress, amount, and pendingAmount in various functions. Updated _processBuyOrder and _processSellOrder to use fewer arguments in _applyOrderUpdate and _computeAmountSent.
// - v0.1.20 (01/10): Modified _processSellOrder to pass amountInReceived, added detailed OrderSkipped events.
// - v0.1.19 (29/09): Fixed amountSent calculation in _applyOrderUpdate, added preBalance handling.
// - v0.1.18: Renamed OrderFailed with OrderSkipped (29/9).

import "./CCUniPartial.sol";

contract CCSettlementPartial is CCUniPartial {
    struct OrderProcessContext {
        uint256 orderId;
        uint256 pendingAmount;
        uint256 filled;
        uint256 amountSent;
        address makerAddress;
        address recipientAddress;
        uint8 status;
        uint256 swapAmount;
        ICCListing.BuyOrderUpdate[] buyUpdates;
        ICCListing.SellOrderUpdate[] sellUpdates;
    }

    function _checkPricing(address listingAddress, uint256 orderIdentifier, bool isBuyOrder) internal returns (bool) {
        ICCListing listingContract = ICCListing(listingAddress);
        (uint256 maxPrice, uint256 minPrice) = isBuyOrder ? listingContract.getBuyOrderPricing(orderIdentifier) : listingContract.getSellOrderPricing(orderIdentifier);
        uint256 currentPrice = listingContract.prices(0);
        if (currentPrice == 0) {
            emit OrderSkipped(orderIdentifier, "Invalid current price");
            return false;
        }
        if (currentPrice < minPrice || currentPrice > maxPrice) {
            emit OrderSkipped(orderIdentifier, "Price out of bounds");
            return false;
        }
        return true;
    }

    function _computeAmountSent(address tokenAddress, address recipientAddress) internal view returns (uint256 preBalance) {
        preBalance = tokenAddress == address(0) ? recipientAddress.balance : IERC20(tokenAddress).balanceOf(recipientAddress);
    }

    function _validateOrderParams(address listingAddress, uint256 orderId, bool isBuyOrder, ICCListing listingContract) internal returns (OrderProcessContext memory context) {
        context.orderId = orderId;
        (context.pendingAmount, context.filled, context.amountSent) = isBuyOrder ? listingContract.getBuyOrderAmounts(orderId) : listingContract.getSellOrderAmounts(orderId);
        (context.makerAddress, context.recipientAddress, context.status) = isBuyOrder ? listingContract.getBuyOrderCore(orderId) : listingContract.getSellOrderCore(orderId);
        if (context.pendingAmount == 0) {
            emit OrderSkipped(orderId, "No pending amount");
            return context;
        }
        if (context.status != 1) {
            emit OrderSkipped(orderId, string(abi.encodePacked("Invalid order status: ", uint2str(context.status))));
            return context;
        }
        if (!_checkPricing(listingAddress, orderId, isBuyOrder)) return context;
    }

    function _computeSwapAmount(address listingAddress, bool isBuyOrder, OrderProcessContext memory context, SettlementContext memory settlementContext) internal returns (OrderProcessContext memory) {
        context.swapAmount = _computeMaxAmountIn(listingAddress, 0, 0, context.pendingAmount, isBuyOrder, settlementContext);
        if (context.swapAmount == 0) emit OrderSkipped(context.orderId, "Zero swap amount");
        return context;
    }

    function _executeOrderSwap(address listingAddress, bool isBuyOrder, OrderProcessContext memory context, SettlementContext memory settlementContext) internal returns (OrderProcessContext memory) {
        if (context.swapAmount == 0) {
            emit OrderSkipped(context.orderId, "Zero swap amount");
            return context;
        }
        if (isBuyOrder) {
            _prepBuyOrderUpdate(listingAddress, context.orderId, context.swapAmount, settlementContext);
            context.buyUpdates = _executePartialBuySwap(listingAddress, context.orderId, context.swapAmount, context.pendingAmount, settlementContext);
        } else {
            _prepSellOrderUpdate(listingAddress, context.orderId, context.swapAmount, settlementContext);
            context.sellUpdates = _executePartialSellSwap(listingAddress, context.orderId, context.swapAmount, context.pendingAmount, settlementContext);
        }
        return context;
    }

    // Changelog: v0.1.22 (01/10): Merged _updateFilledAndStatus and _extractPendingAmount into this function
    function _prepareUpdateData(OrderProcessContext memory context, bool isBuyOrder, uint256 pendingAmount, uint256 preBalance, SettlementContext memory settlementContext) internal view returns (ICCListing.BuyOrderUpdate[] memory buyUpdates, ICCListing.SellOrderUpdate[] memory sellUpdates) {
        uint256 postBalance = _computeAmountSent(isBuyOrder ? settlementContext.tokenB : settlementContext.tokenA, context.recipientAddress);
        uint256 amountSent = postBalance > preBalance ? postBalance - preBalance : 0;
        if (isBuyOrder && context.buyUpdates.length > 0) {
            buyUpdates = context.buyUpdates;
            buyUpdates[0].filled = context.filled + context.swapAmount;
            buyUpdates[0].amountSent = amountSent;
            buyUpdates[1].status = context.swapAmount >= pendingAmount ? 3 : 2;
            sellUpdates = new ICCListing.SellOrderUpdate[](0);
        } else if (!isBuyOrder && context.sellUpdates.length > 0) {
            sellUpdates = context.sellUpdates;
            sellUpdates[0].filled = context.filled + context.swapAmount;
            sellUpdates[0].amountSent = amountSent;
            sellUpdates[1].status = context.swapAmount >= pendingAmount ? 3 : 2;
            buyUpdates = new ICCListing.BuyOrderUpdate[](0);
        } else {
            buyUpdates = new ICCListing.BuyOrderUpdate[](0);
            sellUpdates = new ICCListing.SellOrderUpdate[](0);
        }
    }

    function _applyOrderUpdate(OrderProcessContext memory context, bool isBuyOrder, SettlementContext memory settlementContext, uint256 preBalance) internal view returns (ICCListing.BuyOrderUpdate[] memory buyUpdates, ICCListing.SellOrderUpdate[] memory sellUpdates) {
        return _prepareUpdateData(context, isBuyOrder, context.pendingAmount, preBalance, settlementContext);
    }

    function _processBuyOrder(address listingAddress, uint256 orderIdentifier, ICCListing listingContract, SettlementContext memory settlementContext) internal returns (ICCListing.BuyOrderUpdate[] memory buyUpdates) {
        if (uniswapV2Router == address(0)) {
            emit OrderSkipped(orderIdentifier, "Uniswap V2 router not set");
            return new ICCListing.BuyOrderUpdate[](0);
        }
        OrderProcessContext memory context = _validateOrderParams(listingAddress, orderIdentifier, true, listingContract);
        if (context.status != 1 || context.pendingAmount == 0) return new ICCListing.BuyOrderUpdate[](0);
        context = _computeSwapAmount(listingAddress, true, context, settlementContext);
        if (context.swapAmount == 0) return new ICCListing.BuyOrderUpdate[](0);
        uint256 preBalance = _computeAmountSent(settlementContext.tokenB, context.recipientAddress);
        context = _executeOrderSwap(listingAddress, true, context, settlementContext);
        (buyUpdates,) = _applyOrderUpdate(context, true, settlementContext, preBalance);
        return buyUpdates;
    }

    function _processSellOrder(address listingAddress, uint256 orderIdentifier, ICCListing listingContract, SettlementContext memory settlementContext) internal returns (ICCListing.SellOrderUpdate[] memory sellUpdates) {
        if (uniswapV2Router == address(0)) {
            emit OrderSkipped(orderIdentifier, "Uniswap V2 router not set");
            return new ICCListing.SellOrderUpdate[](0);
        }
        OrderProcessContext memory context = _validateOrderParams(listingAddress, orderIdentifier, false, listingContract);
        if (context.status != 1 || context.pendingAmount == 0) return new ICCListing.SellOrderUpdate[](0);
        context = _computeSwapAmount(listingAddress, false, context, settlementContext);
        if (context.swapAmount == 0) return new ICCListing.SellOrderUpdate[](0);
        _prepSellOrderUpdate(listingAddress, orderIdentifier, context.swapAmount, settlementContext);
        uint256 preBalance = _computeAmountSent(settlementContext.tokenA, context.recipientAddress);
        context = _executeOrderSwap(listingAddress, false, context, settlementContext);
        (,sellUpdates) = _applyOrderUpdate(context, false, settlementContext, preBalance);
        return sellUpdates;
    }
}