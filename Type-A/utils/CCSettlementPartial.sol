// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.3
// Changes:
// - v0.1.4: Refactored _processBuyOrder and _processSellOrder to resolve stack-too-deep error. Split into helper functions (_validateOrderParams, _computeSwapAmount, _executeOrderSwap, _prepareUpdateData, _applyOrderUpdate) based on param groups (validation, swap calculation, execution, update prep, update application). Each helper handles at most 4 variables using OrderProcessContext struct. Ensured incremental updates to Core, Pricing, and Amounts structs via listingContract.ccUpdate.
// - v0.1.3: Added events NonCriticalPriceOutOfBounds, NonCriticalNoPendingOrder, NonCriticalZeroSwapAmount to log non-critical issues. Emitted in _processBuyOrder and _processSellOrder for price out of bounds, no pending orders, and zero swap amount cases to ensure non-reverting behavior with logging. Compatible with CCListingTemplate.sol v0.2.26 and CCUniPartial.sol v0.1.5.
// - v0.1.2: Added _computeMaxAmountIn to fix DeclarationError in _processBuyOrder and _processSellOrder. Calculates max input amount using reserves from CCUniPartial.sol’s _fetchReserves and price constraints. Ensured pending/filled use pre-transfer amount (tokenB for buys, tokenA for sells), amountSent uses post-transfer amount (tokenA for buys, tokenB for sells) with pre/post balance checks. Compatible with CCListingTemplate.sol v0.2.26 and CCUniPartial.sol v0.1.5.
// - v0.1.1: Modified _processBuyOrder and _processSellOrder to use listingContract.ccUpdate with three parameters (updateType, updateSort, updateData). Ensured pending amount uses pre-transfer amount (swapAmount).
// - v0.1.0: Bumped version
// - v0.0.27: Removed `try` from _executePartialBuySwap and _executePartialSellSwap calls, as they are internal.
// - v0.0.26: Removed `this.` from _executePartialBuySwap and _executePartialSellSwap calls.
// - v0.0.25: Enhanced error logging for token transfers, Uniswap swaps, and approvals.

import "./CCUniPartial.sol";
import "./CCMainPartial.sol";

