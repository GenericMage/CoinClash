// SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version 0.0.2:
// - 2025-08-10: Removed view modifier from _computePayoutLong, _computePayoutShort, and _validateExcessMargin due to event emissions.
// - No other functional changes.

import "../imports/ReentrancyGuard.sol";

interface IERC20 {
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ISSAgent {
    struct ListingDetails {
        address listingAddress;
        address liquidityAddress;
        address tokenA;
        address tokenB;
        uint256 listingId;
    }
    function isValidListing(address listingAddress) external view returns (bool isValid, ListingDetails memory details);
}

interface ISSListing {
    struct UpdateType {
        uint8 updateType;
        uint8 structId;
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 amountSent;
    }
    struct PayoutUpdate {
        uint8 payoutType;
        address recipient;
        uint256 required;
    }
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function liquidityAddressView() external view returns (address);
    function prices(address listingAddress) external view returns (uint256);
    function update(UpdateType[] memory updates) external;
    function ssUpdate(PayoutUpdate[] memory updates) external;
}

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
    struct CoreParams {
        address makerAddress;
        address listingAddress;
        uint256 corePositionId;
        uint8 positionType;
        bool status1;
        uint8 status2;
    }
    struct TokenAndInterestParams {
        address token;
        uint256 longIO;
        uint256 shortIO;
        uint256 timestamp;
    }
    struct PositionArrayParams {
        address listingAddress;
        uint8 positionType;
        bool addToPending;
        bool addToActive;
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
        CoreParams memory coreData,
        PriceParams memory priceData,
        MarginParams memory marginData,
        LeverageParams memory leverageData,
        RiskParams memory riskData,
        TokenAndInterestParams memory tokenData,
        PositionArrayParams memory arrayData
    ) external;
}

