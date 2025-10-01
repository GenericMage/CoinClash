// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.27 (01/10/2025)
// Changes:
// - v0.1.27 (01/10): Commented out unused `amounts` variable in try/catch blocks for swap calls in _performETHBuySwap, _performETHSellSwap, and _executeTokenSwap to silence warnings while preserving error handling.
// - v0.1.26 (01/10): Simplified PrepOrderUpdateResult struct by removing normalizedReceived and amountIn. Merged _createBuyOrderUpdates and _createSellOrderUpdates into a single _createOrderUpdates function to reduce code duplication. Reduced _executeBuyTokenSwap and _executeSellTokenSwap by inlining prepResult handling. Removed redundant status checks in _prepareSwapData and _prepareSellSwapData to reduce gas and code size.
// - v0.1.25 (01/10): Changed _prepareSwapData and _prepareSellSwapData to view mutability, removed unused listingAddress in _getTokenAndDecimals and _computeSwapImpact, removed unused filled variable in _prepBuyOrderUpdate and _prepSellOrderUpdate, updated calls to use fewer arguments.
// - v0.1.24 (01/10): Fixed _computeMaxAmountIn to cap maxAmountIn to pendingAmount after fee adjustment. Enhanced _executeSellTokenSwap to use amountInReceived, added detailed error messages.
// - v0.1.23: Fixed _createBuyOrderUpdates and _createSellOrderUpdates to accumulate amountSent (29/09).
// - v0.1.22: Removed denormalization in _prepBuyOrderUpdate/_prepSellOrderUpdate, updated amountSent to use pre/post balance checks (29/9).

import "./CCMainPartial.sol";

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external returns (uint256[] memory amounts);
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external payable returns (uint256[] memory amounts);
    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external returns (uint256[] memory amounts);
}

