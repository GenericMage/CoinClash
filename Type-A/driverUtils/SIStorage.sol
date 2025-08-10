/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-08-07: Replaced hyphen-delimited strings with arrays in SIUpdate and parsing functions; added detailed error messages; added error logging events and restructured for early error catching; removed SafeERC20, imported IERC20; version updated to 0.0.4.
 - 2025-07-20: Fixed DeclarationError in setAgent; renamed SIUpdate parameters; version updated to 0.0.3.
 - 2025-07-20: Fixed TypeError in parsePriceParams and parseMarginParams; version updated to 0.0.2.
 - 2025-07-20: Created SIStorage contract from SSIsolatedDriver.sol, SSDPositionPartial.sol, SSDUtilityPartial.sol; version set to 0.0.1.
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
    function prices(address) external view returns (uint256);
    function volumeBalances(address) external view returns (uint256 xBalance, uint256 yBalance);
    function liquidityAddressView(address) external view returns (address);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function ssUpdate(address caller, PayoutUpdate[] calldata updates) external;
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
    struct PayoutUpdate {
        uint8 payoutType;
        address recipient;
        uint256 required;
    }
    struct UpdateType {
        uint8 updateType;
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
    }
    function update(address caller, UpdateType[] calldata updates) external;
}

interface ISSLiquidityTemplate {
    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees);
    function addFees(address caller, bool isX, uint256 fee) external;
}

