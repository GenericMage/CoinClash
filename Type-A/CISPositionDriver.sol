/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-07-20: Removed redundant _getPositionByIndex function to avoid override error, as it is inherited from CISPositionPartial.sol; version updated to 0.0.4.
 - 2025-07-20: Removed storageContract and agentAddress declarations and setters, as they are now inherited from CISPositionPartial.sol to resolve undeclared identifier errors; version updated to 0.0.3.
 - 2025-07-20: Updated CISPositionDriver to use ISIStorage interface, inlining identifiers, replacing ICSStorage with SIStorage, adapting structs to PositionCoreBase, PositionCoreStatus, PriceParams, MarginParams, LeverageParams, RiskParams, and using SIUpdate; version updated to 0.0.2.
 - 2025-07-20: Created CISPositionDriver contract by adapting SSIsolatedDriver.sol and SSDPositionPartial.sol for isolated margin logic, integrating with CCSPositionDriver.sol's CSStorage-based storage and executionDriver margin transfers. Version set to 0.0.1.
*/

pragma solidity ^0.8.2;

import "./driverUtils/CISPositionPartial.sol";

contract CISPositionDriver is CISPositionPartial {
    // Array to store authorized Hyx addresses
    address[] private hyxes;

    // Events for position actions
    event PositionEntered(uint256 indexed positionId, address indexed maker, uint8 positionType, uint256 minEntryPrice, uint256 maxEntryPrice, address hyx);
    event PositionClosed(uint256 indexed positionId, address indexed maker, uint256 payout);
    event HyxAdded(address indexed hyx);
    event HyxRemoved(address indexed hyx);

    // Modifier to restrict functions to authorized Hyxes
    modifier onlyHyx() {
        bool isHyx = false;
        for (uint256 i = 0; i < hyxes.length; i++) {
            if (hyxes[i] == msg.sender) {
                isHyx = true;
                break;
            }
        }
        require(isHyx, "Caller is not a Hyx");
        _;
    }

    // Constructor initializes state variables
    constructor() {
        positionIdCounter = uint256(0);
    }

    // Adds a new Hyx to the array
    function addHyx(address hyx) external onlyOwner {
        require(hyx != address(0), "Invalid Hyx address");
        for (uint256 i = 0; i < hyxes.length; i++) {
            require(hyxes[i] != hyx, "Hyx already exists");
        }
        hyxes.push(hyx);
        emit HyxAdded(hyx);
    }

    // Removes a Hyx from the array
    function removeHyx(address hyx) external onlyOwner {
        require(hyx != address(0), "Invalid Hyx address");
        for (uint256 i = 0; i < hyxes.length; i++) {
            if (hyxes[i] == hyx) {
                hyxes[i] = hyxes[hyxes.length - 1];
                hyxes.pop();
                emit HyxRemoved(hyx);
                return;
            }
        }
        revert("Hyx not found");
    }

    // Returns the list of Hyxes
    function getHyxes() external view returns (address[] memory) {
        return hyxes;
    }

    // Initiates position entry
    function _initiateEntry(
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        uint8 positionType
    ) internal nonReentrant returns (uint256 positionId) {
        positionId = _getPositionCount() + 1;
        EntryContext memory context = _prepareEntryContext(
            listingAddress,
            positionId,
            minEntryPrice,
            maxEntryPrice,
            initialMargin,
            excessMargin,
            leverage,
            positionType
        );
        context = _validateEntry(context);
        string memory entryPriceStr = string(abi.encodePacked(uint2str(context.minEntryPrice), "-", uint2str(context.maxEntryPrice)));
        positionId = _prepareEntryBase(context, entryPriceStr, context.initialMargin, context.excessMargin, context.positionType);
        _prepareEntryRisk(positionId, leverage, stopLossPrice, takeProfitPrice);
        _prepareEntryToken(positionId);
        _validateEntryBase(positionId);
        _validateEntryRisk(positionId);
        _updateEntryCore(positionId);
        _updateEntryParams(positionId);
        _updateEntryIndexes(positionId);
        _finalizeEntry(positionId);
        emit PositionEntered(positionId, context.maker, context.positionType, context.minEntryPrice, context.maxEntryPrice, address(0));
        return positionId;
    }

    // Enters a long position
    function enterLong(
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external {
        _initiateEntry(
            listingAddress,
            minEntryPrice,
            maxEntryPrice,
            initialMargin,
            excessMargin,
            leverage,
            stopLossPrice,
            takeProfitPrice,
            0
        );
    }

    // Enters a short position
    function enterShort(
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external {
        _initiateEntry(
            listingAddress,
            minEntryPrice,
            maxEntryPrice,
            initialMargin,
            excessMargin,
            leverage,
            stopLossPrice,
            takeProfitPrice,
            1
        );
    }

    // Closes a long position
    function closeLongPosition(uint256 positionId) external nonReentrant {
        (PositionCoreBase memory coreBase, PositionCoreStatus memory coreStatus,,,,,) = _getPositionByIndex(positionId);
        require(coreBase.positionId == positionId, "Invalid position");
        require(coreStatus.status2 == 0, "Position closed");
        require(coreBase.makerAddress == msg.sender, "Not maker");
        address tokenB = ISSListing(coreBase.listingAddress).tokenB();
        uint256 payout = _computePayoutLong(positionId, coreBase.listingAddress, tokenB);
        (, , , MarginParams memory margin,,,) = _getPositionByIndex(positionId);
        _deductMarginAndRemoveToken(
            coreBase.makerAddress,
            ISSListing(coreBase.listingAddress).tokenA(),
            margin.marginTaxed,
            margin.marginExcess
        );
        _executePayoutUpdate(positionId, coreBase.listingAddress, payout, coreBase.positionType, coreBase.makerAddress, tokenB);
        _updatePositionStorage(positionId, coreBase, margin, tokenB);
        _removePositionIndex(positionId, coreBase.positionType, coreBase.listingAddress);
        emit PositionClosed(positionId, coreBase.makerAddress, payout);
    }

    // Closes a short position
    function closeShortPosition(uint256 positionId) external nonReentrant {
        (PositionCoreBase memory coreBase, PositionCoreStatus memory coreStatus,,,,,) = _getPositionByIndex(positionId);
        require(coreBase.positionId == positionId, "Invalid position");
        require(coreStatus.status2 == 0, "Position closed");
        require(coreBase.makerAddress == msg.sender, "Not maker");
        address tokenA = ISSListing(coreBase.listingAddress).tokenA();
        uint256 payout = _computePayoutShort(positionId, coreBase.listingAddress, tokenA);
        (, , , MarginParams memory margin,,,) = _getPositionByIndex(positionId);
        _deductMarginAndRemoveToken(
            coreBase.makerAddress,
            ISSListing(coreBase.listingAddress).tokenB(),
            margin.marginTaxed,
            margin.marginExcess
        );
        _executePayoutUpdate(positionId, coreBase.listingAddress, payout, coreBase.positionType, coreBase.makerAddress, tokenA);
        _updatePositionStorage(positionId, coreBase, margin, tokenA);
        _removePositionIndex(positionId, coreBase.positionType, coreBase.listingAddress);
        emit PositionClosed(positionId, coreBase.makerAddress, payout);
    }

    // Allows any address to create positions on behalf of a maker
    function drive(
        address maker,
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        uint8 positionType
    ) external nonReentrant {
        require(maker != address(0), "Invalid maker address");
        require(positionType <= 1, "Invalid position type");
        uint256 positionId = _getPositionCount() + 1;
        EntryContext memory context = _prepareEntryContext(
            listingAddress,
            positionId,
            minEntryPrice,
            maxEntryPrice,
            initialMargin,
            excessMargin,
            leverage,
            positionType
        );
        context.maker = maker;
        context = _validateEntry(context);
        string memory entryPriceStr = string(abi.encodePacked(uint2str(context.minEntryPrice), "-", uint2str(context.maxEntryPrice)));
        positionId = _prepareEntryBase(context, entryPriceStr, context.initialMargin, context.excessMargin, context.positionType);
        _prepareEntryRisk(positionId, leverage, stopLossPrice, takeProfitPrice);
        _prepareEntryToken(positionId);
        _validateEntryBase(positionId);
        _validateEntryRisk(positionId);
        _updateEntryCore(positionId);
        _updateEntryParams(positionId);
        _updateEntryIndexes(positionId);
        _finalizeEntry(positionId);
        emit PositionEntered(positionId, maker, positionType, minEntryPrice, maxEntryPrice, msg.sender);
    }

    // Allows Hyxes to close a specific position on behalf of a maker
    function drift(uint256 positionId, address maker) external nonReentrant onlyHyx {
        (PositionCoreBase memory coreBase, PositionCoreStatus memory coreStatus,,,,,) = _getPositionByIndex(positionId);
        require(coreBase.positionId == positionId, "Invalid position");
        require(coreStatus.status2 == 0, "Position closed");
        require(coreBase.makerAddress == maker, "Maker mismatch");
        (uint256 payout, address token) = _prepDriftPayout(positionId, coreBase);
        (, , , MarginParams memory margin,,,) = _getPositionByIndex(positionId);
        address marginToken = coreBase.positionType == 0 ? ISSListing(coreBase.listingAddress).tokenA() : ISSListing(coreBase.listingAddress).tokenB();
        _deductMarginAndRemoveToken(
            coreBase.makerAddress,
            marginToken,
            margin.marginTaxed,
            margin.marginExcess
        );
        _prepDriftPayoutUpdate(positionId, coreBase, payout, token);
        _updatePositionStorage(positionId, coreBase, margin, token);
        _removePositionIndex(positionId, coreBase.positionType, coreBase.listingAddress);
        emit PositionClosed(positionId, maker, payout);
    }

    // Helper function to get position count
    function _getPositionCount() internal view returns (uint256) {
        (bool success, bytes memory data) = storageContract.staticcall(abi.encodeWithSignature("positionCount()"));
        require(success, "Failed to get position count");
        return abi.decode(data, (uint256));
    }

    // Helper function to remove position index
    function _removePositionIndex(uint256 positionId, uint8 positionType, address listingAddress) internal {
        (bool success,) = storageContract.call(
            abi.encodeWithSignature("removePositionIndex(uint256,uint8,address)", positionId, positionType, listingAddress)
        );
        require(success, "Failed to remove position index");
    }
}