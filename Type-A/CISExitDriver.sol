/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-08-10: Updated to reflect inherited _getCurrentPrice from CISExitPartial; version set to 0.0.9.
 - 2025-08-10: Removed ISIStorage interface to CISExitPartial; updated to use inherited interfaces; version set to 0.0.8.
 - 2025-08-10: Integrated closeAllLongs, closeAllShorts, cancelAllLongs, cancelAllShorts from CISExtraDriver v0.0.1; updated closeLongPosition, closeShortPosition, cancelPosition to use _finalizeClosePosition and _executeCancelPosition; version set to 0.0.7.
 - 2025-08-08: Updated drift to use this.closeLongPosition and this.closeShortPosition; version set to 0.0.6.
 - 2025-08-08: Cast storageContract to ISIStorage in _getPositionCount and _removePositionIndex; version set to 0.0.5.
 - 2025-08-08: Removed 'this.' from internal function calls; version set to 0.0.4.
 - 2025-08-08: Updated closeLongPosition and closeShortPosition to send payouts to msg.sender; version set to 0.0.3.
 - 2025-08-08: Refactored drift to reuse closeLongPosition and closeShortPosition; added caller parameter; version set to 0.0.2.
 - 2025-08-07: Created CISExitDriver; version set to 0.0.1.
*/

pragma solidity ^0.8.2;

import "./driverUtils/CISExitPartial.sol";

