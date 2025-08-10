/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-08-07: Ensured _prepDriftPayout and _prepDriftMargin are used by CCSExitDriver.sol; version set to 0.0.21.
 - 2025-08-07: No changes; version incremented to 0.0.20 for consistency with CCSExitDriver.sol.
 - 2025-08-07: Added _prepareCancelPosition, _updatePositionParams, _updateMarginAndIndex from CCSExtraPartial.sol for cancellation support; updated ICSStorage interface with positionToken; version set to 0.0.19.
 - 2025-08-05: Created CCSExitPartial by extracting payout and margin deduction functions from CCSPositionPartial.sol; defined ISSListing, ISSLiquidityTemplate, ISSAgent, and ICSStorage interfaces; added try-catch for external calls; version set to 0.0.17.
*/

pragma solidity ^0.8.2;

import "../imports/IERC20.sol";
import "../imports/ReentrancyGuard.sol";

interface ISSListing {
    struct ListingPayoutUpdate {
        uint8 payoutType; // 0: Long, 1: Short
        address recipient; // Address to receive payout
        uint256 required; // Normalized amount required (tokenB for long, tokenA for short)
    }
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function prices(uint256) external view returns (uint256);
    function liquidityAddressView() external view returns (address);
    function ssUpdate(ListingPayoutUpdate[] calldata updates) external;
}

interface ISSLiquidityTemplate {
    function liquidityDetailsView(address caller) external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees);
}

interface ISSAgent {
    struct ListingDetails {
        address listingAddress; // Listing contract address
        address liquidityAddress; // Associated liquidity contract address
        address tokenA; // First token in pair
        address tokenB; // Second token in pair
        uint256 listingId; // Listing ID
    }
    function isValidListing(address listingAddress) external view returns (bool isValid, ListingDetails memory details);
}

