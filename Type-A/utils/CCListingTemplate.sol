// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.11
// Changes:
// - v0.0.11: Modified _updateRegistry and globalizeUpdate to check gas explicitly, revert with error messages on failure, and remove try-catch.
// - v0.0.10: Removed caller parameter from update, ssUpdate, transactToken, transactNative; used msg.sender for router validation.
// - v0.0.9: Removed ReentrancyGuard inheritance and nonReentrant modifiers from update, ssUpdate, transactToken, transactNative.
// - v0.0.8: Added explicit gas limit (500000) to ITokenRegistry.initializeBalances call in _updateRegistry.
// - v0.0.7: Added explicit gas limit (1000000) to ICCAgent.globalizeOrders calls in globalizeUpdate.
// - v0.0.6: Updated ICCListing interface and liquidityAddressView function for CCAgent.sol v0.0.5 compatibility.
// - v0.0.5: Added agentView function for ICCListing compliance.
// - v0.0.4: Removed SafeERC20, used direct IERC20.transfer, added getTokens function.
// - v0.0.3: Split transact into transactToken and transactNative.
// - v0.0.2: Added uniswapV2PairView function.
// - v0.0.1: Changed to BSL 1.1, added Uniswap V2 pair support.

interface IERC20 {
    function decimals() external view returns (uint8);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface ICCListing {
    function prices(uint256) external view returns (uint256);
    function volumeBalances(uint256) external view returns (uint256 xBalance, uint256 yBalance);
    function liquidityAddressView() external view returns (address);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    struct PayoutUpdate {
        uint8 payoutType; // 0: Long, 1: Short
        address recipient;
        uint256 required;
    }
    function ssUpdate(PayoutUpdate[] calldata updates) external;
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface ICCAgent {
    function globalizeOrders(
        uint256 listingId,
        address tokenA,
        address tokenB,
        uint256 orderId,
        bool isBuy,
        address maker,
        address recipient,
        uint256 amount,
        uint8 status
    ) external;
}

interface ICCListingTemplate {
    function getTokens() external view returns (address tokenA, address tokenB);
}

interface ICCLiquidityTemplate {
    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount);
    function setRouters(address[] memory _routers) external;
    function setListingId(uint256 _listingId) external;
    function setListingAddress(address _listingAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setAgent(address _agent) external;
}

interface ITokenRegistry {
    function initializeBalances(address token, address[] memory users) external;
}

contract CCListingTemplate {
    mapping(address => bool) private _routers;
    bool private _routersSet;
    address private _tokenA;
    address private _tokenB;
    uint8 private _decimalsA;
    uint8 private _decimalsB;
    address private _uniswapV2Pair;
    bool private _uniswapV2PairSet;
    uint256 private _listingId;
    address private _agent;
    address private _registryAddress;
    address private _liquidityAddress;
    uint256 private _nextOrderId;
    struct LastDayFee {
        uint256 xFees;
        uint256 yFees;
        uint256 timestamp;
    }
    LastDayFee private _lastDayFee;
    struct VolumeBalance {
        uint256 xBalance;
        uint256 yBalance;
        uint256 xVolume;
        uint256 yVolume;
    }
    VolumeBalance private _volumeBalance;
    uint256 private _currentPrice;
    uint256[] private _pendingBuyOrders;
    uint256[] private _pendingSellOrders;
    uint256[] private _longPayoutsByIndex;
    uint256[] private _shortPayoutsByIndex;
    mapping(address => uint256[]) private _makerPendingOrders;
    mapping(address => uint256[]) private _userPayoutIDs;
    struct HistoricalData {
        uint256 price;
        uint256 xBalance;
        uint256 yBalance;
        uint256 xVolume;
        uint256 yVolume;
        uint256 timestamp;
    }
    HistoricalData[] private _historicalData;

    struct BuyOrderCore {
        address makerAddress;
        address recipientAddress;
        uint8 status; // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
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
    struct PayoutUpdate {
        uint8 payoutType; // 0: Long, 1: Short
        address recipient;
        uint256 required;
    }
    struct LongPayoutStruct {
        address makerAddress;
        address recipientAddress;
        uint256 required;
        uint256 filled;
        uint256 orderId;
        uint8 status;
    }
    struct ShortPayoutStruct {
        address makerAddress;
        address recipientAddress;
        uint256 amount;
        uint256 filled;
        uint256 orderId;
        uint8 status;
    }
    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
        uint8 structId;   // 0 = Core, 1 = Pricing, 2 = Amounts
        uint256 index;    // orderId or slot index (0 = xBalance, 1 = yBalance, 2 = xVolume, 3 = yVolume for type 0)
        uint256 value;    // principal or amount (normalized) or price (for historical)
        address addr;     // makerAddress
        address recipient; // recipientAddress
        uint256 maxPrice; // for Pricing struct or packed xBalance/yBalance (historical)
        uint256 minPrice; // for Pricing struct or packed xVolume/yVolume (historical)
        uint256 amountSent; // Amount of opposite token sent during settlement
    }

    mapping(uint256 => BuyOrderCore) private _buyOrderCores;
    mapping(uint256 => BuyOrderPricing) private _buyOrderPricings;
    mapping(uint256 => BuyOrderAmounts) private _buyOrderAmounts;
    mapping(uint256 => SellOrderCore) private _sellOrderCores;
    mapping(uint256 => SellOrderPricing) private _sellOrderPricings;
    mapping(uint256 => SellOrderAmounts) private _sellOrderAmounts;
    mapping(uint256 => LongPayoutStruct) private _longPayouts;
    mapping(uint256 => ShortPayoutStruct) private _shortPayouts;

    event OrderUpdated(uint256 indexed listingId, uint256 orderId, bool isBuy, uint8 status);
    event PayoutOrderCreated(uint256 indexed orderId, bool isLong, uint8 status);
    event BalancesUpdated(uint256 indexed listingId, uint256 xBalance, uint256 yBalance);

    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (uint256(18) - uint256(decimals));
        else return amount / 10 ** (uint256(decimals) - uint256(18));
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10 ** (uint256(18) - uint256(decimals));
        else return amount * 10 ** (uint256(decimals) - uint256(18));
    }

    function _isSameDay(uint256 time1, uint256 time2) internal pure returns (bool) {
        uint256 midnight1 = time1 - (time1 % 86400);
        uint256 midnight2 = time2 - (time2 % 86400);
        return midnight1 == midnight2;
    }

    function _floorToMidnight(uint256 timestamp) internal pure returns (uint256) {
        return timestamp - (timestamp % 86400);
    }

    function _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) internal view returns (uint256) {
        uint256 currentVolume = isA ? _volumeBalance.xVolume : _volumeBalance.yVolume;
        uint256 iterationsLeft = maxIterations;
        if (_historicalData.length == 0) return 0;
        for (uint256 i = _historicalData.length; i > 0 && iterationsLeft > 0; i--) {
            HistoricalData memory data = _historicalData[i - 1];
            iterationsLeft--;
            if (data.timestamp >= startTime) {
                return currentVolume - (isA ? data.xVolume : data.yVolume);
            }
        }
        if (iterationsLeft == 0 || _historicalData.length <= maxIterations) {
            HistoricalData memory earliest = _historicalData[0];
            return currentVolume - (isA ? earliest.xVolume : earliest.yVolume);
        }
        return 0;
    }

