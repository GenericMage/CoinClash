/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-07-20: Fixed _createOrderForPosition to approve orderRouter for margin transfer using IERC20.approve instead of direct transfer, then call createBuyOrder/createSellOrder, incremented version to 0.0.9.
 - 2025-07-20: Fixed TypeError by adding makerTokenMargin to ICSStorage interface, corrected ParserError in priceParams2 function declaration, removed incorrect CCOrderRouter.sol import, incremented version to 0.0.8.
 - 2025-07-20: Added orderRouter state variable, setOrderRouter, getOrderRouter, and helper functions (_createOrderForPosition, _updateExcessTokens) to integrate order creation via CCOrderRouter during position activation, updated _processPendingPosition to use these helpers, incremented version to 0.0.7.
 - 2025-07-20: Updated _transferMarginToListing to allow transfers from any address to support cancelPosition in CCSExecutionDriver, incremented version to 0.0.6.
 - 2025-07-19: Refactored _processActivePosition to address stack too deep error by splitting into _prepareActivePositionCheck and _executeActivePositionClose helpers, optimized parameter passing, maintained incremental ICSStorage updates, incremented version to 0.0.5.
 - 2025-07-19: Fixed incorrect emit syntax for PositionClosed event, resolved shadowed storageContract declarations by renaming function parameters, incremented version to 0.0.4.
 - 2025-07-19: Fixed shadowed storageContract declarations, added bytesToString helper for CSUpdate string conversion, moved PositionClosed event earlier in ICSStorage interface, maintained split CSUpdate calls and zero-bound entry price execution, incremented version to 0.0.3.
 - 2025-07-19: Inlined ICSStorage interface, fixed struct references, incremented version to 0.0.2.
 - 2025-07-18: Created CCSExecutionPartial contract to store helper functions for CCSExecutionDriver, adapted from CSDExecutionPartial and SSCrossDriver. Uses CSStorage for state updates via CSUpdate. Version set to 0.0.1.
*/

pragma solidity ^0.8.2;

import "../imports/SafeERC20.sol";
import "../imports/Ownable.sol";

interface ISSAgent {
    struct ListingDetails {
        address listingAddress; // Listing contract address
        address liquidityAddress; // Associated liquidity contract address
        address tokenA; // First token in pair
        address tokenB; // Second token in pair
        uint256 listingId; // Listing ID
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

interface ICSStorage {
    event PositionClosed(uint256 indexed positionId, address indexed maker, uint256 payout); // Moved earlier for visibility
    struct PositionCore1 {
        uint256 positionId; // Unique identifier for the position
        address listingAddress; // Address of the associated listing contract
        address makerAddress; // Address of the position owner
        uint8 positionType; // 0 for long, 1 for short
    }
    struct PositionCore2 {
        bool status1; // True if position is active, false if pending
        uint8 status2; // 0 for open, 1 for closed
    }
    struct PriceParams1 {
        uint256 minEntryPrice; // Minimum entry price, normalized
        uint256 maxEntryPrice; // Maximum entry price, normalized
        uint256 minPrice; // Minimum price at entry, normalized
        uint256 priceAtEntry; // Actual entry price, normalized
        uint8 leverage; // Leverage multiplier (2–100)
    }
    struct PriceParams2 {
        uint256 liquidationPrice; // Price at which position is liquidated, normalized
    }
    struct MarginParams1 {
        uint256 initialMargin; // Initial margin provided, normalized
        uint256 taxedMargin; // Margin after fees, normalized
        uint256 excessMargin; // Additional margin, normalized
        uint256 fee; // Fee charged for position, normalized
    }
    struct MarginParams2 {
        uint256 initialLoan; // Loan amount for leverage, normalized
    }
    struct ExitParams {
        uint256 stopLossPrice; // Stop-loss price, normalized
        uint256 takeProfitPrice; // Take-profit price, normalized
        uint256 exitPrice; // Actual exit price, normalized
    }
    struct OpenInterest {
        uint256 leverageAmount; // Leveraged position size, normalized
        uint256 timestamp; // Timestamp of position creation or update
    }
    function positionCore1(uint256) external view returns (PositionCore1 memory);
    function positionCore2(uint256) external view returns (PositionCore2 memory);
    function priceParams1(uint256) external view returns (PriceParams1 memory);
    function priceParams2(uint256) external view returns (PriceParams2 memory);
    function marginParams1(uint256) external view returns (MarginParams1 memory);
    function marginParams2(uint256) external view returns (MarginParams2 memory);
    function exitParams(uint256) external view returns (ExitParams memory);
    function openInterest(uint256) external view returns (OpenInterest memory);
    function positionToken(uint256) external view returns (address);
    function makerTokenMargin(address, address) external view returns (uint256);
    function pendingPositions(address, uint8) external view returns (uint256[] memory);
    function positionsByType(uint8) external view returns (uint256[] memory);
    function longIOByHeight(uint256) external view returns (uint256);
    function shortIOByHeight(uint256) external view returns (uint256);
    function positionCount() external view returns (uint256);
    function removePositionIndex(uint256 positionId, uint8 positionType, address listingAddress) external;
    function removeToken(address maker, address token) external;
    function CSUpdate(
        uint256 positionId,
        string memory coreParams,
        string memory priceParams,
        string memory marginParams,
        string memory exitAndInterestParams,
        string memory makerMarginParams,
        string memory positionArrayParams,
        string memory historicalInterestParams
    ) external;
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

contract CCSExecutionPartial is Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant DECIMAL_PRECISION = 1e18;
    address public agentAddress;
    ICSStorage public storageContract; // Reference to external storage contract
    ICCOrderRouter public orderRouter; // Reference to order router contract

