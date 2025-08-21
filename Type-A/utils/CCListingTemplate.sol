// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.12
// Changes:
// - v0.1.12: Reintroduced `removePendingOrder(uint256[] storage orders, uint256 orderId)` internal function to remove order IDs from `_pendingBuyOrders`, `_pendingSellOrders`, and `_makerPendingOrders` using swap-and-pop. Modified `update` to call `removePendingOrder` for buy/sell orders with status 0 (cancelled) or 3 (filled), improving gas efficiency by pruning arrays. Compatible with CCSettlementRouter.sol v0.0.10, CCUniPartial.sol v0.0.22, CCSettlementPartial.sol v0.0.25.
// - v0.1.11: Fixed DeclarationError by replacing `prices(0)` with `this.prices(0)` in `transactToken` (line 458) and `transactNative` (line 486) to correctly call the external `prices` function. Ensured no other changes to functionality.
// - v0.1.10: Added detailed error logging in update function to capture specific failure reasons (invalid update type, struct ID, or addresses). Enhanced try-catch blocks to return detailed reasons for external call failures. Ensured graceful degradation by skipping invalid updates instead of reverting unless catastrophic.
// - v0.1.9: Modified price calculation in prices, update, transactToken, and transactNative to use IERC20.balanceOf for _tokenA and _tokenB from _uniswapV2Pair instead of getReserves, addressing incorrect price scaling.
// - v0.1.8: Modified price calculation in prices, update, transactToken, and transactNative to use reserveB / reserveA * 1e18 instead of reserveA / reserveB * 1e18.
// - v0.1.7: Refactored globalizeUpdate to occur at end of update, fetching latest order ID and details (maker, token) for ICCGlobalizer.globalizeOrders call.
// - v0.1.6: Modified globalizeUpdate to always call ICCGlobalizer.globalizeOrders for the maker with appropriate token, removing all checks for order existence.
// - v0.1.5: Updated globalizeUpdate to call ICCGlobalizer.globalizeOrders with token (_tokenB for buy, _tokenA for sell) instead of listing address, aligning with new ICCGlobalizer interface (v0.2.1).
// - v0.1.4: Updated _updateRegistry to use ITokenRegistry.initializeTokens, passing both _tokenA and _tokenB (if non-zero) for a single maker, replacing initializeBalances calls.
// - v0.1.3: Updated _updateRegistry to initialize balances for both _tokenA and _tokenB (if non-zero), removing block.timestamp % 2 token selection.
// - v0.1.2: Modified LastDayFee struct to use lastDayXFeesAcc, lastDayYFeesAcc. Updated queryYield to accept depositAmount, isTokenA, fetching xFeesAcc, yFeesAcc from CCLiquidityTemplate.liquidityDetail. Updated update function to set lastDayXFeesAcc, lastDayYFeesAcc on day change.
// - v0.1.1: Removed _updateRegistry calls from transactToken, transactNative. Added UpdateRegistryFailed event.
// Compatible with CCLiquidityTemplate.sol (v0.1.1), CCMainPartial.sol (v0.0.12), CCLiquidityPartial.sol (v0.0.21), ICCLiquidity.sol (v0.0.5), ICCListing.sol (v0.0.7), CCOrderRouter.sol (v0.0.11), TokenRegistry.sol (2025-08-04).

