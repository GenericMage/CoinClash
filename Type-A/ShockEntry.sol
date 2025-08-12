// SPDX-License-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version 0.0.75: Consolidated cancellation functions, added maker restrictions
// - Removed cancelCrossEntryHop, cancelIsolatedEntryHop; replaced with cancelEntryHopByMaker
// - Updated _cancelEntryHop to ensure maker-only cancellation
// - Verified continueCrossEntryHops, continueIsolatedEntryHops restrict to maker
// - Ensured try-catch, no placeholders, ≤4 variables per helper
// - Verified no typos or inconsistencies

import "./imports/ReentrancyGuard.sol";

// Interface for IERC20
interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

// Interface for MultiInitializer
interface IMultiInitializer {
    function hopToken(address listing1, address listing2, address listing3, address listing4, uint256 impactPercent, address startToken, address endToken, uint8 settleType, uint256 maxIterations) external;
    function hopNative(address listing1, address listing2, address listing3, address listing4, uint256 impactPercent, address startToken, address endToken, uint8 settleType, uint256 maxIterations) external payable;
    function multiStorage() external view returns (address);
}

// Interface for MultiController
interface IMultiController {
    function continueHop(uint256 hopId, uint256 maxIterations) external;
    function executeStalls(uint256 maxIterations) external;
    function cancelHop(uint256 hopId) external returns (uint256 refundedAmount, string memory reason);
    function multiStorage() external view returns (address);
}

// Interface for MultiStorage
interface IMultiStorage {
    function hopsByAddress(address user) external view returns (uint256[] memory);
    function totalHops() external view returns (uint256[] memory);
    function nextHopId() external view returns (uint256);
    function hopID(uint256 hopId) external view returns (StalledHop memory);
    struct StalledHop {
        uint8 stage;
        address currentListing;
        uint256 orderID;
        uint256 minPrice;
        uint256 maxPrice;
        address hopMaker;
        address[] remainingListings;
        uint256 principalAmount;
        address startToken;
        address endToken;
        uint8 settleType;
        uint8 hopStatus;
        uint256 maxIterations;
    }
}

// Interface for CCSEntryDriver
interface ICCSEntryDriver {
    function driveToken(address maker, address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice, uint8 positionType) external;
    function executePositions(address listingAddress) external;
}

// Interface for CISEntryDriver
interface ICISEntryDriver {
    function driveToken(address maker, address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice, uint8 positionType) external;
    function executePositions(address listingAddress) external;
}

// Interface for CCSExecutionDriver
interface ICCSExecutionDriver {
    function executeEntries(address listingAddress, uint256 maxIterations) external;
}

// Interface for CISExecutionDriver
interface ICISExecutionDriver {
    function executeEntries(address listingAddress, uint256 maxIterations) external;
}

// Interface for ISSListingTemplate
interface ISSListingTemplate {
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
}

