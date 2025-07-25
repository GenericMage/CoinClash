// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.16
// Changes:
// - v0.0.16: Removed duplicated _prepareSellSwapData (inherited from CCUniPartial.sol), added routers function to ICCLiquidity.
// - v0.0.15: Added ICCLiquidity interface, removed duplicated swap and update functions.
// - v0.0.14: Replaced ISSListingTemplate with ICCListing, ISSLiquidityTemplate with ICCLiquidity, split transact/deposit.
// Compatible with ICCListing.sol (v0.0.3), ICCLiquidity.sol, CCUniPartial.sol (v0.0.6), CCSettlementRouter.sol (v0.0.2).

import "./CCUniPartial.sol";

interface ICCLiquidity {
    struct UpdateType {
        uint8 updateType; // 0=balance, 1=fees, 2=xSlot, 3=ySlot
        uint256 index; // 0=xFees/xLiquid, 1=yFees/yLiquid, or slot index
        uint256 value; // Normalized amount or allocation
        address addr; // Depositor address
        address recipient; // Unused recipient address
    }
    struct PreparedWithdrawal {
        uint256 amountA; // Normalized withdrawal amount for token A
        uint256 amountB; // Normalized withdrawal amount for token B
    }
    struct Slot {
        address depositor; // Address of the slot owner
        address recipient; // Unused recipient address
        uint256 allocation; // Normalized liquidity allocation
        uint256 dFeesAcc; // Cumulative fees at deposit or last claim
        uint256 timestamp; // Slot creation timestamp
    }
    function volumeBalances(uint256 listingId) external view returns (uint256 xBalance, uint256 yBalance);
    function getPrice() external view returns (uint256);
    function getRegistryAddress() external view returns (address);
    function setRouters(address[] memory _routers) external;
    function setListingId(uint256 _listingId) external;
    function setListingAddress(address _listingAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setAgent(address _agent) external;
    function update(address caller, UpdateType[] memory updates) external;
    function changeSlotDepositor(address caller, bool isX, uint256 slotIndex, address newDepositor) external;
    function depositToken(address caller, address token, uint256 amount) external;
    function depositNative(address caller, uint256 amount) external payable;
    function xPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);
    function xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external;
    function yPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);
    function yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external;
    function claimFees(address caller, address listingAddress, uint256 liquidityIndex, bool isX, uint256 volume) external;
    function transactToken(address caller, address token, uint256 amount, address recipient) external;
    function transactNative(address caller, uint256 amount, address recipient) external payable;
    function addFees(address caller, bool isX, uint256 fee) external;
    function updateLiquidity(address caller, bool isX, uint256 amount) external;
    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount);
    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, uint256 xFeesAcc, uint256 yFeesAcc);
    function activeXLiquiditySlotsView() external view returns (uint256[] memory);
    function activeYLiquiditySlotsView() external view returns (uint256[] memory);
    function userIndexView(address user) external view returns (uint256[] memory);
    function getXSlotView(uint256 index) external view returns (Slot memory);
    function getYSlotView(uint256 index) external view returns (Slot memory);
    function routers(address router) external view returns (bool);
}