interface IERC20 {
    function decimals() external view returns (uint8);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface ICCListing {
    struct PayoutUpdate {
        uint8 payoutType; // 0: Long, 1: Short
        address recipient;
        uint256 required;
    }
    function prices(uint256) external view returns (uint256 price);
    function volumeBalances(uint256) external view returns (uint256 xBalance, uint256 yBalance);
    function liquidityAddressView() external view returns (address);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
    function ssUpdate(PayoutUpdate[] calldata updates) external;
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface ICCListingTemplate {
    function getTokens() external view returns (address tokenA, address tokenB);
    function globalizerAddressView() external view returns (address);
    function makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations) external view returns (uint256[] memory orderIds);
    function makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations) external view returns (uint256[] memory orderIds);
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

contract CCListingTemplate is ICCListing, ICCListingTemplate {
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
    address private _globalizerAddress;
    bool private _globalizerSet;
    uint256 private _nextOrderId;

    struct LastDayFee {
        uint256 lastDayXFeesAcc; // Tracks xFeesAcc at midnight
        uint256 lastDayYFeesAcc; // Tracks yFeesAcc at midnight
        uint256 timestamp; // Midnight timestamp
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
    event GlobalizerAddressSet(address indexed globalizer);
    event UpdateRegistryFailed(address indexed user, address[] indexed tokens, string reason);
    event UpdateFailed(uint256 indexed orderId, string reason);

    // Removes orderId from the provided array using swap-and-pop
    function removePendingOrder(uint256[] storage orders, uint256 orderId) internal {
        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i] == orderId) {
                orders[i] = orders[orders.length - 1];
                orders.pop();
                return;
            }
        }
    }

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

    // Calculates volume change since startTime
    function _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) internal view returns (uint256 volumeChange) {
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

    // Updates token registry with balances for both tokens for a single user
    function _updateRegistry(address maker) internal {
        if (_registryAddress == address(0)) {
            emit UpdateRegistryFailed(maker, new address[](0), "Registry address not set");
            return;
        }
        address[] memory tokens = new address[](2);
        tokens[0] = _tokenA;
        tokens[1] = _tokenB;
        try ITokenRegistry(_registryAddress).initializeTokens(maker, tokens) {
            // Registry updated successfully
        } catch Error(string memory reason) {
            emit UpdateRegistryFailed(maker, tokens, reason);
        } catch {
            emit UpdateRegistryFailed(maker, tokens, "Unknown registry update error");
        }
    }

    // Updates globalizer with latest order details
    function _globalizeUpdate(address maker, bool isBuy) internal {
        if (!_globalizerSet || _globalizerAddress == address(0)) return;
        address token = isBuy ? _tokenB : _tokenA;
        try ICCGlobalizer(_globalizerAddress).globalizeOrders(maker, token) {
            // Globalizer updated successfully
        } catch Error(string memory reason) {
            emit UpdateRegistryFailed(maker, new address[](1), string(abi.encodePacked("Globalizer update failed: ", reason)));
        } catch {
            emit UpdateRegistryFailed(maker, new address[](1), "Unknown globalizer update error");
        }
    }

    // Processes updates to balances, orders, or historical data
    function update(UpdateType[] calldata updates) external {
        require(_routers[msg.sender], "Caller not authorized router");
        address latestMaker = address(0);
        bool isBuyOrder = false;
        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType > 3) {
                emit UpdateFailed(u.index, "Invalid update type");
                continue;
            }
            if (u.structId > 2) {
                emit UpdateFailed(u.index, "Invalid struct ID");
                continue;
            }
            if (u.addr == address(0)) {
                emit UpdateFailed(u.index, "Invalid maker address");
                continue;
            }
            if (u.recipient == address(0)) {
                emit UpdateFailed(u.index, "Invalid recipient address");
                continue;
            }
            if (u.updateType == 0) {
                // Balance update
                if (u.structId != 0) {
                    emit UpdateFailed(u.index, "Invalid struct ID for balance update");
                    continue;
                }
                _volumeBalance.xBalance = u.value;
                _volumeBalance.yBalance = u.value;
                emit BalancesUpdated(_listingId, u.value, u.value);
            } else if (u.updateType == 1) {
                // Buy order update
                isBuyOrder = true;
                if (u.structId == 0) {
                    _buyOrderCores[u.index].status = uint8(u.value);
                    _buyOrderCores[u.index].makerAddress = u.addr;
                    _buyOrderCores[u.index].recipientAddress = u.recipient;
                    if (uint8(u.value) == 0 || uint8(u.value) == 3) {
                        removePendingOrder(_pendingBuyOrders, u.index);
                        removePendingOrder(_makerPendingOrders[u.addr], u.index);
                    }
                } else if (u.structId == 1) {
                    _buyOrderPricings[u.index].maxPrice = u.maxPrice;
                    _buyOrderPricings[u.index].minPrice = u.minPrice;
                } else {
                    _buyOrderAmounts[u.index].filled += u.value;
                    _buyOrderAmounts[u.index].pending -= u.value < _buyOrderAmounts[u.index].pending ? u.value : _buyOrderAmounts[u.index].pending;
                    _buyOrderAmounts[u.index].amountSent = u.amountSent;
                }
                latestMaker = u.addr;
                emit OrderUpdated(_listingId, u.index, true, _buyOrderCores[u.index].status);
            } else if (u.updateType == 2) {
                // Sell order update
                isBuyOrder = false;
                if (u.structId == 0) {
                    _sellOrderCores[u.index].status = uint8(u.value);
                    _sellOrderCores[u.index].makerAddress = u.addr;
                    _sellOrderCores[u.index].recipientAddress = u.recipient;
                    if (uint8(u.value) == 0 || uint8(u.value) == 3) {
                        removePendingOrder(_pendingSellOrders, u.index);
                        removePendingOrder(_makerPendingOrders[u.addr], u.index);
                    }
                } else if (u.structId == 1) {
                    _sellOrderPricings[u.index].maxPrice = u.maxPrice;
                    _sellOrderPricings[u.index].minPrice = u.minPrice;
                } else {
                    _sellOrderAmounts[u.index].filled += u.value;
                    _sellOrderAmounts[u.index].pending -= u.value < _sellOrderAmounts[u.index].pending ? u.value : _sellOrderAmounts[u.index].pending;
                    _sellOrderAmounts[u.index].amountSent = u.amountSent;
                }
                latestMaker = u.addr;
                emit OrderUpdated(_listingId, u.index, false, _sellOrderCores[u.index].status);
            } else if (u.updateType == 3) {
                // Historical data update
                if (u.structId != 0) {
                    emit UpdateFailed(u.index, "Invalid struct ID for historical update");
                    continue;
                }
                _historicalData.push(HistoricalData({
                    price: u.value,
                    xBalance: _volumeBalance.xBalance,
                    yBalance: _volumeBalance.yBalance,
                    xVolume: _volumeBalance.xVolume,
                    yVolume: _volumeBalance.yVolume,
                    timestamp: block.timestamp
                }));
            }
        }
        if (latestMaker != address(0)) {
            _updateRegistry(latestMaker);
            _globalizeUpdate(latestMaker, isBuyOrder);
        }
    }

    // Processes payout updates
    function ssUpdate(PayoutUpdate[] calldata updates) external {
        require(_routers[msg.sender], "Caller not authorized router");
        for (uint256 i = 0; i < updates.length; i++) {
            PayoutUpdate memory u = updates[i];
            if (u.payoutType == 0) {
                // Long payout
                _longPayouts[_nextOrderId] = LongPayoutStruct({
                    makerAddress: u.recipient,
                    recipientAddress: u.recipient,
                    required: u.required,
                    filled: 0,
                    orderId: _nextOrderId,
                    status: 1
                });
                _longPayoutsByIndex.push(_nextOrderId);
                _userPayoutIDs[u.recipient].push(_nextOrderId);
                emit PayoutOrderCreated(_nextOrderId, true, 1);
            } else {
                // Short payout
                _shortPayouts[_nextOrderId] = ShortPayoutStruct({
                    makerAddress: u.recipient,
                    recipientAddress: u.recipient,
                    amount: u.required,
                    filled: 0,
                    orderId: _nextOrderId,
                    status: 1
                });
                _shortPayoutsByIndex.push(_nextOrderId);
                _userPayoutIDs[u.recipient].push(_nextOrderId);
                emit PayoutOrderCreated(_nextOrderId, false, 1);
            }
            _nextOrderId++;
        }
    }

    // Sets Uniswap V2 pair address
    function setUniswapV2Pair(address uniswapV2Pair) external {
        require(!_uniswapV2PairSet, "Uniswap V2 pair already set");
        _uniswapV2Pair = uniswapV2Pair;
        _uniswapV2PairSet = true;
    }

    // Sets authorized routers
    function setRouters(address[] memory routers) external {
        require(!_routersSet, "Routers already set");
        for (uint256 i = 0; i < routers.length; i++) {
            require(routers[i] != address(0), "Invalid router address");
            _routers[routers[i]] = true;
        }
        _routersSet = true;
    }

    // Sets listing ID
    function setListingId(uint256 listingId) external {
        require(_listingId == 0, "Listing ID already set");
        _listingId = listingId;
    }

    // Sets liquidity address
    function setLiquidityAddress(address liquidityAddress) external {
        require(_liquidityAddress == address(0), "Liquidity address already set");
        _liquidityAddress = liquidityAddress;
    }

    // Sets token pair
    function setTokens(address tokenA, address tokenB) external {
        require(_tokenA == address(0) && _tokenB == address(0), "Tokens already set");
        require(tokenA != tokenB, "Identical tokens");
        _tokenA = tokenA;
        _tokenB = tokenB;
        _decimalsA = tokenA == address(0) ? 18 : IERC20(tokenA).decimals();
        _decimalsB = tokenB == address(0) ? 18 : IERC20(tokenB).decimals();
    }

    // Sets agent address
    function setAgent(address agentAddress) external {
        require(_agent == address(0), "Agent already set");
        _agent = agentAddress;
    }

    // Sets registry address
    function setRegistry(address registryAddress) external {
        require(_registryAddress == address(0), "Registry already set");
        _registryAddress = registryAddress;
    }

    // Sets globalizer address
    function setGlobalizer(address globalizerAddress) external {
        require(!_globalizerSet, "Globalizer already set");
        _globalizerAddress = globalizerAddress;
        _globalizerSet = true;
        emit GlobalizerAddressSet(globalizerAddress);
    }

    // Transfers tokens
    function transactToken(address token, uint256 amount, address recipient) external {
        require(_routers[msg.sender], "Caller not authorized router");
        require(token == _tokenA || token == _tokenB, "Invalid token");
        uint256 preBalance = IERC20(token).balanceOf(recipient);
        try IERC20(token).transfer(recipient, amount) {
            uint256 postBalance = IERC20(token).balanceOf(recipient);
            require(postBalance > preBalance, "Token transfer failed");
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Token transfer failed: ", reason)));
        } catch {
            revert("Token transfer failed: Unknown error");
        }
        _volumeBalance.xVolume += token == _tokenA ? normalize(amount, _decimalsA) : 0;
        _volumeBalance.yVolume += token == _tokenB ? normalize(amount, _decimalsB) : 0;
        _currentPrice = this.prices(0);
        _historicalData.push(HistoricalData({
            price: _currentPrice,
            xBalance: _volumeBalance.xBalance,
            yBalance: _volumeBalance.yBalance,
            xVolume: _volumeBalance.xVolume,
            yVolume: _volumeBalance.yVolume,
            timestamp: block.timestamp
        }));
    }

    // Transfers native currency
    function transactNative(uint256 amount, address recipient) external payable {
        require(_routers[msg.sender], "Caller not authorized router");
        require(msg.value == amount, "Incorrect ETH amount");
        uint256 preBalance = recipient.balance;
        (bool success, bytes memory data) = recipient.call{value: amount}("");
        if (!success) {
            if (data.length > 0) {
                revert(string(abi.encodePacked("Native transfer failed: ", string(data))));
            } else {
                revert("Native transfer failed: Unknown error");
            }
        }
        uint256 postBalance = recipient.balance;
        require(postBalance > preBalance, "Native transfer failed");
        _volumeBalance.xVolume += _tokenA == address(0) ? normalize(amount, 18) : 0;
        _volumeBalance.yVolume += _tokenB == address(0) ? normalize(amount, 18) : 0;
        _currentPrice = this.prices(0);
        _historicalData.push(HistoricalData({
            price: _currentPrice,
            xBalance: _volumeBalance.xBalance,
            yBalance: _volumeBalance.yBalance,
            xVolume: _volumeBalance.xVolume,
            yVolume: _volumeBalance.yVolume,
            timestamp: block.timestamp
        }));
    }

    // Returns agent address
    function agentView() external view returns (address agentAddress) {
        return _agent;
    }

    // Returns Uniswap V2 pair address
    function uniswapV2PairView() external view returns (address pair) {
        return _uniswapV2Pair;
    }

    // Computes current price from Uniswap V2 pair token balances
    function prices(uint256) external view returns (uint256 price) {
        uint256 reserveA;
        uint256 reserveB;
        try IERC20(_tokenA).balanceOf(_uniswapV2Pair) returns (uint256 balanceA) {
            reserveA = _tokenA == address(0) ? 0 : normalize(balanceA, _decimalsA);
        } catch {
            return _currentPrice;
        }
        try IERC20(_tokenB).balanceOf(_uniswapV2Pair) returns (uint256 balanceB) {
            reserveB = _tokenB == address(0) ? 0 : normalize(balanceB, _decimalsB);
        } catch {
            return _currentPrice;
        }
        return reserveA == 0 ? 0 : (reserveB * 1e18) / reserveA;
    }

    // Returns token pair
    function getTokens() external view returns (address tokenA, address tokenB) {
        require(_tokenA != address(0) || _tokenB != address(0), "Tokens not set");
        return (_tokenA, _tokenB);
    }

    // Returns volume balances
    function volumeBalances(uint256) external view returns (uint256 xBalance, uint256 yBalance) {
        return (_volumeBalance.xBalance, _volumeBalance.yBalance);
    }

    // Returns liquidity address
    function liquidityAddressView() external view returns (address liquidityAddress) {
        return _liquidityAddress;
    }

    // Returns tokenA address
    function tokenA() external view returns (address token) {
        return _tokenA;
    }

    // Returns tokenB address
    function tokenB() external view returns (address token) {
        return _tokenB;
    }

    // Returns decimalsA
    function decimalsA() external view returns (uint8 decimals) {
        return _decimalsA;
    }

    // Returns decimalsB
    function decimalsB() external view returns (uint8 decimals) {
        return _decimalsB;
    }

    // Returns listing ID
    function getListingId() external view returns (uint256 listingId) {
        return _listingId;
    }

    // Returns next order ID
    function getNextOrderId() external view returns (uint256 nextOrderId) {
        return _nextOrderId;
    }

    // Returns volume balance details
    function listingVolumeBalancesView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume) {
        return (_volumeBalance.xBalance, _volumeBalance.yBalance, _volumeBalance.xVolume, _volumeBalance.yVolume);
    }

    // Returns current price
    function listingPriceView() external view returns (uint256 price) {
        return _currentPrice;
    }

    // Returns pending buy order IDs
    function pendingBuyOrdersView() external view returns (uint256[] memory orderIds) {
        return _pendingBuyOrders;
    }

    // Returns pending sell order IDs
    function pendingSellOrdersView() external view returns (uint256[] memory orderIds) {
        return _pendingSellOrders;
    }

    // Returns all order IDs for a maker
    function makerPendingOrdersView(address maker) external view returns (uint256[] memory orderIds) {
        return _makerPendingOrders[maker];
    }

    // Returns long payout IDs
    function longPayoutByIndexView() external view returns (uint256[] memory orderIds) {
        return _longPayoutsByIndex;
    }

    // Returns short payout IDs
    function shortPayoutByIndexView() external view returns (uint256[] memory orderIds) {
        return _shortPayoutsByIndex;
    }

    // Returns payout IDs for a user
    function userPayoutIDsView(address user) external view returns (uint256[] memory orderIds) {
        return _userPayoutIDs[user];
    }

    // Returns long payout details
    function getLongPayout(uint256 orderId) external view returns (LongPayoutStruct memory payout) {
        return _longPayouts[orderId];
    }

    // Returns short payout details
    function getShortPayout(uint256 orderId) external view returns (ShortPayoutStruct memory payout) {
        return _shortPayouts[orderId];
    }

    // Returns buy order core details
    function getBuyOrderCore(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status) {
        BuyOrderCore memory core = _buyOrderCores[orderId];
        return (core.makerAddress, core.recipientAddress, core.status);
    }

    // Returns buy order pricing details
    function getBuyOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice) {
        BuyOrderPricing memory pricing = _buyOrderPricings[orderId];
        return (pricing.maxPrice, pricing.minPrice);
    }

    // Returns buy order amounts
    function getBuyOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent) {
        BuyOrderAmounts memory amounts = _buyOrderAmounts[orderId];
        return (amounts.pending, amounts.filled, amounts.amountSent);
    }

    // Returns sell order core details
    function getSellOrderCore(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status) {
        SellOrderCore memory core = _sellOrderCores[orderId];
        return (core.makerAddress, core.recipientAddress, core.status);
    }

    // Returns sell order pricing details
    function getSellOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice) {
        SellOrderPricing memory pricing = _sellOrderPricings[orderId];
        return (pricing.maxPrice, pricing.minPrice);
    }

    // Returns sell order amounts
    function getSellOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent) {
        SellOrderAmounts memory amounts = _sellOrderAmounts[orderId];
        return (amounts.pending, amounts.filled, amounts.amountSent);
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

    // Returns historical data closest to target timestamp
    function getHistoricalDataByNearestTimestamp(uint256 targetTimestamp) external view returns (HistoricalData memory data) {
        if (_historicalData.length == 0) return HistoricalData(0, 0, 0, 0, 0, 0);
        uint256 minDiff = type(uint256).max;
        uint256 closestIndex = 0;
        for (uint256 i = 0; i < _historicalData.length; i++) {
            uint256 diff = targetTimestamp > _historicalData[i].timestamp
                ? targetTimestamp - _historicalData[i].timestamp
                : _historicalData[i].timestamp - targetTimestamp;
            if (diff < minDiff) {
                minDiff = diff;
                closestIndex = i;
            }
        }
        return _historicalData[closestIndex];
    }

    // Returns globalizer address
    function globalizerAddressView() external view returns (address globalizerAddress) {
        return _globalizerAddress;
    }

    // Returns up to maxIterations pending buy order IDs for a maker, starting from step
    function makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations) external view returns (uint256[] memory orderIds) {
        uint256[] memory allOrders = _makerPendingOrders[maker];
        uint256 count = 0;
        for (uint256 i = step; i < allOrders.length && count < maxIterations; i++) {
            if (_buyOrderCores[allOrders[i]].makerAddress == maker && _buyOrderCores[allOrders[i]].status == 1) {
                count++;
            }
        }
        orderIds = new uint256[](count);
        count = 0;
        for (uint256 i = step; i < allOrders.length && count < maxIterations; i++) {
            if (_buyOrderCores[allOrders[i]].makerAddress == maker && _buyOrderCores[allOrders[i]].status == 1) {
                orderIds[count++] = allOrders[i];
            }
        }
    }

    // Returns up to maxIterations pending sell order IDs for a maker, starting from step
    function makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations) external view returns (uint256[] memory orderIds) {
        uint256[] memory allOrders = _makerPendingOrders[maker];
        uint256 count = 0;
        for (uint256 i = step; i < allOrders.length && count < maxIterations; i++) {
            if (_sellOrderCores[allOrders[i]].makerAddress == maker && _sellOrderCores[allOrders[i]].status == 1) {
                count++;
            }
        }
        orderIds = new uint256[](count);
        count = 0;
        for (uint256 i = step; i < allOrders.length && count < maxIterations; i++) {
            if (_sellOrderCores[allOrders[i]].makerAddress == maker && _sellOrderCores[allOrders[i]].status == 1) {
                orderIds[count++] = allOrders[i];
            }
        }
    }

    // Returns full buy order details
    function getFullBuyOrderDetails(uint256 orderId) external view returns (
        BuyOrderCore memory core,
        BuyOrderPricing memory pricing,
        BuyOrderAmounts memory amounts
    ) {
        core = _buyOrderCores[orderId];
        pricing = _buyOrderPricings[orderId];
        amounts = _buyOrderAmounts[orderId];
    }

    // Returns full sell order details
    function getFullSellOrderDetails(uint256 orderId) external view returns (
        SellOrderCore memory core,
        SellOrderPricing memory pricing,
        SellOrderAmounts memory amounts
    ) {
        core = _sellOrderCores[orderId];
        pricing = _sellOrderPricings[orderId];
        amounts = _sellOrderAmounts[orderId];
    }

    // Returns up to maxIterations order IDs for a maker, starting from step
    function makerOrdersView(address maker, uint256 step, uint256 maxIterations) external view returns (uint256[] memory orderIds) {
        uint256[] memory allOrders = _makerPendingOrders[maker];
        uint256 length = allOrders.length;
        if (step >= length) return new uint256[](0);
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        orderIds = new uint256[](limit);
        for (uint256 i = 0; i < limit; i++) {
            orderIds[i] = allOrders[step + i];
        }
    }
}