/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-08-05: Removed caller parameter from ISSListing.update to match ICCListingTemplate signature. Version updated to 0.0.11.
 - 2025-08-05: Corrected ISSListing interface to match ICCListingTemplate: updated UpdateType struct to include structId, maxPrice, minPrice, amountSent; fixed prices and volumeBalances to take uint256 parameter; removed address parameter from liquidityAddressView. Adjusted function calls in PositionHealthView and LiquidationRiskCount to use prices(0). Version updated to 0.0.10.
 - 2025-08-05: Replaced hyphen-delimited string parameters in CSUpdate with structured arrays and updated parsing functions to handle arrays, removing abi.decode. Added error logging events (UpdateFailed, RemovalFailed) and restructured CSUpdate for early error checking. Removed SafeERC20, imported IERC20, and used direct calls. Version updated to 0.0.9.
 - 2025-07-18: Refactored CSUpdate to use hyphen-delimited string parameters for paired data, parsed by new helper functions to resolve stack too deep error. Version updated to 0.0.8.
*/

pragma solidity ^0.8.2;

import "../imports/IERC20.sol";
import "../imports/Ownable.sol";

interface ISSAgent {
    struct ListingDetails {
        address listingAddress; // Listing contract address
        address liquidityAddress; // Associated liquidity contract address
        address tokenA; // First token in pair
        address tokenB; // Second token in pair
        uint256 listingId; // Listing ID
    }

    function getListing(address tokenA, address tokenB) external view returns (address);
    function isValidListing(address listingAddress) external view returns (bool isValid, ListingDetails memory details);
}

interface ISSListing {
    function prices(uint256) external view returns (uint256);
    function volumeBalances(uint256) external view returns (uint256 xBalance, uint256 yBalance);
    function liquidityAddressView() external view returns (address);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function ssUpdate(address caller, PayoutUpdate[] calldata updates) external;
    struct PayoutUpdate {
        uint8 payoutType;
        address recipient;
        uint256 required;
    }
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
    struct UpdateType {
        uint8 updateType;
        uint8 structId;
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 amountSent;
    }
    function update(UpdateType[] calldata updates) external;
}

