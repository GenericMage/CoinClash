/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-08-08: Added EntryParams struct to reduce _initiateEntry parameters; updated _finalizeEntryTransfer for native token support (v0.0.3).
 - 2025-08-07: Fixed TypeError by casting storageContract to ISIStorage and calling SIUpdate directly in _updateEntryCore, _storeEntryParams, _updateEntryIndexes, and _finalizeEntryFees (v0.0.2).
 - 2025-08-07: Created CISEntryPartial by splitting CISPositionPartial.sol (v0.0.12); included entry-related functions and shared state (v0.0.1).
*/

pragma solidity ^0.8.2;

import "../imports/IERC20.sol";
import "../imports/ReentrancyGuard.sol";

interface ISSListing {
    function tokenA() external view returns (address tokenA);
    function tokenB() external view returns (address tokenB);
    function prices() external view returns (uint256 price);
    function liquidityAddressView() external view returns (address liquidityAddress);
}

interface ISSLiquidityTemplate {
    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees);
    function addFees(bool isLong, uint256 amount) external;
}

interface ISSAgent {
    function isValidListing(address listingAddress) external view returns (bool isValid);
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
}

contract CISEntryPartial is ReentrancyGuard {
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

    struct EntryParams {
        address listingAddress;
        uint256 minEntryPrice;
        uint256 maxEntryPrice;
        uint256 initialMargin;
        uint256 excessMargin;
        uint8 leverage;
        uint256 stopLossPrice;
        uint256 takeProfitPrice;
        uint8 positionType;
        address maker;
        bool isNative;
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

    function normalizeMargins(
        address tokenAddr,
        uint256 initMargin,
        uint256 extraMargin
    ) internal view returns (uint256 normInitMargin, uint256 normExtraMargin) {
        normInitMargin = normalizeAmount(tokenAddr, initMargin);
        normExtraMargin = normalizeAmount(tokenAddr, extraMargin);
    }

    function _prepareEntryContext(
        address listingAddress,
        uint256 positionId,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint8 positionType
    ) internal view returns (EntryContext memory context) {
        require(listingAddress != address(0), "Invalid listing address");
        require(initialMargin > 0, "Initial margin must be positive");
        require(positionType <= 1, string(abi.encodePacked("Invalid position type: ", uint2str(positionType))));

        address token = positionType == 0 ? ISSListing(listingAddress).tokenA() : ISSListing(listingAddress).tokenB();
        (uint256 normInitMargin, uint256 normExtraMargin) = normalizeMargins(token, initialMargin, excessMargin);
        context = EntryContext({
            positionId: positionId,
            listingAddress: listingAddress,
            minEntryPrice: minEntryPrice,
            maxEntryPrice: maxEntryPrice,
            initialMargin: initialMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            positionType: positionType,
            maker: msg.sender,
            token: token
        });
    }

    function _validateEntry(
        EntryContext memory context
    ) internal view returns (EntryContext memory validatedContext) {
        require(context.listingAddress != address(0), "Invalid listing address");
        require(context.initialMargin > 0, string(abi.encodePacked("Invalid initial margin: ", uint2str(context.initialMargin))));
        require(context.leverage >= 2 && context.leverage <= 100, string(abi.encodePacked("Invalid leverage: ", uint2str(context.leverage))));
        bool isValid;
        try ISSAgent(agentAddress).isValidListing(context.listingAddress) returns (bool valid) {
            isValid = valid;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Failed to validate listing ", toString(context.listingAddress), ": ", reason)));
        }
        require(isValid, string(abi.encodePacked("Invalid listing: ", toString(context.listingAddress))));
        validatedContext = context;
    }

    function _prepareEntryBase(
        EntryContext memory context,
        string memory entryPriceStr,
        uint256 initMargin,
        uint256 extraMargin,
        uint8 positionType
    ) internal returns (uint256 positionId) {
        require(context.listingAddress != address(0), "Invalid listing address");
        require(context.initialMargin > 0, string(abi.encodePacked("Invalid initial margin: ", uint2str(context.initialMargin))));

        positionId = positionIdCounter++;
        pendingEntries[positionId] = PendingEntry({
            listingAddr: context.listingAddress,
            tokenAddr: context.token,
            positionId: positionId,
            positionType: positionType,
            initialMargin: initMargin,
            extraMargin: extraMargin,
            entryPriceStr: entryPriceStr,
            makerAddress: context.maker,
            leverageVal: uint8(0),
            stopLoss: uint256(0),
            takeProfit: uint256(0),
            normInitMargin: normalizeAmount(context.token, initMargin),
            normExtraMargin: normalizeAmount(context.token, extraMargin)
        });
    }

    function _prepareEntryRisk(
        uint256 positionId,
        uint8 leverage,
        uint256 stopLoss,
        uint256 takeProfit
    ) internal {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, string(abi.encodePacked("Invalid position ID: ", uint2str(positionId))));
        entry.leverageVal = leverage;
        entry.stopLoss = stopLoss;
        entry.takeProfit = takeProfit;
    }

    function _prepareEntryToken(uint256 positionId) internal view {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, string(abi.encodePacked("Invalid position ID: ", uint2str(positionId))));
    }

    function _validateEntryBase(uint256 positionId) internal view {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, string(abi.encodePacked("Invalid position ID: ", uint2str(positionId))));
        require(entry.listingAddr != address(0), string(abi.encodePacked("Invalid listing address: ", toString(entry.listingAddr))));
        require(entry.initialMargin > 0, string(abi.encodePacked("Invalid initial margin: ", uint2str(entry.initialMargin))));
        bool isValid;
        try ISSAgent(agentAddress).isValidListing(entry.listingAddr) returns (bool valid) {
            isValid = valid;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Failed to validate listing ", toString(entry.listingAddr), ": ", reason)));
        }
        require(isValid, string(abi.encodePacked("Invalid listing: ", toString(entry.listingAddr))));
    }

    function _validateEntryRisk(uint256 positionId) internal view {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, string(abi.encodePacked("Invalid position ID: ", uint2str(positionId))));
        require(entry.leverageVal >= 2 && entry.leverageVal <= 100, string(abi.encodePacked("Invalid leverage: ", uint2str(entry.leverageVal))));
    }

    function _updateEntryCore(uint256 positionId) internal {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, string(abi.encodePacked("Invalid position ID: ", uint2str(positionId))));
        ISIStorage.CoreParams memory coreData = ISIStorage.CoreParams({
            makerAddress: entry.makerAddress,
            listingAddress: entry.listingAddr,
            corePositionId: positionId,
            positionType: entry.positionType,
            status1: true,
            status2: 1
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
            revert(string(abi.encodePacked("SIUpdate core failed for position ID ", uint2str(positionId), ": ", reason)));
        }
    }

    function _computeEntryParams(
        uint256 positionId,
        uint256 minPrice
    ) internal view returns (PrepPosition memory params) {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, string(abi.encodePacked("Invalid position ID: ", uint2str(positionId))));
        params.fee = computeFee(entry.initialMargin, entry.leverageVal);
        params.taxedMargin = normalizeAmount(entry.tokenAddr, entry.initialMargin) - params.fee;
        params.leverageAmount = normalizeAmount(entry.tokenAddr, entry.initialMargin) * uint256(entry.leverageVal);
        uint256 marginRatio = (params.taxedMargin + entry.normExtraMargin) / params.leverageAmount;
        params.liquidationPrice = entry.positionType == 0
            ? (marginRatio < minPrice ? minPrice - marginRatio : 0)
            : minPrice + marginRatio;
        params.initialLoan = entry.positionType == 0
            ? params.leverageAmount / minPrice
            : params.leverageAmount * minPrice;
    }

    function _validateLeverageLimit(
        uint256 positionId,
        uint256 initialLoan,
        uint8 leverage
    ) internal view {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, string(abi.encodePacked("Invalid position ID: ", uint2str(positionId))));
        address liquidityAddr;
        try ISSListing(entry.listingAddr).liquidityAddressView() returns (address addr) {
            liquidityAddr = addr;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Failed to get liquidity address for listing ", toString(entry.listingAddr), ": ", reason)));
        }
        (uint256 xLiquid, uint256 yLiquid,,) = ISSLiquidityTemplate(liquidityAddr).liquidityDetailsView();
        uint256 limitPercent = 101 - uint256(leverage);
        uint256 limit = entry.positionType == 0
            ? (yLiquid * limitPercent) / 100
            : (xLiquid * limitPercent) / 100;
        require(initialLoan <= limit, string(abi.encodePacked("Loan exceeds liquidity limit: loan ", uint2str(initialLoan), ", limit ", uint2str(limit))));
    }

    function _parseEntryPriceInternal(
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        address listingAddress
    ) internal view returns (uint256 currentPrice, uint256 minPrice, uint256 maxPrice, uint256 priceAtEntry) {
        try ISSListing(listingAddress).prices() returns (uint256 price) {
            currentPrice = price;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Failed to get prices for listing ", toString(listingAddress), ": ", reason)));
        }
        minPrice = minEntryPrice;
        maxPrice = maxEntryPrice;
        priceAtEntry = 0;
    }

    function _updateEntryParams(uint256 positionId) internal {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, string(abi.encodePacked("Invalid position ID: ", uint2str(positionId))));
        (uint256 currentPrice, uint256 minPrice, uint256 maxPrice, uint256 priceAtEntry) = _parseEntryPriceInternal(
            normalizePrice(entry.tokenAddr, entry.initialMargin),
            normalizePrice(entry.tokenAddr, entry.extraMargin),
            entry.listingAddr
        );
        PrepPosition memory params = _computeEntryParams(positionId, minPrice);
        _validateLeverageLimit(positionId, params.initialLoan, entry.leverageVal);
        _storeEntryParams(positionId, minPrice, maxPrice, params, entry);
    }

    function _storeEntryParams(
        uint256 positionId,
        uint256 minPrice,
        uint256 maxPrice,
        PrepPosition memory params,
        PendingEntry storage entry
    ) internal {
        ISIStorage.PriceParams memory priceData = ISIStorage.PriceParams({
            priceMin: normalizePrice(entry.tokenAddr, minPrice),
            priceMax: normalizePrice(entry.tokenAddr, maxPrice),
            priceAtEntry: 0,
            priceClose: 0
        });
        ISIStorage.MarginParams memory marginData = ISIStorage.MarginParams({
            marginInitial: entry.normInitMargin,
            marginTaxed: params.taxedMargin,
            marginExcess: entry.normExtraMargin
        });
        ISIStorage.LeverageParams memory leverageData = ISIStorage.LeverageParams({
            leverageVal: entry.leverageVal,
            leverageAmount: params.leverageAmount,
            loanInitial: params.initialLoan
        });
        ISIStorage.RiskParams memory riskData = ISIStorage.RiskParams({
            priceLiquidation: params.liquidationPrice,
            priceStopLoss: normalizePrice(entry.tokenAddr, entry.stopLoss),
            priceTakeProfit: normalizePrice(entry.tokenAddr, entry.takeProfit)
        });
        ISIStorage.TokenAndInterestParams memory tokenData = ISIStorage.TokenAndInterestParams({
            token: entry.tokenAddr,
            longIO: params.leverageAmount,
            shortIO: 0,
            timestamp: block.timestamp
        });
        try ISIStorage(storageContract).SIUpdate(
            positionId,
            ISIStorage.CoreParams(address(0), address(0), 0, 0, false, 0),
            priceData,
            marginData,
            leverageData,
            riskData,
            tokenData,
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        ) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("SIUpdate params failed for position ID ", uint2str(positionId), ": ", reason)));
        }
    }

    function _updateEntryIndexes(uint256 positionId) internal {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, string(abi.encodePacked("Invalid position ID: ", uint2str(positionId))));
        ISIStorage.PositionArrayParams memory arrayData = ISIStorage.PositionArrayParams({
            listingAddress: entry.listingAddr,
            positionType: entry.positionType,
            addToPending: true,
            addToActive: false
        });
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
            revert(string(abi.encodePacked("SIUpdate indexes failed for position ID ", uint2str(positionId), ": ", reason)));
        }
    }

    function _finalizeEntryFees(uint256 positionId) internal returns (uint256 actualFee) {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, string(abi.encodePacked("Invalid position ID: ", uint2str(positionId))));
        actualFee = computeFee(entry.initialMargin, entry.leverageVal);
        if (actualFee > 0) {
            address liquidityAddr;
            try ISSListing(entry.listingAddr).liquidityAddressView() returns (address addr) {
                liquidityAddr = addr;
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("Failed to get liquidity address for listing ", toString(entry.listingAddr), ": ", reason)));
            }
            uint256 denormFee = denormalizeAmount(entry.tokenAddr, actualFee);
            uint256 balanceBefore = IERC20(entry.tokenAddr).balanceOf(liquidityAddr);
            try IERC20(entry.tokenAddr).transferFrom(entry.makerAddress, liquidityAddr, denormFee) {
                uint256 balanceAfter = IERC20(entry.tokenAddr).balanceOf(liquidityAddr);
                require(balanceAfter - balanceBefore >= denormFee, string(abi.encodePacked("Fee transfer amount mismatch: expected ", uint2str(denormFee), ", got ", uint2str(balanceAfter - balanceBefore))));
                try ISSLiquidityTemplate(liquidityAddr).addFees(entry.positionType == 0, actualFee) {} catch Error(string memory reason) {
                    revert(string(abi.encodePacked("Failed to add fees for position ID ", uint2str(positionId), ": ", reason)));
                }
                ISIStorage.TokenAndInterestParams memory tokenData = ISIStorage.TokenAndInterestParams({
                    token: entry.tokenAddr,
                    longIO: entry.positionType == 0 ? actualFee : 0,
                    shortIO: entry.positionType == 1 ? actualFee : 0,
                    timestamp: block.timestamp
                });
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
                    revert(string(abi.encodePacked("SIUpdate fees failed for position ID ", uint2str(positionId), ": ", reason)));
                }
                historicalInterestHeight++;
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("Fee transfer failed for position ID ", uint2str(positionId), ": ", reason)));
            }
        }
    }

    function _finalizeEntryTransfer(uint256 positionId, uint256 actualFee, bool isNative) internal returns (uint256 normalizedAmount) {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, string(abi.encodePacked("Invalid position ID: ", uint2str(positionId))));
        uint256 denormInitMargin = denormalizeAmount(entry.tokenAddr, entry.normInitMargin);
        require(denormInitMargin >= actualFee, string(abi.encodePacked("Fee exceeds initial margin: fee ", uint2str(actualFee), ", margin ", uint2str(denormInitMargin))));
        uint256 remainingMargin = denormInitMargin - actualFee;
        uint256 expectedAmount = remainingMargin + entry.extraMargin;
        if (isNative) {
            require(msg.value >= expectedAmount, string(abi.encodePacked("Insufficient native funds: expected ", uint2str(expectedAmount), ", got ", uint2str(msg.value))));
            uint256 balanceBefore = address(executionDriver).balance;
            (bool success, ) = executionDriver.call{value: expectedAmount}("");
            require(success, string(abi.encodePacked("Native transfer failed for position ID ", uint2str(positionId))));
            uint256 balanceAfter = address(executionDriver).balance;
            require(balanceAfter - balanceBefore >= expectedAmount, string(abi.encodePacked("Native transfer amount mismatch: expected ", uint2str(expectedAmount), ", got ", uint2str(balanceAfter - balanceBefore))));
            normalizedAmount = normalizeAmount(entry.tokenAddr, expectedAmount);
        } else {
            uint256 balanceBefore = IERC20(entry.tokenAddr).balanceOf(executionDriver);
            try IERC20(entry.tokenAddr).transferFrom(entry.makerAddress, executionDriver, expectedAmount) {
                uint256 balanceAfter = IERC20(entry.tokenAddr).balanceOf(executionDriver);
                require(balanceAfter - balanceBefore >= expectedAmount, string(abi.encodePacked("Margin transfer amount mismatch: expected ", uint2str(expectedAmount), ", got ", uint2str(balanceAfter - balanceBefore))));
                normalizedAmount = normalizeAmount(entry.tokenAddr, expectedAmount);
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("Margin transfer failed for position ID ", uint2str(positionId), ": ", reason)));
            }
        }
    }

    function _finalizeEntryPosition(uint256 positionId, uint256 io) internal {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, string(abi.encodePacked("Invalid position ID: ", uint2str(positionId))));
        ISIStorage.TokenAndInterestParams memory tokenData = ISIStorage.TokenAndInterestParams({
            token: entry.tokenAddr,
            longIO: entry.positionType == 0 ? io : 0,
            shortIO: entry.positionType == 1 ? io : 0,
            timestamp: block.timestamp
        });
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
            revert(string(abi.encodePacked("SIUpdate position failed for position ID ", uint2str(positionId), ": ", reason)));
        }
        delete pendingEntries[positionId];
    }

    function _finalizeEntry(uint256 positionId, bool isNative) internal {
        uint256 actualFee = _finalizeEntryFees(positionId);
        uint256 io = _finalizeEntryTransfer(positionId, actualFee, isNative);
        _finalizeEntryPosition(positionId, io);
    }

    function computeFee(uint256 initialMargin, uint8 leverage) internal pure returns (uint256 fee) {
        uint256 feePercent = uint256(leverage) - 1;
        fee = (initialMargin * feePercent * DECIMAL_PRECISION) / 100 / DECIMAL_PRECISION;
    }
}