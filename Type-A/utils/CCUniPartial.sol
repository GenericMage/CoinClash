// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.3
// Changes:
// - v0.0.3: Refactored _computeSwapImpact to use SwapImpactContext struct and helper functions (_getSwapReserves, _computeSwapOutput) to resolve stack too deep error by reducing local variables.
// - v0.0.2: Refactored _executePartialSellSwap to use SellSwapContext struct and helper functions (_prepareSellSwapData, _executeSellTokenSwap, _executeSellETHSwap) to resolve stack too deep error.
// - v0.0.1: Created CCUniPartial.sol to handle Uniswap-adjacent functionality, including _computeCurrentPrice, _computeSwapImpact, _computeMaxAmountIn, _executePartialBuySwap, _executePartialSellSwap, and related helpers/structs.
// - v0.0.1: Imported CCMainPartial.sol for normalize, denormalize, and uniswapV2Router access.
// - v0.0.1: Defined IUniswapV2Pair and IUniswapV2Router02 interfaces for Uniswap V2 integration.
// - v0.0.1: Added listingContract to BuySwapContext to fix TypeError in _executeBuyETHSwap and _executeBuyTokenSwap.
// Compatible with SSListingTemplate.sol (v0.0.10), CCMainPartial.sol (v0.0.2).

import "./CCMainPartial.sol";

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract CCUniPartial is CCMainPartial {
    using SafeERC20 for IERC20;

    struct MaxAmountInContext {
        uint256 reserveIn;
        uint8 decimalsIn;
        uint256 normalizedReserveIn;
        uint256 currentPrice;
    }

    struct BuySwapContext {
        ISSListingTemplate listingContract;
        address makerAddress;
        address recipientAddress;
        uint8 status;
        address tokenIn;
        address tokenOut;
        uint8 decimalsIn;
        uint8 decimalsOut;
        uint256 denormAmountIn;
        uint256 denormAmountOutMin;
        uint256 price;
        uint256 expectedAmountOut;
    }

    struct SellSwapContext {
        ISSListingTemplate listingContract;
        address makerAddress;
        address recipientAddress;
        uint8 status;
        address tokenIn;
        address tokenOut;
        uint8 decimalsIn;
        uint8 decimalsOut;
        uint256 denormAmountIn;
        uint256 denormAmountOutMin;
        uint256 price;
        uint256 expectedAmountOut;
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

    function _computeCurrentPrice(address listingAddress) internal view returns (uint256 price) {
        // Computes current price from Uniswap V2 pair reserves
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address pairAddress = listingContract.uniswapV2PairView();
        require(pairAddress != address(0), "Uniswap V2 pair not set");
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        address token0 = pair.token0();
        bool isToken0A = listingContract.tokenA() == token0;
        uint256 reserveA = isToken0A ? uint256(reserve0) : uint256(reserve1);
        uint256 reserveB = isToken0A ? uint256(reserve1) : uint256(reserve0);
        uint8 decimalsA = listingContract.decimalsA();
        uint8 decimalsB = listingContract.decimalsB();
        uint256 normalizedReserveA = normalize(reserveA, decimalsA);
        uint256 normalizedReserveB = normalize(reserveB, decimalsB);
        require(normalizedReserveB > 0, "Zero reserveB");
        price = (normalizedReserveA * 1e18) / normalizedReserveB;
    }

    function _getReserveData(
        address listingAddress,
        bool isBuyOrder
    ) private view returns (MaxAmountInContext memory context) {
        // Retrieves reserve data and decimals for maxAmountIn calculation
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address pairAddress = listingContract.uniswapV2PairView();
        require(pairAddress != address(0), "Uniswap V2 pair not set");
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        address token0 = pair.token0();
        bool isToken0In = isBuyOrder ? listingContract.tokenB() == token0 : listingContract.tokenA() == token0;
        context.reserveIn = isToken0In ? uint256(reserve0) : uint256(reserve1);
        context.decimalsIn = isBuyOrder ? listingContract.decimalsB() : listingContract.decimalsA();
        context.normalizedReserveIn = normalize(context.reserveIn, context.decimalsIn);
        context.currentPrice = _computeCurrentPrice(listingAddress);
    }

    function _computePriceImpact(
        MaxAmountInContext memory context,
        uint256 maxPrice,
        uint256 minPrice,
        bool isBuyOrder
    ) private pure returns (uint256 maxImpactPercent) {
        // Computes price impact percentage based on price constraints
        if (isBuyOrder) {
            if (maxPrice < context.currentPrice) return 0;
            maxImpactPercent = (maxPrice * 100e18 / context.currentPrice - 100e18) / 1e18;
        } else {
            if (context.currentPrice < minPrice) return 0;
            maxImpactPercent = (context.currentPrice * 100e18 / minPrice - 100e18) / 1e18;
        }
    }

    function _finalizeMaxAmountIn(
        MaxAmountInContext memory context,
        uint256 maxImpactPercent,
        uint256 pendingAmount
    ) private pure returns (uint256 maxAmountIn) {
        // Finalizes maxAmountIn calculation using normalized reserve and impact
        maxAmountIn = (context.normalizedReserveIn * maxImpactPercent) / (100 * 2);
        maxAmountIn = maxAmountIn > pendingAmount ? pendingAmount : maxAmountIn;
    }

    function _computeMaxAmountIn(
        address listingAddress,
        uint256 maxPrice,
        uint256 minPrice,
        uint256 pendingAmount,
        bool isBuyOrder
    ) internal view returns (uint256 maxAmountIn) {
        // Computes maximum amountIn using internal call tree and struct
        MaxAmountInContext memory context = _getReserveData(listingAddress, isBuyOrder);
        uint256 maxImpactPercent = _computePriceImpact(context, maxPrice, minPrice, isBuyOrder);
        maxAmountIn = _finalizeMaxAmountIn(context, maxImpactPercent, pendingAmount);
    }

    function _getSwapReserves(
        address listingAddress,
        bool isBuyOrder
    ) private view returns (SwapImpactContext memory context) {
        // Retrieves reserves and decimals for swap impact calculation
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address pairAddress = listingContract.uniswapV2PairView();
        require(pairAddress != address(0), "Uniswap V2 pair not set");
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        address token0 = pair.token0();
        bool isToken0In = isBuyOrder ? listingContract.tokenB() == token0 : listingContract.tokenA() == token0;
        context.reserveIn = isToken0In ? uint256(reserve0) : uint256(reserve1);
        context.reserveOut = isToken0In ? uint256(reserve1) : uint256(reserve0);
        context.decimalsIn = isBuyOrder ? listingContract.decimalsB() : listingContract.decimalsA();
        context.decimalsOut = isBuyOrder ? listingContract.decimalsA() : listingContract.decimalsB();
        context.normalizedReserveIn = normalize(context.reserveIn, context.decimalsIn);
        context.normalizedReserveOut = normalize(context.reserveOut, context.decimalsOut);
    }

    function _computeSwapOutput(
        SwapImpactContext memory context,
        uint256 inputAmount
    ) private pure returns (uint256 price, uint256 amountOut) {
        // Computes swap output and price using Uniswap V2 formula
        require(context.normalizedReserveIn > 0 && context.normalizedReserveOut > 0, "Zero reserves");
        context.amountInAfterFee = (inputAmount * 997) / 1000; // 0.3% fee
        context.amountOut = (context.amountInAfterFee * context.normalizedReserveOut) / 
                           (context.normalizedReserveIn + context.amountInAfterFee);
        context.price = context.amountOut > 0 ? (inputAmount * 1e18) / context.amountOut : type(uint256).max;
        amountOut = denormalize(context.amountOut, context.decimalsOut);
        price = context.price;
    }

    function _computeSwapImpact(
        address listingAddress,
        uint256 inputAmount,
        bool isBuyOrder
    ) internal view returns (uint256 price, uint256 amountOut) {
        // Computes swap impact price using Uniswap V2 pair reserves
        SwapImpactContext memory context = _getSwapReserves(listingAddress, isBuyOrder);
        (price, amountOut) = _computeSwapOutput(context, inputAmount);
    }

    function _prepareSwapData(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountIn
    ) internal view returns (BuySwapContext memory context, address[] memory path) {
        // Prepares swap data for buy order, including order details and swap path
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        (context.makerAddress, context.recipientAddress, context.status) = listingContract.getBuyOrderCore(orderIdentifier);
        (uint256 maxPrice, uint256 minPrice) = listingContract.getBuyOrderPricing(orderIdentifier);
        context.listingContract = listingContract;
        context.tokenIn = listingContract.tokenB();
        context.tokenOut = listingContract.tokenA();
        context.decimalsIn = listingContract.decimalsB();
        context.decimalsOut = listingContract.decimalsA();
        address pairAddress = listingContract.uniswapV2PairView();
        require(pairAddress != address(0), "Uniswap V2 pair not set");
        require(uniswapV2Router != address(0), "Uniswap V2 router not set");
        context.denormAmountIn = denormalize(amountIn, context.decimalsIn);
        path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        (context.price, context.expectedAmountOut) = _computeSwapImpact(listingAddress, amountIn, true);
        context.denormAmountOutMin = denormalize((amountIn * 1e18) / maxPrice, context.decimalsOut);
        if (context.price < minPrice || context.price > maxPrice || context.expectedAmountOut == 0) {
            context.price = 0; // Signal invalid swap
        }
    }

    function _executeBuyETHSwap(
        BuySwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        // Executes ETH-to-token swap for buy order
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2Router);
        address[] memory path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        uint256 preBalanceOut = context.tokenOut == address(0) ? context.recipientAddress.balance : IERC20(context.tokenOut).balanceOf(context.recipientAddress);
        try context.listingContract.transact{value: context.denormAmountIn}(address(this), address(0), context.denormAmountIn, address(this)) {} catch {
            return new ISSListingTemplate.UpdateType[](0);
        }
        try router.swapExactETHForTokens{value: context.denormAmountIn}(
            context.denormAmountOutMin,
            path,
            context.recipientAddress,
            block.timestamp + 300
        ) returns (uint256[] memory amounts) {
            uint256 amountOut = amounts[1];
            uint256 postBalanceOut = context.tokenOut == address(0) ? context.recipientAddress.balance : IERC20(context.tokenOut).balanceOf(context.recipientAddress);
            uint256 amountReceived = postBalanceOut > preBalanceOut ? postBalanceOut - preBalanceOut : 0;
            if (amountReceived == 0) {
                return new ISSListingTemplate.UpdateType[](0);
            }
            BuyOrderUpdateContext memory updateContext = BuyOrderUpdateContext({
                makerAddress: context.makerAddress,
                recipient: context.recipientAddress,
                status: context.status,
                amountReceived: amountReceived,
                normalizedReceived: normalize(amountReceived, context.decimalsOut),
                amountSent: context.denormAmountIn
            });
            return _createBuyOrderUpdates(orderIdentifier, updateContext, pendingAmount);
        } catch {
            return new ISSListingTemplate.UpdateType[](0);
        }
    }

    function _executeBuyTokenSwap(
        BuySwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        // Executes token-to-token swap for buy order
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2Router);
        address[] memory path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        uint256 preBalanceOut = context.tokenOut == address(0) ? context.recipientAddress.balance : IERC20(context.tokenOut).balanceOf(context.recipientAddress);
        try context.listingContract.transact(address(this), context.tokenIn, context.denormAmountIn, address(this)) {} catch {
            return new ISSListingTemplate.UpdateType[](0);
        }
        IERC20(context.tokenIn).safeApprove(uniswapV2Router, context.denormAmountIn);
        try router.swapExactTokensForTokens(
            context.denormAmountIn,
            context.denormAmountOutMin,
            path,
            context.recipientAddress,
            block.timestamp + 300
        ) returns (uint256[] memory amounts) {
            uint256 amountOut = amounts[1];
            uint256 postBalanceOut = context.tokenOut == address(0) ? context.recipientAddress.balance : IERC20(context.tokenOut).balanceOf(context.recipientAddress);
            uint256 amountReceived = postBalanceOut > preBalanceOut ? postBalanceOut - preBalanceOut : 0;
            if (amountReceived == 0) {
                return new ISSListingTemplate.UpdateType[](0);
            }
            BuyOrderUpdateContext memory updateContext = BuyOrderUpdateContext({
                makerAddress: context.makerAddress,
                recipient: context.recipientAddress,
                status: context.status,
                amountReceived: amountReceived,
                normalizedReceived: normalize(amountReceived, context.decimalsOut),
                amountSent: context.denormAmountIn
            });
            return _createBuyOrderUpdates(orderIdentifier, updateContext, pendingAmount);
        } catch {
            return new ISSListingTemplate.UpdateType[](0);
        }
    }

    function _executePartialBuySwap(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountIn,
        uint256 pendingAmount
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        // Executes partial Uniswap V2 swap for buy order using helper functions
        BuySwapContext memory context;
        address[] memory path;
        (context, path) = _prepareSwapData(listingAddress, orderIdentifier, amountIn);
        if (context.price == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        if (context.tokenIn == address(0)) {
            return _executeBuyETHSwap(context, orderIdentifier, pendingAmount);
        } else {
            return _executeBuyTokenSwap(context, orderIdentifier, pendingAmount);
        }
    }

    function _prepareSellSwapData(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountIn
    ) private view returns (SellSwapContext memory context, address[] memory path) {
        // Prepares swap data for sell order, including order details and swap path
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        (context.recipientAddress, context.makerAddress, context.status) = listingContract.getSellOrderCore(orderIdentifier);
        (uint256 maxPrice, uint256 minPrice) = listingContract.getSellOrderPricing(orderIdentifier);
        context.listingContract = listingContract;
        context.tokenIn = listingContract.tokenA();
        context.tokenOut = listingContract.tokenB();
        context.decimalsIn = listingContract.decimalsA();
        context.decimalsOut = listingContract.decimalsB();
        address pairAddress = listingContract.uniswapV2PairView();
        require(pairAddress != address(0), "Uniswap V2 pair not set");
        require(uniswapV2Router != address(0), "Uniswap V2 router not set");
        context.denormAmountIn = denormalize(amountIn, context.decimalsIn);
        path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        (context.price, context.expectedAmountOut) = _computeSwapImpact(listingAddress, amountIn, false);
        context.denormAmountOutMin = denormalize((amountIn * 1e18) / maxPrice, context.decimalsOut);
        if (context.price < minPrice || context.price > maxPrice || context.expectedAmountOut == 0) {
            context.price = 0; // Signal invalid swap
        }
    }

    function _executeSellETHSwap(
        SellSwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) private returns (ISSListingTemplate.UpdateType[] memory) {
        // Executes token-to-ETH swap for sell order
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2Router);
        address[] memory path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        uint256 preBalanceOut = context.recipientAddress.balance;
        try context.listingContract.transact(address(this), context.tokenIn, context.denormAmountIn, address(this)) {} catch {
            return new ISSListingTemplate.UpdateType[](0);
        }
        IERC20(context.tokenIn).safeApprove(uniswapV2Router, context.denormAmountIn);
        try router.swapExactTokensForETH(
            context.denormAmountIn,
            context.denormAmountOutMin,
            path,
            context.recipientAddress,
            block.timestamp + 300
        ) returns (uint256[] memory amounts) {
            uint256 amountOut = amounts[1];
            uint256 postBalanceOut = context.recipientAddress.balance;
            uint256 amountReceived = postBalanceOut > preBalanceOut ? postBalanceOut - preBalanceOut : 0;
            if (amountReceived == 0) {
                return new ISSListingTemplate.UpdateType[](0);
            }
            SellOrderUpdateContext memory updateContext = SellOrderUpdateContext({
                makerAddress: context.makerAddress,
                recipient: context.recipientAddress,
                status: context.status,
                amountReceived: amountReceived,
                normalizedReceived: normalize(amountReceived, context.decimalsOut),
                amountSent: context.denormAmountIn
            });
            return _createSellOrderUpdates(orderIdentifier, updateContext, pendingAmount);
        } catch {
            return new ISSListingTemplate.UpdateType[](0);
        }
    }

    function _executeSellTokenSwap(
        SellSwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) private returns (ISSListingTemplate.UpdateType[] memory) {
        // Executes token-to-token swap for sell order
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2Router);
        address[] memory path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        uint256 preBalanceOut = IERC20(context.tokenOut).balanceOf(context.recipientAddress);
        try context.listingContract.transact(address(this), context.tokenIn, context.denormAmountIn, address(this)) {} catch {
            return new ISSListingTemplate.UpdateType[](0);
        }
        IERC20(context.tokenIn).safeApprove(uniswapV2Router, context.denormAmountIn);
        try router.swapExactTokensForTokens(
            context.denormAmountIn,
            context.denormAmountOutMin,
            path,
            context.recipientAddress,
            block.timestamp + 300
        ) returns (uint256[] memory amounts) {
            uint256 amountOut = amounts[1];
            uint256 postBalanceOut = IERC20(context.tokenOut).balanceOf(context.recipientAddress);
            uint256 amountReceived = postBalanceOut > preBalanceOut ? postBalanceOut - preBalanceOut : 0;
            if (amountReceived == 0) {
                return new ISSListingTemplate.UpdateType[](0);
            }
            SellOrderUpdateContext memory updateContext = SellOrderUpdateContext({
                makerAddress: context.makerAddress,
                recipient: context.recipientAddress,
                status: context.status,
                amountReceived: amountReceived,
                normalizedReceived: normalize(amountReceived, context.decimalsOut),
                amountSent: context.denormAmountIn
            });
            return _createSellOrderUpdates(orderIdentifier, updateContext, pendingAmount);
        } catch {
            return new ISSListingTemplate.UpdateType[](0);
        }
    }

    function _executePartialSellSwap(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountIn,
        uint256 pendingAmount
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        // Executes partial Uniswap V2 swap for sell order using helper functions
        SellSwapContext memory context;
        address[] memory path;
        (context, path) = _prepareSellSwapData(listingAddress, orderIdentifier, amountIn);
        if (context.price == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        if (context.tokenOut == address(0)) {
            return _executeSellETHSwap(context, orderIdentifier, pendingAmount);
        } else {
            return _executeSellTokenSwap(context, orderIdentifier, pendingAmount);
        }
    }

    function _createBuyOrderUpdates(
        uint256 orderIdentifier,
        BuyOrderUpdateContext memory updateContext,
        uint256 pendingAmount
    ) internal pure returns (ISSListingTemplate.UpdateType[] memory) {
        // Creates update structs for buy order processing
        ISSListingTemplate.UpdateType[] memory updates = new ISSListingTemplate.UpdateType[](2);
        updates[0] = ISSListingTemplate.UpdateType({
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
        updates[1] = ISSListingTemplate.UpdateType({
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
    ) internal pure returns (ISSListingTemplate.UpdateType[] memory) {
        // Creates update structs for sell order processing
        ISSListingTemplate.UpdateType[] memory updates = new ISSListingTemplate.UpdateType[](2);
        updates[0] = ISSListingTemplate.UpdateType({
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
        updates[1] = ISSListingTemplate.UpdateType({
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
}