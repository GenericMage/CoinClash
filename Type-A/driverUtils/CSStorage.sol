/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-07-18: Refactored CSUpdate to use hyphen-delimited string parameters for paired data, parsed by new helper functions (parseCoreParams, parsePriceParams, parseMarginParams, parseExitAndInterest, parseMakerMargin, parsePositionArrays) to resolve stack too deep error. Version updated to 0.0.8.
 - 2025-07-18: Refactored CSUpdate function to use internal helper functions (updateCore, updatePriceParams, updateMarginParams, updateExitAndInterest, updateMakerMargin, updatePositionArrays) to resolve stack too deep error by reducing parameter count and using a call tree. Version updated to 0.0.7.
 - 2025-07-18: Reverted getListing in ISSAgent interface to function(address,address) view returns(address) from mapping to resolve TypeError for indexed expression. Updated AggregateMarginByToken to use function call. Version updated to 0.0.6.
 - 2025-07-18: Added public visibility to getListing mapping in ISSAgent interface to resolve TypeError for member access. Version updated to 0.0.5.
 - 2025-07-18: Replaced getListing function in ISSAgent interface with public mapping(address => mapping(address => address)) to match provided snippet and resolve TypeError. Version updated to 0.0.4.
 - 2025-07-18: Added ISSListing interface from CSDUtilityPartial.sol to resolve undeclared identifier errors for tokenA, tokenB, and prices functions. Version updated to 0.0.3.
 - 2025-07-18: Added ListingDetails struct to ISSAgent interface to resolve undeclared identifier error. Version updated to 0.0.2.
 - 2025-07-18: Created CSStorage contract by extracting position storage and view functions from CSDUtilityPartial.sol, SSCrossDriver.sol, and CSDExecutionPartial.sol. Added CSUpdate function for direct position updates by muxes. Version set to 0.0.1.
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
    struct PayoutUpdate {
        uint8 payoutType;
        address recipient;
        uint256 required;
    }
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
    struct UpdateType {
        uint8 updateType;
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
    }
    function update(address caller, UpdateType[] calldata updates) external;
}

