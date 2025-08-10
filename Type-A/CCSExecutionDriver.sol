/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-08-06: Removed addExcessMargin and pullMargin, extracted to CCSExtraDriver.sol. Incremented version to 0.0.17.
 - 2025-08-06: Removed override from executeEntries, updated call to renamed _executeEntriesInternal in CCSExecutionPartial.sol to resolve visibility mismatch and comply with style guide. Incremented version to 0.0.16.
 - 2025-08-06: Removed override from executeEntries to comply with style guide prohibiting virtuals/overrides. Incremented version to 0.0.15.
 - 2025-08-06: Fixed typo in pullMargin function (positionкакCore1 to positionCore1). Incremented version to 0.0.14.
 - 2025-08-06: Fixed override issues for executeEntries by adding virtual to CCSExecutionPartial and override to CCSExecutionDriver. Incremented version to 0.0.13.
 - 2025-08-06: Created CCSExecutionDriver, extracted executeEntries, TP/SL, and margin adjustment logic from CCSExecutionDriver.sol. Aligned with updated ICSStorage and ISSListing interfaces, used isValidListing for validation. Version set to 0.0.12.
*/

pragma solidity ^0.8.2;

import "./driverUtils/CCSExecutionPartial.sol";

contract CCSExecutionDriver is CCSExecutionPartial {
    mapping(address => bool) private _hyxes;
    address[] private _hyxList;

    event StopLossUpdated(uint256 indexed positionId, uint256 newStopLossPrice, uint256 currentPrice, uint256 timestamp);
    event TakeProfitUpdated(uint256 indexed positionId, uint256 newTakeProfitPrice, uint256 currentPrice, uint256 timestamp);
    event HyxAdded(address indexed hyx);
    event HyxRemoved(address indexed hyx);

    constructor(address _storageContract, address _orderRouter) CCSExecutionPartial(_storageContract) {
        require(_storageContract != address(0), "Storage contract address cannot be zero"); // Validates storage contract
        require(_orderRouter != address(0), "Order router address cannot be zero"); // Validates order router
        orderRouter = ICCOrderRouter(_orderRouter);
    }

    function addHyx(address hyx) external onlyOwner {
        require(hyx != address(0), "Hyx address cannot be zero"); // Validates hyx address
        require(!_hyxes[hyx], "Hyx address already authorized"); // Prevents duplicate
        _hyxes[hyx] = true;
        _hyxList.push(hyx);
        emit HyxAdded(hyx);
    }

    function removeHyx(address hyx) external onlyOwner {
        require(hyx != address(0), "Hyx address cannot be zero"); // Validates hyx address
        require(_hyxes[hyx], "Hyx address not authorized"); // Ensures hyx is authorized
        _hyxes[hyx] = false;
        for (uint256 i = 0; i < _hyxList.length; i++) {
            if (_hyxList[i] == hyx) {
                _hyxList[i] = _hyxList[_hyxList.length - 1];
                _hyxList.pop();
                break;
            }
        }
        emit HyxRemoved(hyx);
    }

    function getHyxes() external view returns (address[] memory hyxAddresses) {
        return _hyxList; // Returns authorized hyx addresses
    }

    function updateSL(uint256 positionId, uint256 newStopLossPrice) external nonReentrant {
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
        require(core1.positionId == positionId, "Position ID does not exist"); // Validates position
        require(core2.status2 == 0, "Position is already closed"); // Ensures open
        require(core1.makerAddress == msg.sender, "Caller is not the position maker"); // Validates maker
        require(newStopLossPrice >= 0, "Stop-loss price cannot be negative"); // Validates stop-loss
        address token = storageContract.positionToken(positionId);
        require(token != address(0), "Position token address cannot be zero"); // Validates token
        uint256 currentPrice = normalizePrice(token, ISSListing(core1.listingAddress).prices(0));
        ICSStorage.PriceParams1 memory price1 = storageContract.priceParams1(positionId);
        _updateSL(positionId, normalizePrice(token, newStopLossPrice), core1.listingAddress, core1.positionType, price1.minPrice, price1.maxEntryPrice, currentPrice);
        emit StopLossUpdated(positionId, newStopLossPrice, currentPrice, block.timestamp);
    }

    function updateTP(uint256 positionId, uint256 newTakeProfitPrice) external nonReentrant {
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
        require(core1.positionId == positionId, "Position ID does not exist"); // Validates position
        require(core2.status2 == 0, "Position is already closed"); // Ensures open
        require(core1.makerAddress == msg.sender, "Caller is not the position maker"); // Validates maker
        require(newTakeProfitPrice >= 0, "Take-profit price cannot be negative"); // Validates take-profit
        address token = storageContract.positionToken(positionId);
        require(token != address(0), "Position token address cannot be zero"); // Validates token
        uint256 currentPrice = normalizePrice(token, ISSListing(core1.listingAddress).prices(0));
        ICSStorage.PriceParams1 memory price1 = storageContract.priceParams1(positionId);
        _updateTP(positionId, normalizePrice(token, newTakeProfitPrice), core1.listingAddress, core1.positionType, price1.priceAtEntry, price1.maxEntryPrice, currentPrice);
        emit TakeProfitUpdated(positionId, newTakeProfitPrice, currentPrice, block.timestamp);
    }

    function executeEntries(address listingAddress, uint256 maxIterations) external nonReentrant {
        _executeEntriesInternal(listingAddress, maxIterations);
    }
}