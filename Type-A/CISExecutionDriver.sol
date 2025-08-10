// SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version 0.0.8:
// - 2025-08-08: Updated to use executeEntries instead of executePositions, focusing on pending position execution and TP/SL updates.
// - 2025-08-08: Segregated into ExecutionDriver, retaining executeEntries, updateSL, updateTP, and related events.
// - 2025-08-08: Updated ISIStorage interface to match ISSIStorage, using CoreParams, TokenAndInterestParams, PositionArrayParams for SIUpdate.
// - 2025-08-08: Replaced hyphen-delimited strings with structured array data in SIUpdate calls.
// - 2025-08-08: Removed hyx functionality (_hyxes, _hyxList, addHyx, removeHyx, getHyxesView, related events) as unused.
// - 2025-08-08: Added detailed error messages with specific details (e.g., position IDs).
// - 2025-08-08: Added ErrorLogged event and restructured functions for early error checking.
// - Compatible with CISExecutionPartial v0.0.10. 

import "./driverUtils/CISExecutionPartial.sol";

contract CISExecutionDriver is CISExecutionPartial {
    // Events
    event StopLossUpdated(uint256 indexed positionId, uint256 newStopLossPrice, uint256 currentPrice, uint256 timestamp); // Emitted when stop-loss is updated
    event TakeProfitUpdated(uint256 indexed positionId, uint256 newTakeProfitPrice, uint256 currentPrice, uint256 timestamp); // Emitted when take-profit is updated

    // Constructor initializes storage and order router
    constructor(address storageContractAddress, address orderRouterAddress) CISExecutionPartial(storageContractAddress) {
        if (storageContractAddress == address(0)) {
            emit ErrorLogged("Constructor: Storage address is zero");
            revert("Constructor: Invalid storage address");
        }
        if (orderRouterAddress == address(0)) {
            emit ErrorLogged("Constructor: Order router address is zero");
            revert("Constructor: Invalid order router address");
        }
        orderRouter = ICCOrderRouter(orderRouterAddress); // Sets order router directly
    }

    // Executes pending positions
    function executeEntries(address listingAddress, uint256 maxIterations) external nonReentrant {
        if (listingAddress == address(0)) {
            emit ErrorLogged("executeEntries: Listing address is zero");
            revert("executeEntries: Invalid listing address");
        }
        _executeEntries(listingAddress, maxIterations); // Executes pending positions
    }

    // Updates stop-loss price for a position
    function updateSL(uint256 positionId, uint256 newStopLossPrice) external nonReentrant {
        ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core position data
        if (coreBase.positionId != positionId) {
            emit ErrorLogged(string(abi.encodePacked("updateSL: Position ", positionId, " does not exist")));
            revert("updateSL: Invalid position");
        }
        if (coreBase.makerAddress != msg.sender) {
            emit ErrorLogged(string(abi.encodePacked("updateSL: Caller not maker for position ", positionId)));
            revert("updateSL: Not maker");
        }
        ISIStorage.PositionCoreStatus memory coreStatus = _storageContract.positionCoreStatus(positionId); // Retrieves position status
        if (coreStatus.status2 != 0) {
            emit ErrorLogged(string(abi.encodePacked("updateSL: Position ", positionId, " is closed")));
            revert("updateSL: Position closed");
        }
        address token = _storageContract.positionToken(positionId); // Retrieves position token
        uint256 currentPrice = normalizePrice(token, ISSListing(coreBase.listingAddress).prices(coreBase.listingAddress)); // Normalizes current price
        if (coreBase.positionType == 0) {
            if (newStopLossPrice != 0 && newStopLossPrice >= currentPrice) {
                emit ErrorLogged(string(abi.encodePacked("updateSL: Invalid stop-loss price for long position ", positionId)));
                revert("updateSL: Invalid SL for long");
            }
        } else {
            if (newStopLossPrice != 0 && newStopLossPrice <= currentPrice) {
                emit ErrorLogged(string(abi.encodePacked("updateSL: Invalid stop-loss price for short position ", positionId)));
                revert("updateSL: Invalid SL for short");
            }
        }
        _updateSL(positionId, normalizePrice(token, newStopLossPrice)); // Updates stop-loss
        emit StopLossUpdated(positionId, newStopLossPrice, currentPrice, block.timestamp); // Emits event
    }

    // Updates take-profit price for a position
    function updateTP(uint256 positionId, uint256 newTakeProfitPrice) external nonReentrant {
        ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core position data
        if (coreBase.positionId != positionId) {
            emit ErrorLogged(string(abi.encodePacked("updateTP: Position ", positionId, " does not exist")));
            revert("updateTP: Invalid position");
        }
        if (coreBase.makerAddress != msg.sender) {
            emit ErrorLogged(string(abi.encodePacked("updateTP: Caller not maker for position ", positionId)));
            revert("updateTP: Not maker");
        }
        ISIStorage.PositionCoreStatus memory coreStatus = _storageContract.positionCoreStatus(positionId); // Retrieves position status
        if (coreStatus.status2 != 0) {
            emit ErrorLogged(string(abi.encodePacked("updateTP: Position ", positionId, " is closed")));
            revert("updateTP: Position closed");
        }
        address token = _storageContract.positionToken(positionId); // Retrieves position token
        uint256 currentPrice = normalizePrice(token, ISSListing(coreBase.listingAddress).prices(coreBase.listingAddress)); // Normalizes current price
        ISIStorage.PriceParams memory price = _storageContract.priceParams(positionId); // Retrieves price data
        if (coreBase.positionType == 0) {
            if (newTakeProfitPrice != 0 && newTakeProfitPrice <= price.priceAtEntry) {
                emit ErrorLogged(string(abi.encodePacked("updateTP: Invalid take-profit price for long position ", positionId)));
                revert("updateTP: Invalid TP for long");
            }
        } else {
            if (newTakeProfitPrice != 0 && newTakeProfitPrice >= price.priceAtEntry) {
                emit ErrorLogged(string(abi.encodePacked("updateTP: Invalid take-profit price for short position ", positionId)));
                revert("updateTP: Invalid TP for short");
            }
        }
        _updateTP(positionId, normalizePrice(token, newTakeProfitPrice)); // Updates take-profit
        emit TakeProfitUpdated(positionId, newTakeProfitPrice, currentPrice, block.timestamp); // Emits event
    }
}