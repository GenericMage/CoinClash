/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-07-20: Refactored cancelAllLongs and cancelAllShorts to address stack too deep error by splitting into helper functions (_prepareCancelPosition, _executeCancelPosition, _updatePositionParams, _updateMarginAndIndex) with prep and execute phases, split by parameter groups, incremented version to 0.0.6.
 - 2025-07-20: Added cancelPosition function to handle cancellation of pending positions, including margin transfer to listing contract and update call, incremented version to 0.0.5.
 - 2025-07-19: Removed redundant storageContract declaration, fixed constructor to call CCSExecutionPartial with _storageContract, cleaned up redundant inheritance entries, incremented version to 0.0.4.
 - 2025-07-19: Fixed undeclared struct identifiers by adding ICSStorage prefix, corrected PositionClosed event emission to use interface, incremented version to 0.0.3.
 - 2025-07-19: Updated to use ICSStorage interface, split CSUpdate calls by parameter group, added hyx management functions (addHyx, removeHyx, getHyxes), incremented version to 0.0.2.
 - 2025-07-18: Created CCSExecutionDriver contract, inheriting CCSExecutionPartial, to handle position execution functions alongside CSStorage. Implemented addExcessMargin, pullMargin, updateSL, updateTP, closeAllLongs, closeAllShorts, cancelAllLongs, cancelAllShorts, and executePositions. Adapted state updates to use CSStorage.CSUpdate. Version set to 0.0.1.
*/

pragma solidity ^0.8.2;

import "./imports/ReentrancyGuard.sol";
import "./driverUtils/CCSExecutionPartial.sol";

