/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-08-07: Added _executeMarginPayout and _reduceMakerMargin to resolve undeclared identifiers in CCSLiquidationDriver.sol. Incremented version to 0.0.24.
 - 2025-08-07: Added _updateLiquidationPrices and _updateMakerMarginParams to resolve undeclared identifiers. Moved _handlePositionClosure to CCSExtraPartial.sol due to dependencies on _prepCloseLong and _prepCloseShort. Incremented version to 0.0.23.
 - 2025-08-06: Removed unused setOrderRouter function. Moved cancellation logic (_prepareCancelPosition, _updatePositionParams, _updateMarginAndIndex) to CCSExtraPartial.sol. Incremented version to 0.0.22.
 - 2025-08-06: Renamed _executeExitsPartial to _executeExitsInternal and changed visibility to internal. Incremented version to 0.0.21.
 - 2025-08-06: Removed view modifier from _checkPositionConditions. Incremented version to 0.0.20.
*/

pragma solidity ^0.8.2;

import "../imports/IERC20.sol";
import "../imports/ReentrancyGuard.sol";

interface ICCAgent {
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
    struct ListingPayoutUpdate {
        uint8 payoutType;
        address recipient;
        uint256 required;
    }
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
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function prices(uint256) external view returns (uint256);
    function update(UpdateType[] calldata updates) external;
    function ssUpdate(ListingPayoutUpdate[] calldata updates) external;
    function liquidityAddressView() external view returns (address);
}

interface ISSLiquidityTemplate {
    function addFees(address caller, bool isLong, uint256 amount) external;
}

