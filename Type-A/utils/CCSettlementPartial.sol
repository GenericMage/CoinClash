// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.15
// Changes: 
// - v0.1.15: Moved uint2str, getTokenAndDecimals,  prepBuyOrderUpdate and prepSellOrderUpdate to unipartial to resolve declaration error. 
// - v0.1.14: Patched _prepBuyOrderUpdate/_prepSellOrderUpdate to use actual contract balance for amountIn after transactToken/transactNative. 
// - v0.1.13: Modified _prepBuyOrderUpdate/_prepSellOrderUpdate to check contract balance after transactToken, using received amount for swaps to handle tax-on-transfer. 
// - v0.1.12: Removed NonCriticalPriceOutOfBounds event, relying on _checkPricing reverts. Ensured transactToken in _prepBuyOrderUpdate/_prepSellOrderUpdate handles tokenB transfers. Streamlined balanceOf calls by caching results. Compatible with CCUniPartial.sol v0.1.15, sol v0.1.8.


import "./CCUniPartial.sol";
import "./CCMainPartial.sol";

contract CCSettlementPartial is CCUniPartial {
      struct OrderProcessContext {
        uint256 orderId;
        uint256 pendingAmount;
        uint256 filled;
        uint256 amountSent;
        address makerAddress;
        address recipientAddress;
        uint8 status;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 currentPrice;
        uint256 maxAmountIn;
        uint256 swapAmount;
        ICCListing.BuyOrderUpdate[] buyUpdates;
        ICCListing.SellOrderUpdate[] sellUpdates;
    }

    function _checkPricing(
        address listingAddress,
        uint256 orderIdentifier,
        bool isBuyOrder,
        uint256 pendingAmount
    ) internal view returns (bool) {
        // Validates order pricing
        ICCListing listingContract = ICCListing(listingAddress);
        uint256 maxPrice;
        uint256 minPrice;
        if (isBuyOrder) {
            (maxPrice, minPrice) = listingContract.getBuyOrderPricing(orderIdentifier);
        } else {
            (maxPrice, minPrice) = listingContract.getSellOrderPricing(orderIdentifier);
        }
        uint256 currentPrice = listingContract.prices(0);
        if (currentPrice == 0) {
            revert("Invalid current price");
        }
        if (currentPrice < minPrice || currentPrice > maxPrice) {
            revert("Price out of bounds");
        }
        return true;
    }

    function _computeAmountSent(
        address tokenAddress,
        address recipientAddress,
        uint256 amount
    ) internal view returns (uint256 preBalance) {
        // Computes pre-transfer balance
        preBalance = tokenAddress == address(0)
            ? recipientAddress.balance
            : IERC20(tokenAddress).balanceOf(recipientAddress);
    }

    function _validateOrderParams(
        address listingAddress,
        uint256 orderId,
        bool isBuyOrder,
        ICCListing listingContract
    ) internal view returns (OrderProcessContext memory context) {
        // Validates order details
        context.orderId = orderId;
        (context.pendingAmount, context.filled, context.amountSent) = isBuyOrder
            ? listingContract.getBuyOrderAmounts(orderId)
            : listingContract.getSellOrderAmounts(orderId);
        (context.makerAddress, context.recipientAddress, context.status) = isBuyOrder
            ? listingContract.getBuyOrderCore(orderId)
            : listingContract.getSellOrderCore(orderId);
        (context.maxPrice, context.minPrice) = isBuyOrder
            ? listingContract.getBuyOrderPricing(orderId)
            : listingContract.getSellOrderPricing(orderId);
        context.currentPrice = listingContract.prices(0);
        if (context.pendingAmount == 0 || context.status != 1) {
            revert(string(abi.encodePacked("Invalid order ", uint2str(orderId), ": no pending amount or status")));
        }
        if (context.currentPrice == 0) {
            revert(string(abi.encodePacked("Invalid current price for order ", uint2str(orderId))));
        }
        if (context.currentPrice < context.minPrice || context.currentPrice > context.maxPrice) {
            revert(string(abi.encodePacked("Price out of bounds for order ", uint2str(orderId))));
        }
    }

    function _computeSwapAmount(
        address listingAddress,
        bool isBuyOrder,
        OrderProcessContext memory context,
        SettlementContext memory settlementContext
    ) internal view returns (OrderProcessContext memory) {
        // Computes swap amount
        context.maxAmountIn = _computeMaxAmountIn(listingAddress, context.maxPrice, context.minPrice, context.pendingAmount, isBuyOrder, settlementContext);
        context.swapAmount = context.maxAmountIn >= context.pendingAmount ? context.pendingAmount : context.maxAmountIn;
        if (context.swapAmount == 0) {
            revert(string(abi.encodePacked("Zero swap amount for order ", uint2str(context.orderId))));
        }
        return context;
    }

    function _executeOrderSwap(
        address listingAddress,
        bool isBuyOrder,
        OrderProcessContext memory context,
        SettlementContext memory settlementContext
    ) internal returns (OrderProcessContext memory) {
        // Executes swap via Uniswap V2
        if (context.swapAmount == 0) {
            return context;
        }
        if (isBuyOrder) {
            context.buyUpdates = _executePartialBuySwap(listingAddress, context.orderId, context.swapAmount, context.pendingAmount, settlementContext);
        } else {
            context.sellUpdates = _executePartialSellSwap(listingAddress, context.orderId, context.swapAmount, context.pendingAmount, settlementContext);
        }
        return context;
    }

    function _extractPendingAmount(
        OrderProcessContext memory context,
        bool isBuyOrder
    ) internal pure returns (uint256 pending) {
        if (isBuyOrder && context.buyUpdates.length > 0) {
            return context.buyUpdates[0].pending;
        } else if (!isBuyOrder && context.sellUpdates.length > 0) {
            return context.sellUpdates[0].pending;
        }
        return 0;
    }

    function _updateFilledAndStatus(
        OrderProcessContext memory context,
        bool isBuyOrder,
        uint256 pendingAmount
    ) internal pure returns (
        ICCListing.BuyOrderUpdate[] memory buyUpdates,
        ICCListing.SellOrderUpdate[] memory sellUpdates
    ) {
        if (isBuyOrder && context.buyUpdates.length > 0) {
            buyUpdates = context.buyUpdates;
            buyUpdates[0].filled = context.filled + context.swapAmount;
            buyUpdates[1].status = context.status == 1 && context.swapAmount >= pendingAmount ? 3 : 2;
            sellUpdates = new ICCListing.SellOrderUpdate[](0);
        } else if (!isBuyOrder && context.sellUpdates.length > 0) {
            sellUpdates = context.sellUpdates;
            sellUpdates[0].filled = context.filled + context.swapAmount;
            sellUpdates[1].status = context.status == 1 && context.swapAmount >= pendingAmount ? 3 : 2;
            buyUpdates = new ICCListing.BuyOrderUpdate[](0);
        } else {
            buyUpdates = new ICCListing.BuyOrderUpdate[](0);
            sellUpdates = new ICCListing.SellOrderUpdate[](0);
        }
    }

    function _prepareUpdateData(
        OrderProcessContext memory context,
        bool isBuyOrder
    ) internal pure returns (
        ICCListing.BuyOrderUpdate[] memory buyUpdates,
        ICCListing.SellOrderUpdate[] memory sellUpdates
    ) {
        uint256 pendingAmount = _extractPendingAmount(context, isBuyOrder);
        return _updateFilledAndStatus(context, isBuyOrder, pendingAmount);
    }

    function _applyOrderUpdate(
        address listingAddress,
        ICCListing listingContract,
        OrderProcessContext memory context,
        bool isBuyOrder
    ) internal pure returns (
        ICCListing.BuyOrderUpdate[] memory buyUpdates,
        ICCListing.SellOrderUpdate[] memory sellUpdates
    ) {
        // Prepares update structs
        (buyUpdates, sellUpdates) = _prepareUpdateData(context, isBuyOrder);
        return (buyUpdates, sellUpdates);
    }

    function _processBuyOrder(
        address listingAddress,
        uint256 orderIdentifier,
        ICCListing listingContract,
        SettlementContext memory settlementContext
    ) internal returns (ICCListing.BuyOrderUpdate[] memory buyUpdates) {
        if (uniswapV2Router == address(0)) {
            revert(string(abi.encodePacked("Missing Uniswap V2 router for buy order ", uint2str(orderIdentifier))));
        }
        OrderProcessContext memory context = _validateOrderParams(listingAddress, orderIdentifier, true, listingContract);
        context = _computeSwapAmount(listingAddress, true, context, settlementContext);
        context = _executeOrderSwap(listingAddress, true, context, settlementContext);
        (buyUpdates, ) = _applyOrderUpdate(listingAddress, listingContract, context, true);
        return buyUpdates;
    }

    function _processSellOrder(
        address listingAddress,
        uint256 orderIdentifier,
        ICCListing listingContract,
        SettlementContext memory settlementContext
    ) internal returns (ICCListing.SellOrderUpdate[] memory sellUpdates) {
        if (uniswapV2Router == address(0)) {
            revert(string(abi.encodePacked("Missing Uniswap V2 router for sell order ", uint2str(orderIdentifier))));
        }
        OrderProcessContext memory context = _validateOrderParams(listingAddress, orderIdentifier, false, listingContract);
        context = _computeSwapAmount(listingAddress, false, context, settlementContext);
        context = _executeOrderSwap(listingAddress, false, context, settlementContext);
        (, sellUpdates) = _applyOrderUpdate(listingAddress, listingContract, context, false);
        return sellUpdates;
    }
}