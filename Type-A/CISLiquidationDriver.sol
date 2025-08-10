// SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version 0.0.3:
// - 2025-08-10: Split addExcessMargin into addExcessTokenMargin and addExcessNativeMargin for ERC20 and ETH handling.
// - No other functional changes.

import "./driverUtils/CISLiquidationPartial.sol";

contract CISLiquidationDriver is CISLiquidationPartial {
	
    // Constructor initializes storage contract
    constructor(address storageContractAddress) CISLiquidationPartial(storageContractAddress) {
        if (storageContractAddress == address(0)) {
            emit ErrorLogged("Constructor: Storage address is zero");
            revert("Constructor: Invalid storage address");
        }
    }

    // Executes active positions
    function executeExits(address listingAddress, uint256 maxIterations) external nonReentrant {
        if (listingAddress == address(0)) {
            emit ErrorLogged("executeExits: Listing address is zero");
            revert("executeExits: Invalid listing address");
        }
        _executeExits(listingAddress, maxIterations); // Executes active positions
    }

    // Adds excess margin using ERC20 token
    function addExcessTokenMargin(uint256 positionId, uint256 amount, address token) external nonReentrant {
        if (amount == 0) {
            emit ErrorLogged(string(abi.encodePacked("addExcessTokenMargin: Amount is zero for position ", positionId)));
            revert("addExcessTokenMargin: Invalid amount");
        }
        ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core position data
        if (coreBase.positionId != positionId) {
            emit ErrorLogged(string(abi.encodePacked("addExcessTokenMargin: Position ", positionId, " does not exist")));
            revert("addExcessTokenMargin: Invalid position");
        }
        if (coreBase.makerAddress != msg.sender) {
            emit ErrorLogged(string(abi.encodePacked("addExcessTokenMargin: Caller not maker for position ", positionId)));
            revert("addExcessTokenMargin: Not maker");
        }
        ISIStorage.PositionCoreStatus memory coreStatus = _storageContract.positionCoreStatus(positionId); // Retrieves position status
        if (coreStatus.status2 != 0) {
            emit ErrorLogged(string(abi.encodePacked("addExcessTokenMargin: Position ", positionId, " is closed")));
            revert("addExcessTokenMargin: Position closed");
        }
        if (token != _storageContract.positionToken(positionId)) {
            emit ErrorLogged(string(abi.encodePacked("addExcessTokenMargin: Token mismatch for position ", positionId)));
            revert("addExcessTokenMargin: Invalid token");
        }
        uint256 normalizedAmount = normalizeAmount(token, amount); // Normalizes amount based on token decimals
        _validateExcessMargin(positionId, normalizedAmount); // Validates margin against leverage
        uint256 actualAmount = _transferExcessMargin(positionId, amount, token, coreBase.listingAddress); // Transfers ERC20 margin
        uint256 actualNormalized = normalizeAmount(token, actualAmount); // Normalizes actual amount
        _updateMarginAndInterest(positionId, actualNormalized, coreBase.positionType, coreBase.listingAddress); // Updates margin and interest
        _updateLiquidationPrice(positionId, coreBase.positionType); // Recalculates liquidation price
        emit ExcessMarginAdded(positionId, msg.sender, amount); // Emits event
    }

    // Adds excess margin using native ETH
    function addExcessNativeMargin(uint256 positionId) external payable nonReentrant {
        uint256 amount = msg.value; // Uses msg.value for ETH amount
        if (amount == 0) {
            emit ErrorLogged(string(abi.encodePacked("addExcessNativeMargin: Amount is zero for position ", positionId)));
            revert("addExcessNativeMargin: Invalid amount");
        }
        ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core position data
        if (coreBase.positionId != positionId) {
            emit ErrorLogged(string(abi.encodePacked("addExcessNativeMargin: Position ", positionId, " does not exist")));
            revert("addExcessNativeMargin: Invalid position");
        }
        if (coreBase.makerAddress != msg.sender) {
            emit ErrorLogged(string(abi.encodePacked("addExcessNativeMargin: Caller not maker for position ", positionId)));
            revert("addExcessNativeMargin: Not maker");
        }
        ISIStorage.PositionCoreStatus memory coreStatus = _storageContract.positionCoreStatus(positionId); // Retrieves position status
        if (coreStatus.status2 != 0) {
            emit ErrorLogged(string(abi.encodePacked("addExcessNativeMargin: Position ", positionId, " is closed")));
            revert("addExcessNativeMargin: Position closed");
        }
        address token = _storageContract.positionToken(positionId); // Retrieves position token
        if (token != address(0)) {
            emit ErrorLogged(string(abi.encodePacked("addExcessNativeMargin: Position ", positionId, " does not use ETH")));
            revert("addExcessNativeMargin: Invalid token");
        }
        uint256 normalizedAmount = amount * DECIMAL_PRECISION; // Normalizes ETH amount (18 decimals)
        _validateExcessMargin(positionId, normalizedAmount); // Validates margin against leverage
        (bool success, ) = coreBase.listingAddress.call{value: amount}(""); // Transfers ETH to listing
        if (!success) {
            emit ErrorLogged(string(abi.encodePacked("addExcessNativeMargin: ETH transfer failed for position ", positionId)));
            revert("addExcessNativeMargin: ETH transfer failed");
        }
        _updateMarginAndInterest(positionId, normalizedAmount, coreBase.positionType, coreBase.listingAddress); // Updates margin and interest
        _updateLiquidationPrice(positionId, coreBase.positionType); // Recalculates liquidation price
        emit ExcessMarginAdded(positionId, msg.sender, amount); // Emits event
    }

    // Withdraws margin from a position
    function pullMargin(uint256 positionId, uint256 amount) external nonReentrant {
        if (amount == 0) {
            emit ErrorLogged(string(abi.encodePacked("pullMargin: Amount is zero for position ", positionId)));
            revert("pullMargin: Invalid amount");
        }
        ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core position data
        if (coreBase.positionId != positionId) {
            emit ErrorLogged(string(abi.encodePacked("pullMargin: Position ", positionId, " does not exist")));
            revert("pullMargin: Invalid position");
        }
        if (coreBase.makerAddress != msg.sender) {
            emit ErrorLogged(string(abi.encodePacked("pullMargin: Caller not maker for position ", positionId)));
            revert("pullMargin: Not maker");
        }
        ISIStorage.PositionCoreStatus memory coreStatus = _storageContract.positionCoreStatus(positionId); // Retrieves position status
        if (coreStatus.status2 != 0) {
            emit ErrorLogged(string(abi.encodePacked("pullMargin: Position ", positionId, " is closed")));
            revert("pullMargin: Position closed");
        }
        address token = _storageContract.positionToken(positionId); // Retrieves position token
        ISIStorage.MarginParams memory margin = _storageContract.marginParams(positionId); // Retrieves margin data
        uint256 normalizedAmount = normalizeAmount(token, amount); // Normalizes amount
        if (normalizedAmount > margin.marginExcess) {
            emit ErrorLogged(string(abi.encodePacked("pullMargin: Insufficient excess margin for position ", positionId)));
            revert("pullMargin: Insufficient excess margin");
        }
        _storageContract.SIUpdate(
            positionId,
            ISIStorage.CoreParams(address(0), address(0), 0, 0, false, 0),
            ISIStorage.PriceParams(0, 0, 0, 0),
            ISIStorage.MarginParams(margin.marginInitial, margin.marginTaxed, margin.marginExcess - normalizedAmount),
            ISIStorage.LeverageParams(0, 0, 0),
            ISIStorage.RiskParams(0, 0, 0),
            ISIStorage.TokenAndInterestParams(address(0), 0, 0, 0),
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        ); // Updates margin
        _updateLiquidationPrice(positionId, coreBase.positionType); // Recalculates liquidation price
        _executeMarginPayout(coreBase.listingAddress, msg.sender, amount); // Executes payout
        _updateHistoricalInterest(normalizedAmount, coreBase.positionType, coreBase.listingAddress, false); // Updates historical interest
    }
}