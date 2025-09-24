/*
 SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
 * Version: 0.0.46
 * Changes:
 * - v0.0.46: Added 0.01% minimum fee and 10% maximum fee in _computeFee.
- v0.0.45: Updated _prepBuyLiquidUpdates and _prepSellLiquidUpdates to pass amountOut to _prepBuyOrderUpdate and _prepSellOrderUpdate, resolving parameter mismatch.
 - v0.0.45: Fixed TypeError in _processSingleOrder by passing amountOut to _prepBuyOrderUpdate and _prepSellOrderUpdate. Ensured amountSent uses pre/post balance checks.
 - v0.0.44: Added status field to PrepOrderUpdateResult struct. Updated _prepBuyOrderUpdate and _prepSellOrderUpdate to handle status correctly, fixing TypeError. Ensured amountSent uses pre/post balance checks. 
 - v0.0.43: Fixed TypeError by updating _prepBuyOrderUpdate and _prepSellOrderUpdate to return PrepOrderUpdateResult, added amountOut parameter, aligned with CCLiquidPartial.sol v0.0.41. Fixed amountSent with pre/post balance checks.
 - v0.0.42: Fixed amountSent in _prepBuyOrderUpdate and _prepSellOrderUpdate to use pre/post balance checks for accurate settlement tracking. Commented in _prepLiquidityUpdates about token usage. (Sept 16 '24)
 - v0.0.41: Removed redundant liquidity updates in _prepBuyOrderUpdate and _prepSellOrderUpdate to prevent double-counting. Consolidated token transfers to _prepareLiquidityUpdates, ensuring single execution of transactToken/transactNative. Compatible with CCListingTemplate.sol v0.3.9, CCMainPartial.sol v0.1.5, CCLiquidityTemplate.sol v0.1.18, CCLiquidRouter.sol v0.0.25.
- v0.0.40: Fixed _prepareLiquidityUpdates to correctly update yLiquid (index 1) for buy orders and xLiquid (index 0) for sell orders. Updated _createBuyOrderUpdates and _createSellOrderUpdates to use transactToken for ERC20 and transactNative for ETH. Fixed status calculation to check pendingAmount - preTransferWithdrawn > 0 for partial fills. Updated _executeOrderWithFees to capture current historical volume from listingContract without incrementing, preventing double-counting with CCListingTemplate.sol. Compatible with CCListingTemplate.sol v0.3.9, CCMainPartial.sol v0.1.5, CCLiquidityTemplate.sol v0.1.18, CCLiquidRouter.sol v0.0.25.
- v0.0.39: Added reverts for critical errors in _executeOrderWithFees and _prepareLiquidityUpdates. Added pre-settlement validation in _processSingleOrder to skip orders with invalid pricing or insufficient x/yLiquid. Ensured transactToken/transactNative only use available x/yLiquid. Non-critical errors (e.g., no orders) remain non-reverting. Compatible with CCListingTemplate.sol v0.3.9, CCMainPartial.sol v0.1.5, CCLiquidityTemplate.sol v0.1.18, CCLiquidRouter.sol v0.0.25.
- v0.0.38: Updated _createBuyOrderUpdates, _createSellOrderUpdates, _prepBuyLiquidUpdates, and _prepSellLiquidUpdates to use CCListingTemplate.sol v0.3.9 ccUpdate with BuyOrderUpdate, SellOrderUpdate structs. Ensured compatibility with CCLiquidRouter.sol v0.0.25.
 - v0.0.37: Optimized CCLiquidPartial.sol by removing unused params and local variables, streamlined structs (removed unused fields in OrderContext, PrepOrderUpdateResult), consolidated repetitive logic in _prepareLiquidityUpdates and _executeOrderWithFees, reduced file size by ~6KB. Maintained compatibility with CCListingTemplate.sol v0.3.2, CCMainPartial.sol v0.1.5, CCLiquidityTemplate.sol v0.1.18, CCLiquidRouter.sol v0.0.24.
 - v0.0.36: Updated _prepareLiquidityUpdates, _executeOrderWithFees, _processOrderBatch to call ccUpdate individually for each update type.
 - v0.0.35: Removed duplicate _computeFee, retained _computeFee (v0.0.34) for stack efficiency. Updated _prepareLiquidityUpdates to use new _computeFee. Maintained fee transfer, correct liquidity updates.
 - v0.0.34: Refactored _computeFeeAndLiquidity to resolve stack issues by splitting into _computeFee, _computeSwapAmount, _prepareLiquidityUpdates. Added LiquidityUpdateContext.
 - v0.0.33: Fixed fee transfer, corrected liquidity updates, fixed TypeError in _executeOrderWithFees.
 - v0.0.32: Refactored _processSingleOrder to resolve stack issues with _validateOrderPricing, _computeFeeAndLiquidity, _executeOrderWithFees. Added OrderProcessingContext.
 - v0.0.31: Added _computeFee for liquidity-based fees (max 1%). Modified _processSingleOrder to deduct fees and update xFees/yFees via ccUpdate. Updated _collectOrderIdentifiers to use makerPendingOrdersView. Added FeeDeducted event.
 - v0.0.30: Updated _updateLiquidityBalances to align with CCLiquidityTemplate.sol v0.1.18 for ccUpdate compatibility.
 - v0.0.29: Refactored _createBuy/SellOrderUpdates to resolve stack issues with helper functions (_prepareCoreUpdate, _prepareAmountsUpdate, _prepareBalanceUpdate).
 - v0.0.28: Updated _createBuy/SellOrderUpdates to use ccUpdate with three arrays, fetching maker/recipient, updating pending/filled, amountSent via balance checks.
 - v0.0.27: Clarified amountSent for settlement.
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
    }

    struct PrepOrderUpdateResult {
    address tokenAddress;
    uint8 tokenDecimals;
    address makerAddress;
    address recipientAddress;
    uint256 amountReceived;
    uint256 normalizedReceived;
    uint256 amountSent;
    uint256 preTransferWithdrawn;
    uint8 status; // Added to store order status
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
        uint256 amountInAfterFee;
        uint256 price;
        uint256 amountOut;
    }

    struct FeeContext {
        uint256 feeAmount;
        uint256 netAmount;
        uint256 liquidityAmount;
        uint8 decimals;
    }

    struct OrderProcessingContext {
        uint256 maxPrice;
        uint256 minPrice;
        uint256 currentPrice;
        uint256 impactPrice;
    }

    struct LiquidityUpdateContext {
        uint256 pendingAmount;
        uint256 amountOut;
        uint8 tokenDecimals;
        bool isBuyOrder;
    }

    event FeeDeducted(address indexed listingAddress, uint256 orderId, bool isBuyOrder, uint256 feeAmount, uint256 netAmount);
    event PriceOutOfBounds(address indexed listingAddress, uint256 orderId, uint256 impactPrice, uint256 maxPrice, uint256 minPrice);
    event MissingUniswapRouter(address indexed listingAddress, uint256 orderId, string reason);
    event TokenTransferFailed(address indexed listingAddress, uint256 orderId, address token, string reason);
    event SwapFailed(address indexed listingAddress, uint256 orderId, uint256 amountIn, string reason);
    event ApprovalFailed(address indexed listingAddress, uint256 orderId, address token, string reason);
    event UpdateFailed(address indexed listingAddress, string reason);
    event InsufficientBalance(address indexed listingAddress, uint256 required, uint256 available);
    
    function _getSwapReserves(address listingAddress, bool isBuyOrder) private view returns (SwapImpactContext memory context) {
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
        context.amountInAfterFee = 0; // Initialized to avoid unused warning
        context.price = 0; // Initialized to avoid unused warning
        context.amountOut = 0; // Initialized to avoid unused warning
    }

    function _computeCurrentPrice(address listingAddress) private view returns (uint256 price) {
        ICCListing listingContract = ICCListing(listingAddress);
        try listingContract.prices(0) returns (uint256 _price) {
            require(_price > 0, "Invalid price from listing");
            price = _price;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Price fetch failed: ", reason)));
        }
    }

    function _computeSwapImpact(address listingAddress, uint256 amountIn, bool isBuyOrder) private view returns (uint256 price, uint256 amountOut) {
        SwapImpactContext memory context = _getSwapReserves(listingAddress, isBuyOrder);
        require(context.reserveIn > 0 && context.reserveOut > 0, "Zero reserves");
        context.amountInAfterFee = (amountIn * 997) / 1000;
        uint256 normalizedReserveIn = normalize(context.reserveIn, context.decimalsIn);
        uint256 normalizedReserveOut = normalize(context.reserveOut, context.decimalsOut);
        context.amountOut = (context.amountInAfterFee * normalizedReserveOut) / (normalizedReserveIn + context.amountInAfterFee);
        context.price = normalizedReserveOut > context.amountOut
            ? ((normalizedReserveIn + context.amountInAfterFee) * 1e18) / (normalizedReserveOut - context.amountOut)
            : type(uint256).max;
        amountOut = denormalize(context.amountOut, context.decimalsOut);
        price = context.price;
    }

    function _getTokenAndDecimals(address listingAddress, bool isBuyOrder) private view returns (address tokenAddress, uint8 tokenDecimals) {
        ICCListing listingContract = ICCListing(listingAddress);
        tokenAddress = isBuyOrder ? listingContract.tokenB() : listingContract.tokenA();
        tokenDecimals = isBuyOrder ? listingContract.decimalsB() : listingContract.decimalsA();
    }

    function _checkPricing(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, uint256 pendingAmount) private view returns (bool) {
        ICCListing listingContract = ICCListing(listingAddress);
        (uint256 maxPrice, uint256 minPrice) = isBuyOrder
            ? listingContract.getBuyOrderPricing(orderIdentifier)
            : listingContract.getSellOrderPricing(orderIdentifier);
        (uint256 impactPrice,) = _computeSwapImpact(listingAddress, pendingAmount, isBuyOrder);
        return impactPrice <= maxPrice && impactPrice >= minPrice;
    }

    function _computeAmountSent(address tokenAddress, address recipientAddress, uint256 amount) private view returns (uint256 preBalance) {
        preBalance = tokenAddress == address(0)
            ? recipientAddress.balance
            : IERC20(tokenAddress).balanceOf(recipientAddress);
    }

    function _prepareLiquidityTransaction(address listingAddress, uint256 inputAmount, bool isBuyOrder) private view returns (uint256 amountOut, address tokenIn, address tokenOut) {
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        (, uint256 computedAmountOut) = _computeSwapImpact(listingAddress, inputAmount, isBuyOrder);
        amountOut = computedAmountOut;
        tokenIn = isBuyOrder ? listingContract.tokenB() : listingContract.tokenA();
        tokenOut = isBuyOrder ? listingContract.tokenA() : listingContract.tokenB();
        require(isBuyOrder ? yAmount >= inputAmount : xAmount >= inputAmount, "Insufficient liquidity");
        require(isBuyOrder ? xAmount >= amountOut : yAmount >= amountOut, "Insufficient output liquidity");
    }

    function _prepareCoreUpdate(uint256 orderIdentifier, address listingAddress, bool isBuyOrder, uint8 status) private view returns (uint8 updateType, uint8 updateSort, uint256 updateData) {
        ICCListing listingContract = ICCListing(listingAddress);
        (address maker, address recipient,) = isBuyOrder
            ? listingContract.getBuyOrderCore(orderIdentifier)
            : listingContract.getSellOrderCore(orderIdentifier);
        updateType = isBuyOrder ? 1 : 2;
        updateSort = 0;
        updateData = uint256(bytes32(abi.encode(maker, recipient, status)));
    }

    function _prepareAmountsUpdate(uint256 orderIdentifier, address listingAddress, bool isBuyOrder, uint256 preTransferWithdrawn, uint256 amountSent) private view returns (uint8 updateType, uint8 updateSort, uint256 updateData) {
        ICCListing listingContract = ICCListing(listingAddress);
        (uint256 pending, uint256 filled,) = isBuyOrder
            ? listingContract.getBuyOrderAmounts(orderIdentifier)
            : listingContract.getSellOrderAmounts(orderIdentifier);
        uint256 newPending = pending >= preTransferWithdrawn ? pending - preTransferWithdrawn : 0;
        uint256 newFilled = filled + preTransferWithdrawn;
        updateType = isBuyOrder ? 1 : 2;
        updateSort = 2;
        updateData = uint256(bytes32(abi.encode(newPending, newFilled, amountSent)));
    }

    function _prepareBalanceUpdate(uint256 normalizedReceived, bool isBuyOrder) private pure returns (uint8 updateType, uint8 updateSort, uint256 updateData) {
        updateType = 0;
        updateSort = 0;
        updateData = normalizedReceived;
    }

    function _createBuyOrderUpdates(uint256 orderIdentifier, BuyOrderUpdateContext memory context, uint256 pendingAmount) private view returns (ICCListing.BuyOrderUpdate[] memory updates) {
    // Creates buy order updates, uses explicit status logic
    updates = new ICCListing.BuyOrderUpdate[](2);
    uint8 newStatus = pendingAmount == 0 ? 0 : (context.preTransferWithdrawn >= pendingAmount ? 3 : 2);
    updates[0] = ICCListing.BuyOrderUpdate({
        structId: 0,
        orderId: orderIdentifier,
        makerAddress: context.makerAddress,
        recipientAddress: context.recipient,
        status: newStatus,
        maxPrice: 0,
        minPrice: 0,
        pending: 0,
        filled: 0,
        amountSent: 0
    });
    updates[1] = ICCListing.BuyOrderUpdate({
        structId: 2,
        orderId: orderIdentifier,
        makerAddress: address(0),
        recipientAddress: address(0),
        status: 0,
        maxPrice: 0,
        minPrice: 0,
        pending: pendingAmount >= context.preTransferWithdrawn ? pendingAmount - context.preTransferWithdrawn : 0,
        filled: context.preTransferWithdrawn,
        amountSent: context.amountSent
    });
}

function _createSellOrderUpdates(uint256 orderIdentifier, SellOrderUpdateContext memory context, uint256 pendingAmount) private view returns (ICCListing.SellOrderUpdate[] memory updates) {
    // Creates sell order updates, uses explicit status logic
    updates = new ICCListing.SellOrderUpdate[](2);
    uint8 newStatus = pendingAmount == 0 ? 0 : (context.preTransferWithdrawn >= pendingAmount ? 3 : 2);
    updates[0] = ICCListing.SellOrderUpdate({
        structId: 0,
        orderId: orderIdentifier,
        makerAddress: context.makerAddress,
        recipientAddress: context.recipient,
        status: newStatus,
        maxPrice: 0,
        minPrice: 0,
        pending: 0,
        filled: 0,
        amountSent: 0
    });
    updates[1] = ICCListing.SellOrderUpdate({
        structId: 2,
        orderId: orderIdentifier,
        makerAddress: address(0),
        recipientAddress: address(0),
        status: 0,
        maxPrice: 0,
        minPrice: 0,
        pending: pendingAmount >= context.preTransferWithdrawn ? pendingAmount - context.preTransferWithdrawn : 0,
        filled: context.preTransferWithdrawn,
        amountSent: context.amountSent
    });
}

    function _prepBuyOrderUpdate(
    address listingAddress,
    uint256 orderId,
    uint256 pendingAmount,
    uint256 amountOut
) private returns (PrepOrderUpdateResult memory result) {
    // Prepares buy order update with accurate amountSent and status
    ICCListing listingContract = ICCListing(listingAddress);
    (result.makerAddress, result.recipientAddress, result.status) = listingContract.getBuyOrderCore(orderId);
    result.tokenAddress = listingContract.tokenA();
    result.tokenDecimals = listingContract.decimalsA();
    result.amountReceived = amountOut;
    result.normalizedReceived = normalize(amountOut, result.tokenDecimals);
    
    // Pre/post balance check for amountSent
    uint256 balanceBefore = result.tokenAddress == address(0) 
        ? result.recipientAddress.balance 
        : IERC20(result.tokenAddress).balanceOf(result.recipientAddress);
    try listingContract.transactToken(result.tokenAddress, amountOut, result.recipientAddress) {} catch Error(string memory reason) {
        revert(string(abi.encodePacked("Token transfer failed: ", reason)));
    }
    uint256 balanceAfter = result.tokenAddress == address(0) 
        ? result.recipientAddress.balance 
        : IERC20(result.tokenAddress).balanceOf(result.recipientAddress);
    result.amountSent = balanceBefore > balanceAfter ? 0 : balanceAfter - balanceBefore;
    result.preTransferWithdrawn = result.amountSent >= result.amountReceived ? result.amountReceived : result.amountSent;
    result.status = result.status == 3 ? 3 : (pendingAmount - result.preTransferWithdrawn > 0 ? 2 : 3);
}

function _prepSellOrderUpdate(
    address listingAddress,
    uint256 orderId,
    uint256 pendingAmount,
    uint256 amountOut
) private returns (PrepOrderUpdateResult memory result) {
    // Prepares sell order update with accurate amountSent and status
    ICCListing listingContract = ICCListing(listingAddress);
    (result.makerAddress, result.recipientAddress, result.status) = listingContract.getSellOrderCore(orderId);
    result.tokenAddress = listingContract.tokenB();
    result.tokenDecimals = listingContract.decimalsB();
    result.amountReceived = amountOut;
    result.normalizedReceived = normalize(amountOut, result.tokenDecimals);
    
    // Pre/post balance check for amountSent
    uint256 balanceBefore = result.tokenAddress == address(0) 
        ? result.recipientAddress.balance 
        : IERC20(result.tokenAddress).balanceOf(result.recipientAddress);
    try listingContract.transactToken(result.tokenAddress, amountOut, result.recipientAddress) {} catch Error(string memory reason) {
        revert(string(abi.encodePacked("Token transfer failed: ", reason)));
    }
    uint256 balanceAfter = result.tokenAddress == address(0) 
        ? result.recipientAddress.balance 
        : IERC20(result.tokenAddress).balanceOf(result.recipientAddress);
    result.amountSent = balanceBefore > balanceAfter ? 0 : balanceAfter - balanceBefore;
    result.preTransferWithdrawn = result.amountSent >= result.amountReceived ? result.amountReceived : result.amountSent;
    result.status = result.status == 3 ? 3 : (pendingAmount - result.preTransferWithdrawn > 0 ? 2 : 3);
}

    function _prepBuyLiquidUpdates(OrderContext memory context, uint256 orderIdentifier, uint256 pendingAmount) private returns (bool success) {
    // Prepares and executes buy order updates, returns success status
    if (uniswapV2Router == address(0)) {
        emit MissingUniswapRouter(address(context.listingContract), orderIdentifier, "Uniswap router not set");
        return false;
    }
    (, uint256 amountOut) = _computeSwapImpact(address(context.listingContract), pendingAmount, true);
    PrepOrderUpdateResult memory result = _prepBuyOrderUpdate(address(context.listingContract), orderIdentifier, pendingAmount, amountOut);
    if (result.normalizedReceived == 0) {
        emit SwapFailed(address(context.listingContract), orderIdentifier, pendingAmount, "No tokens received");
        return false;
    }
    BuyOrderUpdateContext memory updateContext = BuyOrderUpdateContext({
        makerAddress: result.makerAddress,
        recipient: result.recipientAddress,
        status: result.status,
        amountReceived: result.amountReceived,
        normalizedReceived: result.normalizedReceived,
        amountSent: result.amountSent,
        preTransferWithdrawn: result.preTransferWithdrawn
    });
    ICCListing.BuyOrderUpdate[] memory buyUpdates = _createBuyOrderUpdates(orderIdentifier, updateContext, pendingAmount);
    ICCListing.SellOrderUpdate[] memory sellUpdates = new ICCListing.SellOrderUpdate[](0);
    ICCListing.BalanceUpdate[] memory balanceUpdates = new ICCListing.BalanceUpdate[](0);
    ICCListing.HistoricalUpdate[] memory historicalUpdates = new ICCListing.HistoricalUpdate[](0);
    try context.listingContract.ccUpdate(buyUpdates, sellUpdates, balanceUpdates, historicalUpdates) {
        success = true;
    } catch Error(string memory reason) {
        emit UpdateFailed(address(context.listingContract), reason);
        success = false;
    }
}

function _prepSellLiquidUpdates(OrderContext memory context, uint256 orderIdentifier, uint256 pendingAmount) private returns (bool success) {
    // Prepares and executes sell order updates, returns success status
    if (uniswapV2Router == address(0)) {
        emit MissingUniswapRouter(address(context.listingContract), orderIdentifier, "Uniswap router not set");
        return false;
    }
    (, uint256 amountOut) = _computeSwapImpact(address(context.listingContract), pendingAmount, false);
    PrepOrderUpdateResult memory result = _prepSellOrderUpdate(address(context.listingContract), orderIdentifier, pendingAmount, amountOut);
    if (result.normalizedReceived == 0) {
        emit SwapFailed(address(context.listingContract), orderIdentifier, pendingAmount, "No tokens received");
        return false;
    }
    SellOrderUpdateContext memory updateContext = SellOrderUpdateContext({
        makerAddress: result.makerAddress,
        recipient: result.recipientAddress,
        status: result.status,
        amountReceived: result.amountReceived,
        normalizedReceived: result.normalizedReceived,
        amountSent: result.amountSent,
        preTransferWithdrawn: result.preTransferWithdrawn
    });
    ICCListing.SellOrderUpdate[] memory sellUpdates = _createSellOrderUpdates(orderIdentifier, updateContext, pendingAmount);
    ICCListing.BuyOrderUpdate[] memory buyUpdates = new ICCListing.BuyOrderUpdate[](0);
    ICCListing.BalanceUpdate[] memory balanceUpdates = new ICCListing.BalanceUpdate[](0);
    ICCListing.HistoricalUpdate[] memory historicalUpdates = new ICCListing.HistoricalUpdate[](0);
    try context.listingContract.ccUpdate(buyUpdates, sellUpdates, balanceUpdates, historicalUpdates) {
        success = true;
    } catch Error(string memory reason) {
        emit UpdateFailed(address(context.listingContract), reason);
        success = false;
    }
}

    function executeSingleBuyLiquid(address listingAddress, uint256 orderIdentifier) internal returns (bool success) {
    // Executes single buy order update, returns success status
    ICCListing listingContract = ICCListing(listingAddress);
    (address maker, address recipient, uint8 status) = listingContract.getBuyOrderCore(orderIdentifier);
    (uint256 pending,,) = listingContract.getBuyOrderAmounts(orderIdentifier);
    BuyOrderUpdateContext memory context = BuyOrderUpdateContext({
        makerAddress: maker,
        recipient: recipient,
        status: status,
        amountReceived: 0,
        normalizedReceived: 0,
        amountSent: 0,
        preTransferWithdrawn: 0
    });
    ICCListing.BuyOrderUpdate[] memory updates = _createBuyOrderUpdates(orderIdentifier, context, pending);
    ICCListing.SellOrderUpdate[] memory sellUpdates = new ICCListing.SellOrderUpdate[](0);
    ICCListing.BalanceUpdate[] memory balanceUpdates = new ICCListing.BalanceUpdate[](0);
    ICCListing.HistoricalUpdate[] memory historicalUpdates = new ICCListing.HistoricalUpdate[](0);
    try listingContract.ccUpdate(updates, sellUpdates, balanceUpdates, historicalUpdates) {
        success = true;
    } catch Error(string memory reason) {
        emit UpdateFailed(listingAddress, string(abi.encodePacked("Buy order update failed: ", reason)));
        success = false;
    }
}

function executeSingleSellLiquid(address listingAddress, uint256 orderIdentifier) internal returns (bool success) {
    // Executes single sell order update, returns success status
    ICCListing listingContract = ICCListing(listingAddress);
    (address maker, address recipient, uint8 status) = listingContract.getSellOrderCore(orderIdentifier);
    (uint256 pending,,) = listingContract.getSellOrderAmounts(orderIdentifier);
    SellOrderUpdateContext memory context = SellOrderUpdateContext({
        makerAddress: maker,
        recipient: recipient,
        status: status,
        amountReceived: 0,
        normalizedReceived: 0,
        amountSent: 0,
        preTransferWithdrawn: 0
    });
    ICCListing.SellOrderUpdate[] memory updates = _createSellOrderUpdates(orderIdentifier, context, pending);
    ICCListing.BuyOrderUpdate[] memory buyUpdates = new ICCListing.BuyOrderUpdate[](0);
    ICCListing.BalanceUpdate[] memory balanceUpdates = new ICCListing.BalanceUpdate[](0);
    ICCListing.HistoricalUpdate[] memory historicalUpdates = new ICCListing.HistoricalUpdate[](0);
    try listingContract.ccUpdate(buyUpdates, updates, balanceUpdates, historicalUpdates) {
        success = true;
    } catch Error(string memory reason) {
        emit UpdateFailed(listingAddress, string(abi.encodePacked("Sell order update failed: ", reason)));
        success = false;
    }
}

    function _collectOrderIdentifiers(address listingAddress, uint256 maxIterations, bool isBuyOrder, uint256 step) internal view returns (uint256[] memory orderIdentifiers, uint256 iterationCount) {
        ICCListing listingContract = ICCListing(listingAddress);
        uint256[] memory identifiers = listingContract.makerPendingOrdersView(msg.sender);
        require(step <= identifiers.length, "Step exceeds pending orders length");
        uint256 remainingOrders = identifiers.length - step;
        iterationCount = maxIterations < remainingOrders ? maxIterations : remainingOrders;
        orderIdentifiers = new uint256[](iterationCount);
        for (uint256 i = 0; i < iterationCount; i++) {
            orderIdentifiers[i] = identifiers[step + i];
        }
    }

    function _updateLiquidityBalances(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, uint256 pendingAmount, uint256 settleAmount) private {
        ICCListing listingContract = ICCListing(listingAddress);
        ICCLiquidity liquidityContract = ICCLiquidity(listingContract.liquidityAddressView());
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        uint256 normalizedPending = normalize(pendingAmount, isBuyOrder ? listingContract.decimalsB() : listingContract.decimalsA());
        uint256 normalizedSettle = normalize(settleAmount, isBuyOrder ? listingContract.decimalsA() : listingContract.decimalsB());
        ICCLiquidity.UpdateType[] memory liquidityUpdates = new ICCLiquidity.UpdateType[](2);
        liquidityUpdates[0] = ICCLiquidity.UpdateType({
            updateType: 0,
            index: isBuyOrder ? 1 : 0,
            value: isBuyOrder ? yAmount - normalizedPending : xAmount - normalizedPending,
            addr: address(this),
            recipient: address(0)
        });
        liquidityUpdates[1] = ICCLiquidity.UpdateType({
            updateType: 0,
            index: isBuyOrder ? 0 : 1,
            value: isBuyOrder ? xAmount + normalizedSettle : yAmount + normalizedSettle,
            addr: address(this),
            recipient: address(0)
        });
        try liquidityContract.ccUpdate(address(this), liquidityUpdates) {} catch (bytes memory reason) {
            emit SwapFailed(listingAddress, orderIdentifier, pendingAmount, string(abi.encodePacked("Liquidity update failed: ", reason)));
        }
    }

    function _validateOrderPricing(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, uint256 pendingAmount) private returns (OrderProcessingContext memory context) {
        ICCListing listingContract = ICCListing(listingAddress);
        (context.maxPrice, context.minPrice) = isBuyOrder
            ? listingContract.getBuyOrderPricing(orderIdentifier)
            : listingContract.getSellOrderPricing(orderIdentifier);
        context.currentPrice = _computeCurrentPrice(listingAddress);
        (context.impactPrice,) = _computeSwapImpact(listingAddress, pendingAmount, isBuyOrder);
        if (!(context.impactPrice >= context.minPrice && context.impactPrice <= context.maxPrice && 
              context.currentPrice >= context.minPrice && context.currentPrice <= context.maxPrice)) {
            emit PriceOutOfBounds(listingAddress, orderIdentifier, context.impactPrice, context.maxPrice, context.minPrice);
            context.impactPrice = 0;
        }
    }

    function _computeFee(address listingAddress, uint256 pendingAmount, bool isBuyOrder) private view returns (FeeContext memory feeContext) {
    ICCListing listingContract = ICCListing(listingAddress);
    ICCLiquidity liquidityContract = ICCLiquidity(listingContract.liquidityAddressView());
    (uint256 xLiquid, uint256 yLiquid) = liquidityContract.liquidityAmounts();

    // 1. Determine the CORRECT output liquidity pool and decimals
    uint256 outputLiquidityAmount;
    uint8 outputDecimals;

    if (isBuyOrder) {
        // Buy order output is Token A (xLiquid)
        outputLiquidityAmount = xLiquid;
        outputDecimals = listingContract.decimalsA();
    } else {
        // Sell order output is Token B (yLiquid)
        outputLiquidityAmount = yLiquid;
        outputDecimals = listingContract.decimalsB();
    }

    // Use _computeImpactPrice for MFPLiquidPartial or _computeSwapImpact for CCLiquidPartial
    (, uint256 amountOut) = _computeSwapImpact(listingAddress, pendingAmount, isBuyOrder);

    uint256 normalizedAmountSent = normalize(amountOut, outputDecimals);
    uint256 normalizedLiquidity = normalize(outputLiquidityAmount, outputDecimals);

    // 2. Calculate liquidity usage and divide by 10 for the fee percentage
    uint256 feePercent;
    if (normalizedLiquidity > 0) {
        uint256 usagePercent = (normalizedAmountSent * 1e18) / normalizedLiquidity;
        feePercent = usagePercent / 10;
    } else {
        feePercent = 1e17; // Default to max 10% fee if liquidity is zero
    }
    
    // 3. Clamp the fee between 0.01% and 10%
    uint256 minFeePercent = 1e14; // 0.01%
    uint256 maxFeePercent = 1e17; // 10%

    if (feePercent < minFeePercent) {
        feePercent = minFeePercent;
    } else if (feePercent > maxFeePercent) {
        feePercent = maxFeePercent;
    }

    // Calculate final fee amount from the input (pendingAmount)
    feeContext.feeAmount = (pendingAmount * feePercent) / 1e18;
    feeContext.netAmount = pendingAmount - feeContext.feeAmount;
    feeContext.decimals = outputDecimals; // For context, if needed elsewhere
    feeContext.liquidityAmount = outputLiquidityAmount; // For context
}

    function _computeSwapAmount(address listingAddress, FeeContext memory feeContext, bool isBuyOrder) private view returns (LiquidityUpdateContext memory context) {
        context.pendingAmount = feeContext.netAmount;
        context.isBuyOrder = isBuyOrder;
        (, context.tokenDecimals) = _getTokenAndDecimals(listingAddress, isBuyOrder);
        (, context.amountOut) = _computeSwapImpact(listingAddress, feeContext.netAmount, isBuyOrder);
    }

    function _toSingleUpdateArray(ICCLiquidity.UpdateType memory update) private pure returns (ICCLiquidity.UpdateType[] memory) {
        ICCLiquidity.UpdateType[] memory updates = new ICCLiquidity.UpdateType[](1);
        updates[0] = update;
        return updates;
    }

    function _prepareLiquidityUpdates(address listingAddress, uint256 orderIdentifier, LiquidityUpdateContext memory context) private {
    // Prepares liquidity updates, corrects index for buy/sell, reverts on critical failures
    ICCListing listingContract = ICCListing(listingAddress);
    ICCLiquidity liquidityContract = ICCLiquidity(listingContract.liquidityAddressView());
    (uint256 xLiquid, uint256 yLiquid) = liquidityContract.liquidityAmounts();
    (address tokenAddress, uint8 tokenDecimals) = _getTokenAndDecimals(listingAddress, context.isBuyOrder);
    uint256 normalizedPending = normalize(context.pendingAmount, context.tokenDecimals);
    uint256 normalizedSettle = normalize(context.amountOut, context.isBuyOrder ? listingContract.decimalsA() : listingContract.decimalsB());
    FeeContext memory feeContext = _computeFee(listingAddress, context.pendingAmount, context.isBuyOrder);
    uint256 normalizedFee = normalize(feeContext.feeAmount, context.tokenDecimals);

    // Validate liquidity before updates
    require(context.isBuyOrder ? yLiquid >= normalizedPending : xLiquid >= normalizedPending, "Insufficient input liquidity");
    require(context.isBuyOrder ? xLiquid >= normalizedSettle : yLiquid >= normalizedSettle, "Insufficient output liquidity");

    ICCLiquidity.UpdateType memory update;

    // Update incoming liquidity (buy: yLiquid, sell: xLiquid)
    // Buys use TokenB (yLiquid) as principal, while expecting TokenA (xLiquid) as settlement. Vice Versa for sells. 
    update = ICCLiquidity.UpdateType({
        updateType: 0,
        index: context.isBuyOrder ? 1 : 0,
        value: context.isBuyOrder ? yLiquid + normalizedPending : xLiquid + normalizedPending,
        addr: address(this),
        recipient: address(0)
    });
    try liquidityContract.ccUpdate(address(this), _toSingleUpdateArray(update)) {} catch Error(string memory reason) {
        revert(string(abi.encodePacked("Incoming liquidity update failed: ", reason)));
    }

    // Update outgoing liquidity (buy: xLiquid, sell: yLiquid)
    update = ICCLiquidity.UpdateType({
        updateType: 0,
        index: context.isBuyOrder ? 0 : 1,
        value: context.isBuyOrder ? xLiquid - normalizedSettle : yLiquid - normalizedSettle,
        addr: address(this),
        recipient: address(0)
    });
    try liquidityContract.ccUpdate(address(this), _toSingleUpdateArray(update)) {} catch Error(string memory reason) {
        revert(string(abi.encodePacked("Outgoing liquidity update failed: ", reason)));
    }

    // Update fees
    update = ICCLiquidity.UpdateType({
        updateType: 1,
        index: context.isBuyOrder ? 1 : 0,
        value: normalizedFee,
        addr: address(this),
        recipient: address(0)
    });
    try liquidityContract.ccUpdate(address(this), _toSingleUpdateArray(update)) {} catch Error(string memory reason) {
        revert(string(abi.encodePacked("Fee update failed: ", reason)));
    }

    // Use transactToken for ERC20, transactNative for ETH
    if (tokenAddress == address(0)) {
        try listingContract.transactNative(context.pendingAmount, listingContract.liquidityAddressView()) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Native transfer failed: ", reason)));
        }
    } else {
        try listingContract.transactToken(tokenAddress, context.pendingAmount, listingContract.liquidityAddressView()) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Token transfer failed: ", reason)));
        }
    }
}

function _executeOrderWithFees(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, uint256 pendingAmount, FeeContext memory feeContext) private returns (bool success) {
    // Executes order with fees, captures current volume, reverts on critical failures
    ICCListing listingContract = ICCListing(listingAddress);
    emit FeeDeducted(listingAddress, orderIdentifier, isBuyOrder, feeContext.feeAmount, feeContext.netAmount);
    LiquidityUpdateContext memory liquidityContext = _computeSwapAmount(listingAddress, feeContext, isBuyOrder);
    _prepareLiquidityUpdates(listingAddress, orderIdentifier, liquidityContext);
    
    // Capture current historical volume without incrementing
    ICCListing.HistoricalUpdate[] memory historicalUpdates = new ICCListing.HistoricalUpdate[](1);
    (uint256 xBalance, uint256 yBalance) = listingContract.volumeBalances(0);
    uint256 historicalLength = listingContract.historicalDataLengthView();
    uint256 xVolume = 0;
    uint256 yVolume = 0;
    if (historicalLength > 0) {
        ICCListing.HistoricalData memory lastData = listingContract.getHistoricalDataView(historicalLength - 1);
        xVolume = lastData.xVolume;
        yVolume = lastData.yVolume;
    }
    historicalUpdates[0] = ICCListing.HistoricalUpdate({
        price: listingContract.prices(0),
        xBalance: xBalance,
        yBalance: yBalance,
        xVolume: xVolume,
        yVolume: yVolume,
        timestamp: block.timestamp
    });
    try listingContract.ccUpdate(
        new ICCListing.BuyOrderUpdate[](0),
        new ICCListing.SellOrderUpdate[](0),
        new ICCListing.BalanceUpdate[](0),
        historicalUpdates
    ) {} catch Error(string memory reason) {
        revert(string(abi.encodePacked("Historical update failed: ", reason)));
    }

    success = isBuyOrder
        ? executeSingleBuyLiquid(listingAddress, orderIdentifier)
        : executeSingleSellLiquid(listingAddress, orderIdentifier);
    require(success, "Order execution failed");
}

function _processSingleOrder(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, uint256 pendingAmount) internal returns (bool success) {
    // Processes single order, skips if invalid pricing or insufficient liquidity
    ICCListing listingContract = ICCListing(listingAddress);
    ICCLiquidity liquidityContract = ICCLiquidity(listingContract.liquidityAddressView());
    (uint256 xLiquid, uint256 yLiquid) = liquidityContract.liquidityAmounts();
    OrderProcessingContext memory context = _validateOrderPricing(listingAddress, orderIdentifier, isBuyOrder, pendingAmount);
    
    // Skip order if pricing is out of bounds
    if (context.impactPrice == 0) {
        emit PriceOutOfBounds(listingAddress, orderIdentifier, context.impactPrice, context.maxPrice, context.minPrice);
        return false;
    }
    
    // Skip order if insufficient liquidity
    uint256 normalizedPending = normalize(pendingAmount, isBuyOrder ? listingContract.decimalsB() : listingContract.decimalsA());
    (, uint256 amountOut) = _computeSwapImpact(listingAddress, pendingAmount, isBuyOrder);
    uint256 normalizedSettle = normalize(amountOut, isBuyOrder ? listingContract.decimalsA() : listingContract.decimalsB());
    if (isBuyOrder ? yLiquid < normalizedPending : xLiquid < normalizedPending) {
        emit InsufficientBalance(listingAddress, normalizedPending, isBuyOrder ? yLiquid : xLiquid);
        return false;
    }
    if (isBuyOrder ? xLiquid < normalizedSettle : yLiquid < normalizedSettle) {
        emit InsufficientBalance(listingAddress, normalizedSettle, isBuyOrder ? xLiquid : yLiquid);
        return false;
    }
    
    FeeContext memory feeContext = _computeFee(listingAddress, pendingAmount, isBuyOrder);
    PrepOrderUpdateResult memory result = isBuyOrder
        ? _prepBuyOrderUpdate(listingAddress, orderIdentifier, pendingAmount, amountOut)
        : _prepSellOrderUpdate(listingAddress, orderIdentifier, pendingAmount, amountOut);
    success = _executeOrderWithFees(listingAddress, orderIdentifier, isBuyOrder, pendingAmount, feeContext);
}

    function _processOrderBatch(address listingAddress, uint256 maxIterations, bool isBuyOrder, uint256 step) internal returns (bool success) {
    // Processes a batch of orders, returns true if any order is processed successfully
    (uint256[] memory orderIdentifiers, uint256 iterationCount) = _collectOrderIdentifiers(listingAddress, maxIterations, isBuyOrder, step);
    success = false;
    for (uint256 i = 0; i < iterationCount; i++) {
        (uint256 pendingAmount,,) = isBuyOrder
            ? ICCListing(listingAddress).getBuyOrderAmounts(orderIdentifiers[i])
            : ICCListing(listingAddress).getSellOrderAmounts(orderIdentifiers[i]);
        if (pendingAmount == 0) continue;
        if (_processSingleOrder(listingAddress, orderIdentifiers[i], isBuyOrder, pendingAmount)) {
            success = true;
        }
    }
}

    function _finalizeUpdates(bool isBuyOrder, ICCListing.BuyOrderUpdate[] memory buyUpdates, ICCListing.SellOrderUpdate[] memory sellUpdates, uint256 updateIndex) internal pure returns (ICCListing.BuyOrderUpdate[] memory finalBuyUpdates, ICCListing.SellOrderUpdate[] memory finalSellUpdates) {
    // Finalizes updates for buy or sell orders
    if (isBuyOrder) {
        finalBuyUpdates = new ICCListing.BuyOrderUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalBuyUpdates[i] = buyUpdates[i];
        }
        finalSellUpdates = new ICCListing.SellOrderUpdate[](0);
    } else {
        finalSellUpdates = new ICCListing.SellOrderUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalSellUpdates[i] = sellUpdates[i];
        }
        finalBuyUpdates = new ICCListing.BuyOrderUpdate[](0);
    }
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