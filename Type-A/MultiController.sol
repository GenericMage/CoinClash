// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.49
// Change Log:
// - 2025-08-12: Removed hard cap of 20 in prepStalls, using maxIterations instead.
// - 2025-08-12: Updated _createHopOrderNative and _createHopOrderToken to use received amount from MultiInitializer.

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
        // Creates a native order on the listing using received amount
        require(orderData.listing != address(0), "Listing address cannot be zero");
        require(orderData.recipient != address(0), "Recipient address cannot be zero");
        require(orderData.inputAmount > 0, "Input amount must be positive");
        ISSListing listingContract = ISSListing(orderData.listing);
        orderId = listingContract.getNextOrderId();
        uint256 rawAmount = orderData.inputAmount;
        uint256 balanceBefore = address(orderData.listing).balance;
        (bool success, ) = payable(orderData.listing).call{value: rawAmount}("");
        require(success, "Native transfer failed");
        uint256 balanceAfter = address(orderData.listing).balance;
        uint256 transferredAmount = balanceAfter - balanceBefore;
        require(transferredAmount == rawAmount, "Native transferred amount mismatch");
        MultiStorage.HopUpdateType[] memory hopUpdates = new MultiStorage.HopUpdateType[](4);
        setOrderStatus(hopUpdates, 0);
        setOrderAmount(hopUpdates, 1, orderData.inputToken == listingContract.tokenB() ? "buyAmount" : "sellAmount", transferredAmount);
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
        // Creates a token order on the listing using received amount
        require(orderData.listing != address(0), "Listing address cannot be zero");
        require(orderData.recipient != address(0), "Recipient address cannot be zero");
        require(orderData.inputAmount > 0, "Input amount must be positive");
        require(orderData.inputToken != address(0), "Invalid token address");
        ISSListing listingContract = ISSListing(orderData.listing);
        orderId = listingContract.getNextOrderId();
        uint256 rawAmount = denormalizeForToken(orderData.inputAmount, orderData.inputToken);
        uint256 balanceBefore = IERC20(orderData.inputToken).balanceOf(orderData.listing);
        bool success = IERC20(orderData.inputToken).approve(orderData.listing, rawAmount);
        require(success, "Token approval for listing failed");
        success = IERC20(orderData.inputToken).transferFrom(address(this), orderData.listing, rawAmount);
        require(success, "Token transfer from controller failed");
        uint256 balanceAfter = IERC20(orderData.inputToken).balanceOf(orderData.listing);
        uint256 transferredAmount = balanceAfter - balanceBefore;
        require(transferredAmount == rawAmount, "Token transferred amount mismatch");
        MultiStorage.HopUpdateType[] memory hopUpdates = new MultiStorage.HopUpdateType[](4);
        setOrderStatus(hopUpdates, 0);
        setOrderAmount(hopUpdates, 1, orderData.inputToken == listingContract.tokenB() ? "buyAmount" : "sellAmount", transferredAmount);
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
        transferredAmount = balanceAfter - balanceBefore;
        require(transferredAmount == amount, "Native transfer amount mismatch");
    }

    function _checkTransferToken(address token, address from, address to, uint256 amount) internal returns (uint256 transferredAmount) {
        // Transfers ERC20 token and checks balance
        require(token != address(0), "Invalid token address");
        require(to != address(0), "Recipient address cannot be zero");
        require(amount > 0, "Transfer amount must be positive");
        uint256 balanceBefore = IERC20(token).balanceOf(to);
        bool success = IERC20(token).transferFrom(from, to, amount);
        require(success, "Token transfer failed");
        uint256 balanceAfter = IERC20(token).balanceOf(to);
        transferredAmount = balanceAfter - balanceBefore;
        require(transferredAmount == amount, "Token transfer amount mismatch");
    }

    function _validatePriceImpact(address listing, bool isBuy, uint256 inputAmount, uint256 impactPercent) internal view returns (uint256 priceLimit) {
        // Validates price impact for the order
        ISSListing listingContract = ISSListing(listing);
        (uint256 xBalance, uint256 yBalance,,) = listingContract.listingVolumeBalancesView();
        uint256 currentPrice = listingContract.listingPriceView();
        uint256 newXBalance = isBuy ? xBalance : xBalance + inputAmount;
        uint256 newYBalance = isBuy ? yBalance + inputAmount : yBalance;
        uint256 impactPrice = (newXBalance * 1e18) / newYBalance;
        uint256 upperBound = (currentPrice * (10000 + impactPercent)) / 10000;
        uint256 lowerBound = (currentPrice * (10000 - impactPercent)) / 10000;
        require(impactPrice >= lowerBound && impactPrice <= upperBound, "Price impact out of bounds");
        priceLimit = isBuy ? upperBound : lowerBound;
    }

    function computeBuyOrderParams(MultiStorage.OrderParams memory params, address maker) internal view returns (MultiStorage.HopExecutionData memory execData) {
        // Computes parameters for a buy order
        ISSListing listingContract = ISSListing(params.listing);
        address inputToken = listingContract.tokenB();
        uint256 priceLimit = _validatePriceImpact(params.listing, true, params.principal, params.impactPercent);
        execData = MultiStorage.HopExecutionData({
            listing: params.listing,
            isBuy: true,
            recipient: maker,
            priceLimit: priceLimit,
            principal: params.principal,
            inputToken: inputToken,
            settleType: params.settleType,
            maxIterations: params.maxIterations,
            updates: new MultiStorage.HopUpdateType[](4)
        });
    }

    function computeSellOrderParams(MultiStorage.OrderParams memory params, address maker) internal view returns (MultiStorage.HopExecutionData memory execData) {
        // Computes parameters for a sell order
        ISSListing listingContract = ISSListing(params.listing);
        address inputToken = listingContract.tokenA();
        uint256 priceLimit = _validatePriceImpact(params.listing, false, params.principal, params.impactPercent);
        execData = MultiStorage.HopExecutionData({
            listing: params.listing,
            isBuy: false,
            recipient: maker,
            priceLimit: priceLimit,
            principal: params.principal,
            inputToken: inputToken,
            settleType: params.settleType,
            maxIterations: params.maxIterations,
            updates: new MultiStorage.HopUpdateType[](4)
        });
    }

    function safeSettle(address listing, bool isBuy, uint8 settleType, uint256 maxIterations) internal {
        // Safely settles orders via routers
        require(listing != address(0), "Invalid listing address");
        if (settleType == 0) {
            MultiStorage.SettlementRouter[] memory routers = multiStorage.settlementRouters();
            for (uint256 i = 0; i < routers.length; i++) {
                if (routers[i].routerType != 1) continue;
                try ICCSettlementRouter(routers[i].router).settleBuyOrders(listing, maxIterations) {
                    // Buy settlement successful
                } catch Error(string memory reason) {
                    emit SettlementFailed(listing, reason);
                }
                try ICCSettlementRouter(routers[i].router).settleSellOrders(listing, maxIterations) {
                    // Sell settlement successful
                } catch Error(string memory reason) {
                    emit SettlementFailed(listing, reason);
                }
            }
        } else if (settleType == 1) {
            MultiStorage.LiquidRouter[] memory routers = multiStorage.liquidRouters();
            for (uint256 i = 0; i < routers.length; i++) {
                if (routers[i].routerType != 2) continue;
                try ICCLiquidRouter(routers[i].router).settleBuyLiquid(listing, maxIterations) {
                    // Buy liquid settlement successful
                } catch Error(string memory reason) {
                    emit SettlementFailed(listing, reason);
                }
                try ICCLiquidRouter(routers[i].router).settleSellLiquid(listing, maxIterations) {
                    // Sell liquid settlement successful
                } catch Error(string memory reason) {
                    emit SettlementFailed(listing, reason);
                }
            }
        } else {
            revert("Invalid settle type");
        }
    }

    event SettlementFailed(address indexed listing, string reason);

    function checkOrderStatus(address listing, uint256 orderId, bool isBuy) internal view returns (uint256 pending, uint256 filled, uint8 status, uint256 amountSent) {
        // Checks order status and amounts
        require(listing != address(0), "Invalid listing address");
        ISSListing listingContract = ISSListing(listing);
        if (isBuy) {
            (, , status) = listingContract.getBuyOrderCore(orderId);
            (pending, filled, amountSent) = listingContract.getBuyOrderAmounts(orderId);
        } else {
            (, , status) = listingContract.getSellOrderCore(orderId);
            (pending, filled, amountSent) = listingContract.getSellOrderAmounts(orderId);
        }
    }

    function processHopStep(
        MultiStorage.HopExecutionData memory execData,
        address sender,
        bool isNative
    ) internal returns (bool completed, uint256 orderId, uint256 amountSent) {
        // Processes a single hop step
        MultiStorage.OrderUpdateData memory orderData = MultiStorage.OrderUpdateData({
            listing: execData.listing,
            recipient: execData.recipient,
            inputAmount: execData.principal,
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

    function prepStalls(uint256 maxIterations) internal returns (MultiStorage.StallData[] memory stalls) {
        // Prepares stalled hop data up to maxIterations
        require(maxIterations > 0, "Max iterations must be positive");
        uint256[] memory totalHopsList = multiStorage.totalHops();
        stalls = new MultiStorage.StallData[](totalHopsList.length);
        uint256 count = 0;
        for (uint256 i = 0; i < totalHopsList.length && count < maxIterations; i++) {
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
        MultiStorage.StallData[] memory stalls = prepStalls(maxIterations);
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