    function setUniswapV2Pair(address uniswapV2Pair_) external {
        require(!_uniswapV2PairSet, "Uniswap V2 pair already set");
        require(uniswapV2Pair_ != address(0), "Invalid pair address");
        _uniswapV2Pair = uniswapV2Pair_;
        _uniswapV2PairSet = true;
    }

    function queryYield(bool isA, uint256 maxIterations) external view returns (uint256) {
        require(maxIterations > 0, "Invalid maxIterations");
        if (_lastDayFee.timestamp == 0 || _historicalData.length == 0 || !_isSameDay(block.timestamp, _lastDayFee.timestamp)) {
            return 0;
        }
        uint256 feeDifference = isA ? _volumeBalance.xVolume - _lastDayFee.xFees : _volumeBalance.yVolume - _lastDayFee.yFees;
        if (feeDifference == 0) return 0;
        uint256 liquidity = 0;
        try ICCLiquidityTemplate(_liquidityAddress).liquidityAmounts() returns (uint256 xLiquid, uint256 yLiquid) {
            liquidity = isA ? xLiquid : yLiquid;
        } catch {
            return 0;
        }
        if (liquidity == 0) return 0;
        uint256 dailyFees = (feeDifference * 5) / 10000; // 0.05% fee
        uint256 dailyYield = (dailyFees * 1e18) / liquidity;
        return dailyYield * 365;
    }

