// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.8
// Changes:
// - v0.0.8: Fixed TypeError in clearOrders by correcting tuple destructuring for getSellOrderCore from (,,address maker) to (address maker,,).
// - v0.0.7: Removed SafeERC20 usage, replaced with IERC20 interface. Removed require success checks for transfers, relying on pre/post balance checks. Ensured no partial implementations.
// - v0.0.6: Split createBuyOrder and createSellOrder into createTokenBuyOrder, createNativeBuyOrder, createTokenSellOrder, and createNativeSellOrder to handle ERC20 and native ETH separately. Removed payableAmount usage to avoid field errors.
// - v0.0.5: Updated to use ICCListing interface from SSMainPartial.sol v0.0.26. Split _checkTransferAmount into _checkTransferAmountToken and _checkTransferAmountNative to align with CCListing.sol v0.0.3 transactToken/transactNative split.
// - v0.0.4: Fixed ParserError in clearOrders by correcting tuple destructuring.
// - v0.0.3: Integrated clearSingleOrder and clearOrders functions.
// - v0.0.2: Fixed illegal character in _checkTransferAmount, used transferFrom.
// - v0.0.1: Created CCOrderRouter.sol from SSRouter.sol v0.0.61.
// Compatible with CCListing.sol (v0.0.3), CCOrderPartial.sol (v0.0.02), CCMainPartial.sol (v0.0.07).

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
        listingContract.transactNative(address(this), inputAmount, to);
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
            (address maker,,) = listingContract.getBuyOrderCore(orderId);
            if (maker == msg.sender) {
                isBuyOrder = true;
            } else {
                (address maker,,) = listingContract.getSellOrderCore(orderId);
                if (maker != msg.sender) {
                    continue;
                }
            }
            _clearOrderData(listingAddress, orderId, isBuyOrder);
        }
    }
}