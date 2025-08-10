/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-08-10: Added _getCurrentPrice to resolve undeclared identifier errors; confirmed ISSListing compatibility with ICCListing; version set to 0.0.13.
 - 2025-08-10: Confirmed ISIStorage interface presence; integrated _finalizeClosePosition and _executeCancelPosition from CISExtraPartial v0.0.1; added _updateHistoricalInterest; version set to 0.0.12.
 - 2025-08-10: Integrated _finalizeClosePosition and _executeCancelPosition from CISExtraPartial v0.0.1; added _updateHistoricalInterest; version set to 0.0.11.
 - 2025-08-08: Fixed stack too deep in _fetchPositionParams; optimized _fetchPositionData; version set to 0.0.10.
 - 2025-08-08: Fixed TypeError in _fetchPositionParams, _computePayoutLong, _computePayoutShort; version set to 0.0.9.
 - 2025-08-08: Split _fetchPositionParams and _prepareStorageUpdate; version set to 0.0.8.
 - 2025-08-08: Fixed TypeError in _assignPositionData; refactored _updatePositionStorage; version set to 0.0.7.
 - 2025-08-08: Refactored _getPositionByIndex with x64 approach; version set to 0.0.6.
 - 2025-08-08: Cast storageContract to ISIStorage; version set to 0.0.5.
 - 2025-08-08: Removed 'this.' from internal calls; version set to 0.0.4.
 - 2025-08-08: Updated _prepDriftPayout; version set to 0.0.3.
 - 2025-08-08: Updated _executePayoutUpdate; version set to 0.0.2.
 - 2025-08-07: Created CISExitPartial; version set to 0.0.1.
*/

pragma solidity ^0.8.2;

import "../imports/IERC20.sol";
import "../imports/ReentrancyGuard.sol";

interface ISSListing {
    struct ListingPayoutUpdate {
        uint8 payoutType;
        address recipient;
        uint256 required;
    }
    function tokenA() external view returns (address tokenA);
    function tokenB() external view returns (address tokenB);
    function prices(uint256 index) external view returns (uint256 price);
    function ssUpdate(ListingPayoutUpdate[] memory updates) external;
}