contract CCSExecutionDriver is ReentrancyGuard, CCSExecutionPartial {
    mapping(address => bool) private _hyxes; // Tracks authorized hyx addresses
    address[] private _hyxList; // List of authorized hyx addresses

    // Events
    event StopLossUpdated(uint256 indexed positionId, uint256 newStopLossPrice, uint256 currentPrice, uint256 timestamp);
    event TakeProfitUpdated(uint256 indexed positionId, uint256 newTakeProfitPrice, uint256 currentPrice, uint256 timestamp);
    event AllLongsClosed(address indexed maker, uint256 processed);
    event AllLongsCancelled(address indexed maker, uint256 processed);
    event AllShortsClosed(address indexed maker, uint256 processed);
    event AllShortsCancelled(address indexed maker, uint256 processed);
    event HyxAdded(address indexed hyx); // Emitted when a hyx is authorized
    event HyxRemoved(address indexed hyx); // Emitted when a hyx is removed
    event PositionCancelled(uint256 indexed positionId, address indexed maker); // Emitted when a position is cancelled

    constructor(address _storageContract) CCSExecutionPartial(_storageContract) {
        require(_storageContract != address(0), "Invalid storage address"); // Ensures valid storage contract address
    }

    // Authorizes a hyx contract to call update functions
    function addHyx(address hyx) external onlyOwner {
        require(hyx != address(0), "Invalid hyx address"); // Validates hyx address
        require(!_hyxes[hyx], "Hyx already added"); // Prevents duplicate addition
        _hyxes[hyx] = true;
        _hyxList.push(hyx);
        emit HyxAdded(hyx);
    }

    // Revokes a hyx contract’s authorization
    function removeHyx(address hyx) external onlyOwner {
        require(_hyxes[hyx], "Hyx not found"); // Ensures hyx is authorized
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

    // Returns an array of authorized hyx addresses
    function getHyxes() external view returns (address[] memory) {
        return _hyxList; // Returns list of authorized hyx addresses
    }

    // Adds excess margin for a maker
    function addExcessMargin(address listingAddress, bool tokenA, uint256 amount, address maker) external nonReentrant {
        require(amount > 0, "Invalid amount"); // Ensures non-zero amount
        require(maker != address(0), "Invalid maker"); // Validates maker address
        require(listingAddress != address(0), "Invalid listing"); // Validates listing address
        (bool isValid, ) = ISSAgent(agentAddress).isValidListing(listingAddress);
        require(isValid, "Invalid listing"); // Ensures listing is valid
        address token = tokenA ? ISSListing(listingAddress).tokenA() : ISSListing(listingAddress).tokenB();
        uint256 normalizedAmount = _transferMarginToListing(token, amount, listingAddress);
        _updateListingMargin(listingAddress, amount);
        _updateMakerMargin(maker, token, normalizedAmount);
        _updatePositionLiquidationPrices(maker, token, listingAddress);
        _updateHistoricalInterest(normalizedAmount, 0, listingAddress);
    }

    // Withdraws margin for a maker
    function pullMargin(address listingAddress, bool tokenA, uint256 amount) external nonReentrant {
        (address token, uint256 normalizedAmount) = _validateAndNormalizePullMargin(listingAddress, tokenA, amount);
        _updatePositionLiquidationPrices(msg.sender, token, listingAddress);
        _reduceMakerMargin(msg.sender, token, normalizedAmount);
        _executeMarginPayout(listingAddress, msg.sender, amount);
        _updateHistoricalInterest(normalizedAmount, 1, listingAddress);
    }

    // Updates stop-loss price for a position
    function updateSL(uint256 positionId, uint256 newStopLossPrice) external nonReentrant {
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
        require(core1.positionId == positionId, "Invalid position"); // Ensures position exists
        require(core2.status2 == 0, "Position closed"); // Ensures position is open
        require(core1.makerAddress == msg.sender, "Not maker"); // Ensures caller is maker
        require(newStopLossPrice > 0 || newStopLossPrice == 0, "Invalid SL"); // Validates stop-loss price
        address token = storageContract.positionToken(positionId);
        uint256 currentPrice = normalizePrice(token, ISSListing(core1.listingAddress).prices(core1.listingAddress));
        ICSStorage.PriceParams1 memory price1 = storageContract.priceParams1(positionId);
        _updateSL(positionId, normalizePrice(token, newStopLossPrice), core1.listingAddress, core1.positionType, price1.minPrice, price1.maxEntryPrice, currentPrice);
        emit StopLossUpdated(positionId, newStopLossPrice, currentPrice, block.timestamp);
    }

    // Updates take-profit price for a position
    function updateTP(uint256 positionId, uint256 newTakeProfitPrice) external nonReentrant {
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
        require(core1.positionId == positionId, "Invalid position"); // Ensures position exists
        require(core2.status2 == 0, "Position closed"); // Ensures position is open
        require(core1.makerAddress == msg.sender, "Not maker"); // Ensures caller is maker
        require(newTakeProfitPrice > 0 || newTakeProfitPrice == 0, "Invalid TP"); // Validates take-profit price
        address token = storageContract.positionToken(positionId);
        uint256 currentPrice = normalizePrice(token, ISSListing(core1.listingAddress).prices(core1.listingAddress));
        ICSStorage.PriceParams1 memory price1 = storageContract.priceParams1(positionId);
        _updateTP(positionId, normalizePrice(token, newTakeProfitPrice), core1.listingAddress, core1.positionType, price1.priceAtEntry, price1.maxEntryPrice, currentPrice);
        emit TakeProfitUpdated(positionId, newTakeProfitPrice, currentPrice, block.timestamp);
    }

    // Closes all active long positions for a maker
    function closeAllLongs(uint256 maxIterations) external nonReentrant {
        address maker = msg.sender;
        uint256 processed = 0;
        uint256 positionCount = storageContract.positionCount();
        for (uint256 i = 0; i < positionCount && processed < maxIterations && gasleft() >= 50000; i++) {
            uint256 positionId = i + 1;
            ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
            ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
            if (core1.makerAddress != maker || core1.positionType != 0 || core2.status2 != 0 || !core2.status1) continue;
            address tokenB = ISSListing(core1.listingAddress).tokenB();
            uint256 payout = _prepCloseLong(positionId, core1.listingAddress);
            storageContract.removePositionIndex(positionId, core1.positionType, core1.listingAddress);
            ISSListing.PayoutUpdate[] memory updates = new ISSListing.PayoutUpdate[](1);
            updates[0] = ISSListing.PayoutUpdate({
                payoutType: core1.positionType,
                recipient: maker,
                required: denormalizeAmount(tokenB, payout)
            });
            ISSListing(core1.listingAddress).ssUpdate(address(this), updates);
            emit ICSStorage.PositionClosed(positionId, maker, payout);
            processed++;
        }
        emit AllLongsClosed(maker, processed);
    }

    // Prepares data for cancelling a position
    function _prepareCancelPosition(
        uint256 positionId,
        address maker,
        uint8 positionType
    ) internal view returns (
        address token,
        address listingAddress,
        uint256 marginAmount,
        uint256 denormalizedAmount,
        bool isValid
    ) {
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
        if (
            core1.makerAddress != maker ||
            core1.positionType != positionType ||
            core2.status2 != 0 ||
            core2.status1
        ) {
            return (address(0), address(0), 0, 0, false); // Invalid position
        }
        token = storageContract.positionToken(positionId);
        listingAddress = core1.listingAddress;
        ICSStorage.MarginParams1 memory margin1 = storageContract.marginParams1(positionId);
        marginAmount = margin1.taxedMargin + margin1.excessMargin;
        denormalizedAmount = denormalizeAmount(token, marginAmount);
        return (token, listingAddress, marginAmount, denormalizedAmount, true);
    }

    // Updates position-related parameters
    function _updatePositionParams(uint256 positionId) internal {
        _updateCoreParams(positionId, ICSStorage.PositionCore1(0, address(0), address(0), 0)); // Clears core parameters
        _updatePositionStatus(positionId, ICSStorage.PositionCore2(false, 1)); // Marks position as closed
        _updatePriceParams(positionId, ICSStorage.PriceParams1(0, 0, 0, 0, 0), ICSStorage.PriceParams2(0)); // Clears price parameters
        _updateExitParams(positionId, ICSStorage.ExitParams(0, 0, 0)); // Clears exit parameters
        _updateOpenInterest(positionId, ICSStorage.OpenInterest(0, 0)); // Clears open interest
    }

    // Updates margin and index for a cancelled position
    function _updateMarginAndIndex(
        uint256 positionId,
        address maker,
        address token,
        uint256 marginAmount,
        address listingAddress,
        uint8 positionType
    ) internal {
        _updateMakerMarginParams(maker, token, storageContract.makerTokenMargin(maker, token) - marginAmount); // Updates maker margin
        storageContract.removePositionIndex(positionId, positionType, listingAddress); // Removes position from index
    }

    // Executes cancellation of a position
    function _executeCancelPosition(
        uint256 positionId,
        address token,
        uint256 denormalizedAmount,
        address listingAddress,
        address maker
    ) internal {
        _transferMarginToListing(token, denormalizedAmount, listingAddress); // Transfers margin to listing contract
        _updateListingMargin(listingAddress, denormalizedAmount); // Updates listing contract with margin
        _executeMarginPayout(listingAddress, maker, denormalizedAmount); // Executes payout to maker
        emit PositionCancelled(positionId, maker); // Emits cancellation event
    }

    // Cancels all pending long positions for a maker
    function cancelAllLongs(uint256 maxIterations) external nonReentrant {
        address maker = msg.sender;
        uint256 processed = 0;
        uint256 positionCount = storageContract.positionCount();
        for (uint256 i = 0; i < positionCount && processed < maxIterations && gasleft() >= 50000; i++) {
            uint256 positionId = i + 1;
            (address token, address listingAddress, uint256 marginAmount, uint256 denormalizedAmount, bool isValid) =
                _prepareCancelPosition(positionId, maker, 0); // Prepare data for long position cancellation
            if (!isValid) continue;
            _updatePositionParams(positionId); // Update position-related parameters
            _updateMarginAndIndex(positionId, maker, token, marginAmount, listingAddress, 0); // Update margin and index
            _executeCancelPosition(positionId, token, denormalizedAmount, listingAddress, maker); // Execute cancellation
            processed++;
        }
        emit AllLongsCancelled(maker, processed);
    }

    // Closes all active short positions for a maker
    function closeAllShorts(uint256 maxIterations) external nonReentrant {
        address maker = msg.sender;
        uint256 processed = 0;
        uint256 positionCount = storageContract.positionCount();
        for (uint256 i = 0; i < positionCount && processed < maxIterations && gasleft() >= 50000; i++) {
            uint256 positionId = i + 1;
            ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
            ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
            if (core1.makerAddress != maker || core1.positionType != 1 || core2.status2 != 0 || !core2.status1) continue;
            address tokenA = ISSListing(core1.listingAddress).tokenA();
            uint256 payout = _prepCloseShort(positionId, core1.listingAddress);
            storageContract.removePositionIndex(positionId, 1, core1.listingAddress);
            ISSListing.PayoutUpdate[] memory updates = new ISSListing.PayoutUpdate[](1);
            updates[0] = ISSListing.PayoutUpdate({
                payoutType: core1.positionType,
                recipient: maker,
                required: denormalizeAmount(tokenA, payout)
            });
            ISSListing(core1.listingAddress).ssUpdate(address(this), updates);
            emit ICSStorage.PositionClosed(positionId, maker, payout);
            processed++;
        }
        emit AllShortsClosed(maker, processed);
    }

    // Cancels all pending short positions for a maker
    function cancelAllShorts(uint256 maxIterations) external nonReentrant {
        address maker = msg.sender;
        uint256 processed = 0;
        uint256 positionCount = storageContract.positionCount();
        for (uint256 i = 0; i < positionCount && processed < maxIterations && gasleft() >= 50000; i++) {
            uint256 positionId = i + 1;
            (address token, address listingAddress, uint256 marginAmount, uint256 denormalizedAmount, bool isValid) =
                _prepareCancelPosition(positionId, maker, 1); // Prepare data for short position cancellation
            if (!isValid) continue;
            _updatePositionParams(positionId); // Update position-related parameters
            _updateMarginAndIndex(positionId, maker, token, marginAmount, listingAddress, 1); // Update margin and index
            _executeCancelPosition(positionId, token, denormalizedAmount, listingAddress, maker); // Execute cancellation
            processed++;
        }
        emit AllShortsCancelled(maker, processed);
    }

    // Cancels a single pending position
    function cancelPosition(uint256 positionId) external nonReentrant {
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
        require(core1.positionId == positionId, "Invalid position"); // Ensures position exists
        require(core2.status2 == 0, "Position closed"); // Ensures position is open
        require(!core2.status1, "Position active"); // Ensures position is pending
        require(core1.makerAddress == msg.sender, "Not maker"); // Ensures caller is maker
        address token = storageContract.positionToken(positionId);
        ICSStorage.MarginParams1 memory margin1 = storageContract.marginParams1(positionId);
        uint256 marginAmount = margin1.taxedMargin + margin1.excessMargin;
        uint256 denormalizedAmount = denormalizeAmount(token, marginAmount);
        _transferMarginToListing(token, denormalizedAmount, core1.listingAddress); // Transfers margin to listing contract
        _updateListingMargin(core1.listingAddress, denormalizedAmount); // Updates listing contract with margin
        _updateCoreParams(positionId, ICSStorage.PositionCore1(0, address(0), address(0), 0)); // Clears core parameters
        _updatePositionStatus(positionId, ICSStorage.PositionCore2(false, 1)); // Marks position as closed
        _updatePriceParams(positionId, ICSStorage.PriceParams1(0, 0, 0, 0, 0), ICSStorage.PriceParams2(0)); // Clears price parameters
        _updateMarginParams(positionId, ICSStorage.MarginParams1(0, 0, 0, 0), ICSStorage.MarginParams2(0)); // Clears margin parameters
        _updateExitParams(positionId, ICSStorage.ExitParams(0, 0, 0)); // Clears exit parameters
        _updateOpenInterest(positionId, ICSStorage.OpenInterest(0, 0)); // Clears open interest
        _updateMakerMarginParams(core1.makerAddress, token, storageContract.makerTokenMargin(core1.makerAddress, token) - marginAmount); // Updates maker margin
        storageContract.removePositionIndex(positionId, core1.positionType, core1.listingAddress); // Removes position from index
        _executeMarginPayout(core1.listingAddress, msg.sender, denormalizedAmount); // Executes payout to maker
        emit PositionCancelled(positionId, msg.sender); // Emits cancellation event
    }

    // Executes pending and active positions
    function executePositions(address listingAddress, uint256 maxIterations) external nonReentrant {
        _executePositions(listingAddress, maxIterations);
    }
}