contract CSStorage is Ownable {
    uint256 public constant DECIMAL_PRECISION = 1e18;
    address public agentAddress;

    // Mapping to track authorized mux contracts
    mapping(address => bool) public muxes;

    // Position storage structures
    struct PositionCore1 {
        uint256 positionId;
        address listingAddress;
        address makerAddress;
        uint8 positionType;
    }

    struct PositionCore2 {
        bool status1;
        uint8 status2;
    }

    struct PriceParams1 {
        uint256 minEntryPrice;
        uint256 maxEntryPrice;
        uint256 minPrice;
        uint256 priceAtEntry;
        uint8 leverage;
    }

    struct PriceParams2 {
        uint256 liquidationPrice;
    }

    struct MarginParams1 {
        uint256 initialMargin;
        uint256 taxedMargin;
        uint256 excessMargin;
        uint256 fee;
    }

    struct MarginParams2 {
        uint256 initialLoan;
    }

    struct ExitParams {
        uint256 stopLossPrice;
        uint256 takeProfitPrice;
        uint256 exitPrice;
    }

    struct OpenInterest {
        uint256 leverageAmount;
        uint256 timestamp;
    }

    // Update parameter structs
    struct CoreParams {
        uint256 positionId;
        address listingAddress;
        address makerAddress;
        uint8 positionType;
        bool status1;
        uint8 status2;
    }

    struct PriceParams {
        uint256 minEntryPrice;
        uint256 maxEntryPrice;
        uint256 minPrice;
        uint256 priceAtEntry;
        uint8 leverage;
        uint256 liquidationPrice;
    }

    struct MarginParams {
        uint256 initialMargin;
        uint256 taxedMargin;
        uint256 excessMargin;
        uint256 fee;
        uint256 initialLoan;
    }

    struct ExitAndInterestParams {
        uint256 stopLossPrice;
        uint256 takeProfitPrice;
        uint256 exitPrice;
        uint256 leverageAmount;
        uint256 timestamp;
    }

    struct MakerMarginParams {
        address token;
        address maker;
        address marginToken;
        uint256 marginAmount;
    }

    struct PositionArrayParams {
        address listingAddress;
        uint8 positionType;
        bool addToPending;
        bool addToActive;
    }

    struct HistoricalInterestParams {
        uint256 longIO;
        uint256 shortIO;
        uint256 timestamp;
    }

    // Storage mappings
    mapping(address => mapping(address => uint256)) public makerTokenMargin;
    mapping(address => address[]) public makerMarginTokens;
    mapping(uint256 => PositionCore1) public positionCore1;
    mapping(uint256 => PositionCore2) public positionCore2;
    mapping(uint256 => PriceParams1) public priceParams1;
    mapping(uint256 => PriceParams2) public priceParams2;
    mapping(uint256 => MarginParams1) public marginParams1;
    mapping(uint256 => MarginParams2) public marginParams2;
    mapping(uint256 => ExitParams) public exitParams;
    mapping(uint256 => OpenInterest) public openInterest;
    mapping(uint8 => uint256[]) public positionsByType;
    mapping(address => mapping(uint8 => uint256[])) public pendingPositions;
    mapping(uint256 => address) public positionToken;
    mapping(uint256 => uint256) public longIOByHeight;
    mapping(uint256 => uint256) public shortIOByHeight;
    mapping(uint256 => uint256) public historicalInterestTimestamps;
    uint256 public positionCount;

    // Events
    event PositionClosed(uint256 indexed positionId, address indexed maker, uint256 payout);
    event MuxAdded(address indexed mux);
    event MuxRemoved(address indexed mux);
    event UpdateFailed(uint256 positionId, string reason);
    event RemovalFailed(uint256 positionId, string reason);

    // Modifier to restrict functions to authorized muxes
    modifier onlyMux() {
        require(muxes[msg.sender], "Caller is not a mux");
        _;
    }

    // Adds a new mux to the authorized list
    function addMux(address mux) external onlyOwner {
        require(mux != address(0), "Invalid mux address");
        require(!muxes[mux], "Mux already exists");
        muxes[mux] = true;
        emit MuxAdded(mux);
    }

    // Removes a mux from the authorized list
    function removeMux(address mux) external onlyOwner {
        require(muxes[mux], "Mux does not exist");
        muxes[mux] = false;
        emit MuxRemoved(mux);
    }

    // View function to return all authorized muxes
    function getMuxesView() external view returns (address[] memory muxList) {
        uint256 count = 0;
        for (uint256 i = 0; i < 1000; i++) {
            if (muxes[address(uint160(i))]) {
                count++;
            }
        }
        muxList = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < 1000; i++) {
            if (muxes[address(uint160(i))]) {
                muxList[index] = address(uint160(i));
                index++;
            }
        }
    }

    // Internal helper to update core position data
    function updateCoreParams(uint256 positionId, CoreParams memory params) internal {
        if (params.positionId == 0 || params.listingAddress == address(0) || params.makerAddress == address(0)) {
            emit UpdateFailed(positionId, "Invalid core parameters");
            return;
        }
        positionCore1[positionId] = PositionCore1({
            positionId: params.positionId,
            listingAddress: params.listingAddress,
            makerAddress: params.makerAddress,
            positionType: params.positionType
        });
        if (params.status2 != type(uint8).max) {
            positionCore2[positionId] = PositionCore2({
                status1: params.status1,
                status2: params.status2
            });
        }
    }

    // Internal helper to update price parameters
    function updatePriceParams(uint256 positionId, PriceParams memory params) internal {
        if (params.minEntryPrice == 0 && params.maxEntryPrice == 0 && params.minPrice == 0 && params.priceAtEntry == 0 && params.liquidationPrice == 0) {
            emit UpdateFailed(positionId, "Invalid price parameters");
            return;
        }
        priceParams1[positionId] = PriceParams1({
            minEntryPrice: params.minEntryPrice,
            maxEntryPrice: params.maxEntryPrice,
            minPrice: params.minPrice,
            priceAtEntry: params.priceAtEntry,
            leverage: params.leverage
        });
        priceParams2[positionId] = PriceParams2({
            liquidationPrice: params.liquidationPrice
        });
    }

    // Internal helper to update margin parameters
    function updateMarginParams(uint256 positionId, MarginParams memory params) internal {
        if (params.initialMargin == 0 && params.taxedMargin == 0 && params.excessMargin == 0 && params.fee == 0 && params.initialLoan == 0) {
            emit UpdateFailed(positionId, "Invalid margin parameters");
            return;
        }
        marginParams1[positionId] = MarginParams1({
            initialMargin: params.initialMargin,
            taxedMargin: params.taxedMargin,
            excessMargin: params.excessMargin,
            fee: params.fee
        });
        marginParams2[positionId] = MarginParams2({
            initialLoan: params.initialLoan
        });
    }

    // Internal helper to update exit parameters and open interest
    function updateExitAndInterest(uint256 positionId, ExitAndInterestParams memory params) internal {
        if (params.stopLossPrice == 0 && params.takeProfitPrice == 0 && params.exitPrice == 0 && params.leverageAmount == 0 && params.timestamp == 0) {
            emit UpdateFailed(positionId, "Invalid exit or interest parameters");
            return;
        }
        exitParams[positionId] = ExitParams({
            stopLossPrice: params.stopLossPrice,
            takeProfitPrice: params.takeProfitPrice,
            exitPrice: params.exitPrice
        });
        openInterest[positionId] = OpenInterest({
            leverageAmount: params.leverageAmount,
            timestamp: params.timestamp
        });
    }

    // Internal helper to update maker margin and position token
    function updateMakerMargin(uint256 positionId, MakerMarginParams memory params) internal {
        if (params.token == address(0) && params.maker == address(0) && params.marginToken == address(0) && params.marginAmount == 0) {
            emit UpdateFailed(positionId, "Invalid maker margin parameters");
            return;
        }
        if (params.token != address(0)) {
            positionToken[positionId] = params.token;
        }
        if (params.maker != address(0) && params.marginToken != address(0) && params.marginAmount != 0) {
            makerTokenMargin[params.maker][params.marginToken] = params.marginAmount;
            bool tokenExists = false;
            for (uint256 i = 0; i < makerMarginTokens[params.maker].length; i++) {
                if (makerMarginTokens[params.maker][i] == params.marginToken) {
                    tokenExists = true;
                    break;
                }
            }
            if (!tokenExists) {
                makerMarginTokens[params.maker].push(params.marginToken);
            }
        }
    }

    // Internal helper to update position arrays and count
    function updatePositionArrays(uint256 positionId, PositionArrayParams memory params) internal {
        if (params.listingAddress == address(0)) {
            emit UpdateFailed(positionId, "Invalid listing address in position arrays");
            return;
        }
        if (params.addToPending) {
            pendingPositions[params.listingAddress][params.positionType].push(positionId);
        }
        if (params.addToActive) {
            positionsByType[params.positionType].push(positionId);
        }
        if (positionId > positionCount) {
            positionCount = positionId;
        }
    }

    // Updates position data with validation
    function CSUpdate(
        uint256 positionId,
        CoreParams memory coreParams,
        PriceParams memory priceParams,
        MarginParams memory marginParams,
        ExitAndInterestParams memory exitAndInterestParams,
        MakerMarginParams memory makerMarginParams,
        PositionArrayParams memory positionArrayParams,
        HistoricalInterestParams memory historicalInterestParams
    ) external onlyMux {
        if (positionId == 0) {
            emit UpdateFailed(positionId, "Invalid position ID");
            return;
        }
        try this.CSUpdateInternal(
            positionId,
            coreParams,
            priceParams,
            marginParams,
            exitAndInterestParams,
            makerMarginParams,
            positionArrayParams,
            historicalInterestParams
        ) {
        } catch Error(string memory reason) {
            emit UpdateFailed(positionId, reason);
        } catch {
            emit UpdateFailed(positionId, "Unknown error during update");
        }
    }

    // Internal function to handle CSUpdate logic
    function CSUpdateInternal(
        uint256 positionId,
        CoreParams memory coreParams,
        PriceParams memory priceParams,
        MarginParams memory marginParams,
        ExitAndInterestParams memory exitAndInterestParams,
        MakerMarginParams memory makerMarginParams,
        PositionArrayParams memory positionArrayParams,
        HistoricalInterestParams memory historicalInterestParams
    ) external {
        require(msg.sender == address(this), "Only callable by this contract");
        uint256 height = block.number;
        if (historicalInterestParams.longIO != 0) longIOByHeight[height] = historicalInterestParams.longIO;
        if (historicalInterestParams.shortIO != 0) shortIOByHeight[height] = historicalInterestParams.shortIO;
        if (historicalInterestParams.timestamp != 0) historicalInterestTimestamps[height] = historicalInterestParams.timestamp;

        updateCoreParams(positionId, coreParams);
        updatePriceParams(positionId, priceParams);
        updateMarginParams(positionId, marginParams);
        updateExitAndInterest(positionId, exitAndInterestParams);
        updateMakerMargin(positionId, makerMarginParams);
        updatePositionArrays(positionId, positionArrayParams);
    }

    // Removes position from pending or active arrays
    function removePositionIndex(uint256 positionId, uint8 positionType, address listingAddress) external onlyMux {
        try this.removePositionIndexInternal(positionId, positionType, listingAddress) {
        } catch Error(string memory reason) {
            emit RemovalFailed(positionId, reason);
        } catch {
            emit RemovalFailed(positionId, "Unknown error during position removal");
        }
    }

    // Internal function to handle position removal
    function removePositionIndexInternal(uint256 positionId, uint8 positionType, address listingAddress) external {
        require(msg.sender == address(this), "Only callable by this contract");
        uint256[] storage pending = pendingPositions[listingAddress][positionType];
        bool found = false;
        for (uint256 i = 0; i < pending.length; i++) {
            if (pending[i] == positionId) {
                pending[i] = pending[pending.length - 1];
                pending.pop();
                found = true;
                break;
            }
        }
        if (!found) {
            uint256[] storage active = positionsByType[positionType];
            for (uint256 i = 0; i < active.length; i++) {
                if (active[i] == positionId) {
                    active[i] = active[active.length - 1];
                    active.pop();
                    found = true;
                    break;
                }
            }
        }
        if (!found) {
            revert("Position not found in arrays");
        }
    }

    // Removes token from maker's margin token list
    function removeToken(address maker, address token) external onlyMux {
        try this.removeTokenInternal(maker, token) {
        } catch Error(string memory reason) {
            emit RemovalFailed(0, reason);
        } catch {
            emit RemovalFailed(0, "Unknown error during token removal");
        }
    }

    // Internal function to handle token removal
    function removeTokenInternal(address maker, address token) external {
        require(msg.sender == address(this), "Only callable by this contract");
        address[] storage tokens = makerMarginTokens[maker];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                return;
            }
        }
        revert("Token not found in maker's list");
    }

    // View function to retrieve position details
    function positionByIndex(uint256 positionId) external view returns (
        PositionCore1 memory core1,
        PositionCore2 memory core2,
        PriceParams1 memory price1,
        PriceParams2 memory price2,
        MarginParams1 memory margin1,
        MarginParams2 memory margin2,
        ExitParams memory exit,
        address token
    ) {
        require(positionCore1[positionId].positionId == positionId, "Invalid position");
        core1 = positionCore1[positionId];
        core2 = positionCore2[positionId];
        price1 = priceParams1[positionId];
        price2 = priceParams2[positionId];
        margin1 = marginParams1[positionId];
        margin2 = marginParams2[positionId];
        exit = exitParams[positionId];
        token = positionToken[positionId];
    }

    // View function to retrieve positions by type
    function PositionsByTypeView(
        uint8 positionType,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (uint256[] memory positionIds) {
        require(positionType <= 1, "Invalid position type");
        uint256 length = positionsByType[positionType].length;
        uint256 count = length > startIndex + maxIterations ? maxIterations : length - startIndex;
        positionIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            positionIds[i] = positionsByType[positionType][startIndex + i];
        }
    }

    // View function to retrieve positions by maker address
    function PositionsByAddressView(
        address maker,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (uint256[] memory positionIds) {
        uint256 count = 0;
        uint256[] memory tempIds = new uint256[](positionCount);
        for (uint256 i = startIndex; i < positionCount && count < maxIterations; i++) {
            uint256 positionId = i + 1;
            if (positionCore1[positionId].makerAddress == maker && !positionCore2[positionId].status1) {
                tempIds[count] = positionId;
                count++;
            }
        }
        positionIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            positionIds[i] = tempIds[i];
        }
    }

    // View function to retrieve total active positions
    function TotalActivePositionsView() external view returns (uint256 count) {
        for (uint256 i = 1; i <= positionCount; i++) {
            if (positionCore1[i].positionId == i && positionCore2[i].status1 && positionCore2[i].status2 == 0) {
                count++;
            }
        }
    }

    // View function to query historical interest
    function queryInterest(uint256 startIndex, uint256 maxIterations) external view returns (
        uint256[] memory longIO,
        uint256[] memory shortIO,
        uint256[] memory timestamps
    ) {
        uint256 count = positionCount > startIndex + maxIterations ? maxIterations : positionCount - startIndex;
        longIO = new uint256[](count);
        shortIO = new uint256[](count);
        timestamps = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            uint256 height = startIndex + i;
            longIO[i] = longIOByHeight[height];
            shortIO[i] = shortIOByHeight[height];
            timestamps[i] = historicalInterestTimestamps[height];
        }
    }

    // View function to retrieve maker margin details
    function makerMarginIndex(
        address maker,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (address[] memory tokens, uint256[] memory margins) {
        address[] storage makerTokens = makerMarginTokens[maker];
        uint256 length = makerTokens.length > startIndex + maxIterations ? maxIterations : makerTokens.length - startIndex;
        tokens = new address[](length);
        margins = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            tokens[i] = makerTokens[startIndex + i];
            margins[i] = makerTokenMargin[maker][tokens[i]];
        }
    }

    // View function to assess position health
    function PositionHealthView(uint256 positionId) external view returns (
        uint256 marginRatio,
        uint256 distanceToLiquidation,
        uint256 estimatedProfitLoss
    ) {
        require(positionCore1[positionId].positionId == positionId, "Invalid position");
        PositionCore1 memory core1 = positionCore1[positionId];
        MarginParams1 memory margin1 = marginParams1[positionId];
        PriceParams1 memory price1 = priceParams1[positionId];
        PriceParams2 memory price2 = priceParams2[positionId];
        address token = core1.positionType == 0 ? ISSListing(core1.listingAddress).tokenB() : ISSListing(core1.listingAddress).tokenA();
        uint256 currentPrice = normalizePrice(token, ISSListing(core1.listingAddress).prices(0));
        require(currentPrice > 0, "Invalid price");

        address marginToken = core1.positionType == 0 ? ISSListing(core1.listingAddress).tokenA() : ISSListing(core1.listingAddress).tokenB();
        uint256 totalMargin = makerTokenMargin[core1.makerAddress][marginToken];
        marginRatio = totalMargin * DECIMAL_PRECISION / (margin1.initialMargin * uint256(price1.leverage));

        if (core1.positionType == 0) {
            distanceToLiquidation = currentPrice > price2.liquidationPrice ? currentPrice - price2.liquidationPrice : 0;
            estimatedProfitLoss = (margin1.taxedMargin + totalMargin + uint256(price1.leverage) * margin1.initialMargin) / currentPrice - marginParams2[positionId].initialLoan;
        } else {
            distanceToLiquidation = currentPrice < price2.liquidationPrice ? price2.liquidationPrice - currentPrice : 0;
            estimatedProfitLoss = (price1.priceAtEntry - currentPrice) * margin1.initialMargin * uint256(price1.leverage) + (margin1.taxedMargin + totalMargin) * currentPrice / DECIMAL_PRECISION;
        }
    }

    // View function to aggregate margin by token
    function AggregateMarginByToken(
        address tokenA,
        address tokenB,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (address[] memory makers, uint256[] memory margins) {
        address listingAddress = ISSAgent(agentAddress).getListing(tokenA, tokenB);
        require(listingAddress != address(0), "Invalid listing");
        address token = ISSListing(listingAddress).tokenB();
        uint256 length = positionsByType[0].length + positionsByType[1].length;
        uint256 count = length > startIndex + maxIterations ? maxIterations : length - startIndex;
        address[] memory tempMakers = new address[](count);
        uint256[] memory tempMargins = new uint256[](count);
        uint256 index = 0;

        for (uint8 positionType = 0; positionType <= 1 && index < count; positionType++) {
            uint256[] storage positionIds = positionsByType[positionType];
            for (uint256 i = 0; i < positionIds.length && index < count; i++) {
                uint256 positionId = positionIds[i];
                address maker = positionCore1[positionId].makerAddress;
                if (maker != address(0) && makerTokenMargin[maker][token] > 0) {
                    tempMakers[index] = maker;
                    tempMargins[index] = makerTokenMargin[maker][token];
                    index++;
                }
            }
        }

        makers = new address[](index);
        margins = new uint256[](index);
        for (uint256 i = 0; i < index; i++) {
            makers[i] = tempMakers[i];
            margins[i] = tempMargins[i];
        }
    }

    // View function to retrieve open interest trend
    function OpenInterestTrend(
        address listingAddress,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (uint256[] memory leverageAmounts, uint256[] memory timestamps) {
        uint256 count = 0;
        uint256[] memory tempAmounts = new uint256[](positionCount);
        uint256[] memory tempTimestamps = new uint256[](positionCount);

        for (uint256 i = 0; i < positionCount && count < maxIterations; i++) {
            uint256 positionId = i + 1;
            if (positionCore1[positionId].listingAddress == listingAddress && positionCore2[positionId].status2 == 0) {
                tempAmounts[count] = openInterest[positionId].leverageAmount;
                tempTimestamps[count] = openInterest[positionId].timestamp;
                count++;
            }
        }

        leverageAmounts = new uint256[](count);
        timestamps = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            leverageAmounts[i] = tempAmounts[i];
            timestamps[i] = tempTimestamps[i];
        }
    }

    // View function to count positions at liquidation risk
    function LiquidationRiskCount(address listingAddress, uint256 maxIterations) external view returns (uint256 count) {
        uint256 processed = 0;
        for (uint256 i = 0; i < positionCount && processed < maxIterations; i++) {
            uint256 positionId = i + 1;
            PositionCore1 memory core1 = positionCore1[positionId];
            PositionCore2 memory core2 = positionCore2[positionId];
            if (core1.listingAddress != listingAddress || core2.status2 != 0) continue;
            address token = core1.positionType == 0 ? ISSListing(listingAddress).tokenB() : ISSListing(listingAddress).tokenA();
            uint256 currentPrice = normalizePrice(token, ISSListing(listingAddress).prices(0));
            uint256 liquidationPrice = priceParams2[positionId].liquidationPrice;
            uint256 threshold = liquidationPrice * 5 / 100;

            if (core1.positionType == 0) {
                if (currentPrice <= liquidationPrice + threshold) count++;
            } else {
                if (currentPrice >= liquidationPrice - threshold) count++;
            }
            processed++;
        }
    }

    // Normalizes price based on token decimals
    function normalizePrice(address token, uint256 price) internal view returns (uint256 normalizedPrice) {
        uint8 decimals = IERC20(token).decimals();
        if (decimals < 18) return price * (10 ** (18 - decimals));
        if (decimals > 18) return price / (10 ** (decimals - 18));
        return price;
    }

    // Sets agent address
    function setAgent(address newAgentAddress) external onlyOwner {
        require(newAgentAddress != address(0), "Invalid agent address");
        agentAddress = newAgentAddress;
    }
}