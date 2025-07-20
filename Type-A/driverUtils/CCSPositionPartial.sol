/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-07-20: Moved executionDriver state variable, setExecutionDriver, and getExecutionDriver from CCSPositionDriver.sol to CCSPositionPartial.sol; updated _transferMarginToListing to access executionDriver directly, resolving DeclarationError. Version set to 0.0.12.
 - 2025-07-20: Updated _transferMarginToListing to transfer margins to executionDriver instead of listing contract, removing ISSListing.UpdateType call as executionDriver will handle margin updates. Version set to 0.0.11.
 - 2025-07-19: Modified _parseEntryPriceInternal to always set priceAtEntry to 0, ensuring all positions are pending by default (status1 = false, status2 = 0) regardless of minEntryPrice and maxEntryPrice, removing immediate execution logic as execution will be handled by a separate contract. Version set to 0.0.10.
 - 2025-07-19: Refactored _prepEnterLong and _prepEnterShort to address stack too deep errors by splitting into internal helper functions (_parsePriceParams, _calcFeeAndMargin, _updateMakerMargin, _calcLoanAndLiquidationLong, _calcLoanAndLiquidationShort, _checkLiquidityLimitLong, _checkLiquidityLimitShort, _transferMarginToListing) organized by task, reducing stack usage while preserving functionality. Version set to 0.0.9.
 - 2025-07-18: Added 'external' visibility specifier to liquidityDetailsView function in ISSLiquidityTemplate interface to fix TypeError and SyntaxError. Version set to 0.0.8.
 - 2025-07-18: Fixed ParserError in toString function by removing invalid 'Hawkins' identifier and correcting address-to-string conversion logic. Version set to 0.0.7.
 - 2025-07-18: Updated ICSStorage interface to include all functions and structs from ICSStorage.sol, adding positionCore2 and other missing view functions for full compatibility with CCSPositionDriver.sol. Version set to 0.0.6.
 - 2025-07-18: Fixed TypeError by converting address to string in CSUpdate calls and removed redundant struct definitions in CCSPositionPartial to use ICSStorage structs directly for type compatibility. Version set to 0.0.5.
 - 2025-07-18: Removed redundant 'external' visibility specifier from liquidityDetailsView function in ISSLiquidityTemplate interface to fix ParserError. Version set to 0.0.4.
 - 2025-07-18: Fixed syntax error in prepEnterShort function by removing erroneous "Mose" identifier. Version set to 0.0.3.
 - 2025-07-18: Updated ICSStorage interface to align with ICSStorage.sol, replacing outdated CSUpdate function signature with string-based parameters and adjusted prepEnterLong and prepEnterShort functions to use hyphen-delimited strings for CSUpdate calls. Version set to 0.0.2.
 - 2025-07-18: Created CCSPositionPartial contract by extracting helper functions from CSDPositionPartial.sol and SSCrossDriver.sol for position creation, cancellation, and closing. Version set to 0.0.1.
*/

pragma solidity ^0.8.2;

import "../imports/SafeERC20.sol";
import "../imports/ReentrancyGuard.sol";
import "../imports/Ownable.sol";

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
    function prices(address listingAddress) external view returns (uint256);
    function liquidityAddressView(address listingAddress) external view returns (address);
    function update(address caller, UpdateType[] memory updates) external;
    function ssUpdate(address caller, PayoutUpdate[] memory updates) external;
}

interface ISSLiquidityTemplate {
    function liquidityDetailsView(address caller) external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees);
    function addFees(address caller, bool isLong, uint256 amount) external;
}

interface ISSAgent {
    struct ListingDetails {
        address listingAddress; // Listing contract address
        address liquidityAddress; // Associated liquidity contract address
        address tokenA; // First token in pair
        address tokenB; // Second token in pair
        uint256 listingId; // Listing ID
    }
    function getListing(address tokenA, address tokenB) external view returns (address);
    function isValidListing(address listingAddress) external view returns (bool isValid, ISSAgent.ListingDetails memory details);
}

interface ICSStorage {
    // Constant for normalizing amounts and prices across token decimals
    function DECIMAL_PRECISION() external view returns (uint256);
    
    // Stores the address of the ISSAgent contract for listing validation
    function agentAddress() external view returns (address);
    
    // Tracks the total number of positions created for unique position IDs
    function positionCount() external view returns (uint256);
    
