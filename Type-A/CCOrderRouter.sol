// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.0
// Changes:
// - v0.1.0: Bumped version
// - v0.0.11: Moved payout-related functions (executeLongPayouts, executeShortPayouts, executeLongPayout, executeShortPayout, settleLongLiquid, settleShortLiquid) from CCLiquidityRouter.sol v0.0.16 and CCLiquidityPartial.sol v0.0.11. Updated compatibility to CCOrderPartial.sol v0.0.04.
// - v0.0.10: Fixed shadowing declaration of 'maker' in clearOrders by reusing the same variable for getBuyOrderCore and getSellOrderCore destructuring.
// - v0.0.9: Removed caller parameter from listingContract.update and transact calls to align with ICCListing.sol v0.0.7 and CCMainPartial.sol v0.0.10. Updated _executeSingleOrder to pass msg.sender as depositor.
// Compatible with CCListing.sol (v0.0.3), CCOrderPartial.sol (v0.0.04), CCMainPartial.sol (v0.0.10).

import "./utils/CCOrderPartial.sol";

contract CCOrderRouter is CCOrderPartial {
    function createTokenBuyOrder(
        address listingAddress,
        address recipientAddress,
        uint256 inputAmount,
        uint256 maxPrice,
        uint256 minPrice
    ) external onlyValidListing(listingAddress) nonReentrant {
        // Creates buy order for ERC20 token, transfers tokens, executes
        ICCListing listingContract = ICCListing(listingAddress);
        OrderPrep memory prep = _handleOrderPrep(
            listingAddress,
            msg.sender,
            recipientAddress,
            inputAmount,
            maxPrice,
            minPrice,
            true
        );
        address tokenBAddress = listingContract.tokenB();
        require(tokenBAddress != address(0), "TokenB must be ERC20");
        (prep.amountReceived, prep.normalizedReceived) = _checkTransferAmountToken(tokenBAddress, msg.sender, listingAddress, inputAmount);
        _executeSingleOrder(listingAddress, prep, true);
    }

    function createNativeBuyOrder(
        address listingAddress,
        address recipientAddress,
        uint256 inputAmount,
        uint256 maxPrice,
        uint256 minPrice
    ) external payable onlyValidListing(listingAddress) nonReentrant {
        // Creates buy order for native ETH, transfers ETH, executes
        ICCListing listingContract = ICCListing(listingAddress);
        OrderPrep memory prep = _handleOrderPrep(
            listingAddress,
            msg.sender,
            recipientAddress,
            inputAmount,
            maxPrice,
            minPrice,
            true
        );
        require(listingContract.tokenB() == address(0), "TokenB must be native");
        (prep.amountReceived, prep.normalizedReceived) = _checkTransferAmountNative(listingAddress, msg.sender, inputAmount);
        _executeSingleOrder(listingAddress, prep, true);
    }

    function createTokenSellOrder(
        address listingAddress,
        address recipientAddress,
        uint256 inputAmount,
        uint256 maxPrice,
        uint256 minPrice
    ) external onlyValidListing(listingAddress) nonReentrant {
        // Creates sell order for ERC20 token, transfers tokens, executes
        ICCListing listingContract = ICCListing(listingAddress);
        OrderPrep memory prep = _handleOrderPrep(
            listingAddress,
            msg.sender,
            recipientAddress,
            inputAmount,
            maxPrice,
            minPrice,
            false
        );
        address tokenAAddress = listingContract.tokenA();
        require(tokenAAddress != address(0), "TokenA must be ERC20");
        (prep.amountReceived, prep.normalizedReceived) = _checkTransferAmountToken(tokenAAddress, msg.sender, listingAddress, inputAmount);
        _executeSingleOrder(listingAddress, prep, false);
    }

    function createNativeSellOrder(
        address listingAddress,
        address recipientAddress,
        uint256 inputAmount,
        uint256 maxPrice,
        uint256 minPrice
    ) external payable onlyValidListing(listingAddress) nonReentrant {
        // Creates sell order for native ETH, transfers ETH, executes
        ICCListing listingContract = ICCListing(listingAddress);
        OrderPrep memory prep = _handleOrderPrep(
            listingAddress,
            msg.sender,
            recipientAddress,
            inputAmount,
            maxPrice,
            minPrice,
            false
        );
        require(listingContract.tokenA() == address(0), "TokenA must be native");
        (prep.amountReceived, prep.normalizedReceived) = _checkTransferAmountNative(listingAddress, msg.sender, inputAmount);
        _executeSingleOrder(listingAddress, prep, false);
    }

    function _checkTransferAmountToken(
        address tokenAddress,
        address from,
        address to,
        uint256 inputAmount
    ) internal returns (uint256 amountReceived, uint256 normalizedReceived) {
        // Transfers ERC20 tokens, normalizes received amount
        ICCListing listingContract = ICCListing(to);
        uint8 tokenDecimals = IERC20(tokenAddress).decimals();
        uint256 preBalance = IERC20(tokenAddress).balanceOf(to);
        IERC20(tokenAddress).transferFrom(from, to, inputAmount);
        uint256 postBalance = IERC20(tokenAddress).balanceOf(to);
        amountReceived = postBalance > preBalance ? postBalance - preBalance : 0;
        normalizedReceived = amountReceived > 0 ? normalize(amountReceived, tokenDecimals) : 0;
        require(amountReceived > 0, "No tokens received");
    }

    function _checkTransferAmountNative(
        address to,
        address from,
        uint256 inputAmount
    ) internal returns (uint256 amountReceived, uint256 normalizedReceived) {
        // Transfers ETH, normalizes received amount
        ICCListing listingContract = ICCListing(to);
        uint8 tokenDecimals = 18;
        uint256 preBalance = to.balance;
        require(msg.value == inputAmount, "Incorrect ETH amount");
        listingContract.transactNative{value: inputAmount}(inputAmount, to);
        uint256 postBalance = to.balance;
        amountReceived = postBalance > preBalance ? postBalance - preBalance : 0;
        normalizedReceived = amountReceived > 0 ? normalize(amountReceived, tokenDecimals) : 0;
        require(amountReceived > 0, "No ETH received");
    }

    function clearSingleOrder(address listingAddress, uint256 orderIdentifier, bool isBuyOrder) external onlyValidListing(listingAddress) nonReentrant {
        // Clears a single order, maker check in _clearOrderData
        _clearOrderData(listingAddress, orderIdentifier, isBuyOrder);
    }

    function clearOrders(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Clears multiple orders for msg.sender up to maxIterations
        ICCListing listingContract = ICCListing(listingAddress);
        uint256[] memory orderIds = listingContract.makerPendingOrdersView(msg.sender);
        uint256 iterationCount = maxIterations < orderIds.length ? maxIterations : orderIds.length;
        for (uint256 i = 0; i < iterationCount; i++) {
            uint256 orderId = orderIds[i];
            bool isBuyOrder = false;
            address maker;
            (maker,,) = listingContract.getBuyOrderCore(orderId);
            if (maker == msg.sender) {
                isBuyOrder = true;
            } else {
                (maker,,) = listingContract.getSellOrderCore(orderId);
                if (maker != msg.sender) {
                    continue;
                }
            }
            _clearOrderData(listingAddress, orderId, isBuyOrder);
        }
    }

    function executeLongPayouts(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Executes multiple long payouts
        ICCListing listing = ICCListing(listingAddress);
        uint256[] memory orderIdentifiers = listing.longPayoutByIndexView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ICCListing.PayoutUpdate[] memory tempUpdates = new ICCListing.PayoutUpdate[](iterationCount);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; ++i) {
            ICCListing.PayoutUpdate[] memory payoutUpdates = executeLongPayout(listingAddress, orderIdentifiers[i]);
            if (payoutUpdates.length == 0) continue;
            tempUpdates[updateIndex++] = payoutUpdates[0];
        }
        ICCListing.PayoutUpdate[] memory finalUpdates = new ICCListing.PayoutUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; ++i) {
            finalUpdates[i] = tempUpdates[i];
        }
        if (updateIndex > 0) {
            listing.ssUpdate(finalUpdates);
        }
    }

    function executeShortPayouts(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Executes multiple short payouts
        ICCListing listing = ICCListing(listingAddress);
        uint256[] memory orderIdentifiers = listing.shortPayoutByIndexView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ICCListing.PayoutUpdate[] memory tempUpdates = new ICCListing.PayoutUpdate[](iterationCount);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; ++i) {
            ICCListing.PayoutUpdate[] memory payoutUpdates = executeShortPayout(listingAddress, orderIdentifiers[i]);
            if (payoutUpdates.length == 0) continue;
            tempUpdates[updateIndex++] = payoutUpdates[0];
        }
        ICCListing.PayoutUpdate[] memory finalUpdates = new ICCListing.PayoutUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; ++i) {
            finalUpdates[i] = tempUpdates[i];
        }
        if (updateIndex > 0) {
            listing.ssUpdate(finalUpdates);
        }
    }

    function executeLongPayout(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ICCListing.PayoutUpdate[] memory updates) {
        // Executes long payout
        ICCListing listing = ICCListing(listingAddress);
        ICCListing.LongPayoutStruct memory payout = listing.getLongPayout(orderIdentifier);
        if (payout.required == 0) {
            return new ICCListing.PayoutUpdate[](0);
        }
        PayoutContext memory context = _prepPayoutContext(listingAddress, orderIdentifier, true);
        context.recipientAddress = payout.recipientAddress;
        context.amountOut = denormalize(payout.required, context.tokenDecimals);
        uint256 amountReceived;
        uint256 normalizedReceived;
        if (context.tokenOut == address(0)) {
            (amountReceived, normalizedReceived) = _transferNative(
                payable(listingAddress),
                context.amountOut,
                context.recipientAddress,
                false
            );
        } else {
            (amountReceived, normalizedReceived) = _transferToken(
                listingAddress,
                context.tokenOut,
                context.amountOut,
                context.recipientAddress,
                context.tokenDecimals,
                false
            );
        }
        if (normalizedReceived == 0) {
            return new ICCListing.PayoutUpdate[](0);
        }
        payoutPendingAmounts[listingAddress][orderIdentifier] -= normalizedReceived;
        updates = _createPayoutUpdate(normalizedReceived, payout.recipientAddress, true);
    }

    function executeShortPayout(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ICCListing.PayoutUpdate[] memory updates) {
        // Executes short payout
        ICCListing listing = ICCListing(listingAddress);
        ICCListing.ShortPayoutStruct memory payout = listing.getShortPayout(orderIdentifier);
        if (payout.amount == 0) {
            return new ICCListing.PayoutUpdate[](0);
        }
        PayoutContext memory context = _prepPayoutContext(listingAddress, orderIdentifier, false);
        context.recipientAddress = payout.recipientAddress;
        context.amountOut = denormalize(payout.amount, context.tokenDecimals);
        uint256 amountReceived;
        uint256 normalizedReceived;
        if (context.tokenOut == address(0)) {
            (amountReceived, normalizedReceived) = _transferNative(
                payable(listingAddress),
                context.amountOut,
                context.recipientAddress,
                false
            );
        } else {
            (amountReceived, normalizedReceived) = _transferToken(
                listingAddress,
                context.tokenOut,
                context.amountOut,
                context.recipientAddress,
                context.tokenDecimals,
                false
            );
        }
        if (normalizedReceived == 0) {
            return new ICCListing.PayoutUpdate[](0);
        }
        payoutPendingAmounts[listingAddress][orderIdentifier] -= normalizedReceived;
        updates = _createPayoutUpdate(normalizedReceived, payout.recipientAddress, false);
    }

    function settleLongLiquid(address listingAddress, uint256 maxIterations) external nonReentrant onlyValidListing(listingAddress) {
        // Settles multiple long liquidations up to maxIterations
        ICCListing listingContract = ICCListing(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.longPayoutByIndexView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ICCListing.PayoutUpdate[] memory tempUpdates = new ICCListing.PayoutUpdate[](iterationCount);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; ++i) {
            ICCListing.PayoutUpdate[] memory updates = settleSingleLongLiquid(listingAddress, orderIdentifiers[i]);
            if (updates.length == 0) continue;
            tempUpdates[updateIndex++] = updates[0];
        }
        ICCListing.PayoutUpdate[] memory finalUpdates = new ICCListing.PayoutUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; ++i) {
            finalUpdates[i] = tempUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.ssUpdate(finalUpdates);
        }
    }

    function settleShortLiquid(address listingAddress, uint256 maxIterations) external nonReentrant onlyValidListing(listingAddress) {
        // Settles multiple short liquidations up to maxIterations
        ICCListing listingContract = ICCListing(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.shortPayoutByIndexView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ICCListing.PayoutUpdate[] memory tempUpdates = new ICCListing.PayoutUpdate[](iterationCount);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; ++i) {
            ICCListing.PayoutUpdate[] memory updates = settleSingleShortLiquid(listingAddress, orderIdentifiers[i]);
            if (updates.length == 0) continue;
            tempUpdates[updateIndex++] = updates[0];
        }
        ICCListing.PayoutUpdate[] memory finalUpdates = new ICCListing.PayoutUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; ++i) {
            finalUpdates[i] = tempUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.ssUpdate(finalUpdates);
        }
    }
}