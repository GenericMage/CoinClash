// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.2.0
// Changes:
// - v0.2.0: Bumped version
// - v0.1.18: Fixed inconsistent volume tracking in sell order settlement to align with buy order logic. xVolume now tracks tokenA traded, yVolume tracks tokenB traded.
// - v0.1.17: Fixed balance update logic to adjust incrementally. Corrected order settlement to use exchange rate from Uniswap pair balanceOf. Updated volume tracking to reflect actual token amounts during settlement only.
// - v0.1.16: Fixed TypeError in setRouters by using address as key for _routers mapping
// - v0.1.15: Fixed ParserError in queryDurationVolume by renaming 'days' parameter to 'durationDays' to avoid potential keyword conflict and ensure clear syntax.
// - v0.1.14: Fixed ParserError in queryDurationVolume by explicitly casting days parameter to uint256.
// - v0.1.13: Removed redundant view functions and made corresponding state variables/mappings public.
// - v0.1.12: Restored queryYield to calculate annualized yield, adjusted dayStart 
// - v0.1.11: Fixed order settlement in update
// Compatible with CCLiquidityTemplate.sol (v0.1.1), CCMainPartial.sol (v0.0.12), CCLiquidityPartial.sol (v0.0.21), ICCLiquidity.sol (v0.0.5), ICCListing.sol (v0.0.7), CCOrderRouter.sol (v0.0.11), TokenRegistry.sol (2025-08-04).

