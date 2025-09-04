/*
 SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
 Version: 0.0.30
 Changes:
 // - v0.0.30: Updated _updateLiquidityBalances to align with CCLiquidityTemplate.sol v0.1.18, ensuring compatibility with new ccUpdate, maintaining existing updateType=0 behavior for xLiquid/yLiquid updates. No new update types added as they are not required for liquidity balance updates.
 - v0.0.29: Refactored _createBuyOrderUpdates and _createSellOrderUpdates to resolve "Stack too deep" error by splitting into helper functions (_prepareCoreUpdate, _prepareAmountsUpdate, _prepareBalanceUpdate). Each helper handles <=4 variables, segregated by struct group (Core, Amounts, Balance). Maintains ccUpdate with three arrays, using preTransferWithdrawn for pending/filled and pre/post balance checks for amountSent. Compatible with CCListingTemplate.sol v0.3.0, CCMainPartial.sol v0.1.1, CCLiquidityTemplate.sol v0.1.3, CCLiquidRouter.sol v0.0.20.
 - v0.0.28: Updated _createBuyOrderUpdates and _createSellOrderUpdates to use ccUpdate with three arrays, fetching maker/recipient, updating pending/filled with preTransferWithdrawn, and amountSent via pre/post balance checks.
 - v0.0.27: Clarified amountSent for current settlement.
 - v0.0.26: Refactored _processSingleOrder to use _updateLiquidityBalances.
 - v0.0.25: Removed listingContract.update() from _prepBuy/SellOrderUpdate.
 - v0.0.24: Added UpdateFailed event.
 - v0.0.23: Fixed liquidity updates in _processSingleOrder.
 - v0.0.22: Fixed liquidity balance decreases.
 - v0.0.21: Added step parameter to _collectOrderIdentifiers.
 - v0.0.20: Declared listingContract as ICCListing.
 - v0.0.19: Enhanced settlement logic.
 - v0.0.18: Improved error logging.
 - v0.0.17: Fixed makerAddress in _createBuy/SellOrderUpdates.
 - v0.0.16: Fixed makerAddress in _prepBuy/SellLiquidUpdates.
 - v0.0.15: Updated _computeCurrentPrice to use prices(0).
 - v0.0.14: Added _prepBuy/SellLiquidUpdates.
 - v0.0.13: Fixed TypeError in _processSingleOrder.
 - v0.0.12: Updated _computeSwapImpact for flipped price.
*/
pragma solidity ^0.8.2;

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
        uint256 preTransferWithdrawn;
    }

    struct BuyOrderUpdateContext {
        address makerAddress;
        address recipient;
        uint8 status;
        uint256 amountReceived;
        uint256 normalizedReceived;
        uint256 amountSent;
        uint256 preTransferWithdrawn;
    }

    struct SellOrderUpdateContext {
        address makerAddress;
        address recipient;
        uint8 status;
        uint256 amountReceived;
        uint256 normalizedReceived;
        uint256 amountSent;
        uint256 preTransferWithdrawn;
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

    event PriceOutOfBounds(address indexed listingAddress, uint256 orderId, uint256 impactPrice, uint256 maxPrice, uint256 minPrice);
    event MissingUniswapRouter(address indexed listingAddress, uint256 orderId, string reason);
    event TokenTransferFailed(address indexed listingAddress, uint256 orderId, address token, string reason);
    event SwapFailed(address indexed listingAddress, uint256 orderId, uint256 amountIn, string reason);
    event ApprovalFailed(address indexed listingAddress, uint256 orderId, address token, string reason);
    event UpdateFailed(address indexed listingAddress, string reason);

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
        // Fetches current price from listingContract.prices(0) with try-catch
        ICCListing listingContract = ICCListing(listingAddress);
        try listingContract.prices(0) returns (uint256 _price) {
            price = _price;
            require(price > 0, "Invalid price from listing");
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Price fetch failed: ", reason)));
        } catch {
            revert("Price fetch failed: Unknown error");
        }
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

    function _getTokenAndDecimals(address listingAddress, bool isBuyOrder) internal view returns (address tokenAddress, uint8 tokenDecimals) {
        // Retrieves token address and decimals based on order type
        ICCListing listingContract = ICCListing(listingAddress);
        tokenAddress = isBuyOrder ? listingContract.tokenB() : listingContract.tokenA();
        tokenDecimals = isBuyOrder ? listingContract.decimalsB() : listingContract.decimalsA();
    }

    function _checkPricing(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, uint256 pendingAmount) internal view returns (bool) {
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

    function _computeAmountSent(address tokenAddress, address recipientAddress, uint256 amount) private view returns (uint256 preBalance) {
        // Computes pre-transfer balance for recipient
        preBalance = tokenAddress == address(0)
            ? recipientAddress.balance
            : IERC20(tokenAddress).balanceOf(recipientAddress);
    }

    function _prepareLiquidityTransaction(address listingAddress, uint256 inputAmount, bool isBuyOrder) internal view returns (uint256 amountOut, address tokenIn, address tokenOut) {
        // Prepares liquidity transaction, calculating output amount with full validation
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        (uint256 price, uint256 computedAmountOut) = _computeSwapImpact(listingAddress, inputAmount, isBuyOrder);
        amountOut = computedAmountOut;
        tokenIn = isBuyOrder ? listingContract.tokenB() : listingContract.tokenA();
        tokenOut = isBuyOrder ? listingContract.tokenA() : listingContract.tokenB();
        if (isBuyOrder) {
            require(yAmount >= inputAmount, "Insufficient y liquidity");
            require(xAmount >= amountOut, "Insufficient x liquidity for output");
        } else {
            require(xAmount >= inputAmount, "Insufficient x liquidity");
            require(yAmount >= amountOut, "Insufficient y liquidity for output");
        }
    }

    function _prepareCoreUpdate(uint256 orderIdentifier, address listingAddress, bool isBuyOrder, uint8 status) private view returns (uint8 updateType, uint8 updateSort, uint256 updateData) {
        // Prepares Core update for buy/sell order
        ICCListing listingContract = ICCListing(listingAddress);
        (address maker, address recipient,) = isBuyOrder
            ? listingContract.getBuyOrderCore(orderIdentifier)
            : listingContract.getSellOrderCore(orderIdentifier);
        updateType = isBuyOrder ? 1 : 2; // Buy: 1, Sell: 2
        updateSort = 0; // Core
        updateData = uint256(bytes32(abi.encode(maker, recipient, status)));
    }

    function _prepareAmountsUpdate(uint256 orderIdentifier, address listingAddress, bool isBuyOrder, uint256 preTransferWithdrawn, uint256 amountSent) private view returns (uint8 updateType, uint8 updateSort, uint256 updateData) {
        // Prepares Amounts update for buy/sell order
        ICCListing listingContract = ICCListing(listingAddress);
        (uint256 pending, uint256 filled,) = isBuyOrder
            ? listingContract.getBuyOrderAmounts(orderIdentifier)
            : listingContract.getSellOrderAmounts(orderIdentifier);
        uint256 newPending = pending >= preTransferWithdrawn ? pending - preTransferWithdrawn : 0;
        uint256 newFilled = filled + preTransferWithdrawn;
        updateType = isBuyOrder ? 1 : 2; // Buy: 1, Sell: 2
        updateSort = 2; // Amounts
        updateData = uint256(bytes32(abi.encode(newPending, newFilled, amountSent)));
    }

    function _prepareBalanceUpdate(uint256 normalizedReceived, bool isBuyOrder) private pure returns (uint8 updateType, uint8 updateSort, uint256 updateData) {
        // Prepares Balance update for buy/sell order
        updateType = 0; // Balance
        updateSort = 0; // Balance
        updateData = normalizedReceived; // Increase yBalance (buy) or xBalance (sell)
    }

    function _createBuyOrderUpdates(uint256 orderIdentifier, BuyOrderUpdateContext memory context, uint256 pendingAmount) internal view returns (uint8[] memory updateType, uint8[] memory updateSort, uint256[] memory updateData) {
        // Creates update arrays for buy order settlement using helper functions
        updateType = new uint8[](3);
        updateSort = new uint8[](3);
        updateData = new uint256[](3);

        uint8 newStatus = context.preTransferWithdrawn >= pendingAmount ? 3 : 2; // 3: filled, 2: partially filled

        // Core update
        (updateType[0], updateSort[0], updateData[0]) = _prepareCoreUpdate(orderIdentifier, context.recipient, true, newStatus);

        // Amounts update
        (updateType[1], updateSort[1], updateData[1]) = _prepareAmountsUpdate(orderIdentifier, context.recipient, true, context.preTransferWithdrawn, context.amountSent);

        // Balance update
        (updateType[2], updateSort[2], updateData[2]) = _prepareBalanceUpdate(context.normalizedReceived, true);
    }

    function _createSellOrderUpdates(uint256 orderIdentifier, SellOrderUpdateContext memory context, uint256 pendingAmount) internal view returns (uint8[] memory updateType, uint8[] memory updateSort, uint256[] memory updateData) {
        // Creates update arrays for sell order settlement using helper functions
        updateType = new uint8[](3);
        updateSort = new uint8[](3);
        updateData = new uint256[](3);

        uint8 newStatus = context.preTransferWithdrawn >= pendingAmount ? 3 : 2; // 3: filled, 2: partially filled

        // Core update
        (updateType[0], updateSort[0], updateData[0]) = _prepareCoreUpdate(orderIdentifier, context.recipient, false, newStatus);

        // Amounts update
        (updateType[1], updateSort[1], updateData[1]) = _prepareAmountsUpdate(orderIdentifier, context.recipient, false, context.preTransferWithdrawn, context.amountSent);

        // Balance update
        (updateType[2], updateSort[2], updateData[2]) = _prepareBalanceUpdate(context.normalizedReceived, false);
    }

    function _prepBuyOrderUpdate(address listingAddress, uint256 orderIdentifier, uint256 amountReceived) internal returns (PrepOrderUpdateResult memory result) {
        // Prepares buy order update data, handles token transfers
        ICCListing listingContract = ICCListing(listingAddress);
        (uint256 pending, uint256 filled, ) = listingContract.getBuyOrderAmounts(orderIdentifier);
        require(amountReceived <= pending, "Amount exceeds pending");
        (result.tokenAddress, result.tokenDecimals) = _getTokenAndDecimals(listingAddress, true);
        (result.makerAddress, result.recipientAddress, result.orderStatus) = listingContract.getBuyOrderCore(orderIdentifier);
        (uint256 amountOut, , address tokenOut) = _prepareLiquidityTransaction(listingAddress, amountReceived, true);
        uint256 denormalizedAmount = denormalize(amountReceived, result.tokenDecimals);
        uint256 denormalizedAmountOut = denormalize(amountOut, listingContract.decimalsA());
        uint256 preBalance = _computeAmountSent(tokenOut, result.recipientAddress, denormalizedAmountOut);
        address liquidityAddr = listingContract.liquidityAddressView();
        if (uniswapV2Router == address(0)) {
            emit MissingUniswapRouter(listingAddress, orderIdentifier, "Uniswap router not set");
            return result;
        }
        if (result.tokenAddress != address(0)) {
            try IERC20(result.tokenAddress).approve(uniswapV2Router, denormalizedAmount) {
            } catch Error(string memory reason) {
                emit ApprovalFailed(listingAddress, orderIdentifier, result.tokenAddress, reason);
                return result;
            }
        }
        result.amountReceived = amountReceived;
        result.normalizedReceived = normalize(amountReceived, result.tokenDecimals);
        result.preTransferWithdrawn = denormalizedAmount;
        if (result.tokenAddress == address(0)) {
            try listingContract.transactNative{value: denormalizedAmount}(denormalizedAmount, liquidityAddr) {
                uint256 postBalance = IERC20(tokenOut).balanceOf(result.recipientAddress);
                result.amountSent = postBalance > preBalance ? postBalance - preBalance : 0;
            } catch Error(string memory reason) {
                emit TokenTransferFailed(listingAddress, orderIdentifier, result.tokenAddress, reason);
                return result;
            }
        } else {
            try listingContract.transactToken(result.tokenAddress, denormalizedAmount, liquidityAddr) {
                uint256 postBalance = IERC20(tokenOut).balanceOf(result.recipientAddress);
                result.amountSent = postBalance > preBalance ? postBalance - preBalance : 0;
            } catch Error(string memory reason) {
                emit TokenTransferFailed(listingAddress, orderIdentifier, result.tokenAddress, reason);
                return result;
            }
        }
        return result;
    }

    function _prepSellOrderUpdate(address listingAddress, uint256 orderIdentifier, uint256 amountReceived) internal returns (PrepOrderUpdateResult memory result) {
        // Prepares sell order update data, handles token transfers
        ICCListing listingContract = ICCListing(listingAddress);
        (uint256 pending, uint256 filled, ) = listingContract.getSellOrderAmounts(orderIdentifier);
        require(amountReceived <= pending, "Amount exceeds pending");
        (result.tokenAddress, result.tokenDecimals) = _getTokenAndDecimals(listingAddress, false);
        (result.makerAddress, result.recipientAddress, result.orderStatus) = listingContract.getSellOrderCore(orderIdentifier);
        (uint256 amountOut, , address tokenOut) = _prepareLiquidityTransaction(listingAddress, amountReceived, false);
        uint256 denormalizedAmount = denormalize(amountReceived, result.tokenDecimals);
        uint256 denormalizedAmountOut = denormalize(amountOut, listingContract.decimalsB());
        uint256 preBalance = _computeAmountSent(tokenOut, result.recipientAddress, denormalizedAmountOut);
        address liquidityAddr = listingContract.liquidityAddressView();
        if (uniswapV2Router == address(0)) {
            emit MissingUniswapRouter(listingAddress, orderIdentifier, "Uniswap router not set");
            return result;
        }
        if (result.tokenAddress != address(0)) {
            try IERC20(result.tokenAddress).approve(uniswapV2Router, denormalizedAmount) {
            } catch Error(string memory reason) {
                emit ApprovalFailed(listingAddress, orderIdentifier, result.tokenAddress, reason);
                return result;
            }
        }
        result.amountReceived = amountReceived;
        result.normalizedReceived = normalize(amountReceived, result.tokenDecimals);
        result.preTransferWithdrawn = denormalizedAmount;
        try listingContract.transactToken(result.tokenAddress, denormalizedAmount, liquidityAddr) {
            uint256 postBalance = IERC20(tokenOut).balanceOf(result.recipientAddress);
            result.amountSent = postBalance > preBalance ? postBalance - preBalance : 0;
        } catch Error(string memory reason) {
            emit TokenTransferFailed(listingAddress, orderIdentifier, result.tokenAddress, reason);
            return result;
        }
        return result;
    }

    function _prepBuyLiquidUpdates(OrderContext memory context, uint256 orderIdentifier, uint256 pendingAmount) internal returns (ICCListing.UpdateType[] memory) {
        // Prepares buy order liquidation updates with price validation
        if (!_checkPricing(address(context.listingContract), orderIdentifier, true, pendingAmount)) {
            (uint256 maxPrice, uint256 minPrice) = context.listingContract.getBuyOrderPricing(orderIdentifier);
            (uint256 impactPrice,) = _computeSwapImpact(address(context.listingContract), orderIdentifier, true);
            emit PriceOutOfBounds(address(context.listingContract), orderIdentifier, impactPrice, maxPrice, minPrice);
            return new ICCListing.UpdateType[](0);
        }
        (uint256 amountOut, , ) = _prepareLiquidityTransaction(address(context.listingContract), pendingAmount, true);
        if (uniswapV2Router == address(0)) {
            emit MissingUniswapRouter(address(context.listingContract), orderIdentifier, "Uniswap router not set");
            return new ICCListing.UpdateType[](0);
        }
        PrepOrderUpdateResult memory result = _prepBuyOrderUpdate(address(context.listingContract), orderIdentifier, pendingAmount);
        if (result.normalizedReceived == 0) {
            emit SwapFailed(address(context.listingContract), orderIdentifier, pendingAmount, "No tokens received after swap");
            return new ICCListing.UpdateType[](0);
        }
        BuyOrderUpdateContext memory updateContext = BuyOrderUpdateContext({
            makerAddress: result.makerAddress,
            recipient: result.recipientAddress,
            status: result.orderStatus,
            amountReceived: result.amountReceived,
            normalizedReceived: result.normalizedReceived,
            amountSent: result.amountSent,
            preTransferWithdrawn: result.preTransferWithdrawn
        });
        (uint8[] memory updateType, uint8[] memory updateSort, uint256[] memory updateData) = _createBuyOrderUpdates(orderIdentifier, updateContext, pendingAmount);
        try context.listingContract.ccUpdate(updateType, updateSort, updateData) {
        } catch Error(string memory reason) {
            emit UpdateFailed(address(context.listingContract), reason);
            return new ICCListing.UpdateType[](0);
        }
        return new ICCListing.UpdateType[](0);
    }

    function _prepSellLiquidUpdates(OrderContext memory context, uint256 orderIdentifier, uint256 pendingAmount) internal returns (ICCListing.UpdateType[] memory) {
        // Prepares sell order liquidation updates with price validation
        if (!_checkPricing(address(context.listingContract), orderIdentifier, false, pendingAmount)) {
            (uint256 maxPrice, uint256 minPrice) = context.listingContract.getSellOrderPricing(orderIdentifier);
            (uint256 impactPrice,) = _computeSwapImpact(address(context.listingContract), orderIdentifier, false);
            emit PriceOutOfBounds(address(context.listingContract), orderIdentifier, impactPrice, maxPrice, minPrice);
            return new ICCListing.UpdateType[](0);
        }
        (uint256 amountOut, , ) = _prepareLiquidityTransaction(address(context.listingContract), pendingAmount, false);
        if (uniswapV2Router == address(0)) {
            emit MissingUniswapRouter(address(context.listingContract), orderIdentifier, "Uniswap router not set");
            return new ICCListing.UpdateType[](0);
        }
        PrepOrderUpdateResult memory result = _prepSellOrderUpdate(address(context.listingContract), orderIdentifier, pendingAmount);
        if (result.normalizedReceived == 0) {
            emit SwapFailed(address(context.listingContract), orderIdentifier, pendingAmount, "No tokens received after swap");
            return new ICCListing.UpdateType[](0);
        }
        SellOrderUpdateContext memory updateContext = SellOrderUpdateContext({
            makerAddress: result.makerAddress,
            recipient: result.recipientAddress,
            status: result.orderStatus,
            amountReceived: result.amountReceived,
            normalizedReceived: result.normalizedReceived,
            amountSent: result.amountSent,
            preTransferWithdrawn: result.preTransferWithdrawn
        });
        (uint8[] memory updateType, uint8[] memory updateSort, uint256[] memory updateData) = _createSellOrderUpdates(orderIdentifier, updateContext, pendingAmount);
        try context.listingContract.ccUpdate(updateType, updateSort, updateData) {
        } catch Error(string memory reason) {
            emit UpdateFailed(address(context.listingContract), reason);
            return new ICCListing.UpdateType[](0);
        }
        return new ICCListing.UpdateType[](0);
    }

    function executeSingleBuyLiquid(address listingAddress, uint256 orderIdentifier) internal returns (ICCListing.UpdateType[] memory) {
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

    function executeSingleSellLiquid(address listingAddress, uint256 orderIdentifier) internal returns (ICCListing.UpdateType[] memory) {
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

    function _collectOrderIdentifiers(address listingAddress, uint256 maxIterations, bool isBuyOrder, uint256 step) internal view returns (uint256[] memory orderIdentifiers, uint256 iterationCount) {
        // Collects order identifiers starting from step up to maxIterations
        ICCListing listingContract = ICCListing(listingAddress);
        uint256[] memory identifiers = isBuyOrder ? listingContract.pendingBuyOrdersView() : listingContract.pendingSellOrdersView();
        require(step <= identifiers.length, "Step exceeds pending orders length");
        uint256 remainingOrders = identifiers.length - step;
        iterationCount = maxIterations < remainingOrders ? maxIterations : remainingOrders;
        orderIdentifiers = new uint256[](iterationCount);
        for (uint256 i = 0; i < iterationCount; i++) {
            orderIdentifiers[i] = identifiers[step + i];
        }
    }

    function _updateLiquidityBalances(
    address listingAddress,
    uint256 orderIdentifier,
    bool isBuyOrder,
    uint256 pendingAmount,
    uint256 settleAmount
) private {
    // Updates liquidity balances: subtract outgoing, add incoming
    ICCListing listingContract = ICCListing(listingAddress);
    ICCLiquidity liquidityContract = ICCLiquidity(listingContract.liquidityAddressView());
    (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
    ICCLiquidity.UpdateType[] memory liquidityUpdates = new ICCLiquidity.UpdateType[](2);
    uint256 normalizedPending = normalize(pendingAmount, isBuyOrder ? listingContract.decimalsB() : listingContract.decimalsA());
    uint256 normalizedSettle = normalize(settleAmount, isBuyOrder ? listingContract.decimalsA() : listingContract.decimalsB());
    liquidityUpdates[0] = ICCLiquidity.UpdateType({
        updateType: 0, // Balance update
        index: isBuyOrder ? 1 : 0, // Buy: decrease yLiquid (tokenB), Sell: decrease xLiquid (tokenA)
        value: isBuyOrder ? yAmount - normalizedPending : xAmount - normalizedPending, // Subtract outgoing
        addr: address(this),
        recipient: address(0)
    });
    liquidityUpdates[1] = ICCLiquidity.UpdateType({
        updateType: 0, // Balance update
        index: isBuyOrder ? 0 : 1, // Buy: increase xLiquid (tokenA), Sell: increase yLiquid (tokenB)
        value: isBuyOrder ? xAmount + normalizedSettle : yAmount + normalizedSettle, // Add incoming
        addr: address(this),
        recipient: address(0)
    });
    try liquidityContract.ccUpdate(address(this), liquidityUpdates) {
    } catch (bytes memory reason) {
        emit SwapFailed(listingAddress, orderIdentifier, pendingAmount, string(abi.encodePacked("Liquidity update failed: ", reason)));
    }
}

    function _processSingleOrder(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, uint256 pendingAmount) internal returns (ICCListing.UpdateType[] memory updates) {
        // Processes a single order, validating pricing and executing settlement
        ICCListing listingContract = ICCListing(listingAddress);
        (uint256 maxPrice, uint256 minPrice) = isBuyOrder
            ? listingContract.getBuyOrderPricing(orderIdentifier)
            : listingContract.getSellOrderPricing(orderIdentifier);
        uint256 currentPrice = _computeCurrentPrice(listingAddress);
        (uint256 impactPrice, uint256 amountOut) = _computeSwapImpact(listingAddress, pendingAmount, isBuyOrder);
        if (impactPrice >= minPrice && impactPrice <= maxPrice && currentPrice >= minPrice && currentPrice <= maxPrice) {
            updates = isBuyOrder
                ? executeSingleBuyLiquid(listingAddress, orderIdentifier)
                : executeSingleSellLiquid(listingAddress, orderIdentifier);
            if (updates.length > 0) {
                _updateLiquidityBalances(listingAddress, orderIdentifier, isBuyOrder, pendingAmount, amountOut);
            }
        } else {
            emit PriceOutOfBounds(listingAddress, orderIdentifier, impactPrice, maxPrice, minPrice);
            updates = new ICCListing.UpdateType[](0);
        }
        return updates;
    }

    function _processOrderBatch(address listingAddress, uint256 maxIterations, bool isBuyOrder, uint256 step) internal returns (ICCListing.UpdateType[] memory) {
        // Processes a batch of orders, collecting and executing up to maxIterations
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

    function _finalizeUpdates(ICCListing.UpdateType[] memory tempUpdates, uint256 updateIndex) internal pure returns (ICCListing.UpdateType[] memory finalUpdates) {
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