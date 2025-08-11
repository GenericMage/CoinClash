// SPDX-License-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.47
// Change Log:
// - 2025-08-11: Created MultiController with continueHop, execution, and control functions.
// - 2025-08-11: Added MultiStorage state variable with owner-only setter.
// - 2025-08-11: Updated to use MultiStorage.MHUpdate for hop data updates.
// - 2025-08-11: Ensured no reserved keywords, proper error handling, and external calls to MultiStorage.

import "./imports/ReentrancyGuard.sol";
import "./imports/IERC20.sol";

interface ISSListing {
    struct UpdateType {
        string field;
        uint256 value;
    }
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function listingPriceView() external view returns (uint256);
    function listingVolumeBalancesView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function getNextOrderId() external view returns (uint256);
    function getBuyOrderCore(uint256 orderId) external view returns (address makerAddress, address recipient, uint8 status);
    function getSellOrderCore(uint256 orderId) external view returns (address makerAddress, address recipient, uint8 status);
    function getBuyOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent);
    function getSellOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent);
    function update(UpdateType[] memory updates) external;
}

interface ICCSettlementRouter {
    function settleBuyOrders(address listingAddress, uint256 maxIterations) external;
    function settleSellOrders(address listingAddress, uint256 maxIterations) external;
}

interface ICCLiquidRouter {
    function settleBuyLiquid(address listingAddress, uint256 maxIterations) external;
    function settleSellLiquid(address listingAddress, uint256 maxIterations) external;
}

interface MultiStorage {
    struct SettlementRouter {
        address router;
        uint8 routerType;
    }
    struct LiquidRouter {
        address router;
        uint8 routerType;
    }
    struct StalledHop {
        uint8 stage;
        address currentListing;
        uint256 orderID;
        uint256 minPrice;
        uint256 maxPrice;
        address hopMaker;
        address[] remainingListings;
        uint256 principalAmount;
        address startToken;
        address endToken;
        uint8 settleType;
        uint8 hopStatus;
        uint256 maxIterations;
    }
    struct HopUpdateType {
        string field;
        uint256 value;
    }
    struct StallData {
        uint256 hopId;
        address listing;
        uint256 orderId;
        bool isBuy;
        uint256 pending;
        uint256 filled;
        uint8 status;
        uint256 amountSent;
        address hopMaker;
    }
    struct HopExecutionData {
        address listing;
        bool isBuy;
        address recipient;
        uint256 priceLimit;
        uint256 principal;
        address inputToken;
        uint8 settleType;
        uint256 maxIterations;
        HopUpdateType[] updates;
    }
    struct OrderUpdateData {
        address listing;
        address recipient;
        uint256 inputAmount;
        uint256 priceLimit;
        address inputToken;
    }
    struct HopExecutionParams {
        address[] listingAddresses;
        uint256[] impactPricePercents;
        address startToken;
        address endToken;
        uint8 settleType;
        uint256 maxIterations;
        uint256 numListings;
    }
    struct OrderParams {
        address listing;
        uint256 principal;
        uint256 impactPercent;
        uint256 index;
        uint256 numListings;
        uint256 maxIterations;
        uint8 settleType;
    }
    struct HopPrepData {
        uint256 hopId;
        uint256[] indices;
        bool[] isBuy;
        address currentToken;
        uint256 principal;
        address maker;
        bool isNative;
    }
    function settlementRouters() external view returns (SettlementRouter[] memory);
    function liquidRouters() external view returns (LiquidRouter[] memory);
    function agent() external view returns (address);
    function hopID(uint256 hopId) external view returns (StalledHop memory);
    function hopsByAddress(address user) external view returns (uint256[] memory);
    function totalHops() external view returns (uint256[] memory);
    function nextHopId() external view returns (uint256);
    function MHUpdate(uint256 hopId, StalledHop memory hopData, uint256[] memory userHops, bool addToTotalHops) external;
}

