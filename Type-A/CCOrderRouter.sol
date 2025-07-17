// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.4
// Changes:
// - v0.0.4: Fixed ParserError in clearOrders by correcting tuple destructuring in getBuyOrderCore call, removing invalid 'SDT' placeholder and using proper (address maker, , ) syntax.
// - v0.0.3: Integrated clearSingleOrder and clearOrders functions from Pieces.txt to enable order clearing functionality, leveraging _clearOrderData from SSOrderPartial.sol.
// - v0.0.2: Fixed illegal character 'удё' in _checkTransferAmount function, replaced with correct 'transferFrom' call.
// - v0.0.1: Created CCOrderRouter.sol by extracting createBuyOrder and createSellOrder from SSRouter.sol v0.0.61.
// - v0.0.1: Inherited SSOrderPartial.sol v0.0.19 to reuse _handleOrderPrep and _executeSingleOrder.
// - v0.0.1: Retained setAgent from SSMainPartial.sol v0.0.25 for contract setup.
// - v0.0.1: Included ISSListingTemplate and ISSLiquidityTemplate interfaces from SSMainPartial.sol v0.0.25 and SSRouter.sol v0.0.61 for compatibility.
// - v0.0.1: Added SafeERC20 usage and ReentrancyGuard for security.
// Compatible with SSListingTemplate.sol (v0.0.10), SSLiquidityTemplate.sol (v0.0.6), SSMainPartial.sol (v0.0.25), SSOrderPartial.sol (v0.0.19).

import "./utils/SSOrderPartial.sol";

contract CCOrderRouter is SSOrderPartial {
    using SafeERC20 for IERC20;

    // Creates a buy order, transfers input tokens, and executes
    function createBuyOrder(
        address listingAddress,
        address recipientAddress,
        uint256 inputAmount,
        uint256 maxPrice,
        uint256 minPrice
    ) external payable onlyValidListing(listingAddress) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
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
        (prep.amountReceived, prep.normalizedReceived) = _checkTransferAmount(
            tokenBAddress,
            msg.sender,
            listingAddress,
            inputAmount
        );
        _executeSingleOrder(listingAddress, prep, true);
    }

    // Creates a sell order, transfers input tokens, and executes
    function createSellOrder(
        address listingAddress,
        address recipientAddress,
        uint256 inputAmount,
        uint256 maxPrice,
        uint256 minPrice
    ) external payable onlyValidListing(listingAddress) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        OrderPrep memory orderPrep = _handleOrderPrep(
            listingAddress,
            msg.sender,
            recipientAddress,
            inputAmount,
            maxPrice,
            minPrice,
            false
        );
        address tokenAAddress = listingContract.tokenA();
        (orderPrep.amountReceived, orderPrep.normalizedReceived) = _checkTransferAmount(
            tokenAAddress,
            msg.sender,
            listingAddress,
            inputAmount
        );
        _executeSingleOrder(listingAddress, orderPrep, false);
    }

    // Transfers tokens and normalizes received amount based on decimals
    function _checkTransferAmount(
        address tokenAddress,
        address from,
        address to,
        uint256 inputAmount
    ) internal returns (uint256 amountReceived, uint256 normalizedReceived) {
        ISSListingTemplate listingContract = ISSListingTemplate(to);
        uint8 tokenDecimals = tokenAddress == address(0) ? 18 : IERC20(tokenAddress).decimals();
        uint256 preBalance = tokenAddress == address(0)
            ? to.balance
            : IERC20(tokenAddress).balanceOf(to);
        if (tokenAddress == address(0)) {
            require(msg.value == inputAmount, "Incorrect ETH amount");
            listingContract.transact{value: inputAmount}(address(this), tokenAddress, inputAmount, to);
        } else {
            IERC20(tokenAddress).safeTransferFrom(from, to, inputAmount);
        }
        uint256 postBalance = tokenAddress == address(0)
            ? to.balance
            : IERC20(tokenAddress).balanceOf(to);
        amountReceived = postBalance > preBalance ? postBalance - preBalance : 0;
        normalizedReceived = amountReceived > 0 ? normalize(amountReceived, tokenDecimals) : 0;
        require(amountReceived > 0, "No tokens received");
    }

    function clearSingleOrder(address listingAddress, uint256 orderIdentifier, bool isBuyOrder) external onlyValidListing(listingAddress) nonReentrant {
        // Clears a single order, maker check enforced in _clearOrderData
        _clearOrderData(listingAddress, orderIdentifier, isBuyOrder);
    }

    function clearOrders(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Clears multiple orders for msg.sender up to maxIterations
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        uint256[] memory orderIds = listingContract.makerPendingOrdersView(msg.sender);
        uint256 iterationCount = maxIterations < orderIds.length ? maxIterations : orderIds.length;
        for (uint256 i = 0; i < iterationCount; i++) {
            uint256 orderId = orderIds[i];
            bool isBuyOrder = false;
            (address maker, , ) = listingContract.getBuyOrderCore(orderId);
            if (maker == msg.sender) {
                isBuyOrder = true;
            } else {
                (,maker,) = listingContract.getSellOrderCore(orderId);
                if (maker != msg.sender) {
                    continue;
                }
            }
            _clearOrderData(listingAddress, orderId, isBuyOrder);
        }
    }
}