/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-08-08: Refactored _initiateEntry into _initContext, _validateAndStore, _finalizeEntrySteps using EntryParams struct to fix stack overflow (v0.0.3).
 - 2025-08-08: Split enterLong, enterShort, and drive into native and token variants; refactored _initiateEntry to handle native/token transfers (v0.0.2).
 - 2025-08-07: Created CISEntryDriver by splitting CISPositionDriver.sol (v0.0.6); included entry functions and Hyx management (v0.0.1).
*/

pragma solidity ^0.8.2;

import "./driverUtils/CISEntryPartial.sol";

contract CISEntryDriver is CISEntryPartial {
    address[] private hyxes;

    event PositionEntered(uint256 indexed positionId, address indexed maker, uint8 positionType, uint256 minEntryPrice, uint256 maxEntryPrice, address hyx);
    event HyxAdded(address indexed hyx);
    event HyxRemoved(address indexed hyx);

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

    constructor() {
        positionIdCounter = uint256(0);
    }

    function addHyx(address hyx) external onlyOwner {
        require(hyx != address(0), "Invalid Hyx address");
        for (uint256 i = 0; i < hyxes.length; i++) {
            require(hyxes[i] != hyx, "Hyx already exists");
        }
        hyxes.push(hyx);
        emit HyxAdded(hyx);
    }

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

    function getHyxes() external view returns (address[] memory hyxesList) {
        hyxesList = hyxes;
    }

    function _initContext(EntryParams memory params) internal returns (uint256 positionId, EntryContext memory context) {
        // Initializes entry context and position ID
        require(params.listingAddress != address(0), "Invalid listing address");
        require(params.initialMargin > 0, "Initial margin must be positive");
        require(params.positionType <= 1, string(abi.encodePacked("Invalid position type: ", uint2str(params.positionType))));
        positionId = positionIdCounter + 1;
        context = _prepareEntryContext(
            params.listingAddress,
            positionId,
            params.minEntryPrice,
            params.maxEntryPrice,
            params.initialMargin,
            params.excessMargin,
            params.leverage,
            params.positionType
        );
        context.maker = params.maker;
    }

    function _validateAndStore(EntryContext memory context, uint256 positionId, uint256 stopLossPrice, uint256 takeProfitPrice) internal returns (string memory entryPriceStr) {
        // Validates entry and stores base and risk parameters
        context = _validateEntry(context);
        entryPriceStr = string(abi.encodePacked(uint2str(context.minEntryPrice), "-", uint2str(context.maxEntryPrice)));
        positionId = _prepareEntryBase(context, entryPriceStr, context.initialMargin, context.excessMargin, context.positionType);
        _prepareEntryRisk(positionId, context.leverage, stopLossPrice, takeProfitPrice);
        _prepareEntryToken(positionId);
        _validateEntryBase(positionId);
        _validateEntryRisk(positionId);
    }

    function _finalizeEntrySteps(uint256 positionId, bool isNative) internal {
        // Finalizes entry with core updates, params, and indexes
        _updateEntryCore(positionId);
        _updateEntryParams(positionId);
        _updateEntryIndexes(positionId);
        _finalizeEntry(positionId, isNative);
    }

    function enterLongNative(
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external payable {
        // Initiates a long position with native gas token
        EntryParams memory params = EntryParams({
            listingAddress: listingAddress,
            minEntryPrice: minEntryPrice,
            maxEntryPrice: maxEntryPrice,
            initialMargin: initialMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            positionType: 0,
            maker: msg.sender,
            isNative: true
        });
        (uint256 positionId, EntryContext memory context) = _initContext(params);
        string memory entryPriceStr = _validateAndStore(context, positionId, stopLossPrice, takeProfitPrice);
        _finalizeEntrySteps(positionId, params.isNative);
        emit PositionEntered(positionId, params.maker, params.positionType, params.minEntryPrice, params.maxEntryPrice, address(0));
    }

    function enterLongToken(
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external {
        // Initiates a long position with ERC20 token
        EntryParams memory params = EntryParams({
            listingAddress: listingAddress,
            minEntryPrice: minEntryPrice,
            maxEntryPrice: maxEntryPrice,
            initialMargin: initialMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            positionType: 0,
            maker: msg.sender,
            isNative: false
        });
        (uint256 positionId, EntryContext memory context) = _initContext(params);
        string memory entryPriceStr = _validateAndStore(context, positionId, stopLossPrice, takeProfitPrice);
        _finalizeEntrySteps(positionId, params.isNative);
        emit PositionEntered(positionId, params.maker, params.positionType, params.minEntryPrice, params.maxEntryPrice, address(0));
    }

    function enterShortNative(
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external payable {
        // Initiates a short position with native gas token
        EntryParams memory params = EntryParams({
            listingAddress: listingAddress,
            minEntryPrice: minEntryPrice,
            maxEntryPrice: maxEntryPrice,
            initialMargin: initialMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            positionType: 1,
            maker: msg.sender,
            isNative: true
        });
        (uint256 positionId, EntryContext memory context) = _initContext(params);
        string memory entryPriceStr = _validateAndStore(context, positionId, stopLossPrice, takeProfitPrice);
        _finalizeEntrySteps(positionId, params.isNative);
        emit PositionEntered(positionId, params.maker, params.positionType, params.minEntryPrice, params.maxEntryPrice, address(0));
    }

    function enterShortToken(
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external {
        // Initiates a short position with ERC20 token
        EntryParams memory params = EntryParams({
            listingAddress: listingAddress,
            minEntryPrice: minEntryPrice,
            maxEntryPrice: maxEntryPrice,
            initialMargin: initialMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            positionType: 1,
            maker: msg.sender,
            isNative: false
        });
        (uint256 positionId, EntryContext memory context) = _initContext(params);
        string memory entryPriceStr = _validateAndStore(context, positionId, stopLossPrice, takeProfitPrice);
        _finalizeEntrySteps(positionId, params.isNative);
        emit PositionEntered(positionId, params.maker, params.positionType, params.minEntryPrice, params.maxEntryPrice, address(0));
    }

    function driveNative(
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
    ) external payable nonReentrant {
        // Initiates a position on behalf of a maker with native gas token
        require(maker != address(0), "Invalid maker address");
        require(positionType <= 1, string(abi.encodePacked("Invalid position type: ", uint2str(positionType))));
        EntryParams memory params = EntryParams({
            listingAddress: listingAddress,
            minEntryPrice: minEntryPrice,
            maxEntryPrice: maxEntryPrice,
            initialMargin: initialMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            positionType: positionType,
            maker: maker,
            isNative: true
        });
        (uint256 positionId, EntryContext memory context) = _initContext(params);
        string memory entryPriceStr = _validateAndStore(context, positionId, stopLossPrice, takeProfitPrice);
        _finalizeEntrySteps(positionId, params.isNative);
        emit PositionEntered(positionId, params.maker, params.positionType, params.minEntryPrice, params.maxEntryPrice, msg.sender);
    }

    function driveToken(
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
        // Initiates a position on behalf of a maker with ERC20 token
        require(maker != address(0), "Invalid maker address");
        require(positionType <= 1, string(abi.encodePacked("Invalid position type: ", uint2str(positionType))));
        EntryParams memory params = EntryParams({
            listingAddress: listingAddress,
            minEntryPrice: minEntryPrice,
            maxEntryPrice: maxEntryPrice,
            initialMargin: initialMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            positionType: positionType,
            maker: maker,
            isNative: false
        });
        (uint256 positionId, EntryContext memory context) = _initContext(params);
        string memory entryPriceStr = _validateAndStore(context, positionId, stopLossPrice, takeProfitPrice);
        _finalizeEntrySteps(positionId, params.isNative);
        emit PositionEntered(positionId, params.maker, params.positionType, params.minEntryPrice, params.maxEntryPrice, msg.sender);
    }
}