contract CSStorage is Ownable {
    using SafeERC20 for IERC20;

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
    function parseCoreParams(uint256 positionId, string memory coreParams) internal {
        // Parse coreParams: "positionId-listingAddress-makerAddress-positionType-status1-status2"
        bytes memory params = bytes(coreParams);
        if (params.length == 0) return;

        (uint256 corePositionId, address listingAddress, address makerAddress, uint8 positionType, bool status1, uint8 status2) = 
            abi.decode(abi.encodePacked(params), (uint256, address, address, uint8, bool, uint8));

        if (corePositionId != 0) {
            positionCore1[positionId] = PositionCore1({
                positionId: corePositionId,
                listingAddress: listingAddress,
                makerAddress: makerAddress,
                positionType: positionType
            });
        }
        if (status2 != type(uint8).max) {
            positionCore2[positionId] = PositionCore2({
                status1: status1,
                status2: status2
            });
        }
    }

    // Internal helper to parse and update price parameters
    function parsePriceParams(uint256 positionId, string memory priceParams) internal {
        // Parse priceParams: "minEntryPrice-maxEntryPrice-minPrice-priceAtEntry-leverage-liquidationPrice"
        bytes memory params = bytes(priceParams);
        if (params.length == 0) return;

        (uint256 minEntryPrice, uint256 maxEntryPrice, uint256 minPrice, uint256 priceAtEntry, uint8 leverage, uint256 liquidationPrice) = 
            abi.decode(abi.encodePacked(params), (uint256, uint256, uint256, uint256, uint8, uint256));

        if (minEntryPrice != 0 || maxEntryPrice != 0 || minPrice != 0 || priceAtEntry != 0) {
            priceParams1[positionId] = PriceParams1({
                minEntryPrice: minEntryPrice,
                maxEntryPrice: maxEntryPrice,
                minPrice: minPrice,
                priceAtEntry: priceAtEntry,
                leverage: leverage
            });
        }
        if (liquidationPrice != 0) {
            priceParams2[positionId] = PriceParams2({
                liquidationPrice: liquidationPrice
            });
        }
    }

    // Internal helper to parse and update margin parameters
    function parseMarginParams(uint256 positionId, string memory marginParams) internal {
        // Parse marginParams: "initialMargin-taxedMargin-excessMargin-fee-initialLoan"
        bytes memory params = bytes(marginParams);
        if (params.length == 0) return;

        (uint256 initialMargin, uint256 taxedMargin, uint256 excessMargin, uint256 fee, uint256 initialLoan) = 
            abi.decode(abi.encodePacked(params), (uint256, uint256, uint256, uint256, uint256));

        if (initialMargin != 0 || taxedMargin != 0 || excessMargin != 0 || fee != 0) {
            marginParams1[positionId] = MarginParams1({
                initialMargin: initialMargin,
                taxedMargin: taxedMargin,
                excessMargin: excessMargin,
                fee: fee
            });
        }
        if (initialLoan != 0) {
            marginParams2[positionId] = MarginParams2({
                initialLoan: initialLoan
            });
        }
    }

    // Internal helper to parse and update exit parameters and open interest
    function parseExitAndInterest(uint256 positionId, string memory exitAndInterestParams) internal {
        // Parse exitAndInterestParams: "stopLossPrice-takeProfitPrice-exitPrice-leverageAmount-timestamp"
        bytes memory params = bytes(exitAndInterestParams);
        if (params.length == 0) return;

        (uint256 stopLossPrice, uint256 takeProfitPrice, uint256 exitPrice, uint256 leverageAmount, uint256 timestamp) = 
            abi.decode(abi.encodePacked(params), (uint256, uint256, uint256, uint256, uint256));

        if (stopLossPrice != 0 || takeProfitPrice != 0 || exitPrice != 0) {
            exitParams[positionId] = ExitParams({
                stopLossPrice: stopLossPrice,
                takeProfitPrice: takeProfitPrice,
                exitPrice: exitPrice
            });
        }
        if (leverageAmount != 0 || timestamp != 0) {
            openInterest[positionId] = OpenInterest({
                leverageAmount: leverageAmount,
                timestamp: timestamp
            });
        }
    }

    // Internal helper to parse and update maker margin and position token
    function parseMakerMargin(uint256 positionId, string memory makerMarginParams) internal {
        // Parse makerMarginParams: "token-maker-marginToken-marginAmount"
        bytes memory params = bytes(makerMarginParams);
        if (params.length == 0) return;

        (address token, address maker, address marginToken, uint256 marginAmount) = 
            abi.decode(abi.encodePacked(params), (address, address, address, uint256));

        if (token != address(0)) {
            positionToken[positionId] = token;
        }
        if (maker != address(0) && marginToken != address(0) && marginAmount != 0) {
            makerTokenMargin[maker][marginToken] = marginAmount;
            bool tokenExists = false;
            for (uint256 i = 0; i < makerMarginTokens[maker].length; i++) {
                if (makerMarginTokens[maker][i] == marginToken) {
                    tokenExists = true;
                    break;
                }
            }
            if (!tokenExists) {
                makerMarginTokens[maker].push(marginToken);
            }
        }
    }

    // Internal helper to parse and update position arrays and count
    function parsePositionArrays(uint256 positionId, string memory positionArrayParams) internal {
        // Parse positionArrayParams: "listingAddress-positionType-addToPending-addToActive"
        bytes memory params = bytes(positionArrayParams);
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
    function CSUpdate(
        uint256 positionId,
        string memory coreParams,
        string memory priceParams,
        string memory marginParams,
        string memory exitAndInterestParams,
        string memory makerMarginParams,
        string memory positionArrayParams,
        string memory historicalInterestParams
    ) external onlyMux {
        // Parse historicalInterestParams: "longIO-shortIO-timestamp"
        bytes memory histParams = bytes(historicalInterestParams);
        if (histParams.length != 0) {
            (uint256 longIO, uint256 shortIO, uint256 timestamp) = 
                abi.decode(abi.encodePacked(histParams), (uint256, uint256, uint256));
            uint256 height = block.number;
            if (longIO != 0) longIOByHeight[height] = longIO;
            if (shortIO != 0) shortIOByHeight[height] = shortIO;
            if (timestamp != 0) historicalInterestTimestamps[height] = timestamp;
        }

        // Call internal helpers to parse and update state
        parseCoreParams(positionId, coreParams);
        parsePriceParams(positionId, priceParams);
        parseMarginParams(positionId, marginParams);
        parseExitAndInterest(positionId, exitAndInterestParams);
        parseMakerMargin(positionId, makerMarginParams);
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

    // Removes token from maker's margin token list
    function removeToken(address maker, address token) external onlyMux {
        address[] storage tokens = makerMarginTokens[maker];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }
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
        uint256 currentPrice = normalizePrice(token, ISSListing(core1.listingAddress).prices(core1.listingAddress));
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
            uint256 currentPrice = normalizePrice(token, ISSListing(listingAddress).prices(token));
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
    function normalizePrice(address token, uint256 price) internal view returns (uint256) {
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