    function _updateRegistry() internal {
        if (_registryAddress == address(0)) return;
        bool isBuy = block.timestamp % 2 == 0;
        uint256[] memory orders = isBuy ? _pendingBuyOrders : _pendingSellOrders;
        address tokenAddress = isBuy ? _tokenB : _tokenA;
        if (orders.length == 0) return;
        address[] memory tempMakers = new address[](orders.length);
        uint256 makerCount = 0;
        for (uint256 i = 0; i < orders.length; i++) {
            address makerAddress = isBuy ? _buyOrderCores[orders[i]].makerAddress : _sellOrderCores[orders[i]].makerAddress;
            if (makerAddress != address(0)) {
                bool exists = false;
                for (uint256 j = 0; j < makerCount; j++) {
                    if (tempMakers[j] == makerAddress) {
                        exists = true;
                        break;
                    }
                }
                if (!exists) {
                    tempMakers[makerCount++] = makerAddress;
                }
            }
        }
        address[] memory makers = new address[](makerCount);
        for (uint256 i = 0; i < makerCount; i++) {
            makers[i] = tempMakers[i];
        }
        uint256 gasBefore = gasleft();
        ITokenRegistry(_registryAddress).initializeBalances{gas: 500000}(tokenAddress, makers);
        uint256 gasUsed = gasBefore - gasleft();
        if (gasUsed > 500000) {
            revert("Registry call out of gas");
        }
    }

    function setRouters(address[] memory routers_) external {
        require(!_routersSet, "Routers already set");
        require(routers_.length > 0, "No routers provided");
        for (uint256 i = 0; i < routers_.length; i++) {
            require(routers_[i] != address(0), "Invalid router address");
            _routers[routers_[i]] = true;
        }
        _routersSet = true;
    }

    function setListingId(uint256 listingId_) external {
        require(_listingId == 0, "Listing ID already set");
        _listingId = listingId_;
    }

    function setLiquidityAddress(address liquidityAddress_) external {
        require(_liquidityAddress == address(0), "Liquidity already set");
        require(liquidityAddress_ != address(0), "Invalid liquidity address");
        _liquidityAddress = liquidityAddress_;
    }

    function setTokens(address tokenA_, address tokenB_) external {
        require(_tokenA == address(0) && _tokenB == address(0), "Tokens already set");
        require(tokenA_ != tokenB_, "Tokens must be different");
        require(tokenA_ != address(0) || tokenB_ != address(0), "Both tokens cannot be zero");
        _tokenA = tokenA_;
        _tokenB = tokenB_;
        _decimalsA = tokenA_ == address(0) ? 18 : IERC20(tokenA_).decimals();
        _decimalsB = tokenB_ == address(0) ? 18 : IERC20(tokenB_).decimals();
    }

    function setAgent(address agent_) external {
        require(_agent == address(0), "Agent already set");
        require(agent_ != address(0), "Invalid agent address");
        _agent = agent_;
    }

