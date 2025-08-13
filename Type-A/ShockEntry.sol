// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version 0.0.81: Fixed stack too deep in _executeEntryHopNative
// - Refactored _executeEntryHopNative into helper functions (do x64) to split parameter handling
// - Added _validateNativeParams, _transferNativeTokens, _initNativeHop, _executeNativeMultihop, _continueNativeHop
// - Previous changes: Fixed stack too deep in _executeEntryHopToken, added HopExecutionData struct
// - Verified no typos, no SafeERC20, no virtuals/overrides, try-catch used

import "./imports/ReentrancyGuard.sol";

// Interface for IERC20
interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
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
    function getHopOrderDetails(uint256 hopId) external view returns (uint256 pending, uint256 filled, uint8 status, uint256 amountSent, address recipient);
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
    address public multiStorage;
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

    struct HopContext {
        address maker;
        uint256 hopId;
        address startToken;
        uint256 totalAmount;
        bool isCrossDriver;
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

    struct HopExecutionData {
        address hopMaker;
        uint256 entryHopId;
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

    // Transfers and approves ERC20 tokens, returns actual amount received
    function _transferAndApproveTokens(address hopMaker, address startToken, uint256 totalAmount) private returns (uint256) {
        IERC20 token = IERC20(startToken);
        uint256 balanceBefore = token.balanceOf(address(this));
        if (!token.transferFrom(hopMaker, address(this), totalAmount)) revert("Token transfer failed");
        uint256 balanceAfter = token.balanceOf(address(this));
        uint256 actualAmount = balanceAfter - balanceBefore;
        if (!token.approve(multiInitializer, actualAmount)) revert("Token approval failed");
        return actualAmount;
    }

    // Transfers native tokens, returns actual amount received
    function _transferNative(address hopMaker, uint256 totalAmount) private returns (uint256) {
        if (msg.value != totalAmount) revert("Incorrect native token amount");
        uint256 balanceBefore = address(this).balance - msg.value;
        (bool success, ) = multiInitializer.call{value: totalAmount}("");
        if (!success) revert("Native token transfer failed");
        uint256 balanceAfter = address(this).balance;
        return balanceAfter - balanceBefore;
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
            (,,uint8 status,,) = IMultiController(multiController).getHopOrderDetails(entryHopId);
            if (status == 2) margin.status = 2; // Completed
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

    // Validates hop parameters for native hop
    function _validateNativeParams(address hopMaker, HopParams memory hopParams, PositionParams memory posParams, bool isCrossDriver) private view {
        if (hopMaker == address(0)) revert("Invalid maker address");
        if (multiInitializer == address(0)) revert("MultiInitializer not set");
        if (multiController == address(0)) revert("MultiController not set");
        if (multiStorage == address(0)) revert("MultiStorage not set");
        if (isCrossDriver && (ccsEntryDriver == address(0) || ccsExecutionDriver == address(0))) revert("Cross drivers not set");
        if (!isCrossDriver && (cisEntryDriver == address(0) || cisExecutionDriver == address(0))) revert("Isolated drivers not set");
        _validatePositionToken(posParams.listingAddress, hopParams.endToken, posParams.positionType);
    }

    // Transfers native tokens for hop
    function _transferNativeTokens(address hopMaker, uint256 totalAmount) private returns (uint256) {
        return _transferNative(hopMaker, totalAmount);
    }

    // Initializes native hop context
    function _initNativeHop(address hopMaker, uint256 actualAmount, bool isCrossDriver) private returns (HopExecutionData memory) {
        uint256 entryHopId = hopCount;
        _initHopContext(hopMaker, entryHopId, address(0), actualAmount, isCrossDriver);
        return HopExecutionData({
            hopMaker: hopMaker,
            entryHopId: entryHopId,
            totalAmount: actualAmount,
            isCrossDriver: isCrossDriver
        });
    }

    // Executes native multihop
    function _executeNativeMultihop(HopExecutionData memory execData, HopParams memory hopParams, PositionParams memory posParams) private returns (uint256) {
        uint256 entryHopId = _executeMultihop(hopContexts[execData.entryHopId], hopParams, posParams);
        userHops[execData.hopMaker].push(entryHopId);
        return entryHopId;
    }

    // Continues native hop execution
    function _continueNativeHop(HopExecutionData memory execData, HopParams memory hopParams) private {
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
            emit EntryHopCancelled(execData.entryHopId, 0, reason);
        }
        _attemptContinuation(execData.entryHopId, execData.isCrossDriver, hopParams.maxIterations);
        emit EntryHopStarted(execData.hopMaker, execData.entryHopId, execData.entryHopId, execData.isCrossDriver);
    }

    // Validates hop parameters
    function _validateHopParams(address hopMaker, HopParams memory hopParams, PositionParams memory posParams, bool isCrossDriver) private view {
        if (hopMaker == address(0)) revert("Invalid maker address");
        if (multiInitializer == address(0)) revert("MultiInitializer not set");
        if (multiController == address(0)) revert("MultiController not set");
        if (multiStorage == address(0)) revert("MultiStorage not set");
        if (isCrossDriver && (ccsEntryDriver == address(0) || ccsExecutionDriver == address(0))) revert("Cross drivers not set");
        if (!isCrossDriver && (cisEntryDriver == address(0) || cisExecutionDriver == address(0))) revert("Isolated drivers not set");
        _validatePositionToken(posParams.listingAddress, hopParams.endToken, posParams.positionType);
    }

    // Transfers and approves tokens for hop
    function _transferTokens(address hopMaker, address startToken, uint256 totalAmount) private returns (uint256) {
        return _transferAndApproveTokens(hopMaker, startToken, totalAmount);
    }

    // Initializes hop context and storage
    function _initHop(address hopMaker, address startToken, uint256 actualAmount, bool isCrossDriver) private returns (HopExecutionData memory) {
        uint256 entryHopId = hopCount;
        _initHopContext(hopMaker, entryHopId, startToken, actualAmount, isCrossDriver);
        return HopExecutionData({
            hopMaker: hopMaker,
            entryHopId: entryHopId,
            totalAmount: actualAmount,
            isCrossDriver: isCrossDriver
        });
    }

    // Executes multihop and stores hop data
    function _executeHop(HopExecutionData memory execData, HopParams memory hopParams, PositionParams memory posParams) private returns (uint256) {
        uint256 entryHopId = _executeMultihop(hopContexts[execData.entryHopId], hopParams, posParams);
        userHops[execData.hopMaker].push(entryHopId);
        return entryHopId;
    }

    // Initiates multihop via MultiInitializer and continues execution
    function _continueHop(HopExecutionData memory execData, HopParams memory hopParams) private {
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
            emit EntryHopCancelled(execData.entryHopId, 0, reason);
        }
        _attemptContinuation(execData.entryHopId, execData.isCrossDriver, hopParams.maxIterations);
        emit EntryHopStarted(execData.hopMaker, execData.entryHopId, execData.entryHopId, execData.isCrossDriver);
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
                    (,,uint8 status,,) = IMultiController(multiController).getHopOrderDetails(entryHopId);
                    if (status == 2) margin.status = 2; // Completed
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

    // Attempts to globally continue stalled hops without maker restriction
    function _executeEntryStalls(uint256 maxIterations, bool isCrossDriver) private {
        if (multiStorage == address(0)) revert("MultiStorage not set");
        uint256[] memory totalHopsList = IMultiStorage(multiStorage).totalHops();
        uint256 processed = 0;
        for (uint256 i = 0; i < totalHopsList.length && processed < maxIterations; i++) {
            uint256 entryHopId = totalHopsList[i];
            EntryHopMargin storage margin = entryHopsMargin[entryHopId];
            EntryHopParams storage params = entryHopsParams[entryHopId];
            if (margin.status == 1 && params.isCrossDriver == isCrossDriver) {
                try IMultiController(multiController).continueHop(entryHopId, maxIterations) {
                    (,,uint8 status,,) = IMultiController(multiController).getHopOrderDetails(entryHopId);
                    if (status == 2) margin.status = 2; // Completed
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
        _validateHopParams(hopMaker, hopParams, posParams, isCrossDriver);
        uint256 totalAmount = posParams.initialMargin + posParams.excessMargin;
        uint256 actualAmount = _transferTokens(hopMaker, hopParams.startToken, totalAmount);
        HopExecutionData memory execData = _initHop(hopMaker, hopParams.startToken, actualAmount, isCrossDriver);
        uint256 entryHopId = _executeHop(execData, hopParams, posParams);
        _continueHop(execData, hopParams);
    }

    // Executes native token entry hop
    function _executeEntryHopNative(address hopMaker, HopParams memory hopParams, PositionParams memory posParams, bool isCrossDriver, uint256 maxIterations) private {
        _validateNativeParams(hopMaker, hopParams, posParams, isCrossDriver);
        uint256 totalAmount = posParams.initialMargin + posParams.excessMargin;
        uint256 actualAmount = _transferNativeTokens(hopMaker, totalAmount);
        HopExecutionData memory execData = _initNativeHop(hopMaker, actualAmount, isCrossDriver);
        uint256 entryHopId = _executeNativeMultihop(execData, hopParams, posParams);
        _continueNativeHop(execData, hopParams);
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

    function setMultiStorage(address _multiStorage) external onlyOwner {
        if (_multiStorage == address(0)) revert("Invalid MultiStorage address");
        multiStorage = _multiStorage;
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

    function executeEntryStalls(uint256 maxIterations, bool isCrossDriver) external nonReentrant {
        _executeEntryStalls(maxIterations, isCrossDriver);
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

    function multiStorageView() external view returns (address) {
        return multiStorage;
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