// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.15
// Changes:
// - v0.0.15: Updated _computeCurrentPrice to use listingContract.prices(0) instead of reserve-based calculation. Modified _computeSwapImpact to use balanceOf for Uniswap V2 LP tokens for reserve data. Added PriceOutOfBounds event emission in _processSingleOrder for graceful degradation when price is out of bounds.
// - v0.0.14: Added missing _prepBuyLiquidUpdates and _prepSellLiquidUpdates functions to fix DeclarationError in executeSingleBuyLiquid and executeSingleSellLiquid (lines 326, 345).
// - v0.0.13: Fixed TypeError in _processSingleOrder by converting ICCListing.UpdateType[] to ICCLiquidity.UpdateType[] for liquidityContract.update call. Retained flipped price calculation (reserveB / reserveA) and settlement logic from v0.0.12.
// - v0.0.12: Updated _computeSwapImpact to align with flipped price calculation (reserveB / reserveA) from CCListingTemplate.sol v0.1.8. Adjusted _processSingleOrder to settle at current price if impact price is within max/min bounds, using _computeCurrentPrice from CCUniPartial.sol. Ensured pre/post balance checks in _prepBuyOrderUpdate and _prepSellOrderUpdate align with CCSettlementPartial.sol v0.0.21.
// Compatible with CCListingTemplate.sol (v0.1.8), CCMainPartial.sol (v0.0.14), CCLiquidRouter.sol (v0.0.10), CCLiquidityTemplate.sol (v0.1.1).

import "./CCMainPartial.sol";

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
}

