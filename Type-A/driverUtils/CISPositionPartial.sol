/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-07-20: Fixed DeclarationError in _updatePositionStorage by correcting typo from `_prepLeverageAndRiskPadsrams` to `_prepLeverageAndRiskParams` in function call; version updated to 0.0.10.
 - 2025-07-20: Fixed DeclarationError in _finalizeEntryFees by correcting typo from `eqentry.leverageVal` to `entry.leverageVal` in computeFee call; version updated to 0.0.9.
 - 2025-07-20: Fixed DeclarationError in _deductMarginAndRemoveToken by reusing existing `success` variable for SIUpdate call, removing redeclaration; version updated to 0.0.8.
 - 2025-07-20: Fixed ParserError in _prepTokenAndInterestParams by correcting return type from `returnsSandra memory)` to `returns (string memory)`; version updated to 0.0.7.
 - 2025-07-20: Refactored _updatePositionStorage into a call tree of helper functions (_prepCoreParams, _prepPriceParams, _prepMarginParams, _prepLeverageAndRiskParams, _prepTokenAndInterestParams, _computeUpdatedMargin, _executeStorageUpdate) using prep-and-execute pattern to resolve stack-too-deep error; version updated to 0.0.6.
 - 2025-07-20: Fixed DeclarationError by reusing success variable in _updatePositionStorage for staticcall and call; resolved shadowing warning by renaming destructured margin to marginData; version updated to 0.0.5.
 - 2025-07-20: Fixed tuple destructuring in _updatePositionStorage and _computePayoutLong to match 7 components returned by _getPositionByIndex, resolving TypeError; version updated to 0.0.4.
 - 2025-07-20: Added storageContract and agentAddress state variables, setAgent owner-only setter, and getAgentAddress view function to resolve undeclared identifier errors; version updated to 0.0.3.
 - 2025-07-20: Updated CISPositionPartial to use ISIStorage interface, inlining identifiers, replacing ICSStorage with SIStorage, adapting structs to PositionCoreBase, PositionCoreStatus, PriceParams, MarginParams, LeverageParams, RiskParams, and using SIUpdate; version updated to 0.0.2.
 - 2025-07-20: Created CISPositionPartial contract by adapting SSDPositionPartial.sol for isolated margin logic, integrating with CCSPositionPartial.sol's CSStorage-based storage and executionDriver margin transfers; retained pending status with priceAtEntry = 0. Version set to 0.0.1.
*/

pragma solidity ^0.8.2;

import "../imports/SafeERC20.sol";
import "../imports/ReentrancyGuard.sol";
import "../imports/Ownable.sol";

interface ISSListing {
    struct PayoutUpdate {
        uint8 payoutType;
        address recipient;
        uint256 required;
    }
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function prices(address listingAddress) external view returns (uint256);
    function liquidityAddressView(address listingAddress) external view returns (address);
    function ssUpdate(address caller, PayoutUpdate[] memory updates) external;
}

interface ISSLiquidityTemplate {
    function liquidityDetailsView(address caller) external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees);
    function addFees(address caller, bool isLong, uint256 amount) external;
}

interface ISSAgent {
    struct ListingDetails {
        address listingAddress;
        address liquidityAddress;
        address tokenA;
        address tokenB;
        uint256 listingId;
    }
    function getListing(address tokenA, address tokenB) external view returns (address);
}

