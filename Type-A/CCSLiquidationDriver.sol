/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-08-07: Added _executeMarginPayout and _reduceMakerMargin to CCSLiquidationPartial.sol to resolve undeclared identifiers in pullMargin. Incremented version to 0.0.25.
 - 2025-08-07: Moved closeLongPosition, closeShortPosition, closeAllLongs, closeAllShorts, and events AllLongsClosed, AllShortsClosed to CCSExtraDriver.sol. Incremented version to 0.0.24.
 - 2025-08-07: Added missing events AllLongsClosed and AllShortsClosed to fix undeclared identifier errors. Incremented version to 0.0.23.
 - 2025-08-06: Removed unused _hyxes functionality (mappings, arrays, addHyx, removeHyx, getHyxes, events). Moved cancellation functions (cancelPosition, cancelAllLongs, cancelAllShorts) and logic (_prepareCancelPosition, _updatePositionParams, _updateMarginAndIndex, PositionCancelled event) to CCSExtraDriver.sol and CCSExtraPartial.sol. Incremented version to 0.0.22.
 - 2025-08-06: Updated executeExits to call _executeExitsInternal. Incremented version to 0.0.21.
 - 2025-08-06: Removed _hyxes restriction from executeExits. Incremented version to 0.0.20.
*/

pragma solidity ^0.8.2;

import "./driverUtils/CCSLiquidationPartial.sol";

contract CCSLiquidationDriver is CCSLiquidationPartial {
    constructor(address _storageContract, address _orderRouter) CCSLiquidationPartial(_storageContract) {
        require(_storageContract != address(0), "Storage contract address cannot be zero"); // Validates storage contract
        require(_orderRouter != address(0), "Order router address cannot be zero"); // Validates order router
        orderRouter = ICCOrderRouter(_orderRouter);
    }

    function addExcessTokenMargin(address listingAddress, bool tokenA, uint256 amount, address maker) external nonReentrant {
        require(amount > 0, "Margin amount must be greater than zero"); // Validates amount
        require(maker != address(0), "Maker address cannot be zero"); // Validates maker
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        (bool isValid, ICCAgent.ListingDetails memory details) = ICCAgent(agentAddress).isValidListing(listingAddress);
        require(isValid, "Listing is not valid"); // Ensures valid listing
        address token = tokenA ? details.tokenA : details.tokenB;
        require(token != address(0), "Selected token address cannot be zero"); // Validates token
        uint256 normalizedAmount = _transferMarginToListing(token, amount, listingAddress);
        _updateListingMargin(listingAddress, normalizedAmount);
        _updateMakerMargin(maker, token, normalizedAmount);
        _updatePositionLiquidationPrices(maker, token, listingAddress);
        _updateHistoricalInterest(normalizedAmount, tokenA ? 0 : 1, listingAddress);
    }

    function addExcessNativeMargin(address listingAddress, bool tokenA, address maker) external payable nonReentrant {
        require(msg.value > 0, "Margin amount must be greater than zero"); // Validates amount
        require(maker != address(0), "Maker address cannot be zero"); // Validates maker
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        (bool isValid, ICCAgent.ListingDetails memory details) = ICCAgent(agentAddress).isValidListing(listingAddress);
        require(isValid, "Listing is not valid"); // Ensures valid listing
        address token = tokenA ? details.tokenA : details.tokenB;
        require(token == address(0), "Native margin requires WETH as token"); // Validates WETH
        uint256 normalizedAmount = normalizeAmount(token, msg.value);
        (bool success, ) = listingAddress.call{value: msg.value}("");
        require(success, "Native margin transfer failed"); // Checks transfer success
        _updateListingMargin(listingAddress, normalizedAmount);
        _updateMakerMargin(maker, token, normalizedAmount);
        _updatePositionLiquidationPrices(maker, token, listingAddress);
        _updateHistoricalInterest(normalizedAmount, tokenA ? 0 : 1, listingAddress);
    }

    function pullMargin(address listingAddress, bool tokenA, uint256 amount) external nonReentrant {
        (address token, uint256 normalizedAmount) = _validateAndNormalizePullMargin(listingAddress, tokenA, amount);
        uint256 positionCount = storageContract.positionCount();
        for (uint256 i = 1; i <= positionCount; i++) {
            ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(i);
            ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(i);
            if (
                core1.positionId == i &&
                core2.status2 == 0 &&
                core1.makerAddress == msg.sender &&
                storageContract.positionToken(i) == token &&
                core1.listingAddress == listingAddress
            ) {
                revert("Cannot withdraw margin with open or pending positions"); // Reverts if positions exist
            }
        }
        _reduceMakerMargin(msg.sender, token, normalizedAmount);
        _executeMarginPayout(listingAddress, msg.sender, amount);
        _updateHistoricalInterest(normalizedAmount, tokenA ? 0 : 1, listingAddress);
    }

    function executeExits(address listingAddress, uint256 maxIterations) external nonReentrant {
        _executeExitsInternal(listingAddress, maxIterations);
    }
}