    // Stores core position data including ID, listing, maker, and type
    struct PositionCore1 {
        uint256 positionId; // Unique identifier for the position
        address listingAddress; // Address of the associated listing contract
        address makerAddress; // Address of the position owner
        uint8 positionType; // 0 for long, 1 for short
    }
    
    // Tracks position status flags for active and closed states
    struct PositionCore2 {
        bool status1; // True if position is active, false if pending
        uint8 status2; // 0 for open, 1 for closed
    }
    
    // Holds price-related data for position entry and leverage
    struct PriceParams1 {
        uint256 minEntryPrice; // Minimum entry price, normalized
        uint256 maxEntryPrice; // Maximum entry price, normalized
        uint256 minPrice; // Minimum price at entry, normalized
        uint256 priceAtEntry; // Actual entry price, normalized
        uint8 leverage; // Leverage multiplier (2–100)
    }
    
    // Stores liquidation price for risk management
    struct PriceParams2 {
        uint256 liquidationPrice; // Price at which position is liquidated, normalized
    }
    
    // Manages margin details for position funding
    struct MarginParams1 {
        uint256 initialMargin; // Initial margin provided, normalized
        uint256 taxedMargin; // Margin after fees, normalized
        uint256 excessMargin; // Additional margin, normalized
        uint256 fee; // Fee charged for position, normalized
    }
    
    // Tracks initial loan amount for leveraged positions
    struct MarginParams2 {
        uint256 initialLoan; // Loan amount for leverage, normalized
    }
    
    // Stores exit conditions for stop-loss and take-profit
    struct ExitParams {
        uint256 stopLossPrice; // Stop-loss price, normalized
        uint256 takeProfitPrice; // Take-profit price, normalized
        uint256 exitPrice; // Actual exit price, normalized
    }
    
    // Records leverage amount and timestamp for open interest tracking
    struct OpenInterest {
        uint256 leverageAmount; // Leveraged position size, normalized
        uint256 timestamp; // Timestamp of position creation or update
    }
    
    // Tracks margin balances per maker and token, normalized to 1e18
    function makerTokenMargin(address maker, address token) external view returns (uint256);
    
    // Lists tokens with non-zero margin balances for each maker
    function makerMarginTokens(address maker) external view returns (address[] memory);
    
    // Stores core position data for a given position ID
    function positionCore1(uint256 positionId) external view returns (PositionCore1 memory);
    
    // Stores status flags for a given position ID
    function positionCore2(uint256 positionId) external view returns (PositionCore2 memory);
    
    // Stores price parameters for a given position ID
    function priceParams1(uint256 positionId) external view returns (PriceParams1 memory);
    
    // Stores liquidation price for a given position ID
    function priceParams2(uint256 positionId) external view returns (PriceParams2 memory);
    
    // Stores margin details for a given position ID
    function marginParams1(uint256 positionId) external view returns (MarginParams1 memory);
    
    // Stores initial loan amount for a given position ID
    function marginParams2(uint256 positionId) external view returns (MarginParams2 memory);
    
    // Stores exit conditions for a given position ID
    function exitParams(uint256 positionId) external view returns (ExitParams memory);
    
    // Stores open interest data for a given position ID
    function openInterest(uint256 positionId) external view returns (OpenInterest memory);
    
    // Lists position IDs by type (0 for long, 1 for short)
    function positionsByType(uint8 positionType) external view returns (uint256[] memory);
    
    // Tracks pending position IDs by listing address and position type
    function pendingPositions(address listingAddress, uint8 positionType) external view returns (uint256[] memory);
    
    // Maps position ID to margin token (tokenA for long, tokenB for short)
    function positionToken(uint256 positionId) external view returns (address);
    
    // Tracks long open interest by block height
    function longIOByHeight(uint256 height) external view returns (uint256);
    
    // Tracks short open interest by block height
    function shortIOByHeight(uint256 height) external view returns (uint256);
    
    // Stores timestamps for open interest updates by block height
    function historicalInterestTimestamps(uint256 height) external view returns (uint256);
    
    // Tracks authorized mux contracts for position updates
    function muxes(address mux) external view returns (bool);
    
    // Updates the ISSAgent address for listing validation, restricted to owner
    function setAgent(address newAgentAddress) external;
    
