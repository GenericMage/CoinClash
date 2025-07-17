// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.13
// Changes:
// - v0.0.13: Fixed TypeError in _executeBuyETHSwap and _executeBuyTokenSwap by adding listingContract field to BuySwapContext struct; split Uniswap-adjacent functionality into CCUniPartial.sol, importing and inheriting from it; moved CCMainPartial import to CCUniPartial.
// - v0.0.12: Refactored _executePartialBuySwap to use BuySwapContext struct and helper functions (_prepareSwapData, _executeBuyTokenSwap, _executeBuyETHSwap) to resolve stack too deep error.
// - v0.0.11: Refactored _computeMaxAmountIn to use internal call tree with helper functions (_getReserveData, _computePriceImpact, _finalizeMaxAmountIn) and MaxAmountInContext struct to resolve stack too deep error.
// - v0.0.10: Restructured _computeMaxAmountIn to reduce stack usage by computing currentPrice before conditional block.
// - v0.0.9: Replaced uniswapV2RouterView() with direct uniswapV2Router access in _executePartialBuySwap and _executePartialSellSwap.
// - v0.0.8: Removed WETH handling, using swapExactETHForTokens for buy orders (tokenIn == address(0)) and swapExactTokensForETH for sell orders (tokenOut == address(0)).
// - v0.0.7: Updated _processBuyOrder and _processSellOrder to use pendingAmount when maxAmountIn <= pendingAmount, added ETH handling in swaps, confirmed decimal usage.
// - v0.0.6: Updated _processBuyOrder and _processSellOrder to check currentPrice against maxPrice/minPrice, replaced _computeMaxAmountIn with formula-based calculation.
// - v0.0.5: Replaced _computeImpact with _computeSwapImpact, added partial swap functions, updated order processing.
// - v0.0.4: Fixed DeclarationError by replacing executeBuyOrder with executeSingleBuyLiquid and executeSellOrder with executeSingleSellLiquid.
// - v0.0.3: Removed invalid "RECOMMENDATION:" syntax in _computeImpact, set visibility to private.
// - v0.0.2: Added PrepOrderUpdateResult struct to resolve DeclarationError in _prepBuyOrderUpdate and _prepSellOrderUpdate.
// - v0.0.1: Created CCSettlementPartial.sol by extracting order processing and liquidation functions from SSRouter.sol v0.0.61.
// - v0.0.1: Imported SSMainPartial.sol v0.0.25 for normalize, denormalize, and onlyValidListing modifier.
// - v0.0.1: Included necessary structs and interfaces from SSRouter.sol and SSSettlementPartial.sol.
// - v0.0.1: Added SafeERC20 usage for token transfers.
// Compatible with SSListingTemplate.sol (v0.0.10), SSLiquidityTemplate.sol (v0.0.6), CCUniPartial.sol (v0.0.1), SSOrderPartial.sol (v0.0.19), SSSettlementPartial.sol (v0.0.58), CCListingTemplate.sol (v0.0.2).

import "./CCUniPartial.sol";

