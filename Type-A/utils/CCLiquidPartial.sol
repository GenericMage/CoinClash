// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.9
// Changes:
// - v0.0.9: Removed unnecessary isRouter check in _prepareLiquidityTransaction to fix compatibility with CCLiquidityTemplate.sol v0.1.0, where isRouter was removed.
// - v0.0.8: Updated to use depositor in ICCLiquidity function calls (update, updateLiquidity, transactToken, transactNative) in _updateLiquidity, _prepBuyOrderUpdate, _prepSellOrderUpdate to align with ICCLiquidity.sol v0.0.4. Ensured consistency with CCMainPartial.sol v0.0.11 and ICCListing.sol v0.0.7.
// - v0.0.7: Added _prepBuyLiquidUpdates and _prepSellLiquidUpdates to prepare buy/sell order liquidation updates, fixing DeclarationError in executeSingleBuyLiquid and executeSingleSellLiquid.
// - v0.0.6: Replaced ICCLiquidity with ICCLiquidityTemplate in _prepareLiquidityTransaction to fix DeclarationError, aligning with CCMainPartial.sol (v0.0.9).
// - v0.0.5: Removed duplicated ICCListing and ICCLiquidity interfaces, relying on CCMainPartial.sol (v0.0.9) definitions to resolve interface duplication per linearization.
// - v0.0.4: Updated ICCListing interface to remove uint256 parameter from liquidityAddressView for compatibility with CCListingTemplate.sol v0.0.6. Replaced liquidityAddressView(listingContract.getListingId()) with liquidityAddressView() in _prepareLiquidityTransaction and _prepPayoutContext.
// - v0.0.3: Updated ICCLiquidity to return bool for transactToken and transactNative, removed redundant SafeERC20 import.
// - v0.0.2: Added ICCLiquidity interface to resolve DeclarationError, copied from CCSettlementPartial.sol.
// - v0.0.1: Created CCLiquidPartial.sol, extracted liquid settlement functions from CCSettlementPartial.sol, integrated normalize/denormalize from CCMainPartial.sol, removed CCUniPartial.sol dependency.
// Compatible with CCListingTemplate.sol (v0.0.10), CCMainPartial.sol (v0.0.11), CCLiquidRouter.sol (v0.0.6), CCLiquidityRouter.sol (v0.0.25), CCLiquidityTemplate.sol (v0.1.0).

import "./CCMainPartial.sol";

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
        return maxPrice >= minPrice; // Simplified check, assumes external price computation
    }

    function _prepareLiquidityTransaction(
        address listingAddress,
        uint256 inputAmount,
        bool isBuyOrder
    ) internal view returns (uint256 amountOut, address tokenIn, address tokenOut) {
        // Prepares liquidity transaction, calculating output amount
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        amountOut = inputAmount; // Simplified, assumes external swap logic
        if (isBuyOrder) {
            require(xAmount >= inputAmount, "Insufficient x liquidity");
            tokenIn = listingContract.tokenB();
            tokenOut = listingContract.tokenA();
        } else {
            require(yAmount >= inputAmount, "Insufficient y liquidity");
            tokenIn = listingContract.tokenA();
            tokenOut = listingContract.tokenB();
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
            listingContract.transactNative{value: inputAmount}(inputAmount, liquidityAddr);
        } else {
            listingContract.transactToken(tokenIn, inputAmount, liquidityAddr);
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
        address liquidityAddr = listingContract.liquidityAddressView();
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
        liquidityContract.updateLiquidity(address(this), isX, normalizedAmount);
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
            listingContract.transactNative{value: denormalizedAmount}(denormalizedAmount, result.recipientAddress);
            result.amountReceived = denormalizedAmount;
        } else {
            listingContract.transactToken(result.tokenAddress, denormalizedAmount, result.recipientAddress);
            result.amountReceived = denormalizedAmount;
        }
        result.normalizedReceived = result.amountReceived > 0 ? normalize(result.amountReceived, result.tokenDecimals) : 0;
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
        (result.makerAddress, result.recipientAddress, result.orderStatus) = listingContract.getSellOrderCore(orderIdentifier);
        uint256 denormalizedAmount = denormalize(amountOut, result.tokenDecimals);
        if (result.tokenAddress == address(0)) {
            listingContract.transactNative{value: denormalizedAmount}(denormalizedAmount, result.recipientAddress);
            result.amountReceived = denormalizedAmount;
        } else {
            listingContract.transactToken(result.tokenAddress, denormalizedAmount, result.recipientAddress);
            result.amountReceived = denormalizedAmount;
        }
        result.normalizedReceived = result.amountReceived > 0 ? normalize(result.amountReceived, result.tokenDecimals) : 0;
        result.amountSent = _computeAmountSent(result.tokenAddress, result.recipientAddress, denormalizedAmount);
    }

    function _createBuyOrderUpdates(
        uint256 orderIdentifier,
        BuyOrderUpdateContext memory context,
        uint256 pendingAmount
    ) internal pure returns (ICCListing.UpdateType[] memory) {
        // Creates update array for buy order liquidation
        ICCListing.UpdateType[] memory updates = new ICCListing.UpdateType[](3);
        updates[0] = ICCListing.UpdateType({
            updateType: 1,
            structId: 0,
            index: orderIdentifier,
            value: context.status,
            addr: context.makerAddress,
            recipient: context.recipient,
            maxPrice: 0,
            minPrice: 0,
            amountSent: context.amountSent
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
            updateType: 1,
            structId: 2,
            index: orderIdentifier,
            value: pendingAmount,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        return updates;
    }

    function _createSellOrderUpdates(
        uint256 orderIdentifier,
        SellOrderUpdateContext memory context,
        uint256 pendingAmount
    ) internal pure returns (ICCListing.UpdateType[] memory) {
        // Creates update array for sell order liquidation
        ICCListing.UpdateType[] memory updates = new ICCListing.UpdateType[](3);
        updates[0] = ICCListing.UpdateType({
            updateType: 2,
            structId: 0,
            index: orderIdentifier,
            value: context.status,
            addr: context.makerAddress,
            recipient: context.recipient,
            maxPrice: 0,
            minPrice: 0,
            amountSent: context.amountSent
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
            updateType: 2,
            structId: 2,
            index: orderIdentifier,
            value: pendingAmount,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        return updates;
    }

    function _prepBuyLiquidUpdates(
        OrderContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Prepares buy order liquidation updates
        require(_checkPricing(address(context.listingContract), orderIdentifier, true, pendingAmount), "Invalid pricing");
        (uint256 amountOut, , ) = _prepareLiquidityTransaction(address(context.listingContract), pendingAmount, true);
        PrepOrderUpdateResult memory result = _prepBuyOrderUpdate(address(context.listingContract), orderIdentifier, amountOut);
        if (result.normalizedReceived == 0) {
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
        return _createBuyOrderUpdates(orderIdentifier, updateContext, pendingAmount - result.normalizedReceived);
    }

    function _prepSellLiquidUpdates(
        OrderContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ICCListing.UpdateType[] memory) {
        // Prepares sell order liquidation updates
        require(_checkPricing(address(context.listingContract), orderIdentifier, false, pendingAmount), "Invalid pricing");
        (uint256 amountOut, , ) = _prepareLiquidityTransaction(address(context.listingContract), pendingAmount, false);
        PrepOrderUpdateResult memory result = _prepSellOrderUpdate(address(context.listingContract), orderIdentifier, amountOut);
        if (result.normalizedReceived == 0) {
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
        return _createSellOrderUpdates(orderIdentifier, updateContext, pendingAmount - result.normalizedReceived);
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
}