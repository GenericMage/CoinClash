// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.3
// Changes:
// - v0.1.3: Updated `settleSingleLongLiquid` and `settleSingleShortLiquid` to use `payout.required` or `payout.amount` as `filled` in `PayoutUpdate` to account for transfer taxes, ensuring `filled` reflects the full amount withdrawn from liquidity pool. `amountSent` now uses pre/post balance checks. Removed listing template balance usage for payouts, relying solely on liquidity pool transfers via `_transferNative` or `_transferToken`.
// - v0.1.2: Updated `_executeSingleOrder` to set `filled=0` in BuyOrderAmounts/SellOrderAmounts (structId=2) to ensure unused fields are zeroed, per CCListingTemplate.sol v0.2.26 requirements.
// - v0.1.0: Bumped version
// - v0.0.4: Moved payout-related functionality (PayoutContext, payoutPendingAmounts, _prepPayoutContext, _checkLiquidityBalance, _transferNative, _transferToken, _createPayoutUpdate, settleSingleLongLiquid, settleSingleShortLiquid) from CCLiquidityPartial.sol v0.0.11. Ensured PayoutContext defined before use. Added TransferFailed event and InsufficientAllowance error.
// - v0.0.3: Removed caller parameter from listingContract.update and transact calls to align with ICCListing.sol v0.0.7 and CCMainPartial.sol v0.0.10. Updated _executeSingleOrder to pass msg.sender as depositor.
// - v0.0.2: Replaced invalid try-catch in _clearOrderData with conditional for native/ERC20 transfer.
// - v0.0.1: Updated to use ICCListing interface from CCMainPartial.sol v0.0.26.
// Compatible with CCListing.sol (v0.0.3), CCOrderRouter.sol (v0.0.11).

import "./CCMainPartial.sol";