contract MultiController is ReentrancyGuard {
    MultiStorage public multiStorage;

    event HopContinued(uint256 indexed hopId, uint8 newStage);
    event StallsPrepared(uint256 indexed hopId, uint256 count);
    event StallsExecuted(uint256 indexed hopId, uint256 count);

    function setMultiStorage(address storageAddress) external onlyOwner {
        // Sets MultiStorage contract address
        require(storageAddress != address(0), "Invalid storage address");
        multiStorage = MultiStorage(storageAddress);
    }

    function getTokenDecimals(address token) internal view returns (uint8 decimals) {
        // Returns token decimals, defaults to 18 for native
        if (token == address(0)) return 18;
        decimals = IERC20(token).decimals();
        require(decimals <= 18, "Token decimals exceed 18");
    }

    function denormalizeForToken(uint256 amount, address token) internal view returns (uint256 denormalizedAmount) {
        // Converts normalized amount to token-specific decimals
        if (token == address(0)) return amount;
        uint256 decimals = IERC20(token).decimals();
        require(decimals <= 18, "Token decimals exceed 18");
        denormalizedAmount = amount * (10 ** decimals);
    }

    function normalizeForToken(uint256 amount, address token) internal view returns (uint256 normalizedAmount) {
        // Converts token amount to normalized value
        if (token == address(0)) return amount;
        uint256 decimals = IERC20(token).decimals();
        require(decimals <= 18, "Token decimals exceed 18");
        normalizedAmount = amount / (10 ** decimals);
    }

    function _createHopOrderNative(MultiStorage.OrderUpdateData memory orderData, address sender) internal returns (uint256 orderId) {
        // Creates a native order on the listing
        require(orderData.listing != address(0), "Listing address cannot be zero");
        require(orderData.recipient != address(0), "Recipient address cannot be zero");
        require(orderData.inputAmount > 0, "Input amount must be positive");
        ISSListing listingContract = ISSListing(orderData.listing);
        orderId = listingContract.getNextOrderId();
        uint256 rawAmount = orderData.inputAmount;
        uint256 transferredAmount = _checkTransferNative(orderData.listing, rawAmount);
        require(transferredAmount == rawAmount, "Native transferred amount mismatch");
        MultiStorage.HopUpdateType[] memory hopUpdates = new MultiStorage.HopUpdateType[](4);
        setOrderStatus(hopUpdates, 0);
        setOrderAmount(hopUpdates, 1, orderData.inputToken == listingContract.tokenB() ? "buyAmount" : "sellAmount", orderData.inputAmount);
        setOrderPrice(hopUpdates, 2, orderData.inputToken == listingContract.tokenB() ? "buyPrice" : "sellPrice", orderData.priceLimit);
        setOrderRecipient(hopUpdates, 3, orderData.recipient);
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](hopUpdates.length);
        for (uint256 i = 0; i < hopUpdates.length; i++) {
            updates[i] = ISSListing.UpdateType({ field: hopUpdates[i].field, value: hopUpdates[i].value });
        }
        try listingContract.update(updates) {
            // Order created successfully
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Native order creation failed: ", reason)));
        }
    }

    function _createHopOrderToken(MultiStorage.OrderUpdateData memory orderData, address sender) internal returns (uint256 orderId) {
        // Creates a token order on the listing
        require(orderData.listing != address(0), "Listing address cannot be zero");
        require(orderData.recipient != address(0), "Recipient address cannot be zero");
        require(orderData.inputAmount > 0, "Input amount must be positive");
        require(orderData.inputToken != address(0), "Invalid token address");
        ISSListing listingContract = ISSListing(orderData.listing);
        orderId = listingContract.getNextOrderId();
        uint256 rawAmount = denormalizeForToken(orderData.inputAmount, orderData.inputToken);
        bool success = IERC20(orderData.inputToken).transferFrom(sender, address(this), rawAmount);
        require(success, "Token transfer from sender failed");
        success = IERC20(orderData.inputToken).approve(orderData.listing, rawAmount);
        require(success, "Token approval for listing failed");
        uint256 transferredAmount = _checkTransferToken(orderData.inputToken, address(this), orderData.listing, rawAmount);
        require(transferredAmount == rawAmount, "Token transferred amount mismatch");
        MultiStorage.HopUpdateType[] memory hopUpdates = new MultiStorage.HopUpdateType[](4);
        setOrderStatus(hopUpdates, 0);
        setOrderAmount(hopUpdates, 1, orderData.inputToken == listingContract.tokenB() ? "buyAmount" : "sellAmount", orderData.inputAmount);
        setOrderPrice(hopUpdates, 2, orderData.inputToken == listingContract.tokenB() ? "buyPrice" : "sellPrice", orderData.priceLimit);
        setOrderRecipient(hopUpdates, 3, orderData.recipient);
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](hopUpdates.length);
        for (uint256 i = 0; i < hopUpdates.length; i++) {
            updates[i] = ISSListing.UpdateType({ field: hopUpdates[i].field, value: hopUpdates[i].value });
        }
        try listingContract.update(updates) {
            // Order created successfully
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Token order creation failed: ", reason)));
        }
    }

    function _checkTransferNative(address to, uint256 amount) internal returns (uint256 transferredAmount) {
        // Transfers native currency and checks balance
        require(to != address(0), "Recipient address cannot be zero");
        require(amount > 0, "Transfer amount must be positive");
        uint256 balanceBefore = address(to).balance;
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "Native transfer failed");
        uint256 balanceAfter = address(to).balance;
        require(balanceAfter > balanceBefore, "Native transfer did not increase balance");
        transferredAmount = balanceAfter - balanceBefore;
    }

    function _checkTransferToken(address token, address from, address to, uint256 amount) internal returns (uint256 transferredAmount) {
        // Transfers ERC20 token and checks balance
        require(token != address(0), "Invalid token address");
        require(to != address(0), "Recipient address cannot be zero");
        require(amount > 0, "Transfer amount must be positive");
        uint256 balanceBefore = IERC20(token).balanceOf(to);
        bool success = IERC20(token).transferFrom(from, to, amount);
        require(success, "ERC20 transfer failed");
        uint256 balanceAfter = IERC20(token).balanceOf(to);
        require(balanceAfter > balanceBefore, "Token transfer did not increase balance");
        transferredAmount = balanceAfter - balanceBefore;
    }

    function computeBuyOrderParams(MultiStorage.OrderParams memory params, address maker) internal view returns (MultiStorage.HopExecutionData memory execData) {
        // Computes parameters for a buy order
        ISSListing listing = ISSListing(params.listing);
        uint256 priceLimit = _validatePriceImpact(params.listing, params.principal, true, params.impactPercent);
        MultiStorage.HopUpdateType[] memory updates = new MultiStorage.HopUpdateType[](4);
        setOrderStatus(updates, 0);
        setOrderAmount(updates, 1, "buyAmount", params.principal);
        setOrderPrice(updates, 2, "buyPrice", priceLimit);
        setOrderRecipient(updates, 3, maker);
        execData = MultiStorage.HopExecutionData({
            listing: params.listing,
            isBuy: true,
            recipient: maker,
            priceLimit: priceLimit,
            principal: params.principal,
            inputToken: listing.tokenB(),
            settleType: params.settleType,
            maxIterations: params.maxIterations,
            updates: updates
        });
    }

    function computeSellOrderParams(MultiStorage.OrderParams memory params, address maker) internal view returns (MultiStorage.HopExecutionData memory execData) {
        // Computes parameters for a sell order
        ISSListing listing = ISSListing(params.listing);
        uint256 priceLimit = _validatePriceImpact(params.listing, params.principal, false, params.impactPercent);
        MultiStorage.HopUpdateType[] memory updates = new MultiStorage.HopUpdateType[](4);
        setOrderStatus(updates, 0);
        setOrderAmount(updates, 1, "sellAmount", params.principal);
        setOrderPrice(updates, 2, "sellPrice", priceLimit);
        setOrderRecipient(updates, 3, maker);
        execData = MultiStorage.HopExecutionData({
            listing: params.listing,
            isBuy: false,
            recipient: maker,
            priceLimit: priceLimit,
            principal: params.principal,
            inputToken: listing.tokenA(),
            settleType: params.settleType,
            maxIterations: params.maxIterations,
            updates: updates
        });
    }

    function _validatePriceImpact(address listing, uint256 inputAmount, bool isBuy, uint256 impactPercent)
        internal view returns (uint256 impactPrice)
    {
        // Validates price impact for an order
        require(listing != address(0), "Listing address cannot be zero");
        ISSListing listingContract = ISSListing(listing);
        (uint256 xBalance, uint256 yBalance, , ) = listingContract.listingVolumeBalancesView();
        require(xBalance > 0 && yBalance > 0, "Invalid listing balances");
        uint256 amountOut = isBuy ? (inputAmount * xBalance) / yBalance : (inputAmount * yBalance) / xBalance;
        uint256 newXBalance = isBuy ? xBalance - amountOut : xBalance + inputAmount;
        uint256 newYBalance = isBuy ? yBalance + inputAmount : yBalance - amountOut;
        require(newYBalance > 0, "Resulting yBalance cannot be zero");
        impactPrice = (newXBalance * 1e18) / newYBalance;
        uint256 currentPrice = listingContract.listingPriceView();
        require(currentPrice > 0, "Current listing price is zero");
        uint256 limitPrice = isBuy ? (currentPrice * (10000 + impactPercent)) / 10000 : (currentPrice * (10000 - impactPercent)) / 10000;
        require(isBuy ? impactPrice <= limitPrice : impactPrice >= limitPrice, "Price impact exceeds limit");
    }

    function checkOrderStatus(address listing, uint256 orderId, bool isBuy)
        internal view returns (uint256 pending, uint256 filled, uint8 status, uint256 amountSent)
    {
        // Checks the status of an order
        require(listing != address(0), "Listing address cannot be zero");
        ISSListing listingContract = ISSListing(listing);
        if (isBuy) {
            (, , status) = listingContract.getBuyOrderCore(orderId);
            (pending, filled, amountSent) = listingContract.getBuyOrderAmounts(orderId);
        } else {
            (, , status) = listingContract.getSellOrderCore(orderId);
            (pending, filled, amountSent) = listingContract.getSellOrderAmounts(orderId);
        }
        require(status <= 3, "Invalid order status");
    }

    function safeSettle(address listing, bool isBuy, uint8 settleType, uint256 maxIterations)
        internal
    {
        // Safely settles orders using routers
        require(listing != address(0), "Listing address cannot be zero");
        require(maxIterations > 0, "Max iterations must be positive");
        require(settleType <= 1, "Invalid settle type");
        if (settleType == 0) {
            MultiStorage.SettlementRouter[] memory routers = multiStorage.settlementRouters();
            require(routers.length > 0, "No settlement routers configured");
            for (uint256 i = 0; i < routers.length; i++) {
                if (routers[i].routerType != 1) continue;
                ICCSettlementRouter router = ICCSettlementRouter(routers[i].router);
                try router.settleBuyOrders(listing, maxIterations) {
                    if (!isBuy) try router.settleSellOrders(listing, maxIterations) {} catch Error(string memory reason) {
                        revert(string(abi.encodePacked("Settlement router sell failed: ", reason)));
                    }
                } catch Error(string memory reason) {
                    revert(string(abi.encodePacked("Settlement router buy failed: ", reason)));
                }
            }
        } else {
            MultiStorage.LiquidRouter[] memory routers = multiStorage.liquidRouters();
            require(routers.length > 0, "No liquid routers configured");
            for (uint256 i = 0; i < routers.length; i++) {
                if (routers[i].routerType != 2) continue;
                ICCLiquidRouter router = ICCLiquidRouter(routers[i].router);
                try router.settleBuyLiquid(listing, maxIterations) {
                    if (!isBuy) try router.settleSellLiquid(listing, maxIterations) {} catch Error(string memory reason) {
                        revert(string(abi.encodePacked("Liquid router sell failed: ", reason)));
                    }
                } catch Error(string memory reason) {
                    revert(string(abi.encodePacked("Liquid router buy failed: ", reason)));
                }
            }
        }
    }

    function processHopStep(
        MultiStorage.HopExecutionData memory execData,
        address sender,
        bool isNative
    ) internal returns (bool completed, uint256 orderId, uint256 amountSent) {
        // Processes a single hop step
        require(execData.listing != address(0), "Invalid listing in execution data");
        require(execData.recipient != address(0), "Invalid recipient in execution data");
        MultiStorage.OrderUpdateData memory orderData = MultiStorage.OrderUpdateData({
            listing: execData.listing,
            recipient: execData.recipient,
            inputAmount: normalizeForToken(execData.principal, execData.inputToken),
            priceLimit: execData.priceLimit,
            inputToken: execData.inputToken
        });
        orderId = isNative ? _createHopOrderNative(orderData, sender) : _createHopOrderToken(orderData, sender);
        safeSettle(execData.listing, execData.isBuy, execData.settleType, execData.maxIterations);
        (uint256 pending, uint256 filled, uint8 status, uint256 receivedAmount) = checkOrderStatus(execData.listing, orderId, execData.isBuy);
        completed = status == 3 && pending == 0;
        amountSent = receivedAmount;
    }

    function executeHopSteps(
        MultiStorage.HopExecutionParams memory params,
        MultiStorage.HopPrepData memory prepData
    ) internal returns (uint256 principal, address currentToken) {
        // Executes hop steps until completion or stall
        require(prepData.hopId < multiStorage.nextHopId(), "Invalid hop ID");
        require(params.numListings > 0, "No listings to execute");
        MultiStorage.StalledHop memory stalledHop = multiStorage.hopID(prepData.hopId);
        principal = prepData.principal;
        currentToken = prepData.currentToken;
        address maker = prepData.maker;
        for (uint256 i = 0; i < prepData.indices.length; i++) {
            MultiStorage.OrderParams memory orderParams = MultiStorage.OrderParams({
                listing: params.listingAddresses[prepData.indices[i]],
                principal: principal,
                impactPercent: params.impactPricePercents[prepData.indices[i]],
                index: i,
                numListings: params.numListings,
                maxIterations: params.maxIterations,
                settleType: params.settleType
            });
            MultiStorage.HopExecutionData memory execData = prepData.isBuy[i]
                ? computeBuyOrderParams(orderParams, maker)
                : computeSellOrderParams(orderParams, maker);
            (bool completed, uint256 orderId, uint256 amountSent) = processHopStep(execData, maker, prepData.isNative);
            if (!completed) {
                stalledHop.orderID = orderId;
                stalledHop.minPrice = execData.isBuy ? 0 : execData.priceLimit;
                stalledHop.maxPrice = execData.isBuy ? execData.priceLimit : 0;
                stalledHop.currentListing = execData.listing;
                stalledHop.stage = uint8(i);
                stalledHop.principalAmount = amountSent;
                address[] memory newRemaining = new address[](prepData.indices.length - i - 1);
                for (uint256 j = i + 1; j < prepData.indices.length; j++) {
                    newRemaining[j - i - 1] = params.listingAddresses[prepData.indices[j]];
                }
                stalledHop.remainingListings = newRemaining;
                multiStorage.MHUpdate(prepData.hopId, stalledHop, multiStorage.hopsByAddress(maker), false);
                emit HopContinued(prepData.hopId, uint8(i));
                return (principal, currentToken);
            }
            principal = amountSent;
            currentToken = execData.isBuy ? ISSListing(execData.listing).tokenA() : ISSListing(execData.listing).tokenB();
        }
        stalledHop.hopStatus = 2;
        uint256[] memory userHops = multiStorage.hopsByAddress(maker);
        uint256[] memory newUserHops = new uint256[](userHops.length);
        uint256 newIndex = 0;
        for (uint256 i = 0; i < userHops.length; i++) {
            if (userHops[i] != prepData.hopId) {
                newUserHops[newIndex] = userHops[i];
                newIndex++;
            }
        }
        uint256[] memory resizedUserHops = new uint256[](newIndex);
        for (uint256 i = 0; i < newIndex; i++) {
            resizedUserHops[i] = newUserHops[i];
        }
        multiStorage.MHUpdate(prepData.hopId, stalledHop, resizedUserHops, false);
        emit HopContinued(prepData.hopId, uint8(prepData.indices.length));
        return (principal, currentToken);
    }

    function continueHop(uint256 hopId, uint256 maxIterations) external nonReentrant {
        // Continues a stalled hop
        require(hopId < multiStorage.nextHopId(), "Invalid hop ID");
        require(maxIterations > 0, "Max iterations must be positive");
        MultiStorage.StalledHop memory stalledHop = multiStorage.hopID(hopId);
        require(stalledHop.hopStatus == 1, "Hop is not pending");
        require(stalledHop.hopMaker == msg.sender, "Caller is not hop maker");
        MultiStorage.HopPrepData memory prepData = MultiStorage.HopPrepData({
            hopId: hopId,
            indices: new uint256[](stalledHop.remainingListings.length + 1),
            isBuy: new bool[](stalledHop.remainingListings.length + 1),
            currentToken: stalledHop.startToken,
            principal: stalledHop.principalAmount,
            maker: stalledHop.hopMaker,
            isNative: stalledHop.startToken == address(0)
        });
        MultiStorage.HopExecutionParams memory params;
        params.numListings = stalledHop.remainingListings.length + 1;
        params.listingAddresses = new address[](params.numListings);
        params.impactPricePercents = new uint256[](params.numListings);
        params.listingAddresses[0] = stalledHop.currentListing;
        params.impactPricePercents[0] = 500;
        for (uint256 i = 0; i < stalledHop.remainingListings.length; i++) {
            params.listingAddresses[i + 1] = stalledHop.remainingListings[i];
            params.impactPricePercents[i + 1] = 500;
            prepData.indices[i + 1] = i + 1;
            prepData.isBuy[i + 1] = stalledHop.endToken == ISSListing(stalledHop.remainingListings[i]).tokenA();
        }
        prepData.indices[0] = 0;
        prepData.isBuy[0] = stalledHop.maxPrice > 0;
        params.startToken = stalledHop.startToken;
        params.endToken = stalledHop.endToken;
        params.settleType = stalledHop.settleType;
        params.maxIterations = maxIterations;
        executeHopSteps(params, prepData);
    }

    function prepStalls() internal returns (MultiStorage.StallData[] memory stalls) {
        // Prepares stalled hop data
        uint256[] memory totalHopsList = multiStorage.totalHops();
        stalls = new MultiStorage.StallData[](totalHopsList.length);
        uint256 count = 0;
        for (uint256 i = 0; i < totalHopsList.length && count < 20; i++) {
            MultiStorage.StalledHop memory stalledHop = multiStorage.hopID(totalHopsList[i]);
            if (stalledHop.hopStatus != 1) continue;
            (uint256 pending, uint256 filled, uint8 status, uint256 amountSent) = checkOrderStatus(
                stalledHop.currentListing, stalledHop.orderID, stalledHop.maxPrice > 0
            );
            stalls[count] = MultiStorage.StallData({
                hopId: totalHopsList[i],
                listing: stalledHop.currentListing,
                orderId: stalledHop.orderID,
                isBuy: stalledHop.maxPrice > 0,
                pending: pending,
                filled: filled,
                status: status,
                amountSent: amountSent,
                hopMaker: stalledHop.hopMaker
            });
            count++;
        }
        MultiStorage.StallData[] memory resizedStalls = new MultiStorage.StallData[](count);
        for (uint256 i = 0; i < count; i++) {
            resizedStalls[i] = stalls[i];
        }
        emit StallsPrepared(0, count);
        return resizedStalls;
    }

    function executeStalls(uint256 maxIterations) external nonReentrant {
        // Executes stalled hops
        require(maxIterations > 0, "Max iterations must be positive");
        MultiStorage.StallData[] memory stalls = prepStalls();
        uint256 count = 0;
        for (uint256 i = 0; i < stalls.length && count < maxIterations; i++) {
            if (stalls[i].hopId == 0) continue;
            MultiStorage.StalledHop memory stalledHop = multiStorage.hopID(stalls[i].hopId);
            if (stalledHop.hopStatus != 1) continue;
            MultiStorage.HopPrepData memory prepData = MultiStorage.HopPrepData({
                hopId: stalls[i].hopId,
                indices: new uint256[](stalledHop.remainingListings.length + 1),
                isBuy: new bool[](stalledHop.remainingListings.length + 1),
                currentToken: stalledHop.startToken,
                principal: stalledHop.principalAmount,
                maker: stalledHop.hopMaker,
                isNative: stalledHop.startToken == address(0)
            });
            MultiStorage.HopExecutionParams memory params;
            params.numListings = stalledHop.remainingListings.length + 1;
            params.listingAddresses = new address[](params.numListings);
            params.impactPricePercents = new uint256[](params.numListings);
            params.listingAddresses[0] = stalledHop.currentListing;
            params.impactPricePercents[0] = 500;
            for (uint256 j = 0; j < stalledHop.remainingListings.length; j++) {
                params.listingAddresses[j + 1] = stalledHop.remainingListings[j];
                params.impactPricePercents[j + 1] = 500;
                prepData.indices[j + 1] = j + 1;
                prepData.isBuy[j + 1] = stalledHop.endToken == ISSListing(stalledHop.remainingListings[j]).tokenA();
            }
            prepData.indices[0] = 0;
            prepData.isBuy[0] = stalledHop.maxPrice > 0;
            params.startToken = stalledHop.startToken;
            params.endToken = stalledHop.endToken;
            params.settleType = stalledHop.settleType;
            params.maxIterations = maxIterations;
            executeHopSteps(params, prepData);
            count++;
        }
        emit StallsExecuted(0, count);
    }

    function setOrderStatus(MultiStorage.HopUpdateType[] memory updates, uint256 index) internal pure {
        // Sets order status in updates array
        require(index < updates.length, "Invalid update index");
        updates[index] = MultiStorage.HopUpdateType({ field: "status", value: uint256(1) });
    }

    function setOrderAmount(MultiStorage.HopUpdateType[] memory updates, uint256 index, string memory orderType, uint256 amount) internal pure {
        // Sets order amount in updates array
        require(index < updates.length, "Invalid update index");
        updates[index] = MultiStorage.HopUpdateType({ field: orderType, value: amount });
    }

    function setOrderPrice(MultiStorage.HopUpdateType[] memory updates, uint256 index, string memory priceType, uint256 price) internal pure {
        // Sets order price in updates array
        require(index < updates.length, "Invalid update index");
        updates[index] = MultiStorage.HopUpdateType({ field: priceType, value: price });
    }

    function setOrderRecipient(MultiStorage.HopUpdateType[] memory updates, uint256 index, address recipient) internal pure {
        // Sets order recipient in updates array
        require(index < updates.length, "Invalid update index");
        updates[index] = MultiStorage.HopUpdateType({ field: "recipient", value: uint256(uint160(recipient)) });
    }
}