    constructor(address _storageContract) {
        require(_storageContract != address(0), "Invalid storage address"); // Ensures valid storage contract address
        storageContract = ICSStorage(_storageContract);
    }

    // Sets order router address
    function setOrderRouter(address newOrderRouter) external onlyOwner {
        require(newOrderRouter != address(0), "Invalid order router address"); // Validates order router address
        orderRouter = ICCOrderRouter(newOrderRouter);
    }

    // Returns order router address
    function getOrderRouter() external view returns (address) {
        return address(orderRouter); // Returns current order router address
    }

    // Helper function to convert bytes to string for CSUpdate
    function bytesToString(bytes memory data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = alphabet[uint8(data[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }

    // Sets agent address
    function setAgent(address newAgentAddress) external onlyOwner {
        require(newAgentAddress != address(0), "Invalid agent address"); // Validates agent address
        agentAddress = newAgentAddress;
    }

    // Normalizes price based on token decimals
    function normalizePrice(address token, uint256 price) internal view returns (uint256) {
        uint8 decimals = IERC20(token).decimals();
        if (decimals < 18) return price * (10 ** (18 - decimals));
        if (decimals > 18) return price / (10 ** (decimals - 18));
        return price;
    }

    // Denormalizes amount based on token decimals
    function denormalizeAmount(address token, uint256 amount) internal view returns (uint256) {
        uint8 decimals = IERC20(token).decimals();
        return amount * (10 ** decimals) / DECIMAL_PRECISION;
    }

    // Normalizes amount based on token decimals
    function normalizeAmount(address token, uint256 amount) internal view returns (uint256) {
        uint8 decimals = IERC20(token).decimals();
        return amount * DECIMAL_PRECISION / (10 ** decimals);
    }

    // Computes fee based on margin and leverage
    function computeFee(uint256 initialMargin, uint8 leverage) internal pure returns (uint256) {
        uint256 feePercent = uint256(leverage) - 1;
        return (initialMargin * feePercent * DECIMAL_PRECISION) / 100 / DECIMAL_PRECISION;
    }

    // Parses entry price data
    function _parseEntryPriceInternal(
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        address listingAddress
    ) internal view returns (uint256 currentPrice, uint256 minPrice, uint256 maxPrice, uint256 priceAtEntry) {
        currentPrice = ISSListing(listingAddress).prices(listingAddress);
        minPrice = minEntryPrice;
        maxPrice = maxEntryPrice;
        priceAtEntry = (minPrice == 0 && maxPrice == 0) ? currentPrice : (currentPrice >= minPrice && currentPrice <= maxPrice ? currentPrice : 0);
        return (currentPrice, minPrice, maxPrice, priceAtEntry);
    }

    // Transfers liquidity fee to liquidity contract
    function _transferLiquidityFee(
        address listingAddress,
        address token,
        uint256 fee,
        uint8 positionType
    ) internal {
        address liquidityAddr = ISSListing(listingAddress).liquidityAddressView(listingAddress);
        require(liquidityAddr != address(0), "Invalid liquidity address"); // Validates liquidity address
        if (fee > 0) {
            uint256 denormalizedFee = denormalizeAmount(token, fee);
            uint256 balanceBefore = IERC20(token).balanceOf(liquidityAddr);
            bool success = IERC20(token).transfer(liquidityAddr, denormalizedFee);
            require(success, "Transfer failed"); // Ensures successful transfer
            uint256 balanceAfter = IERC20(token).balanceOf(liquidityAddr);
            require(balanceAfter - balanceBefore == denormalizedFee, "Fee transfer failed"); // Verifies balance update
            ISSLiquidityTemplate(liquidityAddr).addFees(address(this), positionType == 0 ? true : false, denormalizedFee);
        }
    }

    // Transfers margin to listing contract
    function _transferMarginToListing(address token, uint256 amount, address listingAddress) internal returns (uint256 normalizedAmount) {
        normalizedAmount = normalizeAmount(token, amount);
        uint256 balanceBefore = IERC20(token).balanceOf(listingAddress);
        bool success = IERC20(token).transferFrom(address(this), listingAddress, amount);
        require(success, "TransferFrom failed"); // Ensures successful transfer
        uint256 balanceAfter = IERC20(token).balanceOf(listingAddress);
        require(balanceAfter - balanceBefore == amount, "Balance update failed"); // Verifies balance update
    }

    // Updates listing contract with margin amount
    function _updateListingMargin(address listingAddress, uint256 amount) internal {
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](1);
        updates[0] = ISSListing.UpdateType({
            updateType: 0,
            index: 0,
            value: amount,
            addr: address(0),
            recipient: address(0)
        });
        ISSListing(listingAddress).update(address(this), updates);
    }

    // Creates order for position activation
    function _createOrderForPosition(
        uint256 positionId,
        uint8 positionType,
        address listingAddress,
        uint256 marginAmount
    ) internal {
        address token = positionType == 0 ? ISSListing(listingAddress).tokenA() : ISSListing(listingAddress).tokenB();
        uint256 denormalizedMargin = denormalizeAmount(token, marginAmount);
        bool success = IERC20(token).approve(address(orderRouter), denormalizedMargin);
        require(success, "Approval failed"); // Ensures successful approval
        if (positionType == 0) {
            orderRouter.createSellOrder(listingAddress, listingAddress, denormalizedMargin, 0, 0);
        } else {
            orderRouter.createBuyOrder(listingAddress, listingAddress, denormalizedMargin, 0, 0);
        }
    }

    // Updates listing balances for excess tokens
    function _updateExcessTokens(address listingAddress, address tokenA, address tokenB) internal {
        uint256 balanceA = IERC20(tokenA).balanceOf(listingAddress);
        uint256 balanceB = IERC20(tokenB).balanceOf(listingAddress);
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](2);
        updates[0] = ISSListing.UpdateType({
            updateType: 0,
            index: 0,
            value: balanceA,
            addr: tokenA,
            recipient: address(0)
        });
        updates[1] = ISSListing.UpdateType({
            updateType: 0,
            index: 1,
            value: balanceB,
            addr: tokenB,
            recipient: address(0)
        });
        ISSListing(listingAddress).update(address(this), updates);
    }

    // Computes loan and liquidation price for long position
    function _computeLoanAndLiquidationLong(
        uint256 leverageAmount,
        uint256 minPrice,
        address maker,
        address tokenA,
        ICSStorage storageContractInstance
    ) internal view returns (uint256 initialLoan, uint256 liquidationPrice) {
        initialLoan = leverageAmount / minPrice;
        uint256 marginRatio = storageContractInstance.makerTokenMargin(maker, tokenA) / leverageAmount;
        liquidationPrice = marginRatio < minPrice ? minPrice - marginRatio : 0;
    }

    // Computes loan and liquidation price for short position
    function _computeLoanAndLiquidationShort(
        uint256 leverageAmount,
        uint256 minPrice,
        address maker,
        address tokenB,
        ICSStorage storageContractInstance
    ) internal view returns (uint256 initialLoan, uint256 liquidationPrice) {
        initialLoan = leverageAmount * minPrice;
        uint256 marginRatio = storageContractInstance.makerTokenMargin(maker, tokenB) / leverageAmount;
        liquidationPrice = minPrice + marginRatio;
    }

    // Updates core parameters
    function _updateCoreParams(uint256 positionId, ICSStorage.PositionCore1 memory core1) internal {
        storageContract.CSUpdate(positionId, bytesToString(abi.encode(core1)), "", "", "", "", "", "");
    }

    // Updates position status
    function _updatePositionStatus(uint256 positionId, ICSStorage.PositionCore2 memory core2) internal {
        storageContract.CSUpdate(positionId, "", bytesToString(abi.encode(core2)), "", "", "", "", "");
    }

    // Updates price parameters
    function _updatePriceParams(uint256 positionId, ICSStorage.PriceParams1 memory price1, ICSStorage.PriceParams2 memory price2) internal {
        storageContract.CSUpdate(positionId, "", "", bytesToString(abi.encode(price1, price2)), "", "", "", "");
    }

    // Updates margin parameters
    function _updateMarginParams(uint256 positionId, ICSStorage.MarginParams1 memory margin1, ICSStorage.MarginParams2 memory margin2) internal {
        storageContract.CSUpdate(positionId, "", "", "", bytesToString(abi.encode(margin1, margin2)), "", "", "");
    }

    // Updates exit parameters
    function _updateExitParams(uint256 positionId, ICSStorage.ExitParams memory exit) internal {
        storageContract.CSUpdate(positionId, "", "", "", "", bytesToString(abi.encode(exit)), "", "");
    }

    // Updates open interest
    function _updateOpenInterest(uint256 positionId, ICSStorage.OpenInterest memory interest) internal {
        storageContract.CSUpdate(positionId, "", "", "", "", "", bytesToString(abi.encode(interest)), "");
    }

    // Updates maker margin
    function _updateMakerMarginParams(address maker, address token, uint256 marginAmount) internal {
        storageContract.CSUpdate(0, "", "", "", "", "", bytesToString(abi.encode(maker, token, marginAmount)), "");
    }

    // Updates historical interest
    function _updateHistoricalInterest(uint256 amount, uint8 positionType, address listingAddress) internal {
        uint256 height = block.number;
        uint256 longIO = positionType == 0 ? storageContract.longIOByHeight(height) + amount : storageContract.longIOByHeight(height);
        uint256 shortIO = positionType == 1 ? storageContract.shortIOByHeight(height) + amount : storageContract.shortIOByHeight(height);
        storageContract.CSUpdate(0, "", "", "", "", "", "", bytesToString(abi.encode(longIO, shortIO, block.timestamp)));
    }

    // Updates position liquidation prices
    function _updatePositionLiquidationPrices(address maker, address token, address listingAddress) internal {
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

    // Updates liquidation price for a specific position
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
        _updatePriceParams(positionId, ICSStorage.PriceParams1(0, 0, 0, 0, 0), ICSStorage.PriceParams2(newLiquidationPrice));
    }

    // Validates and normalizes pull margin request
    function _validateAndNormalizePullMargin(address listingAddress, bool tokenA, uint256 amount) internal view returns (address token, uint256 normalizedAmount) {
        require(amount > 0, "Invalid amount"); // Ensures non-zero amount
        require(listingAddress != address(0), "Invalid listing"); // Validates listing address
        (bool isValid, ) = ISSAgent(agentAddress).isValidListing(listingAddress);
        require(isValid, "Invalid listing"); // Ensures listing is valid
        token = tokenA ? ISSListing(listingAddress).tokenA() : ISSListing(listingAddress).tokenB();
        normalizedAmount = normalizeAmount(token, amount);
        require(normalizedAmount <= storageContract.makerTokenMargin(msg.sender, token), "Insufficient margin"); // Ensures sufficient margin
    }

    // Updates maker's margin balance
    function _updateMakerMargin(address maker, address token, uint256 normalizedAmount) internal {
        uint256 currentMargin = storageContract.makerTokenMargin(maker, token);
        _updateMakerMarginParams(maker, token, currentMargin + normalizedAmount);
    }

    // Reduces maker's margin balance
    function _reduceMakerMargin(address maker, address token, uint256 normalizedAmount) internal {
        uint256 currentMargin = storageContract.makerTokenMargin(maker, token);
        _updateMakerMarginParams(maker, token, currentMargin - normalizedAmount);
        if (currentMargin - normalizedAmount == 0) {
            storageContract.removeToken(maker, token);
        }
    }

    // Executes payout for margin withdrawal
    function _executeMarginPayout(address listingAddress, address recipient, uint256 amount) internal {
        ISSListing.PayoutUpdate[] memory updates = new ISSListing.PayoutUpdate[](1);
        updates[0] = ISSListing.PayoutUpdate({
            payoutType: 0,
            recipient: recipient,
            required: amount
        });
        ISSListing(listingAddress).ssUpdate(address(this), updates);
    }

    // Updates stop-loss price
    function _updateSL(
        uint256 positionId,
        uint256 newStopLossPrice,
        address listingAddress,
        uint8 positionType,
        uint256 minPrice,
        uint256 maxEntryPrice,
        uint256 currentPrice
    ) internal {
        _updateExitParams(positionId, ICSStorage.ExitParams(newStopLossPrice, 0, 0));
    }

    // Updates take-profit price
    function _updateTP(
        uint256 positionId,
        uint256 newTakeProfitPrice,
        address listingAddress,
        uint8 positionType,
        uint256 priceAtEntry,
        uint256 maxEntryPrice,
        uint256 currentPrice
    ) internal {
        if (positionType == 0) {
            require(newTakeProfitPrice == 0 || newTakeProfitPrice > priceAtEntry, "Invalid TP for long"); // Ensures valid TP for long
        } else {
            require(newTakeProfitPrice == 0 || newTakeProfitPrice < priceAtEntry, "Invalid TP for short"); // Ensures valid TP for short
        }
        _updateExitParams(positionId, ICSStorage.ExitParams(0, newTakeProfitPrice, 0));
    }

    // Computes payout for long position
    function _computePayoutLong(
        uint256 positionId,
        address listingAddress,
        address tokenB,
        ICSStorage storageContractInstance
    ) internal view returns (uint256) {
        ICSStorage.MarginParams1 memory margin1 = storageContractInstance.marginParams1(positionId);
        ICSStorage.MarginParams2 memory margin2 = storageContractInstance.marginParams2(positionId);
        ICSStorage.PriceParams1 memory price1 = storageContractInstance.priceParams1(positionId);
        uint256 currentPrice = normalizePrice(tokenB, ISSListing(listingAddress).prices(listingAddress));
        require(currentPrice > 0, "Invalid price"); // Ensures valid price
        uint256 totalMargin = storageContractInstance.makerTokenMargin(storageContractInstance.positionCore1(positionId).makerAddress, ISSListing(listingAddress).tokenA());
        uint256 leverageAmount = uint256(price1.leverage) * margin1.initialMargin;
        uint256 baseValue = (margin1.taxedMargin + totalMargin + leverageAmount) / currentPrice;
        return baseValue > margin2.initialLoan ? baseValue - margin2.initialLoan : 0;
    }

    // Computes payout for short position
    function _computePayoutShort(
        uint256 positionId,
        address listingAddress,
        address tokenA,
        ICSStorage storageContractInstance
    ) internal view returns (uint256) {
        ICSStorage.MarginParams1 memory margin1 = storageContractInstance.marginParams1(positionId);
        ICSStorage.PriceParams1 memory price1 = storageContractInstance.priceParams1(positionId);
        uint256 currentPrice = normalizePrice(tokenA, ISSListing(listingAddress).prices(listingAddress));
        require(currentPrice > 0, "Invalid price"); // Ensures valid price
        uint256 totalMargin = storageContractInstance.makerTokenMargin(storageContractInstance.positionCore1(positionId).makerAddress, ISSListing(listingAddress).tokenB());
        uint256 priceDiff = price1.priceAtEntry > currentPrice ? price1.priceAtEntry - currentPrice : 0;
        uint256 profit = priceDiff * margin1.initialMargin * uint256(price1.leverage);
        return profit + (margin1.taxedMargin + totalMargin) * currentPrice / DECIMAL_PRECISION;
    }

    // Prepares closing of long position
    function _prepCloseLong(
        uint256 positionId,
        address listingAddress
    ) internal returns (uint256 payout) {
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.MarginParams1 memory margin1 = storageContract.marginParams1(positionId);
        address tokenB = ISSListing(listingAddress).tokenB();
        payout = _computePayoutLong(positionId, listingAddress, tokenB, storageContract);
        address tokenA = ISSListing(listingAddress).tokenA();
        uint256 marginAmount = margin1.taxedMargin + margin1.excessMargin;
        _updateCoreParams(positionId, ICSStorage.PositionCore1(0, address(0), address(0), 0));
        _updatePositionStatus(positionId, ICSStorage.PositionCore2(false, 1));
        _updatePriceParams(positionId, ICSStorage.PriceParams1(0, 0, 0, 0, 0), ICSStorage.PriceParams2(0));
        _updateMarginParams(positionId, ICSStorage.MarginParams1(0, 0, 0, 0), ICSStorage.MarginParams2(0));
        _updateExitParams(positionId, ICSStorage.ExitParams(0, 0, normalizePrice(tokenB, ISSListing(listingAddress).prices(listingAddress))));
        _updateOpenInterest(positionId, ICSStorage.OpenInterest(0, 0));
        _updateMakerMarginParams(core1.makerAddress, tokenA, storageContract.makerTokenMargin(core1.makerAddress, tokenA) - marginAmount);
        return payout;
    }

    // Prepares closing of short position
    function _prepCloseShort(
        uint256 positionId,
        address listingAddress
    ) internal returns (uint256 payout) {
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.MarginParams1 memory margin1 = storageContract.marginParams1(positionId);
        address tokenA = ISSListing(listingAddress).tokenA();
        payout = _computePayoutShort(positionId, listingAddress, tokenA, storageContract);
        address tokenB = ISSListing(listingAddress).tokenB();
        uint256 marginAmount = margin1.taxedMargin + margin1.excessMargin;
        _updateCoreParams(positionId, ICSStorage.PositionCore1(0, address(0), address(0), 0));
        _updatePositionStatus(positionId, ICSStorage.PositionCore2(false, 1));
        _updatePriceParams(positionId, ICSStorage.PriceParams1(0, 0, 0, 0, 0), ICSStorage.PriceParams2(0));
        _updateMarginParams(positionId, ICSStorage.MarginParams1(0, 0, 0, 0), ICSStorage.MarginParams2(0));
        _updateExitParams(positionId, ICSStorage.ExitParams(0, 0, normalizePrice(tokenA, ISSListing(listingAddress).prices(listingAddress))));
        _updateOpenInterest(positionId, ICSStorage.OpenInterest(0, 0));
        _updateMakerMarginParams(core1.makerAddress, tokenB, storageContract.makerTokenMargin(core1.makerAddress, tokenB) - marginAmount);
        return payout;
    }

    // Processes pending position
    function _processPendingPosition(
        uint256 positionId,
        uint8 positionType,
        address listingAddress,
        uint256[] memory pending,
        uint256 i,
        uint256 currentPrice
    ) internal returns (bool continueLoop) {
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
        ICSStorage.PriceParams1 memory price1 = storageContract.priceParams1(positionId);
        ICSStorage.PriceParams2 memory price2 = storageContract.priceParams2(positionId);
        ICSStorage.MarginParams1 memory margin1 = storageContract.marginParams1(positionId);
        _updateLiquidationPrices(positionId, core1.makerAddress, positionType, listingAddress);
        price2 = storageContract.priceParams2(positionId);
        bool shouldLiquidate = positionType == 0 ? currentPrice <= price2.liquidationPrice : currentPrice >= price2.liquidationPrice;
        if (shouldLiquidate) {
            uint256 payout = positionType == 0 ? _prepCloseLong(positionId, listingAddress) : _prepCloseShort(positionId, listingAddress);
            storageContract.removePositionIndex(positionId, positionType, listingAddress);
            emit ICSStorage.PositionClosed(positionId, core1.makerAddress, payout);
            return true;
        } else if (price1.minEntryPrice == 0 && price1.maxEntryPrice == 0 || (currentPrice >= price1.minEntryPrice && currentPrice <= price1.maxEntryPrice)) {
            uint256 marginAmount = margin1.taxedMargin + margin1.excessMargin;
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

    // Prepares active position check for liquidation or exit conditions
    function _prepareActivePositionCheck(
        uint256 positionId,
        uint8 positionType,
        address listingAddress,
        uint256 currentPrice
    ) internal returns (bool shouldClose, uint256 payout) {
        _updateLiquidationPrices(positionId, storageContract.positionCore1(positionId).makerAddress, positionType, listingAddress);
        ICSStorage.PriceParams2 memory price2 = storageContract.priceParams2(positionId);
        ICSStorage.ExitParams memory exit = storageContract.exitParams(positionId);
        bool shouldLiquidate = positionType == 0 ? currentPrice <= price2.liquidationPrice : currentPrice >= price2.liquidationPrice;
        bool shouldCloseSL = exit.stopLossPrice > 0 && (positionType == 0 ? currentPrice <= exit.stopLossPrice : currentPrice >= exit.stopLossPrice);
        bool shouldCloseTP = exit.takeProfitPrice > 0 && (positionType == 0 ? currentPrice >= exit.takeProfitPrice : currentPrice <= exit.takeProfitPrice);
        if (shouldLiquidate || shouldCloseSL || shouldCloseTP) {
            payout = positionType == 0 ? _prepCloseLong(positionId, listingAddress) : _prepCloseShort(positionId, listingAddress);
            return (true, payout);
        }
        return (false, 0);
    }

    // Executes active position close
    function _executeActivePositionClose(
        uint256 positionId,
        uint8 positionType,
        address listingAddress,
        uint256 payout,
        address maker
    ) internal returns (bool continueLoop) {
        storageContract.removePositionIndex(positionId, positionType, listingAddress);
        emit ICSStorage.PositionClosed(positionId, maker, payout);
        return true;
    }

    // Processes active position
    function _processActivePosition(
        uint256 positionId,
        uint8 positionType,
        address listingAddress,
        uint256[] memory active,
        uint256 i,
        uint256 currentPrice
    ) internal returns (bool continueLoop) {
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
        if (core1.positionId == 0 || core1.listingAddress != listingAddress || core2.status2 != 0) {
            return false;
        }
        (bool shouldClose, uint256 payout) = _prepareActivePositionCheck(positionId, positionType, listingAddress, currentPrice);
        if (shouldClose) {
            return _executeActivePositionClose(positionId, positionType, listingAddress, payout, core1.makerAddress);
        }
        return false;
    }

    // Executes pending and active positions
    function _executePositions(address listingAddress, uint256 maxIterations) internal {
        require(listingAddress != address(0), "Invalid listing address"); // Validates listing address
        for (uint8 positionType = 0; positionType <= 1; positionType++) {
            uint256[] memory pending = storageContract.pendingPositions(listingAddress, positionType);
            uint256 processed = 0;
            for (uint256 i = 0; i < pending.length && processed < maxIterations && gasleft() >= 50000; i++) {
                uint256 positionId = pending[i];
                ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
                address token = positionType == 0 ? ISSListing(listingAddress).tokenB() : ISSListing(listingAddress).tokenA();
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
            uint256[] memory active = storageContract.positionsByType(positionType);
            for (uint256 i = 0; i < active.length && processed < maxIterations && gasleft() >= 50000; i++) {
                uint256 positionId = active[i];
                address token = positionType == 0 ? ISSListing(listingAddress).tokenB() : ISSListing(listingAddress).tokenA();
                (uint256 currentPrice,,,) = _parseEntryPriceInternal(
                    storageContract.priceParams1(positionId).minEntryPrice,
                    storageContract.priceParams1(positionId).maxEntryPrice,
                    listingAddress
                );
                currentPrice = normalizePrice(token, currentPrice);
                if (_processActivePosition(positionId, positionType, listingAddress, active, i, currentPrice)) {
                    i--;
                }
                processed++;
            }
        }
    }
}