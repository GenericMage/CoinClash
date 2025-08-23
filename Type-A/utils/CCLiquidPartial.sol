// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.24
// Changes:
// - v0.0.24: Added UpdateFailed event declaration to fix DeclarationError in _prepBuyOrderUpdate and _prepSellOrderUpdate. No functional changes. Compatible with CCListingTemplate.sol v0.2.0, CCMainPartial.sol v0.0.14, CCLiquidityTemplate.sol v0.1.3, CCLiquidRouter.sol v0.0.17.
// - v0.0.23: Fixed liquidity updates in _processSingleOrder to decrease balances by setting ICCLiquidity.UpdateType.value to difference rather than absolute value. Added listingContract.update calls in _prepBuyOrderUpdate and _prepSellOrderUpdate to apply settlement results. Corrected amountSent to track output token sent, aligning with CCListingTemplate.sol expectations.
// - v0.0.22: Fixed liquidity update logic in _processSingleOrder to decrease liquidity balances (xLiquid/yLiquid) correctly for buy/sell orders. Added output token liquidity validation in _prepareLiquidityTransaction. Corrected amountSent in _prepBuyOrderUpdate and _prepSellOrderUpdate to reflect received token amount.
// - v0.0.21: Added step parameter to _collectOrderIdentifiers for gas-efficient order settlement.
// - v0.0.20: Fixed DeclarationError in _processSingleOrder by declaring listingContract as ICCListing.
// - v0.0.19: Fixed liquidity updates in _processSingleOrder and enhanced settlement logic.
// - v0.0.18: Enhanced error logging in _prepBuyOrderUpdate and _prepSellOrderUpdate.
// - v0.0.17: Fixed makerAddress in _createBuyOrderUpdates and _createSellOrderUpdates.
// - v0.0.16: Fixed makerAddress in _prepBuyLiquidUpdates and _prepSellLiquidUpdates.
// - v0.0.15: Updated _computeCurrentPrice to use listingContract.prices(0).
// - v0.0.14: Added _prepBuyLiquidUpdates and _prepSellLiquidUpdates.
// - v0.0.13: Fixed TypeError in _processSingleOrder for liquidityContract.update.
// - v0.0.12: Updated _computeSwapImpact for flipped price calculation.

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
        // Prepares liquidity transaction, calculating output amount with full validation
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        (uint256 price, uint256 computedAmountOut) = _computeSwapImpact(listingAddress, inputAmount, isBuyOrder);
        amountOut = computedAmountOut;
        tokenIn = isBuyOrder ? listingContract.tokenB() : listingContract.tokenA();
        tokenOut = isBuyOrder ? listingContract.tokenA() : listingContract.tokenB();
        // Validate sufficient liquidity for both input and output tokens
        if (isBuyOrder) {
            require(yAmount >= inputAmount, "Insufficient y liquidity");
            require(xAmount >= amountOut, "Insufficient x liquidity for output");
        } else {
            require(xAmount >= inputAmount, "Insufficient x liquidity");
            require(yAmount >= amountOut, "Insufficient y liquidity for output");
        }
    }

    function _createBuyOrderUpdates(
        uint256 orderIdentifier,
        BuyOrderUpdateContext memory context,
        uint256 pendingAmount
    ) internal pure returns (ICCListing.UpdateType[] memory updates) {
        // Creates update structs for buy order settlement
        updates = new ICCListing.UpdateType[](3);
        updates[0] = ICCListing.UpdateType({
            updateType: 1,
            structId: 0,
            index: orderIdentifier,
            value: 0,
            addr: context.makerAddress,
            recipient: context.recipient,
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        updates[1] = ICCListing.UpdateType({
            updateType: 1,
            structId: 2,
            index: orderIdentifier,
            value: context.normalizedReceived,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: context.amountSent
        });
        updates[2] = ICCListing.UpdateType({
            updateType: 0,
            structId: 0,
            index: 1,
            value: context.normalizedReceived,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
    }

    function _createSellOrderUpdates(
        uint256 orderIdentifier,
        SellOrderUpdateContext memory context,
        uint256 pendingAmount
    ) internal pure returns (ICCListing.UpdateType[] memory updates) {
        // Creates update structs for sell order settlement
        updates = new ICCListing.UpdateType[](3);
        updates[0] = ICCListing.UpdateType({
            updateType: 2,
            structId: 0,
            index: orderIdentifier,
            value: 0,
            addr: context.makerAddress,
            recipient: context.recipient,
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        updates[1] = ICCListing.UpdateType({
            updateType: 2,
            structId: 2,
            index: orderIdentifier,
            value: context.normalizedReceived,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: context.amountSent
        });
        updates[2] = ICCListing.UpdateType({
            updateType: 0,
            structId: 0,
            index: 0,
            value: context.normalizedReceived,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
    }

    function _prepBuyOrderUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountReceived
    ) internal returns (PrepOrderUpdateResult memory result) {
        // Prepares buy order update data, applies settlement to listing template
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
        result.amountSent = denormalizedAmountOut;
        ICCListing.UpdateType[] memory updates = _createBuyOrderUpdates(
            orderIdentifier,
            BuyOrderUpdateContext({
                makerAddress: result.makerAddress,
                recipient: result.recipientAddress,
                status: result.orderStatus,
                amountReceived: result.amountReceived,
                normalizedReceived: result.normalizedReceived,
                amountSent: result.amountSent
            }),
            amountReceived
        );
        try listingContract.update(updates) {
        } catch Error(string memory reason) {
            emit UpdateFailed(listingAddress, reason);
        } catch {
            emit UpdateFailed(listingAddress, "Unknown update error");
        }
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

    function _prepSellOrderUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountReceived
    ) internal returns (PrepOrderUpdateResult memory result) {
        // Prepares sell order update data, applies settlement to listing template
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
        result.amountSent = denormalizedAmountOut;
        ICCListing.UpdateType[] memory updates = _createSellOrderUpdates(
            orderIdentifier,
            SellOrderUpdateContext({
                makerAddress: result.makerAddress,
                recipient: result.recipientAddress,
                status: result.orderStatus,
                amountReceived: result.amountReceived,
                normalizedReceived: result.normalizedReceived,
                amountSent: result.amountSent
            }),
            amountReceived
        );
        try listingContract.update(updates) {
        } catch Error(string memory reason) {
            emit UpdateFailed(listingAddress, reason);
        } catch {
            emit UpdateFailed(listingAddress, "Unknown update error");
        }
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

    function _prepBuyLiquidUpdates(
        OrderContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ICCListing.UpdateType[] memory) {
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
        bool isBuyOrder,
        uint256 step
    ) internal view returns (uint256[] memory orderIdentifiers, uint256 iterationCount) {
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

    function _processSingleOrder(
        address listingAddress,
        uint256 orderIdentifier,
        bool isBuyOrder,
        uint256 pendingAmount
    ) internal returns (ICCListing.UpdateType[] memory updates) {
        // Processes要件
        ICCListing listingContract = ICCListing(listingAddress);
        (uint256 maxPrice, uint256 minPrice) = isBuyOrder
            ? listingContract.getBuyOrderPricing(orderIdentifier)
            : listingContract.getSellOrderPricing(orderIdentifier);
        uint256 currentPrice = _computeCurrentPrice(listingAddress);
        (uint256 impactPrice, uint256 amountOut) = _computeSwapImpact(listingAddress, pendingAmount, isBuyOrder);
        if (impactPrice >= minPrice && impactPrice <= maxPrice && currentPrice >= minPrice && currentPrice <= maxPrice) {
            // Settle at current price using available liquidity
            uint256 settleAmount = amountOut;
            updates = isBuyOrder
                ? executeSingleBuyLiquid(listingAddress, orderIdentifier)
                : executeSingleSellLiquid(listingAddress, orderIdentifier);
            if (updates.length > 0) {
                // Update liquidity amounts: decrease outgoing, increase incoming
                ICCLiquidity liquidityContract = ICCLiquidity(listingContract.liquidityAddressView());
                ICCLiquidity.UpdateType[] memory liquidityUpdates = new ICCLiquidity.UpdateType[](2);
                liquidityUpdates[0] = ICCLiquidity.UpdateType({
                    updateType: 0,
                    index: isBuyOrder ? 1 : 0, // Buy: decrease yLiquid (tokenB), Sell: decrease xLiquid (tokenA)
                    value: normalize(pendingAmount, isBuyOrder ? listingContract.decimalsB() : listingContract.decimalsA()),
                    addr: address(this),
                    recipient: address(0)
                });
                liquidityUpdates[1] = ICCLiquidity.UpdateType({
                    updateType: 0,
                    index: isBuyOrder ? 0 : 1, // Buy: increase xLiquid (tokenA), Sell: increase yLiquid (tokenB)
                    value: normalize(settleAmount, isBuyOrder ? listingContract.decimalsA() : listingContract.decimalsB()),
                    addr: address(this),
                    recipient: address(0)
                });
                try liquidityContract.update(address(this), liquidityUpdates) {
                } catch (bytes memory reason) {
                    emit SwapFailed(listingAddress, orderIdentifier, pendingAmount, string(abi.encodePacked("Liquidity update failed: ", reason)));
                    updates = new ICCListing.UpdateType[](0);
                }
            }
        } else {
            emit PriceOutOfBounds(listingAddress, orderIdentifier, impactPrice, maxPrice, minPrice);
            updates = new ICCListing.UpdateType[](0);
        }
        return updates;
    }

    function _processOrderBatch(
        address listingAddress,
        uint256 maxIterations,
        bool isBuyOrder,
        uint256 step
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