// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.2.23
// Changes:
// - v0.2.23: Modified update function to reduce pending amount by filled amount during settlement for buy and sell orders when amountSent > 0 or amounts.pending > 0. Ensured no underflow in pending reduction.
// - v0.2.22: Modified update function to determine order state using amountSent and pending amounts. Distinguishes order router updates from settlement router updates. Moved analytics to CCDexlytan, added required views.  Removed getFullBuy/SellOrderDetails. 

interface IERC20 {
    function decimals() external view returns (uint8);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface ICCLiquidityTemplate {
    function liquidityDetail() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, uint256 xFeesAcc, uint256 yFeesAcc);
}

interface ITokenRegistry {
    function initializeTokens(address user, address[] memory tokens) external;
}

interface ICCGlobalizer {
    function globalizeOrders(address maker, address token) external;
}

contract CCListingTemplate {
    mapping(address router => bool isRouter) private _routers;
    bool private _routersSet;
    address public tokenA; // Returns address token
    address public tokenB; // Returns address token
    uint8 public decimalsA; // Returns uint8 decimals
    uint8 public decimalsB; // Returns uint8 decimals
    address public uniswapV2PairView; // Returns address pair
    bool private uniswapV2PairViewSet;
    uint256 public listingId; // Returns uint256 listingId
    address public agentView; // Returns address agent
    address public registryAddress; // Returns address registry
    address public liquidityAddressView; // Returns address liquidityAddress
    address public globalizerAddress;
    bool private _globalizerSet;
    uint256 private nextOrderId; // Returns uint256 nextOrderId

    struct PayoutUpdate {
        uint8 payoutType; // 0: Long, 1: Short
        address recipient;
        uint256 required;
        uint256 filled; // Amount filled during settlement
        uint256 amountSent; // Amount of opposite token sent
    }
    struct DayStartFee {
        uint256 dayStartXFeesAcc; // Tracks xFeesAcc at midnight
        uint256 dayStartYFeesAcc; // Tracks yFeesAcc at midnight
        uint256 timestamp; // Midnight timestamp
    }
    DayStartFee public dayStartFee; // Returns DayStartFee memory fee

    struct Balance {
        uint256 xBalance;
        uint256 yBalance;
    }
    Balance private _balance;
    uint256[] private _pendingBuyOrders; // Returns uint256[] memory orderIds
    uint256[] private _pendingSellOrders; // Returns uint256[] memory orderIds
    mapping(address maker => uint256[] orderIds) public makerPendingOrders; // Returns uint256[] memory orderIds
    uint256[] private longPayoutByIndex; // Returns uint256[] memory orderIds
    uint256[] private shortPayoutByIndex; // Returns uint256[] memory orderIds
    mapping(address user => uint256[] orderIds) private userPayoutIDs; // Returns uint256[] memory orderIds

    struct HistoricalData {
        uint256 price;
        uint256 xBalance;
        uint256 yBalance;
        uint256 xVolume;
        uint256 yVolume;
        uint256 timestamp;
    }
    HistoricalData[] private _historicalData;

    // Maps midnight timestamps to historical data indices
    mapping(uint256 timestamp => uint256 index) private _dayStartIndices;

    struct BuyOrderCore {
        address makerAddress;
        address recipientAddress;
        uint8 status; // 0: cancelled, 1: pending, 2: partially filled, 3: filled
    }
    struct BuyOrderPricing {
        uint256 maxPrice;
        uint256 minPrice;
    }
    struct BuyOrderAmounts {
        uint256 pending;    // Amount of tokenB pending
        uint256 filled;     // Amount of tokenB filled
        uint256 amountSent; // Amount of tokenA sent during settlement
    }
    struct SellOrderCore {
        address makerAddress;
        address recipientAddress;
        uint8 status;
    }
    struct SellOrderPricing {
        uint256 maxPrice;
        uint256 minPrice;
    }
    struct SellOrderAmounts {
        uint256 pending;    // Amount of tokenA pending
        uint256 filled;     // Amount of tokenA filled
        uint256 amountSent; // Amount of tokenB sent during settlement
    }
    struct LongPayoutStruct {
        address makerAddress;
        address recipientAddress;
        uint256 required;
        uint256 filled;
        uint256 amountSent;
        uint256 orderId;
        uint8 status;
    }
    struct ShortPayoutStruct {
        address makerAddress;
        address recipientAddress;
        uint256 amount;
        uint256 filled;
        uint256 amountSent;
        uint256 orderId;
        uint8 status;
    }
    struct UpdateType {
        uint8 updateType; // 0: balance, 1: buy order, 2: sell order, 3: historical
        uint8 structId;   // 0: Core, 1: Pricing, 2: Amounts
        uint256 index;    // orderId or slot index
        uint256 value;    // principal or amount (normalized) or price
        address addr;     // makerAddress
        address recipient; // recipientAddress
        uint256 maxPrice; // for Pricing struct
        uint256 minPrice; // for Pricing struct
        uint256 amountSent; // Amount of opposite token sent during settlement
    }
    struct OrderStatus {
        bool hasCore;    // Tracks if Core struct is set
        bool hasPricing; // Tracks if Pricing struct is set
        bool hasAmounts; // Tracks if Amounts struct is set
    }

    mapping(uint256 orderId => BuyOrderCore) public buyOrderCore; // Returns (address makerAddress, address recipientAddress, uint8 status)
    mapping(uint256 orderId => BuyOrderPricing) public buyOrderPricing; // Returns (uint256 maxPrice, uint256 minPrice)
    mapping(uint256 orderId => BuyOrderAmounts) public buyOrderAmounts; // Returns (uint256 pending, uint256 filled, uint256 amountSent)
    mapping(uint256 orderId => SellOrderCore) public sellOrderCore; // Returns (address makerAddress, address recipientAddress, uint8 status)
    mapping(uint256 orderId => SellOrderPricing) public sellOrderPricing; // Returns (uint256 maxPrice, uint256 minPrice)
    mapping(uint256 orderId => SellOrderAmounts) public sellOrderAmounts; // Returns (uint256 pending, uint256 filled, uint256 amountSent)
    mapping(uint256 orderId => LongPayoutStruct) public longPayout; // Returns LongPayoutStruct memory payout
    mapping(uint256 orderId => ShortPayoutStruct) public shortPayout; // Returns ShortPayoutStruct memory payout
    mapping(uint256 orderId => OrderStatus) private orderStatus; // Tracks completeness of order structs

    event OrderUpdated(uint256 indexed listingId, uint256 orderId, bool isBuy, uint8 status);
    event PayoutOrderCreated(uint256 indexed orderId, bool isLong, uint8 status);
    event PayoutOrderUpdated(uint256 indexed orderId, bool isLong, uint256 filled, uint256 amountSent, uint8 status);
    event BalancesUpdated(uint256 indexed listingId, uint256 xBalance, uint256 yBalance);
    event GlobalizerAddressSet(address indexed globalizer);
    event globalUpdateFailed(uint256 indexed listingId, string reason);
    event RegistryUpdateFailed(address indexed user, address[] indexed tokens, string reason);
    event ExternalCallFailed(address indexed target, string functionName, string reason);
    event TransactionFailed(address indexed recipient, string reason);
    event UpdateFailed(uint256 indexed listingId, string reason);
    event OrderUpdateIncomplete(uint256 indexed listingId, uint256 orderId, string reason);
    event OrderUpdatesComplete(uint256 indexed listingId, uint256 orderId, bool isBuy);

    // Normalizes amount to 1e18 precision
    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256 normalized) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (uint256(18) - uint256(decimals));
        else return amount / 10 ** (uint256(decimals) - uint256(18));
    }

    // Denormalizes amount from 1e18 to token decimals
    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256 denormalized) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10 ** (uint256(18) - uint256(decimals));
        else return amount * 10 ** (uint256(decimals) - uint256(18));
    }

    // Checks if two timestamps are on the same day
    function _isSameDay(uint256 time1, uint256 time2) internal pure returns (bool sameDay) {
        return (time1 / 86400) == (time2 / 86400);
    }

    // Rounds timestamp to midnight
    function _floorToMidnight(uint256 timestamp) internal pure returns (uint256 midnight) {
        return (timestamp / 86400) * 86400;
    }

    // Calculates volume change since startTime using historical data
    function _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) internal view returns (uint256 volumeChange) {
        uint256 iterationsLeft = maxIterations;
        if (_historicalData.length == 0) return 0;
        for (uint256 i = _historicalData.length; i > 0 && iterationsLeft > 0; i--) {
            HistoricalData memory data = _historicalData[i - 1];
            iterationsLeft--;
            if (data.timestamp >= startTime) {
                return isA ? data.xVolume : data.yVolume;
            }
        }
        if (iterationsLeft == 0 || _historicalData.length <= maxIterations) {
            HistoricalData memory earliest = _historicalData[0];
            return isA ? earliest.xVolume : earliest.yVolume;
        }
        return 0;
    }

    // Updates token registry with balances for both tokens for a single user
    function _updateRegistry(address maker) internal {
        if (registryAddress == address(0) || maker == address(0)) {
            address[] memory emptyTokens = new address[](0);
            emit RegistryUpdateFailed(maker, emptyTokens, "Invalid registry or maker address");
            return;
        }
        uint256 tokenCount = (tokenA != address(0) ? 1 : 0) + (tokenB != address(0) ? 1 : 0);
        address[] memory tokens = new address[](tokenCount);
        uint256 index = 0;
        if (tokenA != address(0)) tokens[index++] = tokenA;
        if (tokenB != address(0)) tokens[index] = tokenB;
        try ITokenRegistry(registryAddress).initializeTokens(maker, tokens) {
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit RegistryUpdateFailed(maker, tokens, decodedReason);
            emit ExternalCallFailed(registryAddress, "initializeTokens", decodedReason);
        }
    }

    // Removes order ID from array
    function removePendingOrder(uint256[] storage orders, uint256 orderId) internal {
        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i] == orderId) {
                orders[i] = orders[orders.length - 1];
                orders.pop();
                break;
            }
        }
    }

    // Calls globalizeOrders with latest order details
    function globalizeUpdate() internal {
        if (globalizerAddress == address(0)) {
            emit globalUpdateFailed(listingId, "Invalid globalizer address");
            return;
        }
        uint256 orderId = nextOrderId > 0 ? nextOrderId - 1 : 0; // Use latest order ID or 0 if none
        address maker;
        address token;
        // Check if it's a buy order
        BuyOrderCore memory buyCore = buyOrderCore[orderId];
        if (buyCore.makerAddress != address(0)) {
            maker = buyCore.makerAddress;
            token = tokenB != address(0) ? tokenB : tokenA; // Use tokenB for buy
        } else {
            // Check if it's a sell order
            SellOrderCore memory sellCore = sellOrderCore[orderId];
            if (sellCore.makerAddress != address(0)) {
                maker = sellCore.makerAddress;
                token = tokenA != address(0) ? tokenA : tokenB; // Use tokenA for sell
            } else {
                // No valid order, skip for balance updates
                return;
            }
        }
        try ICCGlobalizer(globalizerAddress).globalizeOrders(maker, token) {
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit ExternalCallFailed(globalizerAddress, "globalizeOrders", decodedReason);
            emit globalUpdateFailed(listingId, decodedReason);
        }
    }

    // Returns pending buy order IDs
    function pendingBuyOrdersView() external view returns (uint256[] memory) {
        return _pendingBuyOrders;
    }

    // Returns pending sell order IDs
    function pendingSellOrdersView() external view returns (uint256[] memory) {
        return _pendingSellOrders;
    }

    // Transfers ERC20 tokens to recipient
    function transactToken(address token, uint256 amount, address recipient) external {
        require(_routers[msg.sender], "Caller not router");
        require(token == tokenA || token == tokenB, "Invalid token");
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        uint256 preBalance = IERC20(token).balanceOf(recipient);
        try IERC20(token).transfer(recipient, amount) returns (bool success) {
            if (!success) {
                emit TransactionFailed(recipient, "Transfer returned false");
                return;
            }
        } catch (bytes memory reason) {
            emit TransactionFailed(recipient, string(reason));
            return;
        }
        uint256 postBalance = IERC20(token).balanceOf(recipient);
        if (postBalance <= preBalance) {
            emit TransactionFailed(recipient, "No tokens received");
        }
    }

    // Transfers native ETH to recipient
    function transactNative(uint256 amount, address recipient) external payable {
        require(_routers[msg.sender], "Caller not router");
        require(tokenA == address(0) || tokenB == address(0), "Native not supported");
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        require(msg.value == amount, "Incorrect ETH amount");
        uint256 preBalance = recipient.balance;
        (bool success, bytes memory reason) = recipient.call{value: amount}("");
        if (!success) {
            emit TransactionFailed(recipient, string(reason));
            return;
        }
        uint256 postBalance = recipient.balance;
        if (postBalance <= preBalance) {
            emit TransactionFailed(recipient, "No ETH received");
        }
    }

    function ssUpdate(PayoutUpdate[] calldata updates) external {
        require(_routers[msg.sender], "Caller not router");
        for (uint256 i = 0; i < updates.length; i++) {
            PayoutUpdate memory u = updates[i];
            if (u.recipient == address(0)) {
                emit UpdateFailed(listingId, "Invalid recipient");
                continue;
            }
            if (u.payoutType > 1) {
                emit UpdateFailed(listingId, "Invalid payout type");
                continue;
            }
            if (u.required == 0 && u.filled == 0) {
                emit UpdateFailed(listingId, "Invalid required or filled amount");
                continue;
            }
            bool isLong = u.payoutType == 0;
            uint256 orderId = nextOrderId;
            if (isLong) {
                LongPayoutStruct storage payout = longPayout[orderId];
                if (payout.orderId == 0) { // New payout
                    payout.makerAddress = u.recipient;
                    payout.recipientAddress = u.recipient;
                    payout.required = u.required;
                    payout.filled = 0; // Initialize filled to 0
                    payout.orderId = orderId;
                    payout.status = u.required > 0 ? 1 : 0; // Pending or cancelled
                    longPayoutByIndex.push(orderId);
                    userPayoutIDs[u.recipient].push(orderId);
                    emit PayoutOrderCreated(orderId, true, payout.status);
                } else { // Update existing payout
                    if (u.filled > 0) payout.filled = u.filled;
                    if (u.amountSent > 0) payout.amountSent = u.amountSent;
                    if (u.required > 0) payout.required = u.required;
                    payout.status = u.filled >= payout.required ? 3 : (u.filled > 0 ? 2 : 1); // Filled, partially filled, or pending
                    emit PayoutOrderUpdated(orderId, true, payout.filled, payout.amountSent, payout.status);
                }
            } else {
                ShortPayoutStruct storage payout = shortPayout[orderId];
                if (payout.orderId == 0) { // New payout
                    payout.makerAddress = u.recipient;
                    payout.recipientAddress = u.recipient;
                    payout.amount = u.required;
                    payout.filled = 0; // Initialize filled to 0
                    payout.orderId = orderId;
                    payout.status = u.required > 0 ? 1 : 0; // Pending or cancelled
                    shortPayoutByIndex.push(orderId);
                    userPayoutIDs[u.recipient].push(orderId);
                    emit PayoutOrderCreated(orderId, false, payout.status);
                } else { // Update existing payout
                    if (u.filled > 0) payout.filled = u.filled;
                    if (u.amountSent > 0) payout.amountSent = u.amountSent;
                    if (u.required > 0) payout.amount = u.required;
                    payout.status = u.filled >= payout.amount ? 3 : (u.filled > 0 ? 2 : 1); // Filled, partially filled, or pending
                    emit PayoutOrderUpdated(orderId, false, payout.filled, payout.amountSent, payout.status);
                }
            }
            if (longPayout[orderId].orderId == 0 && shortPayout[orderId].orderId == 0) {
                nextOrderId++; // Increment only for new payouts
            }
        }
    }

    // Processes balance updates
    function _processBalanceUpdate(UpdateType memory u) internal returns (bool balanceUpdated) {
        if (u.structId == 0) {
            _balance.xBalance = u.value;
        } else if (u.structId == 1) {
            _balance.yBalance = u.value;
        } else {
            emit UpdateFailed(listingId, "Invalid balance structId");
            return false;
        }
        emit BalancesUpdated(listingId, _balance.xBalance, _balance.yBalance);
        return true;
    }

    // Processes buy order updates
    function _processBuyOrderUpdate(UpdateType memory u, uint256[] memory updatedOrders, uint256 updatedCount) internal returns (uint256) {
        // Handles buy order updates for core, pricing, or amounts
        uint256 orderId = u.index;
        if (u.structId == 0) {
            buyOrderCore[orderId] = BuyOrderCore({
                makerAddress: u.addr,
                recipientAddress: u.recipient,
                status: uint8(u.value)
            });
            orderStatus[orderId].hasCore = true;
            if (u.value == 1) {
                _pendingBuyOrders.push(orderId);
                makerPendingOrders[u.addr].push(orderId);
            } else if (u.value == 0 || u.value == 3) {
                buyOrderAmounts[orderId].pending = 0; // Zero pending for cancelled or filled orders
                removePendingOrder(_pendingBuyOrders, orderId);
                removePendingOrder(makerPendingOrders[u.addr], orderId);
            }
            emit OrderUpdated(listingId, orderId, true, uint8(u.value));
        } else if (u.structId == 1) {
            buyOrderPricing[orderId] = BuyOrderPricing({
                maxPrice: u.maxPrice,
                minPrice: u.minPrice
            });
            orderStatus[orderId].hasPricing = true;
        } else if (u.structId == 2) {
            BuyOrderAmounts storage amounts = buyOrderAmounts[orderId];
            amounts.filled += u.value;  // Add to existing filled amount
            amounts.amountSent = u.amountSent;
            uint256 originalTotal = amounts.pending + amounts.filled;
            amounts.pending = originalTotal > amounts.filled ? originalTotal - amounts.filled : 0;
            if (amounts.filled > 0) {
                _historicalData[_historicalData.length - 1].yVolume += u.value;
            }
            orderStatus[orderId].hasAmounts = true;
        } else {
            emit UpdateFailed(listingId, "Invalid buy order structId");
            return updatedCount;
        }
        if (updatedCount < updatedOrders.length && updatedOrders[updatedCount] != orderId) {
            updatedOrders[updatedCount] = orderId;
            updatedCount++;
        }
        return updatedCount;
    }

    // Processes sell order updates
    function _processSellOrderUpdate(UpdateType memory u, uint256[] memory updatedOrders, uint256 updatedCount) internal returns (uint256) {
        // Handles sell order updates for core, pricing, or amounts
        uint256 orderId = u.index;
        if (u.structId == 0) {
            sellOrderCore[orderId] = SellOrderCore({
                makerAddress: u.addr,
                recipientAddress: u.recipient,
                status: uint8(u.value)
            });
            orderStatus[orderId].hasCore = true;
            if (u.value == 1) {
                _pendingSellOrders.push(orderId);
                makerPendingOrders[u.addr].push(orderId);
            } else if (u.value == 0 || u.value == 3) {
                sellOrderAmounts[orderId].pending = 0; // Zero pending for cancelled or filled orders
                removePendingOrder(_pendingSellOrders, orderId);
                removePendingOrder(makerPendingOrders[u.addr], orderId);
            }
            emit OrderUpdated(listingId, orderId, false, uint8(u.value));
        } else if (u.structId == 1) {
            sellOrderPricing[orderId] = SellOrderPricing({
                maxPrice: u.maxPrice,
                minPrice: u.minPrice
            });
            orderStatus[orderId].hasPricing = true;
        } else if (u.structId == 2) {
            SellOrderAmounts storage amounts = sellOrderAmounts[orderId];
            amounts.filled += u.value;  // Add to existing filled amount
            amounts.amountSent = u.amountSent;
            uint256 originalTotal = amounts.pending + amounts.filled;
            amounts.pending = originalTotal > amounts.filled ? originalTotal - amounts.filled : 0;
            if (amounts.filled > 0) {
                _historicalData[_historicalData.length - 1].xVolume += u.value;
            }
            orderStatus[orderId].hasAmounts = true;
        } else {
            emit UpdateFailed(listingId, "Invalid sell order structId");
            return updatedCount;
        }
        if (updatedCount < updatedOrders.length && updatedOrders[updatedCount] != orderId) {
            updatedOrders[updatedCount] = orderId;
            updatedCount++;
        }
        return updatedCount;
    }

    // Processes historical data updates
    function _processHistoricalUpdate(UpdateType memory u) internal returns (bool historicalUpdated) {
        _historicalData.push(HistoricalData({
            price: u.value,
            xBalance: _balance.xBalance,
            yBalance: _balance.yBalance,
            xVolume: u.maxPrice,
            yVolume: u.minPrice,
            timestamp: block.timestamp
        }));
        uint256 midnight = _floorToMidnight(block.timestamp);
        if (_dayStartIndices[midnight] == 0) {
            _dayStartIndices[midnight] = _historicalData.length - 1;
        }
        return true;
    }

    // Modified update function to reduce pending amount during settlement
    function update(UpdateType[] calldata updates) external {
        // Updates balances, orders, and historical data, only callable by routers
        require(_routers[msg.sender], "Caller not router");
        uint256 currentMidnight = (block.timestamp / 86400) * 86400;
        bool balanceUpdated = false;
        uint256[] memory updatedOrders = new uint256[](updates.length);
        uint256 updatedCount = 0;

        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0) { // Balance
                _balance.xBalance = u.index; // xBalance
                _balance.yBalance = u.value; // yBalance
                balanceUpdated = true;
                emit BalancesUpdated(listingId, u.index, u.value);
            } else if (u.updateType == 1) { // Buy order
                if (updatedOrders.length <= updatedCount) {
                    emit UpdateFailed(listingId, "Order array overflow");
                    continue;
                }
                updatedOrders[updatedCount] = u.index;
                OrderStatus storage status = orderStatus[u.index];
                if (u.structId == 0) { // Core
                    buyOrderCore[u.index] = BuyOrderCore({
                        makerAddress: u.addr,
                        recipientAddress: u.recipient,
                        status: uint8(u.value)
                    });
                    if (u.value == 1) {
                        _pendingBuyOrders.push(u.index);
                        makerPendingOrders[u.addr].push(u.index);
                    } else if (u.value == 0) {
                        removePendingOrder(_pendingBuyOrders, u.index);
                        removePendingOrder(makerPendingOrders[u.addr], u.index);
                    }
                    status.hasCore = true;
                    emit OrderUpdated(listingId, u.index, true, uint8(u.value));
                } else if (u.structId == 1) { // Pricing
                    buyOrderPricing[u.index] = BuyOrderPricing({
                        maxPrice: u.maxPrice,
                        minPrice: u.minPrice
                    });
                    status.hasPricing = true;
                } else if (u.structId == 2) { // Amounts
                    BuyOrderAmounts storage amounts = buyOrderAmounts[u.index];
                    if (u.amountSent > 0 || amounts.pending > 0) { // Settlement
                        amounts.filled = u.value;
                        if (amounts.pending >= u.value) { // Prevent underflow
                            amounts.pending -= u.value; // Reduce pending by filled amount
                        } else {
                            amounts.pending = 0; // Set to 0 if filled exceeds pending
                        }
                    } else { // New order
                        amounts.pending = u.value;
                    }
                    if (u.amountSent > 0) amounts.amountSent = u.amountSent;
                    status.hasAmounts = true;
                } else {
                    emit UpdateFailed(listingId, "Invalid buy order struct ID");
                    continue;
                }
                updatedCount++;
            } else if (u.updateType == 2) { // Sell order
                if (updatedOrders.length <= updatedCount) {
                    emit UpdateFailed(listingId, "Order array overflow");
                    continue;
                }
                updatedOrders[updatedCount] = u.index;
                OrderStatus storage status = orderStatus[u.index];
                if (u.structId == 0) { // Core
                    sellOrderCore[u.index] = SellOrderCore({
                        makerAddress: u.addr,
                        recipientAddress: u.recipient,
                        status: uint8(u.value)
                    });
                    if (u.value == 1) {
                        _pendingSellOrders.push(u.index);
                        makerPendingOrders[u.addr].push(u.index);
                    } else if (u.value == 0) {
                        removePendingOrder(_pendingSellOrders, u.index);
                        removePendingOrder(makerPendingOrders[u.addr], u.index);
                    }
                    status.hasCore = true;
                    emit OrderUpdated(listingId, u.index, false, uint8(u.value));
                } else if (u.structId == 1) { // Pricing
                    sellOrderPricing[u.index] = SellOrderPricing({
                        maxPrice: u.maxPrice,
                        minPrice: u.minPrice
                    });
                    status.hasPricing = true;
                } else if (u.structId == 2) { // Amounts
                    SellOrderAmounts storage amounts = sellOrderAmounts[u.index];
                    if (u.amountSent > 0 || amounts.pending > 0) { // Settlement
                        amounts.filled = u.value;
                        if (amounts.pending >= u.value) { // Prevent underflow
                            amounts.pending -= u.value; // Reduce pending by filled amount
                        } else {
                            amounts.pending = 0; // Set to 0 if filled exceeds pending
                        }
                    } else { // New order
                        amounts.pending = u.value;
                    }
                    if (u.amountSent > 0) amounts.amountSent = u.amountSent;
                    status.hasAmounts = true;
                } else {
                    emit UpdateFailed(listingId, "Invalid sell order struct ID");
                    continue;
                }
                updatedCount++;
            } else if (u.updateType == 3) { // Historical
                if (_historicalData.length <= u.index) {
                    _historicalData.push(HistoricalData({
                        price: u.value,
                        xBalance: _balance.xBalance,
                        yBalance: _balance.yBalance,
                        xVolume: 0,
                        yVolume: 0,
                        timestamp: u.value > 0 ? block.timestamp : _floorToMidnight(block.timestamp)
                    }));
                } else {
                    _historicalData[u.index].price = u.value;
                    _historicalData[u.index].xBalance = _balance.xBalance;
                    _historicalData[u.index].yBalance = _balance.yBalance;
                    _historicalData[u.index].timestamp = u.value > 0 ? block.timestamp : _floorToMidnight(block.timestamp);
                }
                if (_isSameDay(_historicalData[u.index].timestamp, currentMidnight)) {
                    _dayStartIndices[currentMidnight] = u.index;
                }
                balanceUpdated = true;
            } else {
                emit UpdateFailed(listingId, "Invalid update type");
                continue;
            }
        }
        if (_historicalData.length > 0 && !_isSameDay(dayStartFee.timestamp, currentMidnight)) {
            dayStartFee = DayStartFee({
                dayStartXFeesAcc: 0,
                dayStartYFeesAcc: 0,
                timestamp: currentMidnight
            });
            try ICCLiquidityTemplate(liquidityAddressView).liquidityDetail() returns (
                uint256 /* xLiq */,
                uint256 /* yLiq */,
                uint256,
                uint256,
                uint256 xFees,
                uint256 yFees
            ) {
                dayStartFee.dayStartXFeesAcc = xFees;
                dayStartFee.dayStartYFeesAcc = yFees;
            } catch {
                emit UpdateFailed(listingId, "Failed to fetch liquidity details");
            }
        }
        for (uint256 i = 0; i < updatedCount; i++) {
            uint256 orderId = updatedOrders[i];
            OrderStatus storage status = orderStatus[orderId];
            bool isBuy = buyOrderCore[orderId].makerAddress != address(0);
            if (status.hasCore && status.hasPricing && status.hasAmounts) {
                emit OrderUpdatesComplete(listingId, orderId, isBuy);
            } else {
                string memory reason;
                if (!status.hasCore) reason = "Missing Core struct";
                else if (!status.hasPricing) reason = "Missing Pricing struct";
                else reason = "Missing Amounts struct";
                emit OrderUpdateIncomplete(listingId, orderId, reason);
            }
        }
        if (balanceUpdated) {
            try IUniswapV2Pair(uniswapV2PairView).token0() returns (address) {
                uint256 balanceA = normalize(IERC20(tokenA).balanceOf(uniswapV2PairView), decimalsA);
                uint256 balanceB = normalize(IERC20(tokenB).balanceOf(uniswapV2PairView), decimalsB);
                // Price updated via prices function
            } catch {
                emit UpdateFailed(listingId, "Failed to update price");
            }
        }
        globalizeUpdate();
    }

    // Sets globalizer contract address, callable once
    function setGlobalizerAddress(address globalizerAddress_) external {
        require(!_globalizerSet, "Globalizer already set");
        require(globalizerAddress_ != address(0), "Invalid globalizer address");
        globalizerAddress = globalizerAddress_;
        _globalizerSet = true;
        emit GlobalizerAddressSet(globalizerAddress_);
    }

    // Sets Uniswap V2 pair address, callable once
    function setUniswapV2Pair(address uniswapV2Pair_) external {
        require(!uniswapV2PairViewSet, "Uniswap V2 pair already set");
        require(uniswapV2Pair_ != address(0), "Invalid pair address");
        uniswapV2PairView = uniswapV2Pair_;
        uniswapV2PairViewSet = true;
    }

    // Sets router addresses, callable once
    function setRouters(address[] memory routers_) external {
        require(!_routersSet, "Routers already set");
        require(routers_.length > 0, "No routers provided");
        for (uint256 i = 0; i < routers_.length; i++) {
            require(routers_[i] != address(0), "Invalid router address");
            _routers[routers_[i]] = true;
        }
        _routersSet = true;
    }

    // Sets listing ID, callable once
    function setListingId(uint256 _listingId) external {
        require(listingId == 0, "Listing ID already set");
        listingId = _listingId;
    }

    // Sets liquidity address, callable once
    function setLiquidityAddress(address _liquidityAddress) external {
        require(liquidityAddressView == address(0), "Liquidity already set");
        require(_liquidityAddress != address(0), "Invalid liquidity address");
        liquidityAddressView = _liquidityAddress;
    }

    // Sets token addresses, initializes historical data and dayStartFee
    function setTokens(address _tokenA, address _tokenB) external {
        require(tokenA == address(0) && tokenB == address(0), "Tokens already set");
        require(_tokenA != _tokenB, "Tokens must be different");
        require(_tokenA != address(0) || _tokenB != address(0), "Both tokens cannot be zero");
        tokenA = _tokenA;
        tokenB = _tokenB;
        decimalsA = _tokenA == address(0) ? 18 : IERC20(_tokenA).decimals();
        decimalsB = _tokenB == address(0) ? 18 : IERC20(_tokenB).decimals();
        uint256 midnight = _floorToMidnight(block.timestamp);
        _historicalData.push(HistoricalData({
            price: 0,
            xBalance: 0,
            yBalance: 0,
            xVolume: 0,
            yVolume: 0,
            timestamp: midnight
        }));
        _dayStartIndices[midnight] = 0;
        dayStartFee = DayStartFee({
            dayStartXFeesAcc: 0,
            dayStartYFeesAcc: 0,
            timestamp: midnight
        });
    }

    // Sets agent address, callable once
    function setAgent(address _agent) external {
        require(agentView == address(0), "Agent already set");
        require(_agent != address(0), "Invalid agent address");
        agentView = _agent;
    }

    // Sets registry address, callable once
    function setRegistry(address registryAddress_) external {
        require(registryAddress == address(0), "Registry already set");
        require(registryAddress_ != address(0), "Invalid registry address");
        registryAddress = registryAddress_;
    }

    // Returns token pair
    function getTokens() external view returns (address tokenA_, address tokenB_) {
        require(tokenA != address(0) || tokenB != address(0), "Tokens not set");
        return (tokenA, tokenB);
    }

    // Returns next order ID
    function getNextOrderId() external view returns (uint256 orderId_) {
        return nextOrderId;
    }

    // Returns long payout details
    function getLongPayout(uint256 orderId) external view returns (LongPayoutStruct memory payout) {
        return longPayout[orderId];
    }

    // Returns short payout details
    function getShortPayout(uint256 orderId) external view returns (ShortPayoutStruct memory payout) {
        return shortPayout[orderId];
    }

    // Computes current price from Uniswap V2 pair token balances
    function prices(uint256 _listingId) external view returns (uint256 price) {
    uint256 balanceA;
    uint256 balanceB;
    try IERC20(tokenA).balanceOf(uniswapV2PairView) returns (uint256 balA) {
        balanceA = tokenA == address(0) ? 0 : normalize(balA, decimalsA);
    } catch {
        return 1; // Return lowest possible price
    }
    try IERC20(tokenB).balanceOf(uniswapV2PairView) returns (uint256 balB) {
        balanceB = tokenB == address(0) ? 0 : normalize(balB, decimalsB);
    } catch {
        return 1; // Return lowest possible price
    }
    return balanceA == 0 ? 0 : (balanceB * 1e18) / balanceA;
}

