// SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version 0.0.6:
// - 2025-07-22: Changed _storageContract visibility to internal to allow access in CISExecutionDriver.sol, fixing DeclarationError for undeclared identifier.
// - 2025-07-22: Added ExcessMarginAdded event to support emission in CISExecutionDriver.sol addExcessMargin function.
// - 2025-07-22: Added PositionClosed event in CISExecutionPartial to fix TypeError when emitting event in _processPendingPosition and _processActivePosition.
// - 2025-07-22: Fixed DeclarationError in _computePayoutShort by correcting leverageVal reference to use leverage.leverageVal from LeverageParams struct.
// - 2025-07-22: Fixed TypeError by correcting leverageVal reference from PriceParams to LeverageParams in _computeLoanAndLiquidationLong and _computeLoanAndLiquidationShort.
// - 2025-07-22: Corrected margin ratio calculation to use correct positionId instead of hardcoded 0 in _computeLoanAndLiquidationLong and _computeLoanAndLiquidationShort.
// - 2025-07-21: Updated to use ISIStorage interface inline instead of ICSStorage, adapting struct names and function calls.
// - 2025-07-21: Created CISExecutionPartial contract, adapted from SSDExecutionPartial and CCSExecutionPartial.
// - Implements helper functions for CISExecutionDriver, focusing on isolated margin execution logic.
// - Integrates with ICCOrderRouter for order creation during position activation.
// - Supports immediate execution of zero-bound entry price positions.
// - Uses ISIStorage for state updates via SIUpdate.
// - Compatible with CISExecutionDriver.sol v0.0.4.

import "../imports/SafeERC20.sol";
import "../imports/Ownable.sol";

interface ISSAgent {
    struct ListingDetails {
        address listingAddress;
        address liquidityAddress;
        address tokenA;
        address tokenB;
        uint256 listingId;
    }
    function isValidListing(address listingAddress) external view returns (bool isValid, ISSAgent.ListingDetails memory details);
    function getListing(address tokenA, address tokenB) external view returns (address);
}

interface ISSListing {
    struct UpdateType {
        uint8 updateType;
        uint8 index;
        uint256 value;
        address addr;
        address recipient;
    }
    struct PayoutUpdate {
        uint8 payoutType;
        address recipient;
        uint256 required;
    }
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function liquidityAddressView(address listingAddress) external view returns (address);
    function prices(address listingAddress) external view returns (uint256);
    function update(address caller, UpdateType[] memory updates) external;
    function ssUpdate(address caller, PayoutUpdate[] memory updates) external;
}

interface ISSLiquidityTemplate {
    function addFees(address caller, bool isLong, uint256 amount) external;
    function liquidityDetailsView(address caller) external view returns (uint256, uint256, uint256, uint256);
}

interface ICCOrderRouter {
    function createBuyOrder(
        address listingAddress,
        address recipientAddress,
        uint256 inputAmount,
        uint256 maxPrice,
        uint256 minPrice
    ) external payable;
    function createSellOrder(
        address listingAddress,
        address recipientAddress,
        uint256 inputAmount,
        uint256 maxPrice,
        uint256 minPrice
    ) external payable;
}

// Inline ISIStorage interface
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
    function positionCoreBase(uint256) external view returns (PositionCoreBase memory);
    function positionCoreStatus(uint256) external view returns (PositionCoreStatus memory);
    function priceParams(uint256) external view returns (PriceParams memory);
    function marginParams(uint256) external view returns (MarginParams memory);
    function leverageParams(uint256) external view returns (LeverageParams memory);
    function riskParams(uint256) external view returns (RiskParams memory);
    function positionToken(uint256) external view returns (address);
    function pendingPositions(address, uint8) external view returns (uint256[] memory);
    function positionsByType(uint8) external view returns (uint256[] memory);
    function longIOByHeight(uint256) external view returns (uint256);
    function shortIOByHeight(uint256) external view returns (uint256);
    function positionCount() external view returns (uint256);
    function removePositionIndex(uint256 positionId, uint8 positionType, address listingAddress) external;
    function SIUpdate(
        uint256 positionId,
        string memory coreParams,
        string memory priceData,
        string memory marginData,
        string memory leverageAndRiskParams,
        string memory tokenAndInterestParams,
        string memory positionArrayParams
    ) external;
}

