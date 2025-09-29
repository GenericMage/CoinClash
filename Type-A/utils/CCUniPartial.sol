// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.22
// Changes:
// - v0.1.22: Removed denormalization in _prepBuyOrderUpdate/_prepSellOrderUpdate as amountIn is already denormalized in _computeMaxAmountIn. Updated amountSent to use pre/post balance checks (29/9).
// - v0.1.21: Updated _finalizeTokenSwap and _finalizeSellTokenSwap to compute amountSent with pre/post balance checks, adjusted status based on pending amount.
// - v0.1.20: added uint2str, getTokenAndDecimals, prepBuyOrderUpdate and prepSellOrderUpdate to unipartial to resolve declaration error. 
// - v0.1.18: Patched _prepareSwapData/_prepareSellSwapData to compute amountOutMin using amountInReceived from _prepBuyOrderUpdate/_prepSellOrderUpdate to handle transfer taxes. 
// - v0.1.17: Patched _executeTokenSwap to use actual amountInReceived for swap. Added allowance check in _prepareTokenSwap, setting 10^50 if insufficient. 
// - v0.1.16: Modified _fetchReserves to use token balances at Uniswap V2 pair address instead of getReserves to avoid scaling issues.
// - v0.1.15: Removed _ensureTokenBalance and NonCriticalInsufficientBalance event, relying on _prepBuyOrderUpdate/_prepSellOrderUpdate for transactToken. Updated _computeMaxAmountIn with dynamic formula using price bounds and reserves. Streamlined _computeSwapImpact and _fetchReserves to use SettlementContext for static data. 

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
	struct PrepOrderUpdateResult {
        address tokenAddress;
        uint8 tokenDecimals;
        address makerAddress;
        address recipientAddress;
        uint8 orderStatus;
        uint256 amountReceived;
        uint256 normalizedReceived;
        uint256 amountSent;
        uint256 amountIn;
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

    struct BuyOrderUpdateContext {
        address makerAddress;
        address recipient;
        uint8 status;
        uint256 normalizedReceived;
        uint256 amountSent;
        uint256 amountIn;
    }

    struct SellOrderUpdateContext {
        address makerAddress;
        address recipient;
        uint8 status;
        uint256 normalizedReceived;
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

function _getTokenAndDecimals(
        address listingAddress,
        bool isBuyOrder,
        SettlementContext memory settlementContext
    ) internal pure returns (address tokenAddress, uint8 tokenDecimals) {
        // Retrieves token address and decimals from cached data
        tokenAddress = isBuyOrder ? settlementContext.tokenB : settlementContext.tokenA;
        tokenDecimals = isBuyOrder ? settlementContext.decimalsB : settlementContext.decimalsA;
        if (tokenAddress == address(0) && !isBuyOrder) {
            revert("Invalid token address for sell order");
        }
    }
    
function _prepBuyOrderUpdate(
    address listingAddress,
    uint256 orderIdentifier,
    uint256 amountReceived,
    SettlementContext memory settlementContext
) internal returns (PrepOrderUpdateResult memory result) {
    // Prepares buy order update, pulls funds via transact for Uniswap swap
    ICCListing listingContract = ICCListing(listingAddress);
    (uint256 pending, uint256 filled, ) = listingContract.getBuyOrderAmounts(orderIdentifier);
    if (pending == 0) {
        revert(string(abi.encodePacked("No pending amount for buy order ", uint2str(orderIdentifier))));
    }
    (result.tokenAddress, result.tokenDecimals) = _getTokenAndDecimals(listingAddress, true, settlementContext);
    (result.makerAddress, result.recipientAddress, result.orderStatus) = listingContract.getBuyOrderCore(orderIdentifier);
    if (result.orderStatus != 1) {
        revert(string(abi.encodePacked("Invalid status for buy order ", uint2str(orderIdentifier), ": ", uint2str(result.orderStatus))));
    }
    uint256 preBalance = result.tokenAddress == address(0) ? address(this).balance : IERC20(result.tokenAddress).balanceOf(address(this));
    if (result.tokenAddress == address(0)) {
        try listingContract.transactNative{value: amountReceived}(amountReceived, address(this)) {
            result.amountSent = address(this).balance - preBalance; // Use balance difference
            result.amountIn = result.amountSent;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Native transfer failed for buy order ", uint2str(orderIdentifier), ": ", reason)));
        }
    } else {
        try listingContract.transactToken(result.tokenAddress, amountReceived, address(this)) {
            result.amountSent = IERC20(result.tokenAddress).balanceOf(address(this)) - preBalance; // Use balance difference
            result.amountIn = result.amountSent;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Token transfer failed for buy order ", uint2str(orderIdentifier), ": ", reason)));
        }
    }
    if (result.amountSent == 0) {
        revert(string(abi.encodePacked("No tokens received for buy order ", uint2str(orderIdentifier))));
    }
    result.normalizedReceived = normalize(result.amountSent, result.tokenDecimals);
}

function _prepSellOrderUpdate(
    address listingAddress,
    uint256 orderIdentifier,
    uint256 amountReceived,
    SettlementContext memory settlementContext
) internal returns (PrepOrderUpdateResult memory result) {
    // Prepares sell order update, pulls funds via transact for Uniswap swap
    ICCListing listingContract = ICCListing(listingAddress);
    (uint256 pending, uint256 filled, ) = listingContract.getSellOrderAmounts(orderIdentifier);
    if (pending == 0) {
        revert(string(abi.encodePacked("No pending amount for sell order ", uint2str(orderIdentifier))));
    }
    (result.tokenAddress, result.tokenDecimals) = _getTokenAndDecimals(listingAddress, false, settlementContext);
    (result.makerAddress, result.recipientAddress, result.orderStatus) = listingContract.getSellOrderCore(orderIdentifier);
    if (result.orderStatus != 1) {
        revert(string(abi.encodePacked("Invalid status for sell order ", uint2str(orderIdentifier), ": ", uint2str(result.orderStatus))));
    }
    uint256 preBalance = result.tokenAddress == address(0) ? address(this).balance : IERC20(result.tokenAddress).balanceOf(address(this));
    if (result.tokenAddress == address(0)) {
        try listingContract.transactNative{value: amountReceived}(amountReceived, address(this)) {
            result.amountSent = address(this).balance - preBalance; // Use balance difference
            result.amountIn = result.amountSent;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Native transfer failed for sell order ", uint2str(orderIdentifier), ": ", reason)));
        }
    } else {
        try listingContract.transactToken(result.tokenAddress, amountReceived, address(this)) {
            result.amountSent = IERC20(result.tokenAddress).balanceOf(address(this)) - preBalance; // Use balance difference
            result.amountIn = result.amountSent;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Token transfer failed for sell order ", uint2str(orderIdentifier), ": ", reason)));
        }
    }
    if (result.amountSent == 0) {
        revert(string(abi.encodePacked("No tokens received for sell order ", uint2str(orderIdentifier))));
    }
    result.normalizedReceived = normalize(result.amountSent, result.tokenDecimals);
}

function _computeCurrentPrice(address listingAddress) internal view returns (uint256 price) {
    // Retrieves current price from listing contract
    ICCListing listingContract = ICCListing(listingAddress);
    price = listingContract.prices(0);
    require(price > 0, "Invalid price from listing");
}

    // Computes swap impact using normalized token balances
function _computeSwapImpact(
    address listingAddress,
    uint256 amountIn,
    bool isBuyOrder,
    SettlementContext memory settlementContext
) internal view returns (uint256 price, uint256 amountOut) {
    SwapImpactContext memory context;
    context.decimalsIn = isBuyOrder ? settlementContext.decimalsB : settlementContext.decimalsA;
    context.decimalsOut = isBuyOrder ? settlementContext.decimalsA : settlementContext.decimalsB;
    context.reserveIn = IERC20(isBuyOrder ? settlementContext.tokenB : settlementContext.tokenA).balanceOf(settlementContext.uniswapV2Pair);
    context.reserveOut = IERC20(isBuyOrder ? settlementContext.tokenA : settlementContext.tokenB).balanceOf(settlementContext.uniswapV2Pair);
    context.normalizedReserveIn = normalize(context.reserveIn, context.decimalsIn);
    context.normalizedReserveOut = normalize(context.reserveOut, context.decimalsOut);
    context.amountInAfterFee = (normalize(amountIn, context.decimalsIn) * 997) / 1000; // Normalize input and apply Uniswap fee
    context.amountOut = (context.amountInAfterFee * context.normalizedReserveOut) / (context.normalizedReserveIn + context.amountInAfterFee);
    context.price = ICCListing(listingAddress).prices(0);
    price = context.price;
    amountOut = denormalize(context.amountOut, context.decimalsOut); // Denormalize output for token decimals
}

    function _fetchReserves(
    address listingAddress,
    bool isBuyOrder,
    SettlementContext memory settlementContext
) internal view returns (ReserveContext memory reserveContext) {
    // Fetches token balance from Uniswap V2 pair for input token
    require(settlementContext.uniswapV2Pair != address(0), "Uniswap V2 pair not set");
    reserveContext.tokenA = settlementContext.tokenA;
    reserveContext.decimalsIn = isBuyOrder ? settlementContext.decimalsB : settlementContext.decimalsA;
    address tokenIn = isBuyOrder ? settlementContext.tokenB : settlementContext.tokenA;
    reserveContext.reserveIn = IERC20(tokenIn).balanceOf(settlementContext.uniswapV2Pair);
    reserveContext.normalizedReserveIn = normalize(reserveContext.reserveIn, reserveContext.decimalsIn);
}

    function _prepareSwapData(
    address listingAddress,
    uint256 orderIdentifier,
    uint256 amountIn,
    SettlementContext memory settlementContext
) internal returns (SwapContext memory context, address[] memory path) {
    // Prepares swap data for buy order using cached static data
    ICCListing listingContract = ICCListing(listingAddress);
    (address makerAddress, address recipientAddress, uint8 status) = listingContract.getBuyOrderCore(orderIdentifier);
    context.listingContract = listingContract;
    context.makerAddress = makerAddress;
    context.recipientAddress = recipientAddress;
    context.status = status;
    context.tokenIn = settlementContext.tokenB;
    context.tokenOut = settlementContext.tokenA;
    context.decimalsIn = settlementContext.decimalsB;
    context.decimalsOut = settlementContext.decimalsA;
    context.denormAmountIn = amountIn;
    context.price = _computeCurrentPrice(listingAddress);
    uint256 amountInReceived = _prepBuyOrderUpdate(listingAddress, orderIdentifier, amountIn, settlementContext).amountIn;
    (, context.expectedAmountOut) = _computeSwapImpact(listingAddress, amountInReceived, true, settlementContext);
    context.denormAmountOutMin = context.expectedAmountOut;
    path = new address[](2);
    path[0] = context.tokenIn;
    path[1] = context.tokenOut;
}

function _prepareSellSwapData(
    address listingAddress,
    uint256 orderIdentifier,
    uint256 amountIn,
    SettlementContext memory settlementContext
) internal returns (SwapContext memory context, address[] memory path) {
    // Prepares swap data for sell order using cached static data
    ICCListing listingContract = ICCListing(listingAddress);
    (address makerAddress, address recipientAddress, uint8 status) = listingContract.getSellOrderCore(orderIdentifier);
    context.listingContract = listingContract;
    context.makerAddress = makerAddress;
    context.recipientAddress = recipientAddress;
    context.status = status;
    context.tokenIn = settlementContext.tokenA;
    context.tokenOut = settlementContext.tokenB;
    context.decimalsIn = settlementContext.decimalsA;
    context.decimalsOut = settlementContext.decimalsB;
    context.denormAmountIn = amountIn;
    context.price = _computeCurrentPrice(listingAddress);
    uint256 amountInReceived = _prepSellOrderUpdate(listingAddress, orderIdentifier, amountIn, settlementContext).amountIn;
    (, context.expectedAmountOut) = _computeSwapImpact(listingAddress, amountInReceived, false, settlementContext);
    context.denormAmountOutMin = context.expectedAmountOut;
    path = new address[](2);
    path[0] = context.tokenIn;
    path[1] = context.tokenOut;
}

    function _prepareTokenSwap(
    address tokenIn,
    address tokenOut,
    address recipientAddress
) internal returns (TokenSwapData memory data) {
    // Prepares token swap with pre/post balance checks and allowance verification
    data.preBalanceIn = IERC20(tokenIn).balanceOf(address(this));
    data.preBalanceOut = IERC20(tokenOut).balanceOf(recipientAddress);
    uint256 currentAllowance = IERC20(tokenIn).allowance(address(this), uniswapV2Router);
    if (currentAllowance < data.preBalanceIn) {
        bool success = IERC20(tokenIn).approve(uniswapV2Router, 10**50);
        require(success, "Token approval failed");
    }
}

    function _executeTokenSwap(
    SwapContext memory context,
    address[] memory path
) internal returns (TokenSwapData memory data) {
    // Executes token-to-token swap using actual received amount
    uint256 deadline = block.timestamp + 15 minutes;
    IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2Router);
    data.postBalanceIn = IERC20(context.tokenIn).balanceOf(address(this));
    data.amountInReceived = data.postBalanceIn > data.preBalanceIn ? data.postBalanceIn - data.preBalanceIn : 0;
    require(data.amountInReceived > 0, "No tokens available for swap");
    uint256[] memory amounts = router.swapExactTokensForTokens(
        data.amountInReceived, // Use actual received amount
        context.denormAmountOutMin,
        path,
        context.recipientAddress,
        deadline
    );
    data.amountReceived = amounts[amounts.length - 1];
    data.postBalanceOut = IERC20(context.tokenOut).balanceOf(context.recipientAddress);
    data.amountOut = data.postBalanceOut > data.preBalanceOut ? data.postBalanceOut - data.preBalanceOut : 0;
}

    function _performETHBuySwap(
        SwapContext memory context,
        address[] memory path
    ) internal returns (ETHSwapData memory data) {
        // Performs ETH-to-token swap
        data.preBalanceIn = address(this).balance;
        data.preBalanceOut = IERC20(context.tokenOut).balanceOf(context.recipientAddress);
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2Router);
        uint256 deadline = block.timestamp + 15 minutes;
        uint256[] memory amounts = router.swapExactETHForTokens{value: context.denormAmountIn}(
            context.denormAmountOutMin,
            path,
            context.recipientAddress,
            deadline
        );
        data.amountReceived = amounts[amounts.length - 1];
        data.postBalanceIn = address(this).balance;
        data.amountInReceived = data.preBalanceIn > data.postBalanceIn ? data.preBalanceIn - data.postBalanceIn : 0;
        data.postBalanceOut = IERC20(context.tokenOut).balanceOf(context.recipientAddress);
        data.amountOut = data.postBalanceOut > data.preBalanceOut ? data.postBalanceOut - data.preBalanceOut : 0;
    }

    function _performETHSellSwap(
        SwapContext memory context,
        address[] memory path
    ) internal returns (ETHSwapData memory data) {
        // Performs token-to-ETH swap
        data.preBalanceIn = IERC20(context.tokenIn).balanceOf(address(this));
        data.preBalanceOut = context.recipientAddress.balance;
        bool success = IERC20(context.tokenIn).approve(uniswapV2Router, type(uint256).max);
        require(success, "Token approval failed");
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2Router);
        uint256 deadline = block.timestamp + 15 minutes;
        uint256[] memory amounts = router.swapExactTokensForETH(
            context.denormAmountIn,
            context.denormAmountOutMin,
            path,
            context.recipientAddress,
            deadline
        );
        data.amountReceived = amounts[amounts.length - 1];
        data.postBalanceIn = IERC20(context.tokenIn).balanceOf(address(this));
        data.amountInReceived = data.postBalanceIn > data.preBalanceIn ? data.postBalanceIn - data.preBalanceIn : 0;
        data.postBalanceOut = context.recipientAddress.balance;
        data.amountOut = data.postBalanceOut > data.preBalanceOut ? data.postBalanceOut - data.preBalanceOut : 0;
    }

    // Modified _finalizeTokenSwap to fix amountSent and status