// Rounds a timestamp to the start of its day (midnight UTC)
function floorToMidnightView(uint256 inputTimestamp) external pure returns (uint256 midnight) {
    midnight = (inputTimestamp / 86400) * 86400;
}

// Checks if two timestamps are in the same calendar day (UTC)
function isSameDayView(uint256 firstTimestamp, uint256 secondTimestamp) external pure returns (bool sameDay) {
    sameDay = (firstTimestamp / 86400) == (secondTimestamp / 86400);
}

// Returns the historical data index for a given midnight timestamp
function getDayStartIndex(uint256 midnightTimestamp) external view returns (uint256 index) {
    index = _dayStartIndices[midnightTimestamp];
}

    // Returns real-time token balances
    function volumeBalances(uint256 _listingId) external view returns (uint256 xBalance, uint256 yBalance) {
        xBalance = tokenA == address(0) ? address(this).balance : normalize(IERC20(tokenA).balanceOf(address(this)), decimalsA);
        yBalance = tokenB == address(0) ? address(this).balance : normalize(IERC20(tokenB).balanceOf(address(this)), decimalsB);
    }

    // Returns up to maxIterations pending buy order IDs for a maker, starting from step
    function makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations) external view returns (uint256[] memory orderIds) {
        uint256[] memory allOrders = makerPendingOrders[maker];
        uint256 count = 0;
        for (uint256 i = step; i < allOrders.length && count < maxIterations; i++) {
            if (buyOrderCore[allOrders[i]].makerAddress == maker && buyOrderCore[allOrders[i]].status == 1) {
                count++;
            }
        }
        orderIds = new uint256[](count);
        count = 0;
        for (uint256 i = step; i < allOrders.length && count < maxIterations; i++) {
            if (buyOrderCore[allOrders[i]].makerAddress == maker && buyOrderCore[allOrders[i]].status == 1) {
                orderIds[count++] = allOrders[i];
            }
        }
    }

    // Returns up to maxIterations pending sell order IDs for a maker, starting from step
    function makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations) external view returns (uint256[] memory orderIds) {
        uint256[] memory allOrders = makerPendingOrders[maker];
        uint256 count = 0;
        for (uint256 i = step; i < allOrders.length && count < maxIterations; i++) {
            if (sellOrderCore[allOrders[i]].makerAddress == maker && sellOrderCore[allOrders[i]].status == 1) {
                count++;
            }
        }
        orderIds = new uint256[](count);
        count = 0;
        for (uint256 i = step; i < allOrders.length && count < maxIterations; i++) {
            if (sellOrderCore[allOrders[i]].makerAddress == maker && sellOrderCore[allOrders[i]].status == 1) {
                orderIds[count++] = allOrders[i];
            }
        }
    }

    // Returns buy order core details
    function getBuyOrderCore(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status) {
        BuyOrderCore memory core = buyOrderCore[orderId];
        return (core.makerAddress, core.recipientAddress, core.status);
    }

    // Returns buy order pricing details
    function getBuyOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice) {
        BuyOrderPricing memory pricing = buyOrderPricing[orderId];
        return (pricing.maxPrice, pricing.minPrice);
    }

    // Returns buy order amounts
    function getBuyOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent) {
        BuyOrderAmounts memory amounts = buyOrderAmounts[orderId];
        return (amounts.pending, amounts.filled, amounts.amountSent);
    }

    // Returns sell order core details
    function getSellOrderCore(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status) {
        SellOrderCore memory core = sellOrderCore[orderId];
        return (core.makerAddress, core.recipientAddress, core.status);
    }

    // Returns sell order pricing details
    function getSellOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice) {
        SellOrderPricing memory pricing = sellOrderPricing[orderId];
        return (pricing.maxPrice, pricing.minPrice);
    }

    // Returns sell order amounts
    function getSellOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent) {
        SellOrderAmounts memory amounts = sellOrderAmounts[orderId];
        return (amounts.pending, amounts.filled, amounts.amountSent);
    }
    
    // Returns up to maxIterations order IDs for a maker, starting from step
    function makerOrdersView(address maker, uint256 step, uint256 maxIterations) external view returns (uint256[] memory orderIds) {
        uint256[] memory allOrders = makerPendingOrders[maker];
        uint256 length = allOrders.length;
        if (step >= length) return new uint256[](0);
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        orderIds = new uint256[](limit);
        for (uint256 i = 0; i < limit; i++) {
            orderIds[i] = allOrders[step + i];
        }
    }

    // Returns pending orders for a maker
    function makerPendingOrdersView(address maker) external view returns (uint256[] memory orderIds) {
        return makerPendingOrders[maker];
    }

    // Returns long payout IDs
    function longPayoutByIndexView() external view returns (uint256[] memory orderIds) {
        return longPayoutByIndex;
    }

    // Returns short payout IDs
    function shortPayoutByIndexView() external view returns (uint256[] memory orderIds) {
        return shortPayoutByIndex;
    }

    // Returns payout IDs for a user
    function userPayoutIDsView(address user) external view returns (uint256[] memory orderIds) {
        return userPayoutIDs[user];
    }

    // Returns historical data at index
    function getHistoricalDataView(uint256 index) external view returns (HistoricalData memory data) {
        require(index < _historicalData.length, "Invalid index");
        return _historicalData[index];
    }

    // Returns historical data length
    function historicalDataLengthView() external view returns (uint256 length) {
        return _historicalData.length;
    }

    // Utility function to convert uint to string for error messages
    function uint2str(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        str = string(bstr);
    }
}