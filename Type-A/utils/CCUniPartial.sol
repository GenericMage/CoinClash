// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.18
// Changes:
// - v0.0.18: Updated _computeCurrentPrice to use reserveB / reserveA to align with flipped price calculation in CCListingTemplate. Adjusted _computeSwapImpact to use (normalizedReserveIn + amountInAfterFee) / (normalizedReserveOut - amountOut) for buy orders and inverse for sell orders. Compatible with CCSettlementPartial.sol v0.0.21, CCSettlementRouter.sol v0.0.8, CCMainPartial.sol v0.0.14.
// - v0.0.17: Fixed DeclarationError in _performETHBuySwap at line 372 by correcting `preBalanceOut` to `data.preBalanceOut`.
// - v0.0.16: Refactored _computeMaxAmountIn to resolve stack-too-deep error.
// - v0.0.15: Fixed _computeSwapImpact to calculate impactPrice correctly.
// - v0.0.14: Fixed TypeError in swap functions.
// - v0.0.13: Added amountInReceived to ETHSwapData struct.
// - v0.0.12: Modified _executeTokenSwap to use amountInReceived.
// - v0.0.11: Refactored _executeBuyETHSwap to resolve stack too deep.
// - v0.0.10: Renamed _executeSellETHSwap to _executeSellETHSwapInternal.
// - v0.0.9: Introduced SwapContext struct.
// - v0.0.8: Refactored _executeBuyTokenSwap to use internal call tree.
// - v0.0.7: Removed SafeERC20, added pre/post balance checks.
// - v0.0.6: Removed inlined ICCListing.
// - v0.0.5: Marked transactNative as payable (reverted).
// - v0.0.4: Replaced ISSListingTemplate with ICCListing.
// - v0.0.3: Refactored _computeSwapImpact to use SwapImpactContext.
// - v0.0.2: Refactored _executePartialSellSwap to use SellSwapContext.
// Compatible with CCMainPartial.sol (v0.0.14), CCSettlementPartial.sol (v0.0.21), CCSettlementRouter.sol (v0.0.8).

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
    struct MaxAmountInContext {
        uint256 reserveIn;
        uint8 decimalsIn;
        uint256 normalizedReserveIn;
        uint256 currentPrice;
    }

    struct SwapContext {
        ICCListing listingContract;
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

    struct TokenSwapData {
        uint256 preBalanceIn;
        uint256 postBalanceIn;
        uint256 amountInReceived;
        uint256 preBalanceOut;
        uint256 postBalanceOut;
        uint256 amountReceived;
        uint256 amountOut;
    }

    struct ETHSwapData {
        uint256 preBalanceIn;
        uint256 postBalanceIn;
        uint256 amountInReceived;
        uint256 preBalanceOut;
        uint256 postBalanceOut;
        uint256 amountReceived;
        uint256 amountOut;
    }

    struct ReserveContext {
        uint256 reserveIn;
        uint8 decimalsIn;
        uint256 normalizedReserveIn;
        address tokenA;
    }

    struct ImpactContext {
        uint256 currentPrice;
        uint256 maxImpactPercent;
        uint256 maxAmountIn;
        uint256 pendingAmount;
    }

    function _computeCurrentPrice(address listingAddress) internal view returns (uint256 price) {
        // Computes current price as reserveB / reserveA to align with flipped CCListingTemplate price
        ICCListing listingContract = ICCListing(listingAddress);
        address pairAddress = listingContract.uniswapV2PairView();
        require(pairAddress != address(0), "Uniswap V2 pair not set");
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        address token0 = pair.token0();
        address tokenA = listingContract.tokenA();
        uint8 decimalsA = listingContract.decimalsA();
        uint8 decimalsB = listingContract.decimalsB();
        uint256 reserveA = tokenA == token0 ? reserve0 : reserve1;
        uint256 reserveB = tokenA == token0 ? reserve1 : reserve0;
        uint256 normalizedReserveA = normalize(reserveA, decimalsA);
        uint256 normalizedReserveB = normalize(reserveB, decimalsB);
        require(normalizedReserveA > 0, "Zero reserveA");
        price = (normalizedReserveB * 1e18) / normalizedReserveA;
    }

    function _computeSwapImpact(
        address listingAddress,
        uint256 amountIn,
        bool isBuyOrder
    ) internal view returns (uint256 price, uint256 amountOut) {
        // Computes swap impact price and output amount, adjusted for flipped price (reserveB / reserveA)
        ICCListing listingContract = ICCListing(listingAddress);
        address pairAddress = listingContract.uniswapV2PairView();
        require(pairAddress != address(0), "Uniswap V2 pair not set");
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        address token0 = pair.token0();
        address tokenA = listingContract.tokenA();
        uint8 decimalsA = listingContract.decimalsA();
        uint8 decimalsB = listingContract.decimalsB();
        SwapImpactContext memory context;
        context.decimalsIn = isBuyOrder ? decimalsB : decimalsA;
        context.decimalsOut = isBuyOrder ? decimalsA : decimalsB;
        context.reserveIn = isBuyOrder ? (tokenA == token0 ? reserve1 : reserve0) : (tokenA == token0 ? reserve0 : reserve1);
        context.reserveOut = isBuyOrder ? (tokenA == token0 ? reserve0 : reserve1) : (tokenA == token0 ? reserve1 : reserve0);
        context.normalizedReserveIn = normalize(context.reserveIn, context.decimalsIn);
        context.normalizedReserveOut = normalize(context.reserveOut, context.decimalsOut);
        context.amountInAfterFee = (amountIn * 997) / 1000;
        context.amountOut = (context.amountInAfterFee * context.normalizedReserveOut) / (context.normalizedReserveIn + context.amountInAfterFee);
        context.price = context.normalizedReserveOut > context.amountOut
            ? ((context.normalizedReserveIn + context.amountInAfterFee) * 1e18) / (context.normalizedReserveOut - context.amountOut)
            : 0;
        price = context.price;
        amountOut = context.amountOut;
    }

    function _fetchReserves(
        address listingAddress,
        bool isBuyOrder
    ) internal view returns (ReserveContext memory reserveContext) {
        // Fetches reserves and token details for max amount calculation
        ICCListing listingContract = ICCListing(listingAddress);
        address pairAddress = listingContract.uniswapV2PairView();
        require(pairAddress != address(0), "Uniswap V2 pair not set");
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        address token0 = pair.token0();
        reserveContext.tokenA = listingContract.tokenA();
        reserveContext.decimalsIn = isBuyOrder ? listingContract.decimalsB() : listingContract.decimalsA();
        reserveContext.reserveIn = isBuyOrder ? (reserveContext.tokenA == token0 ? reserve1 : reserve0) : (reserveContext.tokenA == token0 ? reserve0 : reserve1);
        reserveContext.normalizedReserveIn = normalize(reserveContext.reserveIn, reserveContext.decimalsIn);
    }

    function _computeImpactPercent(
        uint256 maxPrice,
        uint256 minPrice,
        uint256 currentPrice,
        bool isBuyOrder
    ) internal pure returns (uint256 maxImpactPercent) {
        // Computes max impact percent based on price constraints
        maxImpactPercent = isBuyOrder
            ? (maxPrice * 100e18 / currentPrice - 100e18) / 1e18
            : (currentPrice * 100e18 / minPrice - 100e18) / 1e18;
    }

    function _computeMaxAmount(
        ReserveContext memory reserveContext,
        uint256 maxImpactPercent,
        uint256 pendingAmount
    ) internal pure returns (uint256 maxAmountIn) {
        // Computes max input amount based on reserves and impact percent
        maxAmountIn = (reserveContext.normalizedReserveIn * maxImpactPercent) / (100 * 2);
        maxAmountIn = maxAmountIn >= pendingAmount ? pendingAmount : maxAmountIn;
    }

    function _computeMaxAmountIn(
        address listingAddress,
        uint256 maxPrice,
        uint256 minPrice,
        uint256 pendingAmount,
        bool isBuyOrder
    ) internal view returns (uint256 maxAmountIn) {
        // Computes maximum input amount based on price constraints
        ReserveContext memory reserveContext = _fetchReserves(listingAddress, isBuyOrder);
        ImpactContext memory impactContext;
        impactContext.currentPrice = _computeCurrentPrice(listingAddress);
        impactContext.maxImpactPercent = _computeImpactPercent(maxPrice, minPrice, impactContext.currentPrice, isBuyOrder);
        impactContext.pendingAmount = pendingAmount;
        maxAmountIn = _computeMaxAmount(reserveContext, impactContext.maxImpactPercent, impactContext.pendingAmount);
    }

    function _prepareSwapData(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountIn
    ) internal view returns (SwapContext memory context, address[] memory path) {
        // Prepares swap data for buy order
        ICCListing listingContract = ICCListing(listingAddress);
        context.listingContract = listingContract;
        (context.makerAddress, context.recipientAddress, context.status) = listingContract.getBuyOrderCore(orderIdentifier);
        (uint256 maxPrice, uint256 minPrice) = listingContract.getBuyOrderPricing(orderIdentifier);
        context.tokenIn = listingContract.tokenB();
        context.tokenOut = listingContract.tokenA();
        context.decimalsIn = listingContract.decimalsB();
        context.decimalsOut = listingContract.decimalsA();
        context.denormAmountIn = denormalize(amountIn, context.decimalsIn);
        (context.price, context.expectedAmountOut) = _computeSwapImpact(listingAddress, amountIn, true);
        context.denormAmountOutMin = (context.expectedAmountOut * 1e18) / maxPrice;
        context.denormAmountOutMin = denormalize(context.denormAmountOutMin, context.decimalsOut);
        path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
    }

    function _prepareSellSwapData(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountIn
    ) internal view returns (SwapContext memory context, address[] memory path) {
        // Prepares swap data for sell order
        ICCListing listingContract = ICCListing(listingAddress);
        context.listingContract = listingContract;
        (context.makerAddress, context.recipientAddress, context.status) = listingContract.getSellOrderCore(orderIdentifier);
        (uint256 maxPrice, uint256 minPrice) = listingContract.getSellOrderPricing(orderIdentifier);
        context.tokenIn = listingContract.tokenA();
        context.tokenOut = listingContract.tokenB();
        context.decimalsIn = listingContract.decimalsA();
        context.decimalsOut = listingContract.decimalsB();
        context.denormAmountIn = denormalize(amountIn, context.decimalsIn);
        (context.price, context.expectedAmountOut) = _computeSwapImpact(listingAddress, amountIn, false);
        context.denormAmountOutMin = (context.expectedAmountOut * minPrice) / 1e18;
        context.denormAmountOutMin = denormalize(context.denormAmountOutMin, context.decimalsOut);
        path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
    }

    function _prepareTokenSwap(
        address tokenIn,
        address tokenOut,
        address recipientAddress
    ) internal view returns (TokenSwapData memory data) {
        // Prepares token swap data with pre-balance checks
        data = TokenSwapData({
            preBalanceIn: IERC20(tokenIn).balanceOf(address(this)),
            postBalanceIn: 0,
            amountInReceived: 0,
            preBalanceOut: tokenOut == address(0) ? recipientAddress.balance : IERC20(tokenOut).balanceOf(recipientAddress),
            postBalanceOut: 0,
            amountReceived: 0,
            amountOut: 0
        });
    }

    function _executeTokenSwap(
        SwapContext memory context,
        address[] memory path
    ) internal returns (TokenSwapData memory data) {
        // Executes token-to-token swap with pre/post balance checks
        data = _prepareTokenSwap(context.tokenIn, context.tokenOut, context.recipientAddress);
        try context.listingContract.transactToken(context.tokenIn, context.denormAmountIn, address(this)) {
            data.postBalanceIn = IERC20(context.tokenIn).balanceOf(address(this));
            data.amountInReceived = data.postBalanceIn > data.preBalanceIn ? data.postBalanceIn - data.preBalanceIn : 0;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Token transfer failed: ", reason)));
        }
        require(data.amountInReceived > 0, "No tokens received");
        try IERC20(context.tokenIn).approve(uniswapV2Router, data.amountInReceived) {
            // Approval succeeded
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Token approval failed: ", reason)));
        }
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2Router);
        try router.swapExactTokensForTokens(
            data.amountInReceived,
            context.denormAmountOutMin,
            path,
            context.recipientAddress,
            block.timestamp + 300
        ) returns (uint256[] memory amounts) {
            data.amountOut = amounts[amounts.length - 1];
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        }
        data.postBalanceOut = context.tokenOut == address(0)
            ? context.recipientAddress.balance
            : IERC20(context.tokenOut).balanceOf(context.recipientAddress);
        data.amountReceived = data.postBalanceOut > data.preBalanceOut ? data.postBalanceOut - data.preBalanceOut : 0;
    }

    function _performETHBuySwap(
        SwapContext memory context,
        address[] memory path
    ) internal returns (ETHSwapData memory data) {
        // Executes ETH-to-token swap
        data = ETHSwapData({
            preBalanceIn: address(this).balance,
            postBalanceIn: 0,
            amountInReceived: 0,
            preBalanceOut: IERC20(context.tokenOut).balanceOf(context.recipientAddress),
            postBalanceOut: 0,
            amountReceived: 0,
            amountOut: 0
        });
        try context.listingContract.transactNative{value: context.denormAmountIn}(context.denormAmountIn, address(this)) {
            data.postBalanceIn = address(this).balance;
            data.amountInReceived = data.postBalanceIn > data.preBalanceIn ? data.postBalanceIn - data.preBalanceIn : 0;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Native transfer failed: ", reason)));
        }
        require(data.amountInReceived > 0, "No ETH received");
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2Router);
        try router.swapExactETHForTokens{value: data.amountInReceived}(
            context.denormAmountOutMin,
            path,
            context.recipientAddress,
            block.timestamp + 300
        ) returns (uint256[] memory amounts) {
            data.amountOut = amounts[amounts.length - 1];
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        }
        data.postBalanceOut = IERC20(context.tokenOut).balanceOf(context.recipientAddress);
        data.amountReceived = data.postBalanceOut > data.preBalanceOut ? data.postBalanceOut - data.preBalanceOut : 0;
    }

    function _performETHSellSwap(
        SwapContext memory context,
        address[] memory path
    ) internal returns (ETHSwapData memory data) {
        // Executes token-to-ETH swap
        data = ETHSwapData({
            preBalanceIn: IERC20(context.tokenIn).balanceOf(address(this)),
            postBalanceIn: 0,
            amountInReceived: 0,
            preBalanceOut: context.recipientAddress.balance,
            postBalanceOut: 0,
            amountReceived: 0,
            amountOut: 0
        });
        try context.listingContract.transactToken(context.tokenIn, context.denormAmountIn, address(this)) {
            data.postBalanceIn = IERC20(context.tokenIn).balanceOf(address(this));
            data.amountInReceived = data.postBalanceIn > data.preBalanceIn ? data.postBalanceIn - data.preBalanceIn : 0;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Token transfer failed: ", reason)));
        }
        require(data.amountInReceived > 0, "No tokens received");
        try IERC20(context.tokenIn).approve(uniswapV2Router, data.amountInReceived) {
            // Approval succeeded
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Token approval failed: ", reason)));
        }
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2Router);
        try router.swapExactTokensForETH(
            data.amountInReceived,
            context.denormAmountOutMin,
            path,
            context.recipientAddress,
            block.timestamp + 300
        ) returns (uint256[] memory amounts) {
            data.amountOut = amounts[amounts.length - 1];
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        }
        data.postBalanceOut = context.recipientAddress.balance;
        data.amountReceived = data.postBalanceOut > data.preBalanceOut ? data.postBalanceOut - data.preBalanceOut : 0;
    }

    function _finalizeTokenSwap(
        TokenSwapData memory data,
        SwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Finalizes token swap and creates updates
        require(data.amountReceived > 0, "No tokens received in swap");
        BuyOrderUpdateContext memory updateContext = BuyOrderUpdateContext({
            makerAddress: context.makerAddress,
            recipient: context.recipientAddress,
            status: context.status,
            amountReceived: data.amountReceived,
            normalizedReceived: normalize(data.amountReceived, context.decimalsOut),
            amountSent: data.amountInReceived
        });
        return _createBuyOrderUpdates(orderIdentifier, updateContext, pendingAmount);
    }

    function _finalizeSellTokenSwap(
        TokenSwapData memory data,
        SwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Finalizes token swap for sell order
        require(data.amountReceived > 0, "No tokens received in swap");
        SellOrderUpdateContext memory updateContext = SellOrderUpdateContext({
            makerAddress: context.makerAddress,
            recipient: context.recipientAddress,
            status: context.status,
            amountReceived: data.amountReceived,
            normalizedReceived: normalize(data.amountReceived, context.decimalsOut),
            amountSent: data.amountInReceived
        });
        return _createSellOrderUpdates(orderIdentifier, updateContext, pendingAmount);
    }

    function _executeBuyETHSwap(
        SwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Executes ETH-to-token swap for buy order
        address[] memory path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        ETHSwapData memory data = _performETHBuySwap(context, path);
        require(data.amountReceived > 0, "No tokens received in swap");
        BuyOrderUpdateContext memory updateContext = BuyOrderUpdateContext({
            makerAddress: context.makerAddress,
            recipient: context.recipientAddress,
            status: context.status,
            amountReceived: data.amountReceived,
            normalizedReceived: normalize(data.amountReceived, context.decimalsOut),
            amountSent: data.amountInReceived
        });
        return _createBuyOrderUpdates(orderIdentifier, updateContext, pendingAmount);
    }

    function _executeSellETHSwapInternal(
        SwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Executes token-to-ETH swap for sell order
        address[] memory path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        ETHSwapData memory data = _performETHSellSwap(context, path);
        require(data.amountReceived > 0, "No ETH received in swap");
        SellOrderUpdateContext memory updateContext = SellOrderUpdateContext({
            makerAddress: context.makerAddress,
            recipient: context.recipientAddress,
            status: context.status,
            amountReceived: data.amountReceived,
            normalizedReceived: normalize(data.amountReceived, context.decimalsOut),
            amountSent: data.amountInReceived
        });
        return _createSellOrderUpdates(orderIdentifier, updateContext, pendingAmount);
    }

    function _executeBuyTokenSwap(
        SwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Executes token-to-token swap for buy order using helper functions
        address[] memory path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        TokenSwapData memory data = _prepareTokenSwap(context.tokenIn, context.tokenOut, context.recipientAddress);
        data = _executeTokenSwap(context, path);
        return _finalizeTokenSwap(data, context, orderIdentifier, pendingAmount);
    }

    function _executeSellTokenSwap(
        SwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Executes token-to-token swap for sell order using helper functions
        address[] memory path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        TokenSwapData memory data = _prepareTokenSwap(context.tokenIn, context.tokenOut, context.recipientAddress);
        data = _executeTokenSwap(context, path);
        return _finalizeSellTokenSwap(data, context, orderIdentifier, pendingAmount);
    }

    function _executePartialBuySwap(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountIn,
        uint256 pendingAmount
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Executes partial Uniswap V2 swap for buy order using helper functions
        SwapContext memory context;
        address[] memory path;
        (context, path) = _prepareSwapData(listingAddress, orderIdentifier, amountIn);
        if (context.price == 0) {
            return new ICCListing.UpdateType[](0);
        }
        if (context.tokenIn == address(0)) {
            return _executeBuyETHSwap(context, orderIdentifier, pendingAmount);
        } else {
            return _executeBuyTokenSwap(context, orderIdentifier, pendingAmount);
        }
    }

    function _executePartialSellSwap(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountIn,
        uint256 pendingAmount
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Executes partial Uniswap V2 swap for sell order using helper functions
        SwapContext memory context;
        address[] memory path;
        (context, path) = _prepareSellSwapData(listingAddress, orderIdentifier, amountIn);
        if (context.price == 0) {
            return new ICCListing.UpdateType[](0);
        }
        if (context.tokenOut == address(0)) {
            return _executeSellETHSwapInternal(context, orderIdentifier, pendingAmount);
        } else {
            return _executeSellTokenSwap(context, orderIdentifier, pendingAmount);
        }
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
}