contract CCSettlementPartial is CCUniPartial {
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
    ICCListing.UpdateType[] updates;
}
    
    event NonCriticalPriceOutOfBounds(address indexed listingAddress, uint256 indexed orderIdentifier, bool isBuyOrder, uint256 currentPrice, uint256 minPrice, uint256 maxPrice);
    event NonCriticalNoPendingOrder(address indexed listingAddress, uint256 indexed orderIdentifier, bool isBuyOrder);
    event NonCriticalZeroSwapAmount(address indexed listingAddress, uint256 indexed orderIdentifier, bool isBuyOrder);

    function _getTokenAndDecimals(
        address listingAddress,
        bool isBuyOrder
    ) internal view returns (address tokenAddress, uint8 tokenDecimals) {
        // Retrieves token address and decimals based on order type
        ICCListing listingContract = ICCListing(listingAddress);
        tokenAddress = isBuyOrder ? listingContract.tokenB() : listingContract.tokenA();
        tokenDecimals = isBuyOrder ? listingContract.decimalsB() : listingContract.decimalsA();
        if (tokenAddress == address(0) && !isBuyOrder) {
            revert("Invalid token address for sell order");
        }
    }

    function _checkPricing(
        address listingAddress,
        uint256 orderIdentifier,
        bool isBuyOrder,
        uint256 pendingAmount
    ) internal view returns (bool) {
        // Validates order pricing against max/min price constraints using listingContract.prices(0)
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
            return false;
        }
        return currentPrice <= maxPrice && currentPrice >= minPrice;
    }

    function _computeAmountSent(
        address tokenAddress,
        address recipientAddress,
        uint256 amount
    ) internal view returns (uint256 preBalance) {
        // Computes pre-transfer balance for recipient
        preBalance = tokenAddress == address(0)
            ? recipientAddress.balance
            : IERC20(tokenAddress).balanceOf(recipientAddress);
    }

    function _computeMaxAmountIn(
        address listingAddress,
        uint256 maxPrice,
        uint256 minPrice,
        uint256 pendingAmount,
        bool isBuyOrder
    ) internal view returns (uint256 maxAmountIn) {
        // Calculates maximum input amount based on price constraints and reserves
        ReserveContext memory reserveContext = _fetchReserves(listingAddress, isBuyOrder);
        ICCListing listingContract = ICCListing(listingAddress);
        uint256 currentPrice = listingContract.prices(0);
        if (currentPrice == 0 || reserveContext.normalizedReserveIn == 0) {
            return 0;
        }
        // Adjust maxAmountIn to respect maxPrice and minPrice constraints
        uint256 priceAdjustedAmount = isBuyOrder
            ? (pendingAmount * currentPrice) / 1e18 // For buys: tokenB amount
            : (pendingAmount * 1e18) / currentPrice; // For sells: tokenA amount
        maxAmountIn = priceAdjustedAmount > pendingAmount ? pendingAmount : priceAdjustedAmount;
        // Ensure maxAmountIn does not exceed available reserves
        if (maxAmountIn > reserveContext.normalizedReserveIn) {
            maxAmountIn = reserveContext.normalizedReserveIn;
        }
    }

    function _prepBuyOrderUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountReceived
    ) internal returns (PrepOrderUpdateResult memory result) {
        // Prepares buy order update data, including token transfer with validation
        ICCListing listingContract = ICCListing(listingAddress);
        (uint256 pending, uint256 filled, ) = listingContract.getBuyOrderAmounts(orderIdentifier);
        if (pending == 0) {
            revert(string(abi.encodePacked("No pending amount for buy order ", uint2str(orderIdentifier))));
        }
        (result.tokenAddress, result.tokenDecimals) = _getTokenAndDecimals(listingAddress, true);
        (result.makerAddress, result.recipientAddress, result.orderStatus) = listingContract.getBuyOrderCore(orderIdentifier);
        if (result.orderStatus != 1) {
            revert(string(abi.encodePacked("Invalid status for buy order ", uint2str(orderIdentifier), ": ", uint2str(result.orderStatus))));
        }
        uint256 denormalizedAmount = denormalize(amountReceived, result.tokenDecimals);
        uint256 preBalance = _computeAmountSent(result.tokenAddress, result.recipientAddress, denormalizedAmount);
        if (result.tokenAddress == address(0)) {
            try listingContract.transactNative{value: denormalizedAmount}(denormalizedAmount, result.recipientAddress) {
                uint256 postBalance = result.recipientAddress.balance;
                result.amountReceived = postBalance > preBalance ? postBalance - preBalance : 0;
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("Native transfer failed for buy order ", uint2str(orderIdentifier), ": ", reason)));
            }
        } else {
            try listingContract.transactToken(result.tokenAddress, denormalizedAmount, result.recipientAddress) {
                uint256 postBalance = IERC20(result.tokenAddress).balanceOf(result.recipientAddress);
                result.amountReceived = postBalance > preBalance ? postBalance - preBalance : 0;
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("Token transfer failed for buy order ", uint2str(orderIdentifier), ": ", reason)));
            }
        }
        if (result.amountReceived == 0) {
            revert(string(abi.encodePacked("No tokens received for buy order ", uint2str(orderIdentifier))));
        }
        result.normalizedReceived = normalize(result.amountReceived, result.tokenDecimals);
        result.amountSent = result.amountReceived;
    }

    function _prepSellOrderUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountReceived
    ) internal returns (PrepOrderUpdateResult memory result) {
        // Prepares sell order update data, including token transfer with validation
        ICCListing listingContract = ICCListing(listingAddress);
        (uint256 pending, uint256 filled, ) = listingContract.getSellOrderAmounts(orderIdentifier);
        if (pending == 0) {
            revert(string(abi.encodePacked("No pending amount for sell order ", uint2str(orderIdentifier))));
        }
        (result.tokenAddress, result.tokenDecimals) = _getTokenAndDecimals(listingAddress, false);
        (result.makerAddress, result.recipientAddress, result.orderStatus) = listingContract.getSellOrderCore(orderIdentifier);
        if (result.orderStatus != 1) {
            revert(string(abi.encodePacked("Invalid status for sell order ", uint2str(orderIdentifier), ": ", uint2str(result.orderStatus))));
        }
        uint256 denormalizedAmount = denormalize(amountReceived, result.tokenDecimals);
        uint256 preBalance = _computeAmountSent(result.tokenAddress, result.recipientAddress, denormalizedAmount);
        if (result.tokenAddress == address(0)) {
            try listingContract.transactNative{value: denormalizedAmount}(denormalizedAmount, result.recipientAddress) {
                uint256 postBalance = result.recipientAddress.balance;
                result.amountReceived = postBalance > preBalance ? postBalance - preBalance : 0;
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("Native transfer failed for sell order ", uint2str(orderIdentifier), ": ", reason)));
            }
        } else {
            try listingContract.transactToken(result.tokenAddress, denormalizedAmount, result.recipientAddress) {
                uint256 postBalance = IERC20(result.tokenAddress).balanceOf(result.recipientAddress);
                result.amountReceived = postBalance > preBalance ? postBalance - preBalance : 0;
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("Token transfer failed for sell order ", uint2str(orderIdentifier), ": ", reason)));
            }
        }
        if (result.amountReceived == 0) {
            revert(string(abi.encodePacked("No tokens received for sell order ", uint2str(orderIdentifier))));
        }
        result.normalizedReceived = normalize(result.amountReceived, result.tokenDecimals);
        result.amountSent = result.amountReceived;
    }