interface ISIStorage {
    struct PositionCoreBase {
        address makerAddress;
        address listingAddress;
        uint256 positionId;
        uint8 positionType;
    }
    struct PositionCoreStatus {
        bool status1;
        uint8 status2;
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
    function positionCount() external view returns (uint256 count);
    function positionByIndex(uint256 index) external view returns (
        PositionCoreBase memory coreBase,
        PositionCoreStatus memory coreStatus,
        PriceParams memory price,
        MarginParams memory margin,
        LeverageParams memory leverage,
        RiskParams memory risk,
        address token
    );
    function AggregateMarginByToken(address tokenA, address tokenB, uint256 step, uint256 maxIterations) external view returns (address[] memory makers, uint256[] memory margins);
    function removePositionIndex(uint256 positionId, uint8 positionType, address listingAddress) external;
    function longIOByHeight(uint256) external view returns (uint256);
    function shortIOByHeight(uint256) external view returns (uint256);
    function SIUpdate(
        uint256 positionId,
        CoreParams memory coreData,
        PriceParams memory priceData,
        MarginParams memory marginData,
        LeverageParams memory leverageData,
        RiskParams memory riskData,
        TokenAndInterestParams memory tokenData,
        PositionArrayParams memory arrayData
    ) external;
    function positionCoreBase(uint256) external view returns (PositionCoreBase memory);
    function positionCoreStatus(uint256) external view returns (PositionCoreStatus memory);
    function pendingPositions(address, uint8) external view returns (uint256[] memory);
    function positionsByType(uint8) external view returns (uint256[] memory);
}

interface ISSAgent {
    struct ListingDetails {
        address listingAddress;
        address liquidityAddress;
        address tokenA;
        address tokenB;
        uint256 listingId;
    }
    function isValidListing(address listingAddress) external view returns (bool isValid, ListingDetails memory details);
}

contract CISExitPartial is ReentrancyGuard {
    uint256 public constant DECIMAL_PRECISION = 1e18;
    address public executionDriver;
    address public storageContract;
    address public agentAddress;
    uint256 internal positionIdCounter;
    uint256 internal historicalInterestHeight;

    struct PendingEntry {
        address listingAddr;
        address tokenAddr;
        uint256 positionId;
        uint8 positionType;
        uint256 initialMargin;
        uint256 extraMargin;
        string entryPriceStr;
        address makerAddress;
        uint8 leverageVal;
        uint256 stopLoss;
        uint256 takeProfit;
        uint256 normInitMargin;
        uint256 normExtraMargin;
    }

    struct EntryContext {
        uint256 positionId;
        address listingAddress;
        uint256 minEntryPrice;
        uint256 maxEntryPrice;
        uint256 initialMargin;
        uint256 excessMargin;
        uint8 leverage;
        uint8 positionType;
        address maker;
        address token;
    }

    struct PrepPosition {
        uint256 fee;
        uint256 taxedMargin;
        uint256 leverageAmount;
        uint256 initialLoan;
        uint256 liquidationPrice;
    }

    struct PositionData {
        ISIStorage.PositionCoreBase coreBase;
        ISIStorage.PositionCoreStatus coreStatus;
        ISIStorage.PriceParams price;
        ISIStorage.MarginParams margin;
        ISIStorage.LeverageParams leverage;
        ISIStorage.RiskParams risk;
        address token;
    }

    mapping(uint256 => PendingEntry) internal pendingEntries;

    constructor() {
        historicalInterestHeight = uint256(1);
        positionIdCounter = uint256(0);
    }

    function setExecutionDriver(address _executionDriver) external onlyOwner {
        require(_executionDriver != address(0), "Invalid execution driver address");
        executionDriver = _executionDriver;
    }

    function setStorageContract(address _storageContract) external onlyOwner {
        require(_storageContract != address(0), "Invalid storage address");
        storageContract = _storageContract;
    }

    function setAgent(address newAgentAddress) external onlyOwner {
        require(newAgentAddress != address(0), "Invalid agent address");
        agentAddress = newAgentAddress;
    }

    function getExecutionDriver() external view returns (address driver) {
        driver = executionDriver;
    }

    function getAgentAddress() external view returns (address agent) {
        agent = agentAddress;
    }

    function uint2str(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0) return "0";
        uint256 temp = _i;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (_i != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + (_i % 10)));
            _i /= 10;
        }
        str = string(buffer);
    }

    function toString(address _addr) internal pure returns (string memory str) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory strBytes = new bytes(42);
        strBytes[0] = "0";
        strBytes[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            strBytes[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            strBytes[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        str = string(strBytes);
    }

    function normalizeAmount(address token, uint256 amount) internal view returns (uint256 normalized) {
        uint8 decimals = IERC20(token).decimals();
        normalized = amount * DECIMAL_PRECISION / (10 ** decimals);
    }

    function denormalizeAmount(address token, uint256 amount) internal view returns (uint256 denormalized) {
        uint8 decimals = IERC20(token).decimals();
        denormalized = amount * (10 ** decimals) / DECIMAL_PRECISION;
    }

    function normalizePrice(address token, uint256 price) internal view returns (uint256 normalized) {
        uint8 decimals = IERC20(token).decimals();
        if (decimals < 18) return price * (10 ** (18 - decimals));
        if (decimals > 18) return price / (10 ** (decimals - 18));
        normalized = price;
    }

    // Fetches current price from ISSListing and normalizes it for the given token
    function _getCurrentPrice(address listingAddress, address token) internal view returns (uint256 price) {
        try ISSListing(listingAddress).prices(0) returns (uint256 currentPrice) {
            price = normalizePrice(token, currentPrice);
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Failed to fetch price for listing ", toString(listingAddress), ": ", reason)));
        }
    }

    function _prepDriftPayout(
        uint256 positionId,
        ISIStorage.PositionCoreBase memory coreBase
    ) internal view returns (uint256 payout, address token) {
        if (coreBase.positionType == 0) {
            token = ISSListing(coreBase.listingAddress).tokenB();
            payout = _computePayoutLong(positionId, coreBase.listingAddress, token);
        } else {
            token = ISSListing(coreBase.listingAddress).tokenA();
            payout = _computePayoutShort(positionId, coreBase.listingAddress, token);
        }
    }

    function _prepDriftPayoutUpdate(
        uint256 positionId,
        ISIStorage.PositionCoreBase memory coreBase,
        uint256 payout,
        address token
    ) internal {
        ISSListing.ListingPayoutUpdate[] memory updates = new ISSListing.ListingPayoutUpdate[](1);
        updates[0] = ISSListing.ListingPayoutUpdate({
            payoutType: coreBase.positionType,
            recipient: msg.sender,
            required: denormalizeAmount(token, payout)
        });
        try ISSListing(coreBase.listingAddress).ssUpdate(updates) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Payout update failed for position ID ", uint2str(positionId), ": ", reason)));
        }
    }

    function _prepCoreParams(
        uint256 positionId,
        ISIStorage.PositionCoreBase memory coreBase
    ) internal pure returns (ISIStorage.CoreParams memory coreData) {
        coreData = ISIStorage.CoreParams({
            makerAddress: coreBase.makerAddress,
            listingAddress: coreBase.listingAddress,
            corePositionId: positionId,
            positionType: coreBase.positionType,
            status1: true,
            status2: 0
        });
    }

    function _prepPriceParams(
        ISIStorage.PriceParams memory price,
        address token,
        address listingAddress
    ) internal view returns (ISIStorage.PriceParams memory priceData) {
        uint256 currentPrice = _getCurrentPrice(listingAddress, token);
        priceData = ISIStorage.PriceParams({
            priceMin: price.priceMin,
            priceMax: price.priceMax,
            priceAtEntry: price.priceAtEntry,
            priceClose: currentPrice
        });
    }

    function _prepMarginParams(
        ISIStorage.MarginParams memory marginData
    ) internal pure returns (ISIStorage.MarginParams memory marginParams) {
        marginParams = ISIStorage.MarginParams({
            marginInitial: marginData.marginInitial,
            marginTaxed: marginData.marginTaxed,
            marginExcess: marginData.marginExcess
        });
    }

    function _prepLeverageAndRiskParams(
        ISIStorage.LeverageParams memory leverage,
        ISIStorage.RiskParams memory risk
    ) internal pure returns (ISIStorage.LeverageParams memory leverageData, ISIStorage.RiskParams memory riskData) {
        leverageData = ISIStorage.LeverageParams({
            leverageVal: leverage.leverageVal,
            leverageAmount: leverage.leverageAmount,
            loanInitial: leverage.loanInitial
        });
        riskData = ISIStorage.RiskParams({
            priceLiquidation: risk.priceLiquidation,
            priceStopLoss: risk.priceStopLoss,
            priceTakeProfit: risk.priceTakeProfit
        });
    }

    function _prepTokenAndInterestParams(
        address token,
        uint256 leverageAmount
    ) internal view returns (ISIStorage.TokenAndInterestParams memory tokenData) {
        tokenData = ISIStorage.TokenAndInterestParams({
            token: token,
            longIO: leverageAmount,
            shortIO: 0,
            timestamp: block.timestamp
        });
    }

    function _computeUpdatedMargin(
        address maker,
        address tokenA,
        address tokenB,
        uint256 taxedMargin,
        uint256 excessMargin
    ) internal view returns (uint256 updatedMargin) {
        address[] memory makers;
        uint256[] memory margins;
        try ISIStorage(storageContract).AggregateMarginByToken(tokenA, tokenB, 0, type(uint256).max) returns (address[] memory _makers, uint256[] memory _margins) {
            (makers, margins) = (_makers, _margins);
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Failed to get margin data for tokens ", toString(tokenA), ", ", toString(tokenB), ": ", reason)));
        }
        updatedMargin = 0;
        for (uint256 i = 0; i < makers.length; i++) {
            if (makers[i] == maker) {
                updatedMargin = margins[i] - (taxedMargin + excessMargin);
                break;
            }
        }
    }

    function _fetchCoreParams(
        uint256 positionId,
        ISIStorage.PositionCoreBase memory coreBase
    ) internal pure returns (ISIStorage.CoreParams memory coreData) {
        coreData = _prepCoreParams(positionId, coreBase);
    }

    function _fetchPriceParams(
        PositionData memory posData,
        address token,
        address listingAddress
    ) internal view returns (ISIStorage.PriceParams memory priceData) {
        priceData = _prepPriceParams(posData.price, token, listingAddress);
    }

    function _fetchPositionData(uint256 positionId) internal view returns (PositionData memory posData) {
        try ISIStorage(storageContract).positionByIndex(positionId) returns (
            ISIStorage.PositionCoreBase memory coreBase,
            ISIStorage.PositionCoreStatus memory coreStatus,
            ISIStorage.PriceParams memory price,
            ISIStorage.MarginParams memory margin,
            ISIStorage.LeverageParams memory leverage,
            ISIStorage.RiskParams memory risk,
            address token
        ) {
            posData = PositionData({
                coreBase: coreBase,
                coreStatus: coreStatus,
                price: price,
                margin: margin,
                leverage: leverage,
                risk: risk,
                token: token
            });
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Failed to get position data for ID ", uint2str(positionId), ": ", reason)));
        }
    }

    function _assignPositionData(PositionData memory posData) internal pure returns (
        ISIStorage.PositionCoreBase memory coreBase,
        ISIStorage.PositionCoreStatus memory coreStatus,
        ISIStorage.PriceParams memory price,
        ISIStorage.MarginParams memory margin,
        ISIStorage.LeverageParams memory leverage,
        ISIStorage.RiskParams memory risk,
        address token
    ) {
        coreBase = posData.coreBase;
        coreStatus = posData.coreStatus;
        price = posData.price;
        margin = posData.margin;
        leverage = posData.leverage;
        risk = posData.risk;
        token = posData.token;
    }

    function _getPositionByIndex(uint256 positionId) internal view returns (
        ISIStorage.PositionCoreBase memory coreBase,
        ISIStorage.PositionCoreStatus memory coreStatus,
        ISIStorage.PriceParams memory price,
        ISIStorage.MarginParams memory margin,
        ISIStorage.LeverageParams memory leverage,
        ISIStorage.RiskParams memory risk,
        address token
    ) {
        PositionData memory posData = _fetchPositionData(positionId);
        return _assignPositionData(posData);
    }

    function _computeLongPayout(
        ISIStorage.MarginParams memory margin,
        ISIStorage.LeverageParams memory leverage,
        uint256 currentPrice
    ) internal pure returns (uint256 payout) {
        uint256 leverageAmount = uint256(leverage.leverageVal) * margin.marginInitial;
        uint256 baseValue = (margin.marginTaxed + margin.marginExcess + leverageAmount) / currentPrice;
        payout = baseValue > leverage.loanInitial ? baseValue - leverage.loanInitial : 0;
    }

    function _computePayoutLong(
        uint256 positionId,
        address listingAddress,
        address tokenB
    ) internal view returns (uint256 payout) {
        PositionData memory posData = _fetchPositionData(positionId);
        uint256 currentPrice = _getCurrentPrice(listingAddress, tokenB);
        payout = _computeLongPayout(posData.margin, posData.leverage, currentPrice);
    }

    function _computeShortPayout(
        ISIStorage.PriceParams memory price,
        ISIStorage.MarginParams memory margin,
        ISIStorage.LeverageParams memory leverage,
        uint256 currentPrice
    ) internal pure returns (uint256 payout) {
        uint256 priceDiff = price.priceAtEntry > currentPrice ? price.priceAtEntry - currentPrice : 0;
        uint256 profit = priceDiff * margin.marginInitial * uint256(leverage.leverageVal);
        payout = profit + (margin.marginTaxed + margin.marginExcess) * currentPrice / DECIMAL_PRECISION;
    }

    function _computePayoutShort(
        uint256 positionId,
        address listingAddress,
        address tokenA
    ) internal view returns (uint256 payout) {
        PositionData memory posData = _fetchPositionData(positionId);
        uint256 currentPrice = _getCurrentPrice(listingAddress, tokenA);
        payout = _computeShortPayout(posData.price, posData.margin, posData.leverage, currentPrice);
    }

    function _deductMarginAndRemoveToken(
        address maker,
        address token,
        uint256 taxedMargin,
        uint256 excessMargin
    ) internal {
        uint256 transferAmount = taxedMargin + excessMargin;
        address[] memory makers;
        uint256[] memory margins;
        try ISIStorage(storageContract).AggregateMarginByToken(token, token, 0, type(uint256).max) returns (address[] memory _makers, uint256[] memory _margins) {
            (makers, margins) = (_makers, _margins);
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Failed to get margin data for token ", toString(token), ": ", reason)));
        }
        uint256 updatedMargin = 0;
        for (uint256 i = 0; i < makers.length; i++) {
            if (makers[i] == maker) {
                updatedMargin = margins[i] - transferAmount;
                break;
            }
        }
        ISIStorage.TokenAndInterestParams memory tokenData = ISIStorage.TokenAndInterestParams({
            token: token,
            longIO: 0,
            shortIO: 0,
            timestamp: block.timestamp
        });
        try ISIStorage(storageContract).SIUpdate(
            0,
            ISIStorage.CoreParams(address(0), address(0), 0, 0, false, 0),
            ISIStorage.PriceParams(0, 0, 0, 0),
            ISIStorage.MarginParams(0, 0, 0),
            ISIStorage.LeverageParams(0, 0, 0),
            ISIStorage.RiskParams(0, 0, 0),
            tokenData,
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        ) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("SIUpdate margin failed for maker ", toString(maker), ": ", reason)));
        }
    }

    function _executePayoutUpdate(
        uint256 positionId,
        address listingAddress,
        uint256 payout,
        uint8 positionType,
        address recipient,
        address token
    ) internal {
        ISSListing.ListingPayoutUpdate[] memory updates = new ISSListing.ListingPayoutUpdate[](1);
        updates[0] = ISSListing.ListingPayoutUpdate({
            payoutType: positionType,
            recipient: recipient,
            required: denormalizeAmount(token, payout)
        });
        try ISSListing(listingAddress).ssUpdate(updates) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Payout update failed for position ID ", uint2str(positionId), ": ", reason)));
        }
    }

    function _updateCoreData(
        uint256 positionId,
        ISIStorage.CoreParams memory coreData
    ) internal {
        try ISIStorage(storageContract).SIUpdate(
            positionId,
            coreData,
            ISIStorage.PriceParams(0, 0, 0, 0),
            ISIStorage.MarginParams(0, 0, 0),
            ISIStorage.LeverageParams(0, 0, 0),
            ISIStorage.RiskParams(0, 0, 0),
            ISIStorage.TokenAndInterestParams(address(0), 0, 0, 0),
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        ) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Core data update failed for position ID ", uint2str(positionId), ": ", reason)));
        }
    }

    function _updatePriceData(
        uint256 positionId,
        ISIStorage.PriceParams memory priceData
    ) internal {
        try ISIStorage(storageContract).SIUpdate(
            positionId,
            ISIStorage.CoreParams(address(0), address(0), 0, 0, false, 0),
            priceData,
            ISIStorage.MarginParams(0, 0, 0),
            ISIStorage.LeverageParams(0, 0, 0),
            ISIStorage.RiskParams(0, 0, 0),
            ISIStorage.TokenAndInterestParams(address(0), 0, 0, 0),
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        ) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Price data update failed for position ID ", uint2str(positionId), ": ", reason)));
        }
    }

    function _updateMarginData(
        uint256 positionId,
        ISIStorage.MarginParams memory marginData
    ) internal {
        try ISIStorage(storageContract).SIUpdate(
            positionId,
            ISIStorage.CoreParams(address(0), address(0), 0, 0, false, 0),
            ISIStorage.PriceParams(0, 0, 0, 0),
            marginData,
            ISIStorage.LeverageParams(0, 0, 0),
            ISIStorage.RiskParams(0, 0, 0),
            ISIStorage.TokenAndInterestParams(address(0), 0, 0, 0),
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        ) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Margin data update failed for position ID ", uint2str(positionId), ": ", reason)));
        }
    }

    function _updateLeverageData(
        uint256 positionId,
        ISIStorage.LeverageParams memory leverageData
    ) internal {
        try ISIStorage(storageContract).SIUpdate(
            positionId,
            ISIStorage.CoreParams(address(0), address(0), 0, 0, false, 0),
            ISIStorage.PriceParams(0, 0, 0, 0),
            ISIStorage.MarginParams(0, 0, 0),
            leverageData,
            ISIStorage.RiskParams(0, 0, 0),
            ISIStorage.TokenAndInterestParams(address(0), 0, 0, 0),
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        ) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Leverage data update failed for position ID ", uint2str(positionId), ": ", reason)));
        }
    }

    function _updateRiskData(
        uint256 positionId,
        ISIStorage.RiskParams memory riskData
    ) internal {
        try ISIStorage(storageContract).SIUpdate(
            positionId,
            ISIStorage.CoreParams(address(0), address(0), 0, 0, false, 0),
            ISIStorage.PriceParams(0, 0, 0, 0),
            ISIStorage.MarginParams(0, 0, 0),
            ISIStorage.LeverageParams(0, 0, 0),
            riskData,
            ISIStorage.TokenAndInterestParams(address(0), 0, 0, 0),
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        ) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Risk data update failed for position ID ", uint2str(positionId), ": ", reason)));
        }
    }

    function _updateTokenData(
        uint256 positionId,
        ISIStorage.TokenAndInterestParams memory tokenData
    ) internal {
        try ISIStorage(storageContract).SIUpdate(
            positionId,
            ISIStorage.CoreParams(address(0), address(0), 0, 0, false, 0),
            ISIStorage.PriceParams(0, 0, 0, 0),
            ISIStorage.MarginParams(0, 0, 0),
            ISIStorage.LeverageParams(0, 0, 0),
            ISIStorage.RiskParams(0, 0, 0),
            tokenData,
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        ) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Token data update failed for position ID ", uint2str(positionId), ": ", reason)));
        }
    }

    function _updateArrayData(
        uint256 positionId,
        ISIStorage.PositionArrayParams memory arrayData
    ) internal {
        try ISIStorage(storageContract).SIUpdate(
            positionId,
            ISIStorage.CoreParams(address(0), address(0), 0, 0, false, 0),
            ISIStorage.PriceParams(0, 0, 0, 0),
            ISIStorage.MarginParams(0, 0, 0),
            ISIStorage.LeverageParams(0, 0, 0),
            ISIStorage.RiskParams(0, 0, 0),
            ISIStorage.TokenAndInterestParams(address(0), 0, 0, 0),
            arrayData
        ) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Array data update failed for position ID ", uint2str(positionId), ": ", reason)));
        }
    }

    function _prepareStorageUpdate(
        uint256 positionId,
        ISIStorage.CoreParams memory coreData,
        ISIStorage.PriceParams memory priceData,
        ISIStorage.MarginParams memory marginData,
        ISIStorage.LeverageParams memory leverageData,
        ISIStorage.RiskParams memory riskData,
        ISIStorage.TokenAndInterestParams memory tokenData,
        ISIStorage.PositionArrayParams memory arrayData
    ) internal {
        _updateCoreData(positionId, coreData);
        _updatePriceData(positionId, priceData);
        _updateMarginData(positionId, marginData);
        _updateLeverageData(positionId, leverageData);
        _updateRiskData(positionId, riskData);
        _updateTokenData(positionId, tokenData);
        _updateArrayData(positionId, arrayData);
    }

    function _updatePositionStorage(
        uint256 positionId,
        ISIStorage.PositionCoreBase memory coreBase,
        ISIStorage.MarginParams memory margin,
        address token
    ) internal {
        (
            ISIStorage.CoreParams memory coreData,
            ISIStorage.PriceParams memory priceData,
            ISIStorage.MarginParams memory marginData,
            ISIStorage.LeverageParams memory leverageData,
            ISIStorage.RiskParams memory riskData,
            ISIStorage.TokenAndInterestParams memory tokenData,
            ISIStorage.PositionArrayParams memory arrayData
        ) = _fetchPositionParams(positionId, coreBase, token);
        uint256 updatedMargin = _computeMarginUpdate(coreBase, margin);
        marginData.marginTaxed = updatedMargin;
        marginData.marginExcess = 0;
        _prepareStorageUpdate(positionId, coreData, priceData, marginData, leverageData, riskData, tokenData, arrayData);
    }

    function _computeMarginUpdate(
        ISIStorage.PositionCoreBase memory coreBase,
        ISIStorage.MarginParams memory margin
    ) internal view returns (uint256 updatedMargin) {
        address tokenA = ISSListing(coreBase.listingAddress).tokenA();
        address tokenB = ISSListing(coreBase.listingAddress).tokenB();
        updatedMargin = _computeUpdatedMargin(coreBase.makerAddress, tokenA, tokenB, margin.marginTaxed, margin.marginExcess);
    }

    function _fetchPositionParams(
        uint256 positionId,
        ISIStorage.PositionCoreBase memory coreBase,
        address token
    ) internal view returns (
        ISIStorage.CoreParams memory coreData,
        ISIStorage.PriceParams memory priceData,
        ISIStorage.MarginParams memory marginData,
        ISIStorage.LeverageParams memory leverageData,
        ISIStorage.RiskParams memory riskData,
        ISIStorage.TokenAndInterestParams memory tokenData,
        ISIStorage.PositionArrayParams memory arrayData
    ) {
        PositionData memory posData = _fetchPositionData(positionId);
        coreData = _fetchCoreParams(positionId, posData.coreBase);
        priceData = _fetchPriceParams(posData, token, coreBase.listingAddress);
        marginData = _prepMarginParams(posData.margin);
        (leverageData, riskData) = _prepLeverageAndRiskParams(posData.leverage, posData.risk);
        tokenData = _prepTokenAndInterestParams(token, posData.leverage.leverageAmount);
        arrayData = ISIStorage.PositionArrayParams({
            listingAddress: coreBase.listingAddress,
            positionType: coreBase.positionType,
            addToPending: false,
            addToActive: false
        });
    }

    function _updateHistoricalInterest(
        uint256 amount,
        uint8 positionType,
        address listingAddress,
        bool isAdd
    ) internal {
        uint256 height = historicalInterestHeight;
        uint256 longIO = ISIStorage(storageContract).longIOByHeight(height);
        uint256 shortIO = ISIStorage(storageContract).shortIOByHeight(height);
        if (isAdd) {
            longIO = positionType == 0 ? longIO + amount : longIO;
            shortIO = positionType == 1 ? shortIO + amount : shortIO;
        } else {
            longIO = positionType == 0 ? longIO - amount : longIO;
            shortIO = positionType == 1 ? shortIO - amount : shortIO;
        }
        ISIStorage.TokenAndInterestParams memory tokenData = ISIStorage.TokenAndInterestParams({
            token: address(0),
            longIO: longIO,
            shortIO: shortIO,
            timestamp: block.timestamp
        });
        try ISIStorage(storageContract).SIUpdate(
            0,
            ISIStorage.CoreParams(address(0), address(0), 0, 0, false, 0),
            ISIStorage.PriceParams(0, 0, 0, 0),
            ISIStorage.MarginParams(0, 0, 0),
            ISIStorage.LeverageParams(0, 0, 0),
            ISIStorage.RiskParams(0, 0, 0),
            tokenData,
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        ) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Historical interest update failed: ", reason)));
        }
        historicalInterestHeight++;
    }

    function _finalizeClosePosition(
        uint256 positionId,
        uint8 positionType,
        address listingAddress,
        address caller
    ) internal returns (uint256 payout) {
        (bool isValid, ) = ISSAgent(agentAddress).isValidListing(listingAddress);
        if (!isValid) {
            revert(string(abi.encodePacked("finalizeClosePosition: Invalid listing for position ", uint2str(positionId))));
        }
        PositionData memory posData = _fetchPositionData(positionId);
        if (posData.coreBase.positionId != positionId || posData.coreBase.listingAddress != listingAddress) {
            revert(string(abi.encodePacked("finalizeClosePosition: Invalid position or listing for ", uint2str(positionId))));
        }
        if (posData.coreStatus.status2 != 0) {
            revert(string(abi.encodePacked("finalizeClosePosition: Position ", uint2str(positionId), " is closed")));
        }
        if (posData.coreBase.makerAddress != caller) {
            revert(string(abi.encodePacked("finalizeClosePosition: Caller not maker for position ", uint2str(positionId))));
        }
        address token = positionType == 0 ? ISSListing(listingAddress).tokenB() : ISSListing(listingAddress).tokenA();
        payout = positionType == 0 ? _computePayoutLong(positionId, listingAddress, token) : _computePayoutShort(positionId, listingAddress, token);
        uint256 marginAmount = posData.margin.marginTaxed + posData.margin.marginExcess;
        _deductMarginAndRemoveToken(posData.coreBase.makerAddress, positionType == 0 ? ISSListing(listingAddress).tokenA() : ISSListing(listingAddress).tokenB(), posData.margin.marginTaxed, posData.margin.marginExcess);
        _executePayoutUpdate(positionId, listingAddress, payout, positionType, posData.coreBase.makerAddress, token);
        ISIStorage.PriceParams memory priceData = _prepPriceParams(posData.price, token, listingAddress);
        ISIStorage.CoreParams memory coreData = ISIStorage.CoreParams({
            makerAddress: address(0),
            listingAddress: address(0),
            corePositionId: 0,
            positionType: 0,
            status1: false,
            status2: 2
        });
        try ISIStorage(storageContract).SIUpdate(
            positionId,
            coreData,
            priceData,
            ISIStorage.MarginParams(0, 0, 0),
            ISIStorage.LeverageParams(0, 0, 0),
            ISIStorage.RiskParams(0, 0, 0),
            ISIStorage.TokenAndInterestParams(address(0), 0, 0, 0),
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        ) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Storage update failed for position ID ", uint2str(positionId), ": ", reason)));
        }
        try ISIStorage(storageContract).removePositionIndex(positionId, positionType, listingAddress) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Remove position index failed for ID ", uint2str(positionId), ": ", reason)));
        }
        _updateHistoricalInterest(marginAmount, positionType, listingAddress, false);
    }

    function _executeCancelPosition(
        uint256 positionId,
        uint8 positionType,
        address listingAddress,
        address caller
    ) internal {
        PositionData memory posData = _fetchPositionData(positionId);
        if (posData.coreBase.positionId != positionId || posData.coreBase.listingAddress != listingAddress) {
            revert(string(abi.encodePacked("executeCancelPosition: Invalid position or listing for ", uint2str(positionId))));
        }
        if (posData.coreStatus.status2 != 0) {
            revert(string(abi.encodePacked("executeCancelPosition: Position ", uint2str(positionId), " is closed")));
        }
        if (posData.coreBase.makerAddress != caller) {
            revert(string(abi.encodePacked("executeCancelPosition: Caller not maker for position ", uint2str(positionId))));
        }
        uint256 marginAmount = posData.margin.marginTaxed + posData.margin.marginExcess;
        _deductMarginAndRemoveToken(posData.coreBase.makerAddress, positionType == 0 ? ISSListing(listingAddress).tokenA() : ISSListing(listingAddress).tokenB(), posData.margin.marginTaxed, posData.margin.marginExcess);
        ISIStorage.CoreParams memory coreData = ISIStorage.CoreParams({
            makerAddress: address(0),
            listingAddress: address(0),
            corePositionId: 0,
            positionType: 0,
            status1: false,
            status2: 2
        });
        try ISIStorage(storageContract).SIUpdate(
            positionId,
            coreData,
            ISIStorage.PriceParams(0, 0, 0, 0),
            ISIStorage.MarginParams(0, 0, 0),
            ISIStorage.LeverageParams(0, 0, 0),
            ISIStorage.RiskParams(0, 0, 0),
            ISIStorage.TokenAndInterestParams(address(0), 0, 0, 0),
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        ) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Storage update failed for position ID ", uint2str(positionId), ": ", reason)));
        }
        try ISIStorage(storageContract).removePositionIndex(positionId, positionType, listingAddress) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Remove position index failed for ID ", uint2str(positionId), ": ", reason)));
        }
        _updateHistoricalInterest(marginAmount, positionType, listingAddress, false);
        ISSListing.ListingPayoutUpdate[] memory updates = new ISSListing.ListingPayoutUpdate[](1);
        updates[0] = ISSListing.ListingPayoutUpdate({
            payoutType: 0,
            recipient: posData.coreBase.makerAddress,
            required: marginAmount
        });
        try ISSListing(listingAddress).ssUpdate(updates) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Payout update failed for position ID ", uint2str(positionId), ": ", reason)));
        }
    }
}