contract SIStorage is Ownable {
    uint256 public constant DECIMAL_PRECISION = 1e18;
    address public agent;

    // Mapping to track authorized mux contracts
    mapping(address => bool) public muxes;

    // Position storage structures
    struct PositionCoreBase {
        address makerAddress;
        address listingAddress;
        uint256 positionId;
        uint8 positionType; // 0: Long, 1: Short
    }

    struct PositionCoreStatus {
        bool status1; // false: pending, true: executable
        uint8 status2; // 0: open, 1: closed, 2: cancelled
    }

    struct PriceParams {
        uint256 priceMin;
        uint256 priceMax;
        uint256 priceAtEntry;
        uint256 priceClose;
    }

    struct MarginParams {
        uint256 marginInitial;
        uint256 marginTaxed;
        uint256 marginExcess;
    }

    struct LeverageParams {
        uint8 leverageVal;
        uint256 leverageAmount;
        uint256 loanInitial;
    }

    struct RiskParams {
        uint256 priceLiquidation;
        uint256 priceStopLoss;
        uint256 priceTakeProfit;
    }

    struct CoreParams {
        address makerAddress;
        address listingAddress;
        uint256 corePositionId;
        uint8 positionType;
        bool status1;
        uint8 status2;
    }

    struct TokenAndInterestParams {
        address token;
        uint256 longIO;
        uint256 shortIO;
        uint256 timestamp;
    }

    struct PositionArrayParams {
        address listingAddress;
        uint8 positionType;
        bool addToPending;
        bool addToActive;
    }

    // Storage mappings
    mapping(uint256 => PositionCoreBase) public positionCoreBase;
    mapping(uint256 => PositionCoreStatus) public positionCoreStatus;
    mapping(uint256 => PriceParams) public priceParams;
    mapping(uint256 => MarginParams) public marginParams;
    mapping(uint256 => LeverageParams) public leverageParams;
    mapping(uint256 => RiskParams) public riskParams;
    mapping(address => mapping(uint8 => uint256[])) public pendingPositions;
    mapping(uint8 => uint256[]) public positionsByType;
    mapping(uint256 => address) public positionToken;
    mapping(uint256 => uint256) public longIOByHeight;
    mapping(uint256 => uint256) public shortIOByHeight;
    mapping(uint256 => uint256) public historicalInterestTimestamps;
    uint256 public positionCount;
    uint256 public historicalInterestHeight;

    // Events
    event PositionClosed(uint256 indexed positionId, address indexed maker, uint256 payout);
    event MuxAdded(address indexed mux);
    event MuxRemoved(address indexed mux);
    event ErrorLogged(string reason, address caller, uint256 positionId);

    // Modifier to restrict functions to authorized muxes
    modifier onlyMux() {
        require(muxes[msg.sender], "Caller is not an authorized mux");
        _;
    }

    // Constructor
    constructor() {
        historicalInterestHeight = 1;
        positionCount = 1;
    }

    // Adds a new mux to the authorized list
    function addMux(address mux) external onlyOwner {
        if (mux == address(0)) {
            emit ErrorLogged("Attempted to add invalid mux address", msg.sender, 0);
            revert("Invalid mux address: zero address");
        }
        if (muxes[mux]) {
            emit ErrorLogged("Attempted to add existing mux", msg.sender, 0);
            revert("Mux already authorized");
        }
        muxes[mux] = true;
        emit MuxAdded(mux);
    }

    // Removes a mux from the authorized list
    function removeMux(address mux) external onlyOwner {
        if (!muxes[mux]) {
            emit ErrorLogged("Attempted to remove non-existent mux", msg.sender, 0);
            revert("Mux not authorized");
        }
        muxes[mux] = false;
        emit MuxRemoved(mux);
    }

    // View function to return all authorized muxes
    function getMuxesView() external view returns (address[] memory muxList) {
        uint256 count = 0;
        uint256 maxIterations = 1000; // Gas safety limit
        for (uint256 i = 0; i < maxIterations; i++) {
            if (muxes[address(uint160(i))]) {
                count++;
            }
        }
        muxList = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < maxIterations && index < count; i++) {
            address muxAddr = address(uint160(i));
            if (muxes[muxAddr]) {
                muxList[index] = muxAddr;
                index++;
            }
        }
        return muxList;
    }

    // Internal helper to parse and update core position data
    function parseCoreParams(uint256 positionId, CoreParams memory coreData) internal {
        if (coreData.corePositionId != 0) {
            if (coreData.makerAddress == address(0) || coreData.listingAddress == address(0)) {
                emit ErrorLogged("Invalid core params: zero address", msg.sender, positionId);
                revert("Core params: invalid maker or listing address");
            }
            positionCoreBase[positionId] = PositionCoreBase({
                makerAddress: coreData.makerAddress,
                listingAddress: coreData.listingAddress,
                positionId: coreData.corePositionId,
                positionType: coreData.positionType
            });
        }
        if (coreData.status2 != type(uint8).max) {
            positionCoreStatus[positionId] = PositionCoreStatus({
                status1: coreData.status1,
                status2: coreData.status2
            });
        }
    }

    // Internal helper to parse and update price parameters
    function parsePriceParams(uint256 positionId, PriceParams memory priceData) internal {
        if (priceData.priceMin != 0 || priceData.priceMax != 0 || priceData.priceAtEntry != 0) {
            priceParams[positionId] = priceData;
        }
    }

    // Internal helper to parse and update margin parameters
    function parseMarginParams(uint256 positionId, MarginParams memory marginData) internal {
        if (marginData.marginInitial != 0 || marginData.marginTaxed != 0 || marginData.marginExcess != 0) {
            marginParams[positionId] = marginData;
        }
    }

    // Internal helper to parse and update leverage and risk parameters
    function parseLeverageAndRiskParams(uint256 positionId, LeverageParams memory leverageData, RiskParams memory riskData) internal {
        if (leverageData.leverageVal != 0 || leverageData.leverageAmount != 0 || leverageData.loanInitial != 0) {
            leverageParams[positionId] = leverageData;
        }
        if (riskData.priceLiquidation != 0 || riskData.priceStopLoss != 0 || riskData.priceTakeProfit != 0) {
            riskParams[positionId] = riskData;
        }
    }

    // Internal helper to parse and update position token and interest
    function parseTokenAndInterest(uint256 positionId, TokenAndInterestParams memory tokenData) internal {
        if (tokenData.token != address(0)) {
            positionToken[positionId] = tokenData.token;
        }
        if (tokenData.longIO != 0 || tokenData.shortIO != 0 || tokenData.timestamp != 0) {
            uint256 height = historicalInterestHeight;
            if (tokenData.longIO != 0) longIOByHeight[height] = tokenData.longIO;
            if (tokenData.shortIO != 0) shortIOByHeight[height] = tokenData.shortIO;
            if (tokenData.timestamp != 0) historicalInterestTimestamps[height] = tokenData.timestamp;
            historicalInterestHeight++;
        }
    }

    // Internal helper to parse and update position arrays
    function parsePositionArrays(uint256 positionId, PositionArrayParams memory arrayData) internal {
        if (arrayData.addToPending && arrayData.listingAddress != address(0)) {
            pendingPositions[arrayData.listingAddress][arrayData.positionType].push(positionId);
        }
        if (arrayData.addToActive) {
            positionsByType[arrayData.positionType].push(positionId);
        }
        if (positionId > positionCount) {
            positionCount = positionId;
        }
    }

    // Updates position data directly without validation
    function SIUpdate(
        uint256 positionId,
        CoreParams memory coreData,
        PriceParams memory priceData,
        MarginParams memory marginData,
        LeverageParams memory leverageData,
        RiskParams memory riskData,
        TokenAndInterestParams memory tokenData,
        PositionArrayParams memory arrayData
    ) external onlyMux {
        if (positionId == 0) {
            emit ErrorLogged("Invalid position ID in SIUpdate", msg.sender, positionId);
            revert("SIUpdate: position ID cannot be zero");
        }
        // Early validation for critical fields
        if (coreData.corePositionId != 0 && (coreData.makerAddress == address(0) || coreData.listingAddress == address(0))) {
            emit ErrorLogged("Invalid core data in SIUpdate", msg.sender, positionId);
            revert("SIUpdate: invalid maker or listing address");
        }
        // Call internal helpers
        parseCoreParams(positionId, coreData);
        parsePriceParams(positionId, priceData);
        parseMarginParams(positionId, marginData);
        parseLeverageAndRiskParams(positionId, leverageData, riskData);
        parseTokenAndInterest(positionId, tokenData);
        parsePositionArrays(positionId, arrayData);
    }

    // Removes position from pending or active arrays
    function removePositionIndex(uint256 positionId, uint8 positionType, address listingAddress) external onlyMux {
        if (positionId == 0) {
            emit ErrorLogged("Invalid position ID in removePositionIndex", msg.sender, positionId);
            revert("removePositionIndex: position ID cannot be zero");
        }
        if (listingAddress == address(0)) {
            emit ErrorLogged("Invalid listing address in removePositionIndex", msg.sender, positionId);
            revert("removePositionIndex: listing address cannot be zero");
        }
        uint256[] storage pending = pendingPositions[listingAddress][positionType];
        for (uint256 i = 0; i < pending.length; i++) {
            if (pending[i] == positionId) {
                pending[i] = pending[pending.length - 1];
                pending.pop();
                break;
            }
        }
        uint256[] storage active = positionsByType[positionType];
        for (uint256 i = 0; i < active.length; i++) {
            if (active[i] == positionId) {
                active[i] = active[active.length - 1];
                active.pop();
                break;
            }
        }
    }

    // View function to retrieve position details
    function positionByIndex(uint256 positionId) external view returns (
        PositionCoreBase memory coreBase,
        PositionCoreStatus memory coreStatus,
        PriceParams memory price,
        MarginParams memory margin,
        LeverageParams memory leverage,
        RiskParams memory risk,
        address token
    ) {
        if (positionCoreBase[positionId].positionId != positionId) {
            revert("positionByIndex: invalid position ID");
        }
        coreBase = positionCoreBase[positionId];
        coreStatus = positionCoreStatus[positionId];
        price = priceParams[positionId];
        margin = marginParams[positionId];
        leverage = leverageParams[positionId];
        risk = riskParams[positionId];
        token = positionToken[positionId];
    }

    // View function to retrieve positions by type
    function PositionsByTypeView(
        uint8 positionType,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (uint256[] memory positionIds) {
        if (positionType > 1) {
            revert("PositionsByTypeView: invalid position type");
        }
        uint256 length = positionsByType[positionType].length;
        if (startIndex >= length) {
            return new uint256[](0);
        }
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
        if (maker == address(0)) {
            revert("PositionsByAddressView: invalid maker address");
        }
        if (startIndex >= positionCount) {
            return new uint256[](0);
        }
        uint256 count = 0;
        uint256[] memory tempIds = new uint256[](maxIterations);
        for (uint256 i = startIndex; i < positionCount && count < maxIterations; i++) {
            uint256 positionId = i + 1;
            if (positionCoreBase[positionId].makerAddress == maker && !positionCoreStatus[positionId].status1) {
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
            if (positionCoreBase[i].positionId == i && positionCoreStatus[i].status1 && positionCoreStatus[i].status2 == 0) {
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
        if (startIndex >= positionCount) {
            return (new uint256[](0), new uint256[](0), new uint256[](0));
        }
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

    // View function to assess position health
    function PositionHealthView(uint256 positionId) external view returns (
        uint256 marginRatio,
        uint256 distanceToLiquidation,
        uint256 estimatedProfitLoss
    ) {
        if (positionCoreBase[positionId].positionId != positionId) {
            revert("PositionHealthView: invalid position ID");
        }
        PositionCoreBase memory coreBase = positionCoreBase[positionId];
        MarginParams memory margin = marginParams[positionId];
        PriceParams memory price = priceParams[positionId];
        LeverageParams memory leverage = leverageParams[positionId];
        RiskParams memory risk = riskParams[positionId];
        address token = coreBase.positionType == 0 ? ISSListing(coreBase.listingAddress).tokenB() : ISSListing(coreBase.listingAddress).tokenA();
        uint256 currentPrice;
        try ISSListing(coreBase.listingAddress).prices(coreBase.listingAddress) returns (uint256 price) {
            currentPrice = normalizePrice(token, price);
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("PositionHealthView: price fetch failed - ", reason)));
        }
        if (currentPrice == 0) {
            revert("PositionHealthView: invalid price returned");
        }

        address marginToken = coreBase.positionType == 0 ? ISSListing(coreBase.listingAddress).tokenA() : ISSListing(coreBase.listingAddress).tokenB();
        uint256 totalMargin = margin.marginTaxed + margin.marginExcess;
        marginRatio = totalMargin * DECIMAL_PRECISION / (margin.marginInitial * uint256(leverage.leverageVal));

        if (coreBase.positionType == 0) {
            distanceToLiquidation = currentPrice > risk.priceLiquidation ? currentPrice - risk.priceLiquidation : 0;
            estimatedProfitLoss = (margin.marginTaxed + margin.marginExcess + uint256(leverage.leverageVal) * margin.marginInitial) / currentPrice - leverage.loanInitial;
        } else {
            distanceToLiquidation = currentPrice < risk.priceLiquidation ? risk.priceLiquidation - currentPrice : 0;
            estimatedProfitLoss = (price.priceAtEntry - currentPrice) * margin.marginInitial * uint256(leverage.leverageVal) + (margin.marginTaxed + margin.marginExcess) * currentPrice / DECIMAL_PRECISION;
        }
    }

    // View function to aggregate margin by token
    function AggregateMarginByToken(
        address tokenA,
        address tokenB,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (address[] memory makers, uint256[] memory margins) {
        address listingAddress;
        try ISSAgent(agent).getListing(tokenA, tokenB) returns (address listing) {
            listingAddress = listing;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("AggregateMarginByToken: listing fetch failed - ", reason)));
        }
        if (listingAddress == address(0)) {
            revert("AggregateMarginByToken: invalid listing address");
        }
        if (startIndex >= positionsByType[0].length + positionsByType[1].length) {
            return (new address[](0), new uint256[](0));
        }
        uint256 length = positionsByType[0].length + positionsByType[1].length;
        uint256 count = length > startIndex + maxIterations ? maxIterations : length - startIndex;
        address[] memory tempMakers = new address[](count);
        uint256[] memory tempMargins = new uint256[](count);
        uint256 index = 0;

        for (uint8 positionType = 0; positionType <= 1 && index < count; positionType++) {
            uint256[] storage positionIds = positionsByType[positionType];
            for (uint256 i = 0; i < positionIds.length && index < count; i++) {
                uint256 positionId = positionIds[i];
                address maker = positionCoreBase[positionId].makerAddress;
                if (maker != address(0) && marginParams[positionId].marginInitial > 0) {
                    tempMakers[index] = maker;
                    tempMargins[index] = marginParams[positionId].marginInitial;
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
        if (listingAddress == address(0)) {
            revert("OpenInterestTrend: invalid listing address");
        }
        if (startIndex >= positionCount) {
            return (new uint256[](0), new uint256[](0));
        }
        uint256 count = 0;
        uint256[] memory tempAmounts = new uint256[](maxIterations);
        uint256[] memory tempTimestamps = new uint256[](maxIterations);

        for (uint256 i = 0; i < positionCount && count < maxIterations; i++) {
            uint256 positionId = i + 1;
            if (positionCoreBase[positionId].listingAddress == listingAddress && positionCoreStatus[positionId].status2 == 0) {
                tempAmounts[count] = leverageParams[positionId].leverageAmount;
                tempTimestamps[count] = historicalInterestTimestamps[i];
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
        if (listingAddress == address(0)) {
            revert("LiquidationRiskCount: invalid listing address");
        }
        uint256 processed = 0;
        for (uint256 i = 0; i < positionCount && processed < maxIterations; i++) {
            uint256 positionId = i + 1;
            PositionCoreBase memory coreBase = positionCoreBase[positionId];
            PositionCoreStatus memory coreStatus = positionCoreStatus[positionId];
            if (coreBase.listingAddress != listingAddress || coreStatus.status2 != 0) continue;
            address token = coreBase.positionType == 0 ? ISSListing(listingAddress).tokenB() : ISSListing(listingAddress).tokenA();
            uint256 currentPrice;
            try ISSListing(listingAddress).prices(token) returns (uint256 price) {
                currentPrice = normalizePrice(token, price);
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("LiquidationRiskCount: price fetch failed - ", reason)));
            }
            uint256 liquidationPrice = riskParams[positionId].priceLiquidation;
            uint256 threshold = liquidationPrice * 5 / 100;

            if (coreBase.positionType == 0) {
                if (currentPrice <= liquidationPrice + threshold) count++;
            } else {
                if (currentPrice >= liquidationPrice - threshold) count++;
            }
            processed++;
        }
    }

    // Normalizes price based on token decimals
    function normalizePrice(address token, uint256 price) internal view returns (uint256 normalizedPrice) {
        if (token == address(0)) {
            revert("normalizePrice: invalid token address");
        }
        uint8 decimals;
        try IERC20(token).decimals() returns (uint8 dec) {
            decimals = dec;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("normalizePrice: decimals fetch failed - ", reason)));
        }
        if (decimals < 18) return price * (10 ** (18 - decimals));
        if (decimals > 18) return price / (10 ** (decimals - 18));
        return price;
    }

    // Sets agent address
    function setAgent(address newAgentAddress) external onlyOwner {
        if (newAgentAddress == address(0)) {
            emit ErrorLogged("Attempted to set invalid agent address", msg.sender, 0);
            revert("setAgent: invalid agent address - zero address");
        }
        agent = newAgentAddress;
    }
}