    function setRegistry(address registryAddress_) external {
        require(_registryAddress == address(0), "Registry already set");
        require(registryAddress_ != address(0), "Invalid registry address");
        _registryAddress = registryAddress_;
    }

    function agentView() external view returns (address) {
        return _agent;
    }

    function globalizeUpdate() internal {
        if (_agent == address(0)) return;
        uint256 gasLimit = 1000000;
        for (uint256 i = 0; i < _pendingBuyOrders.length; i++) {
            uint256 orderId = _pendingBuyOrders[i];
            BuyOrderCore memory order = _buyOrderCores[orderId];
            BuyOrderAmounts memory amounts = _buyOrderAmounts[orderId];
            if (order.status == 1 || order.status == 2) {
                uint256 gasBefore = gasleft();
                ICCAgent(_agent).globalizeOrders{gas: gasLimit}(
                    _listingId,
                    _tokenA,
                    _tokenB,
                    orderId,
                    true,
                    order.makerAddress,
                    order.recipientAddress,
                    amounts.pending,
                    order.status
                );
                uint256 gasUsed = gasBefore - gasleft();
                if (gasUsed > gasLimit) {
                    revert("Globalize buy order call out of gas");
                }
            }
        }
        for (uint256 i = 0; i < _pendingSellOrders.length; i++) {
            uint256 orderId = _pendingSellOrders[i];
            SellOrderCore memory order = _sellOrderCores[orderId];
            SellOrderAmounts memory amounts = _sellOrderAmounts[orderId];
            if (order.status == 1 || order.status == 2) {
                uint256 gasBefore = gasleft();
                ICCAgent(_agent).globalizeOrders{gas: gasLimit}(
                    _listingId,
                    _tokenA,
                    _tokenB,
                    orderId,
                    false,
                    order.makerAddress,
                    order.recipientAddress,
                    amounts.pending,
                    order.status
                );
                uint256 gasUsed = gasBefore - gasleft();
                if (gasUsed > gasLimit) {
                    revert("Globalize sell order call out of gas");
                }
            }
        }
    }

