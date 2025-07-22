// SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version 0.0.5:
// - 2025-07-22: Removed ExcessMarginAdded event declaration to fix DeclarationError due to duplicate event definition in CISExecutionPartial.sol.
// - 2025-07-22: Fixed multiple DeclarationError instances by ensuring _storageContract is accessed via inherited CISExecutionPartial.
// - 2025-07-22: Removed redundant ISIStorage interface declaration to fix DeclarationError due to duplicate identifier.
// - 2025-07-22: Updated _finalizeClosePosition to emit PositionClosed event directly instead of ISIStorage.PositionClosed to align with CISExecutionPartial event definition.
// - 2025-07-21: Updated to use ISIStorage interface inline instead of ICSStorage, adapting struct names and function calls.
// - 2025-07-21: Created CISExecutionDriver contract, inheriting CISExecutionPartial, adapted from SSIsolatedDriver and CCSExecutionDriver.
// - Implements execution functions (addExcessMargin, pullMargin, updateSL, updateTP, closeAllLongs, closeAllShorts, cancelAllLongs, cancelAllShorts, cancelPosition, executePositions).
// - Integrates with ICCOrderRouter for order creation during position activation.
// - Uses ISIStorage for state updates via SIUpdate, following isolated margin logic.
// - Added hyx management functions (addHyx, removeHyx, getHyxesView).
// - Compatible with CISExecutionPartial.sol v0.0.6.

import "./imports/ReentrancyGuard.sol";
import "./driverUtils/CISExecutionPartial.sol";