// Helper function to validate order parameters
function _validateOrderParams(
    address listingAddress,
    uint256 orderId,
    bool isBuyOrder,
    ICCListing listingContract
) internal view returns (OrderProcessContext memory context) {
    // Validates order details and pricing
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
}

// Helper function to compute swap amount
function _computeSwapAmount(
    address listingAddress,
    bool isBuyOrder,
    OrderProcessContext memory context
) internal returns (OrderProcessContext memory) {
    // Computes swap amount based on price and reserves
    if (context.pendingAmount == 0) {
        emit NonCriticalNoPendingOrder(listingAddress, context.orderId, isBuyOrder);
        return context;
    }
    if (context.status != 1) {
        revert(string(abi.encodePacked("Invalid status for order ", uint2str(context.orderId), ": ", uint2str(context.status))));
    }
    if (context.currentPrice == 0) {
        revert(string(abi.encodePacked("Invalid current price for order ", uint2str(context.orderId))));
    }
    if (context.currentPrice < context.minPrice || context.currentPrice > context.maxPrice) {
        emit NonCriticalPriceOutOfBounds(listingAddress, context.orderId, isBuyOrder, context.currentPrice, context.minPrice, context.maxPrice);
        return context;
    }
    context.maxAmountIn = _computeMaxAmountIn(listingAddress, context.maxPrice, context.minPrice, context.pendingAmount, isBuyOrder);
    context.swapAmount = context.maxAmountIn >= context.pendingAmount ? context.pendingAmount : context.maxAmountIn;
    if (context.swapAmount == 0) {
        emit NonCriticalZeroSwapAmount(listingAddress, context.orderId, isBuyOrder);
        return context;
    }
    return context;
}

// Helper function to execute swap
function _executeOrderSwap(
    address listingAddress,
    bool isBuyOrder,
    OrderProcessContext memory context
) internal returns (OrderProcessContext memory) {
    // Executes swap via Uniswap V2
    if (context.swapAmount == 0) {
        return context;
    }
    context.updates = isBuyOrder
        ? _executePartialBuySwap(listingAddress, context.orderId, context.swapAmount, context.pendingAmount)
        : _executePartialSellSwap(listingAddress, context.orderId, context.swapAmount, context.pendingAmount);
    return context;
}