    function removePendingOrder(uint256[] storage orders, uint256 orderId) internal {
        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i] == orderId) {
                orders[i] = orders[orders.length - 1];
                orders.pop();
                break;
            }
        }
    }

    function update(UpdateType[] memory updates) external {
        require(_routers[msg.sender], "Router only");
        VolumeBalance storage balances = _volumeBalance;
        bool volumeUpdated = false;
        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0 && (u.index == 2 || u.index == 3)) {
                volumeUpdated = true;
                break;
            } else if (u.updateType == 1 && u.structId == 2 && u.value > 0) {
                volumeUpdated = true;
                break;
            } else if (u.updateType == 2 && u.structId == 2 && u.value > 0) {
                volumeUpdated = true;
                break;
            }
        }
        if (volumeUpdated && (_lastDayFee.timestamp == 0 || block.timestamp >= _lastDayFee.timestamp + 86400)) {
            _lastDayFee.xFees = _volumeBalance.xVolume;
            _lastDayFee.yFees = _volumeBalance.yVolume;
            _lastDayFee.timestamp = _floorToMidnight(block.timestamp);
        }
        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0) {
                if (u.index == 0) balances.xBalance = u.value;
                else if (u.index == 1) balances.yBalance = u.value;
                else if (u.index == 2) balances.xVolume += u.value;
                else if (u.index == 3) balances.yVolume += u.value;
            } else if (u.updateType == 1) {
                if (u.structId == 0) {
                    BuyOrderCore storage core = _buyOrderCores[u.index];
                    if (core.makerAddress == address(0)) {
                        core.makerAddress = u.addr;
                        core.recipientAddress = u.recipient;
                        core.status = 1;
                        _pendingBuyOrders.push(u.index);
                        _makerPendingOrders[u.addr].push(u.index);
                        _nextOrderId = u.index + 1;
                        emit OrderUpdated(_listingId, u.index, true, 1);
                    } else if (u.value == 0) {
                        core.status = 0;
                        removePendingOrder(_pendingBuyOrders, u.index);
                        removePendingOrder(_makerPendingOrders[core.makerAddress], u.index);
                        emit OrderUpdated(_listingId, u.index, true, 0);
                    }
                } else if (u.structId == 1) {
                    BuyOrderPricing storage pricing = _buyOrderPricings[u.index];
                    pricing.maxPrice = u.maxPrice;
                    pricing.minPrice = u.minPrice;
                } else if (u.structId == 2) {
                    BuyOrderAmounts storage amounts = _buyOrderAmounts[u.index];
                    BuyOrderCore storage core = _buyOrderCores[u.index];
                    if (amounts.pending == 0 && core.makerAddress != address(0)) {
                        amounts.pending = u.value;
                        amounts.amountSent = u.amountSent;
                        balances.yBalance += u.value;
                        balances.yVolume += u.value;
                    } else if (core.status == 1) {
                        require(amounts.pending >= u.value, "Insufficient pending");
                        amounts.pending -= u.value;
                        amounts.filled += u.value;
                        amounts.amountSent += u.amountSent;
                        balances.xBalance -= u.value;
                        core.status = amounts.pending == 0 ? 3 : 2;
                        if (amounts.pending == 0) {
                            removePendingOrder(_pendingBuyOrders, u.index);
                            removePendingOrder(_makerPendingOrders[core.makerAddress], u.index);
                        }
                        emit OrderUpdated(_listingId, u.index, true, core.status);
                    }
                }
            } else if (u.updateType == 2) {
                if (u.structId == 0) {
                    SellOrderCore storage core = _sellOrderCores[u.index];
                    if (core.makerAddress == address(0)) {
                        core.makerAddress = u.addr;
                        core.recipientAddress = u.recipient;
                        core.status = 1;
                        _pendingSellOrders.push(u.index);
                        _makerPendingOrders[u.addr].push(u.index);
                        _nextOrderId = u.index + 1;
                        emit OrderUpdated(_listingId, u.index, false, 1);
                    } else if (u.value == 0) {
                        core.status = 0;
                        removePendingOrder(_pendingSellOrders, u.index);
                        removePendingOrder(_makerPendingOrders[core.makerAddress], u.index);
                        emit OrderUpdated(_listingId, u.index, false, 0);
                    }
                } else if (u.structId == 1) {
                    SellOrderPricing storage pricing = _sellOrderPricings[u.index];
                    pricing.maxPrice = u.maxPrice;
                    pricing.minPrice = u.minPrice;
                } else if (u.structId == 2) {
                    SellOrderAmounts storage amounts = _sellOrderAmounts[u.index];
                    SellOrderCore storage core = _sellOrderCores[u.index];
                    if (amounts.pending == 0 && core.makerAddress != address(0)) {
                        amounts.pending = u.value;
                        amounts.amountSent = u.amountSent;
                        balances.xBalance += u.value;
                        balances.xVolume += u.value;
                    } else if (core.status == 1) {
                        require(amounts.pending >= u.value, "Insufficient pending");
                        amounts.pending -= u.value;
                        amounts.filled += u.value;
                        amounts.amountSent += u.amountSent;
                        balances.yBalance -= u.value;
                        core.status = amounts.pending == 0 ? 3 : 2;
                        if (amounts.pending == 0) {
                            removePendingOrder(_pendingSellOrders, u.index);
                            removePendingOrder(_makerPendingOrders[core.makerAddress], u.index);
                        }
                        emit OrderUpdated(_listingId, u.index, false, core.status);
                    }
                }
            } else if (u.updateType == 3) {
                (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(_uniswapV2Pair).getReserves();
                uint256 reserveA = _tokenA == IUniswapV2Pair(_uniswapV2Pair).token0() ? reserve0 : reserve1;
                uint256 reserveB = _tokenB == IUniswapV2Pair(_uniswapV2Pair).token1() ? reserve1 : reserve0;
                uint256 normalizedReserveA = normalize(reserveA, _decimalsA);
                uint256 normalizedReserveB = normalize(reserveB, _decimalsB);
                _historicalData.push(HistoricalData(
                    normalizedReserveA > 0 && normalizedReserveB > 0 ? (normalizedReserveA * 1e18) / normalizedReserveB : 0,
                    u.maxPrice >> 128, u.maxPrice & ((1 << 128) - 1),
                    u.minPrice >> 128, u.minPrice & ((1 << 128) - 1),
                    block.timestamp
                ));
            }
        }
        if (_uniswapV2Pair != address(0)) {
            (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(_uniswapV2Pair).getReserves();
            uint256 reserveA = _tokenA == IUniswapV2Pair(_uniswapV2Pair).token0() ? reserve0 : reserve1;
            uint256 reserveB = _tokenB == IUniswapV2Pair(_uniswapV2Pair).token1() ? reserve1 : reserve0;
            uint256 normalizedReserveA = normalize(reserveA, _decimalsA);
            uint256 normalizedReserveB = normalize(reserveB, _decimalsB);
            _currentPrice = normalizedReserveA > 0 && normalizedReserveB > 0 ? (normalizedReserveA * 1e18) / normalizedReserveB : 0;
        }
        emit BalancesUpdated(_listingId, balances.xBalance, balances.yBalance);
        globalizeUpdate();
    }

    function ssUpdate(PayoutUpdate[] memory payoutUpdates) external {
        require(_routers[msg.sender], "Router only");
        for (uint256 i = 0; i < payoutUpdates.length; i++) {
            PayoutUpdate memory p = payoutUpdates[i];
            uint256 orderId = _nextOrderId;
            if (p.payoutType == 0) {
                LongPayoutStruct storage payout = _longPayouts[orderId];
                payout.makerAddress = msg.sender;
                payout.recipientAddress = p.recipient;
                payout.required = p.required;
                payout.filled = 0;
                payout.orderId = orderId;
                payout.status = 0;
                _longPayoutsByIndex.push(orderId);
                _userPayoutIDs[p.recipient].push(orderId);
                emit PayoutOrderCreated(orderId, true, 0);
            } else if (p.payoutType == 1) {
                ShortPayoutStruct storage payout = _shortPayouts[orderId];
                payout.makerAddress = msg.sender;
                payout.recipientAddress = p.recipient;
                payout.amount = p.required;
                payout.filled = 0;
                payout.orderId = orderId;
                payout.status = 0;
                _shortPayoutsByIndex.push(orderId);
                _userPayoutIDs[p.recipient].push(orderId);
                emit PayoutOrderCreated(orderId, false, 0);
            } else {
                revert("Invalid payout type");
            }
            _nextOrderId = orderId + 1;
        }
    }

    function transactToken(address token, uint256 amount, address recipient) external {
        require(_routers[msg.sender], "Router only");
        require(token != address(0), "Use transactNative for ETH");
        require(token == _tokenA || token == _tokenB, "Invalid token");
        VolumeBalance storage balances = _volumeBalance;
        uint8 decimals = IERC20(token).decimals();
        uint256 normalizedAmount = normalize(amount, decimals);
        require(balances.xBalance >= normalizedAmount || balances.yBalance >= normalizedAmount, "Insufficient balance");
        if (_lastDayFee.timestamp == 0 || block.timestamp >= _lastDayFee.timestamp + 86400) {
            _lastDayFee.xFees = _volumeBalance.xVolume;
            _lastDayFee.yFees = _volumeBalance.yVolume;
            _lastDayFee.timestamp = _floorToMidnight(block.timestamp);
        }
        if (token == _tokenA) {
            balances.xBalance -= normalizedAmount;
            balances.xVolume += normalizedAmount;
        } else {
            balances.yBalance -= normalizedAmount;
            balances.yVolume += normalizedAmount;
        }
        IERC20(token).transfer(recipient, amount);
        if (_uniswapV2Pair != address(0)) {
            (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(_uniswapV2Pair).getReserves();
            uint256 reserveA = _tokenA == IUniswapV2Pair(_uniswapV2Pair).token0() ? reserve0 : reserve1;
            uint256 reserveB = _tokenB == IUniswapV2Pair(_uniswapV2Pair).token1() ? reserve1 : reserve0;
            uint256 normalizedReserveA = normalize(reserveA, _decimalsA);
            uint256 normalizedReserveB = normalize(reserveB, _decimalsB);
            _currentPrice = normalizedReserveA > 0 && normalizedReserveB > 0 ? (normalizedReserveA * 1e18) / normalizedReserveB : 0;
        }
        emit BalancesUpdated(_listingId, balances.xBalance, balances.yBalance);
        _updateRegistry();
    }

    function transactNative(uint256 amount, address recipient) external {
        require(_routers[msg.sender], "Router only");
        require(_tokenA == address(0) || _tokenB == address(0), "No native token in pair");
        VolumeBalance storage balances = _volumeBalance;
        uint256 normalizedAmount = normalize(amount, 18);
        require(balances.xBalance >= normalizedAmount || balances.yBalance >= normalizedAmount, "Insufficient balance");
        if (_lastDayFee.timestamp == 0 || block.timestamp >= _lastDayFee.timestamp + 86400) {
            _lastDayFee.xFees = _volumeBalance.xVolume;
            _lastDayFee.yFees = _volumeBalance.yVolume;
            _lastDayFee.timestamp = _floorToMidnight(block.timestamp);
        }
        if (_tokenA == address(0)) {
            balances.xBalance -= normalizedAmount;
            balances.xVolume += normalizedAmount;
        } else {
            balances.yBalance -= normalizedAmount;
            balances.yVolume += normalizedAmount;
        }
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "ETH transfer failed");
        if (_uniswapV2Pair != address(0)) {
            (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(_uniswapV2Pair).getReserves();
            uint256 reserveA = _tokenA == IUniswapV2Pair(_uniswapV2Pair).token0() ? reserve0 : reserve1;
            uint256 reserveB = _tokenB == IUniswapV2Pair(_uniswapV2Pair).token1() ? reserve1 : reserve0;
            uint256 normalizedReserveA = normalize(reserveA, _decimalsA);
            uint256 normalizedReserveB = normalize(reserveB, _decimalsB);
            _currentPrice = normalizedReserveA > 0 && normalizedReserveB > 0 ? (normalizedReserveA * 1e18) / normalizedReserveB : 0;
        }
        emit BalancesUpdated(_listingId, balances.xBalance, balances.yBalance);
        _updateRegistry();
    }

    function uniswapV2PairView() external view returns (address) {
        return _uniswapV2Pair;
    }

    function prices(uint256) external view returns (uint256) {
        if (_uniswapV2Pair == address(0)) return 0;
        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(_uniswapV2Pair).getReserves();
        uint256 reserveA = _tokenA == IUniswapV2Pair(_uniswapV2Pair).token0() ? reserve0 : reserve1;
        uint256 reserveB = _tokenB == IUniswapV2Pair(_uniswapV2Pair).token1() ? reserve1 : reserve0;
        uint256 normalizedReserveA = normalize(reserveA, _decimalsA);
        uint256 normalizedReserveB = normalize(reserveB, _decimalsB);
        return normalizedReserveA > 0 && normalizedReserveB > 0 ? (normalizedReserveA * 1e18) / normalizedReserveB : 0;
    }

    function getTokens() external view returns (address tokenA, address tokenB) {
        address fetchedTokenA = _tokenA;
        address fetchedTokenB = _tokenB;
        require(fetchedTokenA != address(0) || fetchedTokenB != address(0), "No valid tokens set");
        return (fetchedTokenA, fetchedTokenB);
    }

    function volumeBalances(uint256) external view returns (uint256 xBalance, uint256 yBalance) {
        return (_volumeBalance.xBalance, _volumeBalance.yBalance);
    }

    function liquidityAddressView() external view returns (address) {
        return _liquidityAddress;
    }

    function tokenA() external view returns (address) {
        return _tokenA;
    }

    function tokenB() external view returns (address) {
        return _tokenB;
    }

    function decimalsA() external view returns (uint8) {
        return _decimalsA;
    }

    function decimalsB() external view returns (uint8) {
        return _decimalsB;
    }

    function getListingId() external view returns (uint256) {
        return _listingId;
    }

    function getNextOrderId() external view returns (uint256) {
        return _nextOrderId;
    }

    function listingVolumeBalancesView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume) {
        return (_volumeBalance.xBalance, _volumeBalance.yBalance, _volumeBalance.xVolume, _volumeBalance.yVolume);
    }

    function listingPriceView() external view returns (uint256) {
        return _currentPrice;
    }

    function pendingBuyOrdersView() external view returns (uint256[] memory) {
        return _pendingBuyOrders;
    }

    function pendingSellOrdersView() external view returns (uint256[] memory) {
        return _pendingSellOrders;
    }

    function makerPendingOrdersView(address maker) external view returns (uint256[] memory) {
        return _makerPendingOrders[maker];
    }

    function longPayoutByIndexView() external view returns (uint256[] memory) {
        return _longPayoutsByIndex;
    }

    function shortPayoutByIndexView() external view returns (uint256[] memory) {
        return _shortPayoutsByIndex;
    }

    function userPayoutIDsView(address user) external view returns (uint256[] memory) {
        return _userPayoutIDs[user];
    }

    function getLongPayout(uint256 orderId) external view returns (LongPayoutStruct memory) {
        return _longPayouts[orderId];
    }

    function getShortPayout(uint256 orderId) external view returns (ShortPayoutStruct memory) {
        return _shortPayouts[orderId];
    }

    function getBuyOrderCore(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status) {
        BuyOrderCore memory core = _buyOrderCores[orderId];
        return (core.makerAddress, core.recipientAddress, core.status);
    }

    function getBuyOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice) {
        BuyOrderPricing memory pricing = _buyOrderPricings[orderId];
        return (pricing.maxPrice, pricing.minPrice);
    }

    function getBuyOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent) {
        BuyOrderAmounts memory amounts = _buyOrderAmounts[orderId];
        return (amounts.pending, amounts.filled, amounts.amountSent);
    }

    function getSellOrderCore(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status) {
        SellOrderCore memory core = _sellOrderCores[orderId];
        return (core.makerAddress, core.recipientAddress, core.status);
    }

    function getSellOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice) {
        SellOrderPricing memory pricing = _sellOrderPricings[orderId];
        return (pricing.maxPrice, pricing.minPrice);
    }

    function getSellOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent) {
        SellOrderAmounts memory amounts = _sellOrderAmounts[orderId];
        return (amounts.pending, amounts.filled, amounts.amountSent);
    }

    function getHistoricalDataView(uint256 index) external view returns (HistoricalData memory) {
        require(index < _historicalData.length, "Invalid index");
        return _historicalData[index];
    }

    function historicalDataLengthView() external view returns (uint256) {
        return _historicalData.length;
    }

    function getHistoricalDataByNearestTimestamp(uint256 targetTimestamp) external view returns (HistoricalData memory) {
        require(_historicalData.length > 0, "No historical data");
        uint256 minDiff = type(uint256).max;
        uint256 closestIndex = 0;
        for (uint256 i = 0; i < _historicalData.length; i++) {
            uint256 diff;
            if (targetTimestamp >= _historicalData[i].timestamp) {
                diff = targetTimestamp - _historicalData[i].timestamp;
            } else {
                diff = _historicalData[i].timestamp - targetTimestamp;
            }
            if (diff < minDiff) {
                minDiff = diff;
                closestIndex = i;
            }
        }
        return _historicalData[closestIndex];
    }
}