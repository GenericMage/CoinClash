// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.9
// Changes:
// - v0.1.9: Adjusted pending amount in _createBuyOrderUpdates and _createSellOrderUpdates to use pendingAmount - updateContext.amountIn
// - v0.1.8: Addresses Redundant amountReceived in BuyOrderUpdateContext and SellOrderUpdateContext
// - v0.1.7: Addresses Incorrect status logic in _createBuyOrderUpdates and _createSellOrderUpdates
// - v0.1.6: Modified _createBuyOrderUpdates and _createSellOrderUpdates to return BuyOrderUpdate and SellOrderUpdate structs directly, removing encoding/decoding. Updated _executePartialBuySwap and _executePartialSellSwap to return correct struct types.
// - v0.1.5: Fixed TypeError in _finalizeTokenSwap and _finalizeSellTokenSwap by adding `amountIn` to BuyOrderUpdateContext and SellOrderUpdateContext constructors, using SwapContext.denormAmountIn. Ensured pending/filled use pre-transfer amount (tokenB for buys, tokenA for sells), and amountSent uses post-transfer amount (tokenA for buys, tokenB for sells) with pre/post balance checks.
// - v0.1.4: Fixed TypeError in _executeBuyTokenSwap, _executeSellTokenSwap, _executeBuyETHSwap, and _executeSellETHSwapInternal by adding `amountIn` to constructors.
// - v0.1.3: Fixed naming confusion by adding `amountIn` to BuyOrderUpdateContext and SellOrderUpdateContext for pre-transfer amount in pending/filled updates.
// - v0.1.2: Fixed TypeError by replacing `amountInReceived` with `amountSent`.
// - v0.1.1: Modified _createBuyOrderUpdates and _createSellOrderUpdates to encode data for ccUpdate, excluding Uniswap fees from pending/filled.
// - v0.1.0: Bumped version
// - v0.0.21: Updated _createBuyOrderUpdates and _createSellOrderUpdates to set makerAddress and recipient for all updates.
// - v0.0.20: Updated _computeSwapImpact to use IERC20 balanceOf for tokenA and tokenB from listing contract. Ensured decimals normalization.
// - v0.0.19: Modified _computeCurrentPrice to use listingContract.prices(0). Updated _computeSwapImpact for consistency.
// - v0.0.18: Updated _computeCurrentPrice to use reserveB / reserveA for flipped price calculation.

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
        uint256 normalizedReceived; // Normalized post-transfer amount
        uint256 amountSent; // Post-transfer amount received by recipient
        uint256 amountIn; // Pre-transfer amount for pending/filled
    }

    struct SellOrderUpdateContext {
        address makerAddress;
        address recipient;
        uint8 status;
        uint256 normalizedReceived; // Normalized post-transfer amount
        uint256 amountSent; // Post-transfer amount received by recipient
        uint256 amountIn; // Pre-transfer amount for pending/filled
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
        // Retrieves current price from listingContract.prices(0)
        ICCListing listingContract = ICCListing(listingAddress);
        price = listingContract.prices(0);
        require(price > 0, "Invalid price from listing");
    }

    function _computeSwapImpact(
        address listingAddress,
        uint256 amountIn,
        bool isBuyOrder
    ) internal view returns (uint256 price, uint256 amountOut) {
        // Computes swap impact using IERC20 balanceOf for tokenA and tokenB
        ICCListing listingContract = ICCListing(listingAddress);
        address tokenA = listingContract.tokenA();
        address tokenB = listingContract.tokenB();
        uint8 decimalsA = listingContract.decimalsA();
        uint8 decimalsB = listingContract.decimalsB();
        SwapImpactContext memory context;
        context.decimalsIn = isBuyOrder ? decimalsB : decimalsA;
        context.decimalsOut = isBuyOrder ? decimalsA : decimalsB;
        context.reserveIn = isBuyOrder ? IERC20(tokenB).balanceOf(listingAddress) : IERC20(tokenA).balanceOf(listingAddress);
        context.reserveOut = isBuyOrder ? IERC20(tokenA).balanceOf(listingAddress) : IERC20(tokenB).balanceOf(listingAddress);
        context.normalizedReserveIn = normalize(context.reserveIn, context.decimalsIn);
        context.normalizedReserveOut = normalize(context.reserveOut, context.decimalsOut);
        context.amountInAfterFee = (amountIn * 997) / 1000; // Apply 0.3% Uniswap fee
        context.amountOut = (context.amountInAfterFee * context.normalizedReserveOut) / (context.normalizedReserveIn + context.amountInAfterFee);
        context.price = listingContract.prices(0);
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

    function _prepareSwapData(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountIn
    ) internal view returns (SwapContext memory context, address[] memory path) {
        // Prepares swap data for buy order
        ICCListing listingContract = ICCListing(listingAddress);
        (address makerAddress, address recipientAddress, uint8 status) = listingContract.getBuyOrderCore(orderIdentifier);
        context.listingContract = listingContract;
        context.makerAddress = makerAddress;
        context.recipientAddress = recipientAddress;
        context.status = status;
        context.tokenIn = listingContract.tokenB();
        context.tokenOut = listingContract.tokenA();
        context.decimalsIn = listingContract.decimalsB();
        context.decimalsOut = listingContract.decimalsA();
        context.denormAmountIn = amountIn;
        context.price = _computeCurrentPrice(listingAddress);
        (, context.expectedAmountOut) = _computeSwapImpact(listingAddress, amountIn, true);
        context.denormAmountOutMin = context.expectedAmountOut;
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
        (address makerAddress, address recipientAddress, uint8 status) = listingContract.getSellOrderCore(orderIdentifier);
        context.listingContract = listingContract;
        context.makerAddress = makerAddress;
        context.recipientAddress = recipientAddress;
        context.status = status;
        context.tokenIn = listingContract.tokenA();
        context.tokenOut = listingContract.tokenB();
        context.decimalsIn = listingContract.decimalsA();
        context.decimalsOut = listingContract.decimalsB();
        context.denormAmountIn = amountIn;
        context.price = _computeCurrentPrice(listingAddress);
        (, context.expectedAmountOut) = _computeSwapImpact(listingAddress, amountIn, false);
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
        // Prepares token swap with pre/post balance checks
        data.preBalanceIn = IERC20(tokenIn).balanceOf(address(this));
        data.preBalanceOut = IERC20(tokenOut).balanceOf(recipientAddress);
        bool success = IERC20(tokenIn).approve(uniswapV2Router, type(uint256).max);
        require(success, "Token approval failed");
    }

    function _executeTokenSwap(
        SwapContext memory context,
        address[] memory path
    ) internal returns (TokenSwapData memory data) {
        // Executes token-to-token swap with Uniswap V2
        uint256 deadline = block.timestamp + 15 minutes;
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2Router);
        data.postBalanceIn = IERC20(context.tokenIn).balanceOf(address(this));
        data.amountInReceived = data.postBalanceIn > data.preBalanceIn ? data.postBalanceIn - data.preBalanceIn : 0;
        uint256[] memory amounts = router.swapExactTokensForTokens(
            context.denormAmountIn,
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
        // Performs ETH-to-token swap for buy order
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
        // Performs token-to-ETH swap for sell order
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

function _finalizeTokenSwap(
        TokenSwapData memory data,
        SwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal pure returns (ICCListing.BuyOrderUpdate[] memory) {
        require(data.amountReceived > 0, "No tokens received in swap");
        BuyOrderUpdateContext memory updateContext = BuyOrderUpdateContext({
            makerAddress: context.makerAddress,
            recipient: context.recipientAddress,
            status: context.status,
            normalizedReceived: normalize(data.amountReceived, context.decimalsOut),
            amountSent: data.amountInReceived,
            amountIn: context.denormAmountIn
        });
        return _createBuyOrderUpdates(orderIdentifier, updateContext, pendingAmount);
    }

function _finalizeSellTokenSwap(
        TokenSwapData memory data,
        SwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal pure returns (ICCListing.SellOrderUpdate[] memory) {
        require(data.amountReceived > 0, "No tokens received in swap");
        SellOrderUpdateContext memory updateContext = SellOrderUpdateContext({
            makerAddress: context.makerAddress,
            recipient: context.recipientAddress,
            status: context.status,
            normalizedReceived: normalize(data.amountReceived, context.decimalsOut),
            amountSent: data.amountInReceived,
            amountIn: context.denormAmountIn
        });
        return _createSellOrderUpdates(orderIdentifier, updateContext, pendingAmount);
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
        require(data.amountReceived > 0, "No tokens received in swap");
        BuyOrderUpdateContext memory updateContext = BuyOrderUpdateContext({
            makerAddress: context.makerAddress,
            recipient: context.recipientAddress,
            status: context.status,
            normalizedReceived: normalize(data.amountReceived, context.decimalsOut),
            amountSent: data.amountInReceived,
            amountIn: context.denormAmountIn
        });
        return _createBuyOrderUpdates(orderIdentifier, updateContext, pendingAmount);
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
        require(data.amountReceived > 0, "No ETH received in swap");
        SellOrderUpdateContext memory updateContext = SellOrderUpdateContext({
            makerAddress: context.makerAddress,
            recipient: context.recipientAddress,
            status: context.status,
            normalizedReceived: normalize(data.amountReceived, context.decimalsOut),
            amountSent: data.amountInReceived,
            amountIn: context.denormAmountIn
        });
        return _createSellOrderUpdates(orderIdentifier, updateContext, pendingAmount);
    }

    // Updated _executeBuyTokenSwap to return BuyOrderUpdate[]
    function _executeBuyTokenSwap(
        SwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ICCListing.BuyOrderUpdate[] memory buyUpdates) {
        // Executes token-to-token swap for buy order; updates prepared here are refined in CCSettlementPartial.sol and applied once in CCSettlementRouter.sol via ccUpdate
        address[] memory path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        TokenSwapData memory data = _prepareTokenSwap(context.tokenIn, context.tokenOut, context.recipientAddress);
        data = _executeTokenSwap(context, path);
        return _finalizeTokenSwap(data, context, orderIdentifier, pendingAmount);
    }

    // Updated _executeSellTokenSwap to return SellOrderUpdate[]
    function _executeSellTokenSwap(
        SwapContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ICCListing.SellOrderUpdate[] memory sellUpdates) {
        // Executes token-to-token swap for sell order; updates prepared here are refined in CCSettlementPartial.sol and applied once in CCSettlementRouter.sol via ccUpdate
        address[] memory path = new address[](2);
        path[0] = context.tokenIn;
        path[1] = context.tokenOut;
        TokenSwapData memory data = _prepareTokenSwap(context.tokenIn, context.tokenOut, context.recipientAddress);
        data = _executeTokenSwap(context, path);
        return _finalizeSellTokenSwap(data, context, orderIdentifier, pendingAmount);
    }

    // Updated _executePartialBuySwap to return BuyOrderUpdate[]
    function _executePartialBuySwap(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountIn,
        uint256 pendingAmount
    ) internal returns (ICCListing.BuyOrderUpdate[] memory buyUpdates) {
        SwapContext memory context;
        address[] memory path;
        (context, path) = _prepareSwapData(listingAddress, orderIdentifier, amountIn);
        if (context.price == 0) {
            return new ICCListing.BuyOrderUpdate[](0);
        }
        if (context.tokenIn == address(0)) {
            return _executeBuyETHSwap(context, orderIdentifier, pendingAmount);
        } else {
            return _executeBuyTokenSwap(context, orderIdentifier, pendingAmount);
        }
        }

        // Updated _executePartialSellSwap to return SellOrderUpdate[]
    function _executePartialSellSwap(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountIn,
        uint256 pendingAmount
    ) internal returns (ICCListing.SellOrderUpdate[] memory sellUpdates) {
        SwapContext memory context;
        address[] memory path;
        (context, path) = _prepareSellSwapData(listingAddress, orderIdentifier, amountIn);
        if (context.price == 0) {
            return new ICCListing.SellOrderUpdate[](0);
        }
        if (context.tokenOut == address(0)) {
            return _executeSellETHSwapInternal(context, orderIdentifier, pendingAmount);
        } else {
            return _executeSellTokenSwap(context, orderIdentifier, pendingAmount);
        }
    }

    // Helper: Computes status for buy/sell updates
    function _computeOrderStatus(
        uint256 normalizedReceived,
        uint256 filled,
        uint256 pendingAmount,
        uint8 currentStatus
    ) internal pure returns (uint8 status) {
        uint256 totalFilled = normalizedReceived + filled;
        status = currentStatus == 1 && totalFilled >= pendingAmount ? 3 : 2;
    }

// Creates BuyOrderUpdate structs with correct pending amount
function _createBuyOrderUpdates(
    uint256 orderIdentifier,
    BuyOrderUpdateContext memory updateContext,
    uint256 pendingAmount
) internal pure returns (ICCListing.BuyOrderUpdate[] memory buyUpdates) {
    buyUpdates = new ICCListing.BuyOrderUpdate[](2);
    buyUpdates[0] = ICCListing.BuyOrderUpdate({
        structId: 2, // Amounts
        orderId: orderIdentifier,
        makerAddress: updateContext.makerAddress,
        recipientAddress: updateContext.recipient,
        status: updateContext.status,
        maxPrice: 0,
        minPrice: 0,
        pending: pendingAmount - updateContext.amountIn, // Fixed: remaining pending amount
        filled: updateContext.normalizedReceived,
        amountSent: updateContext.amountSent
    });
    buyUpdates[1] = ICCListing.BuyOrderUpdate({
        structId: 0, // Core
        orderId: orderIdentifier,
        makerAddress: updateContext.makerAddress,
        recipientAddress: updateContext.recipient,
        status: _computeOrderStatus(updateContext.normalizedReceived, updateContext.normalizedReceived, pendingAmount, updateContext.status),
        maxPrice: 0,
        minPrice: 0,
        pending: 0,
        filled: 0,
        amountSent: 0
    });
}

// Creates SellOrderUpdate structs with correct pending amount
function _createSellOrderUpdates(
    uint256 orderIdentifier,
    SellOrderUpdateContext memory updateContext,
    uint256 pendingAmount
) internal pure returns (ICCListing.SellOrderUpdate[] memory sellUpdates) {
    sellUpdates = new ICCListing.SellOrderUpdate[](2);
    sellUpdates[0] = ICCListing.SellOrderUpdate({
        structId: 2, // Amounts
        orderId: orderIdentifier,
        makerAddress: updateContext.makerAddress,
        recipientAddress: updateContext.recipient,
        status: updateContext.status,
        maxPrice: 0,
        minPrice: 0,
        pending: pendingAmount - updateContext.amountIn, // Fixed: remaining pending amount
        filled: updateContext.normalizedReceived,
        amountSent: updateContext.amountSent
    });
    sellUpdates[1] = ICCListing.SellOrderUpdate({
        structId: 0, // Core
        orderId: orderIdentifier,
        makerAddress: updateContext.makerAddress,
        recipientAddress: updateContext.recipient,
        status: _computeOrderStatus(updateContext.normalizedReceived, updateContext.normalizedReceived, pendingAmount, updateContext.status),
        maxPrice: 0,
        minPrice: 0,
        pending: 0,
        filled: 0,
        amountSent: 0
    });
}
}