function _finalizeTokenSwap(
    TokenSwapData memory data,
    SwapContext memory context,
    uint256 orderIdentifier,
    uint256 pendingAmount
) internal view returns (ICCListing.BuyOrderUpdate[] memory) {
    require(data.amountOut > 0, "No tokens received in swap");
    BuyOrderUpdateContext memory updateContext = BuyOrderUpdateContext({
        makerAddress: context.makerAddress,
        recipient: context.recipientAddress,
        status: pendingAmount <= data.amountOut ? 3 : 2,
        normalizedReceived: normalize(data.amountOut, context.decimalsOut),
        amountSent: data.amountOut,
        amountIn: context.denormAmountIn
    });
    (, uint256 filled, ) = context.listingContract.getBuyOrderAmounts(orderIdentifier);
    return _createBuyOrderUpdates(orderIdentifier, updateContext, pendingAmount, filled);
}

    // Modified _finalizeSellTokenSwap to fix amountSent and status
function _finalizeSellTokenSwap(
    TokenSwapData memory data,
    SwapContext memory context,
    uint256 orderIdentifier,
    uint256 pendingAmount
) internal view returns (ICCListing.SellOrderUpdate[] memory) {
    require(data.amountOut > 0, "No tokens received in swap");
    SellOrderUpdateContext memory updateContext = SellOrderUpdateContext({
        makerAddress: context.makerAddress,
        recipient: context.recipientAddress,
        status: pendingAmount <= data.amountOut ? 3 : 2,
        normalizedReceived: normalize(data.amountOut, context.decimalsOut),
        amountSent: data.amountOut,
        amountIn: context.denormAmountIn
    });
    (, uint256 filled, ) = context.listingContract.getSellOrderAmounts(orderIdentifier);
    return _createSellOrderUpdates(orderIdentifier, updateContext, pendingAmount, filled);
}

    function _executeBuyETHSwap(
        SwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ICCListing.BuyOrderUpdate[] memory buyUpdates) {
        address[] memory path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        ETHSwapData memory data = _performETHBuySwap(context, path);
        require(data.amountOut > 0, "No tokens received in swap"); // Check using balance difference
        BuyOrderUpdateContext memory updateContext = BuyOrderUpdateContext({
            makerAddress: context.makerAddress,
            recipient: context.recipientAddress,
            status: context.status,
            normalizedReceived: normalize(data.amountOut, context.decimalsOut), // Use balance difference
            amountSent: data.amountOut, // Use actual amount received by user
            amountIn: context.denormAmountIn
        });
        (, uint256 filled, ) = context.listingContract.getBuyOrderAmounts(orderIdentifier);
        return _createBuyOrderUpdates(orderIdentifier, updateContext, pendingAmount, filled);
    }

    function _executeSellETHSwapInternal(
        SwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ICCListing.SellOrderUpdate[] memory sellUpdates) {
        address[] memory path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        ETHSwapData memory data = _performETHSellSwap(context, path);
        require(data.amountOut > 0, "No ETH received in swap"); // Check using balance difference
        SellOrderUpdateContext memory updateContext = SellOrderUpdateContext({
            makerAddress: context.makerAddress,
            recipient: context.recipientAddress,
            status: context.status,
            normalizedReceived: normalize(data.amountOut, context.decimalsOut), // Use balance difference
            amountSent: data.amountOut, // Use actual amount received by user
            amountIn: context.denormAmountIn
        });
        (, uint256 filled, ) = context.listingContract.getSellOrderAmounts(orderIdentifier);
        return _createSellOrderUpdates(orderIdentifier, updateContext, pendingAmount, filled);
    }

    function _executeBuyTokenSwap(
        SwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ICCListing.BuyOrderUpdate[] memory buyUpdates) {
        // Executes token-to-token swap for buy order
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
    ) internal returns (ICCListing.SellOrderUpdate[] memory sellUpdates) {
        // Executes token-to-token swap for sell order
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
        uint256 pendingAmount,
        SettlementContext memory settlementContext
    ) internal returns (ICCListing.BuyOrderUpdate[] memory buyUpdates) {
        SwapContext memory context;
        address[] memory path;
        (context, path) = _prepareSwapData(listingAddress, orderIdentifier, amountIn, settlementContext);
        if (context.price == 0) {
            return new ICCListing.BuyOrderUpdate[](0);
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
        uint256 pendingAmount,
        SettlementContext memory settlementContext
    ) internal returns (ICCListing.SellOrderUpdate[] memory sellUpdates) {
        SwapContext memory context;
        address[] memory path;
        (context, path) = _prepareSellSwapData(listingAddress, orderIdentifier, amountIn, settlementContext);
        if (context.price == 0) {
            return new ICCListing.SellOrderUpdate[](0);
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
        uint256 pendingAmount,
        uint256 filled
    ) internal pure returns (ICCListing.BuyOrderUpdate[] memory buyUpdates) {
        // Creates BuyOrderUpdate structs
        buyUpdates = new ICCListing.BuyOrderUpdate[](2);
        uint256 newPending = pendingAmount > updateContext.amountIn ? pendingAmount - updateContext.amountIn : 0;
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
            amountSent: updateContext.amountSent
        });
        buyUpdates[1] = ICCListing.BuyOrderUpdate({
            structId: 0,
            orderId: orderIdentifier,
            makerAddress: updateContext.makerAddress,
            recipientAddress: updateContext.recipient,
            status: newPending == 0 ? 3 : 2, // Corrected status logic
            maxPrice: 0,
            minPrice: 0,
            pending: 0,
            filled: 0,
            amountSent: 0
        });
    }

    function _createSellOrderUpdates(
        uint256 orderIdentifier,
        SellOrderUpdateContext memory updateContext,
        uint256 pendingAmount,
        uint256 filled
    ) internal pure returns (ICCListing.SellOrderUpdate[] memory sellUpdates) {
        // Creates SellOrderUpdate structs
        sellUpdates = new ICCListing.SellOrderUpdate[](2);
        uint256 newPending = pendingAmount > updateContext.amountIn ? pendingAmount - updateContext.amountIn : 0;
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
            amountSent: updateContext.amountSent
        });
        sellUpdates[1] = ICCListing.SellOrderUpdate({
            structId: 0,
            orderId: orderIdentifier,
            makerAddress: updateContext.makerAddress,
            recipientAddress: updateContext.recipient,
            status: newPending == 0 ? 3 : 2, // Corrected status logic
            maxPrice: 0,
            minPrice: 0,
            pending: 0,
            filled: 0,
            amountSent: 0
        });
    }

    // Computes max input amount with proper decimal normalization
