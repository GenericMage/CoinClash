/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-08-06: Restored _updateLiquidationPrices, _updateMakerMarginParams, _computeLoanAndLiquidationLong, _computeLoanAndLiquidationShort from CCSExtraPartial.sol to fix DeclarationError in _prepCloseLong, _prepCloseShort, and _processPendingPosition. Incremented version to 0.0.19.
 - 2025-08-06: Removed _transferMarginToListing, _updateListingMargin, _updateMakerMargin, _updatePositionLiquidationPrices, _updateHistoricalInterest, _validateAndNormalizePullMargin, _reduceMakerMargin, _executeMarginPayout, _updateMakerMarginParams, _updateLiquidationPrices, _computeLoanAndLiquidationLong, _computeLoanAndLiquidationShort, extracted to CCSExtraPartial.sol. Incremented version to 0.0.18.
 - 2025-08-06: Renamed executeEntries to _executeEntriesInternal to avoid conflicts with external function, kept internal visibility to comply with style guide prohibiting virtuals/overrides. Incremented version to 0.0.17.
 - 2025-08-06: Removed virtual from executeEntries and changed visibility to external to comply with style guide prohibiting virtuals/overrides. Incremented version to 0.0.16.
 - 2025-08-06: Added virtual to executeEntries to allow override in CCSExecutionDriver, removed marginParams2 usage to align with ICSStorage interface, updated _prepCloseLong and _prepCloseShort accordingly. Incremented version to 0.0.15.
 - 2025-08-06: Updated _updateExcessTokens to handle token balances with normalization, adapted to newer ISSListing.update signature, added try-catch for external call. Incremented version to 0.0.14.
 - 2025-08-06: Added _prepCloseLong, _prepCloseShort, and helper functions (_updateCoreParams, _updatePriceParams, _updateMarginParams, _updateExitParams, _updateOpenInterest) extracted and adapted from older CCSExecutionPartial.txt to fix DeclarationError. Aligned with updated ICSStorage and ISSListing interfaces. Incremented version to 0.0.13.
 - 2025-08-06: Created CCSExecutionPartial, extracted executeEntries, TP/SL, and margin adjustment logic from CCSExecutionPartial.sol. Aligned with updated ICSStorage and ISSListing interfaces, used isValidListing for validation. Version set to 0.0.12.
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
    function liquidityAddressView() external view returns (address);
    function prices(uint256) external view returns (uint256);
    function update(UpdateType[] calldata updates) external;
    function ssUpdate(ListingPayoutUpdate[] calldata updates) external;
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
    struct ExitParams {
        uint256 stopLossPrice;
        uint256 takeProfitPrice;
        uint256 exitPrice;
    }
    struct OpenInterest {
        uint256 leverageAmount;
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
    struct HistoricalInterestParams {
        uint256 longIO;
        uint256 shortIO;
        uint256 timestamp;
    }
    function makerTokenMargin(address maker, address token) external view returns (uint256 margin);
    function positionCore1(uint256 positionId) external view returns (PositionCore1 memory core);
    function positionCore2(uint256 positionId) external view returns (PositionCore2 memory status);
    function priceParams1(uint256 positionId) external view returns (PriceParams1 memory params);
    function priceParams2(uint256 positionId) external view returns (PriceParams2 memory params);
    function marginParams1(uint256 positionId) external view returns (MarginParams1 memory params);
    function positionToken(uint256 positionId) external view returns (address token);
    function longIOByHeight(uint256 height) external view returns (uint256 longIO);
    function shortIOByHeight(uint256 height) external view returns (uint256 shortIO);
    function pendingPositions(address listingAddress, uint8 positionType) external view returns (uint256[] memory positionIds);
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

contract CCSExecutionPartial is ReentrancyGuard {
    uint256 public constant DECIMAL_PRECISION = 1e18;
    address public agentAddress;
    ICSStorage public storageContract;
    ICCOrderRouter public orderRouter;

    constructor(address _storageContract) {
        require(_storageContract != address(0), "Storage contract address cannot be zero"); // Validates storage contract
        storageContract = ICSStorage(_storageContract);
    }

    function setOrderRouter(address newOrderRouter) external onlyOwner {
        require(newOrderRouter != address(0), "Order router address cannot be zero"); // Validates order router
        orderRouter = ICCOrderRouter(newOrderRouter);
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

    function computeFee(uint256 initialMargin, uint8 leverage) internal pure returns (uint256 fee) {
        uint256 feePercent = uint256(leverage) - 1;
        return (initialMargin * feePercent * DECIMAL_PRECISION) / 100 / DECIMAL_PRECISION;
    }

    function _parseEntryPriceInternal(
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        address listingAddress
    ) internal view returns (uint256 currentPrice, uint256 minPrice, uint256 maxPrice, uint256 priceAtEntry) {
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        currentPrice = ISSListing(listingAddress).prices(0);
        minPrice = minEntryPrice;
        maxPrice = maxEntryPrice;
        priceAtEntry = (minPrice == 0 && maxPrice == 0) ? currentPrice : (currentPrice >= minPrice && currentPrice <= maxPrice ? currentPrice : 0);
        return (currentPrice, minPrice, maxPrice, priceAtEntry);
    }

    function _transferLiquidityFee(
        address listingAddress,
        address token,
        uint256 fee,
        uint8 positionType
    ) internal {
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        require(token != address(0), "Token address cannot be zero"); // Validates token
        address liquidityAddr = ISSListing(listingAddress).liquidityAddressView();
        require(liquidityAddr != address(0), "Liquidity address cannot be zero"); // Validates liquidity address
        if (fee > 0) {
            uint256 denormalizedFee = denormalizeAmount(token, fee);
            uint256 balanceBefore = IERC20(token).balanceOf(liquidityAddr);
            try IERC20(token).transfer(liquidityAddr, denormalizedFee) returns (bool success) {
                if (!success) revert("Liquidity fee transfer failed"); // Checks transfer success
                uint256 balanceAfter = IERC20(token).balanceOf(liquidityAddr);
                require(balanceAfter - balanceBefore == denormalizedFee, "Liquidity fee balance update failed"); // Verifies balance
                try ISSLiquidityTemplate(liquidityAddr).addFees(address(this), positionType == 0, denormalizedFee) {} catch Error(string memory reason) {
                    emit ICSStorage.ExternalCallFailed("addFees", reason);
                    revert(string(abi.encodePacked("Failed to add fees to liquidity: ", reason)));
                }
            } catch Error(string memory reason) {
                emit ICSStorage.ExternalCallFailed("transferLiquidityFee", reason);
                revert(string(abi.encodePacked("Liquidity fee transfer failed: ", reason)));
            }
        }
    }

    function _updateCoreParams(
        uint256 positionId,
        ICSStorage.PositionCore1 memory core1,
        ICSStorage.PositionCore2 memory core2
    ) internal {
        require(positionId > 0, "Position ID must be greater than zero"); // Validates position
        try storageContract.CSUpdate(
            positionId,
            ICSStorage.CoreParams(
                core1.positionId,
                core1.listingAddress,
                core1.makerAddress,
                core1.positionType,
                core2.status1,
                core2.status2
            ),
            ICSStorage.PriceParams(0, 0, 0, 0, 0, 0),
            ICSStorage.MarginParams(0, 0, 0, 0, 0),
            ICSStorage.ExitAndInterestParams(0, 0, 0, 0, 0),
            ICSStorage.MakerMarginParams(address(0), address(0), address(0), 0),
            ICSStorage.PositionArrayParams(address(0), 0, false, false),
            ICSStorage.HistoricalInterestParams(0, 0, 0)
        ) {} catch Error(string memory reason) {
            emit ICSStorage.ExternalCallFailed("updateCoreParams", reason);
            revert(string(abi.encodePacked("Failed to update core params: ", reason)));
        }
    }

    function _updatePriceParams(
        uint256 positionId,
        ICSStorage.PriceParams1 memory price1,
        ICSStorage.PriceParams2 memory price2
    ) internal {
        require(positionId > 0, "Position ID must be greater than zero"); // Validates position
        try storageContract.CSUpdate(
            positionId,
            ICSStorage.CoreParams(0, address(0), address(0), 0, false, 0),
            ICSStorage.PriceParams(
                price1.minEntryPrice,
                price1.maxEntryPrice,
                price1.minPrice,
                price1.priceAtEntry,
                price1.leverage,
                price2.liquidationPrice
            ),
            ICSStorage.MarginParams(0, 0, 0, 0, 0),
            ICSStorage.ExitAndInterestParams(0, 0, 0, 0, 0),
            ICSStorage.MakerMarginParams(address(0), address(0), address(0), 0),
            ICSStorage.PositionArrayParams(address(0), 0, false, false),
            ICSStorage.HistoricalInterestParams(0, 0, 0)
        ) {} catch Error(string memory reason) {
            emit ICSStorage.ExternalCallFailed("updatePriceParams", reason);
            revert(string(abi.encodePacked("Failed to update price params: ", reason)));
        }
    }

    function _updateMarginParams(
        uint256 positionId,
        ICSStorage.MarginParams1 memory margin1
    ) internal {
        require(positionId > 0, "Position ID must be greater than zero"); // Validates position
        try storageContract.CSUpdate(
            positionId,
            ICSStorage.CoreParams(0, address(0), address(0), 0, false, 0),
            ICSStorage.PriceParams(0, 0, 0, 0, 0, 0),
            ICSStorage.MarginParams(
                margin1.initialMargin,
                margin1.taxedMargin,
                margin1.excessMargin,
                margin1.fee,
                0
            ),
            ICSStorage.ExitAndInterestParams(0, 0, 0, 0, 0),
            ICSStorage.MakerMarginParams(address(0), address(0), address(0), 0),
            ICSStorage.PositionArrayParams(address(0), 0, false, false),
            ICSStorage.HistoricalInterestParams(0, 0, 0)
        ) {} catch Error(string memory reason) {
            emit ICSStorage.ExternalCallFailed("updateMarginParams", reason);
            revert(string(abi.encodePacked("Failed to update margin params: ", reason)));
        }
    }

    function _updateExitParams(uint256 positionId, ICSStorage.ExitParams memory exit) internal {
        require(positionId > 0, "Position ID must be greater than zero"); // Validates position
        try storageContract.CSUpdate(
            positionId,
            ICSStorage.CoreParams(0, address(0), address(0), 0, false, 0),
            ICSStorage.PriceParams(0, 0, 0, 0, 0, 0),
            ICSStorage.MarginParams(0, 0, 0, 0, 0),
            ICSStorage.ExitAndInterestParams(
                exit.stopLossPrice,
                exit.takeProfitPrice,
                exit.exitPrice,
                0,
                0
            ),
            ICSStorage.MakerMarginParams(address(0), address(0), address(0), 0),
            ICSStorage.PositionArrayParams(address(0), 0, false, false),
            ICSStorage.HistoricalInterestParams(0, 0, 0)
        ) {} catch Error(string memory reason) {
            emit ICSStorage.ExternalCallFailed("updateExitParams", reason);
            revert(string(abi.encodePacked("Failed to update exit params: ", reason)));
        }
    }

    function _updateOpenInterest(uint256 positionId, ICSStorage.OpenInterest memory interest) internal {
        require(positionId > 0, "Position ID must be greater than zero"); // Validates position
        try storageContract.CSUpdate(
            positionId,
            ICSStorage.CoreParams(0, address(0), address(0), 0, false, 0),
            ICSStorage.PriceParams(0, 0, 0, 0, 0, 0),
            ICSStorage.MarginParams(0, 0, 0, 0, 0),
            ICSStorage.ExitAndInterestParams(0, 0, 0, interest.leverageAmount, interest.timestamp),
            ICSStorage.MakerMarginParams(address(0), address(0), address(0), 0),
            ICSStorage.PositionArrayParams(address(0), 0, false, false),
            ICSStorage.HistoricalInterestParams(0, 0, 0)
        ) {} catch Error(string memory reason) {
            emit ICSStorage.ExternalCallFailed("updateOpenInterest", reason);
            revert(string(abi.encodePacked("Failed to update open interest: ", reason)));
        }
    }

    function _updateMakerMarginParams(address maker, address token, uint256 marginAmount) internal {
        require(maker != address(0), "Maker address cannot be zero"); // Validates maker
        require(token != address(0), "Token address cannot be zero"); // Validates token
        try storageContract.CSUpdate(
            0,
            ICSStorage.CoreParams(0, address(0), address(0), 0, false, 0),
            ICSStorage.PriceParams(0, 0, 0, 0, 0, 0),
            ICSStorage.MarginParams(0, 0, 0, 0, 0),
            ICSStorage.ExitAndInterestParams(0, 0, 0, 0, 0),
            ICSStorage.MakerMarginParams(token, maker, token, marginAmount),
            ICSStorage.PositionArrayParams(address(0), 0, false, false),
            ICSStorage.HistoricalInterestParams(0, 0, 0)
        ) {} catch Error(string memory reason) {
            emit ICSStorage.ExternalCallFailed("updateMakerMarginParams", reason);
            revert(string(abi.encodePacked("Failed to update maker margin: ", reason)));
        }
    }

    function _updateLiquidationPrices(
        uint256 positionId,
        address maker,
        uint8 positionType,
        address listingAddress
    ) internal {
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
        if (core1.positionId != positionId || core2.status2 != 0) {
            return;
        }
        ICSStorage.PriceParams1 memory price1 = storageContract.priceParams1(positionId);
        ICSStorage.MarginParams1 memory margin1 = storageContract.marginParams1(positionId);
        uint256 newLiquidationPrice;
        if (positionType == 0) {
            address tokenA = ISSListing(listingAddress).tokenA();
            (, newLiquidationPrice) = _computeLoanAndLiquidationLong(
                uint256(price1.leverage) * margin1.initialMargin,
                price1.minEntryPrice,
                maker,
                tokenA,
                storageContract
            );
        } else {
            address tokenB = ISSListing(listingAddress).tokenB();
            (, newLiquidationPrice) = _computeLoanAndLiquidationShort(
                uint256(price1.leverage) * margin1.initialMargin,
                price1.minEntryPrice,
                maker,
                tokenB,
                storageContract
            );
        }
        try storageContract.CSUpdate(
            positionId,
            ICSStorage.CoreParams(0, address(0), address(0), 0, false, 0),
            ICSStorage.PriceParams(0, 0, 0, 0, 0, newLiquidationPrice),
            ICSStorage.MarginParams(0, 0, 0, 0, 0),
            ICSStorage.ExitAndInterestParams(0, 0, 0, 0, 0),
            ICSStorage.MakerMarginParams(address(0), address(0), address(0), 0),
            ICSStorage.PositionArrayParams(address(0), 0, false, false),
            ICSStorage.HistoricalInterestParams(0, 0, 0)
        ) {} catch Error(string memory reason) {
            emit ICSStorage.ExternalCallFailed("updatePriceParams", reason);
            revert(string(abi.encodePacked("Failed to update price params: ", reason)));
        }
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

    function _computePayoutLong(
        uint256 positionId,
        address listingAddress,
        address tokenB,
        ICSStorage storageContractInstance
    ) internal view returns (uint256 payout) {
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        require(tokenB != address(0), "Token B address cannot be zero"); // Validates token
        ICSStorage.MarginParams1 memory margin1 = storageContractInstance.marginParams1(positionId);
        ICSStorage.PriceParams1 memory price1 = storageContractInstance.priceParams1(positionId);
        uint256 currentPrice = normalizePrice(tokenB, ISSListing(listingAddress).prices(0));
        require(currentPrice > 0, "Current price must be greater than zero"); // Ensures valid price
        uint256 totalMargin = storageContractInstance.makerTokenMargin(storageContractInstance.positionCore1(positionId).makerAddress, ISSListing(listingAddress).tokenA());
        uint256 leverageAmount = uint256(price1.leverage) * margin1.initialMargin;
        uint256 baseValue = (margin1.taxedMargin + totalMargin + leverageAmount) / currentPrice;
        return baseValue > 0 ? baseValue : 0;
    }

    function _computePayoutShort(
        uint256 positionId,
        address listingAddress,
        address tokenA,
        ICSStorage storageContractInstance
    ) internal view returns (uint256 payout) {
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        require(tokenA != address(0), "Token A address cannot be zero"); // Validates token
        ICSStorage.MarginParams1 memory margin1 = storageContractInstance.marginParams1(positionId);
        ICSStorage.PriceParams1 memory price1 = storageContractInstance.priceParams1(positionId);
        uint256 currentPrice = normalizePrice(tokenA, ISSListing(listingAddress).prices(0));
        require(currentPrice > 0, "Current price must be greater than zero"); // Ensures valid price
        uint256 totalMargin = storageContractInstance.makerTokenMargin(storageContractInstance.positionCore1(positionId).makerAddress, ISSListing(listingAddress).tokenB());
        uint256 priceDiff = price1.priceAtEntry > currentPrice ? price1.priceAtEntry - currentPrice : 0;
        uint256 profit = priceDiff * margin1.initialMargin * uint256(price1.leverage);
        return profit + (margin1.taxedMargin + totalMargin) * currentPrice / DECIMAL_PRECISION;
    }

    function _prepCloseLong(
        uint256 positionId,
        address listingAddress
    ) internal returns (uint256 payout) {
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.MarginParams1 memory margin1 = storageContract.marginParams1(positionId);
        address tokenB = ISSListing(listingAddress).tokenB();
        require(tokenB != address(0), "Token B address cannot be zero"); // Validates token
        payout = _computePayoutLong(positionId, listingAddress, tokenB, storageContract);
        address tokenA = ISSListing(listingAddress).tokenA();
        require(tokenA != address(0), "Token A address cannot be zero"); // Validates token
        uint256 marginAmount = margin1.taxedMargin + margin1.excessMargin;
        _updateCoreParams(positionId, ICSStorage.PositionCore1(0, address(0), address(0), 0), ICSStorage.PositionCore2(false, 1));
        _updatePriceParams(positionId, ICSStorage.PriceParams1(0, 0, 0, 0, 0), ICSStorage.PriceParams2(0));
        _updateMarginParams(positionId, ICSStorage.MarginParams1(0, 0, 0, 0));
        _updateExitParams(positionId, ICSStorage.ExitParams(0, 0, normalizePrice(tokenB, ISSListing(listingAddress).prices(0))));
        _updateOpenInterest(positionId, ICSStorage.OpenInterest(0, 0));
        _updateMakerMarginParams(core1.makerAddress, tokenA, storageContract.makerTokenMargin(core1.makerAddress, tokenA) - marginAmount);
        return payout; // Returns calculated payout
    }

    function _prepCloseShort(
        uint256 positionId,
        address listingAddress
    ) internal returns (uint256 payout) {
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.MarginParams1 memory margin1 = storageContract.marginParams1(positionId);
        address tokenA = ISSListing(listingAddress).tokenA();
        require(tokenA != address(0), "Token A address cannot be zero"); // Validates token
        payout = _computePayoutShort(positionId, listingAddress, tokenA, storageContract);
        address tokenB = ISSListing(listingAddress).tokenB();
        require(tokenB != address(0), "Token B address cannot be zero"); // Validates token
        uint256 marginAmount = margin1.taxedMargin + margin1.excessMargin;
        _updateCoreParams(positionId, ICSStorage.PositionCore1(0, address(0), address(0), 0), ICSStorage.PositionCore2(false, 1));
        _updatePriceParams(positionId, ICSStorage.PriceParams1(0, 0, 0, 0, 0), ICSStorage.PriceParams2(0));
        _updateMarginParams(positionId, ICSStorage.MarginParams1(0, 0, 0, 0));
        _updateExitParams(positionId, ICSStorage.ExitParams(0, 0, normalizePrice(tokenA, ISSListing(listingAddress).prices(0))));
        _updateOpenInterest(positionId, ICSStorage.OpenInterest(0, 0));
        _updateMakerMarginParams(core1.makerAddress, tokenB, storageContract.makerTokenMargin(core1.makerAddress, tokenB) - marginAmount);
        return payout; // Returns calculated payout
    }

    function _updateExcessTokens(address listingAddress, address tokenA, address tokenB) internal {
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        require(tokenA != address(0) && tokenB != address(0), "Token addresses cannot be zero"); // Validates tokens
        uint256 balanceA = normalizeAmount(tokenA, IERC20(tokenA).balanceOf(listingAddress));
        uint256 balanceB = normalizeAmount(tokenB, IERC20(tokenB).balanceOf(listingAddress));
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](2);
        updates[0] = ISSListing.UpdateType({
            updateType: 0,
            structId: 0,
            index: 0,
            value: balanceA,
            addr: tokenA,
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        updates[1] = ISSListing.UpdateType({
            updateType: 0,
            structId: 0,
            index: 1,
            value: balanceB,
            addr: tokenB,
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        try ISSListing(listingAddress).update(updates) {} catch Error(string memory reason) {
            emit ICSStorage.ExternalCallFailed("updateExcessTokens", reason);
            revert(string(abi.encodePacked("Failed to update excess tokens: ", reason)));
        }
    }

    function _createOrderForPosition(
        uint256 positionId,
        uint8 positionType,
        address listingAddress,
        uint256 marginAmount
    ) internal {
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        address token = positionType == 0 ? ISSListing(listingAddress).tokenA() : ISSListing(listingAddress).tokenB();
        require(token != address(0), "Token address cannot be zero"); // Validates token
        require(address(orderRouter) != address(0), "Order router not set"); // Validates order router
        uint256 denormalizedMargin = denormalizeAmount(token, marginAmount);
        try IERC20(token).approve(address(orderRouter), denormalizedMargin) returns (bool success) {
            if (!success) revert("Token approval for order router failed"); // Checks approval
            if (positionType == 0) {
                try orderRouter.createSellOrder(listingAddress, listingAddress, denormalizedMargin, 0, 0) {} catch Error(string memory reason) {
                    emit ICSStorage.ExternalCallFailed("createSellOrder", reason);
                    revert(string(abi.encodePacked("Failed to create sell order: ", reason)));
                }
            } else {
                try orderRouter.createBuyOrder(listingAddress, listingAddress, denormalizedMargin, 0, 0) {} catch Error(string memory reason) {
                    emit ICSStorage.ExternalCallFailed("createBuyOrder", reason);
                    revert(string(abi.encodePacked("Failed to create buy order: ", reason)));
                }
            }
        } catch Error(string memory reason) {
            emit ICSStorage.ExternalCallFailed("approveToken", reason);
            revert(string(abi.encodePacked("Token approval failed: ", reason)));
        }
    }

    function _updateSL(
        uint256 positionId,
        uint256 newStopLossPrice,
        address listingAddress,
        uint8 positionType,
        uint256 minPrice,
        uint256 maxEntryPrice,
        uint256 currentPrice
    ) internal {
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        _updateExitParams(positionId, ICSStorage.ExitParams(newStopLossPrice, 0, 0));
    }

    function _updateTP(
        uint256 positionId,
        uint256 newTakeProfitPrice,
        address listingAddress,
        uint8 positionType,
        uint256 priceAtEntry,
        uint256 maxEntryPrice,
        uint256 currentPrice
    ) internal {
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        if (positionType == 0) {
            require(newTakeProfitPrice == 0 || newTakeProfitPrice > priceAtEntry, "Take-profit price must be greater than entry for long position"); // Validates TP for long
        } else {
            require(newTakeProfitPrice == 0 || newTakeProfitPrice < priceAtEntry, "Take-profit price must be less than entry for short position"); // Validates TP for short
        }
        _updateExitParams(positionId, ICSStorage.ExitParams(0, newTakeProfitPrice, 0));
    }

    function _updatePositionStatus(uint256 positionId, ICSStorage.PositionCore2 memory core2) internal {
        require(positionId > 0, "Position ID must be greater than zero"); // Validates position
        try storageContract.CSUpdate(
            positionId,
            ICSStorage.CoreParams(0, address(0), address(0), 0, core2.status1, core2.status2),
            ICSStorage.PriceParams(0, 0, 0, 0, 0, 0),
            ICSStorage.MarginParams(0, 0, 0, 0, 0),
            ICSStorage.ExitAndInterestParams(0, 0, 0, 0, 0),
            ICSStorage.MakerMarginParams(address(0), address(0), address(0), 0),
            ICSStorage.PositionArrayParams(address(0), 0, false, false),
            ICSStorage.HistoricalInterestParams(0, 0, 0)
        ) {} catch Error(string memory reason) {
            emit ICSStorage.ExternalCallFailed("updatePositionStatus", reason);
            revert(string(abi.encodePacked("Failed to update position status: ", reason)));
        }
    }

    function _processPendingPosition(
        uint256 positionId,
        uint8 positionType,
        address listingAddress,
        uint256[] memory pending,
        uint256 i,
        uint256 currentPrice
    ) internal returns (bool continueLoop) {
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
        ICSStorage.PriceParams1 memory price1 = storageContract.priceParams1(positionId);
        ICSStorage.PriceParams2 memory price2 = storageContract.priceParams2(positionId);
        _updateLiquidationPrices(positionId, core1.makerAddress, positionType, listingAddress);
        price2 = storageContract.priceParams2(positionId);
        bool shouldLiquidate = positionType == 0 ? currentPrice <= price2.liquidationPrice : currentPrice >= price2.liquidationPrice;
        if (shouldLiquidate) {
            uint256 payout = positionType == 0 ? _prepCloseLong(positionId, listingAddress) : _prepCloseShort(positionId, listingAddress);
            try storageContract.removePositionIndex(positionId, positionType, listingAddress) {} catch Error(string memory reason) {
                emit ICSStorage.ExternalCallFailed("removePositionIndex", reason);
                revert(string(abi.encodePacked("Failed to remove position index: ", reason)));
            }
            emit ICSStorage.PositionClosed(positionId, core1.makerAddress, payout);
            return true;
        } else if (price1.minEntryPrice == 0 && price1.maxEntryPrice == 0 || (currentPrice >= price1.minEntryPrice && currentPrice <= price1.maxEntryPrice)) {
            uint256 marginAmount = storageContract.marginParams1(positionId).taxedMargin + storageContract.marginParams1(positionId).excessMargin;
            _createOrderForPosition(positionId, positionType, listingAddress, marginAmount);
            _updateExcessTokens(listingAddress, ISSListing(listingAddress).tokenA(), ISSListing(listingAddress).tokenB());
            _updatePositionStatus(positionId, ICSStorage.PositionCore2(true, 0));
            if (price1.minEntryPrice == 0 && price1.maxEntryPrice == 0) {
                _updatePriceParams(positionId, ICSStorage.PriceParams1(0, 0, 0, currentPrice, price1.leverage), ICSStorage.PriceParams2(price2.liquidationPrice));
            }
            return true;
        }
        return false;
    }

    function _executeEntriesInternal(address listingAddress, uint256 maxIterations) internal {
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        (bool isValid, ICCAgent.ListingDetails memory details) = ICCAgent(agentAddress).isValidListing(listingAddress);
        require(isValid, "Listing is not valid"); // Ensures valid listing
        for (uint8 positionType = 0; positionType <= 1; positionType++) {
            uint256[] memory pending = storageContract.pendingPositions(listingAddress, positionType);
            uint256 processed = 0;
            for (uint256 i = 0; i < pending.length && processed < maxIterations && gasleft() >= 50000; i++) {
                uint256 positionId = pending[i];
                ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
                address token = positionType == 0 ? details.tokenB : details.tokenA;
                require(token != address(0), "Token address cannot be zero"); // Validates token
                (uint256 currentPrice,,,) = _parseEntryPriceInternal(
                    storageContract.priceParams1(positionId).minEntryPrice,
                    storageContract.priceParams1(positionId).maxEntryPrice,
                    listingAddress
                );
                currentPrice = normalizePrice(token, currentPrice);
                if (_processPendingPosition(positionId, positionType, listingAddress, pending, i, currentPrice)) {
                    i--;
                }
                processed++;
            }
        }
    }
}