contract CISPositionPartial is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant DECIMAL_PRECISION = 1e18;
    address public executionDriver;
    address public storageContract;
    address public agentAddress;
    uint256 internal positionIdCounter;
    uint256 internal historicalInterestHeight;

    // Structs from ISIStorage inlined
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

    // Temporary storage for position entry
    struct PendingEntry {
        address listingAddr;
        address tokenAddr;
        uint256 positionId;
        uint8 positionType;
        uint256 initialMargin;
        uint256 extraMargin;
        string entryPriceStr;
        address makerAddress;
        uint8 leverageVal;
        uint256 stopLoss;
        uint256 takeProfit;
        uint256 normInitMargin;
        uint256 normExtraMargin;
    }

    // Context struct to reduce stack usage
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

    // Struct for preparing position data
    struct PrepPosition {
        uint256 fee;
        uint256 taxedMargin;
        uint256 leverageAmount;
        uint256 initialLoan;
        uint256 liquidationPrice;
    }

    // Temporary storage mapping
    mapping(uint256 => PendingEntry) internal pendingEntries;

    // Constructor initializes state variables
    constructor() {
        historicalInterestHeight = uint256(1);
        positionIdCounter = uint256(0);
    }

    // Sets execution driver address
    function setExecutionDriver(address _executionDriver) external onlyOwner {
        require(_executionDriver != address(0), "Invalid execution driver address");
        executionDriver = _executionDriver;
    }

    // Sets storage contract address
    function setStorageContract(address _storageContract) external onlyOwner {
        require(_storageContract != address(0), "Invalid storage address");
        storageContract = _storageContract;
    }

    // Sets agent address
    function setAgent(address newAgentAddress) external onlyOwner {
        require(newAgentAddress != address(0), "Invalid agent address");
        agentAddress = newAgentAddress;
    }

    // Returns the execution driver address
    function getExecutionDriver() external view returns (address) {
        return executionDriver;
    }

    // Returns the agent address
    function getAgentAddress() external view returns (address) {
        return agentAddress;
    }

    // Converts uint to string for entryPriceStr
    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 temp = _i;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (_i != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + (_i % 10)));
            _i /= 10;
        }
        return string(buffer);
    }

    // Converts address to string for SIUpdate compatibility
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

    // Normalizes amount to 18 decimals
    function normalizeAmount(address token, uint256 amount) internal view returns (uint256) {
        uint8 decimals = IERC20(token).decimals();
        return amount * DECIMAL_PRECISION / (10 ** decimals);
    }

    // Denormalizes amount based on token decimals
    function denormalizeAmount(address token, uint256 amount) internal view returns (uint256) {
        uint8 decimals = IERC20(token).decimals();
        return amount * (10 ** decimals) / DECIMAL_PRECISION;
    }

    // Normalizes price to 18 decimals
    function normalizePrice(address token, uint256 price) internal view returns (uint256) {
        uint8 decimals = IERC20(token).decimals();
        if (decimals < 18) return price * (10 ** (18 - decimals));
        if (decimals > 18) return price / (10 ** (decimals - 18));
        return price;
    }

    // Prepares entry context for position creation
    function _prepareEntryContext(
        address listingAddress,
        uint256 positionId,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint8 positionType
    ) internal view returns (EntryContext memory context) {
        address token = positionType == 0 ? ISSListing(listingAddress).tokenA() : ISSListing(listingAddress).tokenB();
        (uint256 normInitMargin, uint256 normExtraMargin) = normalizeMargins(token, initialMargin, excessMargin);
        context = EntryContext({
            positionId: positionId,
            listingAddress: listingAddress,
            minEntryPrice: minEntryPrice,
            maxEntryPrice: maxEntryPrice,
            initialMargin: initialMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            positionType: positionType,
            maker: msg.sender,
            token: token
        });
        return context;
    }

    // Normalizes margin amounts
    function normalizeMargins(
        address tokenAddr,
        uint256 initMargin,
        uint256 extraMargin
    ) internal view returns (uint256 normInitMargin, uint256 normExtraMargin) {
        normInitMargin = normalizeAmount(tokenAddr, initMargin);
        normExtraMargin = normalizeAmount(tokenAddr, extraMargin);
    }

    // Validates entry context
    function _validateEntry(
        EntryContext memory context
    ) internal view returns (EntryContext memory) {
        require(context.initialMargin > 0, "Invalid margin");
        require(context.leverage >= 2 && context.leverage <= 100, "Invalid leverage");
        require(context.listingAddress != address(0), "Invalid listing");
        address tokenA = ISSListing(context.listingAddress).tokenA();
        address tokenB = ISSListing(context.listingAddress).tokenB();
        address expectedListing = ISSAgent(agentAddress).getListing(tokenA, tokenB);
        require(expectedListing == context.listingAddress, "Invalid listing");
        return context;
    }

    // Prepares entry base
    function _prepareEntryBase(
        EntryContext memory context,
        string memory entryPriceStr,
        uint256 initMargin,
        uint256 extraMargin,
        uint8 positionType
    ) internal returns (uint256 positionId) {
        positionId = positionIdCounter++;
        pendingEntries[positionId] = PendingEntry({
            listingAddr: context.listingAddress,
            tokenAddr: context.token,
            positionId: positionId,
            positionType: positionType,
            initialMargin: initMargin,
            extraMargin: extraMargin,
            entryPriceStr: entryPriceStr,
            makerAddress: context.maker,
            leverageVal: uint8(0),
            stopLoss: uint256(0),
            takeProfit: uint256(0),
            normInitMargin: normalizeAmount(context.token, initMargin),
            normExtraMargin: normalizeAmount(context.token, extraMargin)
        });
        return positionId;
    }

    // Prepares entry risk parameters
    function _prepareEntryRisk(
        uint256 positionId,
        uint8 leverage,
        uint256 stopLoss,
        uint256 takeProfit
    ) internal {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
        entry.leverageVal = leverage;
        entry.stopLoss = stopLoss;
        entry.takeProfit = takeProfit;
    }

    // Prepares entry token parameters
    function _prepareEntryToken(uint256 positionId) internal view {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
    }

    // Validates base parameters
    function _validateEntryBase(uint256 positionId) internal view {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
        require(entry.initialMargin > 0, "Invalid margin");
        require(entry.listingAddr != address(0), "Invalid listing");
        address tokenA = ISSListing(entry.listingAddr).tokenA();
        address tokenB = ISSListing(entry.listingAddr).tokenB();
        address validListing = ISSAgent(agentAddress).getListing(tokenA, tokenB);
        require(validListing == entry.listingAddr, "Invalid listing");
    }

    // Validates risk parameters
    function _validateEntryRisk(uint256 positionId) internal view {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
        require(entry.leverageVal >= 2 && entry.leverageVal <= 100, "Invalid leverage");
    }

    // Updates entry core
    function _updateEntryCore(uint256 positionId) internal {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
        string memory coreParams = string(abi.encodePacked(
            positionId, "-", toString(entry.listingAddr), "-", toString(entry.makerAddress), "-", uint256(entry.positionType)
        ));
        (bool success,) = storageContract.call(
            abi.encodeWithSignature(
                "SIUpdate(uint256,string,string,string,string,string)",
                positionId,
                coreParams,
                "",
                "",
                "",
                "",
                ""
            )
        );
        require(success, "SIUpdate core failed");
    }

    // Computes entry parameters
    function _computeEntryParams(
        uint256 positionId,
        uint256 minPrice
    ) internal view returns (PrepPosition memory params) {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
        params.fee = computeFee(entry.initialMargin, entry.leverageVal);
        params.taxedMargin = normalizeAmount(entry.tokenAddr, entry.initialMargin) - params.fee;
        params.leverageAmount = normalizeAmount(entry.tokenAddr, entry.initialMargin) * uint256(entry.leverageVal);
        uint256 marginRatio = (params.taxedMargin + entry.normExtraMargin) / params.leverageAmount;
        params.liquidationPrice = entry.positionType == 0
            ? (marginRatio < minPrice ? minPrice - marginRatio : 0)
            : minPrice + marginRatio;
        params.initialLoan = entry.positionType == 0
            ? params.leverageAmount / minPrice
            : params.leverageAmount * minPrice;
    }

    // Validates leverage limit
    function _validateLeverageLimit(
        uint256 positionId,
        uint256 initialLoan,
        uint8 leverage
    ) internal view {
        PendingEntry storage entry = pendingEntries[positionId];
        address liquidityAddr = ISSListing(entry.listingAddr).liquidityAddressView(entry.listingAddr);
        (uint256 xLiquid, uint256 yLiquid,,) = ISSLiquidityTemplate(liquidityAddr).liquidityDetailsView(address(this));
        uint256 limitPercent = 101 - uint256(leverage);
        uint256 limit = entry.positionType == 0
            ? (yLiquid * limitPercent) / 100
            : (xLiquid * limitPercent) / 100;
        require(initialLoan <= limit, "Loan exceeds liquidity limit");
    }

    // Parses entry price
    function _parseEntryPriceInternal(
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        address listingAddress
    ) internal view returns (uint256 currentPrice, uint256 minPrice, uint256 maxPrice, uint256 priceAtEntry) {
        currentPrice = ISSListing(listingAddress).prices(listingAddress);
        minPrice = minEntryPrice;
        maxPrice = maxEntryPrice;
        priceAtEntry = 0; // Always set to 0 for pending status
        return (currentPrice, minPrice, maxPrice, priceAtEntry);
    }

    // Updates entry parameters
    function _updateEntryParams(uint256 positionId) internal {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
        (uint256 currentPrice, uint256 minPrice, uint256 maxPrice, uint256 priceAtEntry) = _parseEntryPriceInternal(
            normalizePrice(entry.tokenAddr, entry.initialMargin),
            normalizePrice(entry.tokenAddr, entry.extraMargin),
            entry.listingAddr
        );
        PrepPosition memory params = _computeEntryParams(positionId, minPrice);
        _validateLeverageLimit(positionId, params.initialLoan, entry.leverageVal);
        _storeEntryParams(positionId, minPrice, maxPrice, params, entry);
    }

    // Stores entry parameters
    function _storeEntryParams(
        uint256 positionId,
        uint256 minPrice,
        uint256 maxPrice,
        PrepPosition memory params,
        PendingEntry storage entry
    ) internal {
        string memory priceParams = string(abi.encodePacked(
            normalizePrice(entry.tokenAddr, minPrice), "-",
            normalizePrice(entry.tokenAddr, maxPrice), "-",
            uint256(0), "-", // priceAtEntry set to 0
            uint256(0) // priceClose
        ));
        string memory marginParams = string(abi.encodePacked(
            entry.normInitMargin, "-",
            params.taxedMargin, "-",
            entry.normExtraMargin
        ));
        string memory leverageAndRiskParams = string(abi.encodePacked(
            uint256(entry.leverageVal), "-",
            params.leverageAmount, "-",
            params.initialLoan, "-",
            params.liquidationPrice, "-",
            normalizePrice(entry.tokenAddr, entry.stopLoss), "-",
            normalizePrice(entry.tokenAddr, entry.takeProfit)
        ));
        string memory tokenAndInterestParams = string(abi.encodePacked(
            toString(entry.tokenAddr), "-",
            params.leverageAmount, "-",
            block.timestamp
        ));
        (bool success,) = storageContract.call(
            abi.encodeWithSignature(
                "SIUpdate(uint256,string,string,string,string,string)",
                positionId,
                "",
                priceParams,
                marginParams,
                leverageAndRiskParams,
                tokenAndInterestParams,
                ""
            )
        );
        require(success, "SIUpdate params failed");
    }

    // Updates entry indexes
    function _updateEntryIndexes(uint256 positionId) internal {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
        string memory positionArrayParams = string(abi.encodePacked(
            entry.positionType == 0 ? entry.normInitMargin : uint256(0), "-",
            entry.positionType == 1 ? entry.normInitMargin : uint256(0), "-",
            block.timestamp
        ));
        (bool success,) = storageContract.call(
            abi.encodeWithSignature(
                "SIUpdate(uint256,string,string,string,string,string)",
                positionId,
                "",
                "",
                "",
                "",
                "",
                positionArrayParams
            )
        );
        require(success, "SIUpdate indexes failed");
    }

    // Finalizes entry fees
    function _finalizeEntryFees(uint256 positionId) internal returns (uint256 actualFee) {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
        actualFee = computeFee(entry.initialMargin, entry.leverageVal);
        if (actualFee > 0) {
            address liquidityAddr = ISSListing(entry.listingAddr).liquidityAddressView(entry.listingAddr);
            uint256 denormFee = denormalizeAmount(entry.tokenAddr, actualFee);
            uint256 balanceBefore = IERC20(entry.tokenAddr).balanceOf(liquidityAddr);
            IERC20(entry.tokenAddr).safeTransferFrom(entry.makerAddress, liquidityAddr, denormFee);
            uint256 balanceAfter = IERC20(entry.tokenAddr).balanceOf(liquidityAddr);
            require(balanceAfter - balanceBefore >= denormFee, "Fee transfer amount mismatch");
            ISSLiquidityTemplate(liquidityAddr).addFees(address(this), entry.positionType == 0, actualFee);
            string memory tokenAndInterestParams = string(abi.encodePacked(
                toString(entry.tokenAddr), "-",
                entry.positionType == 0 ? actualFee : uint256(0), "-",
                entry.positionType == 1 ? actualFee : uint256(0), "-",
                block.timestamp
            ));
            (bool success,) = storageContract.call(
            abi.encodeWithSignature(
                "SIUpdate(uint256,string,string,string,string,string)",
                positionId,
                "",
                "",
                "",
                "",
                tokenAndInterestParams,
                ""
            )
        );
            require(success, "SIUpdate fees failed");
            historicalInterestHeight++;
        }
        return actualFee;
    }

    // Finalizes entry margin transfer
    function _finalizeEntryTransfer(uint256 positionId, uint256 actualFee) internal returns (uint256) {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
        uint256 denormInitMargin = denormalizeAmount(entry.tokenAddr, entry.normInitMargin);
        require(denormInitMargin >= actualFee, "Fee exceeds initial margin");
        uint256 remainingMargin = denormInitMargin - actualFee;
        uint256 expectedAmount = remainingMargin + entry.extraMargin;
        uint256 balanceBefore = IERC20(entry.tokenAddr).balanceOf(executionDriver);
        IERC20(entry.tokenAddr).safeTransferFrom(entry.makerAddress, executionDriver, expectedAmount);
        uint256 balanceAfter = IERC20(entry.tokenAddr).balanceOf(executionDriver);
        require(balanceAfter - balanceBefore >= expectedAmount, "Margin transfer amount mismatch");
        return normalizeAmount(entry.tokenAddr, expectedAmount);
    }

    // Finalizes entry position
    function _finalizeEntryPosition(uint256 positionId, uint256 io) internal {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
        string memory tokenAndInterestParams = string(abi.encodePacked(
            toString(entry.tokenAddr), "-",
            entry.positionType == 0 ? io : uint256(0), "-",
            entry.positionType == 1 ? io : uint256(0), "-",
            block.timestamp
        ));
        (bool success,) = storageContract.call(
            abi.encodeWithSignature(
                "SIUpdate(uint256,string,string,string,string,string)",
                positionId,
                "",
                "",
                "",
                "",
                tokenAndInterestParams,
                ""
            )
        );
        require(success, "SIUpdate position failed");
        delete pendingEntries[positionId];
    }

    // Finalizes entry
    function _finalizeEntry(uint256 positionId) internal {
        uint256 actualFee = _finalizeEntryFees(positionId);
        uint256 io = _finalizeEntryTransfer(positionId, actualFee);
        _finalizeEntryPosition(positionId, io);
    }

    // Computes fee based on leverage and initial margin
    function computeFee(uint256 initialMargin, uint8 leverage) internal pure returns (uint256) {
        uint256 feePercent = uint256(leverage) - 1;
        return (initialMargin * feePercent * DECIMAL_PRECISION) / 100 / DECIMAL_PRECISION;
    }

    // Prepares payout and token for drift function
    function _prepDriftPayout(
        uint256 positionId,
        PositionCoreBase memory coreBase
    ) internal view returns (uint256 payout, address token) {
        if (coreBase.positionType == 0) {
            token = ISSListing(coreBase.listingAddress).tokenB();
            payout = _computePayoutLong(positionId, coreBase.listingAddress, token);
        } else {
            token = ISSListing(coreBase.listingAddress).tokenA();
            payout = _computePayoutShort(positionId, coreBase.listingAddress, token);
        }
    }

    // Prepares payout update for drift function
    function _prepDriftPayoutUpdate(
        uint256 positionId,
        PositionCoreBase memory coreBase,
        uint256 payout,
        address token
    ) internal {
        ISSListing.PayoutUpdate[] memory updates = new ISSListing.PayoutUpdate[](1);
        updates[0] = ISSListing.PayoutUpdate({
            payoutType: coreBase.positionType,
            recipient: msg.sender,
            required: denormalizeAmount(token, payout)
        });
        ISSListing(coreBase.listingAddress).ssUpdate(address(this), updates);
    }

    // Prepares core parameters for storage update
    function _prepCoreParams(
        uint256 positionId,
        PositionCoreBase memory coreBase
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(
            positionId, "-", toString(coreBase.listingAddress), "-", toString(coreBase.makerAddress), "-", uint256(coreBase.positionType)
        ));
    }

    // Prepares price parameters for storage update
    function _prepPriceParams(
        PriceParams memory price,
        address token,
        address listingAddress
    ) internal view returns (string memory) {
        return string(abi.encodePacked(
            price.priceMin, "-",
            price.priceMax, "-",
            price.priceAtEntry, "-",
            normalizePrice(token, ISSListing(listingAddress).prices(listingAddress))
        ));
    }

    // Prepares margin parameters for storage update
    function _prepMarginParams(
        MarginParams memory marginData
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(
            marginData.marginInitial, "-",
            marginData.marginTaxed, "-",
            marginData.marginExcess
        ));
    }

    // Prepares leverage and risk parameters for storage update
    function _prepLeverageAndRiskParams(
        LeverageParams memory leverage,
        RiskParams memory risk
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(
            uint256(leverage.leverageVal), "-",
            leverage.leverageAmount, "-",
            leverage.loanInitial, "-",
            risk.priceLiquidation, "-",
            risk.priceStopLoss, "-",
            risk.priceTakeProfit
        ));
    }

    // Prepares token and interest parameters for storage update
    function _prepTokenAndInterestParams(
        address token,
        uint256 leverageAmount
    ) internal view returns (string memory) {
        return string(abi.encodePacked(
            toString(token), "-",
            leverageAmount, "-",
            block.timestamp
        ));
    }

    // Computes updated margin from AggregateMarginByToken
    function _computeUpdatedMargin(
        address maker,
        address tokenA,
        address tokenB,
        uint256 taxedMargin,
        uint256 excessMargin
    ) internal view returns (uint256) {
        (bool success, bytes memory data) = storageContract.staticcall(
            abi.encodeWithSignature("AggregateMarginByToken(address,address,uint256,uint256)", tokenA, tokenB, 0, 1)
        );
        require(success, "Failed to get margin data");
        (address[] memory makers, uint256[] memory margins) = abi.decode(data, (address[], uint256[]));
        uint256 updatedMargin = 0;
        for (uint256 i = 0; i < makers.length; i++) {
            if (makers[i] == maker) {
                updatedMargin = margins[i] - (taxedMargin + excessMargin);
                break;
            }
        }
        return updatedMargin;
    }

    // Executes storage update for a specific parameter group
    function _executeStorageUpdate(
        uint256 positionId,
        string memory coreParams,
        string memory priceParams,
        string memory marginParams,
        string memory leverageAndRiskParams,
        string memory tokenAndInterestParams,
        string memory positionArrayParams
    ) internal {
        (bool success,) = storageContract.call(
            abi.encodeWithSignature(
                "SIUpdate(uint256,string,string,string,string,string)",
                positionId,
                coreParams,
                priceParams,
                marginParams,
                leverageAndRiskParams,
                tokenAndInterestParams,
                positionArrayParams
            )
        );
        require(success, "SIUpdate storage failed");
    }

    // Updates position storage for close functions
    function _updatePositionStorage(
        uint256 positionId,
        PositionCoreBase memory coreBase,
        MarginParams memory margin,
        address token
    ) internal {
        // Fetch position data
        (, , PriceParams memory price, MarginParams memory marginData, LeverageParams memory leverage, RiskParams memory risk, ) = _getPositionByIndex(positionId);

        // Prepare parameters
        string memory coreParams = _prepCoreParams(positionId, coreBase);
        string memory priceParams = _prepPriceParams(price, token, coreBase.listingAddress);
        string memory marginParams = _prepMarginParams(marginData);
        string memory leverageAndRiskParams = _prepLeverageAndRiskParams(leverage, risk);
        uint256 updatedMargin = _computeUpdatedMargin(
            coreBase.makerAddress,
            ISSListing(coreBase.listingAddress).tokenA(),
            ISSListing(coreBase.listingAddress).tokenB(),
            margin.marginTaxed,
            margin.marginExcess
        );
        string memory tokenAndInterestParams = _prepTokenAndInterestParams(token, leverage.leverageAmount);

        // Execute incremental updates
        _executeStorageUpdate(positionId, coreParams, "", "", "", "", "");
        _executeStorageUpdate(positionId, "", priceParams, "", "", "", "");
        _executeStorageUpdate(positionId, "", "", marginParams, "", "", "");
        _executeStorageUpdate(positionId, "", "", "", leverageAndRiskParams, "", "");
        _executeStorageUpdate(positionId, "", "", "", "", tokenAndInterestParams, "");
    }

    // Computes payout for long positions
    function _computePayoutLong(
        uint256 positionId,
        address listingAddress,
        address tokenB
    ) internal view returns (uint256) {
        (, , , MarginParams memory margin, LeverageParams memory leverage, , ) = _getPositionByIndex(positionId);
        uint256 currentPrice = normalizePrice(tokenB, ISSListing(listingAddress).prices(listingAddress));
        require(currentPrice > 0, "Invalid price");
        uint256 leverageAmount = uint256(leverage.leverageVal) * margin.marginInitial;
        uint256 baseValue = (margin.marginTaxed + margin.marginExcess + leverageAmount) / currentPrice;
        return baseValue > leverage.loanInitial ? baseValue - leverage.loanInitial : 0;
    }

    // Computes payout for short positions
    function _computePayoutShort(
        uint256 positionId,
        address listingAddress,
        address tokenA
    ) internal view returns (uint256) {
        (, , PriceParams memory price, MarginParams memory margin, LeverageParams memory leverage, , ) = _getPositionByIndex(positionId);
        uint256 currentPrice = normalizePrice(tokenA, ISSListing(listingAddress).prices(listingAddress));
        require(currentPrice > 0, "Invalid price");
        uint256 priceDiff = price.priceAtEntry > currentPrice ? price.priceAtEntry - currentPrice : 0;
        uint256 profit = priceDiff * margin.marginInitial * uint256(leverage.leverageVal);
        return profit + (margin.marginTaxed + margin.marginExcess) * currentPrice / DECIMAL_PRECISION;
    }

    // Deducts margin and removes token from maker's margin list
    function _deductMarginAndRemoveToken(
        address maker,
        address token,
        uint256 taxedMargin,
        uint256 excessMargin
    ) internal {
        uint256 transferAmount = taxedMargin + excessMargin;
        bool success;
        bytes memory data;
        (success, data) = storageContract.staticcall(
            abi.encodeWithSignature("AggregateMarginByToken(address,address,uint256,uint256)", token, token, 0, 1)
        );
        require(success, "Failed to get margin data");
        (address[] memory makers, uint256[] memory margins) = abi.decode(data, (address[], uint256[]));
        uint256 updatedMargin = 0;
        for (uint256 i = 0; i < makers.length; i++) {
            if (makers[i] == maker) {
                updatedMargin = margins[i] - transferAmount;
                break;
            }
        }
        string memory tokenAndInterestParams = string(abi.encodePacked(
            toString(maker), "-", toString(token), "-", updatedMargin
        ));
        (success,) = storageContract.call(
            abi.encodeWithSignature(
                "SIUpdate(uint256,string,string,string,string,string)",
                0,
                "",
                "",
                "",
                "",
                tokenAndInterestParams,
                ""
            )
        );
        require(success, "SIUpdate margin failed");
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

    // Helper function to get position data by index
    function _getPositionByIndex(uint256 positionId) internal view returns (
        PositionCoreBase memory coreBase,
        PositionCoreStatus memory coreStatus,
        PriceParams memory price,
        MarginParams memory margin,
        LeverageParams memory leverage,
        RiskParams memory risk,
        address token
    ) {
        (bool success, bytes memory data) = storageContract.staticcall(
            abi.encodeWithSignature("positionByIndex(uint256)", positionId)
        );
        require(success, "Failed to get position data");
        (coreBase, coreStatus, price, margin, leverage, risk, token) = abi.decode(
            data,
            (PositionCoreBase, PositionCoreStatus, PriceParams, MarginParams, LeverageParams, RiskParams, address)
        );
    }
}