contract CISExecutionPartial is Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant DECIMAL_PRECISION = 1e18; // Precision for normalization
    address private _agentAddress; // Agent contract address
    ISIStorage internal _storageContract; // Storage contract reference, internal for inheritance
    ICCOrderRouter public orderRouter; // Order router reference
    uint256 private _historicalInterestHeight; // Tracks historical interest height

    // Events
    event PositionClosed(uint256 indexed positionId, address indexed maker, uint256 payout); // Emitted when a position is closed
    event ExcessMarginAdded(uint256 indexed positionId, address indexed maker, uint256 amount); // Emitted when excess margin is added

    // Constructor initializes storage contract
    constructor(address storageContractAddress) {
        require(storageContractAddress != address(0), "Invalid storage address"); // Validates storage address
        _storageContract = ISIStorage(storageContractAddress); // Sets storage contract
        _historicalInterestHeight = 1; // Initializes interest height
    }

    // Sets agent address
    function setAgent(address newAgentAddress) external onlyOwner {
        require(newAgentAddress != address(0), "Invalid agent address"); // Validates agent address
        _agentAddress = newAgentAddress; // Updates agent address
    }

    // Sets order router address
    function setOrderRouter(address newOrderRouter) external onlyOwner {
        require(newOrderRouter != address(0), "Invalid order router address"); // Validates order router address
        orderRouter = ICCOrderRouter(newOrderRouter); // Updates order router
    }

    // Returns order router address
    function getOrderRouterView() external view returns (address) {
        return address(orderRouter); // Returns current order router address
    }

    // Returns historical interest height
    function getHistoricalInterestHeightView() external view returns (uint256) {
        return _historicalInterestHeight; // Returns current interest height
    }

    // Helper: Converts bytes to string for SIUpdate
    function _bytesToString(bytes memory data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef"; // Hex alphabet
        bytes memory str = new bytes(2 + data.length * 2); // Allocates string buffer
        str[0] = "0"; // Sets prefix
        str[1] = "x"; // Sets prefix
        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = alphabet[uint8(data[i] >> 4)]; // Encodes high nibble
            str[3 + i * 2] = alphabet[uint8(data[i] & 0x0f)]; // Encodes low nibble
        }
        return string(str); // Returns encoded string
    }

    // Helper: Normalizes price based on token decimals
    function normalizePrice(address token, uint256 price) internal view returns (uint256) {
        uint8 decimals = IERC20(token).decimals(); // Retrieves token decimals
        if (decimals < 18) return price * (10 ** (18 - decimals)); // Adjusts for fewer decimals
        if (decimals > 18) return price / (10 ** (decimals - 18)); // Adjusts for more decimals
        return price; // Returns price if decimals match
    }

    // Helper: Denormalizes amount based on token decimals
    function denormalizeAmount(address token, uint256 amount) internal view returns (uint256) {
        uint8 decimals = IERC20(token).decimals(); // Retrieves token decimals
        return amount * (10 ** decimals) / DECIMAL_PRECISION; // Denormalizes amount
    }

    // Helper: Normalizes amount based on token decimals
    function normalizeAmount(address token, uint256 amount) internal view returns (uint256) {
        uint8 decimals = IERC20(token).decimals(); // Retrieves token decimals
        return amount * DECIMAL_PRECISION / (10 ** decimals); // Normalizes amount
    }

    // Helper: Computes fee based on margin and leverage
    function _computeFee(uint256 initialMargin, uint8 leverage) internal pure returns (uint256) {
        uint256 feePercent = uint256(leverage) - 1; // Calculates fee percentage
        return (initialMargin * feePercent * DECIMAL_PRECISION) / 100 / DECIMAL_PRECISION; // Computes fee
    }

    // Helper: Transfers excess margin to listing
    function _transferExcessMargin(uint256 positionId, uint256 amount, address tokenAddr, address listingAddress) internal returns (uint256) {
        uint256 balanceBefore = IERC20(tokenAddr).balanceOf(listingAddress); // Records balance before transfer
        bool success = IERC20(tokenAddr).transferFrom(msg.sender, listingAddress, amount); // Transfers margin
        require(success, "TransferFrom failed"); // Ensures successful transfer
        uint256 balanceAfter = IERC20(tokenAddr).balanceOf(listingAddress); // Records balance after transfer
        uint256 actualAmount = balanceAfter - balanceBefore; // Calculates actual transferred amount
        require(actualAmount >= amount, "Transfer amount mismatch"); // Verifies transfer amount
        return actualAmount; // Returns actual amount transferred
    }

    // Helper: Updates margin and historical interest
    function _updateMarginAndInterest(uint256 positionId, uint256 actualNormalized, uint8 positionType, address listingAddress) internal {
        ISIStorage.MarginParams memory margin = _storageContract.marginParams(positionId); // Retrieves margin parameters
        _updateMarginParams(positionId, ISIStorage.MarginParams(
            margin.marginInitial,
            margin.marginTaxed,
            margin.marginExcess + actualNormalized
        )); // Updates excess margin
        _transferMarginToListing(listingAddress, actualNormalized, positionType); // Transfers margin to listing
        _updateHistoricalInterest(actualNormalized, positionType, listingAddress, true); // Updates historical interest
    }

    // Helper: Transfers margin to listing contract
    function _transferMarginToListing(address listingAddress, uint256 amount, uint8 positionType) internal {
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](1); // Prepares update array
        updates[0] = ISSListing.UpdateType({
            updateType: positionType,
            index: 0,
            value: amount,
            addr: address(0),
            recipient: address(0)
        }); // Configures margin update
        ISSListing(listingAddress).update(address(this), updates); // Updates listing
    }

    // Helper: Executes margin payout
    function _executeMarginPayout(address listingAddress, address recipient, uint256 amount) internal {
        ISSListing.PayoutUpdate[] memory updates = new ISSListing.PayoutUpdate[](1); // Prepares payout array
        updates[0] = ISSListing.PayoutUpdate({
            payoutType: 0,
            recipient: recipient,
            required: amount
        }); // Configures payout
        ISSListing(listingAddress).ssUpdate(address(this), updates); // Executes payout
    }

    // Helper: Validates excess margin
    function _validateExcessMargin(uint256 positionId, uint256 normalizedAmount) internal view {
        ISIStorage.LeverageParams memory leverage = _storageContract.leverageParams(positionId); // Retrieves leverage parameters
        require(normalizedAmount <= leverage.leverageAmount, "Excess margin exceeds leverage"); // Ensures margin does not exceed leverage
    }

    // Helper: Updates liquidation price
    function _updateLiquidationPrice(uint256 positionId, uint8 positionType) internal {
        ISIStorage.MarginParams memory margin = _storageContract.marginParams(positionId); // Retrieves margin parameters
        ISIStorage.PriceParams memory price = _storageContract.priceParams(positionId); // Retrieves price parameters
        ISIStorage.LeverageParams memory leverage = _storageContract.leverageParams(positionId); // Retrieves leverage parameters
        uint256 leverageAmount = uint256(leverage.leverageVal) * margin.marginInitial; // Calculates leverage amount
        uint256 liquidationPrice;
        if (positionType == 0) {
            address tokenA = ISSListing(_storageContract.positionCoreBase(positionId).listingAddress).tokenA(); // Retrieves tokenA
            (, liquidationPrice) = _computeLoanAndLiquidationLong(leverageAmount, price.priceMin, _storageContract.positionCoreBase(positionId).makerAddress, tokenA, positionId); // Computes liquidation price
        } else {
            address tokenB = ISSListing(_storageContract.positionCoreBase(positionId).listingAddress).tokenB(); // Retrieves tokenB
            (, liquidationPrice) = _computeLoanAndLiquidationShort(leverageAmount, price.priceMin, _storageContract.positionCoreBase(positionId).makerAddress, tokenB, positionId); // Computes liquidation price
        }
        _updateLeverageAndRiskParams(positionId, _storageContract.leverageParams(positionId), ISIStorage.RiskParams(liquidationPrice, _storageContract.riskParams(positionId).priceStopLoss, _storageContract.riskParams(positionId).priceTakeProfit)); // Updates liquidation price
    }

    // Helper: Computes loan and liquidation price for long position
    function _computeLoanAndLiquidationLong(uint256 leverageAmount, uint256 minPrice, address maker, address tokenA, uint256 positionId) internal view returns (uint256 initialLoan, uint256 liquidationPrice) {
        initialLoan = leverageAmount / minPrice; // Calculates initial loan
        uint256 marginRatio = _storageContract.marginParams(positionId).marginInitial / leverageAmount; // Calculates margin ratio using correct positionId
        liquidationPrice = marginRatio < minPrice ? minPrice - marginRatio : 0; // Sets liquidation price
    }

    // Helper: Computes loan and liquidation price for short position
    function _computeLoanAndLiquidationShort(uint256 leverageAmount, uint256 minPrice, address maker, address tokenB, uint256 positionId) internal view returns (uint256 initialLoan, uint256 liquidationPrice) {
        initialLoan = leverageAmount * minPrice; // Calculates initial loan
        uint256 marginRatio = _storageContract.marginParams(positionId).marginInitial / leverageAmount; // Calculates margin ratio using correct positionId
        liquidationPrice = minPrice + marginRatio; // Sets liquidation price
    }

    // Helper: Updates historical interest
    function _updateHistoricalInterest(uint256 amount, uint8 positionType, address listingAddress, bool isAdd) internal {
        uint256 height = _historicalInterestHeight; // Retrieves current height
        uint256 longIO = _storageContract.longIOByHeight(height); // Retrieves long open interest
        uint256 shortIO = _storageContract.shortIOByHeight(height); // Retrieves short open interest
        if (isAdd) {
            longIO = positionType == 0 ? longIO + amount : longIO; // Adds to long interest
            shortIO = positionType == 1 ? shortIO + amount : shortIO; // Adds to short interest
        } else {
            longIO = positionType == 0 ? longIO - amount : longIO; // Subtracts from long interest
            shortIO = positionType == 1 ? shortIO - amount : shortIO; // Subtracts from short interest
        }
        _storageContract.SIUpdate(0, "", "", "", "", _bytesToString(abi.encode(longIO, shortIO)), ""); // Updates interest
        _historicalInterestHeight++; // Increments height
    }

    // Helper: Updates stop-loss price
    function _updateSL(uint256 positionId, uint256 newStopLossPrice) internal {
        ISIStorage.RiskParams memory risk = _storageContract.riskParams(positionId); // Retrieves risk parameters
        _updateLeverageAndRiskParams(positionId, _storageContract.leverageParams(positionId), ISIStorage.RiskParams(risk.priceLiquidation, newStopLossPrice, risk.priceTakeProfit)); // Updates stop-loss
    }

    // Helper: Updates take-profit price
    function _updateTP(uint256 positionId, uint256 newTakeProfitPrice) internal {
        ISIStorage.RiskParams memory risk = _storageContract.riskParams(positionId); // Retrieves risk parameters
        _updateLeverageAndRiskParams(positionId, _storageContract.leverageParams(positionId), ISIStorage.RiskParams(risk.priceLiquidation, risk.priceStopLoss, newTakeProfitPrice)); // Updates take-profit
    }

    // Helper: Computes payout for long position
    function _computePayoutLong(uint256 positionId, address listingAddress) internal view returns (uint256) {
        ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core data
        ISIStorage.MarginParams memory margin = _storageContract.marginParams(positionId); // Retrieves margin data
        ISIStorage.PriceParams memory price = _storageContract.priceParams(positionId); // Retrieves price data
        ISIStorage.LeverageParams memory leverage = _storageContract.leverageParams(positionId); // Retrieves leverage data
        address tokenB = ISSListing(listingAddress).tokenB(); // Retrieves tokenB
        uint256 currentPrice = normalizePrice(tokenB, ISSListing(listingAddress).prices(listingAddress)); // Normalizes current price
        require(currentPrice > 0, "Invalid price"); // Ensures valid price
        uint256 totalMargin = margin.marginTaxed + margin.marginExcess; // Calculates total margin
        uint256 leverageAmount = uint256(leverage.leverageVal) * margin.marginInitial; // Calculates leverage amount
        uint256 baseValue = (totalMargin + leverageAmount) / currentPrice; // Computes base value
        return baseValue > leverage.loanInitial ? baseValue - leverage.loanInitial : 0; // Returns payout
    }

    // Helper: Computes payout for short position
    function _computePayoutShort(uint256 positionId, address listingAddress) internal view returns (uint256) {
        ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core data
        ISIStorage.MarginParams memory margin = _storageContract.marginParams(positionId); // Retrieves margin data
        ISIStorage.PriceParams memory price = _storageContract.priceParams(positionId); // Retrieves price data
        ISIStorage.LeverageParams memory leverage = _storageContract.leverageParams(positionId); // Retrieves leverage data
        address tokenA = ISSListing(listingAddress).tokenA(); // Retrieves tokenA
        uint256 currentPrice = normalizePrice(tokenA, ISSListing(listingAddress).prices(listingAddress)); // Normalizes current price
        require(currentPrice > 0, "Invalid price"); // Ensures valid price
        uint256 totalMargin = margin.marginTaxed + margin.marginExcess; // Calculates total margin
        uint256 priceDiff = price.priceAtEntry > currentPrice ? price.priceAtEntry - currentPrice : 0; // Calculates price difference
        uint256 profit = priceDiff * margin.marginInitial * uint256(leverage.leverageVal); // Computes profit
        return profit + (totalMargin * currentPrice) / DECIMAL_PRECISION; // Returns payout
    }

    // Helper: Prepares closing of long position
    function _prepCloseLong(uint256 positionId, address listingAddress) internal returns (uint256 payout) {
        ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core data
        ISIStorage.MarginParams memory margin = _storageContract.marginParams(positionId); // Retrieves margin data
        address tokenB = ISSListing(listingAddress).tokenB(); // Retrieves tokenB
        payout = _computePayoutLong(positionId, listingAddress); // Computes payout
        uint256 marginAmount = margin.marginTaxed + margin.marginExcess; // Calculates total margin
        _updateCoreParams(positionId, ISIStorage.PositionCoreBase(address(0), address(0), 0, 0)); // Clears core parameters
        _updatePositionStatus(positionId, ISIStorage.PositionCoreStatus(false, 2)); // Marks position as cancelled
        _updatePriceParams(positionId, ISIStorage.PriceParams(0, 0, 0, normalizePrice(tokenB, ISSListing(listingAddress).prices(listingAddress)))); // Sets close price
        _updateMarginParams(positionId, ISIStorage.MarginParams(0, 0, 0)); // Clears margin parameters
        _updateLeverageAndRiskParams(positionId, ISIStorage.LeverageParams(0, 0, 0), ISIStorage.RiskParams(0, 0, 0)); // Clears leverage and risk
        _updateHistoricalInterest(marginAmount, coreBase.positionType, listingAddress, false); // Updates historical interest
        return payout; // Returns payout
    }

    // Helper: Prepares closing of short position
    function _prepCloseShort(uint256 positionId, address listingAddress) internal returns (uint256 payout) {
        ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core data
        ISIStorage.MarginParams memory margin = _storageContract.marginParams(positionId); // Retrieves margin data
        address tokenA = ISSListing(listingAddress).tokenA(); // Retrieves tokenA
        payout = _computePayoutShort(positionId, listingAddress); // Computes payout
        uint256 marginAmount = margin.marginTaxed + margin.marginExcess; // Calculates total margin
        _updateCoreParams(positionId, ISIStorage.PositionCoreBase(address(0), address(0), 0, 0)); // Clears core parameters
        _updatePositionStatus(positionId, ISIStorage.PositionCoreStatus(false, 2)); // Marks position as cancelled
        _updatePriceParams(positionId, ISIStorage.PriceParams(0, 0, 0, normalizePrice(tokenA, ISSListing(listingAddress).prices(listingAddress)))); // Sets close price
        _updateMarginParams(positionId, ISIStorage.MarginParams(0, 0, 0)); // Clears margin parameters
        _updateLeverageAndRiskParams(positionId, ISIStorage.LeverageParams(0, 0, 0), ISIStorage.RiskParams(0, 0, 0)); // Clears leverage and risk
        _updateHistoricalInterest(marginAmount, coreBase.positionType, listingAddress, false); // Updates historical interest
        return payout; // Returns payout
    }

    // Helper: Creates order for position activation
    function _createOrderForPosition(uint256 positionId, uint8 positionType, address listingAddress, uint256 marginAmount) internal {
        address token = positionType == 0 ? ISSListing(listingAddress).tokenA() : ISSListing(listingAddress).tokenB(); // Retrieves token
        uint256 denormalizedMargin = denormalizeAmount(token, marginAmount); // Denormalizes margin
        bool success = IERC20(token).approve(address(orderRouter), denormalizedMargin); // Approves order router
        require(success, "Approval failed"); // Ensures successful approval
        if (positionType == 0) {
            orderRouter.createSellOrder(listingAddress, listingAddress, denormalizedMargin, 0, 0); // Creates sell order for long
        } else {
            orderRouter.createBuyOrder(listingAddress, listingAddress, denormalizedMargin, 0, 0); // Creates buy order for short
        }
    }

    // Helper: Updates excess tokens in listing
    function _updateExcessTokens(address listingAddress, address tokenA, address tokenB) internal {
        uint256 balanceA = IERC20(tokenA).balanceOf(listingAddress); // Retrieves tokenA balance
        uint256 balanceB = IERC20(tokenB).balanceOf(listingAddress); // Retrieves tokenB balance
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](2); // Prepares update array
        updates[0] = ISSListing.UpdateType({
            updateType: 0,
            index: 0,
            value: balanceA,
            addr: tokenA,
            recipient: address(0)
        }); // Updates tokenA balance
        updates[1] = ISSListing.UpdateType({
            updateType: 0,
            index: 1,
            value: balanceB,
            addr: tokenB,
            recipient: address(0)
        }); // Updates tokenB balance
        ISSListing(listingAddress).update(address(this), updates); // Executes update
    }

    // Helper: Processes pending position
    function _processPendingPosition(uint256 positionId, uint8 positionType, address listingAddress, uint256 currentPrice) internal returns (bool continueLoop) {
        ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core data
        ISIStorage.PositionCoreStatus memory coreStatus = _storageContract.positionCoreStatus(positionId); // Retrieves status
        ISIStorage.PriceParams memory price = _storageContract.priceParams(positionId); // Retrieves price data
        ISIStorage.RiskParams memory risk = _storageContract.riskParams(positionId); // Retrieves risk data
        ISIStorage.MarginParams memory margin = _storageContract.marginParams(positionId); // Retrieves margin data
        if (coreBase.positionId == 0 || coreStatus.status2 != 0) return false; // Skips invalid positions
        _updateLiquidationPrice(positionId, positionType); // Updates liquidation price
        risk = _storageContract.riskParams(positionId); // Retrieves updated risk parameters
        bool shouldLiquidate = positionType == 0 ? currentPrice <= risk.priceLiquidation : currentPrice >= risk.priceLiquidation; // Checks liquidation
        if (shouldLiquidate) {
            uint256 payout = positionType == 0 ? _prepCloseLong(positionId, listingAddress) : _prepCloseShort(positionId, listingAddress); // Prepares close
            _storageContract.removePositionIndex(positionId, positionType, listingAddress); // Removes position
            emit PositionClosed(positionId, coreBase.makerAddress, payout); // Emits event
            return true; // Continues loop
        } else if (price.priceMin == 0 && price.priceMax == 0 || (currentPrice >= price.priceMin && currentPrice <= price.priceMax)) {
            uint256 marginAmount = margin.marginTaxed + margin.marginExcess; // Calculates total margin
            _createOrderForPosition(positionId, positionType, listingAddress, marginAmount); // Creates order
            _updateExcessTokens(listingAddress, ISSListing(listingAddress).tokenA(), ISSListing(listingAddress).tokenB()); // Updates token balances
            _updatePositionStatus(positionId, ISIStorage.PositionCoreStatus(true, 0)); // Activates position
            if (price.priceMin == 0 && price.priceMax == 0) {
                _updatePriceParams(positionId, ISIStorage.PriceParams(0, 0, currentPrice, price.priceClose)); // Sets entry price
            }
            return true; // Continues loop
        }
        return false; // No action taken
    }

    // Helper: Processes active position
    function _processActivePosition(uint256 positionId, uint8 positionType, address listingAddress, uint256 currentPrice) internal returns (bool continueLoop) {
        ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core data
        ISIStorage.PositionCoreStatus memory coreStatus = _storageContract.positionCoreStatus(positionId); // Retrieves status
        if (coreBase.positionId == 0 || coreBase.listingAddress != listingAddress || coreStatus.status2 != 0) return false; // Skips invalid positions
        _updateLiquidationPrice(positionId, positionType); // Updates liquidation price
        ISIStorage.RiskParams memory risk = _storageContract.riskParams(positionId); // Retrieves risk parameters
        bool shouldLiquidate = positionType == 0 ? currentPrice <= risk.priceLiquidation : currentPrice >= risk.priceLiquidation; // Checks liquidation
        bool shouldCloseSL = risk.priceStopLoss > 0 && (positionType == 0 ? currentPrice <= risk.priceStopLoss : currentPrice >= risk.priceStopLoss); // Checks stop-loss
        bool shouldCloseTP = risk.priceTakeProfit > 0 && (positionType == 0 ? currentPrice >= risk.priceTakeProfit : currentPrice <= risk.priceTakeProfit); // Checks take-profit
        if (shouldLiquidate || shouldCloseSL || shouldCloseTP) {
            uint256 payout = positionType == 0 ? _prepCloseLong(positionId, listingAddress) : _prepCloseShort(positionId, listingAddress); // Prepares close
            _storageContract.removePositionIndex(positionId, positionType, listingAddress); // Removes position
            emit PositionClosed(positionId, coreBase.makerAddress, payout); // Emits event
            return true; // Continues loop
        }
        return false; // No action taken
    }

    // Helper: Updates core parameters
    function _updateCoreParams(uint256 positionId, ISIStorage.PositionCoreBase memory coreBase) internal {
        _storageContract.SIUpdate(positionId, _bytesToString(abi.encode(coreBase)), "", "", "", "", ""); // Updates core parameters
    }

    // Helper: Updates position status
    function _updatePositionStatus(uint256 positionId, ISIStorage.PositionCoreStatus memory coreStatus) internal {
        _storageContract.SIUpdate(positionId, "", _bytesToString(abi.encode(coreStatus)), "", "", "", ""); // Updates status
    }

    // Helper: Updates price parameters
    function _updatePriceParams(uint256 positionId, ISIStorage.PriceParams memory price) internal {
        _storageContract.SIUpdate(positionId, "", "", _bytesToString(abi.encode(price)), "", "", ""); // Updates price parameters
    }

    // Helper: Updates margin parameters
    function _updateMarginParams(uint256 positionId, ISIStorage.MarginParams memory margin) internal {
        _storageContract.SIUpdate(positionId, "", "", "", _bytesToString(abi.encode(margin)), "", ""); // Updates margin parameters
    }

    // Helper: Updates leverage and risk parameters
    function _updateLeverageAndRiskParams(uint256 positionId, ISIStorage.LeverageParams memory leverage, ISIStorage.RiskParams memory risk) internal {
        _storageContract.SIUpdate(positionId, "", "", "", "", _bytesToString(abi.encode(leverage, risk)), ""); // Updates leverage and risk parameters
    }

    // Helper: Executes positions
    function _executePositions(address listingAddress, uint256 maxIterations) internal {
        require(listingAddress != address(0), "Invalid listing address"); // Validates listing address
        (bool isValid, ) = ISSAgent(_agentAddress).isValidListing(listingAddress); // Checks listing validity
        require(isValid, "Invalid listing"); // Ensures valid listing
        for (uint8 positionType = 0; positionType <= 1; positionType++) {
            uint256[] memory pending = _storageContract.pendingPositions(listingAddress, positionType); // Retrieves pending positions
            uint256 processed = 0; // Tracks processed positions
            for (uint256 i = 0; i < pending.length && processed < maxIterations && gasleft() >= 50000; i++) {
                uint256 positionId = pending[i]; // Retrieves position ID
                address token = positionType == 0 ? ISSListing(listingAddress).tokenB() : ISSListing(listingAddress).tokenA(); // Retrieves token
                uint256 currentPrice = normalizePrice(token, ISSListing(listingAddress).prices(listingAddress)); // Normalizes current price
                if (_processPendingPosition(positionId, positionType, listingAddress, currentPrice)) {
                    i--; // Adjusts index after removal
                }
                processed++; // Increments processed count
            }
            uint256[] memory active = _storageContract.positionsByType(positionType); // Retrieves active positions
            for (uint256 i = 0; i < active.length && processed < maxIterations && gasleft() >= 50000; i++) {
                uint256 positionId = active[i]; // Retrieves position ID
                address token = positionType == 0 ? ISSListing(listingAddress).tokenB() : ISSListing(listingAddress).tokenA(); // Retrieves token
                uint256 currentPrice = normalizePrice(token, ISSListing(listingAddress).prices(listingAddress)); // Normalizes current price
                if (_processActivePosition(positionId, positionType, listingAddress, currentPrice)) {
                    i--; // Adjusts index after removal
                }
                processed++; // Increments processed count
            }
        }
    }
}