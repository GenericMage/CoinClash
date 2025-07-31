// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.14
// Changes:
// - v0.0.14: Fixed TypeError in _performETHBuySwap, _performETHSellSwap, and _executeTokenSwap by correcting argument counts for transactToken and transactNative to align with ICCListing.sol v0.0.7 (removed 'depositor' parameter). Ensured try-catch returns decoded error reasons. Compatible with CCMainPartial.sol v0.0.12.
// - v0.0.13: Added amountInReceived to ETHSwapData struct, updated _performETHSellSwap and _finalizeETHSellSwap to use it for tax handling consistency.
// - v0.0.12: Modified _executeTokenSwap and _performETHSellSwap to use amountInReceived after transactToken, even if less than denormAmountIn, to handle transfer taxes gracefully.
// - v0.0.11: Refactored _executeBuyETHSwap and _executeSellETHSwapInternal into single-task helper functions to resolve stack too deep error, using structs for data passing.
// - v0.0.10: Renamed _executeSellETHSwap to _executeSellETHSwapInternal, updated to use SwapContext, fixed undeclared identifier error in _executePartialSellSwap.
// - v0.0.9: Introduced generic SwapContext struct and refactored _executeTokenSwap to use it, resolving TypeError from passing SellSwapContext to BuySwapContext.
// - v0.0.8: Refactored _executeBuyTokenSwap and _executeSellTokenSwap to use internal call tree with helper functions to resolve stack too deep error.
// - v0.0.7: Removed SafeERC20 usage, rely on IERC20 from CCMainPartial.sol, removed safeApprove, used direct approve, added pre/post balance checks for transactToken.
// - v0.0.6: Removed inlined ICCListing, imported from CCMainPartial.sol to avoid duplication.
// - v0.0.5: Marked transactNative as payable in inlined ICCListing (reverted).
// - v0.0.4: Replaced ISSListingTemplate with ICCListing, updated transact to transactNative/transactToken.
// - v0.0.3: Refactored _computeSwapImpact to use SwapImpactContext struct.
// - v0.0.2: Refactored _executePartialSellSwap to use SellSwapContext struct.
// Compatible with CCMainPartial.sol (v0.0.12), CCSettlementPartial.sol (v0.0.19), CCSettlementRouter.sol (v0.0.6).

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

    function _computeCurrentPrice(address listingAddress) internal view returns (uint256 price) {
        // Computes current price from Uniswap V2 pair reserves
        ICCListing listingContract = ICCListing(listingAddress);
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
        ICCListing listingContract = ICCListing(listingAddress);
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
        ICCListing listingContract = ICCListing(listingAddress);
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
    ) internal view returns (SwapContext memory context, address[] memory path) {
        // Prepares swap data for buy order, including order details and swap path
        ICCListing listingContract = ICCListing(listingAddress);
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

    function _prepareSellSwapData(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountIn
    ) private view returns (SwapContext memory context, address[] memory path) {
        // Prepares swap data for sell order, including order details and swap path
        ICCListing listingContract = ICCListing(listingAddress);
        (context.makerAddress, context.recipientAddress, context.status) = listingContract.getSellOrderCore(orderIdentifier);
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

    function _prepareETHSwap(
        address tokenOut,
        address recipientAddress
    ) private view returns (ETHSwapData memory data) {
        // Prepares balance checks for ETH swap
        data.preBalanceOut = tokenOut == address(0) ? recipientAddress.balance : IERC20(tokenOut).balanceOf(recipientAddress);
    }

    function _performETHBuySwap(
        SwapContext memory context,
        address[] memory path
    ) private returns (ETHSwapData memory data) {
        // Performs ETH-to-token swap
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2Router);
        try context.listingContract.transactNative{value: context.denormAmountIn}(context.denormAmountIn, address(this)) {
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Native transfer failed: ", reason)));
        }
        try router.swapExactETHForTokens{value: context.denormAmountIn}(
            context.denormAmountOutMin,
            path,
            context.recipientAddress,
            block.timestamp + 300
        ) returns (uint256[] memory amounts) {
            data.amountOut = amounts[1];
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        }
        data.postBalanceOut = context.tokenOut == address(0) ? context.recipientAddress.balance : IERC20(context.tokenOut).balanceOf(context.recipientAddress);
        data.amountReceived = data.postBalanceOut > data.preBalanceOut ? data.postBalanceOut - data.preBalanceOut : 0;
    }

    function _finalizeETHBuySwap(
        ETHSwapData memory data,
        SwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) private pure returns (ICCListing.UpdateType[] memory) {
        // Finalizes ETH buy swap and creates update structs
        if (data.amountReceived == 0) {
            return new ICCListing.UpdateType[](0);
        }
        BuyOrderUpdateContext memory updateContext = BuyOrderUpdateContext({
            makerAddress: context.makerAddress,
            recipient: context.recipientAddress,
            status: context.status,
            amountReceived: data.amountReceived,
            normalizedReceived: normalize(data.amountReceived, context.decimalsOut),
            amountSent: context.denormAmountIn
        });
        return _createBuyOrderUpdates(orderIdentifier, updateContext, pendingAmount);
    }

    function _executeBuyETHSwap(
        SwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Executes ETH-to-token swap for buy order using helper functions
        address[] memory path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        ETHSwapData memory data = _prepareETHSwap(context.tokenOut, context.recipientAddress);
        data = _performETHBuySwap(context, path);
        return _finalizeETHBuySwap(data, context, orderIdentifier, pendingAmount);
    }

    function _performETHSellSwap(
        SwapContext memory context,
        address[] memory path
    ) private returns (ETHSwapData memory data) {
        // Performs token-to-ETH swap, using actual amount received after tax
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2Router);
        data.preBalanceIn = IERC20(context.tokenIn).balanceOf(address(this));
        data.preBalanceOut = context.recipientAddress.balance;
        try context.listingContract.transactToken(context.tokenIn, context.denormAmountIn, address(this)) {
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Token transfer failed: ", reason)));
        }
        data.postBalanceIn = IERC20(context.tokenIn).balanceOf(address(this));
        data.amountInReceived = data.postBalanceIn > data.preBalanceIn ? data.postBalanceIn - data.preBalanceIn : 0;
        if (data.amountInReceived == 0) {
            return data;
        }
        IERC20(context.tokenIn).approve(uniswapV2Router, data.amountInReceived);
        try router.swapExactTokensForETH(
            data.amountInReceived,
            context.denormAmountOutMin,
            path,
            context.recipientAddress,
            block.timestamp + 300
        ) returns (uint256[] memory amounts) {
            data.amountOut = amounts[1];
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        }
        data.postBalanceOut = context.recipientAddress.balance;
        data.amountReceived = data.postBalanceOut > data.preBalanceOut ? data.postBalanceOut - data.preBalanceOut : 0;
    }

    function _finalizeETHSellSwap(
        ETHSwapData memory data,
        SwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) private pure returns (ICCListing.UpdateType[] memory) {
        // Finalizes ETH sell swap and creates update structs
        if (data.amountReceived == 0 || data.amountInReceived == 0) {
            return new ICCListing.UpdateType[](0);
        }
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

    function _executeSellETHSwapInternal(
        SwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) private returns (ICCListing.UpdateType[] memory) {
        // Executes token-to-ETH swap for sell order using helper functions
        address[] memory path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        ETHSwapData memory data = _prepareETHSwap(context.tokenOut, context.recipientAddress);
        data = _performETHSellSwap(context, path);
        return _finalizeETHSellSwap(data, context, orderIdentifier, pendingAmount);
    }

    function _prepareTokenSwap(
        address tokenIn,
        address tokenOut,
        address recipientAddress
    ) private view returns (TokenSwapData memory data) {
        // Prepares balance checks for token swap
        data.preBalanceIn = IERC20(tokenIn).balanceOf(address(this));
        data.preBalanceOut = IERC20(tokenOut).balanceOf(recipientAddress);
    }

    function _executeTokenSwap(
        SwapContext memory context,
        address[] memory path
    ) private returns (TokenSwapData memory data) {
        // Executes token transfer and swap, using actual amount received after tax
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2Router);
        data.preBalanceIn = IERC20(context.tokenIn).balanceOf(address(this));
        try context.listingContract.transactToken(context.tokenIn, context.denormAmountIn, address(this)) {
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Token transfer failed: ", reason)));
        }
        data.postBalanceIn = IERC20(context.tokenIn).balanceOf(address(this));
        data.amountInReceived = data.postBalanceIn > data.preBalanceIn ? data.postBalanceIn - data.preBalanceIn : 0;
        if (data.amountInReceived == 0) {
            return data;
        }
        IERC20(context.tokenIn).approve(uniswapV2Router, data.amountInReceived);
        try router.swapExactTokensForTokens(
            data.amountInReceived,
            context.denormAmountOutMin,
            path,
            context.recipientAddress,
            block.timestamp + 300
        ) returns (uint256[] memory amounts) {
            data.amountOut = amounts[1];
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        }
        data.postBalanceOut = IERC20(context.tokenOut).balanceOf(context.recipientAddress);
        data.amountReceived = data.postBalanceOut > data.preBalanceOut ? data.postBalanceOut - data.preBalanceOut : 0;
    }

    function _finalizeTokenSwap(
        TokenSwapData memory data,
        SwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) private pure returns (ICCListing.UpdateType[] memory) {
        // Finalizes token swap and creates update structs for buy order
        if (data.amountReceived == 0 || data.amountInReceived == 0) {
            return new ICCListing.UpdateType[](0);
        }
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
    ) private pure returns (ICCListing.UpdateType[] memory) {
        // Finalizes token swap and creates update structs for sell order
        if (data.amountReceived == 0 || data.amountInReceived == 0) {
            return new ICCListing.UpdateType[](0);
        }
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
    ) private returns (ICCListing.UpdateType[] memory) {
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