// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.7 (Updated)
// Changes:
// - v0.0.7: Fixed TypeError in _transferNative/_transferToken by removing incorrect returns clause in try blocks.
// - v0.0.6: Fixed ParserError in _transferNative by correcting try block syntax.
// - v0.0.5: Removed inlined ICCListing/ICCLiquidity, used CCMainPartial interfaces, aligned with ICCLiquidityTemplate, made depositNative/TransactNative payable.
// - v0.0.4: Split _transferPayoutAmount/_TransferListingPayouts into _transferNative/_transferToken, aligned with ICCLiquidity depositToken/depositNative.
// - v0.0.3: Created from SSPayoutPartial.sol v0.0.58, extracted liquidity functions, used ICCListing/ICCLiquidity, split transact calls.
// - v0.0.2: Modified settleSingleLongLiquid/settleSingleShortLiquid to set zero-amount payouts to completed (3).
// - v0.0.1: Initial extraction from SSPayoutPartial.sol.

import "./CCMainPartial.sol";

contract CCLiquidityPartial is CCMainPartial {
    using SafeERC20 for IERC20;

    struct PayoutContext {
        address listingAddress;
        address liquidityAddr;
        address tokenOut;
        uint8 tokenDecimals;
        uint256 amountOut;
        address recipientAddress;
    }

    mapping(address => mapping(uint256 => uint256)) internal payoutPendingAmounts;

    function _prepPayoutContext(
        address listingAddress,
        uint256 orderId,
        bool isLong
    ) internal view returns (PayoutContext memory context) {
        // Prepares payout context
        ICCListing listing = ICCListing(listingAddress);
        context = PayoutContext({
            listingAddress: listingAddress,
            liquidityAddr: listing.liquidityAddressView(0),
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
        ICCLiquidityTemplate liquidityContract = ICCLiquidityTemplate(context.liquidityAddr);
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
        ICCLiquidityTemplate liquidityContract;
        ICCListing listing;
        if (isLiquidityContract) {
            liquidityContract = ICCLiquidityTemplate(contractAddr);
        } else {
            listing = ICCListing(contractAddr);
        }
        uint256 preBalance = recipientAddress.balance;
        bool success = true;
        if (isLiquidityContract) {
            try liquidityContract.transactNative(address(this), amountOut, recipientAddress) {
                // No return value expected
            } catch {
                success = false;
            }
            require(success, "Native transfer failed");
        } else {
            try listing.transactNative(address(this), amountOut, recipientAddress) {
                // No return value expected
            } catch {
                success = false;
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
        ICCLiquidityTemplate liquidityContract;
        ICCListing listing;
        if (isLiquidityContract) {
            liquidityContract = ICCLiquidityTemplate(contractAddr);
        } else {
            listing = ICCListing(contractAddr);
        }
        uint256 preBalance = IERC20(tokenAddress).balanceOf(recipientAddress);
        bool success = true;
        if (isLiquidityContract) {
            try liquidityContract.transactToken(address(this), tokenAddress, amountOut, recipientAddress) {
                // No return value expected
            } catch {
                success = false;
            }
            require(success, "ERC20 transfer failed");
        } else {
            try listing.transactToken(address(this), tokenAddress, amountOut, recipientAddress) {
                // No return value expected
            } catch {
                success = false;
            }
            require(success, "ERC20 transfer failed");
        }
        uint256 postBalance = IERC20(tokenAddress).balanceOf(recipientAddress);
        amountReceived = postBalance > preBalance ? postBalance - preBalance : 0;
        normalizedReceived = amountReceived > 0 ? normalize(amountReceived, tokenDecimals) : 0;
    }

    function _createPayoutUpdate(
        uint256 normalizedReceived,
        address recipientAddress,
        bool isLong
    ) internal pure returns (ICCListing.PayoutUpdate[] memory updates) {
        // Creates payout updates
        updates = new ICCListing.PayoutUpdate[](1);
        updates[0] = ICCListing.PayoutUpdate({
            payoutType: isLong ? 0 : 1,
            recipient: recipientAddress,
            required: normalizedReceived
        });
    }

    function settleSingleLongLiquid(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ICCListing.PayoutUpdate[] memory updates) {
        // Settles single long liquidation payout
        ICCListing listing = ICCListing(listingAddress);
        ICCListing.LongPayoutStruct memory payout = listing.getLongPayout(orderIdentifier);
        if (payout.required == 0) {
            updates = new ICCListing.PayoutUpdate[](1);
            updates[0] = ICCListing.PayoutUpdate({
                payoutType: 0,
                recipient: payout.recipientAddress,
                required: 0
            });
            ICCListing.UpdateType[] memory statusUpdate = new ICCListing.UpdateType[](1);
            statusUpdate[0] = ICCListing.UpdateType({
                updateType: 0,
                structId: 0,
                index: orderIdentifier,
                value: 3,
                addr: payout.makerAddress,
                recipient: payout.recipientAddress,
                maxPrice: 0,
                minPrice: 0,
                amountSent: 0
            });
            listing.update(address(this), statusUpdate);
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
            (amountReceived, normalizedReceived) = _transferNative(
                payable(context.liquidityAddr),
                context.amountOut,
                context.recipientAddress,
                true
            );
        } else {
            (amountReceived, normalizedReceived) = _transferToken(
                context.liquidityAddr,
                context.tokenOut,
                context.amountOut,
                context.recipientAddress,
                context.tokenDecimals,
                true
            );
        }
        if (normalizedReceived == 0) {
            return new ICCListing.PayoutUpdate[](0);
        }
        payoutPendingAmounts[listingAddress][orderIdentifier] -= normalizedReceived;
        updates = _createPayoutUpdate(normalizedReceived, payout.recipientAddress, true);
    }

    function settleSingleShortLiquid(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ICCListing.PayoutUpdate[] memory updates) {
        // Settles single short liquidation payout
        ICCListing listing = ICCListing(listingAddress);
        ICCListing.ShortPayoutStruct memory payout = listing.getShortPayout(orderIdentifier);
        if (payout.amount == 0) {
            updates = new ICCListing.PayoutUpdate[](1);
            updates[0] = ICCListing.PayoutUpdate({
                payoutType: 1,
                recipient: payout.recipientAddress,
                required: 0
            });
            ICCListing.UpdateType[] memory statusUpdate = new ICCListing.UpdateType[](1);
            statusUpdate[0] = ICCListing.UpdateType({
                updateType: 0,
                structId: 0,
                index: orderIdentifier,
                value: 3,
                addr: payout.makerAddress,
                recipient: payout.recipientAddress,
                maxPrice: 0,
                minPrice: 0,
                amountSent: 0
            });
            listing.update(address(this), statusUpdate);
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
            (amountReceived, normalizedReceived) = _transferNative(
                payable(context.liquidityAddr),
                context.amountOut,
                context.recipientAddress,
                true
            );
        } else {
            (amountReceived, normalizedReceived) = _transferToken(
                context.liquidityAddr,
                context.tokenOut,
                context.amountOut,
                context.recipientAddress,
                context.tokenDecimals,
                true
            );
        }
        if (normalizedReceived == 0) {
            return new ICCListing.PayoutUpdate[](0);
        }
        payoutPendingAmounts[listingAddress][orderIdentifier] -= normalizedReceived;
        updates = _createPayoutUpdate(normalizedReceived, payout.recipientAddress, false);
    }

    function executeLongPayouts(address listingAddress, uint256 maxIterations) internal onlyValidListing(listingAddress) {
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
            listing.ssUpdate(address(this), finalUpdates);
        }
    }

    function executeShortPayouts(address listingAddress, uint256 maxIterations) internal onlyValidListing(listingAddress) {
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
            listing.ssUpdate(address(this), finalUpdates);
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
}