contract CCUniPartial is CCMainPartial {
    struct PrepOrderUpdateResult {
        address tokenAddress;
        uint8 tokenDecimals;
        address makerAddress;
        address recipientAddress;
        uint8 orderStatus;
        uint256 amountSent;
    }

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

    struct OrderUpdateContext {
        address makerAddress;
        address recipient;
        uint8 status;
        uint256 amountSent;
        uint256 amountIn;
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

    struct SettlementContext {
        address tokenA;
        address tokenB;
        uint8 decimalsA;
        uint8 decimalsB;
        address uniswapV2Pair;
    }

    struct OrderContext {
        uint256 orderId;
        uint256 pending;
        uint8 status;
        ICCListing.BuyOrderUpdate[] buyUpdates;
        ICCListing.SellOrderUpdate[] sellUpdates;
    }
    
    event OrderSkipped(uint256 orderId, string reason);

    function _getTokenAndDecimals(bool isBuyOrder, SettlementContext memory settlementContext) internal pure returns (address tokenAddress, uint8 tokenDecimals) {
        tokenAddress = isBuyOrder ? settlementContext.tokenB : settlementContext.tokenA;
        tokenDecimals = isBuyOrder ? settlementContext.decimalsB : settlementContext.decimalsA;
        if (tokenAddress == address(0) && !isBuyOrder) revert("Invalid token address for sell order");
        if (tokenDecimals == 0) revert("Invalid token decimals");
    }

    function _prepBuyOrderUpdate(address listingAddress, uint256 orderIdentifier, uint256 amountReceived, SettlementContext memory settlementContext) internal returns (PrepOrderUpdateResult memory result) {
        ICCListing listingContract = ICCListing(listingAddress);
        (uint256 pending,,) = listingContract.getBuyOrderAmounts(orderIdentifier);
        if (pending == 0) revert(string(abi.encodePacked("No pending amount for buy order ", uint2str(orderIdentifier))));
        (result.tokenAddress, result.tokenDecimals) = _getTokenAndDecimals(true, settlementContext);
        (result.makerAddress, result.recipientAddress, result.orderStatus) = listingContract.getBuyOrderCore(orderIdentifier);
        if (result.orderStatus != 1) revert(string(abi.encodePacked("Invalid status for buy order ", uint2str(orderIdentifier), ": ", uint2str(result.orderStatus))));
        uint256 preBalance = result.tokenAddress == address(0) ? address(this).balance : IERC20(result.tokenAddress).balanceOf(address(this));
        if (result.tokenAddress == address(0)) {
            try listingContract.transactNative{value: amountReceived}(amountReceived, address(this)) {
                result.amountSent = address(this).balance - preBalance;
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("Native transfer failed for buy order ", uint2str(orderIdentifier), ": ", reason)));
            }
        } else {
            try listingContract.transactToken(result.tokenAddress, amountReceived, address(this)) {
                result.amountSent = IERC20(result.tokenAddress).balanceOf(address(this)) - preBalance;
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("Token transfer failed for buy order ", uint2str(orderIdentifier), ": ", reason)));
            }
        }
        if (result.amountSent == 0) revert(string(abi.encodePacked("No tokens received for buy order ", uint2str(orderIdentifier))));
    }

    function _prepSellOrderUpdate(address listingAddress, uint256 orderIdentifier, uint256 amountReceived, SettlementContext memory settlementContext) internal returns (PrepOrderUpdateResult memory result) {
        ICCListing listingContract = ICCListing(listingAddress);
        (uint256 pending,,) = listingContract.getSellOrderAmounts(orderIdentifier);
        if (pending == 0) revert(string(abi.encodePacked("No pending amount for sell order ", uint2str(orderIdentifier))));
        (result.tokenAddress, result.tokenDecimals) = _getTokenAndDecimals(false, settlementContext);
        (result.makerAddress, result.recipientAddress, result.orderStatus) = listingContract.getSellOrderCore(orderIdentifier);
        if (result.orderStatus != 1) revert(string(abi.encodePacked("Invalid status for sell order ", uint2str(orderIdentifier), ": ", uint2str(result.orderStatus))));
        uint256 preBalance = result.tokenAddress == address(0) ? address(this).balance : IERC20(result.tokenAddress).balanceOf(address(this));
        if (result.tokenAddress == address(0)) {
            try listingContract.transactNative{value: amountReceived}(amountReceived, address(this)) {
                result.amountSent = address(this).balance - preBalance;
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("Native transfer failed for sell order ", uint2str(orderIdentifier), ": ", reason)));
            }
        } else {
            try listingContract.transactToken(result.tokenAddress, amountReceived, address(this)) {
                result.amountSent = IERC20(result.tokenAddress).balanceOf(address(this)) - preBalance;
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("Token transfer failed for sell order ", uint2str(orderIdentifier), ": ", reason)));
            }
        }
        if (result.amountSent == 0) revert(string(abi.encodePacked("No tokens received for sell order ", uint2str(orderIdentifier))));
    }

    function _computeCurrentPrice(address listingAddress) internal view returns (uint256 price) {
        ICCListing listingContract = ICCListing(listingAddress);
        price = listingContract.prices(0);
        if (price == 0) revert("Invalid price from listing");
    }

    function _computeSwapImpact(uint256 amountIn, bool isBuyOrder, SettlementContext memory settlementContext) internal view returns (uint256 price, uint256 amountOut) {
        SwapImpactContext memory context;
        context.decimalsIn = isBuyOrder ? settlementContext.decimalsB : settlementContext.decimalsA;
        context.decimalsOut = isBuyOrder ? settlementContext.decimalsA : settlementContext.decimalsB;
        context.reserveIn = IERC20(isBuyOrder ? settlementContext.tokenB : settlementContext.tokenA).balanceOf(settlementContext.uniswapV2Pair);
        context.reserveOut = IERC20(isBuyOrder ? settlementContext.tokenA : settlementContext.tokenB).balanceOf(settlementContext.uniswapV2Pair);
        if (context.reserveIn == 0 || context.reserveOut == 0) revert("Zero reserves in Uniswap pair");
        context.normalizedReserveIn = normalize(context.reserveIn, context.decimalsIn);
        context.normalizedReserveOut = normalize(context.reserveOut, context.decimalsOut);
        context.amountInAfterFee = (normalize(amountIn, context.decimalsIn) * 997) / 1000;
        context.amountOut = (context.amountInAfterFee * context.normalizedReserveOut) / (context.normalizedReserveIn + context.amountInAfterFee);
        context.price = ICCListing(settlementContext.uniswapV2Pair).prices(0);
        if (context.price == 0) revert("Invalid listing price");
        price = context.price;
        amountOut = denormalize(context.amountOut, context.decimalsOut);
    }

    function _fetchReserves(bool isBuyOrder, SettlementContext memory settlementContext) internal view returns (ReserveContext memory reserveContext) {
        if (settlementContext.uniswapV2Pair == address(0)) revert("Uniswap V2 pair not set");
        reserveContext.tokenA = settlementContext.tokenA;
        reserveContext.decimalsIn = isBuyOrder ? settlementContext.decimalsB : settlementContext.decimalsA;
        address tokenIn = isBuyOrder ? settlementContext.tokenB : settlementContext.tokenA;
        reserveContext.reserveIn = IERC20(tokenIn).balanceOf(settlementContext.uniswapV2Pair);
        if (reserveContext.reserveIn == 0) revert("Zero input token reserve");
        reserveContext.normalizedReserveIn = normalize(reserveContext.reserveIn, reserveContext.decimalsIn);
    }

    function _prepareSwapData(address listingAddress, uint256 orderIdentifier, uint256 amountIn, SettlementContext memory settlementContext) internal view returns (SwapContext memory context, address[] memory path) {
        ICCListing listingContract = ICCListing(listingAddress);
        (context.makerAddress, context.recipientAddress, context.status) = listingContract.getBuyOrderCore(orderIdentifier);
        context.listingContract = listingContract;
        context.tokenIn = settlementContext.tokenB;
        context.tokenOut = settlementContext.tokenA;
        context.decimalsIn = settlementContext.decimalsB;
        context.decimalsOut = settlementContext.decimalsA;
        context.denormAmountIn = amountIn;
        (context.price, context.expectedAmountOut) = _computeSwapImpact(amountIn, true, settlementContext);
        context.denormAmountOutMin = context.expectedAmountOut * 95 / 100;
        path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
    }

    function _prepareSellSwapData(address listingAddress, uint256 orderIdentifier, uint256 amountIn, SettlementContext memory settlementContext) internal view returns (SwapContext memory context, address[] memory path) {
        ICCListing listingContract = ICCListing(listingAddress);
        (context.makerAddress, context.recipientAddress, context.status) = listingContract.getSellOrderCore(orderIdentifier);
        context.listingContract = listingContract;
        context.tokenIn = settlementContext.tokenA;
        context.tokenOut = settlementContext.tokenB;
        context.decimalsIn = settlementContext.decimalsA;
        context.decimalsOut = settlementContext.decimalsB;
        context.denormAmountIn = amountIn;
        (context.price, context.expectedAmountOut) = _computeSwapImpact(amountIn, false, settlementContext);
        context.denormAmountOutMin = context.expectedAmountOut * 95 / 100;
        path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
    }

    function _prepareTokenSwap(address tokenIn, address tokenOut, address recipient) internal view returns (TokenSwapData memory data) {
        data.preBalanceIn = IERC20(tokenIn).balanceOf(address(this));
        data.preBalanceOut = IERC20(tokenOut).balanceOf(recipient);
    }

    // Changelog: v0.1.27 (01/10): Commented out unused `amounts` variable
    function _performETHBuySwap(SwapContext memory context, address[] memory path) internal returns (ETHSwapData memory data) {
        data.preBalanceIn = address(this).balance;
        data.preBalanceOut = IERC20(context.tokenOut).balanceOf(context.recipientAddress);
        try IUniswapV2Router02(uniswapV2Router).swapExactETHForTokens{value: context.denormAmountIn}(context.denormAmountOutMin, path, context.recipientAddress, block.timestamp + 15) returns (uint256[] memory /* amounts */) {
            data.postBalanceIn = address(this).balance;
            data.amountInReceived = data.preBalanceIn > data.postBalanceIn ? data.preBalanceIn - data.postBalanceIn : 0;
            data.postBalanceOut = IERC20(context.tokenOut).balanceOf(context.recipientAddress);
            data.amountOut = data.postBalanceOut > data.preBalanceOut ? data.postBalanceOut - data.preBalanceOut : 0;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("ETH buy swap failed: ", reason)));
        }
        if (data.amountOut == 0) revert("No tokens received in ETH swap");
    }

    // Changelog: v0.1.27 (01/10): Commented out unused `amounts` variable
    function _performETHSellSwap(SwapContext memory context, address[] memory path) internal returns (ETHSwapData memory data) {
        data.preBalanceIn = IERC20(context.tokenIn).balanceOf(address(this));
        data.preBalanceOut = context.recipientAddress.balance;
        try IUniswapV2Router02(uniswapV2Router).swapExactTokensForETH(context.denormAmountIn, context.denormAmountOutMin, path, context.recipientAddress, block.timestamp + 15) returns (uint256[] memory /* amounts */) {
            data.postBalanceIn = IERC20(context.tokenIn).balanceOf(address(this));
            data.amountInReceived = data.postBalanceIn > data.preBalanceIn ? data.postBalanceIn - data.preBalanceIn : 0;
            data.postBalanceOut = context.recipientAddress.balance;
            data.amountOut = data.postBalanceOut > data.preBalanceOut ? data.postBalanceOut - data.preBalanceOut : 0;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("ETH sell swap failed: ", reason)));
        }
        if (data.amountOut == 0) revert("No ETH received in swap");
    }

    function _createOrderUpdates(uint256 orderIdentifier, OrderUpdateContext memory updateContext, uint256 pendingAmount, uint256 filled, bool isBuyOrder) internal view returns (ICCListing.BuyOrderUpdate[] memory buyUpdates, ICCListing.SellOrderUpdate[] memory sellUpdates) {
        ICCListing listingContract = ICCListing(updateContext.makerAddress);
        (, , uint256 priorAmountSent) = isBuyOrder ? listingContract.getBuyOrderAmounts(orderIdentifier) : listingContract.getSellOrderAmounts(orderIdentifier);
        uint256 newPending = pendingAmount > updateContext.amountIn ? pendingAmount - updateContext.amountIn : 0;
        if (isBuyOrder) {
            buyUpdates = new ICCListing.BuyOrderUpdate[](2);
            buyUpdates[0] = ICCListing.BuyOrderUpdate({
                structId: 2,
                orderId: orderIdentifier,
                makerAddress: updateContext.makerAddress,
                recipientAddress: updateContext.recipient,
                status: updateContext.status,
                maxPrice: 0,
                minPrice: 0,
                pending: newPending,
                filled: filled + updateContext.amountIn,
                amountSent: priorAmountSent + updateContext.amountSent
            });
            buyUpdates[1] = ICCListing.BuyOrderUpdate({
                structId: 0,
                orderId: orderIdentifier,
                makerAddress: updateContext.makerAddress,
                recipientAddress: updateContext.recipient,
                status: newPending == 0 ? 3 : 2,
                maxPrice: 0,
                minPrice: 0,
                pending: 0,
                filled: 0,
                amountSent: 0
            });
            sellUpdates = new ICCListing.SellOrderUpdate[](0);
        } else {
            sellUpdates = new ICCListing.SellOrderUpdate[](2);
            sellUpdates[0] = ICCListing.SellOrderUpdate({
                structId: 2,
                orderId: orderIdentifier,
                makerAddress: updateContext.makerAddress,
                recipientAddress: updateContext.recipient,
                status: updateContext.status,
                maxPrice: 0,
                minPrice: 0,
                pending: newPending,
                filled: filled + updateContext.amountIn,
                amountSent: priorAmountSent + updateContext.amountSent
            });
            sellUpdates[1] = ICCListing.SellOrderUpdate({
                structId: 0,
                orderId: orderIdentifier,
                makerAddress: updateContext.makerAddress,
                recipientAddress: updateContext.recipient,
                status: newPending == 0 ? 3 : 2,
                maxPrice: 0,
                minPrice: 0,
                pending: 0,
                filled: 0,
                amountSent: 0
            });
            buyUpdates = new ICCListing.BuyOrderUpdate[](0);
        }
    }

    function _finalizeTokenSwap(TokenSwapData memory data, SwapContext memory context, uint256 orderIdentifier, uint256 pendingAmount, bool isBuyOrder) internal view returns (ICCListing.BuyOrderUpdate[] memory buyUpdates, ICCListing.SellOrderUpdate[] memory sellUpdates) {
        if (data.amountOut == 0) revert("No tokens received in swap");
        OrderUpdateContext memory updateContext = OrderUpdateContext({
            makerAddress: context.makerAddress,
            recipient: context.recipientAddress,
            status: pendingAmount <= data.amountOut ? 3 : 2,
            amountSent: data.amountOut,
            amountIn: context.denormAmountIn
        });
        (, uint256 filled, ) = isBuyOrder ? context.listingContract.getBuyOrderAmounts(orderIdentifier) : context.listingContract.getSellOrderAmounts(orderIdentifier);
        return _createOrderUpdates(orderIdentifier, updateContext, pendingAmount, filled, isBuyOrder);
    }

    function _executeBuyETHSwap(SwapContext memory context, uint256 orderIdentifier, uint256 pendingAmount) internal returns (ICCListing.BuyOrderUpdate[] memory buyUpdates) {
        address[] memory path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        ETHSwapData memory data = _performETHBuySwap(context, path);
        if (data.amountOut == 0) revert("No tokens received in ETH swap");
        OrderUpdateContext memory updateContext = OrderUpdateContext({
            makerAddress: context.makerAddress,
            recipient: context.recipientAddress,
            status: pendingAmount <= data.amountOut ? 3 : 2,
            amountSent: data.amountOut,
            amountIn: context.denormAmountIn
        });
        (, uint256 filled, ) = context.listingContract.getBuyOrderAmounts(orderIdentifier);
        (buyUpdates,) = _createOrderUpdates(orderIdentifier, updateContext, pendingAmount, filled, true);
    }

    function _executeSellETHSwapInternal(SwapContext memory context, uint256 orderIdentifier, uint256 pendingAmount) internal returns (ICCListing.SellOrderUpdate[] memory sellUpdates) {
        address[] memory path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        ETHSwapData memory data = _performETHSellSwap(context, path);
        if (data.amountOut == 0) revert("No ETH received in swap");
        OrderUpdateContext memory updateContext = OrderUpdateContext({
            makerAddress: context.makerAddress,
            recipient: context.recipientAddress,
            status: pendingAmount <= data.amountOut ? 3 : 2,
            amountSent: data.amountOut,
            amountIn: context.denormAmountIn
        });
        (, uint256 filled, ) = context.listingContract.getSellOrderAmounts(orderIdentifier);
        (,sellUpdates) = _createOrderUpdates(orderIdentifier, updateContext, pendingAmount, filled, false);
    }

    function _executeBuyTokenSwap(SwapContext memory context, uint256 orderIdentifier, uint256 pendingAmount) internal returns (ICCListing.BuyOrderUpdate[] memory buyUpdates) {
        address[] memory path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        TokenSwapData memory data = _prepareTokenSwap(context.tokenIn, context.tokenOut, context.recipientAddress);
        data = _executeTokenSwap(context, path, context.denormAmountIn);
        (buyUpdates,) = _finalizeTokenSwap(data, context, orderIdentifier, pendingAmount, true);
    }

    function _executeSellTokenSwap(SwapContext memory context, uint256 orderIdentifier, uint256 pendingAmount, uint256 amountInReceived) internal returns (ICCListing.SellOrderUpdate[] memory sellUpdates) {
        address[] memory path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        TokenSwapData memory data = _prepareTokenSwap(context.tokenIn, context.tokenOut, context.recipientAddress);
        data = _executeTokenSwap(context, path, amountInReceived);
        (,sellUpdates) = _finalizeTokenSwap(data, context, orderIdentifier, pendingAmount, false);
    }

    function _executePartialBuySwap(address listingAddress, uint256 orderIdentifier, uint256 amountIn, uint256 pendingAmount, SettlementContext memory settlementContext) internal returns (ICCListing.BuyOrderUpdate[] memory buyUpdates) {
        SwapContext memory context;
        address[] memory path;
        (context, path) = _prepareSwapData(listingAddress, orderIdentifier, amountIn, settlementContext);
        if (context.price == 0) {
            emit OrderSkipped(orderIdentifier, "Zero price in swap data");
            return new ICCListing.BuyOrderUpdate[](0);
        }
        if (context.tokenIn == address(0)) return _executeBuyETHSwap(context, orderIdentifier, pendingAmount);
        return _executeBuyTokenSwap(context, orderIdentifier, pendingAmount);
    }

    function _executePartialSellSwap(address listingAddress, uint256 orderIdentifier, uint256 amountIn, uint256 pendingAmount, SettlementContext memory settlementContext) internal returns (ICCListing.SellOrderUpdate[] memory sellUpdates) {
        SwapContext memory context;
        address[] memory path;
        (context, path) = _prepareSellSwapData(listingAddress, orderIdentifier, amountIn, settlementContext);
        if (context.price == 0) {
            emit OrderSkipped(orderIdentifier, "Zero price in swap data");
            return new ICCListing.SellOrderUpdate[](0);
        }
        PrepOrderUpdateResult memory prepResult = _prepSellOrderUpdate(listingAddress, orderIdentifier, amountIn, settlementContext);
        if (context.tokenOut == address(0)) return _executeSellETHSwapInternal(context, orderIdentifier, pendingAmount);
        return _executeSellTokenSwap(context, orderIdentifier, pendingAmount, prepResult.amountSent);
    }

    function _computeMaxAmountIn(address listingAddress, uint256 maxPrice, uint256 minPrice, uint256 pendingAmount, bool isBuyOrder, SettlementContext memory settlementContext) internal view returns (uint256 maxAmountIn) {
        ReserveContext memory reserveContext = _fetchReserves(isBuyOrder, settlementContext);
        ICCListing listingContract = ICCListing(listingAddress);
        uint256 currentPrice = listingContract.prices(0);
        if (currentPrice == 0) revert("Zero current price");
        if (reserveContext.normalizedReserveIn == 0) revert("Zero normalized reserve");
        if (reserveContext.decimalsIn == 0) revert("Invalid input token decimals");
        uint256 priceAdjustedAmount = isBuyOrder ? (pendingAmount * maxPrice) / 1e18 : (pendingAmount * 1e18) / minPrice;
        maxAmountIn = priceAdjustedAmount > pendingAmount ? pendingAmount : priceAdjustedAmount;
        if (maxAmountIn > reserveContext.normalizedReserveIn) maxAmountIn = reserveContext.normalizedReserveIn;
        maxAmountIn = (maxAmountIn * 1000) / 997;
        if (maxAmountIn > pendingAmount) maxAmountIn = pendingAmount;
        maxAmountIn = denormalize(maxAmountIn, reserveContext.decimalsIn);
    }

    // Changelog: v0.1.27 (01/10): Commented out unused `amounts` variable
    function _executeTokenSwap(SwapContext memory context, address[] memory path, uint256 amountIn) internal returns (TokenSwapData memory data) {
        data.preBalanceIn = IERC20(context.tokenIn).balanceOf(address(this));
        data.preBalanceOut = IERC20(context.tokenOut).balanceOf(context.recipientAddress);
        try IUniswapV2Router02(uniswapV2Router).swapExactTokensForTokens(amountIn, context.denormAmountOutMin, path, context.recipientAddress, block.timestamp + 15) returns (uint256[] memory /* amounts */) {
            data.postBalanceIn = IERC20(context.tokenIn).balanceOf(address(this));
            data.amountInReceived = data.postBalanceIn > data.preBalanceIn ? data.postBalanceIn - data.preBalanceIn : 0;
            data.postBalanceOut = IERC20(context.tokenOut).balanceOf(context.recipientAddress);
            data.amountOut = data.postBalanceOut > data.preBalanceOut ? data.postBalanceOut - data.preBalanceOut : 0;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Token swap failed: ", reason)));
        }
        if (data.amountOut == 0) revert("No tokens received in swap");
    }

    function uint2str(uint256 _i) internal pure returns (string memory str) {
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