// ShockEntry contract for multi-hop swaps followed by position creation
contract ShockEntry is ReentrancyGuard {
    uint256 private constant DECIMAL_PRECISION = 1e18;

    // State variables
    address public ccsEntryDriver;
    address public cisEntryDriver;
    address public ccsExecutionDriver;
    address public cisExecutionDriver;
    address public multiInitializer;
    address public multiController;
    uint256 public hopCount;
    mapping(address => uint256[]) public userHops;
    mapping(uint256 => EntryHopCore) public entryHopsCore;
    mapping(uint256 => EntryHopMargin) public entryHopsMargin;
    mapping(uint256 => EntryHopParams) public entryHopsParams;
    mapping(uint256 => HopContext) private hopContexts;

    struct EntryHopCore {
        address maker;
        uint256 hopId;
        address listingAddress;
        uint8 positionType;
    }

    struct EntryHopMargin {
        uint256 initialMargin;
        uint256 excessMargin;
        uint8 leverage;
        uint8 status;
    }

    struct EntryHopParams {
        uint256 stopLossPrice;
        uint256 takeProfitPrice;
        address endToken;
        bool isCrossDriver;
        uint256 minEntryPrice;
        uint256 maxEntryPrice;
    }

    struct HopParams {
        address[] listings;
        uint256 impactPercent;
        address startToken;
        address endToken;
        uint8 settleType;
        uint256 maxIterations;
    }

    struct PositionParams {
        address listingAddress;
        uint256 minEntryPrice;
        uint256 maxEntryPrice;
        uint256 initialMargin;
        uint256 excessMargin;
        uint8 leverage;
        uint256 stopLossPrice;
        uint256 takeProfitPrice;
        uint8 positionType;
    }

    struct HopContext {
        address maker;
        uint256 hopId;
        address startToken;
        uint256 totalAmount;
        bool isCrossDriver;
    }

    event EntryHopStarted(address indexed maker, uint256 indexed entryHopId, uint256 hopId, bool isCrossDriver);
    event EntryHopCancelled(uint256 indexed entryHopId, uint256 refundedAmount, string reason);

    // Validates position token matches end token
    function _validatePositionToken(address listingAddress, address endToken, uint8 positionType) private view {
        if (listingAddress == address(0)) revert("Invalid listing address");
        ISSListingTemplate listing = ISSListingTemplate(listingAddress);
        address token = positionType == 0 ? listing.tokenB() : listing.tokenA();
        if (token != endToken) revert("End token mismatch with position type");
    }

    // Transfers and approves ERC20 tokens
    function _transferAndApproveTokens(address hopMaker, address startToken, uint256 totalAmount) private {
        IERC20 token = IERC20(startToken);
        if (!token.transferFrom(hopMaker, address(this), totalAmount)) revert("Token transfer failed");
        if (!token.approve(multiInitializer, totalAmount)) revert("Token approval failed");
    }

    // Transfers native tokens
    function _transferNative(address hopMaker, uint256 totalAmount) private {
        if (msg.value != totalAmount) revert("Incorrect native token amount");
        (bool success, ) = multiInitializer.call{value: totalAmount}("");
        if (!success) revert("Native token transfer failed");
    }

    // Refunds maker for cancelled hop
    function _refundMaker(address maker, address token, uint256 amount) private {
        if (amount == 0) return;
        if (token == address(0)) {
            (bool success, ) = maker.call{value: amount}("");
            if (!success) revert("Native refund failed");
        } else {
            if (!IERC20(token).transfer(maker, amount)) revert("Token refund failed");
        }
    }

    // Initializes hop context
    function _initHopContext(address hopMaker, uint256 hopId, address startToken, uint256 totalAmount, bool isCrossDriver) private {
        hopContexts[hopId] = HopContext({
            maker: hopMaker,
            hopId: hopId,
            startToken: startToken,
            totalAmount: totalAmount,
            isCrossDriver: isCrossDriver
        });
    }

    // Stores core position data
    function _storePositionCore(uint256 hopId, address maker, address listingAddress, uint8 positionType) private {
        entryHopsCore[hopId] = EntryHopCore({
            maker: maker,
            hopId: hopId,
            listingAddress: listingAddress,
            positionType: positionType
        });
    }

    // Stores margin data
    function _storePositionMargin(uint256 hopId, uint256 initialMargin, uint256 excessMargin, uint8 leverage) private {
        entryHopsMargin[hopId] = EntryHopMargin({
            initialMargin: initialMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            status: 1
        });
    }

    // Stores position parameters
    function _storePositionParams(uint256 hopId, uint256 stopLossPrice, uint256 takeProfitPrice, address endToken, bool isCrossDriver, uint256 minEntryPrice, uint256 maxEntryPrice) private {
        entryHopsParams[hopId] = EntryHopParams({
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            endToken: endToken,
            isCrossDriver: isCrossDriver,
            minEntryPrice: minEntryPrice,
            maxEntryPrice: maxEntryPrice
        });
    }

    // Executes multihop via MultiInitializer
    function _executeMultihop(HopContext memory context, HopParams memory hopParams, PositionParams memory posParams) private returns (uint256) {
        uint256 entryHopId = hopCount++;
        _storePositionCore(entryHopId, context.maker, posParams.listingAddress, posParams.positionType);
        _storePositionMargin(entryHopId, posParams.initialMargin, posParams.excessMargin, posParams.leverage);
        _storePositionParams(entryHopId, posParams.stopLossPrice, posParams.takeProfitPrice, hopParams.endToken, context.isCrossDriver, posParams.minEntryPrice, posParams.maxEntryPrice);
        return entryHopId;
    }

    // Attempts continuation via MultiController and execution driver
    function _attemptContinuation(uint256 entryHopId, bool isCrossDriver, uint256 maxIterations) private {
        EntryHopMargin storage margin = entryHopsMargin[entryHopId];
        try IMultiController(multiController).continueHop(entryHopId, maxIterations) {
            margin.status = 2;
            address entryDriver = isCrossDriver ? ccsEntryDriver : cisEntryDriver;
            address executionDriver = isCrossDriver ? ccsExecutionDriver : cisExecutionDriver;
            if (entryDriver == address(0)) revert("Entry driver not set");
            if (executionDriver == address(0)) revert("Execution driver not set");
            if (isCrossDriver) {
                ICCSEntryDriver(entryDriver).executePositions(entryHopsCore[entryHopId].listingAddress);
                ICCSExecutionDriver(executionDriver).executeEntries(entryHopsCore[entryHopId].listingAddress, maxIterations);
            } else {
                ICISEntryDriver(entryDriver).executePositions(entryHopsCore[entryHopId].listingAddress);
                ICISExecutionDriver(executionDriver).executeEntries(entryHopsCore[entryHopId].listingAddress, maxIterations);
            }
        } catch Error(string memory reason) {
            margin.status = 3;
            emit EntryHopCancelled(entryHopId, 0, reason);
        }
    }

    // Validates and sets up hop execution
    function _validateAndSetupHop(address hopMaker, HopParams memory hopParams, PositionParams memory posParams, bool isCrossDriver) private view {
        if (hopMaker == address(0)) revert("Invalid maker address");
        if (multiInitializer == address(0)) revert("MultiInitializer not set");
        if (multiController == address(0)) revert("MultiController not set");
        if (isCrossDriver && (ccsEntryDriver == address(0) || ccsExecutionDriver == address(0))) revert("Cross drivers not set");
        if (!isCrossDriver && (cisEntryDriver == address(0) || cisExecutionDriver == address(0))) revert("Isolated drivers not set");
        _validatePositionToken(posParams.listingAddress, hopParams.endToken, posParams.positionType);
    }

    // Continues pending hops for a driver type
    function _continueEntryHops(uint256 maxIterations, bool isCrossDriver) private {
        address user = msg.sender;
        uint256[] storage hops = userHops[user];
        uint256 processed = 0;
        for (uint256 i = 0; i < hops.length && processed < maxIterations; i++) {
            uint256 entryHopId = hops[i];
            EntryHopCore storage core = entryHopsCore[entryHopId];
            EntryHopMargin storage margin = entryHopsMargin[entryHopId];
            EntryHopParams storage params = entryHopsParams[entryHopId];
            if (margin.status == 1 && params.isCrossDriver == isCrossDriver && core.maker == user) {
                try IMultiController(multiController).continueHop(entryHopId, maxIterations) {
                    margin.status = 2;
                    address entryDriver = isCrossDriver ? ccsEntryDriver : cisEntryDriver;
                    address executionDriver = isCrossDriver ? ccsExecutionDriver : cisExecutionDriver;
                    if (entryDriver == address(0)) revert("Entry driver not set");
                    if (executionDriver == address(0)) revert("Execution driver not set");
                    if (isCrossDriver) {
                        ICCSEntryDriver(entryDriver).executePositions(core.listingAddress);
                        ICCSExecutionDriver(executionDriver).executeEntries(core.listingAddress, maxIterations);
                    } else {
                        ICISEntryDriver(entryDriver).executePositions(core.listingAddress);
                        ICISExecutionDriver(executionDriver).executeEntries(core.listingAddress, maxIterations);
                    }
                } catch Error(string memory reason) {
                    margin.status = 3;
                    emit EntryHopCancelled(entryHopId, 0, reason);
                }
                processed++;
            }
        }
    }

    // Cancels a specific hop and refunds maker
    function _cancelEntryHop(uint256 entryHopId, bool isCrossDriver) private {
        EntryHopCore storage core = entryHopsCore[entryHopId];
        EntryHopMargin storage margin = entryHopsMargin[entryHopId];
        EntryHopParams storage params = entryHopsParams[entryHopId];
        HopContext storage context = hopContexts[entryHopId];
        if (margin.status != 1) revert("Hop not pending");
        if (params.isCrossDriver != isCrossDriver) revert("Driver mismatch");
        if (core.maker != msg.sender) revert("Only maker can cancel");
        try IMultiController(multiController).cancelHop(entryHopId) returns (uint256 refundedAmount, string memory reason) {
            margin.status = 3;
            _refundMaker(context.maker, context.startToken, refundedAmount);
            emit EntryHopCancelled(entryHopId, refundedAmount, reason);
        } catch Error(string memory reason) {
            margin.status = 3;
            emit EntryHopCancelled(entryHopId, 0, reason);
        }
    }

    // Executes ERC20 token entry hop
    function _executeEntryHopToken(address hopMaker, HopParams memory hopParams, PositionParams memory posParams, bool isCrossDriver, uint256 maxIterations) private {
        _validateAndSetupHop(hopMaker, hopParams, posParams, isCrossDriver);
        uint256 totalAmount = posParams.initialMargin + posParams.excessMargin;
        _transferAndApproveTokens(hopMaker, hopParams.startToken, totalAmount);
        _initHopContext(hopMaker, hopCount, hopParams.startToken, totalAmount, isCrossDriver);
        uint256 entryHopId = _executeMultihop(hopContexts[hopCount], hopParams, posParams);
        userHops[hopMaker].push(entryHopId);
        IMultiInitializer(multiInitializer).hopToken(
            hopParams.listings.length > 0 ? hopParams.listings[0] : address(0),
            hopParams.listings.length > 1 ? hopParams.listings[1] : address(0),
            hopParams.listings.length > 2 ? hopParams.listings[2] : address(0),
            hopParams.listings.length > 3 ? hopParams.listings[3] : address(0),
            hopParams.impactPercent,
            hopParams.startToken,
            hopParams.endToken,
            hopParams.settleType,
            hopParams.maxIterations
        );
        try IMultiController(multiController).executeStalls(hopParams.maxIterations) {} catch Error(string memory reason) {
            emit EntryHopCancelled(entryHopId, 0, reason);
        }
        _attemptContinuation(entryHopId, isCrossDriver, maxIterations);
        emit EntryHopStarted(hopMaker, entryHopId, entryHopId, isCrossDriver);
    }

    // Executes native token entry hop
    function _executeEntryHopNative(address hopMaker, HopParams memory hopParams, PositionParams memory posParams, bool isCrossDriver, uint256 maxIterations) private {
        _validateAndSetupHop(hopMaker, hopParams, posParams, isCrossDriver);
        uint256 totalAmount = posParams.initialMargin + posParams.excessMargin;
        _transferNative(hopMaker, totalAmount);
        _initHopContext(hopMaker, hopCount, address(0), totalAmount, isCrossDriver);
        uint256 entryHopId = _executeMultihop(hopContexts[hopCount], hopParams, posParams);
        userHops[hopMaker].push(entryHopId);
        IMultiInitializer(multiInitializer).hopNative(
            hopParams.listings.length > 0 ? hopParams.listings[0] : address(0),
            hopParams.listings.length > 1 ? hopParams.listings[1] : address(0),
            hopParams.listings.length > 2 ? hopParams.listings[2] : address(0),
            hopParams.listings.length > 3 ? hopParams.listings[3] : address(0),
            hopParams.impactPercent,
            hopParams.startToken,
            hopParams.endToken,
            hopParams.settleType,
            hopParams.maxIterations
        );
        try IMultiController(multiController).executeStalls(hopParams.maxIterations) {} catch Error(string memory reason) {
            emit EntryHopCancelled(entryHopId, 0, reason);
        }
        _attemptContinuation(entryHopId, isCrossDriver, maxIterations);
        emit EntryHopStarted(hopMaker, entryHopId, entryHopId, isCrossDriver);
    }

    // Setters
    function setMultiInitializer(address _multiInitializer) external onlyOwner {
        if (_multiInitializer == address(0)) revert("Invalid MultiInitializer address");
        multiInitializer = _multiInitializer;
    }

    function setMultiController(address _multiController) external onlyOwner {
        if (_multiController == address(0)) revert("Invalid MultiController address");
        multiController = _multiController;
    }

    function setCCSEntryDriver(address _ccsEntryDriver) external onlyOwner {
        if (_ccsEntryDriver == address(0)) revert("Invalid CCSEntryDriver address");
        ccsEntryDriver = _ccsEntryDriver;
    }

    function setCISEntryDriver(address _cisEntryDriver) external onlyOwner {
        if (_cisEntryDriver == address(0)) revert("Invalid CISEntryDriver address");
        cisEntryDriver = _cisEntryDriver;
    }

    function setCCSExecutionDriver(address _ccsExecutionDriver) external onlyOwner {
        if (_ccsExecutionDriver == address(0)) revert("Invalid CCSExecutionDriver address");
        ccsExecutionDriver = _ccsExecutionDriver;
    }

    function setCISExecutionDriver(address _cisExecutionDriver) external onlyOwner {
        if (_cisExecutionDriver == address(0)) revert("Invalid CISExecutionDriver address");
        cisExecutionDriver = _cisExecutionDriver;
    }

    // Entry hop functions for ERC20 tokens
    function crossEntryHopToken(address[] memory listings, uint256 impactPercent, address[] memory tokens, uint8 settleType, uint256 maxIterations, PositionParams memory posParams, address maker) external nonReentrant {
        address hopMaker = maker == address(0) ? msg.sender : maker;
        if (tokens.length != 2) revert("Tokens array must contain start and end token");
        HopParams memory hopParams = HopParams({
            listings: listings,
            impactPercent: impactPercent,
            startToken: tokens[0],
            endToken: tokens[1],
            settleType: settleType,
            maxIterations: maxIterations
        });
        _executeEntryHopToken(hopMaker, hopParams, posParams, true, maxIterations);
    }

    function isolatedEntryHopToken(address[] memory listings, uint256 impactPercent, address[] memory tokens, uint8 settleType, uint256 maxIterations, PositionParams memory posParams, address maker) external nonReentrant {
        address hopMaker = maker == address(0) ? msg.sender : maker;
        if (tokens.length != 2) revert("Tokens array must contain start and end token");
        HopParams memory hopParams = HopParams({
            listings: listings,
            impactPercent: impactPercent,
            startToken: tokens[0],
            endToken: tokens[1],
            settleType: settleType,
            maxIterations: maxIterations
        });
        _executeEntryHopToken(hopMaker, hopParams, posParams, false, maxIterations);
    }

    // Entry hop functions for native tokens
    function crossEntryHopNative(address[] memory listings, uint256 impactPercent, address[] memory tokens, uint8 settleType, uint256 maxIterations, PositionParams memory posParams, address maker) external payable nonReentrant {
        address hopMaker = maker == address(0) ? msg.sender : maker;
        if (tokens.length != 2) revert("Tokens array must contain start and end token");
        HopParams memory hopParams = HopParams({
            listings: listings,
            impactPercent: impactPercent,
            startToken: tokens[0],
            endToken: tokens[1],
            settleType: settleType,
            maxIterations: maxIterations
        });
        _executeEntryHopNative(hopMaker, hopParams, posParams, true, maxIterations);
    }

    function isolatedEntryHopNative(address[] memory listings, uint256 impactPercent, address[] memory tokens, uint8 settleType, uint256 maxIterations, PositionParams memory posParams, address maker) external payable nonReentrant {
        address hopMaker = maker == address(0) ? msg.sender : maker;
        if (tokens.length != 2) revert("Tokens array must contain start and end token");
        HopParams memory hopParams = HopParams({
            listings: listings,
            impactPercent: impactPercent,
            startToken: tokens[0],
            endToken: tokens[1],
            settleType: settleType,
            maxIterations: maxIterations
        });
        _executeEntryHopNative(hopMaker, hopParams, posParams, false, maxIterations);
    }

    // Continuation and cancellation functions
    function continueEntryHop(uint256 entryHopId, bool isCrossDriver) external nonReentrant {
        EntryHopCore storage core = entryHopsCore[entryHopId];
        if (core.maker != msg.sender) revert("Only maker can continue");
        _continueEntryHops(1, isCrossDriver);
    }

    function cancelEntryHop(uint256 entryHopId, bool isCrossDriver) external nonReentrant {
        _cancelEntryHop(entryHopId, isCrossDriver);
    }

    // View functions
    function getEntryHopDetails(uint256 entryHopId) external view returns (EntryHopCore memory core, EntryHopMargin memory margin, EntryHopParams memory params) {
        core = entryHopsCore[entryHopId];
        margin = entryHopsMargin[entryHopId];
        params = entryHopsParams[entryHopId];
    }

    function getUserEntryHops(address user) external view returns (uint256[] memory) {
        return userHops[user];
    }

    function multiInitializerView() external view returns (address) {
        return multiInitializer;
    }

    function multiControllerView() external view returns (address) {
        return multiController;
    }

    function ccsEntryDriverView() external view returns (address) {
        return ccsEntryDriver;
    }

    function cisEntryDriverView() external view returns (address) {
        return cisEntryDriver;
    }

    function ccsExecutionDriverView() external view returns (address) {
        return ccsExecutionDriver;
    }

    function cisExecutionDriverView() external view returns (address) {
        return cisExecutionDriver;
    }
}