// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.02
// Changes:
// - v0.0.02: Replaced invalid try-catch in _clearOrderData with conditional for native/ERC20 transfer.
// - v0.0.01: Updated to use ICCListing interface from CCMainPartial.sol v0.0.26. Split _clearOrderData's transact call into transactToken and transactNative to align with CCListing.sol v0.0.3.
// Compatible with CCListing.sol (v0.0.3), CCOrderRouter.sol (v0.0.6).

import "./CCMainPartial.sol";

contract CCOrderPartial is CCMainPartial {
    struct OrderPrep {
        address maker;
        address recipient;
        uint256 amount;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 amountReceived;
        uint256 normalizedReceived;
    }

    function _handleOrderPrep(
        address listing,
        address maker,
        address recipient,
        uint256 amount,
        uint256 maxPrice,
        uint256 minPrice,
        bool isBuy
    ) internal view returns (OrderPrep memory) {
        // Prepares order data, normalizes amount based on token decimals
        require(maker != address(0), "Invalid maker");
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        ICCListing listingContract = ICCListing(listing);
        uint8 decimals = isBuy ? listingContract.decimalsB() : listingContract.decimalsA();
        uint256 normalizedAmount = normalize(amount, decimals);
        return OrderPrep(maker, recipient, normalizedAmount, maxPrice, minPrice, 0, 0);
    }

    function _executeSingleOrder(
        address listing,
        OrderPrep memory prep,
        bool isBuy
    ) internal {
        // Executes single order creation, initializes amountSent to 0
        ICCListing listingContract = ICCListing(listing);
        uint256 orderId = listingContract.getNextOrderId();
        ICCListing.UpdateType[] memory updates = new ICCListing.UpdateType[](3);
        updates[0] = ICCListing.UpdateType({
            updateType: isBuy ? 1 : 2,
            structId: 0,
            index: orderId,
            value: 1,
            addr: prep.maker,
            recipient: prep.recipient,
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        updates[1] = ICCListing.UpdateType({
            updateType: isBuy ? 1 : 2,
            structId: 1,
            index: orderId,
            value: 0,
            addr: address(0),
            recipient: address(0),
            maxPrice: prep.maxPrice,
            minPrice: prep.minPrice,
            amountSent: 0
        });
        updates[2] = ICCListing.UpdateType({
            updateType: isBuy ? 1 : 2,
            structId: 2,
            index: orderId,
            value: prep.normalizedReceived,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        listingContract.update(address(this), updates);
    }

    function _clearOrderData(
        address listing,
        uint256 orderId,
        bool isBuy
    ) internal {
        // Clears order data, refunds pending amounts, sets status to cancelled
        ICCListing listingContract = ICCListing(listing);
        (address maker, address recipient, uint8 status) = isBuy
            ? listingContract.getBuyOrderCore(orderId)
            : listingContract.getSellOrderCore(orderId);
        require(maker == msg.sender, "Only maker can cancel");
        (uint256 pending, uint256 filled, uint256 amountSent) = isBuy
            ? listingContract.getBuyOrderAmounts(orderId)
            : listingContract.getSellOrderAmounts(orderId);
        if (pending > 0 && (status == 1 || status == 2)) {
            address tokenAddress = isBuy ? listingContract.tokenB() : listingContract.tokenA();
            uint8 tokenDecimals = isBuy ? listingContract.decimalsB() : listingContract.decimalsA();
            uint256 refundAmount = denormalize(pending, tokenDecimals);
            if (tokenAddress == address(0)) {
                bool success = listingContract.transactNative(address(this), refundAmount, recipient);
                require(success, "Native refund failed");
            } else {
                bool success = listingContract.transactToken(address(this), tokenAddress, refundAmount, recipient);
                require(success, "Token refund failed");
            }
        }
        ICCListing.UpdateType[] memory updates = new ICCListing.UpdateType[](1);
        updates[0] = ICCListing.UpdateType({
            updateType: isBuy ? 1 : 2,
            structId: 0,
            index: orderId,
            value: 0,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        listingContract.update(address(this), updates);
    }
}