    // Authorizes a mux contract to call update functions, restricted to owner
    function addMux(address mux) external;
    
    // Revokes a mux contract’s authorization, restricted to owner
    function removeMux(address mux) external;
    
    // Returns an array of authorized mux addresses
    function getMuxesView() external view returns (address[] memory);
    
    // Updates position data using hyphen-delimited strings, restricted to muxes
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
    
    // Removes a position from pending or active arrays, restricted to muxes
    function removePositionIndex(uint256 positionId, uint8 positionType, address listingAddress) external;
    
    // Removes a token from a maker’s margin token list if balance is zero, restricted to muxes
    function removeToken(address maker, address token) external;
    
    // Returns all position data (core, price, margin, exit, token) for a given ID
    function positionByIndex(uint256 positionId) external view returns (
        PositionCore1 memory core1,
        PositionCore2 memory core2,
        PriceParams1 memory price1,
        PriceParams2 memory price2,
        MarginParams1 memory margin1,
        MarginParams2 memory margin2,
        ExitParams memory exit,
        address token
    );
    
    // Returns position IDs by type starting at an index, up to maxIterations
    function PositionsByTypeView(uint8 positionType, uint256 startIndex, uint256 maxIterations) external view returns (uint256[] memory positionIds);
    
    // Returns pending position IDs for a maker starting at an index, up to maxIterations
    function PositionsByAddressView(address maker, uint256 startIndex, uint256 maxIterations) external view returns (uint256[] memory positionIds);
    
    // Returns the count of active positions (status1 true, status2 0)
    function TotalActivePositionsView() external view returns (uint256 count);
    
    // Returns open interest and timestamps for a range of block heights
    function queryInterest(uint256 startIndex, uint256 maxIterations) external view returns (
        uint256[] memory longIO,
        uint256[] memory shortIO,
        uint256[] memory timestamps
    );
    
    // Returns tokens and margins for a maker starting at an index, up to maxIterations
    function makerMarginIndex(address maker, uint256 startIndex, uint256 maxIterations) external view returns (address[] memory tokens, uint256[] memory margins);
    
    // Returns margin ratio, liquidation distance, and estimated profit/loss for a position
    function PositionHealthView(uint256 positionId) external view returns (
        uint256 marginRatio,
        uint256 distanceToLiquidation,
        uint256 estimatedProfitLoss
    );
    
    // Returns makers and margins for a listing’s tokenB from position types
    function AggregateMarginByToken(address tokenA, address tokenB, uint256 startIndex, uint256 maxIterations) external view returns (address[] memory makers, uint256[] memory margins);
    
    // Returns leverage amounts and timestamps for open positions in a listing
    function OpenInterestTrend(address listingAddress, uint256 startIndex, uint256 maxIterations) external view returns (uint256[] memory leverageAmounts, uint256[] memory timestamps);
    
    // Counts positions within 5% of liquidation price for a listing
    function LiquidationRiskCount(address listingAddress, uint256 maxIterations) external view returns (uint256 count);
}

