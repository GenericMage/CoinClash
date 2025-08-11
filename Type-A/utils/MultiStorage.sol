// SPDX-License-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.49
// Change Log:
// - 2025-08-11: Added cancellation functions (cancelHop, cancelAll, etc.) from MultiInitializer.sol.
// - 2025-08-11: Updated cancellation functions to use this.MHUpdate and this.updateHopField.
// - 2025-08-11: Added updateHopField function for incremental StalledHop updates.
// - 2025-08-11: Clarified MHUpdate supports incremental updates via hopID overwrite.
// - 2025-08-11: Created MultiStorage to hold shared data, mux array, and MHUpdate function.

import "../imports/ReentrancyGuard.sol";
import "../imports/IERC20.sol";

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

interface ISSAgent {
    function getListing(address listing) external view returns (bool);
}

contract MultiStorage is ReentrancyGuard {
    struct SettlementRouter {
        address router; // Settlement router contract address
        uint8 routerType; // 1 = SettlementRouter
    }
    struct LiquidRouter {
        address router; // Liquid router contract address
        uint8 routerType; // 2 = LiquidRouter
    }
    struct HopUpdateType {
        string field;
        uint256 value;
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
    struct CancelPrepData {
        uint256 hopId;
        address listing;
        bool isBuy;
        address outputToken;
        address inputToken;
        uint256 pending;
        uint256 filled;
        uint8 status;
        uint256 receivedAmount;
        address recipient;
        uint256 refundedPending;
    }
    struct CancelBalanceData {
        address token;
        uint256 balanceBefore;
        uint256 balanceAfter;
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
    struct HopRouteData {
        address[] listings;
        bool[] isBuy;
    }
    struct HopOrderDetails {
        uint256 pending;
        uint256 filled;
        uint8 status;
        uint256 amountSent;
        address recipient;
    }

    SettlementRouter[] public settlementRouters;
    LiquidRouter[] public liquidRouters;
    address public agent;
    mapping(uint256 => StalledHop) public hopID;
    mapping(address => uint256[]) public hopsByAddress;
    uint256[] public totalHops;
    uint256 public nextHopId;
    address[] public mux;

    event SettlementRouterAdded(address indexed router, uint8 routerType);
    event LiquidRouterAdded(address indexed router, uint8 routerType);
    event RouterRemoved(address indexed router);
    event AgentSet(address indexed agent);
    event MuxAdded(address indexed muxAddress);
    event MuxRemoved(address indexed muxAddress);
    event HopDataUpdated(uint256 indexed hopId, address indexed caller);
    event HopFieldUpdated(uint256 indexed hopId, string field, uint256 value);
    event HopCanceled(uint256 indexed hopId);
    event AllHopsCanceled(address indexed maker, uint256 count);

    modifier onlyMux() {
        // Restricts access to mux addresses
        bool isMux = false;
        for (uint256 i = 0; i < mux.length; i++) {
            if (mux[i] == msg.sender) {
                isMux = true;
                break;
            }
        }
        require(isMux, "Caller not in mux");
        _;
    }

    function addMux(address muxAddress) external onlyOwner {
        // Adds a mux address
        require(muxAddress != address(0), "Invalid mux address");
        for (uint256 i = 0; i < mux.length; i++) {
            require(mux[i] != muxAddress, "Mux address already added");
        }
        mux.push(muxAddress);
        emit MuxAdded(muxAddress);
    }

    function removeMux(address muxAddress) external onlyOwner {
        // Removes a mux address
        require(muxAddress != address(0), "Invalid mux address");
        for (uint256 i = 0; i < mux.length; i++) {
            if (mux[i] == muxAddress) {
                mux[i] = mux[mux.length - 1];
                mux.pop();
                emit MuxRemoved(muxAddress);
                return;
            }
        }
        revert("Mux address not found");
    }

    function setAgent(address newAgent) external onlyOwner {
        // Sets the agent address
        require(newAgent != address(0), "Invalid agent address");
        agent = newAgent;
        emit AgentSet(newAgent);
    }

    function addSettlementRouter(address router, uint8 routerType) external onlyOwner {
        // Adds a settlement router
        require(router != address(0), "Invalid settlement router address");
        require(routerType == 1, "Invalid settlement router type");
        for (uint256 i = 0; i < settlementRouters.length; i++) {
            require(settlementRouters[i].router != router, "Settlement router already added");
        }
        for (uint256 i = 0; i < liquidRouters.length; i++) {
            require(liquidRouters[i].router != router, "Router address used for liquid router");
        }
        settlementRouters.push(SettlementRouter({ router: router, routerType: routerType }));
        emit SettlementRouterAdded(router, routerType);
    }

    function addLiquidRouter(address router, uint8 routerType) external onlyOwner {
        // Adds a liquid router
        require(router != address(0), "Invalid liquid router address");
        require(routerType == 2, "Invalid liquid router type");
        for (uint256 i = 0; i < liquidRouters.length; i++) {
            require(liquidRouters[i].router != router, "Liquid router already added");
        }
        for (uint256 i = 0; i < settlementRouters.length; i++) {
            require(settlementRouters[i].router != router, "Router address used for settlement router");
        }
        liquidRouters.push(LiquidRouter({ router: router, routerType: routerType }));
        emit LiquidRouterAdded(router, routerType);
    }

    function removeRouter(address router) external onlyOwner {
        // Removes a router
        require(router != address(0), "Invalid router address");
        for (uint256 i = 0; i < settlementRouters.length; i++) {
            if (settlementRouters[i].router == router) {
                settlementRouters[i] = settlementRouters[settlementRouters.length - 1];
                settlementRouters.pop();
                emit RouterRemoved(router);
                return;
            }
        }
        for (uint256 i = 0; i < liquidRouters.length; i++) {
            if (liquidRouters[i].router == router) {
                liquidRouters[i] = liquidRouters[liquidRouters.length - 1];
                liquidRouters.pop();
                emit RouterRemoved(router);
                return;
            }
        }
        revert("Router not found");
    }

    function MHUpdate(
        uint256 hopId,
        StalledHop memory hopData,
        uint256[] memory userHops,
        bool addToTotalHops
    ) external onlyMux {
        // Updates hop data and user hops
        require(hopId < nextHopId, "Invalid hop ID");
        hopID[hopId] = hopData;
        hopsByAddress[hopData.hopMaker] = userHops;
        if (addToTotalHops) {
            bool exists = false;
            for (uint256 i = 0; i < totalHops.length; i++) {
                if (totalHops[i] == hopId) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                totalHops.push(hopId);
            }
        }
        emit HopDataUpdated(hopId, msg.sender);
    }

    function updateHopField(uint256 hopId, string memory field, uint256 value) external onlyMux {
        // Updates a single field in StalledHop
        require(hopId < nextHopId, "Invalid hop ID");
        StalledHop memory hopData = hopID[hopId];
        if (keccak256(abi.encodePacked(field)) == keccak256(abi.encodePacked("stage"))) {
            hopData.stage = uint8(value);
        } else if (keccak256(abi.encodePacked(field)) == keccak256(abi.encodePacked("orderID"))) {
            hopData.orderID = value;
        } else if (keccak256(abi.encodePacked(field)) == keccak256(abi.encodePacked("minPrice"))) {
            hopData.minPrice = value;
        } else if (keccak256(abi.encodePacked(field)) == keccak256(abi.encodePacked("maxPrice"))) {
            hopData.maxPrice = value;
        } else if (keccak256(abi.encodePacked(field)) == keccak256(abi.encodePacked("principalAmount"))) {
            hopData.principalAmount = value;
        } else if (keccak256(abi.encodePacked(field)) == keccak256(abi.encodePacked("settleType"))) {
            hopData.settleType = uint8(value);
        } else if (keccak256(abi.encodePacked(field)) == keccak256(abi.encodePacked("hopStatus"))) {
            hopData.hopStatus = uint8(value);
        } else if (keccak256(abi.encodePacked(field)) == keccak256(abi.encodePacked("maxIterations"))) {
            hopData.maxIterations = value;
        } else if (keccak256(abi.encodePacked(field)) == keccak256(abi.encodePacked("currentListing"))) {
            hopData.currentListing = address(uint160(value));
        } else if (keccak256(abi.encodePacked(field)) == keccak256(abi.encodePacked("hopMaker"))) {
            hopData.hopMaker = address(uint160(value));
        } else if (keccak256(abi.encodePacked(field)) == keccak256(abi.encodePacked("startToken"))) {
            hopData.startToken = address(uint160(value));
        } else if (keccak256(abi.encodePacked(field)) == keccak256(abi.encodePacked("endToken"))) {
            hopData.endToken = address(uint160(value));
        } else {
            revert("Invalid field name");
        }
        hopID[hopId] = hopData;
        emit HopFieldUpdated(hopId, field, value);
    }

    function _prepClearHopOrder(address listing, uint256 orderId, bool isBuy, uint256 hopId)
        internal view returns (
            address maker,
            address recipient,
            uint8 status,
            uint256 pending,
            uint256 filled,
            uint256 amountSent,
            address tokenIn,
            address tokenOut
        )
    {
        // Prepares data for clearing a hop order
        require(listing != address(0), "Listing address cannot be zero");
        StalledHop memory hopData = hopID[hopId];
        require(hopData.hopMaker == msg.sender, "Only hop maker can cancel");
        ISSListing listingContract = ISSListing(listing);
        (maker, recipient, status) = isBuy ? listingContract.getBuyOrderCore(orderId) : listingContract.getSellOrderCore(orderId);
        require(maker == msg.sender, "Caller is not order maker");
        require(status == 1 || status == 2, "Order not cancellable");
        (pending, filled, amountSent) = isBuy ? listingContract.getBuyOrderAmounts(orderId) : listingContract.getSellOrderAmounts(orderId);
        tokenIn = isBuy ? listingContract.tokenB() : listingContract.tokenA();
        tokenOut = isBuy ? listingContract.tokenA() : listingContract.tokenB();
    }

    function _executeClearHopOrder(CancelPrepData memory prepData) internal {
        // Executes hop order cancellation
        require(prepData.listing != address(0), "Invalid listing in cancel data");
        ISSListing listingContract = ISSListing(prepData.listing);
        bool isNative = prepData.outputToken == address(0);
        uint256 balanceBefore = isNative ? address(this).balance : IERC20(prepData.outputToken).balanceOf(address(this));
        HopUpdateType[] memory hopUpdates = new HopUpdateType[](1);
        hopUpdates[0] = HopUpdateType({ field: "status", value: uint256(1) });
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](hopUpdates.length);
        for (uint256 i = 0; i < hopUpdates.length; i++) {
            updates[i] = ISSListing.UpdateType({ field: hopUpdates[i].field, value: hopUpdates[i].value });
        }
        try listingContract.update(updates) {
            uint256 balanceAfter = isNative ? address(this).balance : IERC20(prepData.outputToken).balanceOf(address(this));
            CancelBalanceData memory balanceData = CancelBalanceData({
                token: prepData.outputToken,
                balanceBefore: balanceBefore,
                balanceAfter: balanceAfter
            });
            if (isNative) {
                _handleFilledOrSentNative(prepData.filled, prepData.receivedAmount, prepData.recipient);
                _handlePendingNative(prepData.pending, prepData.hopId, prepData);
                _handleBalanceNative(balanceData, prepData.hopId);
            } else {
                _handleFilledOrSentToken(prepData.filled, prepData.receivedAmount, prepData.outputToken, prepData.recipient);
                _handlePendingToken(prepData.pending, prepData.inputToken, prepData.hopId, prepData);
                _handleBalanceToken(balanceData, prepData.hopId);
            }
            StalledHop memory hopData = hopID[prepData.hopId];
            hopData.principalAmount = prepData.refundedPending;
            this.MHUpdate(prepData.hopId, hopData, hopsByAddress[hopData.hopMaker], false);
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Order cancellation failed: ", reason)));
        }
    }

    function _handleFilledOrSentNative(uint256 filled, uint256 receivedAmount, address recipient) internal {
        // Handles refund of filled or sent native amounts
        if (filled > 0 || receivedAmount > 0) {
            uint256 rawAmount = receivedAmount > 0 ? receivedAmount : filled;
            require(rawAmount > 0, "No refundable native amount");
            uint256 balanceBefore = address(recipient).balance;
            (bool success, ) = payable(recipient).call{value: rawAmount}("");
            require(success, "Native refund transfer failed");
            uint256 balanceAfter = address(recipient).balance;
            require(balanceAfter > balanceBefore, "Native refund did not increase balance");
        }
    }

    function _handleFilledOrSentToken(uint256 filled, uint256 receivedAmount, address outputToken, address recipient) internal {
        // Handles refund of filled or sent token amounts
        if (filled > 0 || receivedAmount > 0) {
            uint256 rawAmount = receivedAmount > 0 ? receivedAmount : filled;
            rawAmount = rawAmount * (10 ** IERC20(outputToken).decimals());
            require(rawAmount > 0, "No refundable token amount");
            uint256 balanceBefore = IERC20(outputToken).balanceOf(recipient);
            bool success = IERC20(outputToken).transfer(recipient, rawAmount);
            require(success, "Token refund transfer failed");
            uint256 balanceAfter = IERC20(outputToken).balanceOf(recipient);
            require(balanceAfter > balanceBefore, "Token refund did not increase balance");
        }
    }

    function _handlePendingNative(uint256 pending, uint256 hopId, CancelPrepData memory prepData) internal {
        // Handles refund of pending native amounts
        if (pending > 0) {
            require(pending > 0, "No pending native amount to refund");
            uint256 balanceBefore = address(hopID[hopId].hopMaker).balance;
            (bool success, ) = payable(hopID[hopId].hopMaker).call{value: pending}("");
            require(success, "Native pending refund failed");
            uint256 balanceAfter = address(hopID[hopId].hopMaker).balance;
            require(balanceAfter > balanceBefore, "Native pending refund did not increase balance");
            prepData.refundedPending = pending;
        }
    }

    function _handlePendingToken(uint256 pending, address inputToken, uint256 hopId, CancelPrepData memory prepData) internal {
        // Handles refund of pending token amounts
        if (pending > 0) {
            uint256 rawPending = pending * (10 ** IERC20(inputToken).decimals());
            require(rawPending > 0, "No pending token amount to refund");
            uint256 balanceBefore = IERC20(inputToken).balanceOf(hopID[hopId].hopMaker);
            bool success = IERC20(inputToken).transfer(hopID[hopId].hopMaker, rawPending);
            require(success, "Token pending refund failed");
            uint256 balanceAfter = IERC20(inputToken).balanceOf(hopID[hopId].hopMaker);
            require(balanceAfter > balanceBefore, "Token pending refund did not increase balance");
            prepData.refundedPending = pending;
        }
    }

    function _handleBalanceNative(CancelBalanceData memory balanceData, uint256 hopId) internal {
        // Handles refund of native balance
        if (balanceData.balanceAfter > balanceData.balanceBefore) {
            uint256 amount = balanceData.balanceAfter - balanceData.balanceBefore;
            require(amount > 0, "No native balance to refund");
            uint256 balanceBefore = address(hopID[hopId].hopMaker).balance;
            (bool success, ) = payable(hopID[hopId].hopMaker).call{value: amount}("");
            require(success, "Native balance refund failed");
            uint256 balanceAfter = address(hopID[hopId].hopMaker).balance;
            require(balanceAfter > balanceBefore, "Native balance refund did not increase balance");
        }
    }

    function _handleBalanceToken(CancelBalanceData memory balanceData, uint256 hopId) internal {
        // Handles refund of token balance
        if (balanceData.balanceAfter > balanceData.balanceBefore) {
            uint256 amount = balanceData.balanceAfter - balanceData.balanceBefore;
            require(amount > 0, "No token balance to refund");
            uint256 balanceBefore = IERC20(balanceData.token).balanceOf(hopID[hopId].hopMaker);
            bool success = IERC20(balanceData.token).transfer(hopID[hopId].hopMaker, amount);
            require(success, "Token balance refund failed");
            uint256 balanceAfter = IERC20(balanceData.token).balanceOf(hopID[hopId].hopMaker);
            require(balanceAfter > balanceBefore, "Token balance refund did not increase balance");
        }
    }

    function _prepCancelHopBuy(uint256 hopId) internal returns (CancelPrepData memory prepData) {
        // Prepares cancellation for a buy hop
        StalledHop memory stalledHop = hopID[hopId];
        require(stalledHop.hopMaker == msg.sender, "Caller is not hop maker");
        require(stalledHop.hopStatus == 1, "Hop is not stalled");
        require(stalledHop.currentListing != address(0), "Invalid current listing");
        ISSListing listing = ISSListing(stalledHop.currentListing);
        address outputToken = listing.tokenA();
        address inputToken = listing.tokenB();
        (address maker, address recipient, uint8 status, uint256 pending, uint256 filled, uint256 amountSent, , ) =
            _prepClearHopOrder(stalledHop.currentListing, stalledHop.orderID, true, hopId);
        prepData = CancelPrepData({
            hopId: hopId,
            listing: stalledHop.currentListing,
            isBuy: true,
            outputToken: outputToken,
            inputToken: inputToken,
            pending: pending,
            filled: filled,
            status: status,
            receivedAmount: amountSent,
            recipient: recipient,
            refundedPending: 0
        });
        _executeClearHopOrder(prepData);
    }

    function _prepCancelHopSell(uint256 hopId) internal returns (CancelPrepData memory prepData) {
        // Prepares cancellation for a sell hop
        StalledHop memory stalledHop = hopID[hopId];
        require(stalledHop.hopMaker == msg.sender, "Caller is not hop maker");
        require(stalledHop.hopStatus == 1, "Hop is not stalled");
        require(stalledHop.currentListing != address(0), "Invalid current listing");
        ISSListing listing = ISSListing(stalledHop.currentListing);
        address outputToken = listing.tokenB();
        address inputToken = listing.tokenA();
        (address maker, address recipient, uint8 status, uint256 pending, uint256 filled, uint256 amountSent, , ) =
            _prepClearHopOrder(stalledHop.currentListing, stalledHop.orderID, false, hopId);
        prepData = CancelPrepData({
            hopId: hopId,
            listing: stalledHop.currentListing,
            isBuy: false,
            outputToken: outputToken,
            inputToken: inputToken,
            pending: pending,
            filled: filled,
            status: status,
            receivedAmount: amountSent,
            recipient: recipient,
            refundedPending: 0
        });
        _executeClearHopOrder(prepData);
    }

    function _finalizeCancel(uint256 hopId) internal {
        // Finalizes hop cancellation
        StalledHop memory stalledHop = hopID[hopId];
        require(stalledHop.hopStatus == 1, "Hop already finalized or invalid");
        this.updateHopField(hopId, "hopStatus", 2);
        uint256[] memory userHops = hopsByAddress[stalledHop.hopMaker];
        uint256[] memory newUserHops = new uint256[](userHops.length);
        uint256 newIndex = 0;
        for (uint256 i = 0; i < userHops.length; i++) {
            if (userHops[i] != hopId) {
                newUserHops[newIndex] = userHops[i];
                newIndex++;
            }
        }
        uint256[] memory resizedUserHops = new uint256[](newIndex);
        for (uint256 i = 0; i < newIndex; i++) {
            resizedUserHops[i] = newUserHops[i];
        }
        hopsByAddress[stalledHop.hopMaker] = resizedUserHops;
        emit HopCanceled(hopId);
    }

    function cancelHop(uint256 hopId) external nonReentrant {
        // Cancels a specific hop
        require(hopId < nextHopId, "Invalid hop ID");
        StalledHop memory stalledHop = hopID[hopId];
        require(stalledHop.hopStatus == 1, "Hop is not stalled");
        bool isBuy = stalledHop.maxPrice > 0;
        if (isBuy) {
            _prepCancelHopBuy(hopId);
        } else {
            _prepCancelHopSell(hopId);
        }
        _finalizeCancel(hopId);
    }

    function cancelAll(uint256 maxIterations) external nonReentrant {
        // Cancels all user hops up to maxIterations
        require(maxIterations > 0, "Max iterations must be positive");
        uint256[] memory userHops = hopsByAddress[msg.sender];
        uint256 canceled = 0;
        for (uint256 i = userHops.length; i > 0 && canceled < maxIterations; i--) {
            uint256 hopId = userHops[i - 1];
            StalledHop memory stalledHop = hopID[hopId];
            if (stalledHop.hopStatus == 1) {
                this.cancelHop(hopId);
                canceled++;
            }
        }
        emit AllHopsCanceled(msg.sender, canceled);
    }
}