contract CISExecutionDriver is ReentrancyGuard, CISExecutionPartial {
    mapping(address => bool) private _hyxes; // Tracks authorized hyx addresses
    address[] private _hyxList; // List of authorized hyx addresses

    // Events
    event StopLossUpdated(uint256 indexed positionId, uint256 newStopLossPrice, uint256 currentPrice, uint256 timestamp); // Emitted when stop-loss is updated
    event TakeProfitUpdated(uint256 indexed positionId, uint256 newTakeProfitPrice, uint256 currentPrice, uint256 timestamp); // Emitted when take-profit is updated
    event AllLongsClosed(address indexed maker, uint256 processed); // Emitted when all long positions are closed
    event AllLongsCancelled(address indexed maker, uint256 processed); // Emitted when all pending long positions are cancelled
    event AllShortsClosed(address indexed maker, uint256 processed); // Emitted when all short positions are closed
    event AllShortsCancelled(address indexed maker, uint256 processed); // Emitted when all pending short positions are cancelled
    event hyxAdded(address indexed hyx); // Emitted when a hyx is authorized
    event hyxRemoved(address indexed hyx); // Emitted when a hyx is removed
    event PositionCancelled(uint256 indexed positionId, address indexed maker); // Emitted when a position is cancelled

    // Constructor initializes storage and order router
    constructor(address storageContractAddress, address orderRouterAddress) CISExecutionPartial(storageContractAddress) {
        require(storageContractAddress != address(0), "Invalid storage address"); // Ensures valid storage contract address
        require(orderRouterAddress != address(0), "Invalid order router address"); // Ensures valid order router address
        orderRouter = ICCOrderRouter(orderRouterAddress); // Sets order router directly
    }

    // Authorizes a hyx contract to call execution functions
    function addHyx(address hyx) external onlyOwner {
        require(hyx != address(0), "Invalid hyx address"); // Validates hyx address
        require(!_hyxes[hyx], "hyx already authorized"); // Prevents duplicate addition
        _hyxes[hyx] = true; // Marks hyx as authorized
        _hyxList.push(hyx); // Adds to hyx list
        emit hyxAdded(hyx); // Emits authorization event
    }

    // Revokes a hyx contract's authorization
    function removeHyx(address hyx) external onlyOwner {
        require(_hyxes[hyx], "hyx not authorized"); // Ensures hyx is authorized
        _hyxes[hyx] = false; // Revokes authorization
        for (uint256 i = 0; i < _hyxList.length; i++) {
            if (_hyxList[i] == hyx) {
                _hyxList[i] = _hyxList[_hyxList.length - 1]; // Moves last element to current index
                _hyxList.pop(); // Removes last element
                break;
            }
        }
        emit hyxRemoved(hyx); // Emits revocation event
    }

    // Returns list of authorized hyxes
    function getHyxesView() external view returns (address[] memory) {
        return _hyxList; // Returns array of authorized hyx addresses
    }

    // Adds excess margin to a position
    function addExcessMargin(uint256 positionId, uint256 amount, address token) external nonReentrant {
        ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core position data
        ISIStorage.PositionCoreStatus memory coreStatus = _storageContract.positionCoreStatus(positionId); // Retrieves position status
        require(coreBase.positionId == positionId, "Invalid position"); // Ensures position exists
        require(coreStatus.status2 == 0, "Position closed"); // Ensures position is open
        require(coreBase.makerAddress == msg.sender, "Not maker"); // Ensures caller is maker
        require(amount > 0, "Invalid amount"); // Ensures non-zero amount
        require(token == _storageContract.positionToken(positionId), "Invalid token"); // Validates token
        uint256 normalizedAmount = normalizeAmount(token, amount); // Normalizes amount based on token decimals
        _validateExcessMargin(positionId, normalizedAmount); // Validates margin against leverage
        uint256 actualAmount = _transferExcessMargin(positionId, amount, token, coreBase.listingAddress); // Transfers margin
        uint256 actualNormalized = normalizeAmount(token, actualAmount); // Normalizes actual amount
        _updateMarginAndInterest(positionId, actualNormalized, coreBase.positionType, coreBase.listingAddress); // Updates margin and interest
        _updateLiquidationPrice(positionId, coreBase.positionType); // Recalculates liquidation price
        emit ExcessMarginAdded(positionId, msg.sender, amount); // Emits event
    }

    // Withdraws margin from a position
    function pullMargin(uint256 positionId, uint256 amount) external nonReentrant {
        ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core position data
        ISIStorage.PositionCoreStatus memory coreStatus = _storageContract.positionCoreStatus(positionId); // Retrieves position status
        require(coreBase.positionId == positionId, "Invalid position"); // Ensures position exists
        require(coreStatus.status2 == 0, "Position closed"); // Ensures position is open
        require(coreBase.makerAddress == msg.sender, "Not maker"); // Ensures caller is maker
        require(amount > 0, "Invalid amount"); // Ensures non-zero amount
        address token = _storageContract.positionToken(positionId); // Retrieves position token
        ISIStorage.MarginParams memory margin = _storageContract.marginParams(positionId); // Retrieves margin data
        uint256 normalizedAmount = normalizeAmount(token, amount); // Normalizes amount
        require(normalizedAmount <= margin.marginExcess, "Insufficient excess margin"); // Ensures sufficient margin
        _updateMarginParams(positionId, ISIStorage.MarginParams(margin.marginInitial, margin.marginTaxed, margin.marginExcess - normalizedAmount)); // Updates margin
        _updateLiquidationPrice(positionId, coreBase.positionType); // Recalculates liquidation price
        _executeMarginPayout(coreBase.listingAddress, msg.sender, amount); // Executes payout
        _updateHistoricalInterest(normalizedAmount, coreBase.positionType, coreBase.listingAddress, false); // Updates historical interest
    }

    // Updates stop-loss price for a position
    function updateSL(uint256 positionId, uint256 newStopLossPrice) external nonReentrant {
        ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core position data
        ISIStorage.PositionCoreStatus memory coreStatus = _storageContract.positionCoreStatus(positionId); // Retrieves position status
        require(coreBase.positionId == positionId, "Invalid position"); // Ensures position exists
        require(coreStatus.status2 == 0, "Position closed"); // Ensures position is open
        require(coreBase.makerAddress == msg.sender, "Not maker"); // Ensures caller is maker
        address token = _storageContract.positionToken(positionId); // Retrieves position token
        uint256 currentPrice = normalizePrice(token, ISSListing(coreBase.listingAddress).prices(coreBase.listingAddress)); // Normalizes current price
        if (coreBase.positionType == 0) {
            require(newStopLossPrice == 0 || newStopLossPrice < currentPrice, "Invalid SL for long"); // Validates stop-loss for long
        } else {
            require(newStopLossPrice == 0 || newStopLossPrice > currentPrice, "Invalid SL for short"); // Validates stop-loss for short
        }
        _updateSL(positionId, normalizePrice(token, newStopLossPrice)); // Updates stop-loss
        emit StopLossUpdated(positionId, newStopLossPrice, currentPrice, block.timestamp); // Emits event
    }

    // Updates take-profit price for a position
    function updateTP(uint256 positionId, uint256 newTakeProfitPrice) external nonReentrant {
        ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core position data
        ISIStorage.PositionCoreStatus memory coreStatus = _storageContract.positionCoreStatus(positionId); // Retrieves position status
        require(coreBase.positionId == positionId, "Invalid position"); // Ensures position exists
        require(coreStatus.status2 == 0, "Position closed"); // Ensures position is open
        require(coreBase.makerAddress == msg.sender, "Not maker"); // Ensures caller is maker
        address token = _storageContract.positionToken(positionId); // Retrieves position token
        uint256 currentPrice = normalizePrice(token, ISSListing(coreBase.listingAddress).prices(coreBase.listingAddress)); // Normalizes current price
        ISIStorage.PriceParams memory price = _storageContract.priceParams(positionId); // Retrieves price data
        if (coreBase.positionType == 0) {
            require(newTakeProfitPrice == 0 || newTakeProfitPrice > price.priceAtEntry, "Invalid TP for long"); // Validates take-profit for long
        } else {
            require(newTakeProfitPrice == 0 || newTakeProfitPrice < price.priceAtEntry, "Invalid TP for short"); // Validates take-profit for short
        }
        _updateTP(positionId, normalizePrice(token, newTakeProfitPrice)); // Updates take-profit
        emit TakeProfitUpdated(positionId, newTakeProfitPrice, currentPrice, block.timestamp); // Emits event
    }

    // Closes all active long positions
    function closeAllLongs(uint256 maxIterations) external nonReentrant {
        address maker = msg.sender; // Retrieves caller address
        uint256 processed = _closeAllPositions(maker, 0, maxIterations); // Closes long positions
        emit AllLongsClosed(maker, processed); // Emits event
    }

    // Closes all active short positions
    function closeAllShorts(uint256 maxIterations) external nonReentrant {
        address maker = msg.sender; // Retrieves caller address
        uint256 processed = _closeAllPositions(maker, 1, maxIterations); // Closes short positions
        emit AllShortsClosed(maker, processed); // Emits event
    }

    // Cancels all pending long positions
    function cancelAllLongs(uint256 maxIterations) external nonReentrant {
        address maker = msg.sender; // Retrieves caller address
        uint256 processed = _cancelAllPositions(maker, 0, maxIterations); // Cancels long positions
        emit AllLongsCancelled(maker, processed); // Emits event
    }

    // Cancels all pending short positions
    function cancelAllShorts(uint256 maxIterations) external nonReentrant {
        address maker = msg.sender; // Retrieves caller address
        uint256 processed = _cancelAllPositions(maker, 1, maxIterations); // Cancels short positions
        emit AllShortsCancelled(maker, processed); // Emits event
    }

    // Cancels a single pending position
    function cancelPosition(uint256 positionId) external nonReentrant {
        ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core position data
        ISIStorage.PositionCoreStatus memory coreStatus = _storageContract.positionCoreStatus(positionId); // Retrieves position status
        require(coreBase.positionId == positionId, "Invalid position"); // Ensures position exists
        require(coreStatus.status2 == 0, "Position closed"); // Ensures position is open
        require(!coreStatus.status1, "Position active"); // Ensures position is pending
        require(coreBase.makerAddress == msg.sender, "Not maker"); // Ensures caller is maker
        address token = _storageContract.positionToken(positionId); // Retrieves position token
        ISIStorage.MarginParams memory margin = _storageContract.marginParams(positionId); // Retrieves margin data
        uint256 marginAmount = margin.marginTaxed + margin.marginExcess; // Calculates total margin
        uint256 denormalizedAmount = denormalizeAmount(token, marginAmount); // Denormalizes margin
        _executeCancelPosition(positionId, coreBase, margin, token, denormalizedAmount); // Executes cancellation
        emit PositionCancelled(positionId, msg.sender); // Emits event
    }

    // Executes pending and active positions
    function executePositions(address listingAddress, uint256 maxIterations) external nonReentrant {
        _executePositions(listingAddress, maxIterations); // Executes positions
    }

    // Internal: Closes all positions of a given type
    function _closeAllPositions(address maker, uint8 positionType, uint256 maxIterations) internal returns (uint256 processed) {
        processed = 0; // Tracks processed positions
        uint256[] memory positions = _storageContract.positionsByType(positionType); // Retrieves active positions
        for (uint256 i = 0; i < positions.length && processed < maxIterations && gasleft() >= 50000; i++) {
            uint256 positionId = positions[i]; // Retrieves position ID
            ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core position data
            ISIStorage.PositionCoreStatus memory coreStatus = _storageContract.positionCoreStatus(positionId); // Retrieves position status
            if (coreBase.makerAddress != maker || coreStatus.status2 != 0 || !coreStatus.status1) continue; // Skips invalid positions
            address token = positionType == 0 ? ISSListing(coreBase.listingAddress).tokenB() : ISSListing(coreBase.listingAddress).tokenA(); // Retrieves token
            uint256 payout = positionType == 0 ? _prepCloseLong(positionId, coreBase.listingAddress) : _prepCloseShort(positionId, coreBase.listingAddress); // Prepares payout
            _finalizeClosePosition(positionId, coreBase, payout, token); // Finalizes close
            processed++; // Increments processed count
        }
        return processed; // Returns number of processed positions
    }

    // Internal: Cancels all positions of a given type
    function _cancelAllPositions(address maker, uint8 positionType, uint256 maxIterations) internal returns (uint256 processed) {
        processed = 0; // Tracks processed positions
        uint256[] memory positions = _storageContract.pendingPositions(maker, positionType); // Retrieves pending positions
        for (uint256 i = 0; i < positions.length && processed < maxIterations && gasleft() >= 50000; i++) {
            uint256 positionId = positions[i]; // Retrieves position ID
            ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core position data
            ISIStorage.PositionCoreStatus memory coreStatus = _storageContract.positionCoreStatus(positionId); // Retrieves position status
            if (coreBase.makerAddress != maker || coreStatus.status2 != 0 || coreStatus.status1) continue; // Skips invalid positions
            ISIStorage.MarginParams memory margin = _storageContract.marginParams(positionId); // Retrieves margin data
            address token = _storageContract.positionToken(positionId); // Retrieves token
            uint256 marginAmount = margin.marginTaxed + margin.marginExcess; // Calculates total margin
            uint256 denormalizedAmount = denormalizeAmount(token, marginAmount); // Denormalizes margin
            _executeCancelPosition(positionId, coreBase, margin, token, denormalizedAmount); // Executes cancellation
            processed++; // Increments processed count
        }
        return processed; // Returns number of processed positions
    }

    // Internal: Finalizes position closure
    function _finalizeClosePosition(uint256 positionId, ISIStorage.PositionCoreBase memory coreBase, uint256 payout, address token) internal {
        _storageContract.removePositionIndex(positionId, coreBase.positionType, coreBase.listingAddress); // Removes position from index
        ISSListing.PayoutUpdate[] memory updates = new ISSListing.PayoutUpdate[](1); // Prepares payout update
        updates[0] = ISSListing.PayoutUpdate({
            payoutType: coreBase.positionType,
            recipient: coreBase.makerAddress,
            required: denormalizeAmount(token, payout)
        }); // Configures payout
        ISSListing(coreBase.listingAddress).ssUpdate(address(this), updates); // Executes payout
        emit PositionClosed(positionId, coreBase.makerAddress, payout); // Emits event
    }

    // Internal: Executes position cancellation
    function _executeCancelPosition(uint256 positionId, ISIStorage.PositionCoreBase memory coreBase, ISIStorage.MarginParams memory margin, address token, uint256 denormalizedAmount) internal {
        _updateCoreParams(positionId, ISIStorage.PositionCoreBase(address(0), address(0), 0, 0)); // Clears core parameters
        _updatePositionStatus(positionId, ISIStorage.PositionCoreStatus(false, 2)); // Marks position as cancelled
        _updatePriceParams(positionId, ISIStorage.PriceParams(0, 0, 0, 0)); // Clears price parameters
        _updateMarginParams(positionId, ISIStorage.MarginParams(0, 0, 0)); // Clears margin parameters
        _updateLeverageAndRiskParams(positionId, ISIStorage.LeverageParams(0, 0, 0), ISIStorage.RiskParams(0, 0, 0)); // Clears leverage and risk
        _storageContract.removePositionIndex(positionId, coreBase.positionType, coreBase.listingAddress); // Removes position from index
        _executeMarginPayout(coreBase.listingAddress, coreBase.makerAddress, denormalizedAmount); // Executes payout
    }
}