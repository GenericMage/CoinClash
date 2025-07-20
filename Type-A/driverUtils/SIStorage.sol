/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-07-20: Fixed DeclarationError in setAgent by correcting typo from 'new personally' to 'newAgentAddress'; renamed SIUpdate parameters priceParams to priceData and marginParams to marginData to avoid shadowing state variables; version updated to 0.0.3.
 - 2025-07-20: Fixed TypeError by renaming parameters in parsePriceParams and parseMarginParams to avoid shadowing state variables; version updated to 0.0.2.
 - 2025-07-20: Created SIStorage contract by extracting position storage and view functions from SSIsolatedDriver.sol, SSDPositionPartial.sol, and SSDUtilityPartial.sol, adapting CSStorage.sol's structure. Added SIUpdate function for direct position updates by muxes. Version set to 0.0.1.
*/

pragma solidity ^0.8.2;

import "../imports/SafeERC20.sol";
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
    using SafeERC20 for IERC20;

    uint256 public constant DECIMAL_PRECISION = 1e18;
    address public agent;

    // Mapping to track authorized mux contracts
    mapping(address => bool) public muxes;

    // Position storage structures from SSDUtilityPartial
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

    // Modifier to restrict functions to authorized muxes
    modifier onlyMux() {
        require(muxes[msg.sender], "Caller is not a mux");
        _;
    }

    // Constructor
    constructor() {
        historicalInterestHeight = 1;
        positionCount = 1;
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
    function getMuxesView() external view returns (address[] memory) {
        uint256 count = 0;
        // Count authorized muxes (limit to 1000 for gas safety)
        for (uint256 i = 0; i < 1000; i++) {
            if (muxes[address(uint160(i))]) {
                count++;
            }
        }
        address[] memory result = new address[](count);
        uint256 index = 0;
        // Populate result array
        for (uint256 i = 0; i < 1000; i++) {
            if (muxes[address(uint160(i))]) {
                result[index] = address(uint160(i));
                index++;
            }
        }
        return result;
    }

    // Internal helper to parse and update core position data
    function parseCoreParams(uint256 positionId, string memory coreData) internal {
        // Parse coreData: "makerAddress-listingAddress-positionId-positionType-status1-status2"
        bytes memory params = bytes(coreData);
        if (params.length == 0) return;

        (address makerAddress, address listingAddress, uint256 corePositionId, uint8 positionType, bool status1, uint8 status2) = 
            abi.decode(abi.encodePacked(params), (address, address, uint256, uint8, bool, uint8));

        if (corePositionId != 0) {
            positionCoreBase[positionId] = PositionCoreBase({
                makerAddress: makerAddress,
                listingAddress: listingAddress,
                positionId: corePositionId,
                positionType: positionType
            });
        }
        if (status2 != type(uint8).max) {
            positionCoreStatus[positionId] = PositionCoreStatus({
                status1: status1,
                status2: status2
            });
        }
    }

    // Internal helper to parse and update price parameters
    function parsePriceParams(uint256 positionId, string memory priceData) internal {
        // Parse priceData: "priceMin-priceMax-priceAtEntry-priceClose"
        bytes memory params = bytes(priceData);
        if (params.length == 0) return;

        (uint256 priceMin, uint256 priceMax, uint256 priceAtEntry, uint256 priceClose) = 
            abi.decode(abi.encodePacked(params), (uint256, uint256, uint256, uint256));

        if (priceMin != 0 || priceMax != 0 || priceAtEntry != 0) {
            priceParams[positionId] = PriceParams({
                priceMin: priceMin,
                priceMax: priceMax,
                priceAtEntry: priceAtEntry,
                priceClose: priceClose
            });
        }
    }

    // Internal helper to parse and update margin parameters
    function parseMarginParams(uint256 positionId, string memory marginData) internal {
        // Parse marginData: "marginInitial-marginTaxed-marginExcess"
        bytes memory params = bytes(marginData);
        if (params.length == 0) return;

        (uint256 marginInitial, uint256 marginTaxed, uint256 marginExcess) = 
            abi.decode(abi.encodePacked(params), (uint256, uint256, uint256));

        if (marginInitial != 0 || marginTaxed != 0 || marginExcess != 0) {
            marginParams[positionId] = MarginParams({
                marginInitial: marginInitial,
                marginTaxed: marginTaxed,
                marginExcess: marginExcess
            });
        }
    }

    // Internal helper to parse and update leverage and risk parameters
    function parseLeverageAndRiskParams(uint256 positionId, string memory leverageAndRiskData) internal {
        // Parse leverageAndRiskData: "leverageVal-leverageAmount-loanInitial-priceLiquidation-priceStopLoss-priceTakeProfit"
        bytes memory params = bytes(leverageAndRiskData);
        if (params.length == 0) return;

        (uint8 leverageVal, uint256 leverageAmount, uint256 loanInitial, uint256 priceLiquidation, uint256 priceStopLoss, uint256 priceTakeProfit) = 
            abi.decode(abi.encodePacked(params), (uint8, uint256, uint256, uint256, uint256, uint256));

        if (leverageVal != 0 || leverageAmount != 0 || loanInitial != 0) {
            leverageParams[positionId] = LeverageParams({
                leverageVal: leverageVal,
                leverageAmount: leverageAmount,
                loanInitial: loanInitial
            });
        }
        if (priceLiquidation != 0 || priceStopLoss != 0 || priceTakeProfit != 0) {
            riskParams[positionId] = RiskParams({
                priceLiquidation: priceLiquidation,
                priceStopLoss: priceStopLoss,
                priceTakeProfit: priceTakeProfit
            });
        }
    }

    // Internal helper to parse and update position token and interest
    function parseTokenAndInterest(uint256 positionId, string memory tokenAndInterestData) internal {
        // Parse tokenAndInterestData: "token-longIO-shortIO-timestamp"
        bytes memory params = bytes(tokenAndInterestData);
        if (params.length == 0) return;

        (address token, uint256 longIO, uint256 shortIO, uint256 timestamp) = 
            abi.decode(abi.encodePacked(params), (address, uint256, uint256, uint256));

        if (token != address(0)) {
            positionToken[positionId] = token;
        }
        if (longIO != 0 || shortIO != 0 || timestamp != 0) {
            uint256 height = historicalInterestHeight;
            if (longIO != 0) longIOByHeight[height] = longIO;
            if (shortIO != 0) shortIOByHeight[height] = shortIO;
            if (timestamp != 0) historicalInterestTimestamps[height] = timestamp;
            historicalInterestHeight++;
        }
    }

    // Internal helper to parse and update position arrays
    function parsePositionArrays(uint256 positionId, string memory positionArrayData) internal {
        // Parse positionArrayData: "listingAddress-positionType-addToPending-addToActive"
        bytes memory params = bytes(positionArrayData);
        if (params.length == 0) return;

        (address listingAddress, uint8 positionType, bool addToPending, bool addToActive) = 
            abi.decode(abi.encodePacked(params), (address, uint8, bool, bool));

        if (addToPending && listingAddress != address(0)) {
            pendingPositions[listingAddress][positionType].push(positionId);
        }
        if (addToActive) {
            positionsByType[positionType].push(positionId);
        }
        if (positionId > positionCount) {
            positionCount = positionId;
        }
    }

    // Updates position data directly without validation
    function SIUpdate(
        uint256 positionId,
        string memory coreParams,
        string memory priceData,
        string memory marginData,
        string memory leverageAndRiskParams,
        string memory tokenAndInterestParams,
        string memory positionArrayParams
    ) external onlyMux {
        // Call internal helpers to parse and update state
        parseCoreParams(positionId, coreParams);
        parsePriceParams(positionId, priceData);
        parseMarginParams(positionId, marginData);
        parseLeverageAndRiskParams(positionId, leverageAndRiskParams);
        parseTokenAndInterest(positionId, tokenAndInterestParams);
        parsePositionArrays(positionId, positionArrayParams);
    }

    // Removes position from pending or active arrays
    function removePositionIndex(uint256 positionId, uint8 positionType, address listingAddress) external onlyMux {
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
        require(positionCoreBase[positionId].positionId == positionId, "Invalid position");
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
        require(positionCoreBase[positionId].positionId == positionId, "Invalid position");
        PositionCoreBase memory coreBase = positionCoreBase[positionId];
        MarginParams memory margin = marginParams[positionId];
        PriceParams memory price = priceParams[positionId];
        LeverageParams memory leverage = leverageParams[positionId];
        RiskParams memory risk = riskParams[positionId];
        address token = coreBase.positionType == 0 ? ISSListing(coreBase.listingAddress).tokenB() : ISSListing(coreBase.listingAddress).tokenA();
        uint256 currentPrice = normalizePrice(token, ISSListing(coreBase.listingAddress).prices(coreBase.listingAddress));
        require(currentPrice > 0, "Invalid price");

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
        address listingAddress = ISSAgent(agent).getListing(tokenA, tokenB);
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
        uint256 count = 0;
        uint256[] memory tempAmounts = new uint256[](positionCount);
        uint256[] memory tempTimestamps = new uint256[](positionCount);

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
        uint256 processed = 0;
        for (uint256 i = 0; i < positionCount && processed < maxIterations; i++) {
            uint256 positionId = i + 1;
            PositionCoreBase memory coreBase = positionCoreBase[positionId];
            PositionCoreStatus memory coreStatus = positionCoreStatus[positionId];
            if (coreBase.listingAddress != listingAddress || coreStatus.status2 != 0) continue;
            address token = coreBase.positionType == 0 ? ISSListing(listingAddress).tokenB() : ISSListing(listingAddress).tokenA();
            uint256 currentPrice = normalizePrice(token, ISSListing(listingAddress).prices(token));
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
    function normalizePrice(address token, uint256 price) internal view returns (uint256) {
        uint8 decimals = IERC20(token).decimals();
        if (decimals < 18) return price * (10 ** (18 - decimals));
        if (decimals > 18) return price / (10 ** (decimals - 18));
        return price;
    }

    // Sets agent address
    function setAgent(address newAgentAddress) external onlyOwner {
        require(newAgentAddress != address(0), "Invalid agent address");
        agent = newAgentAddress;
    }
}