contract CISExitDriver is CISExitPartial {
    address[] private hyxes;

    event PositionClosed(uint256 indexed positionId, address indexed maker, uint256 payout);
    event PositionCancelled(uint256 indexed positionId, address indexed maker, uint256 timestamp);
    event HyxAdded(address indexed hyx);
    event HyxRemoved(address indexed hyx);
    event ErrorLogged(string reason);

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

    function closeLongPosition(uint256 positionId, address caller) external nonReentrant {
        ISIStorage.PositionCoreBase memory coreBase = ISIStorage(storageContract).positionCoreBase(positionId);
        ISIStorage.PositionCoreStatus memory coreStatus = ISIStorage(storageContract).positionCoreStatus(positionId);
        require(coreBase.positionId == positionId, string(abi.encodePacked("Invalid position ID: ", uint2str(positionId))));
        require(coreStatus.status2 == 0, "Position already closed");
        require(coreBase.makerAddress == caller, "Caller does not match maker");
        if (caller != msg.sender) {
            bool isHyx = false;
            for (uint256 i = 0; i < hyxes.length; i++) {
                if (hyxes[i] == msg.sender) {
                    isHyx = true;
                    break;
                }
            }
            require(isHyx, "Caller is not a Hyx");
        }
        uint256 payout = _finalizeClosePosition(positionId, 0, coreBase.listingAddress, caller);
        emit PositionClosed(positionId, coreBase.makerAddress, payout);
    }

    function closeShortPosition(uint256 positionId, address caller) external nonReentrant {
        ISIStorage.PositionCoreBase memory coreBase = ISIStorage(storageContract).positionCoreBase(positionId);
        ISIStorage.PositionCoreStatus memory coreStatus = ISIStorage(storageContract).positionCoreStatus(positionId);
        require(coreBase.positionId == positionId, string(abi.encodePacked("Invalid position ID: ", uint2str(positionId))));
        require(coreStatus.status2 == 0, "Position already closed");
        require(coreBase.makerAddress == caller, "Caller does not match maker");
        if (caller != msg.sender) {
            bool isHyx = false;
            for (uint256 i = 0; i < hyxes.length; i++) {
                if (hyxes[i] == msg.sender) {
                    isHyx = true;
                    break;
                }
            }
            require(isHyx, "Caller is not a Hyx");
        }
        uint256 payout = _finalizeClosePosition(positionId, 1, coreBase.listingAddress, caller);
        emit PositionClosed(positionId, coreBase.makerAddress, payout);
    }

    function cancelPosition(uint256 positionId) external nonReentrant {
        ISIStorage.PositionCoreBase memory coreBase = ISIStorage(storageContract).positionCoreBase(positionId);
        ISIStorage.PositionCoreStatus memory coreStatus = ISIStorage(storageContract).positionCoreStatus(positionId);
        require(coreBase.positionId == positionId, string(abi.encodePacked("Invalid position ID: ", uint2str(positionId))));
        require(coreStatus.status2 == 0, "Position already closed");
        require(coreBase.makerAddress == msg.sender, string(abi.encodePacked("Caller not maker for position ", uint2str(positionId))));
        _executeCancelPosition(positionId, coreBase.positionType, coreBase.listingAddress, msg.sender);
        emit PositionCancelled(positionId, msg.sender, block.timestamp);
    }

    function drift(uint256 positionId, address maker) external nonReentrant onlyHyx {
        ISIStorage.PositionCoreBase memory coreBase = ISIStorage(storageContract).positionCoreBase(positionId);
        ISIStorage.PositionCoreStatus memory coreStatus = ISIStorage(storageContract).positionCoreStatus(positionId);
        require(coreBase.positionId == positionId, string(abi.encodePacked("Invalid position ID: ", uint2str(positionId))));
        require(coreStatus.status2 == 0, "Position already closed");
        require(coreBase.makerAddress == maker, string(abi.encodePacked("Maker mismatch: expected ", toString(maker), ", got ", toString(coreBase.makerAddress))));
        if (coreBase.positionType == 0) {
            this.closeLongPosition(positionId, maker);
        } else {
            this.closeShortPosition(positionId, maker);
        }
    }

    function closeAllLongs(address listingAddress, uint256 maxIterations) external nonReentrant {
        if (listingAddress == address(0)) {
            emit ErrorLogged("closeAllLongs: Listing address is zero");
            revert("closeAllLongs: Invalid listing address");
        }
        _closeAllPositions(listingAddress, 0, maxIterations);
    }

    function closeAllShorts(address listingAddress, uint256 maxIterations) external nonReentrant {
        if (listingAddress == address(0)) {
            emit ErrorLogged("closeAllShorts: Listing address is zero");
            revert("closeAllShorts: Invalid listing address");
        }
        _closeAllPositions(listingAddress, 1, maxIterations);
    }

    function cancelAllLongs(address listingAddress, uint256 maxIterations) external nonReentrant {
        if (listingAddress == address(0)) {
            emit ErrorLogged("cancelAllLongs: Listing address is zero");
            revert("cancelAllLongs: Invalid listing address");
        }
        _cancelAllPositions(listingAddress, 0, maxIterations);
    }

    function cancelAllShorts(address listingAddress, uint256 maxIterations) external nonReentrant {
        if (listingAddress == address(0)) {
            emit ErrorLogged("cancelAllShorts: Listing address is zero");
            revert("cancelAllShorts: Invalid listing address");
        }
        _cancelAllPositions(listingAddress, 1, maxIterations);
    }

    function _getPositionCount() internal view returns (uint256 positionCount) {
        try ISIStorage(storageContract).positionCount() returns (uint256 count) {
            positionCount = count;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Failed to get position count: ", reason)));
        }
    }

    function _removePositionIndex(uint256 positionId, uint8 positionType, address listingAddress) internal {
        try ISIStorage(storageContract).removePositionIndex(positionId, positionType, address(0)) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Failed to remove position index for ID ", uint2str(positionId), ": ", reason)));
        }
    }

    function _closeAllPositions(address listingAddress, uint8 positionType, uint256 maxIterations) internal {
        (bool isValid, ) = ISSAgent(agentAddress).isValidListing(listingAddress);
        if (!isValid) {
            emit ErrorLogged("closeAllPositions: Invalid listing");
            revert("closeAllPositions: Invalid listing");
        }
        uint256[] memory positions = ISIStorage(storageContract).positionsByType(positionType);
        uint256 processed = 0;
        for (uint256 i = 0; i < positions.length && processed < maxIterations && gasleft() >= 50000; i++) {
            uint256 positionId = positions[i];
            ISIStorage.PositionCoreBase memory coreBase = ISIStorage(storageContract).positionCoreBase(positionId);
            if (coreBase.listingAddress == listingAddress && coreBase.makerAddress == msg.sender) {
                _finalizeClosePosition(positionId, positionType, listingAddress, msg.sender);
                i--;
            }
            processed++;
        }
    }

    function _cancelAllPositions(address listingAddress, uint8 positionType, uint256 maxIterations) internal {
        (bool isValid, ) = ISSAgent(agentAddress).isValidListing(listingAddress);
        if (!isValid) {
            emit ErrorLogged("cancelAllPositions: Invalid listing");
            revert("cancelAllPositions: Invalid listing");
        }
        uint256[] memory positions = ISIStorage(storageContract).pendingPositions(listingAddress, positionType);
        uint256 processed = 0;
        for (uint256 i = 0; i < positions.length && processed < maxIterations && gasleft() >= 50000; i++) {
            uint256 positionId = positions[i];
            ISIStorage.PositionCoreBase memory coreBase = ISIStorage(storageContract).positionCoreBase(positionId);
            if (coreBase.makerAddress == msg.sender) {
                _executeCancelPosition(positionId, positionType, listingAddress, msg.sender);
                i--;
            }
            processed++;
        }
    }
}