// SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version 0.0.11:
// - 2025-08-09: Refactored _processPendingPosition into a call tree to fix stack too deep error.
// - 2025-08-09: Added PendingPositionData struct and helper functions (_fetchPositionData, _validatePosition, _updateListingBalances, _finalizePosition).
// - 2025-08-09: Ensured no code bloat, reused existing update functions, and verified no compiler errors.
// - Compatible with CISExecutionDriver.sol v0.0.8.

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

contract CISExecutionPartial is ReentrancyGuard {
    uint256 public constant DECIMAL_PRECISION = 1e18;
    address private _agentAddress;
    ISIStorage internal _storageContract;
    ICCOrderRouter public orderRouter;
    uint256 private _historicalInterestHeight;

    event ErrorLogged(string reason);

    constructor(address storageContractAddress) {
        if (storageContractAddress == address(0)) {
            emit ErrorLogged("Constructor: Storage address is zero");
            revert("Constructor: Invalid storage address");
        }
        _storageContract = ISIStorage(storageContractAddress);
        _historicalInterestHeight = 1;
    }

    function setAgent(address newAgentAddress) external onlyOwner {
        if (newAgentAddress == address(0)) {
            emit ErrorLogged("setAgent: Agent address is zero");
            revert("setAgent: Invalid agent address");
        }
        _agentAddress = newAgentAddress;
    }

    function setOrderRouter(address newOrderRouter) external onlyOwner {
        if (newOrderRouter == address(0)) {
            emit ErrorLogged("setOrderRouter: Order router address is zero");
            revert("setOrderRouter: Invalid order router address");
        }
        orderRouter = ICCOrderRouter(newOrderRouter);
    }

    function getOrderRouterView() external view returns (address routerAddress) {
        routerAddress = address(orderRouter);
    }

    function getHistoricalInterestHeightView() external view returns (uint256 height) {
        height = _historicalInterestHeight;
    }

    function normalizePrice(address token, uint256 price) internal view returns (uint256 normalizedPrice) {
        uint8 decimals = IERC20(token).decimals();
        if (decimals < 18) return price * (10 ** (18 - decimals));
        if (decimals > 18) return price / (10 ** (decimals - 18));
        return price;
    }

    function denormalizeAmount(address token, uint256 amount) internal view returns (uint256 denormalizedAmount) {
        uint8 decimals = IERC20(token).decimals();
        denormalizedAmount = amount * (10 ** decimals) / DECIMAL_PRECISION;
    }

    function normalizeAmount(address token, uint256 amount) internal view returns (uint256 normalizedAmount) {
        uint8 decimals = IERC20(token).decimals();
        normalizedAmount = amount * DECIMAL_PRECISION / (10 ** decimals);
    }

    function _computeFee(uint256 initialMargin, uint8 leverage) internal pure returns (uint256 fee) {
        uint256 feePercent = uint256(leverage) - 1;
        fee = (initialMargin * feePercent * DECIMAL_PRECISION) / 100 / DECIMAL_PRECISION;
    }

    function _updateHistoricalInterest(uint256 amount, uint8 positionType, address listingAddress, bool isAdd) internal {
        uint256 height = _historicalInterestHeight;
        uint256 longIO = _storageContract.longIOByHeight(height);
        uint256 shortIO = _storageContract.shortIOByHeight(height);
        if (isAdd) {
            longIO = positionType == 0 ? longIO + amount : longIO;
            shortIO = positionType == 1 ? shortIO + amount : shortIO;
        } else {
            longIO = positionType == 0 ? longIO - amount : longIO;
            shortIO = positionType == 1 ? shortIO - amount : shortIO;
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
        );
        _historicalInterestHeight++;
    }

    function _updateSL(uint256 positionId, uint256 newStopLossPrice) internal {
        ISIStorage.RiskParams memory risk = _storageContract.riskParams(positionId);
        _storageContract.SIUpdate(
            positionId,
            ISIStorage.CoreParams(address(0), address(0), 0, 0, false, 0),
            ISIStorage.PriceParams(0, 0, 0, 0),
            ISIStorage.MarginParams(0, 0, 0),
            ISIStorage.LeverageParams(0, 0, 0),
            ISIStorage.RiskParams(risk.priceLiquidation, newStopLossPrice, risk.priceTakeProfit),
            ISIStorage.TokenAndInterestParams(address(0), 0, 0, 0),
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        );
    }

    function _updateTP(uint256 positionId, uint256 newTakeProfitPrice) internal {
        ISIStorage.RiskParams memory risk = _storageContract.riskParams(positionId);
        _storageContract.SIUpdate(
            positionId,
            ISIStorage.CoreParams(address(0), address(0), 0, 0, false, 0),
            ISIStorage.PriceParams(0, 0, 0, 0),
            ISIStorage.MarginParams(0, 0, 0),
            ISIStorage.LeverageParams(0, 0, 0),
            ISIStorage.RiskParams(risk.priceLiquidation, risk.priceStopLoss, newTakeProfitPrice),
            ISIStorage.TokenAndInterestParams(address(0), 0, 0, 0),
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        );
    }

    function _updateCoreParams(uint256 positionId, ISIStorage.PositionCoreBase memory coreBase) internal {
        _storageContract.SIUpdate(
            positionId,
            ISIStorage.CoreParams(coreBase.makerAddress, coreBase.listingAddress, coreBase.positionId, coreBase.positionType, false, 0),
            ISIStorage.PriceParams(0, 0, 0, 0),
            ISIStorage.MarginParams(0, 0, 0),
            ISIStorage.LeverageParams(0, 0, 0),
            ISIStorage.RiskParams(0, 0, 0),
            ISIStorage.TokenAndInterestParams(address(0), 0, 0, 0),
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        );
    }

    function _updatePositionStatus(uint256 positionId, ISIStorage.PositionCoreStatus memory coreStatus) internal {
        _storageContract.SIUpdate(
            positionId,
            ISIStorage.CoreParams(address(0), address(0), 0, 0, coreStatus.status1, coreStatus.status2),
            ISIStorage.PriceParams(0, 0, 0, 0),
            ISIStorage.MarginParams(0, 0, 0),
            ISIStorage.LeverageParams(0, 0, 0),
            ISIStorage.RiskParams(0, 0, 0),
            ISIStorage.TokenAndInterestParams(address(0), 0, 0, 0),
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        );
    }

    function _updatePriceParams(uint256 positionId, ISIStorage.PriceParams memory price) internal {
        _storageContract.SIUpdate(
            positionId,
            ISIStorage.CoreParams(address(0), address(0), 0, 0, false, 0),
            price,
            ISIStorage.MarginParams(0, 0, 0),
            ISIStorage.LeverageParams(0, 0, 0),
            ISIStorage.RiskParams(0, 0, 0),
            ISIStorage.TokenAndInterestParams(address(0), 0, 0, 0),
            ISIStorage.PositionArrayParams(address(0), 0, false, false)
        );
    }

    // Struct to hold pending position data
    struct PendingPositionData {
        ISIStorage.PositionCoreBase coreBase;
        ISIStorage.PositionCoreStatus coreStatus;
        ISIStorage.PriceParams price;
        ISIStorage.RiskParams risk;
        ISIStorage.MarginParams margin;
        address tokenA;
        address tokenB;
        uint256 balanceA;
        uint256 balanceB;
        uint256 marginAmount;
    }

    // Fetches position data
    function _fetchPositionData(uint256 positionId, address listingAddress) private view returns (PendingPositionData memory data) {
        data.coreBase = _storageContract.positionCoreBase(positionId);
        data.coreStatus = _storageContract.positionCoreStatus(positionId);
        data.price = _storageContract.priceParams(positionId);
        data.risk = _storageContract.riskParams(positionId);
        data.margin = _storageContract.marginParams(positionId);
        data.tokenA = ISSListing(listingAddress).tokenA();
        data.tokenB = ISSListing(listingAddress).tokenB();
        data.balanceA = IERC20(data.tokenA).balanceOf(listingAddress);
        data.balanceB = IERC20(data.tokenB).balanceOf(listingAddress);
        data.marginAmount = data.margin.marginTaxed + data.margin.marginExcess;
    }

    // Validates position
    function _validatePosition(uint256 positionId, PendingPositionData memory data) private returns (bool isValid) {
        if (data.coreBase.positionId == 0) {
            emit ErrorLogged(string(abi.encodePacked("processPendingPosition: Position ", positionId, " does not exist")));
            return false;
        }
        if (data.coreStatus.status2 != 0) {
            emit ErrorLogged(string(abi.encodePacked("processPendingPosition: Position ", positionId, " is closed")));
            return false;
        }
        return true;
    }

    // Updates listing balances
    function _updateListingBalances(address listingAddress, PendingPositionData memory data) private {
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](2);
        updates[0] = ISSListing.UpdateType({
            updateType: 0,
            structId: 0,
            index: 0,
            value: data.balanceA,
            addr: data.tokenA,
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        updates[1] = ISSListing.UpdateType({
            updateType: 0,
            structId: 0,
            index: 1,
            value: data.balanceB,
            addr: data.tokenB,
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        ISSListing(listingAddress).update(updates);
    }

    // Finalizes position status and price
    function _finalizePosition(uint256 positionId, PendingPositionData memory data, uint256 currentPrice) private {
        _updatePositionStatus(positionId, ISIStorage.PositionCoreStatus(true, 0));
        if (data.price.priceMin == 0 && data.price.priceMax == 0) {
            _updatePriceParams(positionId, ISIStorage.PriceParams(0, 0, currentPrice, data.price.priceClose));
        }
    }

    // Processes pending position
    function _processPendingPosition(uint256 positionId, uint8 positionType, address listingAddress, uint256 currentPrice) internal returns (bool continueLoop) {
        PendingPositionData memory data = _fetchPositionData(positionId, listingAddress);
        if (!_validatePosition(positionId, data)) {
            return false;
        }
        if (data.price.priceMin == 0 && data.price.priceMax == 0 || (currentPrice >= data.price.priceMin && currentPrice <= data.price.priceMax)) {
            _updateListingBalances(listingAddress, data);
            _finalizePosition(positionId, data, currentPrice);
            return true;
        }
        return false;
    }

    // Executes pending positions
    function _executeEntries(address listingAddress, uint256 maxIterations) internal {
        if (listingAddress == address(0)) {
            emit ErrorLogged("executeEntries: Listing address is zero");
            revert("executeEntries: Invalid listing address");
        }
        (bool isValid, ) = ISSAgent(_agentAddress).isValidListing(listingAddress);
        if (!isValid) {
            emit ErrorLogged("executeEntries: Listing is invalid");
            revert("executeEntries: Invalid listing");
        }
        for (uint8 positionType = 0; positionType <= 1; positionType++) {
            uint256[] memory pending = _storageContract.pendingPositions(listingAddress, positionType);
            uint256 processed = 0;
            for (uint256 i = 0; i < pending.length && processed < maxIterations && gasleft() >= 50000; i++) {
                uint256 positionId = pending[i];
                address token = positionType == 0 ? ISSListing(listingAddress).tokenB() : ISSListing(listingAddress).tokenA();
                uint256 currentPrice = normalizePrice(token, ISSListing(listingAddress).prices(listingAddress));
                if (_processPendingPosition(positionId, positionType, listingAddress, currentPrice)) {
                    i--;
                }
                processed++;
            }
        }
    }
}