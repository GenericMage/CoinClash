// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.10
// Changes:
// - v0.1.10: Added error logging in update, transactToken, transactNative with new events ExternalCallFailed, UpdateFailed, TransactionFailed. Emitted decoded reasons from external calls and added specific revert messages.
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
    event ExternalCallFailed(address indexed target, string functionName, string reason);
    event UpdateFailed(uint256 indexed listingId, string reason);
    event TransactionFailed(address indexed recipient, string reason);

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
        if (_registryAddress == address(0) || maker == address(0)) return;
        uint256 tokenCount = (_tokenA != address(0) ? 1 : 0) + (_tokenB != address(0) ? 1 : 0);
        address[] memory tokens = new address[](tokenCount);
        uint256 index = 0;
        if (_tokenA != address(0)) tokens[index++] = _tokenA;
        if (_tokenB != address(0)) tokens[index] = _tokenB;
        uint256 gasBefore = gasleft();
        try ITokenRegistry(_registryAddress).initializeTokens{gas: 500000}(maker, tokens) {
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit UpdateRegistryFailed(maker, tokens, decodedReason);
            emit ExternalCallFailed(_registryAddress, "initializeTokens", decodedReason);
            revert(string(abi.encodePacked("Registry update failed: ", decodedReason)));
        }
        uint256 gasUsed = gasBefore - gasleft();
        if (gasUsed > 500000) {
            string memory reason = "Out of gas in registry call";
            emit UpdateRegistryFailed(maker, tokens, reason);
            emit UpdateFailed(_listingId, reason);
            revert(string(abi.encodePacked("Registry call failed: ", reason)));
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
        if (_globalizerAddress == address(0) || _nextOrderId == 0) return;
        uint256 orderId = _nextOrderId - 1; // Latest order ID
        address maker;
        address token;
        // Check if it's a buy order
        BuyOrderCore memory buyCore = _buyOrderCores[orderId];
        if (buyCore.makerAddress != address(0)) {
            maker = buyCore.makerAddress;
            token = _tokenB != address(0) ? _tokenB : _tokenA; // Use tokenB for buy
        } else {
            // Check if it's a sell order
            SellOrderCore memory sellCore = _sellOrderCores[orderId];
            if (sellCore.makerAddress != address(0)) {
                maker = sellCore.makerAddress;
                token = _tokenA != address(0) ? _tokenA : _tokenB; // Use tokenA for sell
            } else {
                return; // No valid order found
            }
        }
        uint256 gasBefore = gasleft();
        try ICCGlobalizer(_globalizerAddress).globalizeOrders{gas: gasBefore / 10}(maker, token) {
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit ExternalCallFailed(_globalizerAddress, "globalizeOrders", decodedReason);
            revert(string(abi.encodePacked("Globalizer call failed: ", decodedReason)));
        }
    }

    // Updates balances, orders, or historical data, restricted to routers
    function update(UpdateType[] memory updates) external {
        require(_routers[msg.sender], "Router only");
        VolumeBalance storage balances = _volumeBalance;
        bool volumeUpdated = false;
        address maker = address(0);
        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0 && (u.index == 2 || u.index == 3)) {
                volumeUpdated = true;
            } else if (u.updateType == 1 && u.structId == 2 && u.value > 0) {
                volumeUpdated = true;
            } else if (u.updateType == 2 && u.structId == 2 && u.value > 0) {
                volumeUpdated = true;
            }
            if (u.updateType == 1 || u.updateType == 2) {
                maker = u.addr;
            }
        }
        if (volumeUpdated && (!_isSameDay(_lastDayFee.timestamp, block.timestamp) || _lastDayFee.timestamp == 0)) {
            uint256 xFeesAcc;
            uint256 yFeesAcc;
            try ICCLiquidityTemplate(_liquidityAddress).liquidityDetail() returns (
                uint256,
                uint256,
                uint256,
                uint256,
                uint256 xFees,
                uint256 yFees
            ) {
                xFeesAcc = xFees;
                yFeesAcc = yFees;
            } catch (bytes memory reason) {
                string memory decodedReason = string(reason);
                emit ExternalCallFailed(_liquidityAddress, "liquidityDetail", decodedReason);
                xFeesAcc = _lastDayFee.lastDayXFeesAcc;
                yFeesAcc = _lastDayFee.lastDayYFeesAcc;
            }
            _lastDayFee = LastDayFee(xFeesAcc, yFeesAcc, _floorToMidnight(block.timestamp));
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
                        if (amounts.pending < u.value) {
                            string memory reason = "Insufficient pending amount for buy order";
                            emit UpdateFailed(_listingId, reason);
                            revert(string(abi.encodePacked("Update failed: ", reason)));
                        }
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
                        if (amounts.pending < u.value) {
                            string memory reason = "Insufficient pending amount for sell order";
                            emit UpdateFailed(_listingId, reason);
                            revert(string(abi.encodePacked("Update failed: ", reason)));
                        }
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
                HistoricalData memory data;
                data.price = u.value;
                data.xBalance = balances.xBalance;
                data.yBalance = balances.yBalance;
                data.xVolume = balances.xVolume;
                data.yVolume = balances.yVolume;
                data.timestamp = block.timestamp;
                _historicalData.push(data);
            }
        }
        uint256 reserveA;
        uint256 reserveB;
        try IERC20(_tokenA).balanceOf(_uniswapV2Pair) returns (uint256 balanceA) {
            reserveA = _tokenA == address(0) ? 0 : normalize(balanceA, _decimalsA);
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit ExternalCallFailed(_tokenA, "balanceOf", decodedReason);
            reserveA = 0;
        }
        try IERC20(_tokenB).balanceOf(_uniswapV2Pair) returns (uint256 balanceB) {
            reserveB = _tokenB == address(0) ? 0 : normalize(balanceB, _decimalsB);
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit ExternalCallFailed(_tokenB, "balanceOf", decodedReason);
            reserveB = 0;
        }
        _currentPrice = reserveA == 0 ? 0 : (reserveB * 1e18) / reserveA;
        if (maker != address(0)) {
            _updateRegistry(maker);
        }
        globalizeUpdate();
        emit BalancesUpdated(_listingId, balances.xBalance, balances.yBalance);
    }

    // Processes payout updates, restricted to routers
    function ssUpdate(ICCListing.PayoutUpdate[] memory payoutUpdates) external override {
        require(_routers[msg.sender], "Router only");
        for (uint256 i = 0; i < payoutUpdates.length; i++) {
            ICCListing.PayoutUpdate memory p = payoutUpdates[i];
            if (p.payoutType == 0) {
                LongPayoutStruct storage payout = _longPayouts[_nextOrderId];
                payout.makerAddress = p.recipient;
                payout.recipientAddress = p.recipient;
                payout.required = p.required;
                payout.orderId = _nextOrderId;
                payout.status = 1;
                _longPayoutsByIndex.push(_nextOrderId);
                _userPayoutIDs[p.recipient].push(_nextOrderId);
                emit PayoutOrderCreated(_nextOrderId, true, 1);
                _nextOrderId++;
            } else if (p.payoutType == 1) {
                ShortPayoutStruct storage payout = _shortPayouts[_nextOrderId];
                payout.makerAddress = p.recipient;
                payout.recipientAddress = p.recipient;
                payout.amount = p.required;
                payout.orderId = _nextOrderId;
                payout.status = 1;
                _shortPayoutsByIndex.push(_nextOrderId);
                _userPayoutIDs[p.recipient].push(_nextOrderId);
                emit PayoutOrderCreated(_nextOrderId, false, 1);
                _nextOrderId++;
            }
        }
    }

    // Transfers ERC20 tokens, restricted to routers
    function transactToken(address token, uint256 amount, address recipient) external {
        require(_routers[msg.sender], "Router only");
        require(token == _tokenA || token == _tokenB, "Invalid token");
        uint8 decimals = token == _tokenA ? _decimalsA : _decimalsB;
        uint256 normalizedAmount = normalize(amount, decimals);
        if (token == _tokenA) {
            _volumeBalance.xBalance += normalizedAmount;
            _volumeBalance.xVolume += normalizedAmount;
        } else {
            _volumeBalance.yBalance += normalizedAmount;
            _volumeBalance.yVolume += normalizedAmount;
        }
        uint256 reserveA;
        uint256 reserveB;
        try IERC20(_tokenA).balanceOf(_uniswapV2Pair) returns (uint256 balanceA) {
            reserveA = _tokenA == address(0) ? 0 : normalize(balanceA, _decimalsA);
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit ExternalCallFailed(_tokenA, "balanceOf", decodedReason);
            reserveA = 0;
        }
        try IERC20(_tokenB).balanceOf(_uniswapV2Pair) returns (uint256 balanceB) {
            reserveB = _tokenB == address(0) ? 0 : normalize(balanceB, _decimalsB);
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit ExternalCallFailed(_tokenB, "balanceOf", decodedReason);
            reserveB = 0;
        }
        _currentPrice = reserveA == 0 ? 0 : (reserveB * 1e18) / reserveA;
        try IERC20(token).transfer(recipient, amount) returns (bool success) {
            if (!success) {
                string memory reason = "Token transfer returned false";
                emit TransactionFailed(recipient, reason);
                revert(string(abi.encodePacked("Token transfer failed: ", reason)));
            }
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit ExternalCallFailed(token, "transfer", decodedReason);
            emit TransactionFailed(recipient, decodedReason);
            revert(string(abi.encodePacked("Token transfer failed: ", decodedReason)));
        }
        emit BalancesUpdated(_listingId, _volumeBalance.xBalance, _volumeBalance.yBalance);
    }

    // Transfers native ETH, restricted to routers
    function transactNative(uint256 amount, address recipient) external {
        require(_routers[msg.sender], "Router only");
        require(_tokenA == address(0) || _tokenB == address(0), "No native token");
        uint256 normalizedAmount = normalize(amount, 18);
        if (_tokenA == address(0)) {
            _volumeBalance.xBalance += normalizedAmount;
            _volumeBalance.xVolume += normalizedAmount;
        } else {
            _volumeBalance.yBalance += normalizedAmount;
            _volumeBalance.yVolume += normalizedAmount;
        }
        uint256 reserveA;
        uint256 reserveB;
        try IERC20(_tokenA).balanceOf(_uniswapV2Pair) returns (uint256 balanceA) {
            reserveA = _tokenA == address(0) ? 0 : normalize(balanceA, _decimalsA);
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit ExternalCallFailed(_tokenA, "balanceOf", decodedReason);
            reserveA = 0;
        }
        try IERC20(_tokenB).balanceOf(_uniswapV2Pair) returns (uint256 balanceB) {
            reserveB = _tokenB == address(0) ? 0 : normalize(balanceB, _decimalsB);
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit ExternalCallFailed(_tokenB, "balanceOf", decodedReason);
            reserveB = 0;
        }
        _currentPrice = reserveA == 0 ? 0 : (reserveB * 1e18) / reserveA;
        (bool success, bytes memory data) = recipient.call{value: amount}("");
        if (!success) {
            string memory reason = data.length > 0 ? string(data) : "Native transfer call failed";
            emit TransactionFailed(recipient, reason);
            revert(string(abi.encodePacked("Native transfer failed: ", reason)));
        }
        emit BalancesUpdated(_listingId, _volumeBalance.xBalance, _volumeBalance.yBalance);
    }

    // Sets globalizer contract address, callable once
    function setGlobalizerAddress(address globalizerAddress_) external {
        require(!_globalizerSet, "Globalizer already set");
        require(globalizerAddress_ != address(0), "Invalid globalizer address");
        _globalizerAddress = globalizerAddress_;
        _globalizerSet = true;
        emit GlobalizerAddressSet(globalizerAddress_);
    }

    // Sets Uniswap V2 pair address, callable once
    function setUniswapV2Pair(address uniswapV2Pair_) external {
        require(!_uniswapV2PairSet, "Uniswap V2 pair already set");
        require(uniswapV2Pair_ != address(0), "Invalid pair address");
        _uniswapV2Pair = uniswapV2Pair_;
        _uniswapV2PairSet = true;
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
    function setListingId(uint256 listingId_) external {
        require(_listingId == 0, "Listing ID already set");
        _listingId = listingId_;
    }

    // Sets liquidity address, callable once
    function setLiquidityAddress(address liquidityAddress_) external {
        require(_liquidityAddress == address(0), "Liquidity already set");
        require(liquidityAddress_ != address(0), "Invalid liquidity address");
        _liquidityAddress = liquidityAddress_;
    }

    // Sets token addresses, callable once
    function setTokens(address tokenA_, address tokenB_) external {
        require(_tokenA == address(0) && _tokenB == address(0), "Tokens already set");
        require(tokenA_ != tokenB_, "Tokens must be different");
        require(tokenA_ != address(0) || tokenB_ != address(0), "Both tokens cannot be zero");
        _tokenA = tokenA_;
        _tokenB = tokenB_;
        _decimalsA = tokenA_ == address(0) ? 18 : IERC20(tokenA_).decimals();
        _decimalsB = tokenB_ == address(0) ? 18 : IERC20(tokenB_).decimals();
    }

    // Sets agent address, callable once
    function setAgent(address agent_) external {
        require(_agent == address(0), "Agent already set");
        require(agent_ != address(0), "Invalid agent address");
        _agent = agent_;
    }

    // Sets registry address, callable once
    function setRegistry(address registryAddress_) external {
        require(_registryAddress == address(0), "Registry already set");
        require(registryAddress_ != address(0), "Invalid registry address");
        _registryAddress = registryAddress_;
    }

    // Returns agent address
    function agentView() external view returns (address agent) {
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