contract CCSettlementPartial is CCUniPartial {
    using SafeERC20 for IERC20;

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

    function _prepareLiquidityTransaction(
        address listingAddress,
        uint256 inputAmount,
        bool isBuyOrder
    ) internal view returns (uint256 amountOut, address tokenIn, address tokenOut) {
        // Prepares liquidity transaction, calculating output amount
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(listingContract.getListingId());
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
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
        ICCListing listingContract
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
            try listingContract.transactNative{value: inputAmount}(address(this), inputAmount, liquidityAddr) {} catch {
                revert("Native transfer failed");
            }
        } else {
            try listingContract.transactToken(address(this), tokenIn, inputAmount, liquidityAddr) {} catch {
                revert("Token transfer failed");
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
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(listingContract.getListingId());
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        uint256 actualAmount;
        uint8 tokenDecimals;
        (actualAmount, tokenDecimals) = _checkAndTransferPrincipal(
            listingAddress,
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
        ICCListing listingContract = ICCListing(listingAddress);
        (result.tokenAddress, result.tokenDecimals) = _getTokenAndDecimals(listingAddress, true);
        (result.makerAddress, result.recipientAddress, result.orderStatus) = listingContract.getBuyOrderCore(orderIdentifier);
        uint256 denormalizedAmount = denormalize(amountOut, result.tokenDecimals);
        if (result.tokenAddress == address(0)) {
            try listingContract.transactNative{value: denormalizedAmount}(address(this), denormalizedAmount, result.recipientAddress) {} catch {
                result.amountReceived = 0;
                result.normalizedReceived = 0;
            }
        } else {
            try listingContract.transactToken(address(this), result.tokenAddress, denormalizedAmount, result.recipientAddress) {} catch {
                result.amountReceived = 0;
                result.normalizedReceived = 0;
            }
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
        ICCListing listingContract = ICCListing(listingAddress);
        (result.tokenAddress, result.tokenDecimals) = _getTokenAndDecimals(listingAddress, false);
        (result.recipientAddress, result.makerAddress, result.orderStatus) = listingContract.getSellOrderCore(orderIdentifier);
        uint256 denormalizedAmount = denormalize(amountOut, result.tokenDecimals);
        if (result.tokenAddress == address(0)) {
            try listingContract.transactNative{value: denormalizedAmount}(address(this), denormalizedAmount, result.recipientAddress) {} catch {
                result.amountReceived = 0;
                result.normalizedReceived = 0;
            }
        } else {
            try listingContract.transactToken(address(this), result.tokenAddress, denormalizedAmount, result.recipientAddress) {} catch {
                result.amountReceived = 0;
                result.normalizedReceived = 0;
            }
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
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Prepares updates for buy order liquidation
        if (!_checkPricing(address(context.listingContract), orderIdentifier, true, pendingAmount)) {
            return new ICCListing.UpdateType[](0);
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
            ICCLiquidity liquidityContract = ICCLiquidity(context.liquidityAddr);
            if (tokenOut == address(0)) {
                try liquidityContract.transactNative{value: denormalizedAmount}(address(this), denormalizedAmount, updateContext.recipient) {} catch {
                    return new ICCListing.UpdateType[](0);
                }
            } else {
                try liquidityContract.transactToken(address(this), tokenOut, denormalizedAmount, updateContext.recipient) {} catch {
                    return new ICCListing.UpdateType[](0);
                }
            }
            updateContext.amountReceived = denormalizedAmount;
            updateContext.normalizedReceived = normalize(denormalizedAmount, tokenDecimals);
            updateContext.amountSent = _computeAmountSent(tokenOut, updateContext.recipient, denormalizedAmount);
        }
        if (updateContext.normalizedReceived == 0) {
            return new ICCListing.UpdateType[](0);
        }
        _updateLiquidity(address(context.listingContract), tokenIn, false, pendingAmount);
        return _createBuyOrderUpdates(orderIdentifier, updateContext, pendingAmount);
    }

    function _prepSellLiquidUpdates(
        OrderContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Prepares updates for sell order liquidation
        if (!_checkPricing(address(context.listingContract), orderIdentifier, false, pendingAmount)) {
            return new ICCListing.UpdateType[](0);
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
            ICCLiquidity liquidityContract = ICCLiquidity(context.liquidityAddr);
            if (tokenOut == address(0)) {
                try liquidityContract.transactNative{value: denormalizedAmount}(address(this), denormalizedAmount, updateContext.recipient) {} catch {
                    return new ICCListing.UpdateType[](0);
                }
            } else {
                try liquidityContract.transactToken(address(this), tokenOut, denormalizedAmount, updateContext.recipient) {} catch {
                    return new ICCListing.UpdateType[](0);
                }
            }
            updateContext.amountReceived = denormalizedAmount;
            updateContext.normalizedReceived = normalize(denormalizedAmount, tokenDecimals);
            updateContext.amountSent = _computeAmountSent(tokenOut, updateContext.recipient, denormalizedAmount);
        }
        if (updateContext.normalizedReceived == 0) {
            return new ICCListing.UpdateType[](0);
        }
        _updateLiquidity(address(context.listingContract), tokenIn, true, pendingAmount);
        return _createSellOrderUpdates(orderIdentifier, updateContext, pendingAmount);
    }

    function executeSingleBuyLiquid(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Executes a single buy order liquidation
        ICCListing listingContract = ICCListing(listingAddress);
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.getBuyOrderAmounts(orderIdentifier);
        if (pendingAmount == 0) {
            return new ICCListing.UpdateType[](0);
        }
        OrderContext memory context = OrderContext({
            listingContract: listingContract,
            tokenIn: listingContract.tokenB(),
            tokenOut: listingContract.tokenA(),
            liquidityAddr: listingContract.liquidityAddressView(listingContract.getListingId())
        });
        return _prepBuyLiquidUpdates(context, orderIdentifier, pendingAmount);
    }

    function executeSingleSellLiquid(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Executes a single sell order liquidation
        ICCListing listingContract = ICCListing(listingAddress);
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.getSellOrderAmounts(orderIdentifier);
        if (pendingAmount == 0) {
            return new ICCListing.UpdateType[](0);
        }
        OrderContext memory context = OrderContext({
            listingContract: listingContract,
            tokenIn: listingContract.tokenA(),
            tokenOut: listingContract.tokenB(),
            liquidityAddr: listingContract.liquidityAddressView(listingContract.getListingId())
        });
        return _prepSellLiquidUpdates(context, orderIdentifier, pendingAmount);
    }

    function _processBuyOrder(
        address listingAddress,
        uint256 orderIdentifier,
        ICCListing listingContract
    ) internal returns (ICCListing.UpdateType[] memory updates) {
        // Processes a single buy order using Uniswap V2 swap
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.getBuyOrderAmounts(orderIdentifier);
        if (pendingAmount == 0) {
            return new ICCListing.UpdateType[](0);
        }
        (uint256 maxPrice, uint256 minPrice) = listingContract.getBuyOrderPricing(orderIdentifier);
        uint256 currentPrice = _computeCurrentPrice(listingAddress);
        if (currentPrice < minPrice || currentPrice > maxPrice) {
            return new ICCListing.UpdateType[](0);
        }
        uint256 maxAmountIn = _computeMaxAmountIn(listingAddress, maxPrice, minPrice, pendingAmount, true);
        uint256 swapAmount = maxAmountIn >= pendingAmount ? pendingAmount : maxAmountIn;
        if (swapAmount == 0) {
            return new ICCListing.UpdateType[](0);
        }
        updates = _executePartialBuySwap(listingAddress, orderIdentifier, swapAmount, pendingAmount);
    }

    function _processSellOrder(
        address listingAddress,
        uint256 orderIdentifier,
        ICCListing listingContract
    ) internal returns (ICCListing.UpdateType[] memory updates) {
        // Processes a single sell order using Uniswap V2 swap
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.getSellOrderAmounts(orderIdentifier);
        if (pendingAmount == 0) {
            return new ICCListing.UpdateType[](0);
        }
        (uint256 maxPrice, uint256 minPrice) = listingContract.getSellOrderPricing(orderIdentifier);
        uint256 currentPrice = _computeCurrentPrice(listingAddress);
        if (currentPrice < minPrice || currentPrice > maxPrice) {
            return new ICCListing.UpdateType[](0);
        }
        uint256 maxAmountIn = _computeMaxAmountIn(listingAddress, maxPrice, minPrice, pendingAmount, false);
        uint256 swapAmount = maxAmountIn >= pendingAmount ? pendingAmount : maxAmountIn;
        if (swapAmount == 0) {
            return new ICCListing.UpdateType[](0);
        }
        updates = _executePartialSellSwap(listingAddress, orderIdentifier, swapAmount, pendingAmount);
    }
}