interface ICSStorage {
    event PositionClosed(uint256 indexed positionId, address indexed maker, uint256 payout);
    event ExternalCallFailed(string functionName, string reason);
    function DECIMAL_PRECISION() external view returns (uint256 precision);
    function agentAddress() external view returns (address agent);
    function positionCount() external view returns (uint256 count);
    struct PositionCore1 {
        uint256 positionId;
        address listingAddress;
        address makerAddress;
        uint8 positionType;
    }
    struct PositionCore2 {
        bool status1;
        uint8 status2;
    }
    struct PriceParams1 {
        uint256 minEntryPrice;
        uint256 maxEntryPrice;
        uint256 minPrice;
        uint256 priceAtEntry;
        uint8 leverage;
    }
    struct PriceParams2 {
        uint256 liquidationPrice;
    }
    struct MarginParams1 {
        uint256 initialMargin;
        uint256 taxedMargin;
        uint256 excessMargin;
        uint256 fee;
    }
    struct MarginParams2 {
        uint256 initialLoan;
    }
    struct ExitParams {
        uint256 stopLossPrice;
        uint256 takeProfitPrice;
        uint256 exitPrice;
    }
    struct HistoricalInterestParams {
        uint256 longIO;
        uint256 shortIO;
        uint256 timestamp;
    }
    struct CoreParams {
        uint256 positionId;
        address listingAddress;
        address makerAddress;
        uint8 positionType;
        bool status1;
        uint8 status2;
    }
    struct PriceParams {
        uint256 minEntryPrice;
        uint256 maxEntryPrice;
        uint256 minPrice;
        uint256 priceAtEntry;
        uint8 leverage;
        uint256 liquidationPrice;
    }
    struct MarginParams {
        uint256 initialMargin;
        uint256 taxedMargin;
        uint256 excessMargin;
        uint256 fee;
        uint256 initialLoan;
    }
    struct ExitAndInterestParams {
        uint256 stopLossPrice;
        uint256 takeProfitPrice;
        uint256 exitPrice;
        uint256 leverageAmount;
        uint256 timestamp;
    }
    struct MakerMarginParams {
        address token;
        address maker;
        address marginToken;
        uint256 marginAmount;
    }
    struct PositionArrayParams {
        address listingAddress;
        uint8 positionType;
        bool addToPending;
        bool addToActive;
    }
    function makerTokenMargin(address maker, address token) external view returns (uint256 margin);
    function positionCore1(uint256 positionId) external view returns (PositionCore1 memory core);
    function positionCore2(uint256 positionId) external view returns (PositionCore2 memory status);
    function priceParams1(uint256 positionId) external view returns (PriceParams1 memory params);
    function priceParams2(uint256 positionId) external view returns (PriceParams2 memory params);
    function marginParams1(uint256 positionId) external view returns (MarginParams1 memory params);
    function marginParams2(uint256 positionId) external view returns (MarginParams2 memory params);
    function exitParams(uint256 positionId) external view returns (ExitParams memory params);
    function positionToken(uint256 positionId) external view returns (address token);
    function positionsByType(uint8 positionType) external view returns (uint256[] memory positionIds);
    function longIOByHeight(uint256 height) external view returns (uint256 longIO);
    function shortIOByHeight(uint256 height) external view returns (uint256 shortIO);
    function CSUpdate(
        uint256 positionId,
        CoreParams memory coreParams,
        PriceParams memory priceParams,
        MarginParams memory marginParams,
        ExitAndInterestParams memory exitAndInterestParams,
        MakerMarginParams memory makerMarginParams,
        PositionArrayParams memory positionArrayParams,
        HistoricalInterestParams memory historicalInterestParams
    ) external;
    function removePositionIndex(uint256 positionId, uint8 positionType, address listingAddress) external;
    function removeToken(address maker, address token) external;
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

contract CCSLiquidationPartial is ReentrancyGuard {
    uint256 public constant DECIMAL_PRECISION = 1e18;
    address public agentAddress;
    ICSStorage public storageContract;
    ICCOrderRouter public orderRouter;

    struct PositionCheck {
        bool shouldLiquidate;
        bool shouldStopLoss;
        bool shouldTakeProfit;
        uint256 payout;
    }
    mapping(uint256 => PositionCheck) private _tempPositionData;

    constructor(address _storageContract) {
        require(_storageContract != address(0), "Storage contract address cannot be zero"); // Validates storage contract
        storageContract = ICSStorage(_storageContract);
    }

    function setAgent(address newAgentAddress) external onlyOwner {
        require(newAgentAddress != address(0), "Agent address cannot be zero"); // Validates agent address
        agentAddress = newAgentAddress;
    }

    function normalizePrice(address token, uint256 price) internal view returns (uint256 normalizedPrice) {
        require(token != address(0), "Token address cannot be zero"); // Validates token
        uint8 decimals = IERC20(token).decimals();
        if (decimals < 18) return price * (10 ** (18 - decimals));
        if (decimals > 18) return price / (10 ** (decimals - 18));
        return price;
    }

    function denormalizeAmount(address token, uint256 amount) internal view returns (uint256 denormalizedAmount) {
        require(token != address(0), "Token address cannot be zero"); // Validates token
        uint8 decimals = IERC20(token).decimals();
        return amount * (10 ** decimals) / DECIMAL_PRECISION;
    }

    function normalizeAmount(address token, uint256 amount) internal view returns (uint256 normalizedAmount) {
        require(token != address(0), "Token address cannot be zero"); // Validates token
        uint8 decimals = IERC20(token).decimals();
        return amount * DECIMAL_PRECISION / (10 ** decimals);
    }

    function _transferMarginToListing(address token, uint256 amount, address listingAddress) internal returns (uint256 normalizedAmount) {
        require(token != address(0), "Token address cannot be zero"); // Validates token
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        require(amount > 0, "Margin amount must be greater than zero"); // Validates amount
        normalizedAmount = normalizeAmount(token, amount);
        uint256 balanceBefore = IERC20(token).balanceOf(listingAddress);
        try IERC20(token).transferFrom(address(this), listingAddress, amount) returns (bool success) {
            if (!success) revert("Margin transferFrom failed"); // Checks transfer success
            uint256 balanceAfter = IERC20(token).balanceOf(listingAddress);
            require(balanceAfter - balanceBefore == amount, "Margin balance update failed"); // Verifies balance
        } catch Error(string memory reason) {
            emit ICSStorage.ExternalCallFailed("transferMarginToListing", reason);
            revert(string(abi.encodePacked("Margin transferFrom failed: ", reason)));
        }
    }

    function _updateListingMargin(address listingAddress, uint256 amount) internal {
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](1);
        updates[0] = ISSListing.UpdateType({
            updateType: 0,
            structId: 0,
            index: 0,
            value: amount,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        try ISSListing(listingAddress).update(updates) {} catch Error(string memory reason) {
            emit ICSStorage.ExternalCallFailed("updateListingMargin", reason);
            revert(string(abi.encodePacked("Failed to update listing margin: ", reason)));
        }
    }

    function _updateMakerMargin(address maker, address token, uint256 normalizedAmount) internal {
        require(maker != address(0), "Maker address cannot be zero"); // Validates maker
        require(token != address(0), "Token address cannot be zero"); // Validates token
        uint256 currentMargin = storageContract.makerTokenMargin(maker, token);
        _updateMakerMarginParams(maker, token, currentMargin + normalizedAmount);
    }

    function _reduceMakerMargin(address maker, address token, uint256 normalizedAmount) internal {
        require(maker != address(0), "Maker address cannot be zero"); // Validates maker
        require(token != address(0), "Token address cannot be zero"); // Validates token
        uint256 currentMargin = storageContract.makerTokenMargin(maker, token);
        require(currentMargin >= normalizedAmount, "Insufficient margin to reduce"); // Ensures sufficient margin
        _updateMakerMarginParams(maker, token, currentMargin - normalizedAmount);
    }

    function _updateMakerMarginParams(address maker, address token, uint256 newMargin) internal {
        require(maker != address(0), "Maker address cannot be zero"); // Validates maker
        require(token != address(0), "Token address cannot be zero"); // Validates token
        ICSStorage.MakerMarginParams memory makerParams = ICSStorage.MakerMarginParams({
            token: token,
            maker: maker,
            marginToken: token,
            marginAmount: newMargin
        });
        try storageContract.CSUpdate(
            0,
            ICSStorage.CoreParams(0, address(0), address(0), 0, false, 0),
            ICSStorage.PriceParams(0, 0, 0, 0, 0, 0),
            ICSStorage.MarginParams(0, 0, 0, 0, 0),
            ICSStorage.ExitAndInterestParams(0, 0, 0, 0, 0),
            makerParams,
            ICSStorage.PositionArrayParams(address(0), 0, false, false),
            ICSStorage.HistoricalInterestParams(0, 0, 0)
        ) {} catch Error(string memory reason) {
            emit ICSStorage.ExternalCallFailed("updateMakerMarginParams", reason);
            revert(string(abi.encodePacked("Failed to update maker margin: ", reason)));
        }
    }

    function _executeMarginPayout(address listingAddress, address recipient, uint256 amount) internal {
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        require(recipient != address(0), "Recipient address cannot be zero"); // Validates recipient
        require(amount > 0, "Payout amount must be greater than zero"); // Validates amount
        ISSListing.ListingPayoutUpdate[] memory updates = new ISSListing.ListingPayoutUpdate[](1);
        updates[0] = ISSListing.ListingPayoutUpdate({
            payoutType: 0,
            recipient: recipient,
            required: amount
        });
        try ISSListing(listingAddress).ssUpdate(updates) {} catch Error(string memory reason) {
            emit ICSStorage.ExternalCallFailed("ssUpdate", reason);
            revert(string(abi.encodePacked("Failed to execute margin payout: ", reason)));
        }
    }

    function _updatePositionLiquidationPrices(address maker, address token, address listingAddress) internal {
        require(maker != address(0), "Maker address cannot be zero"); // Validates maker
        require(token != address(0), "Token address cannot be zero"); // Validates token
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        uint256 positionCount = storageContract.positionCount();
        for (uint256 i = 1; i <= positionCount; i++) {
            ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(i);
            ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(i);
            if (
                core1.positionId == i &&
                core2.status2 == 0 &&
                core1.makerAddress == maker &&
                storageContract.positionToken(i) == token &&
                core1.listingAddress == listingAddress
            ) {
                _updateLiquidationPrices(i, maker, core1.positionType, listingAddress);
            }
        }
    }

    function _updateLiquidationPrices(uint256 positionId, address maker, uint8 positionType, address listingAddress) internal {
        require(maker != address(0), "Maker address cannot be zero"); // Validates maker
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        ICSStorage.PriceParams1 memory price1 = storageContract.priceParams1(positionId);
        ICSStorage.MarginParams1 memory margin1 = storageContract.marginParams1(positionId);
        uint256 currentPrice = normalizePrice(positionType == 0 ? ISSListing(listingAddress).tokenB() : ISSListing(listingAddress).tokenA(), ISSListing(listingAddress).prices(0));
        uint256 liquidationPrice = positionType == 0
            ? currentPrice - (margin1.initialMargin * DECIMAL_PRECISION / price1.leverage)
            : currentPrice + (margin1.initialMargin * DECIMAL_PRECISION / price1.leverage);
        ICSStorage.PriceParams memory priceParams = ICSStorage.PriceParams({
            minEntryPrice: price1.minEntryPrice,
            maxEntryPrice: price1.maxEntryPrice,
            minPrice: price1.minPrice,
            priceAtEntry: price1.priceAtEntry,
            leverage: price1.leverage,
            liquidationPrice: liquidationPrice
        });
        try storageContract.CSUpdate(
            positionId,
            ICSStorage.CoreParams(0, address(0), address(0), 0, false, 0),
            priceParams,
            ICSStorage.MarginParams(0, 0, 0, 0, 0),
            ICSStorage.ExitAndInterestParams(0, 0, 0, 0, 0),
            ICSStorage.MakerMarginParams(address(0), address(0), address(0), 0),
            ICSStorage.PositionArrayParams(address(0), 0, false, false),
            ICSStorage.HistoricalInterestParams(0, 0, 0)
        ) {} catch Error(string memory reason) {
            emit ICSStorage.ExternalCallFailed("updateLiquidationPrices", reason);
            revert(string(abi.encodePacked("Failed to update liquidation prices: ", reason)));
        }
    }

    function _updateHistoricalInterest(uint256 amount, uint8 positionType, address listingAddress) internal {
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        uint256 height = block.number;
        uint256 longIO = positionType == 0 ? storageContract.longIOByHeight(height) + amount : storageContract.longIOByHeight(height);
        uint256 shortIO = positionType == 1 ? storageContract.shortIOByHeight(height) + amount : storageContract.shortIOByHeight(height);
        ICSStorage.HistoricalInterestParams memory interestParams = ICSStorage.HistoricalInterestParams({
            longIO: longIO,
            shortIO: shortIO,
            timestamp: block.timestamp
        });
        try storageContract.CSUpdate(
            0,
            ICSStorage.CoreParams(0, address(0), address(0), 0, false, 0),
            ICSStorage.PriceParams(0, 0, 0, 0, 0, 0),
            ICSStorage.MarginParams(0, 0, 0, 0, 0),
            ICSStorage.ExitAndInterestParams(0, 0, 0, 0, 0),
            ICSStorage.MakerMarginParams(address(0), address(0), address(0), 0),
            ICSStorage.PositionArrayParams(address(0), 0, false, false),
            interestParams
        ) {} catch Error(string memory reason) {
            emit ICSStorage.ExternalCallFailed("updateHistoricalInterest", reason);
            revert(string(abi.encodePacked("Failed to update historical interest: ", reason)));
        }
    }

    function _validateAndNormalizePullMargin(address listingAddress, bool tokenA, uint256 amount) internal view returns (address token, uint256 normalizedAmount) {
        require(amount > 0, "Margin amount must be greater than zero"); // Validates amount
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        (bool isValid, ICCAgent.ListingDetails memory details) = ICCAgent(agentAddress).isValidListing(listingAddress);
        require(isValid, "Listing is not valid"); // Ensures valid listing
        token = tokenA ? details.tokenA : details.tokenB;
        require(token != address(0), "Selected token address cannot be zero"); // Validates token
        normalizedAmount = normalizeAmount(token, amount);
    }

    function _computeLoanAndLiquidationLong(
        uint256 leverageAmount,
        uint256 minPrice,
        address maker,
        address tokenA,
        ICSStorage storageContractInstance
    ) internal view returns (uint256 initialLoan, uint256 liquidationPrice) {
        require(minPrice > 0, "Minimum price must be greater than zero"); // Validates price
        initialLoan = leverageAmount / minPrice;
        uint256 marginRatio = storageContractInstance.makerTokenMargin(maker, tokenA) / leverageAmount;
        liquidationPrice = marginRatio < minPrice ? minPrice - marginRatio : 0;
    }

    function _computeLoanAndLiquidationShort(
        uint256 leverageAmount,
        uint256 minPrice,
        address maker,
        address tokenB,
        ICSStorage storageContractInstance
    ) internal view returns (uint256 initialLoan, uint256 liquidationPrice) {
        require(minPrice > 0, "Minimum price must be greater than zero"); // Validates price
        initialLoan = leverageAmount * minPrice;
        uint256 marginRatio = storageContractInstance.makerTokenMargin(maker, tokenB) / leverageAmount;
        liquidationPrice = minPrice + marginRatio;
    }

    function _checkPositionConditions(
        uint256 positionId,
        uint8 positionType,
        uint256 currentPrice
    ) internal returns (bool continueLoop, PositionCheck memory check) {
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
        if (core1.positionId != positionId || core2.status2 != 0 || !core2.status1) {
            return (true, check);
        }
        ICSStorage.PriceParams2 memory price2 = storageContract.priceParams2(positionId);
        ICSStorage.ExitParams memory exit = storageContract.exitParams(positionId);
        check.shouldLiquidate = positionType == 0 ? currentPrice <= price2.liquidationPrice : currentPrice >= price2.liquidationPrice;
        check.shouldStopLoss = exit.stopLossPrice != 0 && (positionType == 0 ? currentPrice <= exit.stopLossPrice : currentPrice >= exit.stopLossPrice);
        check.shouldTakeProfit = exit.takeProfitPrice != 0 && (positionType == 0 ? currentPrice >= exit.takeProfitPrice : currentPrice <= exit.takeProfitPrice);
        _tempPositionData[positionId] = check;
        return (false, check);
    }

    function _executeExitsInternal(address listingAddress, uint256 maxIterations) internal {
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        (bool isValid, ICCAgent.ListingDetails memory details) = ICCAgent(agentAddress).isValidListing(listingAddress);
        require(isValid, "Listing is not valid"); // Ensures valid listing
        for (uint8 positionType = 0; positionType <= 1; positionType++) {
            uint256[] memory activePositions = storageContract.positionsByType(positionType);
            uint256 processed = 0;
            for (uint256 i = 0; i < activePositions.length && processed < maxIterations && gasleft() >= 50000; i++) {
                uint256 positionId = activePositions[i];
                ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
                if (core1.listingAddress != listingAddress) continue;
                address token = positionType == 0 ? details.tokenB : details.tokenA;
                require(token != address(0), "Token address cannot be zero"); // Validates token
                uint256 currentPrice = normalizePrice(token, ISSListing(listingAddress).prices(0));
                (bool continueLoop, ) = _checkPositionConditions(positionId, positionType, currentPrice);
                if (!continueLoop) {
                    i--;
                }
                processed++;
            }
        }
    }
}