contract CCOrderPartial is CCMainPartial {
    // Emitted when IERC20.transfer fails
    event TransferFailed(address indexed sender, address indexed token, uint256 amount, bytes reason);
    // Emitted when allowance is insufficient
    error InsufficientAllowance(address sender, address token, uint256 required, uint256 available);

    struct OrderPrep {
        address maker;
        address recipient;
        uint256 amount;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 amountReceived;
        uint256 normalizedReceived;
    }

    struct PayoutContext {
        address listingAddress;
        address liquidityAddr;
        address tokenOut;
        uint8 tokenDecimals;
        uint256 amountOut;
        address recipientAddress;
    }

    mapping(address => mapping(uint256 => uint256)) internal payoutPendingAmounts;

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
        // Executes single order creation, initializes amountSent and filled to 0
        ICCListing listingContract = ICCListing(listing);
        uint256 orderId = listingContract.getNextOrderId();
        uint8[] memory updateType = new uint8[](3);
        uint8[] memory updateSort = new uint8[](3);
        uint256[] memory updateData = new uint256[](3);
        
        updateType[0] = isBuy ? 1 : 2; // Buy or Sell
        updateSort[0] = 0; // Core
        updateData[0] = uint256(bytes32(abi.encode(prep.maker, prep.recipient, uint8(1)))); // status=pending
        
        updateType[1] = isBuy ? 1 : 2;
        updateSort[1] = 1; // Pricing
        updateData[1] = uint256(bytes32(abi.encode(prep.maxPrice, prep.minPrice)));
        
        updateType[2] = isBuy ? 1 : 2;
        updateSort[2] = 2; // Amounts
        updateData[2] = uint256(bytes32(abi.encode(prep.normalizedReceived, uint256(0), uint256(0)))); // pending, filled=0, amountSent=0
        
        listingContract.ccUpdate(updateType, updateSort, updateData);
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
                listingContract.transactNative(refundAmount, recipient);
            } else {
                listingContract.transactToken(tokenAddress, refundAmount, recipient);
            }
        }
        uint8[] memory updateType = new uint8[](1);
        uint8[] memory updateSort = new uint8[](1);
        uint256[] memory updateData = new uint256[](1);
        
        updateType[0] = isBuy ? 1 : 2;
        updateSort[0] = 0; // Core
        updateData[0] = uint256(bytes32(abi.encode(address(0), address(0), uint8(0)))); // status=cancelled
        
        listingContract.ccUpdate(updateType, updateSort, updateData);
    }

    function _prepPayoutContext(
        address listingAddress,
        uint256 orderId,
        bool isLong
    ) internal view returns (PayoutContext memory context) {
        // Prepares payout context
        ICCListing listing = ICCListing(listingAddress);
        context = PayoutContext({
            listingAddress: listingAddress,
            liquidityAddr: listing.liquidityAddressView(),
            tokenOut: isLong ? listing.tokenB() : listing.tokenA(),
            tokenDecimals: isLong ? listing.decimalsB() : listing.decimalsA(),
            amountOut: 0,
            recipientAddress: address(0)
        });
    }

    function _checkLiquidityBalance(
        PayoutContext memory context,
        uint256 requiredAmount,
        bool isLong
    ) internal view returns (bool sufficient) {
        // Checks if liquidity pool has sufficient tokens
        ICCLiquidity liquidityContract = ICCLiquidity(context.liquidityAddr);
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        sufficient = isLong ? yAmount >= requiredAmount : xAmount >= requiredAmount;
    }

    function _transferNative(
        address payable contractAddr,
        uint256 amountOut,
        address recipientAddress,
        bool isLiquidityContract
    ) internal returns (uint256 amountReceived, uint256 normalizedReceived) {
        // Transfers ETH, tracks received amount
        ICCLiquidity liquidityContract;
        ICCListing listing;
        if (isLiquidityContract) {
            liquidityContract = ICCLiquidity(contractAddr);
        } else {
            listing = ICCListing(contractAddr);
        }
        uint256 preBalance = recipientAddress.balance;
        bool success = true;
        if (isLiquidityContract) {
            try liquidityContract.transactNative(msg.sender, amountOut, recipientAddress) {
                // No return value expected
            } catch (bytes memory reason) {
                success = false;
                emit TransferFailed(msg.sender, address(0), amountOut, reason);
            }
            require(success, "Native transfer failed");
        } else {
            try listing.transactNative(amountOut, recipientAddress) {
                // No return value expected
            } catch (bytes memory reason) {
                success = false;
                emit TransferFailed(msg.sender, address(0), amountOut, reason);
            }
            require(success, "Native transfer failed");
        }
        uint256 postBalance = recipientAddress.balance;
        amountReceived = postBalance > preBalance ? postBalance - preBalance : 0;
        normalizedReceived = amountReceived > 0 ? normalize(amountReceived, 18) : 0;
    }

    function _transferToken(
        address contractAddr,
        address tokenAddress,
        uint256 amountOut,
        address recipientAddress,
        uint8 tokenDecimals,
        bool isLiquidityContract
    ) internal returns (uint256 amountReceived, uint256 normalizedReceived) {
        // Transfers ERC20 tokens, tracks received amount
        ICCLiquidity liquidityContract;
        ICCListing listing;
        if (isLiquidityContract) {
            liquidityContract = ICCLiquidity(contractAddr);
        } else {
            listing = ICCListing(contractAddr);
        }
        uint256 preBalance = IERC20(tokenAddress).balanceOf(recipientAddress);
        bool success = true;
        if (isLiquidityContract) {
            try liquidityContract.transactToken(msg.sender, tokenAddress, amountOut, recipientAddress) {
                // No return value expected
            } catch (bytes memory reason) {
                success = false;
                emit TransferFailed(msg.sender, tokenAddress, amountOut, reason);
            }
            require(success, "ERC20 transfer failed");
        } else {
            try listing.transactToken(tokenAddress, amountOut, recipientAddress) {
                // No return value expected
            } catch (bytes memory reason) {
                success = false;
                emit TransferFailed(msg.sender, tokenAddress, amountOut, reason);
            }
            require(success, "ERC20 transfer failed");
        }
        uint256 postBalance = IERC20(tokenAddress).balanceOf(recipientAddress);
        amountReceived = postBalance > preBalance ? postBalance - preBalance : 0;
        normalizedReceived = amountReceived > 0 ? normalize(amountReceived, tokenDecimals) : 0;
    }

    function settleSingleLongLiquid(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ICCListing.PayoutUpdate[] memory updates) {
        // Settles single long liquidation payout using liquidity pool
        ICCListing listing = ICCListing(listingAddress);
        ICCListing.LongPayoutStruct memory payout = listing.getLongPayout(orderIdentifier);
        if (payout.required == 0) {
            updates = new ICCListing.PayoutUpdate[](1);
            updates[0] = ICCListing.PayoutUpdate({
                payoutType: 0, // Long
                recipient: payout.recipientAddress,
                required: 0,
                filled: 0,
                amountSent: 0
            });
            listing.ssUpdate(updates);
            return updates;
        }
        PayoutContext memory context = _prepPayoutContext(listingAddress, orderIdentifier, true);
        context.recipientAddress = payout.recipientAddress;
        context.amountOut = denormalize(payout.required, context.tokenDecimals);
        if (!_checkLiquidityBalance(context, payout.required, true)) {
            return new ICCListing.PayoutUpdate[](0);
        }
        uint256 amountReceived;
        uint256 normalizedReceived;
        if (context.tokenOut == address(0)) {
            uint256 preBalance = context.recipientAddress.balance;
            (amountReceived, normalizedReceived) = _transferNative(
                payable(context.liquidityAddr),
                context.amountOut,
                context.recipientAddress,
                true
            );
            amountReceived = context.recipientAddress.balance > preBalance
                ? context.recipientAddress.balance - preBalance
                : 0;
            normalizedReceived = amountReceived > 0 ? normalize(amountReceived, context.tokenDecimals) : 0;
        } else {
            uint256 preBalance = IERC20(context.tokenOut).balanceOf(context.recipientAddress);
            (amountReceived, normalizedReceived) = _transferToken(
                context.liquidityAddr,
                context.tokenOut,
                context.amountOut,
                context.recipientAddress,
                context.tokenDecimals,
                true
            );
            amountReceived = IERC20(context.tokenOut).balanceOf(context.recipientAddress) > preBalance
                ? IERC20(context.tokenOut).balanceOf(context.recipientAddress) - preBalance
                : 0;
            normalizedReceived = amountReceived > 0 ? normalize(amountReceived, context.tokenDecimals) : 0;
        }
        if (normalizedReceived == 0) {
            return new ICCListing.PayoutUpdate[](0);
        }
        payoutPendingAmounts[listingAddress][orderIdentifier] -= payout.required;
        updates = new ICCListing.PayoutUpdate[](1);
        updates[0] = ICCListing.PayoutUpdate({
            payoutType: 0, // Long
            recipient: payout.recipientAddress,
            required: payout.required,
            filled: payout.required, // Full amount withdrawn
            amountSent: normalizedReceived // Tax-affected amount
        });
        listing.ssUpdate(updates);
    }

    function settleSingleShortLiquid(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ICCListing.PayoutUpdate[] memory updates) {
        // Settles single short liquidation payout using liquidity pool
        ICCListing listing = ICCListing(listingAddress);
        ICCListing.ShortPayoutStruct memory payout = listing.getShortPayout(orderIdentifier);
        if (payout.amount == 0) {
            updates = new ICCListing.PayoutUpdate[](1);
            updates[0] = ICCListing.PayoutUpdate({
                payoutType: 1, // Short
                recipient: payout.recipientAddress,
                required: 0,
                filled: 0,
                amountSent: 0
            });
            listing.ssUpdate(updates);
            return updates;
        }
        PayoutContext memory context = _prepPayoutContext(listingAddress, orderIdentifier, false);
        context.recipientAddress = payout.recipientAddress;
        context.amountOut = denormalize(payout.amount, context.tokenDecimals);
        if (!_checkLiquidityBalance(context, payout.amount, false)) {
            return new ICCListing.PayoutUpdate[](0);
        }
        uint256 amountReceived;
        uint256 normalizedReceived;
        if (context.tokenOut == address(0)) {
            uint256 preBalance = context.recipientAddress.balance;
            (amountReceived, normalizedReceived) = _transferNative(
                payable(context.liquidityAddr),
                context.amountOut,
                context.recipientAddress,
                true
            );
            amountReceived = context.recipientAddress.balance > preBalance
                ? context.recipientAddress.balance - preBalance
                : 0;
            normalizedReceived = amountReceived > 0 ? normalize(amountReceived, context.tokenDecimals) : 0;
        } else {
            uint256 preBalance = IERC20(context.tokenOut).balanceOf(context.recipientAddress);
            (amountReceived, normalizedReceived) = _transferToken(
                context.liquidityAddr,
                context.tokenOut,
                context.amountOut,
                context.recipientAddress,
                context.tokenDecimals,
                true
            );
            amountReceived = IERC20(context.tokenOut).balanceOf(context.recipientAddress) > preBalance
                ? IERC20(context.tokenOut).balanceOf(context.recipientAddress) - preBalance
                : 0;
            normalizedReceived = amountReceived > 0 ? normalize(amountReceived, context.tokenDecimals) : 0;
        }
        if (normalizedReceived == 0) {
            return new ICCListing.PayoutUpdate[](0);
        }
        payoutPendingAmounts[listingAddress][orderIdentifier] -= payout.amount;
        updates = new ICCListing.PayoutUpdate[](1);
        updates[0] = ICCListing.PayoutUpdate({
            payoutType: 1, // Short
            recipient: payout.recipientAddress,
            required: payout.amount,
            filled: payout.amount, // Full amount withdrawn
            amountSent: normalizedReceived // Tax-affected amount
        });
        listing.ssUpdate(updates);
    }
}