interface ICSStorage {
    struct PositionCore1 {
        uint256 positionId; // Unique position identifier
        address listingAddress; // Listing contract address
        address makerAddress; // Position owner
        uint8 positionType; // 0 for long, 1 for short
    }
    struct PositionCore2 {
        bool status1; // Active flag
        uint8 status2; // 0 for open, 1 for closed
    }
    struct PriceParams1 {
        uint256 minEntryPrice; // Minimum entry price, normalized
        uint256 maxEntryPrice; // Maximum entry price, normalized
        uint256 minPrice; // Minimum price, normalized
        uint256 priceAtEntry; // Entry price, normalized
        uint8 leverage; // Leverage multiplier
    }
    struct PriceParams2 {
        uint256 liquidationPrice; // Liquidation price, normalized
    }
    struct MarginParams1 {
        uint256 initialMargin; // Initial margin, normalized
        uint256 taxedMargin; // Taxed margin, normalized
        uint256 excessMargin; // Excess margin, normalized
        uint256 fee; // Fee amount, normalized
    }
    struct MarginParams2 {
        uint256 initialLoan; // Initial loan amount, normalized
    }
    struct ExitParams {
        uint256 stopLossPrice; // Stop loss price, normalized
        uint256 takeProfitPrice; // Take profit price, normalized
        uint256 exitPrice; // Exit price, normalized
    }
    struct OpenInterest {
        uint256 leverageAmount; // Leveraged amount, normalized
        uint256 timestamp; // Timestamp of update
    }
    struct CoreParams {
        uint256 positionId; // Position ID
        address listingAddress; // Listing contract address
        address makerAddress; // Position owner
        uint8 positionType; // 0 for long, 1 for short
        bool status1; // Active flag
        uint8 status2; // 0 for open, 1 for closed
    }
    struct PriceParams {
        uint256 minEntryPrice; // Minimum entry price
        uint256 maxEntryPrice; // Maximum entry price
        uint256 minPrice; // Minimum price
        uint256 priceAtEntry; // Entry price
        uint8 leverage; // Leverage multiplier
        uint256 liquidationPrice; // Liquidation price
    }
    struct MarginParams {
        uint256 initialMargin; // Initial margin
        uint256 taxedMargin; // Taxed margin
        uint256 excessMargin; // Excess margin
        uint256 fee; // Fee amount
        uint256 initialLoan; // Initial loan amount
    }
    struct ExitAndInterestParams {
        uint256 stopLossPrice; // Stop loss price
        uint256 takeProfitPrice; // Take profit price
        uint256 exitPrice; // Exit price
        uint256 leverageAmount; // Leveraged amount
        uint256 timestamp; // Update timestamp
    }
    struct MakerMarginParams {
        address token; // Position token
        address maker; // Position owner
        address marginToken; // Margin token
        uint256 marginAmount; // Margin amount, normalized
    }
    struct PositionArrayParams {
        address listingAddress; // Listing contract address
        uint8 positionType; // 0 for long, 1 for short
        bool addToPending; // Add to pending positions
        bool addToActive; // Add to active positions
    }
    struct HistoricalInterestParams {
        uint256 longIO; // Long open interest
        uint256 shortIO; // Short open interest
        uint256 timestamp; // Timestamp of interest update
    }
    function positionCount() external view returns (uint256 count);
    function makerTokenMargin(address maker, address token) external view returns (uint256 amount);
    function positionCore1(uint256 positionId) external view returns (PositionCore1 memory core1);
    function positionCore2(uint256 positionId) external view returns (PositionCore2 memory core2);
    function priceParams1(uint256 positionId) external view returns (PriceParams1 memory priceParams);
    function priceParams2(uint256 positionId) external view returns (PriceParams2 memory priceParams);
    function marginParams1(uint256 positionId) external view returns (MarginParams1 memory marginParams);
    function marginParams2(uint256 positionId) external view returns (MarginParams2 memory marginParams);
    function exitParams(uint256 positionId) external view returns (ExitParams memory exitParams);
    function openInterest(uint256 positionId) external view returns (OpenInterest memory openInterest);
    function positionToken(uint256 positionId) external view returns (address token);
    function removePositionIndex(uint256 positionId, uint8 positionType, address listingAddress) external;
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
    function PositionsByAddressView(
        address maker,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (uint256[] memory positionIds);
}

contract CCSExitPartial is ReentrancyGuard {
    uint256 public constant DECIMAL_PRECISION = 1e18;
    address public executionDriver;

    // Sets the execution driver address for margin transfers
    function setExecutionDriver(address _executionDriver) external onlyOwner {
        require(_executionDriver != address(0), "Invalid execution driver address"); // Validates driver address
        executionDriver = _executionDriver;
    }

    // Returns the execution driver address
    function getExecutionDriver() external view returns (address driver) {
        driver = executionDriver; // Returns current execution driver
        return driver;
    }

    // Normalizes price to 1e18 precision
    function normalizePrice(address token, uint256 price) internal view returns (uint256 normalizedPrice) {
        require(token != address(0), "Token address cannot be zero"); // Validates token
        uint8 decimals = IERC20(token).decimals();
        if (decimals < 18) return price * (10 ** (18 - decimals));
        if (decimals > 18) return price / (10 ** (decimals - 18));
        return price;
    }

    // Denormalizes amount from 1e18 to token decimals
    function denormalizeAmount(address token, uint256 amount) internal view returns (uint256 denormalizedAmount) {
        require(token != address(0), "Token address cannot be zero"); // Validates token
        uint8 decimals = IERC20(token).decimals();
        return amount * (10 ** decimals) / DECIMAL_PRECISION;
    }

    // Prepares cancellation of a position
    function _prepareCancelPosition(
        uint256 positionId,
        address maker,
        uint8 positionType,
        ICSStorage sContract
    ) internal view returns (address token, address listingAddress, uint256 marginAmount, uint256 denormalizedAmount, bool isValid) {
        ICSStorage.PositionCore1 memory core1 = sContract.positionCore1(positionId);
        ICSStorage.PositionCore2 memory core2 = sContract.positionCore2(positionId);
        if (
            core1.positionId != positionId ||
            core2.status2 != 0 ||
            core2.status1 ||
            core1.makerAddress != maker ||
            core1.positionType != positionType
        ) {
            return (address(0), address(0), 0, 0, false);
        }
        token = sContract.positionToken(positionId);
        require(token != address(0), "Position token address cannot be zero"); // Validates token
        listingAddress = core1.listingAddress;
        marginAmount = sContract.marginParams1(positionId).initialMargin + sContract.marginParams1(positionId).excessMargin;
        denormalizedAmount = denormalizeAmount(token, marginAmount);
        isValid = true;
    }

    // Updates position parameters to mark as closed
    function _updatePositionParams(uint256 positionId, ICSStorage sContract) internal {
        ICSStorage.PositionCore2 memory core2 = sContract.positionCore2(positionId);
        core2.status2 = 1; // Marks position as closed
        ICSStorage.CoreParams memory coreParams = ICSStorage.CoreParams({
            positionId: positionId,
            listingAddress: address(0),
            makerAddress: address(0),
            positionType: 0,
            status1: core2.status1,
            status2: core2.status2
        });
        try sContract.CSUpdate(
            positionId,
            coreParams,
            ICSStorage.PriceParams(0, 0, 0, 0, 0, 0),
            ICSStorage.MarginParams(0, 0, 0, 0, 0),
            ICSStorage.ExitAndInterestParams(0, 0, 0, 0, 0),
            ICSStorage.MakerMarginParams(address(0), address(0), address(0), 0),
            ICSStorage.PositionArrayParams(address(0), 0, false, false),
            ICSStorage.HistoricalInterestParams(0, 0, 0)
        ) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Failed to update position params: ", reason)));
        }
    }