contract CISLiquidationPartial is ReentrancyGuard {
    uint256 public constant DECIMAL_PRECISION = 1e18; // Precision for normalization
    address private _agentAddress; // Agent contract address
    ISIStorage internal _storageContract; // Storage contract reference
    uint256 private _historicalInterestHeight; // Tracks historical interest height

    // Events
    event PositionClosed(uint256 indexed positionId, address indexed maker, uint256 payout); // Emitted when a position is closed
    event ExcessMarginAdded(uint256 indexed positionId, address indexed maker, uint256 amount); // Emitted when excess margin is added
    event ErrorLogged(string reason); // Emitted for error logging

    // Constructor initializes storage contract
    constructor(address storageContractAddress) {
        if (storageContractAddress == address(0)) {
            emit ErrorLogged("Constructor: Storage address is zero");
            revert("Constructor: Invalid storage address");
        }
        _storageContract = ISIStorage(storageContractAddress); // Sets storage contract
        _historicalInterestHeight = 1; // Initializes interest height
    }

    // Sets agent address
    function setAgent(address newAgentAddress) external onlyOwner {
        if (newAgentAddress == address(0)) {
            emit ErrorLogged("setAgent: Agent address is zero");
            revert("setAgent: Invalid agent address");
        }
        _agentAddress = newAgentAddress; // Updates agent address
    }

    // Helper: Normalizes price based on token decimals
    function normalizePrice(address token, uint256 price) internal view returns (uint256 normalizedPrice) {
        uint8 decimals = IERC20(token).decimals(); // Retrieves token decimals
        if (decimals < 18) return price * (10 ** (18 - decimals)); // Adjusts for fewer decimals
        if (decimals > 18) return price / (10 ** (decimals - 18)); // Adjusts for more decimals
        return price; // Returns price if decimals match
    }

    // Helper: Denormalizes amount based on token decimals
    function denormalizeAmount(address token, uint256 amount) internal view returns (uint256 denormalizedAmount) {
        uint8 decimals = IERC20(token).decimals(); // Retrieves token decimals
        denormalizedAmount = amount * (10 ** decimals) / DECIMAL_PRECISION; // Denormalizes amount
    }

    // Helper: Normalizes amount based on token decimals
    function normalizeAmount(address token, uint256 amount) internal view returns (uint256 normalizedAmount) {
        uint8 decimals = IERC20(token).decimals(); // Retrieves token decimals
        normalizedAmount = amount * DECIMAL_PRECISION / (10 ** decimals); // Normalizes amount
    }

    // Helper: Computes fee based on margin and leverage
    function _computeFee(uint256 initialMargin, uint8 leverage) internal pure returns (uint256 fee) {
        uint256 feePercent = uint256(leverage) - 1; // Calculates fee percentage
        fee = (initialMargin * feePercent * DECIMAL_PRECISION) / 100 / DECIMAL_PRECISION; // Computes fee
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
        _storageContract.SIUpdate(
            0,
            ISIStorage.CoreParams(address(0), address(0), 0, 0, false, 0),
            ISIStorage.PriceParams(0, 0, 0, 0),
            ISIStorage.MarginParams(0, 0, 0),
            ISIStorage.LeverageParams(0, 0, 0),
            ISIStorage.RiskParams(0, 0, 0),
            ISIStorage.TokenAndInterestParams(address(0), longIO, shortIO, block.timestamp),
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        ); // Updates interest
        _historicalInterestHeight++; // Increments height
    }

    // Helper: Transfers excess margin to listing
    function _transferExcessMargin(uint256 positionId, uint256 amount, address tokenAddr, address listingAddress) internal returns (uint256 actualAmount) {
        uint256 balanceBefore = IERC20(tokenAddr).balanceOf(listingAddress); // Records balance before transfer
        bool success = IERC20(tokenAddr).transferFrom(msg.sender, listingAddress, amount); // Transfers margin
        if (!success) {
            emit ErrorLogged(string(abi.encodePacked("transferExcessMargin: TransferFrom failed for position ", positionId)));
            revert("transferExcessMargin: TransferFrom failed");
        }
        uint256 balanceAfter = IERC20(tokenAddr).balanceOf(listingAddress); // Records balance after transfer
        actualAmount = balanceAfter - balanceBefore; // Calculates actual transferred amount
        if (actualAmount < amount) {
            emit ErrorLogged(string(abi.encodePacked("transferExcessMargin: Transfer amount mismatch for position ", positionId)));
            revert("transferExcessMargin: Transfer amount mismatch");
        }
    }

    // Helper: Updates margin and historical interest
    function _updateMarginAndInterest(uint256 positionId, uint256 actualNormalized, uint8 positionType, address listingAddress) internal {
        ISIStorage.MarginParams memory margin = _storageContract.marginParams(positionId); // Retrieves margin parameters
        _storageContract.SIUpdate(
            positionId,
            ISIStorage.CoreParams(address(0), address(0), 0, 0, false, 0),
            ISIStorage.PriceParams(0, 0, 0, 0),
            ISIStorage.MarginParams(margin.marginInitial, margin.marginTaxed, margin.marginExcess + actualNormalized),
            ISIStorage.LeverageParams(0, 0, 0),
            ISIStorage.RiskParams(0, 0, 0),
            ISIStorage.TokenAndInterestParams(address(0), 0, 0, 0),
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        ); // Updates excess margin
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](1); // Prepares update array
        updates[0] = ISSListing.UpdateType({
            updateType: positionType,
            structId: 0,
            index: 0,
            value: actualNormalized,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        }); // Configures margin update
        ISSListing(listingAddress).update(updates); // Updates listing
        _updateHistoricalInterest(actualNormalized, positionType, listingAddress, true); // Updates historical interest
    }

    // Helper: Executes margin payout
    function _executeMarginPayout(address listingAddress, address recipient, uint256 amount) internal {
        ISSListing.PayoutUpdate[] memory updates = new ISSListing.PayoutUpdate[](1); // Prepares payout array
        updates[0] = ISSListing.PayoutUpdate({
            payoutType: 0,
            recipient: recipient,
            required: amount
        }); // Configures payout
        ISSListing(listingAddress).ssUpdate(updates); // Executes payout
    }

    // Helper: Validates excess margin
    function _validateExcessMargin(uint256 positionId, uint256 normalizedAmount) internal {
        ISIStorage.LeverageParams memory leverage = _storageContract.leverageParams(positionId); // Retrieves leverage parameters
        if (normalizedAmount > leverage.leverageAmount) {
            emit ErrorLogged(string(abi.encodePacked("validateExcessMargin: Excess margin exceeds leverage for position ", positionId)));
            revert("validateExcessMargin: Excess margin exceeds leverage");
        }
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
        ISIStorage.RiskParams memory risk = _storageContract.riskParams(positionId); // Retrieves risk parameters
        _storageContract.SIUpdate(
            positionId,
            ISIStorage.CoreParams(address(0), address(0), 0, 0, false, 0),
            ISIStorage.PriceParams(0, 0, 0, 0),
            ISIStorage.MarginParams(0, 0, 0),
            leverage,
            ISIStorage.RiskParams(liquidationPrice, risk.priceStopLoss, risk.priceTakeProfit),
            ISIStorage.TokenAndInterestParams(address(0), 0, 0, 0),
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        ); // Updates liquidation price
    }

    // Helper: Computes loan and liquidation price for long position
    function _computeLoanAndLiquidationLong(uint256 leverageAmount, uint256 minPrice, address maker, address tokenA, uint256 positionId) internal view returns (uint256 initialLoan, uint256 liquidationPrice) {
        initialLoan = leverageAmount / minPrice; // Calculates initial loan
        uint256 marginRatio = _storageContract.marginParams(positionId).marginInitial / leverageAmount; // Calculates margin ratio
        liquidationPrice = marginRatio < minPrice ? minPrice - marginRatio : 0; // Sets liquidation price
    }

    // Helper: Computes loan and liquidation price for short position
    function _computeLoanAndLiquidationShort(uint256 leverageAmount, uint256 minPrice, address maker, address tokenB, uint256 positionId) internal view returns (uint256 initialLoan, uint256 liquidationPrice) {
        initialLoan = leverageAmount * minPrice; // Calculates initial loan
        uint256 marginRatio = _storageContract.marginParams(positionId).marginInitial / leverageAmount; // Calculates margin ratio
        liquidationPrice = minPrice + marginRatio; // Sets liquidation price
    }

    // Helper: Computes payout for long position
    function _computePayoutLong(uint256 positionId, address listingAddress) internal returns (uint256 payout) {
        ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core data
        ISIStorage.MarginParams memory margin = _storageContract.marginParams(positionId); // Retrieves margin data
        ISIStorage.PriceParams memory price = _storageContract.priceParams(positionId); // Retrieves price data
        ISIStorage.LeverageParams memory leverage = _storageContract.leverageParams(positionId); // Retrieves leverage data
        address tokenB = ISSListing(listingAddress).tokenB(); // Retrieves tokenB
        uint256 currentPrice = normalizePrice(tokenB, ISSListing(listingAddress).prices(listingAddress)); // Normalizes current price
        if (currentPrice == 0) {
            emit ErrorLogged(string(abi.encodePacked("computePayoutLong: Invalid price for position ", positionId)));
            revert("computePayoutLong: Invalid price");
        }
        uint256 totalMargin = margin.marginTaxed + margin.marginExcess; // Calculates total margin
        uint256 leverageAmount = uint256(leverage.leverageVal) * margin.marginInitial; // Calculates leverage amount
        uint256 baseValue = (totalMargin + leverageAmount) / currentPrice; // Computes base value
        payout = baseValue > leverage.loanInitial ? baseValue - leverage.loanInitial : 0; // Returns payout
    }

    // Helper: Computes payout for short position
    function _computePayoutShort(uint256 positionId, address listingAddress) internal returns (uint256 payout) {
        ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core data
        ISIStorage.MarginParams memory margin = _storageContract.marginParams(positionId); // Retrieves margin data
        ISIStorage.PriceParams memory price = _storageContract.priceParams(positionId); // Retrieves price data
        ISIStorage.LeverageParams memory leverage = _storageContract.leverageParams(positionId); // Retrieves leverage data
        address tokenA = ISSListing(listingAddress).tokenA(); // Retrieves tokenA
        uint256 currentPrice = normalizePrice(tokenA, ISSListing(listingAddress).prices(listingAddress)); // Normalizes current price
        if (currentPrice == 0) {
            emit ErrorLogged(string(abi.encodePacked("computePayoutShort: Invalid price for position ", positionId)));
            revert("computePayoutShort: Invalid price");
        }
        uint256 totalMargin = margin.marginTaxed + margin.marginExcess; // Calculates total margin
        uint256 priceDiff = price.priceAtEntry > currentPrice ? price.priceAtEntry - currentPrice : 0; // Calculates price difference
        uint256 profit = priceDiff * margin.marginInitial * uint256(leverage.leverageVal); // Computes profit
        payout = profit + (totalMargin * currentPrice) / DECIMAL_PRECISION; // Returns payout
    }

    // Helper: Processes active position
    function _processActivePosition(uint256 positionId, uint8 positionType, address listingAddress, uint256 currentPrice) internal returns (bool continueLoop) {
        ISIStorage.PositionCoreBase memory coreBase = _storageContract.positionCoreBase(positionId); // Retrieves core data
        if (coreBase.positionId == 0 || coreBase.listingAddress != listingAddress) {
            emit ErrorLogged(string(abi.encodePacked("processActivePosition: Invalid position or listing for ", positionId)));
            return false;
        }
        ISIStorage.PositionCoreStatus memory coreStatus = _storageContract.positionCoreStatus(positionId); // Retrieves status
        if (coreStatus.status2 != 0) {
            emit ErrorLogged(string(abi.encodePacked("processActivePosition: Position ", positionId, " is closed")));
            return false;
        }
        _updateLiquidationPrice(positionId, positionType); // Updates liquidation price
        ISIStorage.RiskParams memory risk = _storageContract.riskParams(positionId); // Retrieves risk parameters
        bool shouldLiquidate = positionType == 0 ? currentPrice <= risk.priceLiquidation : currentPrice >= risk.priceLiquidation; // Checks liquidation
        bool shouldCloseSL = risk.priceStopLoss > 0 && (positionType == 0 ? currentPrice <= risk.priceStopLoss : currentPrice >= risk.priceStopLoss); // Checks stop-loss
        bool shouldCloseTP = risk.priceTakeProfit > 0 && (positionType == 0 ? currentPrice >= risk.priceTakeProfit : currentPrice <= risk.priceTakeProfit); // Checks take-profit
        if (shouldLiquidate || shouldCloseSL || shouldCloseTP) {
            uint256 payout = positionType == 0 ? _computePayoutLong(positionId, listingAddress) : _computePayoutShort(positionId, listingAddress); // Computes payout
            _storageContract.removePositionIndex(positionId, positionType, listingAddress); // Removes position
            emit PositionClosed(positionId, coreBase.makerAddress, payout); // Emits event
            return true; // Continues loop
        }
        return false; // No action taken
    }

    // Helper: Executes active positions
    function _executeExits(address listingAddress, uint256 maxIterations) internal {
        if (listingAddress == address(0)) {
            emit ErrorLogged("executeExits: Listing address is zero");
            revert("executeExits: Invalid listing address");
        }
        (bool isValid, ) = ISSAgent(_agentAddress).isValidListing(listingAddress); // Checks listing validity
        if (!isValid) {
            emit ErrorLogged("executeExits: Listing is invalid");
            revert("executeExits: Invalid listing");
        }
        for (uint8 positionType = 0; positionType <= 1; positionType++) {
            uint256[] memory active = _storageContract.positionsByType(positionType); // Retrieves active positions
            uint256 processed = 0; // Tracks processed positions
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