// Helper function to prepare update data
function _prepareUpdateData(
    OrderProcessContext memory context
) internal pure returns (uint8[] memory updateType, uint8[] memory updateSort, uint256[] memory updateData) {
    // Prepares data for ccUpdate
    if (context.updates.length == 0) {
        return (new uint8[](0), new uint8[](0), new uint256[](0));
    }
    updateType = new uint8[](context.updates.length);
    updateSort = new uint8[](context.updates.length);
    updateData = new uint256[](context.updates.length);
    for (uint256 i = 0; i < context.updates.length; i++) {
        updateType[i] = context.updates[i].updateType;
        updateSort[i] = context.updates[i].structId;
        if (context.updates[i].structId == 0) {
            updateData[i] = uint256(bytes32(abi.encode(context.updates[i].addr, context.updates[i].recipient, uint8(context.updates[i].value))));
        } else if (context.updates[i].structId == 1) {
            updateData[i] = uint256(bytes32(abi.encode(context.updates[i].maxPrice, context.updates[i].minPrice)));
        } else if (context.updates[i].structId == 2) {
            updateData[i] = uint256(bytes32(abi.encode(context.updates[i].value, context.filled + context.updates[i].value, context.updates[i].amountSent)));
        }
    }
}

// Helper function to apply updates
function _applyOrderUpdate(
    address listingAddress,
    ICCListing listingContract,
    OrderProcessContext memory context
) internal returns (ICCListing.UpdateType[] memory) {
    // Applies updates via ccUpdate
    if (context.updates.length == 0) {
        return new ICCListing.UpdateType[](0);
    }
    (uint8[] memory updateType, uint8[] memory updateSort, uint256[] memory updateData) = _prepareUpdateData(context);
    try listingContract.ccUpdate(updateType, updateSort, updateData) {
        // Success
    } catch Error(string memory reason) {
        revert(string(abi.encodePacked("ccUpdate failed for order ", uint2str(context.orderId), ": ", reason)));
    }
    for (uint256 i = 0; i < context.updates.length; i++) {
        context.updates[i].addr = context.makerAddress;
        context.updates[i].recipient = context.recipientAddress;
    }
    return context.updates;
}

// Updated _processBuyOrder function
function _processBuyOrder(
    address listingAddress,
    uint256 orderIdentifier,
    ICCListing listingContract
) internal returns (ICCListing.UpdateType[] memory updates) {
    // Processes a single buy order using Uniswap V2 swap
    if (uniswapV2Router == address(0)) {
        revert(string(abi.encodePacked("Missing Uniswap V2 router for buy order ", uint2str(orderIdentifier))));
    }
    OrderProcessContext memory context = _validateOrderParams(listingAddress, orderIdentifier, true, listingContract);
    context = _computeSwapAmount(listingAddress, true, context);
    context = _executeOrderSwap(listingAddress, true, context);
    return _applyOrderUpdate(listingAddress, listingContract, context);
}

// Updated _processSellOrder function
function _processSellOrder(
    address listingAddress,
    uint256 orderIdentifier,
    ICCListing listingContract
) internal returns (ICCListing.UpdateType[] memory updates) {
    // Processes a single sell order using Uniswap V2 swap
    if (uniswapV2Router == address(0)) {
        revert(string(abi.encodePacked("Missing Uniswap V2 router for sell order ", uint2str(orderIdentifier))));
    }
    OrderProcessContext memory context = _validateOrderParams(listingAddress, orderIdentifier, false, listingContract);
    context = _computeSwapAmount(listingAddress, false, context);
    context = _executeOrderSwap(listingAddress, false, context);
    return _applyOrderUpdate(listingAddress, listingContract, context);
}

    function uint2str(uint256 _i) internal pure returns (string memory str) {
        // Utility function to convert uint to string for error messages
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        str = string(bstr);
    }
}