    // Updates margin and removes position index
    function _updateMarginAndIndex(
        uint256 positionId,
        address maker,
        address token,
        uint256 marginAmount,
        address listingAddress,
        uint8 positionType,
        ICSStorage sContract
    ) internal {
        require(maker != address(0), "Maker address cannot be zero"); // Validates maker
        require(token != address(0), "Token address cannot be zero"); // Validates token
        require(listingAddress != address(0), "Listing address cannot be zero"); // Validates listing
        uint256 currentMargin = sContract.makerTokenMargin(maker, token);
        require(currentMargin >= marginAmount, "Insufficient margin to reduce"); // Ensures sufficient margin
        ICSStorage.MakerMarginParams memory makerParams = ICSStorage.MakerMarginParams({
            token: token,
            maker: maker,
            marginToken: token,
            marginAmount: currentMargin - marginAmount
        });
        ICSStorage.PositionArrayParams memory arrayParams = ICSStorage.PositionArrayParams({
            listingAddress: listingAddress,
            positionType: positionType,
            addToPending: false,
            addToActive: false
        });
        ICSStorage.HistoricalInterestParams memory historicalInterestParams = ICSStorage.HistoricalInterestParams({
            longIO: 0,
            shortIO: 0,
            timestamp: 0
        });
        try sContract.CSUpdate(
            positionId,
            ICSStorage.CoreParams(0, address(0), address(0), 0, false, 0),
            ICSStorage.PriceParams(0, 0, 0, 0, 0, 0),
            ICSStorage.MarginParams(0, 0, 0, 0, 0),
            ICSStorage.ExitAndInterestParams(0, 0, 0, 0, 0),
            makerParams,
            arrayParams,
            historicalInterestParams
        ) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Failed to update margin and index: ", reason)));
        }
    }

    // Computes payout for long position
    function _computePayoutLong(
        uint256 positionId,
        address listingAddress,
        address tokenB,
        ICSStorage storageContract
    ) internal view returns (uint256 payout) {
        ICSStorage.MarginParams1 memory margin1 = storageContract.marginParams1(positionId);
        ICSStorage.MarginParams2 memory margin2 = storageContract.marginParams2(positionId);
        ICSStorage.PriceParams1 memory price1 = storageContract.priceParams1(positionId);
        uint256 currentPrice;
        try ISSListing(listingAddress).prices(0) returns (uint256 price) {
            currentPrice = normalizePrice(tokenB, price);
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Price fetch failed: ", reason)));
        }
        require(currentPrice > 0, "Invalid current price for long position payout"); // Validates price
        address maker = storageContract.positionCore1(positionId).makerAddress;
        address tokenA = ISSListing(listingAddress).tokenA();
        uint256 totalMargin;
        try storageContract.makerTokenMargin(maker, tokenA) returns (uint256 margin) {
            totalMargin = margin;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Maker margin fetch failed: ", reason)));
        }
        uint256 leverageAmount = uint256(price1.leverage) * margin1.initialMargin;
        uint256 baseValue = (margin1.taxedMargin + totalMargin + leverageAmount) / currentPrice;
        return baseValue > margin2.initialLoan ? baseValue - margin2.initialLoan : 0;
    }

    // Computes payout for short position
    function _computePayoutShort(
        uint256 positionId,
        address listingAddress,
        address tokenA,
        ICSStorage storageContract
    ) internal view returns (uint256 payout) {
        ICSStorage.MarginParams1 memory margin1 = storageContract.marginParams1(positionId);
        ICSStorage.PriceParams1 memory price1 = storageContract.priceParams1(positionId);
        uint256 currentPrice;
        try ISSListing(listingAddress).prices(0) returns (uint256 price) {
            currentPrice = normalizePrice(tokenA, price);
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Price fetch failed: ", reason)));
        }
        require(currentPrice > 0, "Invalid current price for short position payout"); // Validates price
        address maker = storageContract.positionCore1(positionId).makerAddress;
        address tokenB = ISSListing(listingAddress).tokenB();
        uint256 totalMargin;
        try storageContract.makerTokenMargin(maker, tokenB) returns (uint256 margin) {
            totalMargin = margin;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Maker margin fetch failed: ", reason)));
        }
        uint256 priceDiff = price1.priceAtEntry > currentPrice ? price1.priceAtEntry - currentPrice : 0;
        uint256 profit = priceDiff * margin1.initialMargin * uint256(price1.leverage);
        return profit + (margin1.taxedMargin + totalMargin) * currentPrice / DECIMAL_PRECISION;
    }

    // Executes payout update via ISSListing.ssUpdate
    function _executePayoutUpdate(
        uint256 positionId,
        address listingAddress,
        uint256 payout,
        uint8 positionType,
        address maker,
        address token
    ) internal {
        ISSListing.ListingPayoutUpdate[] memory updates = new ISSListing.ListingPayoutUpdate[](1);
        updates[0] = ISSListing.ListingPayoutUpdate({
            payoutType: positionType,
            recipient: maker,
            required: denormalizeAmount(token, payout)
        });
        try ISSListing(listingAddress).ssUpdate(updates) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Payout update failed: ", reason)));
        }
    }

    // Deducts margin and updates makerTokenMargin
    function _deductMarginAndRemoveToken(
        address maker,
        address token,
        uint256 taxedMargin,
        uint256 excessMargin,
        ICSStorage storageContract
    ) internal {
        uint256 transferAmount = taxedMargin + excessMargin;
        ICSStorage.MakerMarginParams memory makerMarginParams = ICSStorage.MakerMarginParams({
            token: address(0),
            maker: maker,
            marginToken: token,
            marginAmount: 0
        });
        try storageContract.makerTokenMargin(maker, token) returns (uint256 margin) {
            makerMarginParams.marginAmount = margin - transferAmount;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Maker margin fetch failed: ", reason)));
        }
        try storageContract.CSUpdate(
            0,
            ICSStorage.CoreParams({
                positionId: 0,
                listingAddress: address(0),
                makerAddress: address(0),
                positionType: 0,
                status1: false,
                status2: 0
            }),
            ICSStorage.PriceParams({
                minEntryPrice: 0,
                maxEntryPrice: 0,
                minPrice: 0,
                priceAtEntry: 0,
                leverage: 0,
                liquidationPrice: 0
            }),
            ICSStorage.MarginParams({
                initialMargin: 0,
                taxedMargin: 0,
                excessMargin: 0,
                fee: 0,
                initialLoan: 0
            }),
            ICSStorage.ExitAndInterestParams({
                stopLossPrice: 0,
                takeProfitPrice: 0,
                exitPrice: 0,
                leverageAmount: 0,
                timestamp: 0
            }),
            makerMarginParams,
            ICSStorage.PositionArrayParams({
                listingAddress: address(0),
                positionType: 0,
                addToPending: false,
                addToActive: false
            }),
            ICSStorage.HistoricalInterestParams({
                longIO: 0,
                shortIO: 0,
                timestamp: 0
            })
        ) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("CSUpdate failed: ", reason)));
        }
    }

    // Prepares payout for drift
    function _prepDriftPayout(
        uint256 positionId,
        ICSStorage.PositionCore1 memory core1,
        ICSStorage sContract
    ) internal view returns (uint256 payout, address token) {
        if (core1.positionType == 0) {
            token = ISSListing(core1.listingAddress).tokenB();
            payout = _computePayoutLong(positionId, core1.listingAddress, token, sContract);
        } else {
            token = ISSListing(core1.listingAddress).tokenA();
            payout = _computePayoutShort(positionId, core1.listingAddress, token, sContract);
        }
    }

    // Prepares margin deduction for drift
    function _prepDriftMargin(
        uint256 positionId,
        ICSStorage.PositionCore1 memory core1,
        ICSStorage sContract
    ) internal returns (ICSStorage.MarginParams1 memory margin1, address marginToken) {
        margin1 = sContract.marginParams1(positionId);
        marginToken = core1.positionType == 0 ? ISSListing(core1.listingAddress).tokenA() : ISSListing(core1.listingAddress).tokenB();
        _deductMarginAndRemoveToken(
            core1.makerAddress,
            marginToken,
            margin1.taxedMargin,
            margin1.excessMargin,
            sContract
        );
    }
}