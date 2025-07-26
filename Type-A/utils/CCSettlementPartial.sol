// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.17
// Changes:
// - v0.0.17: Removed liquid settlement functions (_prepBuyLiquidUpdates, _prepSellLiquidUpdates, executeSingleBuyLiquid, executeSingleSellLiquid, _prepareLiquidityTransaction, _checkAndTransferPrincipal, _updateLiquidity) and ICCLiquidity interface, retained Uniswap V2 settlement logic.
// - v0.0.16: Removed duplicated _prepareSellSwapData (inherited from CCUniPartial.sol), added routers function to ICCLiquidity.
// - v0.0.15: Added ICCLiquidity interface, removed duplicated swap and update functions.
// - v0.0.14: Replaced ISSListingTemplate with ICCListing, ISSLiquidityTemplate with ICCLiquidity, split transact/deposit.
// Compatible with ICCListing.sol (v0.0.3), CCUniPartial.sol (v0.0.6), CCSettlementRouter.sol (v0.0.4).

import "./CCUniPartial.sol";

contract CCSettlementPartial is CCUniPartial {
    using SafeERC20 for IERC20;

    struct PrepOrderUpdateResult {
        address tokenAddress;
        uint8 tokenDecimals;
        address makerAddress;
        address recipientAddress;
        uint8 orderStatus;
        uint256 amountReceived;
        uint256 normalizedReceived;
        uint256 amountSent;
    }

    function _getTokenAndDecimals(
        address listingAddress,
        bool isBuyOrder
    ) internal view returns (address tokenAddress, uint8 tokenDecimals) {
        // Retrieves token address and decimals based on order type
        ICCListing listingContract = ICCListing(listingAddress);
        tokenAddress = isBuyOrder ? listingContract.tokenB() : listingContract.tokenA();
        tokenDecimals = isBuyOrder ? listingContract.decimalsB() : listingContract.decimalsA();
    }

    function _checkPricing(
        address listingAddress,
        uint256 orderIdentifier,
        bool isBuyOrder,
        uint256 pendingAmount
    ) internal view returns (bool) {
        // Validates order pricing against max/min price constraints
        ICCListing listingContract = ICCListing(listingAddress);
        uint256 maxPrice;
        uint256 minPrice;
        if (isBuyOrder) {
            (maxPrice, minPrice) = listingContract.getBuyOrderPricing(orderIdentifier);
        } else {
            (maxPrice, minPrice) = listingContract.getSellOrderPricing(orderIdentifier);
        }
        (uint256 impactPrice,) = _computeSwapImpact(listingAddress, pendingAmount, isBuyOrder);
        return impactPrice <= maxPrice && impactPrice >= minPrice;
    }

    function _computeAmountSent(
        address tokenAddress,
        address recipientAddress,
        uint256 amount
    ) internal view returns (uint256) {
        // Computes actual tokens sent by checking recipient balance changes
        uint256 preBalance = tokenAddress == address(0)
            ? recipientAddress.balance
            : IERC20(tokenAddress).balanceOf(recipientAddress);
        uint256 postBalance = preBalance; // Placeholder, actual logic depends on transfer
        return postBalance > preBalance ? postBalance - preBalance : 0;
    }

    function _prepBuyOrderUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountOut
    ) internal returns (PrepOrderUpdateResult memory result) {
        // Prepares buy order update data, including token transfer
        ICCListing listingContract = ICCListing(listingAddress);
        (result.tokenAddress, result.tokenDecimals) = _getTokenAndDecimals(listingAddress, true);
        (result.makerAddress, result.recipientAddress, result.orderStatus) = listingContract.getBuyOrderCore(orderIdentifier);
        uint256 denormalizedAmount = denormalize(amountOut, result.tokenDecimals);
        if (result.tokenAddress == address(0)) {
            try listingContract.transactNative{value: denormalizedAmount}(address(this), denormalizedAmount, result.recipientAddress) {} catch {
                result.amountReceived = 0;
                result.normalizedReceived = 0;
            }
        } else {
            try listingContract.transactToken(address(this), result.tokenAddress, denormalizedAmount, result.recipientAddress) {} catch {
                result.amountReceived = 0;
                result.normalizedReceived = 0;
            }
        }
        if (result.amountReceived > 0) {
            result.normalizedReceived = normalize(result.amountReceived, result.tokenDecimals);
        }
        result.amountSent = _computeAmountSent(result.tokenAddress, result.recipientAddress, denormalizedAmount);
    }

    function _prepSellOrderUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountOut
    ) internal returns (PrepOrderUpdateResult memory result) {
        // Prepares sell order update data, including token transfer
        ICCListing listingContract = ICCListing(listingAddress);
        (result.tokenAddress, result.tokenDecimals) = _getTokenAndDecimals(listingAddress, false);
        (result.recipientAddress, result.makerAddress, result.orderStatus) = listingContract.getSellOrderCore(orderIdentifier);
        uint256 denormalizedAmount = denormalize(amountOut, result.tokenDecimals);
        if (result.tokenAddress == address(0)) {
            try listingContract.transactNative{value: denormalizedAmount}(address(this), denormalizedAmount, result.recipientAddress) {} catch {
                result.amountReceived = 0;
                result.normalizedReceived = 0;
            }
        } else {
            try listingContract.transactToken(address(this), result.tokenAddress, denormalizedAmount, result.recipientAddress) {} catch {
                result.amountReceived = 0;
                result.normalizedReceived = 0;
            }
        }
        if (result.amountReceived > 0) {
            result.normalizedReceived = normalize(result.amountReceived, result.tokenDecimals);
        }
        result.amountSent = _computeAmountSent(result.tokenAddress, result.recipientAddress, denormalizedAmount);
    }

    function _processBuyOrder(
        address listingAddress,
        uint256 orderIdentifier,
        ICCListing listingContract
    ) internal returns (ICCListing.UpdateType[] memory updates) {
        // Processes a single buy order using Uniswap V2 swap
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.getBuyOrderAmounts(orderIdentifier);
        if (pendingAmount == 0) {
            return new ICCListing.UpdateType[](0);
        }
        (uint256 maxPrice, uint256 minPrice) = listingContract.getBuyOrderPricing(orderIdentifier);
        uint256 currentPrice = _computeCurrentPrice(listingAddress);
        if (currentPrice < minPrice || currentPrice > maxPrice) {
            return new ICCListing.UpdateType[](0);
        }
        uint256 maxAmountIn = _computeMaxAmountIn(listingAddress, maxPrice, minPrice, pendingAmount, true);
        uint256 swapAmount = maxAmountIn >= pendingAmount ? pendingAmount : maxAmountIn;
        if (swapAmount == 0) {
            return new ICCListing.UpdateType[](0);
        }
        updates = _executePartialBuySwap(listingAddress, orderIdentifier, swapAmount, pendingAmount);
    }

    function _processSellOrder(
        address listingAddress,
        uint256 orderIdentifier,
        ICCListing listingContract
    ) internal returns (ICCListing.UpdateType[] memory updates) {
        // Processes a single sell order using Uniswap V2 swap
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.getSellOrderAmounts(orderIdentifier);
        if (pendingAmount == 0) {
            return new ICCListing.UpdateType[](0);
        }
        (uint256 maxPrice, uint256 minPrice) = listingContract.getSellOrderPricing(orderIdentifier);
        uint256 currentPrice = _computeCurrentPrice(listingAddress);
        if (currentPrice < minPrice || currentPrice > maxPrice) {
            return new ICCListing.UpdateType[](0);
        }
        uint256 maxAmountIn = _computeMaxAmountIn(listingAddress, maxPrice, minPrice, pendingAmount, false);
        uint256 swapAmount = maxAmountIn >= pendingAmount ? pendingAmount : maxAmountIn;
        if (swapAmount == 0) {
            return new ICCListing.UpdateType[](0);
        }
        updates = _executePartialSellSwap(listingAddress, orderIdentifier, swapAmount, pendingAmount);
    }
}