contract CCLiquidPartial is CCMainPartial {
    struct OrderContext {
        ICCListing listingContract;
        address tokenIn;
        address tokenOut;
        address liquidityAddr;
    }

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

    struct BuyOrderUpdateContext {
        address makerAddress;
        address recipient;
        uint8 status;
        uint256 amountReceived;
        uint256 normalizedReceived;
        uint256 amountSent;
    }

    struct SellOrderUpdateContext {
        address makerAddress;
        address recipient;
        uint8 status;
        uint256 amountReceived;
        uint256 normalizedReceived;
        uint256 amountSent;
    }

    struct OrderBatchContext {
        address listingAddress;
        uint256 maxIterations;
        bool isBuyOrder;
    }

    struct SwapImpactContext {
        uint256 reserveIn;
        uint256 reserveOut;
        uint8 decimalsIn;
        uint8 decimalsOut;
        uint256 normalizedReserveIn;
        uint256 normalizedReserveOut;
        uint256 amountInAfterFee;
        uint256 price;
        uint256 amountOut;
    }

    // Emitted when price is out of bounds
    event PriceOutOfBounds(address indexed listingAddress, uint256 orderId, uint256 impactPrice, uint256 maxPrice, uint256 minPrice);

    function _getSwapReserves(address listingAddress, bool isBuyOrder) private view returns (SwapImpactContext memory context) {
        // Retrieves reserves and decimals for swap impact calculation using balanceOf
        ICCListing listingContract = ICCListing(listingAddress);
        address pairAddress = listingContract.uniswapV2PairView();
        require(pairAddress != address(0), "Uniswap V2 pair not set");
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        address token0 = pair.token0();
        bool isToken0In = isBuyOrder ? listingContract.tokenB() == token0 : listingContract.tokenA() == token0;
        context.reserveIn = isToken0In ? IERC20(token0).balanceOf(pairAddress) : IERC20(listingContract.tokenB()).balanceOf(pairAddress);
        context.reserveOut = isToken0In ? IERC20(listingContract.tokenA()).balanceOf(pairAddress) : IERC20(token0).balanceOf(pairAddress);
        context.decimalsIn = isBuyOrder ? listingContract.decimalsB() : listingContract.decimalsA();
        context.decimalsOut = isBuyOrder ? listingContract.decimalsA() : listingContract.decimalsB();
        context.normalizedReserveIn = normalize(context.reserveIn, context.decimalsIn);
        context.normalizedReserveOut = normalize(context.reserveOut, context.decimalsOut);
    }

    function _computeCurrentPrice(address listingAddress) private view returns (uint256 price) {
        // Fetches current price from listingContract.prices(0)
        ICCListing listingContract = ICCListing(listingAddress);
        price = listingContract.prices(0);
        require(price > 0, "Invalid price from listing");
    }

    function _computeSwapImpact(address listingAddress, uint256 amountIn, bool isBuyOrder) private view returns (uint256 price, uint256 amountOut) {
        // Computes swap impact price and output amount using balanceOf reserves
        SwapImpactContext memory context = _getSwapReserves(listingAddress, isBuyOrder);
        require(context.normalizedReserveIn > 0 && context.normalizedReserveOut > 0, "Zero reserves");
        context.amountInAfterFee = (amountIn * 997) / 1000; // 0.3% fee
        context.amountOut = (context.amountInAfterFee * context.normalizedReserveOut) / (context.normalizedReserveIn + context.amountInAfterFee);
        context.price = context.normalizedReserveOut > context.amountOut
            ? ((context.normalizedReserveIn + context.amountInAfterFee) * 1e18) / (context.normalizedReserveOut - context.amountOut)
            : type(uint256).max;
        amountOut = denormalize(context.amountOut, context.decimalsOut);
        price = context.price;
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
    ) private view returns (uint256 preBalance) {
        // Computes pre-transfer balance for recipient
        preBalance = tokenAddress == address(0)
            ? recipientAddress.balance
            : IERC20(tokenAddress).balanceOf(recipientAddress);
    }

    function _prepareLiquidityTransaction(
        address listingAddress,
        uint256 inputAmount,
        bool isBuyOrder
    ) internal view returns (uint256 amountOut, address tokenIn, address tokenOut) {
        // Prepares liquidity transaction, calculating output amount
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        amountOut = inputAmount; // Simplified, assumes external swap logic
        tokenIn = isBuyOrder ? listingContract.tokenB() : listingContract.tokenA();
        tokenOut = isBuyOrder ? listingContract.tokenA() : listingContract.tokenB();
        // Validate sufficient liquidity
        if (isBuyOrder) {
            require(yAmount >= inputAmount, "Insufficient y liquidity");
        } else {
            require(xAmount >= inputAmount, "Insufficient x liquidity");
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
        require(amountReceived <= pending, "Amount exceeds pending");
        (result.tokenAddress, result.tokenDecimals) = _getTokenAndDecimals(listingAddress, true);
        (result.makerAddress, result.recipientAddress, result.orderStatus) = listingContract.getBuyOrderCore(orderIdentifier);
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
        result.normalizedReceived = result.amountReceived > 0 ? normalize(result.amountReceived, result.tokenDecimals) : 0;
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
        require(amountReceived <= pending, "Amount exceeds pending");
        (result.tokenAddress, result.tokenDecimals) = _getTokenAndDecimals(listingAddress, false);
        (result.makerAddress, result.recipientAddress, result.orderStatus) = listingContract.getSellOrderCore(orderIdentifier);
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
        result.normalizedReceived = result.amountReceived > 0 ? normalize(result.amountReceived, result.tokenDecimals) : 0;
        result.amountSent = result.amountReceived;
    }

    function _createBuyOrderUpdates(
        uint256 orderIdentifier,
        BuyOrderUpdateContext memory updateContext,
        uint256 pendingAmount
    ) internal pure returns (ICCListing.UpdateType[] memory) {
        // Creates update structs for buy order processing
        ICCListing.UpdateType[] memory updates = new ICCListing.UpdateType[](2);
        updates[0] = ICCListing.UpdateType({
            updateType: 1,
            structId: 2,
            index: orderIdentifier,
            value: updateContext.normalizedReceived,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: updateContext.amountSent
        });
        updates[1] = ICCListing.UpdateType({
            updateType: 1,
            structId: 0,
            index: orderIdentifier,
            value: updateContext.status == 1 && updateContext.normalizedReceived >= pendingAmount ? 3 : 2,
            addr: updateContext.makerAddress,
            recipient: updateContext.recipient,
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        return updates;
    }

    function _createSellOrderUpdates(
        uint256 orderIdentifier,
        SellOrderUpdateContext memory updateContext,
        uint256 pendingAmount
    ) internal pure returns (ICCListing.UpdateType[] memory) {
        // Creates update structs for sell order processing
        ICCListing.UpdateType[] memory updates = new ICCListing.UpdateType[](2);
        updates[0] = ICCListing.UpdateType({
            updateType: 2,
            structId: 2,
            index: orderIdentifier,
            value: updateContext.normalizedReceived,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: updateContext.amountSent
        });
        updates[1] = ICCListing.UpdateType({
            updateType: 2,
            structId: 0,
            index: orderIdentifier,
            value: updateContext.status == 1 && updateContext.normalizedReceived >= pendingAmount ? 3 : 2,
            addr: updateContext.makerAddress,
            recipient: updateContext.recipient,
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        return updates;
    }

    function _prepBuyLiquidUpdates(
        OrderContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Prepares buy order liquidation updates with price validation
        if (!_checkPricing(address(context.listingContract), orderIdentifier, true, pendingAmount)) {
            (uint256 maxPrice, uint256 minPrice) = context.listingContract.getBuyOrderPricing(orderIdentifier);
            (uint256 impactPrice,) = _computeSwapImpact(address(context.listingContract), pendingAmount, true);
            emit PriceOutOfBounds(address(context.listingContract), orderIdentifier, impactPrice, maxPrice, minPrice);
            return new ICCListing.UpdateType[](0);
        }
        (uint256 amountOut, , ) = _prepareLiquidityTransaction(address(context.listingContract), pendingAmount, true);
        PrepOrderUpdateResult memory result = _prepBuyOrderUpdate(address(context.listingContract), orderIdentifier, amountOut);
        if (result.normalizedReceived == 0) {
            return new ICCListing.UpdateType[](0);
        }
        BuyOrderUpdateContext memory updateContext = BuyOrderUpdateContext({
            makerAddress: result.makerAddress,
            recipient: result.recipientAddress,
            status: result.orderStatus,
            amountReceived: result.amountReceived,
            normalizedReceived: result.normalizedReceived,
            amountSent: result.amountSent
        });
        return _createBuyOrderUpdates(orderIdentifier, updateContext, pendingAmount);
    }

    function _prepSellLiquidUpdates(
        OrderContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Prepares sell order liquidation updates with price validation
        if (!_checkPricing(address(context.listingContract), orderIdentifier, false, pendingAmount)) {
            (uint256 maxPrice, uint256 minPrice) = context.listingContract.getSellOrderPricing(orderIdentifier);
            (uint256 impactPrice,) = _computeSwapImpact(address(context.listingContract), pendingAmount, false);
            emit PriceOutOfBounds(address(context.listingContract), orderIdentifier, impactPrice, maxPrice, minPrice);
            return new ICCListing.UpdateType[](0);
        }
        (uint256 amountOut, , ) = _prepareLiquidityTransaction(address(context.listingContract), pendingAmount, false);
        PrepOrderUpdateResult memory result = _prepSellOrderUpdate(address(context.listingContract), orderIdentifier, amountOut);
        if (result.normalizedReceived == 0) {
            return new ICCListing.UpdateType[](0);
        }
        SellOrderUpdateContext memory updateContext = SellOrderUpdateContext({
            makerAddress: result.makerAddress,
            recipient: result.recipientAddress,
            status: result.orderStatus,
            amountReceived: result.amountReceived,
            normalizedReceived: result.normalizedReceived,
            amountSent: result.amountSent
        });
        return _createSellOrderUpdates(orderIdentifier, updateContext, pendingAmount);
    }

    function executeSingleBuyLiquid(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Executes a single buy order liquidation
        ICCListing listingContract = ICCListing(listingAddress);
        (uint256 pendingAmount, , ) = listingContract.getBuyOrderAmounts(orderIdentifier);
        if (pendingAmount == 0) {
            return new ICCListing.UpdateType[](0);
        }
        OrderContext memory context = OrderContext({
            listingContract: listingContract,
            tokenIn: listingContract.tokenB(),
            tokenOut: listingContract.tokenA(),
            liquidityAddr: listingContract.liquidityAddressView()
        });
        return _prepBuyLiquidUpdates(context, orderIdentifier, pendingAmount);
    }

    function executeSingleSellLiquid(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Executes a single sell order liquidation
        ICCListing listingContract = ICCListing(listingAddress);
        (uint256 pendingAmount, , ) = listingContract.getSellOrderAmounts(orderIdentifier);
        if (pendingAmount == 0) {
            return new ICCListing.UpdateType[](0);
        }
        OrderContext memory context = OrderContext({
            listingContract: listingContract,
            tokenIn: listingContract.tokenA(),
            tokenOut: listingContract.tokenB(),
            liquidityAddr: listingContract.liquidityAddressView()
        });
        return _prepSellLiquidUpdates(context, orderIdentifier, pendingAmount);
    }

    function _collectOrderIdentifiers(
        address listingAddress,
        uint256 maxIterations,
        bool isBuyOrder
    ) internal view returns (uint256[] memory orderIdentifiers, uint256 iterationCount) {
        // Collects order identifiers up to maxIterations
        ICCListing listingContract = ICCListing(listingAddress);
        uint256[] memory identifiers = isBuyOrder ? listingContract.pendingBuyOrdersView() : listingContract.pendingSellOrdersView();
        iterationCount = maxIterations < identifiers.length ? maxIterations : identifiers.length;
        orderIdentifiers = new uint256[](iterationCount);
        for (uint256 i = 0; i < iterationCount; i++) {
            orderIdentifiers[i] = identifiers[i];
        }
    }

    function _processSingleOrder(
        address listingAddress,
        uint256 orderIdentifier,
        bool isBuyOrder,
        uint256 pendingAmount
    ) internal returns (ICCListing.UpdateType[] memory updates) {
        // Processes a single order, settling at current price if impact price is within bounds
        (uint256 maxPrice, uint256 minPrice) = isBuyOrder
            ? ICCListing(listingAddress).getBuyOrderPricing(orderIdentifier)
            : ICCListing(listingAddress).getSellOrderPricing(orderIdentifier);
        uint256 currentPrice = _computeCurrentPrice(listingAddress);
        (uint256 impactPrice, uint256 amountOut) = _computeSwapImpact(listingAddress, pendingAmount, isBuyOrder);
        if (impactPrice >= minPrice && impactPrice <= maxPrice && currentPrice >= minPrice && currentPrice <= maxPrice) {
            // Settle at current price using available liquidity
            uint256 settleAmount = amountOut;
            updates = isBuyOrder
                ? executeSingleBuyLiquid(listingAddress, orderIdentifier)
                : executeSingleSellLiquid(listingAddress, orderIdentifier);
            if (updates.length > 0) {
                // Update liquidity amounts
                ICCLiquidity liquidityContract = ICCLiquidity(ICCListing(listingAddress).liquidityAddressView());
                ICCLiquidity.UpdateType[] memory liquidityUpdates = new ICCLiquidity.UpdateType[](1);
                liquidityUpdates[0] = ICCLiquidity.UpdateType({
                    updateType: 0,
                    index: isBuyOrder ? 1 : 0,
                    value: isBuyOrder ? pendingAmount : amountOut,
                    addr: address(this),
                    recipient: address(0)
                });
                try liquidityContract.update(address(this), liquidityUpdates) {
                } catch (bytes memory reason) {
                    revert(string(abi.encodePacked("Liquidity update failed: ", reason)));
                }
            }
        } else {
            emit PriceOutOfBounds(listingAddress, orderIdentifier, impactPrice, maxPrice, minPrice);
            updates = new ICCListing.UpdateType[](0);
        }
    }

    function _processOrderBatch(
        address listingAddress,
        uint256 maxIterations,
        bool isBuyOrder
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Processes a batch of orders, collecting and executing up to maxIterations
        OrderBatchContext memory batchContext = OrderBatchContext({
            listingAddress: listingAddress,
            maxIterations: maxIterations,
            isBuyOrder: isBuyOrder
        });
        (uint256[] memory orderIdentifiers, uint256 iterationCount) = _collectOrderIdentifiers(
            batchContext.listingAddress,
            batchContext.maxIterations,
            batchContext.isBuyOrder
        );
        ICCListing.UpdateType[] memory tempUpdates = new ICCListing.UpdateType[](iterationCount * 3);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            (uint256 pendingAmount, , ) = batchContext.isBuyOrder
                ? ICCListing(listingAddress).getBuyOrderAmounts(orderIdentifiers[i])
                : ICCListing(listingAddress).getSellOrderAmounts(orderIdentifiers[i]);
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

    function _finalizeUpdates(
        ICCListing.UpdateType[] memory tempUpdates,
        uint256 updateIndex
    ) internal pure returns (ICCListing.UpdateType[] memory finalUpdates) {
        // Resizes and returns final updates array
        finalUpdates = new ICCListing.UpdateType[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalUpdates[i] = tempUpdates[i];
        }
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