contract CCSPositionPartial is ReentrancyGuard, Ownable {
    uint256 public constant DECIMAL_PRECISION = 1e18;
    address public executionDriver;

    // Sets execution driver address
    function setExecutionDriver(address _executionDriver) external onlyOwner {
        require(_executionDriver != address(0), "Invalid execution driver address");
        executionDriver = _executionDriver;
    }

    // Returns the execution driver address
    function getExecutionDriver() external view returns (address) {
        return executionDriver;
    }

    // Struct for preparing position data
    struct PrepPosition {
        uint256 fee;
        uint256 taxedMargin;
        uint256 leverageAmount;
        uint256 initialLoan;
        uint256 liquidationPrice;
    }

    // Struct for position entry context
    struct EntryContext {
        uint256 positionId;
        address listingAddress;
        uint256 minEntryPrice;
        uint256 maxEntryPrice;
        uint256 initialMargin;
        uint256 excessMargin;
        uint8 leverage;
        uint8 positionType;
        address maker;
        address token;
    }

    // Converts address to string for CSUpdate compatibility
    function toString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }

    // Normalizes price to 18 decimals
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

    // Normalizes amount to 18 decimals
    function normalizeAmount(address token, uint256 amount) internal view returns (uint256) {
        uint8 decimals = IERC20(token).decimals();
        return amount * DECIMAL_PRECISION / (10 ** decimals);
    }

    // Computes fee based on leverage and initial margin
    function computeFee(uint256 initialMargin, uint8 leverage) internal pure returns (uint256) {
        uint256 feePercent = uint256(leverage) - 1;
        return (initialMargin * feePercent * DECIMAL_PRECISION) / 100 / DECIMAL_PRECISION;
    }

    // Parses and validates entry price range, always sets priceAtEntry to 0 for pending status
    function _parseEntryPriceInternal(
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        address listingAddress
    ) internal view returns (uint256 currentPrice, uint256 minPrice, uint256 maxPrice, uint256 priceAtEntry) {
        currentPrice = ISSListing(listingAddress).prices(listingAddress);
        minPrice = minEntryPrice;
        maxPrice = maxEntryPrice;
        priceAtEntry = 0; // Always set to 0 to ensure pending status
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
        require(liquidityAddr != address(0), "Invalid liquidity address");
        if (fee > 0) {
            uint256 denormalizedFee = denormalizeAmount(token, fee);
            uint256 balanceBefore = IERC20(token).balanceOf(liquidityAddr);
            bool success = IERC20(token).transfer(liquidityAddr, denormalizedFee);
            require(success, "Transfer failed");
            uint256 balanceAfter = IERC20(token).balanceOf(liquidityAddr);
            require(balanceAfter - balanceBefore == denormalizedFee, "Fee transfer failed");
            ISSLiquidityTemplate(liquidityAddr).addFees(address(this), positionType == 0 ? true : false, denormalizedFee);
        }
    }

    // Transfers margin to execution driver
    function _transferMarginToListing(
        address token,
        address listingAddress,
        address maker,
        uint256 taxedMargin,
        uint256 excessMargin,
        uint256 fee,
        uint8 positionType
    ) internal {
        uint256 transferAmount = taxedMargin + excessMargin;
        _transferLiquidityFee(listingAddress, token, fee, positionType);
        if (transferAmount > 0) {
            require(executionDriver != address(0), "Execution driver not set");
            uint256 denormalizedAmount = denormalizeAmount(token, transferAmount);
            uint256 balanceBefore = IERC20(token).balanceOf(executionDriver);
            bool success = IERC20(token).transferFrom(msg.sender, executionDriver, denormalizedAmount);
            require(success, "TransferFrom failed");
            uint256 balanceAfter = IERC20(token).balanceOf(executionDriver);
            require(balanceAfter - balanceBefore == denormalizedAmount, "Balance update failed");
        }
    }

    // Checks liquidity limit for long positions
    function _checkLiquidityLimitLong(
        address listingAddress,
        uint256 initialLoan,
        uint8 leverage
    ) internal view returns (address tokenB) {
        address liquidityAddr = ISSListing(listingAddress).liquidityAddressView(listingAddress);
        (, uint256 yLiquid,,) = ISSLiquidityTemplate(liquidityAddr).liquidityDetailsView(address(this));
        uint256 limitPercent = 101 - uint256(leverage);
        uint256 limit = yLiquid * limitPercent / 100;
        require(initialLoan <= limit, "Initial loan exceeds limit");
        return ISSListing(listingAddress).tokenB();
    }

    // Checks liquidity limit for short positions
    function _checkLiquidityLimitShort(
        address listingAddress,
        uint256 initialLoan,
        uint8 leverage
    ) internal view returns (address tokenA) {
        address liquidityAddr = ISSListing(listingAddress).liquidityAddressView(listingAddress);
        (uint256 xLiquid,,,) = ISSLiquidityTemplate(liquidityAddr).liquidityDetailsView(address(this));
        uint256 limitPercent = 101 - uint256(leverage);
        uint256 limit = xLiquid * limitPercent / 100;
        require(initialLoan <= limit, "Initial loan exceeds limit");
        return ISSListing(listingAddress).tokenA();
    }

    // Computes loan and liquidation price for long positions
    function _computeLoanAndLiquidationLong(
        uint256 leverageAmount,
        uint256 minPrice,
        address maker,
        address tokenA,
        ICSStorage storageContract
    ) internal view returns (uint256 initialLoan, uint256 liquidationPrice) {
        initialLoan = leverageAmount / minPrice;
        uint256 marginRatio = storageContract.makerTokenMargin(maker, tokenA) / leverageAmount;
        liquidationPrice = marginRatio < minPrice ? minPrice - marginRatio : 0;
    }

    // Computes loan and liquidation price for short positions
    function _computeLoanAndLiquidationShort(
        uint256 leverageAmount,
        uint256 minPrice,
        address maker,
        address tokenB,
        ICSStorage storageContract
    ) internal view returns (uint256 initialLoan, uint256 liquidationPrice) {
        initialLoan = leverageAmount * minPrice;
        uint256 marginRatio = storageContract.makerTokenMargin(maker, tokenB) / leverageAmount;
        liquidationPrice = minPrice + marginRatio;
    }

    // Deducts margin and removes token from maker's margin list
    function _deductMarginAndRemoveToken(
        address maker,
        address token,
        uint256 taxedMargin,
        uint256 excessMargin,
        ICSStorage storageContract
    ) internal {
        uint256 transferAmount = taxedMargin + excessMargin;
        string memory makerMarginParams = string(abi.encodePacked(
            toString(maker), "-", toString(token), "-", storageContract.makerTokenMargin(maker, token) - transferAmount
        ));
        storageContract.CSUpdate(
            0, // positionId (not updated)
            "", // coreParams (not updated)
            "", // priceParams (not updated)
            "", // marginParams (not updated)
            "", // exitAndInterestParams (not updated)
            makerMarginParams, // Update maker margin
            "", // positionArrayParams (not updated)
            "" // historicalInterestParams (not updated)
        );
    }

    // Computes payout for long positions
    function _computePayoutLong(
        uint256 positionId,
        address listingAddress,
        address tokenB,
        ICSStorage storageContract
    ) internal view returns (uint256) {
        ICSStorage.MarginParams1 memory margin1 = storageContract.marginParams1(positionId);
        ICSStorage.MarginParams2 memory margin2 = storageContract.marginParams2(positionId);
        ICSStorage.PriceParams1 memory price1 = storageContract.priceParams1(positionId);
        uint256 currentPrice = normalizePrice(tokenB, ISSListing(listingAddress).prices(listingAddress));
        require(currentPrice > 0, "Invalid price");
        address maker = storageContract.positionCore1(positionId).makerAddress;
        address tokenA = ISSListing(listingAddress).tokenA();
        uint256 totalMargin = storageContract.makerTokenMargin(maker, tokenA);
        uint256 leverageAmount = uint256(price1.leverage) * margin1.initialMargin;
        uint256 baseValue = (margin1.taxedMargin + totalMargin + leverageAmount) / currentPrice;
        return baseValue > margin2.initialLoan ? baseValue - margin2.initialLoan : 0;
    }

    // Computes payout for short positions
    function _computePayoutShort(
        uint256 positionId,
        address listingAddress,
        address tokenA,
        ICSStorage storageContract
    ) internal view returns (uint256) {
        ICSStorage.MarginParams1 memory margin1 = storageContract.marginParams1(positionId);
        ICSStorage.PriceParams1 memory price1 = storageContract.priceParams1(positionId);
        uint256 currentPrice = normalizePrice(tokenA, ISSListing(listingAddress).prices(listingAddress));
        require(currentPrice > 0, "Invalid price");
        address maker = storageContract.positionCore1(positionId).makerAddress;
        address tokenB = ISSListing(listingAddress).tokenB();
        uint256 totalMargin = storageContract.makerTokenMargin(maker, tokenB);
        uint256 priceDiff = price1.priceAtEntry > currentPrice ? price1.priceAtEntry - currentPrice : 0;
        uint256 profit = priceDiff * margin1.initialMargin * uint256(price1.leverage);
        return profit + (margin1.taxedMargin + totalMargin) * currentPrice / DECIMAL_PRECISION;
    }

    // Executes payout update to listing contract
    function _executePayoutUpdate(
        uint256 positionId,
        address listingAddress,
        uint256 payout,
        uint8 positionType,
        address maker,
        address token
    ) internal {
        ISSListing.PayoutUpdate[] memory updates = new ISSListing.PayoutUpdate[](1);
        updates[0] = ISSListing.PayoutUpdate({
            payoutType: positionType,
            recipient: maker,
            required: denormalizeAmount(token, payout)
        });
        ISSListing(listingAddress).ssUpdate(address(this), updates);
    }

    // Helper to parse and validate entry price range
    function _parsePriceParams(
        EntryContext memory context
    ) internal view returns (uint256 currentPrice, uint256 minPrice, uint256 maxPrice) {
        (currentPrice, minPrice, maxPrice,) = _parseEntryPriceInternal(
            normalizePrice(context.token, context.minEntryPrice),
            normalizePrice(context.token, context.maxEntryPrice),
            context.listingAddress
        );
    }

    // Helper to calculate fee and taxed margin
    function _calcFeeAndMargin(
        EntryContext memory context
    ) internal view returns (uint256 fee, uint256 taxedMargin, uint256 leverageAmount) {
        fee = computeFee(context.initialMargin, context.leverage);
        taxedMargin = normalizeAmount(context.token, context.initialMargin) - fee;
        leverageAmount = normalizeAmount(context.token, context.initialMargin) * uint256(context.leverage);
    }

    // Helper to update maker margin
    function _updateMakerMargin(
        EntryContext memory context,
        uint256 taxedMargin,
        uint256 excessMargin,
        address marginToken,
        ICSStorage storageContract
    ) internal {
        uint256 transferAmount = taxedMargin + normalizeAmount(context.token, context.excessMargin);
        string memory makerMarginParams = string(abi.encodePacked(
            toString(context.maker), "-", toString(marginToken), "-", storageContract.makerTokenMargin(context.maker, marginToken) + transferAmount
        ));
        storageContract.CSUpdate(
            0, // positionId (not updated)
            "", // coreParams (not updated)
            "", // priceParams (not updated)
            "", // marginParams (not updated)
            "", // exitAndInterestParams (not updated)
            makerMarginParams, // Update maker margin
            "", // positionArrayParams (not updated)
            "" // historicalInterestParams (not updated)
        );
    }

    // Prepares long position entry
    function prepEnterLong(
        EntryContext memory context,
        ICSStorage storageContract
    ) internal returns (PrepPosition memory params) {
        // Parse price parameters
        (uint256 currentPrice, uint256 minPrice, uint256 maxPrice) = _parsePriceParams(context);

        // Calculate fee, taxed margin, and leverage amount
        (params.fee, params.taxedMargin, params.leverageAmount) = _calcFeeAndMargin(context);

        // Update maker margin
        address tokenA = ISSListing(context.listingAddress).tokenA();
        _updateMakerMargin(context, params.taxedMargin, context.excessMargin, tokenA, storageContract);

        // Calculate initial loan and liquidation price
        (params.initialLoan, params.liquidationPrice) = _computeLoanAndLiquidationLong(
            params.leverageAmount,
            minPrice,
            context.maker,
            tokenA,
            storageContract
        );

        // Check liquidity limit
        _checkLiquidityLimitLong(context.listingAddress, params.initialLoan, context.leverage);

        // Transfer margin to execution driver
        _transferMarginToListing(
            tokenA,
            context.listingAddress,
            context.maker,
            params.taxedMargin,
            normalizeAmount(context.token, context.excessMargin),
            params.fee,
            0
        );

        return params;
    }

    // Prepares short position entry
    function prepEnterShort(
        EntryContext memory context,
        ICSStorage storageContract
    ) internal returns (PrepPosition memory params) {
        // Parse price parameters
        (uint256 currentPrice, uint256 minPrice, uint256 maxPrice) = _parsePriceParams(context);

        // Calculate fee, taxed margin, and leverage amount
        (params.fee, params.taxedMargin, params.leverageAmount) = _calcFeeAndMargin(context);

        // Update maker margin
        address tokenB = ISSListing(context.listingAddress).tokenB();
        _updateMakerMargin(context, params.taxedMargin, context.excessMargin, tokenB, storageContract);

        // Calculate initial loan and liquidation price
        (params.initialLoan, params.liquidationPrice) = _computeLoanAndLiquidationShort(
            params.leverageAmount,
            minPrice,
            context.maker,
            tokenB,
            storageContract
        );

        // Check liquidity limit
        _checkLiquidityLimitShort(context.listingAddress, params.initialLoan, context.leverage);

        // Transfer margin to execution driver
        _transferMarginToListing(
            tokenB,
            context.listingAddress,
            context.maker,
            params.taxedMargin,
            normalizeAmount(context.token, context.excessMargin),
            params.fee,
            1
        );

        return params;
    }
}