contract CCSettlementPartial is CCUniPartial {
    using SafeERC20 for IERC20;

    struct OrderContext {
        ISSListingTemplate listingContract;
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

    function _getTokenAndDecimals(
        address listingAddress,
        bool isBuyOrder
    ) internal view returns (address tokenAddress, uint8 tokenDecimals) {
        // Retrieves token address and decimals based on order type
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
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
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
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

    function _prepareLiquidityTransaction(
        address listingAddress,
        uint256 inputAmount,
        bool isBuyOrder
    ) internal view returns (uint256 amountOut, address tokenIn, address tokenOut) {
        // Prepares liquidity transaction, calculating output amount
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        (uint256 impactPrice, uint256 computedAmountOut) = _computeSwapImpact(listingAddress, inputAmount, isBuyOrder);
        if (isBuyOrder) {
            require(xAmount >= inputAmount, "Insufficient x liquidity");
            tokenIn = listingContract.tokenB();
            tokenOut = listingContract.tokenA();
            amountOut = computedAmountOut;
        } else {
            require(yAmount >= inputAmount, "Insufficient y liquidity");
            tokenIn = listingContract.tokenA();
            tokenOut = listingContract.tokenB();
            amountOut = computedAmountOut;
        }
    }

    function _checkAndTransferPrincipal(
        address listingAddress,
        address tokenIn,
        uint256 inputAmount,
        address liquidityAddr,
        ISSListingTemplate listingContract
    ) internal returns (uint256 actualAmount, uint8 tokenDecimals) {
        // Checks and transfers principal amount, tracking actual amounts sent/received
        tokenDecimals = tokenIn == address(0) ? 18 : IERC20(tokenIn).decimals();
        uint256 listingPreBalance = tokenIn == address(0)
            ? listingAddress.balance
            : IERC20(tokenIn).balanceOf(listingAddress);
        uint256 liquidityPreBalance = tokenIn == address(0)
            ? liquidityAddr.balance
            : IERC20(tokenIn).balanceOf(liquidityAddr);
        if (tokenIn == address(0)) {
            try listingContract.transact{value: inputAmount}(address(this), address(0), inputAmount, liquidityAddr) {} catch {
                revert("Principal transfer failed");
            }
        } else {
            try listingContract.transact(address(this), tokenIn, inputAmount, liquidityAddr) {} catch {
                revert("Principal transfer failed");
            }
        }
        uint256 listingPostBalance = tokenIn == address(0)
            ? listingAddress.balance
            : IERC20(tokenIn).balanceOf(listingAddress);
        uint256 liquidityPostBalance = tokenIn == address(0)
            ? liquidityAddr.balance
            : IERC20(tokenIn).balanceOf(liquidityAddr);
        uint256 amountSent = listingPreBalance > listingPostBalance 
            ? listingPreBalance - listingPostBalance 
            : 0;
        uint256 amountReceived = liquidityPostBalance > liquidityPreBalance 
            ? liquidityPostBalance - liquidityPreBalance 
            : 0;
        require(amountSent > 0, "No amount sent from listing");
        require(amountReceived > 0, "No amount received by liquidity");
        actualAmount = amountSent < amountReceived ? amountSent : amountReceived;
    }

    function _updateLiquidity(
        address listingAddress,
        address tokenIn,
        bool isX,
        uint256 inputAmount
    ) internal {
        // Updates liquidity pool with transferred tokens
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        uint256 actualAmount;
        uint8 tokenDecimals;
        (actualAmount, tokenDecimals) = _checkAndTransferPrincipal(
            address(listingAddress),
            tokenIn,
            inputAmount,
            liquidityAddr,
            listingContract
        );
        uint256 normalizedAmount = normalize(actualAmount, tokenDecimals);
        require(normalizedAmount > 0, "Normalized amount is zero");
        try liquidityContract.updateLiquidity(address(this), isX, normalizedAmount) {} catch {
            revert("Liquidity update failed");
        }
    }

    function _computeAmountSent(
        address tokenAddress,
        address recipientAddress,
        uint256 amount
    ) internal view returns (uint256) {
        // Computes actual tokens sent by checking recipient balance changes
        uint256 preBalance = tokenAddress == address(0)
            ? recipientAddress.balance
            : IERC20(tokenAddress).balanceOf(recipientAddress);
        uint256 postBalance = preBalance; // Placeholder, actual logic depends on transfer
        return postBalance > preBalance ? postBalance - preBalance : 0;
    }

    function _prepBuyOrderUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountOut
    ) internal returns (PrepOrderUpdateResult memory result) {
        // Prepares buy order update data, including token transfer
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        (result.tokenAddress, result.tokenDecimals) = _getTokenAndDecimals(listingAddress, true);
        (result.makerAddress, result.recipientAddress, result.orderStatus) = listingContract.getBuyOrderCore(orderIdentifier);
        uint256 denormalizedAmount = denormalize(amountOut, result.tokenDecimals);
        try listingContract.transact(address(this), result.tokenAddress, denormalizedAmount, result.recipientAddress) {} catch {
            result.amountReceived = 0;
            result.normalizedReceived = 0;
        }
        if (result.amountReceived > 0) {
            result.normalizedReceived = normalize(result.amountReceived, result.tokenDecimals);
        }
        result.amountSent = _computeAmountSent(result.tokenAddress, result.recipientAddress, denormalizedAmount);
    }

    function _prepSellOrderUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountOut
    ) internal returns (PrepOrderUpdateResult memory result) {
        // Prepares sell order update data, including token transfer
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        (result.tokenAddress, result.tokenDecimals) = _getTokenAndDecimals(listingAddress, false);
        (result.recipientAddress, result.makerAddress, result.orderStatus) = listingContract.getSellOrderCore(orderIdentifier);
        uint256 denormalizedAmount = denormalize(amountOut, result.tokenDecimals);
        try listingContract.transact(address(this), result.tokenAddress, denormalizedAmount, result.recipientAddress) {} catch {
            result.amountReceived = 0;
            result.normalizedReceived = 0;
        }
        if (result.amountReceived > 0) {
            result.normalizedReceived = normalize(result.amountReceived, result.tokenDecimals);
        }
        result.amountSent = _computeAmountSent(result.tokenAddress, result.recipientAddress, denormalizedAmount);
    }

    function _prepBuyLiquidUpdates(
        OrderContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        // Prepares updates for buy order liquidation
        if (!_checkPricing(address(context.listingContract), orderIdentifier, true, pendingAmount)) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        uint256 amountOut;
        address tokenIn;
        address tokenOut;
        {
            (amountOut, tokenIn, tokenOut) = _prepareLiquidityTransaction(
                address(context.listingContract),
                pendingAmount,
                true
            );
        }
        BuyOrderUpdateContext memory updateContext;
        {
            PrepOrderUpdateResult memory prepResult = _prepBuyOrderUpdate(
                address(context.listingContract),
                orderIdentifier,
                amountOut
            );
            updateContext.makerAddress = prepResult.makerAddress;
            updateContext.recipient = prepResult.recipientAddress;
            updateContext.status = prepResult.orderStatus;
            updateContext.amountReceived = prepResult.amountReceived;
            updateContext.normalizedReceived = prepResult.normalizedReceived;
            updateContext.amountSent = prepResult.amountSent;
            uint8 tokenDecimals = prepResult.tokenDecimals;
            uint256 denormalizedAmount = denormalize(amountOut, tokenDecimals);
            try ISSLiquidityTemplate(context.liquidityAddr).transact(address(this), tokenOut, denormalizedAmount, updateContext.recipient) {} catch {
                return new ISSListingTemplate.UpdateType[](0);
            }
            updateContext.amountReceived = denormalizedAmount;
            updateContext.normalizedReceived = normalize(denormalizedAmount, tokenDecimals);
            updateContext.amountSent = _computeAmountSent(tokenOut, updateContext.recipient, denormalizedAmount);
        }
        if (updateContext.normalizedReceived == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        _updateLiquidity(address(context.listingContract), tokenIn, false, pendingAmount);
        return _createBuyOrderUpdates(orderIdentifier, updateContext, pendingAmount);
    }

    function _prepSellLiquidUpdates(
        OrderContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        // Prepares updates for sell order liquidation
        if (!_checkPricing(address(context.listingContract), orderIdentifier, false, pendingAmount)) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        uint256 amountOut;
        address tokenIn;
        address tokenOut;
        {
            (amountOut, tokenIn, tokenOut) = _prepareLiquidityTransaction(
                address(context.listingContract),
                pendingAmount,
                false
            );
        }
        SellOrderUpdateContext memory updateContext;
        {
            PrepOrderUpdateResult memory prepResult = _prepSellOrderUpdate(
                address(context.listingContract),
                orderIdentifier,
                amountOut
            );
            updateContext.makerAddress = prepResult.makerAddress;
            updateContext.recipient = prepResult.recipientAddress;
            updateContext.status = prepResult.orderStatus;
            updateContext.amountReceived = prepResult.amountReceived;
            updateContext.normalizedReceived = prepResult.normalizedReceived;
            updateContext.amountSent = prepResult.amountSent;
            uint8 tokenDecimals = prepResult.tokenDecimals;
            uint256 denormalizedAmount = denormalize(amountOut, tokenDecimals);
            try ISSLiquidityTemplate(context.liquidityAddr).transact(address(this), tokenOut, denormalizedAmount, updateContext.recipient) {} catch {
                return new ISSListingTemplate.UpdateType[](0);
            }
            updateContext.amountReceived = denormalizedAmount;
            updateContext.normalizedReceived = normalize(denormalizedAmount, tokenDecimals);
            updateContext.amountSent = _computeAmountSent(tokenOut, updateContext.recipient, denormalizedAmount);
        }
        if (updateContext.normalizedReceived == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        _updateLiquidity(address(context.listingContract), tokenIn, true, pendingAmount);
        return _createSellOrderUpdates(orderIdentifier, updateContext, pendingAmount);
    }

    function _processBuyOrder(
        address listingAddress,
        uint256 orderIdentifier,
        ISSListingTemplate listingContract
    ) internal returns (ISSListingTemplate.UpdateType[] memory updates) {
        // Processes a single buy order using Uniswap V2 swap, uses pendingAmount if maxAmountIn <= pendingAmount
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.getBuyOrderAmounts(orderIdentifier);
        if (pendingAmount == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        (uint256 maxPrice, uint256 minPrice) = listingContract.getBuyOrderPricing(orderIdentifier);
        uint256 currentPrice = _computeCurrentPrice(listingAddress);
        if (currentPrice < minPrice || currentPrice > maxPrice) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        uint256 maxAmountIn = _computeMaxAmountIn(listingAddress, maxPrice, minPrice, pendingAmount, true);
        uint256 swapAmount = maxAmountIn >= pendingAmount ? pendingAmount : maxAmountIn;
        if (swapAmount == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        updates = _executePartialBuySwap(listingAddress, orderIdentifier, swapAmount, pendingAmount);
    }

    function _processSellOrder(
        address listingAddress,
        uint256 orderIdentifier,
        ISSListingTemplate listingContract
    ) internal returns (ISSListingTemplate.UpdateType[] memory updates) {
        // Processes a single sell order using Uniswap V2 swap, uses pendingAmount if maxAmountIn <= pendingAmount
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.getSellOrderAmounts(orderIdentifier);
        if (pendingAmount == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        (uint256 maxPrice, uint256 minPrice) = listingContract.getSellOrderPricing(orderIdentifier);
        uint256 currentPrice = _computeCurrentPrice(listingAddress);
        if (currentPrice < minPrice || currentPrice > maxPrice) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        uint256 maxAmountIn = _computeMaxAmountIn(listingAddress, maxPrice, minPrice, pendingAmount, false);
        uint256 swapAmount = maxAmountIn >= pendingAmount ? pendingAmount : maxAmountIn;
        if (swapAmount == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        updates = _executePartialSellSwap(listingAddress, orderIdentifier, swapAmount, pendingAmount);
    }

    function executeSingleBuyLiquid(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        // Executes a single buy order liquidation
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.getBuyOrderAmounts(orderIdentifier);
        if (pendingAmount == 0) {
            return new ISSListingTemplate.UpdateType[](0);
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
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        // Executes a single sell order liquidation
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.getSellOrderAmounts(orderIdentifier);
        if (pendingAmount == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        OrderContext memory context = OrderContext({
            listingContract: listingContract,
            tokenIn: listingContract.tokenA(),
            tokenOut: listingContract.tokenB(),
            liquidityAddr: listingContract.liquidityAddressView()
        });
        return _prepSellLiquidUpdates(context, orderIdentifier, pendingAmount);
    }
}