interface IERC20 {
    function decimals() external view returns (uint8);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface ICCListing {
    function prices(uint256) external view returns (uint256 price);
    function volumeBalances(uint256) external view returns (uint256 xBalance, uint256 yBalance);
    function liquidityAddressView() external view returns (address);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
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
    mapping(address => bool) private _routers;
    bool private _routersSet;
    address public tokenA; // Returns address token
    address public tokenB; // Returns address token
    uint8 public decimalsA; // Returns uint8 decimals
    uint8 public decimalsB; // Returns uint8 decimals
    address public uniswapV2PairView; // Returns address pair
    bool private _uniswapV2PairSet;
    uint256 public getListingId; // Returns uint256 listingId
    address public agentView; // Returns address agent
    address private _registryAddress;
    address public liquidityAddressView; // Returns address liquidityAddress
    address private _globalizerAddress;
    bool private _globalizerSet;
    uint256 public getNextOrderId; // Returns uint256 nextOrderId

    struct PayoutUpdate {
        uint8 payoutType; // 0: Long, 1: Short
        address recipient;
        uint256 required;
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

    uint256 public listingPriceView; // Returns uint256 price
    uint256[] public pendingBuyOrdersView; // Returns uint256[] memory orderIds
    uint256[] public pendingSellOrdersView; // Returns uint256[] memory orderIds
    mapping(address => uint256[]) public makerPendingOrdersView; // Returns uint256[] memory orderIds
    uint256[] public longPayoutByIndexView; // Returns uint256[] memory orderIds
    uint256[] public shortPayoutByIndexView; // Returns uint256[] memory orderIds
    mapping(address => uint256[]) public userPayoutIDsView; // Returns uint256[] memory orderIds

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
    mapping(uint256 => uint256) private _dayStartIndices;

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

    mapping(uint256 => BuyOrderCore) public getBuyOrderCore; // Returns (address makerAddress, address recipientAddress, uint8 status)
    mapping(uint256 => BuyOrderPricing) public getBuyOrderPricing; // Returns (uint256 maxPrice, uint256 minPrice)
    mapping(uint256 => BuyOrderAmounts) public getBuyOrderAmounts; // Returns (uint256 pending, uint256 filled, uint256 amountSent)
    mapping(uint256 => SellOrderCore) public getSellOrderCore; // Returns (address makerAddress, address recipientAddress, uint8 status)
    mapping(uint256 => SellOrderPricing) public getSellOrderPricing; // Returns (uint256 maxPrice, uint256 minPrice)
    mapping(uint256 => SellOrderAmounts) public getSellOrderAmounts; // Returns (uint256 pending, uint256 filled, uint256 amountSent)
    mapping(uint256 => LongPayoutStruct) public getLongPayout; // Returns LongPayoutStruct memory payout
    mapping(uint256 => ShortPayoutStruct) public getShortPayout; // Returns ShortPayoutStruct memory payout

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
        if (_registryAddress == address(0) || maker == address(0)) return;
        uint256 tokenCount = (tokenA != address(0) ? 1 : 0) + (tokenB != address(0) ? 1 : 0);
        address[] memory tokens = new address[](tokenCount);
        uint256 index = 0;
        if (tokenA != address(0)) tokens[index++] = tokenA;
        if (tokenB != address(0)) tokens[index] = tokenB;
        uint256 gasBefore = gasleft();
        try ITokenRegistry(_registryAddress).initializeTokens{gas: 500000}(maker, tokens) {
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit UpdateRegistryFailed(maker, tokens, decodedReason);
            emit ExternalCallFailed(_registryAddress, "initializeTokens", decodedReason);
        }
        uint256 gasUsed = gasBefore - gasleft();
        if (gasUsed > 500000) {
            string memory reason = "Out of gas in registry call";
            emit UpdateRegistryFailed(maker, tokens, reason);
            emit UpdateFailed(getListingId, reason);
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
        if (_globalizerAddress == address(0) || getNextOrderId == 0) return;
        uint256 orderId = getNextOrderId - 1; // Latest order ID
        address maker;
        address token;
        // Check if it's a buy order
        BuyOrderCore memory buyCore = getBuyOrderCore[orderId];
        if (buyCore.makerAddress != address(0)) {
            maker = buyCore.makerAddress;
            token = tokenB != address(0) ? tokenB : tokenA; // Use tokenB for buy
        } else {
            // Check if it's a sell order
            SellOrderCore memory sellCore = getSellOrderCore[orderId];
            if (sellCore.makerAddress != address(0)) {
                maker = sellCore.makerAddress;
                token = tokenA != address(0) ? tokenA : tokenB; // Use tokenA for sell
            } else {
                return; // No valid order found
            }
        }
        uint256 gasBefore = gasleft();
        try ICCGlobalizer(_globalizerAddress).globalizeOrders{gas: gasBefore / 10}(maker, token) {
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit ExternalCallFailed(_globalizerAddress, "globalizeOrders", decodedReason);
        }
    }

    // Captures live price, balances, and volumes into historical data
    function _captureHistoricalData() internal {
        uint256 balanceA;
        uint256 balanceB;
        try IERC20(tokenA).balanceOf(uniswapV2PairView) returns (uint256 balA) {
            balanceA = tokenA == address(0) ? 0 : normalize(balA, decimalsA);
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit ExternalCallFailed(tokenA, "balanceOf", decodedReason);
            balanceA = 0;
        }
        try IERC20(tokenB).balanceOf(uniswapV2PairView) returns (uint256 balB) {
            balanceB = tokenB == address(0) ? 0 : normalize(balB, decimalsB);
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit ExternalCallFailed(tokenB, "balanceOf", decodedReason);
            balanceB = 0;
        }
        uint256 price = balanceA == 0 ? 0 : (balanceB * 1e18) / balanceA;
        uint256 midnight = _floorToMidnight(block.timestamp);
        if (_historicalData.length == 0 || !_isSameDay(_historicalData[_historicalData.length - 1].timestamp, block.timestamp)) {
            _dayStartIndices[midnight] = _historicalData.length;
        }
        _historicalData.push(HistoricalData({
            price: price,
            xBalance: _balance.xBalance,
            yBalance: _balance.yBalance,
            xVolume: 0, // Updated during settlement
            yVolume: 0, // Updated during settlement
            timestamp: block.timestamp
        }));
    }

    // Computes current exchange rate from Uniswap pair balanceOf
    function _getExchangeRate() internal view returns (uint256 price) {
        uint256 balanceA;
        uint256 balanceB;
        try IERC20(tokenA).balanceOf(uniswapV2PairView) returns (uint256 balA) {
            balanceA = tokenA == address(0) ? 0 : normalize(balA, decimalsA);
        } catch {
            return listingPriceView;
        }
        try IERC20(tokenB).balanceOf(uniswapV2PairView) returns (uint256 balB) {
            balanceB = tokenB == address(0) ? 0 : normalize(balB, decimalsB);
        } catch {
            return listingPriceView;
        }
        return balanceA == 0 ? 0 : (balanceB * 1e18) / balanceA;
    }

    // Updates balances, orders, or historical data, restricted to routers
    function update(UpdateType[] memory updates) external {
        require(_routers[msg.sender], "Router only");
        Balance storage balances = _balance;
        bool volumeUpdated = false;
        address maker = address(0);
        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 1 && u.structId == 2 && u.value > 0 && u.amountSent > 0) {
                volumeUpdated = true;
            } else if (u.updateType == 2 && u.structId == 2 && u.value > 0 && u.amountSent > 0) {
                volumeUpdated = true;
            }
            if (u.updateType == 1 || u.updateType == 2) {
                maker = u.addr;
            }
        }
        if (volumeUpdated && (!_isSameDay(dayStartFee.timestamp, block.timestamp) || dayStartFee.timestamp == 0)) {
            uint256 xFeesAcc;
            uint256 yFeesAcc;
            try ICCLiquidityTemplate(liquidityAddressView).liquidityDetail() returns (
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
                emit ExternalCallFailed(liquidityAddressView, "liquidityDetail", decodedReason);
                xFeesAcc = dayStartFee.dayStartXFeesAcc;
                yFeesAcc = dayStartFee.dayStartYFeesAcc;
            }
            dayStartFee = DayStartFee(xFeesAcc, yFeesAcc, _floorToMidnight(block.timestamp));
        }
        uint256 xVolume = 0;
        uint256 yVolume = 0;
        uint256 exchangeRate = _getExchangeRate();
        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0) {
                if (u.index == 0) balances.xBalance += u.value; // Incremental update for tokenA
                else if (u.index == 1) balances.yBalance += u.value; // Incremental update for tokenB
            } else if (u.updateType == 1) {
                if (u.structId == 0) {
                    BuyOrderCore storage core = getBuyOrderCore[u.index];
                    if (core.makerAddress == address(0)) {
                        core.makerAddress = u.addr;
                        core.recipientAddress = u.recipient;
                        core.status = 1;
                        pendingBuyOrdersView.push(u.index);
                        makerPendingOrdersView[u.addr].push(u.index);
                        getNextOrderId = u.index + 1;
                        emit OrderUpdated(getListingId, u.index, true, 1);
                    } else if (u.value == 0) {
                        core.status = 0;
                        removePendingOrder(pendingBuyOrdersView, u.index);
                        removePendingOrder(makerPendingOrdersView[core.makerAddress], u.index);
                        emit OrderUpdated(getListingId, u.index, true, 0);
                    }
                } else if (u.structId == 1) {
                    BuyOrderPricing storage pricing = getBuyOrderPricing[u.index];
                    pricing.maxPrice = u.maxPrice;
                    pricing.minPrice = u.minPrice;
                } else if (u.structId == 2) {
                    BuyOrderAmounts storage amounts = getBuyOrderAmounts[u.index];
                    BuyOrderCore storage core = getBuyOrderCore[u.index];
                    if (amounts.pending == 0 && core.makerAddress != address(0)) {
                        amounts.pending = u.value; // tokenB pending
                        amounts.amountSent = u.amountSent; // tokenA sent
                        balances.yBalance += u.value; // tokenB received
                    } else if (core.status == 1 && u.value > 0 && u.amountSent > 0) {
                        if (amounts.pending < u.value) {
                            string memory reason = "Insufficient pending amount for buy order";
                            emit UpdateFailed(getListingId, reason);
                            revert(string(abi.encodePacked("Update failed: ", reason)));
                        }
                        amounts.pending -= u.value;
                        amounts.filled += u.value;
                        amounts.amountSent += u.amountSent;
                        balances.xBalance += u.amountSent; // tokenA received
                        balances.yBalance -= u.value; // tokenB spent
                        xVolume += u.amountSent; // tokenA volume
                        yVolume += u.value; // tokenB volume
                        if (amounts.pending == 0) {
                            core.status = 3;
                            removePendingOrder(pendingBuyOrdersView, u.index);
                            removePendingOrder(makerPendingOrdersView[core.makerAddress], u.index);
                            emit OrderUpdated(getListingId, u.index, true, 3);
                        } else {
                            core.status = 2;
                            emit OrderUpdated(getListingId, u.index, true, 2);
                        }
                    }
                }
            } else if (u.updateType == 2) {
                if (u.structId == 0) {
                    SellOrderCore storage core = getSellOrderCore[u.index];
                    if (core.makerAddress == address(0)) {
                        core.makerAddress = u.addr;
                        core.recipientAddress = u.recipient;
                        core.status = 1;
                        pendingSellOrdersView.push(u.index);
                        makerPendingOrdersView[u.addr].push(u.index);
                        getNextOrderId = u.index + 1;
                        emit OrderUpdated(getListingId, u.index, false, 1);
                    } else if (u.value == 0) {
                        core.status = 0;
                        removePendingOrder(pendingSellOrdersView, u.index);
                        removePendingOrder(makerPendingOrdersView[core.makerAddress], u.index);
                        emit OrderUpdated(getListingId, u.index, false, 0);
                    }
                } else if (u.structId == 1) {
                    SellOrderPricing storage pricing = getSellOrderPricing[u.index];
                    pricing.maxPrice = u.maxPrice;
                    pricing.minPrice = u.minPrice;
                } else if (u.structId == 2) {
                    SellOrderAmounts storage amounts = getSellOrderAmounts[u.index];
                    SellOrderCore storage core = getSellOrderCore[u.index];
                    if (amounts.pending == 0 && core.makerAddress != address(0)) {
                        amounts.pending = u.value; // tokenA pending
                        amounts.amountSent = u.amountSent; // tokenB sent
                        balances.xBalance += u.value; // tokenA received
                    } else if (core.status == 1 && u.value > 0 && u.amountSent > 0) {
                        if (amounts.pending < u.value) {
                            string memory reason = "Insufficient pending amount for sell order";
                            emit UpdateFailed(getListingId, reason);
                            revert(string(abi.encodePacked("Update failed: ", reason)));
                        }
                        amounts.pending -= u.value;
                        amounts.filled += u.value;
                        amounts.amountSent += u.amountSent;
                        balances.xBalance -= u.value; // tokenA spent
                        balances.yBalance += u.amountSent; // tokenB received
                        xVolume += u.value; // tokenA volume
                        yVolume += u.amountSent; // tokenB volume
                        if (amounts.pending == 0) {
                            core.status = 3;
                            removePendingOrder(pendingSellOrdersView, u.index);
                            removePendingOrder(makerPendingOrdersView[core.makerAddress], u.index);
                            emit OrderUpdated(getListingId, u.index, false, 3);
                        } else {
                            core.status = 2;
                            emit OrderUpdated(getListingId, u.index, false, 2);
                        }
                    }
                }
            }
        }
        if (xVolume > 0 || yVolume > 0) {
            HistoricalData storage latest = _historicalData[_historicalData.length - 1];
            latest.xVolume += xVolume;
            latest.yVolume += yVolume;
            _captureHistoricalData();
        }
        if (maker != address(0)) {
            _updateRegistry(maker);
            globalizeUpdate();
        }
        emit BalancesUpdated(getListingId, balances.xBalance, balances.yBalance);
    }

    // Processes long and short payout updates, restricted to routers
    function ssUpdate(PayoutUpdate[] memory payoutUpdates) external {
        require(_routers[msg.sender], "Router only");
        for (uint256 i = 0; i < payoutUpdates.length; i++) {
            PayoutUpdate memory p = payoutUpdates[i];
            if (p.payoutType == 0) {
                LongPayoutStruct storage payout = getLongPayout[getNextOrderId];
                payout.makerAddress = p.recipient;
                payout.recipientAddress = p.recipient;
                payout.required = p.required;
                payout.orderId = getNextOrderId;
                payout.status = 1;
                longPayoutByIndexView.push(getNextOrderId);
                userPayoutIDsView[p.recipient].push(getNextOrderId);
                emit PayoutOrderCreated(getNextOrderId, true, 1);
                getNextOrderId++;
            } else if (p.payoutType == 1) {
                ShortPayoutStruct storage payout = getShortPayout[getNextOrderId];
                payout.makerAddress = p.recipient;
                payout.recipientAddress = p.recipient;
                payout.amount = p.required;
                payout.orderId = getNextOrderId;
                payout.status = 1;
                shortPayoutByIndexView.push(getNextOrderId);
                userPayoutIDsView[p.recipient].push(getNextOrderId);
                emit PayoutOrderCreated(getNextOrderId, false, 1);
                getNextOrderId++;
            }
        }
    }

    // Transfers ERC20 tokens, restricted to routers
    function transactToken(address token, uint256 amount, address recipient) external {
        require(_routers[msg.sender], "Router only");
        require(token == tokenA || token == tokenB, "Invalid token");
        uint8 decimals = token == tokenA ? decimalsA : decimalsB;
        uint256 normalizedAmount = normalize(amount, decimals);
        if (token == tokenA) {
            _balance.xBalance += normalizedAmount;
        } else {
            _balance.yBalance += normalizedAmount;
        }
        uint256 balanceA;
        uint256 balanceB;
        try IERC20(tokenA).balanceOf(uniswapV2PairView) returns (uint256 balA) {
            balanceA = tokenA == address(0) ? 0 : normalize(balA, decimalsA);
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit ExternalCallFailed(tokenA, "balanceOf", decodedReason);
            balanceA = 0;
        }
        try IERC20(tokenB).balanceOf(uniswapV2PairView) returns (uint256 balB) {
            balanceB = tokenB == address(0) ? 0 : normalize(balB, decimalsB);
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit ExternalCallFailed(tokenB, "balanceOf", decodedReason);
            balanceB = 0;
        }
        listingPriceView = balanceA == 0 ? 0 : (balanceB * 1e18) / balanceA;
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
        emit BalancesUpdated(getListingId, _balance.xBalance, _balance.yBalance);
    }

    // Transfers native ETH, restricted to routers
    function transactNative(uint256 amount, address recipient) external payable {
        require(_routers[msg.sender], "Router only");
        require(tokenA == address(0) || tokenB == address(0), "No native token");
        uint256 normalizedAmount = normalize(amount, 18);
        if (tokenA == address(0)) {
            _balance.xBalance += normalizedAmount;
        } else {
            _balance.yBalance += normalizedAmount;
        }
        uint256 balanceA;
        uint256 balanceB;
        try IERC20(tokenA).balanceOf(uniswapV2PairView) returns (uint256 balA) {
            balanceA = tokenA == address(0) ? 0 : normalize(balA, decimalsA);
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit ExternalCallFailed(tokenA, "balanceOf", decodedReason);
            balanceA = 0;
        }
        try IERC20(tokenB).balanceOf(uniswapV2PairView) returns (uint256 balB) {
            balanceB = tokenB == address(0) ? 0 : normalize(balB, decimalsB);
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit ExternalCallFailed(tokenB, "balanceOf", decodedReason);
            balanceB = 0;
        }
        listingPriceView = balanceA == 0 ? 0 : (balanceB * 1e18) / balanceA;
        (bool success, bytes memory data) = recipient.call{value: amount}("");
        if (!success) {
            string memory reason = data.length > 0 ? string(data) : "Native transfer call failed";
            emit TransactionFailed(recipient, reason);
            revert(string(abi.encodePacked("Native transfer failed: ", reason)));
        }
        emit BalancesUpdated(getListingId, _balance.xBalance, _balance.yBalance);
    }

    // Calculates annualized yield based on liquidity fees
    function queryYield(bool isA, uint256 maxIterations, uint256 depositAmount, bool isTokenA) external view returns (uint256 yieldAnnualized) {
        require(maxIterations > 0, "Invalid maxIterations");
        if (liquidityAddressView == address(0)) return 0;
        uint256 xLiquid;
        uint256 yLiquid;
        uint256 xFeesAcc;
        uint256 yFeesAcc;
        try ICCLiquidityTemplate(liquidityAddressView).liquidityDetail() returns (
            uint256 xLiq,
            uint256 yLiq,
            uint256,
            uint256,
            uint256 xFees,
            uint256 yFees
        ) {
            xLiquid = xLiq;
            yLiquid = yLiq;
            xFeesAcc = xFees;
            yFeesAcc = yFees;
        } catch {
            return 0;
        }
        DayStartFee memory dayStart = dayStartFee;
        if (dayStart.timestamp == 0 || !_isSameDay(dayStart.timestamp, block.timestamp)) return 0;
        uint256 fees = isTokenA ? xFeesAcc : yFeesAcc;
        uint256 dFeesAcc = isTokenA ? dayStart.dayStartXFeesAcc : dayStart.dayStartYFeesAcc;
        uint256 liquid = isTokenA ? xLiquid : yLiquid;
        uint256 contributedFees = fees > dFeesAcc ? fees - dFeesAcc : 0;
        uint256 liquidityContribution = liquid > 0 ? (depositAmount * 1e18) / (liquid + depositAmount) : 0;
        uint256 feeShare = (contributedFees * liquidityContribution) / 1e18;
        feeShare = feeShare > contributedFees ? contributedFees : feeShare;
        uint256 dailyFees = feeShare;
        yieldAnnualized = (dailyFees * 365 * 10000) / (depositAmount > 0 ? depositAmount : 1);
        return yieldAnnualized;
    }

    // Approximates volume over a specified number of days
    function queryDurationVolume(bool isA, uint256 durationDays, uint256 maxIterations) external view returns (uint256 volume) {
        require(durationDays > 0, "Invalid durationDays");
        require(maxIterations > 0, "Invalid maxIterations");
        if (_historicalData.length == 0) return 0;
        uint256 currentMidnight = _floorToMidnight(block.timestamp);
        uint256 startMidnight = currentMidnight - (durationDays * 86400);
        uint256 totalVolume = 0;
        uint256 iterationsLeft = maxIterations;
        for (uint256 i = _historicalData.length; i > 0 && iterationsLeft > 0; i--) {
            HistoricalData memory data = _historicalData[i - 1];
            if (data.timestamp >= startMidnight && data.timestamp <= currentMidnight) {
                totalVolume += isA ? data.xVolume : data.yVolume;
            }
            iterationsLeft--;
        }
        return totalVolume;
    }

    // Returns up to count day boundary indices and timestamps
    function getLastDays(uint256 count, uint256 maxIterations) external view returns (uint256[] memory indices, uint256[] memory timestamps) {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 currentMidnight = _floorToMidnight(block.timestamp);
        uint256[] memory tempIndices = new uint256[](maxIterations);
        uint256[] memory tempTimestamps = new uint256[](maxIterations);
        uint256 found = 0;
        uint256 iterationsLeft = maxIterations;
        for (uint256 i = 0; i < count && iterationsLeft > 0; i++) {
            uint256 dayTimestamp = currentMidnight - (i * 86400);
            uint256 index = _dayStartIndices[dayTimestamp];
            if (_historicalData.length > index && _historicalData[index].timestamp == dayTimestamp) {
                tempIndices[found] = index;
                tempTimestamps[found] = dayTimestamp;
                found++;
            }
            iterationsLeft--;
        }
        indices = new uint256[](found);
        timestamps = new uint256[](found);
        for (uint256 i = 0; i < found; i++) {
            indices[i] = tempIndices[i];
            timestamps[i] = tempTimestamps[i];
        }
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
    function setUniswapV2Pair(address _uniswapV2Pair) external {
        require(!_uniswapV2PairSet, "Uniswap V2 pair already set");
        require(_uniswapV2Pair != address(0), "Invalid pair address");
        uniswapV2PairView = _uniswapV2Pair;
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
    function setListingId(uint256 _listingId) external {
        require(getListingId == 0, "Listing ID already set");
        getListingId = _listingId;
    }

    // Sets liquidity address, callable once
    function setLiquidityAddress(address _liquidityAddress) external {
        require(liquidityAddressView == address(0), "Liquidity already set");
        require(_liquidityAddress != address(0), "Invalid liquidity address");
        liquidityAddressView = _liquidityAddress;
    }

    // Sets token addresses, callable once
    function setTokens(address _tokenA, address _tokenB) external {
        require(tokenA == address(0) && tokenB == address(0), "Tokens already set");
        require(_tokenA != _tokenB, "Tokens must be different");
        require(_tokenA != address(0) || _tokenB != address(0), "Both tokens cannot be zero");
        tokenA = _tokenA;
        tokenB = _tokenB;
        decimalsA = _tokenA == address(0) ? 18 : IERC20(_tokenA).decimals();
        decimalsB = _tokenB == address(0) ? 18 : IERC20(_tokenB).decimals();
    }

    // Sets agent address, callable once
    function setAgent(address _agent) external {
        require(agentView == address(0), "Agent already set");
        require(_agent != address(0), "Invalid agent address");
        agentView = _agent;
    }

    // Sets registry address, callable once
    function setRegistry(address registryAddress_) external {
        require(_registryAddress == address(0), "Registry already set");
        require(registryAddress_ != address(0), "Invalid registry address");
        _registryAddress = registryAddress_;
    }

    // Returns token pair
    function getTokens() external view returns (address tokenA_, address tokenB_) {
        require(tokenA != address(0) || tokenB != address(0), "Tokens not set");
        return (tokenA, tokenB);
    }

    // Computes current price from Uniswap V2 pair token balances
    function prices(uint256) external view returns (uint256 price) {
        uint256 balanceA;
        uint256 balanceB;
        try IERC20(tokenA).balanceOf(uniswapV2PairView) returns (uint256 balA) {
            balanceA = tokenA == address(0) ? 0 : normalize(balA, decimalsA);
        } catch {
            return listingPriceView;
        }
        try IERC20(tokenB).balanceOf(uniswapV2PairView) returns (uint256 balB) {
            balanceB = tokenB == address(0) ? 0 : normalize(balB, decimalsB);
        } catch {
            return listingPriceView;
        }
        return balanceA == 0 ? 0 : (balanceB * 1e18) / balanceA;
    }

    // Returns balances
    function volumeBalances(uint256) external view returns (uint256 xBalance, uint256 yBalance) {
        return (_balance.xBalance, _balance.yBalance);
    }

    // Returns balance and volume details
    function listingVolumeBalancesView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume) {
        xBalance = _balance.xBalance;
        yBalance = _balance.yBalance;
        if (_historicalData.length > 0) {
            HistoricalData memory latest = _historicalData[_historicalData.length - 1];
            xVolume = latest.xVolume;
            yVolume = latest.yVolume;
        } else {
            xVolume = 0;
            yVolume = 0;
        }
    }

    // Returns up to maxIterations pending buy order IDs for a maker, starting from step
    function makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations) external view returns (uint256[] memory orderIds) {
        uint256[] memory allOrders = makerPendingOrdersView[maker];
        uint256 count = 0;
        for (uint256 i = step; i < allOrders.length && count < maxIterations; i++) {
            if (getBuyOrderCore[allOrders[i]].makerAddress == maker && getBuyOrderCore[allOrders[i]].status == 1) {
                count++;
            }
        }
        orderIds = new uint256[](count);
        count = 0;
        for (uint256 i = step; i < allOrders.length && count < maxIterations; i++) {
            if (getBuyOrderCore[allOrders[i]].makerAddress == maker && getBuyOrderCore[allOrders[i]].status == 1) {
                orderIds[count++] = allOrders[i];
            }
        }
    }

    // Returns up to maxIterations pending sell order IDs for a maker, starting from step
    function makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations) external view returns (uint256[] memory orderIds) {
        uint256[] memory allOrders = makerPendingOrdersView[maker];
        uint256 count = 0;
        for (uint256 i = step; i < allOrders.length && count < maxIterations; i++) {
            if (getSellOrderCore[allOrders[i]].makerAddress == maker && getSellOrderCore[allOrders[i]].status == 1) {
                count++;
            }
        }
        orderIds = new uint256[](count);
        count = 0;
        for (uint256 i = step; i < allOrders.length && count < maxIterations; i++) {
            if (getSellOrderCore[allOrders[i]].makerAddress == maker && getSellOrderCore[allOrders[i]].status == 1) {
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
        core = getBuyOrderCore[orderId];
        pricing = getBuyOrderPricing[orderId];
        amounts = getBuyOrderAmounts[orderId];
    }

    // Returns full sell order details
    function getFullSellOrderDetails(uint256 orderId) external view returns (
        SellOrderCore memory core,
        SellOrderPricing memory pricing,
        SellOrderAmounts memory amounts
    ) {
        core = getSellOrderCore[orderId];
        pricing = getSellOrderPricing[orderId];
        amounts = getSellOrderAmounts[orderId];
    }

    // Returns up to maxIterations order IDs for a maker, starting from step
    function makerOrdersView(address maker, uint256 step, uint256 maxIterations) external view returns (uint256[] memory orderIds) {
        uint256[] memory allOrders = makerPendingOrdersView[maker];
        uint256 length = allOrders.length;
        if (step >= length) return new uint256[](0);
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        orderIds = new uint256[](limit);
        for (uint256 i = 0; i < limit; i++) {
            orderIds[i] = allOrders[step + i];
        }
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
}