function _computeMaxAmountIn(
    address listingAddress,
    uint256 maxPrice,
    uint256 minPrice,
    uint256 pendingAmount,
    bool isBuyOrder,
    SettlementContext memory settlementContext
) internal view returns (uint256 maxAmountIn) {
    ReserveContext memory reserveContext = _fetchReserves(listingAddress, isBuyOrder, settlementContext);
    ICCListing listingContract = ICCListing(listingAddress);
    uint256 currentPrice = listingContract.prices(0);
    if (currentPrice == 0 || reserveContext.normalizedReserveIn == 0) {
        return 0;
    }
    uint256 priceAdjustedAmount = isBuyOrder
        ? (pendingAmount * maxPrice) / 1e18 // tokenB amount for buys
        : (pendingAmount * 1e18) / minPrice; // tokenA amount for sells
    maxAmountIn = priceAdjustedAmount > pendingAmount ? pendingAmount : priceAdjustedAmount;
    if (maxAmountIn > reserveContext.normalizedReserveIn) {
        maxAmountIn = reserveContext.normalizedReserveIn;
    }
    maxAmountIn = (maxAmountIn * 1000) / 997; // Apply Uniswap fee
    maxAmountIn = denormalize(maxAmountIn, reserveContext.decimalsIn); // Denormalize for token decimals
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