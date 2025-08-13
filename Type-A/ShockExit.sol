// SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version 0.0.74: Updated to use MultiInitializer array params
// - Replaced individual listing params with listingAddresses array
// - Added tokenPath for start and end tokens
// - Refactored _executeHop to reduce size while maintaining stack depth mitigations
// - Previous changes: Fixed TypeError in _validateHopParams
// - Verified no typos, no SafeERC20, no virtuals/overrides, try-catch used

import "./imports/ReentrancyGuard.sol";

// IERC20 interface for token operations
interface IERC20 {
    function decimals() external view returns (uint8);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

// Interface for MultiInitializer contract
interface IMultiInitializer {
    struct HopPrepState {
        uint256 numListings;
        address[] listingAddresses;
        uint256[] impactPricePercents;
        uint256 hopId;
        uint256[] indices;
        bool[] isBuy;
        address[] tokenPath;
    }
    function hopToken(address[] memory listingAddresses, uint256 impactPercent, address[] memory tokenPath, uint8 settleType, uint256 maxIterations) external returns (uint256);
    function hopNative(address[] memory listingAddresses, uint256 impactPercent, address[] memory tokenPath, uint8 settleType, uint256 maxIterations) external payable returns (uint256);
    function multiStorage() external view returns (address);
}

// Interface for MultiController contract
interface IMultiController {
    struct HopOrderDetails {
        uint256 pending;
        uint256 filled;
        uint8 status;
        uint256 amountSent;
        address recipient;
    }
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
    function continueHop(uint256 hopId, uint256 maxIterations) external;
    function getHopOrderDetails(uint256 hopId) external view returns (HopOrderDetails memory);
    function getHopDetails(uint256 hopId) external view returns (StalledHop memory);
}

// Interface for MultiStorage contract
interface IMultiStorage {
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
    function hopID(uint256 hopId) external view returns (StalledHop memory);
    function hopsByAddress(address user) external view returns (uint256[] memory);
    function totalHops() external view returns (uint256[] memory);
    function nextHopId() external view returns (uint256);
}

// Interface for ICCSExitDriver contract
interface ICCSExitDriver {
    function drift(uint256 positionId, address maker) external;
}

// Interface for ICISExitDriver contract
interface ICISExitDriver {
    function drift(uint256 positionId, address maker) external;
}

// Interface for CCSLiquidationDriver contract
interface ICCSLiquidationDriver {
    function executeExits(address listingAddress, uint256 maxIterations) external;
}

// Interface for CISLiquidationDriver contract
interface ICISLiquidationDriver {
    function executeExits(address listingAddress, uint256 maxIterations) external;
}

// Interface for ICCListingTemplate contract
interface ICCListingTemplate {
    struct LongPayoutStruct {
        address makerAddress;
        address recipientAddress;
        uint256 required;
        uint256 filled;
        uint256 orderId;
        uint8 status;
    }
    struct ShortPayoutStruct {
        address makerAddress;
        address recipientAddress;
        uint256 amount;
        uint256 filled;
        uint256 orderId;
        uint8 status;
    }
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
    function getNextOrderId() external view returns (uint256);
    function getLongPayout(uint256 orderId) external view returns (LongPayoutStruct memory);
    function getShortPayout(uint256 orderId) external view returns (ShortPayoutStruct memory);
    function settleLongLiquid(address listingAddress, uint256 maxIterations) external;
    function settleShortLiquid(address listingAddress, uint256 maxIterations) external;
    function settleLongPayouts(address listingAddress, uint256 maxIterations) external;
    function settleShortPayouts(address listingAddress, uint256 maxIterations) external;
}

// ShockExit contract for closing positions and initiating multi-hop swaps
contract ShockExit is ReentrancyGuard {
    uint256 public constant DECIMAL_PRECISION = 1e18;

    address public ccsExitDriver;
    address public cisExitDriver;
    address public ccsLiquidationDriver;
    address public cisLiquidationDriver;
    address public multiInitializer;
    address public multiController;
    address public multiStorage;
    uint256 public hopCount;
    mapping(address => uint256[]) public userHops;
    mapping(uint256 => ExitHopCore) public exitHopsCore;
    mapping(uint256 => ExitHopTokens) public exitHopsTokens;
    mapping(uint256 => ExitHopStatus) public exitHopsStatus;

    struct ExitHopCore {
        address maker;
        uint256 multihopId;
        uint256 positionId;
        address listingAddress;
    }

    struct ExitHopTokens {
        address startToken;
        address endToken;
        uint256 payoutOrderId;
        uint256 actualAmount;
    }

    struct ExitHopStatus {
        uint8 positionType;
        uint8 settleType;
        uint8 status;
        bool isCrossDriver;
    }

    struct HopParams {
        address[] listingAddresses;
        address[] tokenPath;
        uint256 impactPercent;
        uint8 settleType;
        uint256 maxIterations;
    }

    struct PositionParams {
        address listingAddress;
        uint256 positionId;
        uint8 positionType;
    }

    struct ExitHopData {
        uint256 exitHopId;
        bool payoutSettled;
        uint256 multihopId;
        address listingAddress;
        uint256 actualAmount;
    }

    struct MultihopData {
        uint256 multihopId;
        uint256 actualAmount;
        uint8 status;
    }

    struct HopExecutionData {
        address hopMaker;
        uint256 exitHopId;
        uint256 actualAmount;
        bool isCrossDriver;
    }

    event ExitHopStarted(address indexed maker, uint256 indexed exitHopId, uint256 multihopId, bool isCrossDriver);
    event ExitHopCompleted(address indexed maker, uint256 indexed exitHopId);
    event ExitHopCancelled(address indexed maker, uint256 indexed exitHopId);
    event ErrorLogged(string reason);

    constructor() {}

    function setMultiStorage(address _multiStorage) external onlyOwner {
        if (_multiStorage == address(0)) {
            emit ErrorLogged("MultiStorage address cannot be zero");
            revert("MultiStorage address cannot be zero");
        }
        multiStorage = _multiStorage;
    }

    function setMultiInitializer(address _multiInitializer) external onlyOwner {
        if (_multiInitializer == address(0)) {
            emit ErrorLogged("MultiInitializer address cannot be zero");
            revert("MultiInitializer address cannot be zero");
        }
        multiInitializer = _multiInitializer;
    }

    function setMultiController(address _multiController) external onlyOwner {
        if (_multiController == address(0)) {
            emit ErrorLogged("MultiController address cannot be zero");
            revert("MultiController address cannot be zero");
        }
        multiController = _multiController;
    }

    function setCCSExitDriver(address _ccsExitDriver) external onlyOwner {
        if (_ccsExitDriver == address(0)) {
            emit ErrorLogged("CCSExitDriver address cannot be zero");
            revert("CCSExitDriver address cannot be zero");
        }
        ccsExitDriver = _ccsExitDriver;
    }

    function setCISExitDriver(address _cisExitDriver) external onlyOwner {
        if (_cisExitDriver == address(0)) {
            emit ErrorLogged("CISExitDriver address cannot be zero");
            revert("CISExitDriver address cannot be zero");
        }
        cisExitDriver = _cisExitDriver;
    }

    function setCCSLiquidationDriver(address _ccsLiquidationDriver) external onlyOwner {
        if (_ccsLiquidationDriver == address(0)) {
            emit ErrorLogged("CCSLiquidationDriver address cannot be zero");
            revert("CCSLiquidationDriver address cannot be zero");
        }
        ccsLiquidationDriver = _ccsLiquidationDriver;
    }

    function setCISLiquidationDriver(address _cisLiquidationDriver) external onlyOwner {
        if (_cisLiquidationDriver == address(0)) {
            emit ErrorLogged("CISLiquidationDriver address cannot be zero");
            revert("CISLiquidationDriver address cannot be zero");
        }
        cisLiquidationDriver = _cisLiquidationDriver;
    }

    function crossExitHopToken(
        address[] memory listingAddresses,
        uint256 impactPercent,
        address[] memory tokenPath,
        uint8 settleType,
        uint256 maxIterations,
        address listingAddress,
        uint256[2] memory positionParams,
        address maker
    ) external nonReentrant {
        if (multiInitializer == address(0)) {
            emit ErrorLogged("MultiInitializer not set");
            revert("MultiInitializer not set");
        }
        if (ccsExitDriver == address(0)) {
            emit ErrorLogged("CCSExitDriver not set");
            revert("CCSExitDriver not set");
        }
        if (ccsLiquidationDriver == address(0)) {
            emit ErrorLogged("CCSLiquidationDriver not set");
            revert("CCSLiquidationDriver not set");
        }
        if (multiStorage == address(0)) {
            emit ErrorLogged("MultiStorage not set");
            revert("MultiStorage not set");
        }
        if (listingAddresses.length > 4) {
            emit ErrorLogged("Too many listings, maximum 4");
            revert("Too many listings, maximum 4");
        }
        if (settleType > 1) {
            emit ErrorLogged("Invalid settle type, must be 0 or 1");
            revert("Invalid settle type, must be 0 or 1");
        }
        if (maxIterations == 0) {
            emit ErrorLogged("Max iterations cannot be zero");
            revert("Max iterations cannot be zero");
        }
        if (positionParams[1] > 1) {
            emit ErrorLogged("Invalid position type, must be 0 or 1");
            revert("Invalid position type, must be 0 or 1");
        }
        if (tokenPath.length != 2) {
            emit ErrorLogged("Token path must contain start and end token");
            revert("Token path must contain start and end token");
        }

        address hopMaker = maker == address(0) ? msg.sender : maker;
        HopParams memory hopParams = HopParams({
            listingAddresses: listingAddresses,
            tokenPath: tokenPath,
            impactPercent: impactPercent,
            settleType: settleType,
            maxIterations: maxIterations
        });
        PositionParams memory posParams = PositionParams({
            listingAddress: listingAddress,
            positionId: positionParams[0],
            positionType: uint8(positionParams[1])
        });

        _executeExitHop(hopMaker, hopParams, posParams, true, false);
    }

    function crossExitHopNative(
        address[] memory listingAddresses,
        uint256 impactPercent,
        address[] memory tokenPath,
        uint8 settleType,
        uint256 maxIterations,
        address listingAddress,
        uint256[2] memory positionParams,
        address maker
    ) external payable nonReentrant {
        if (multiInitializer == address(0)) {
            emit ErrorLogged("MultiInitializer not set");
            revert("MultiInitializer not set");
        }
        if (ccsExitDriver == address(0)) {
            emit ErrorLogged("CCSExitDriver not set");
            revert("CCSExitDriver not set");
        }
        if (ccsLiquidationDriver == address(0)) {
            emit ErrorLogged("CCSLiquidationDriver not set");
            revert("CCSLiquidationDriver not set");
        }
        if (multiStorage == address(0)) {
            emit ErrorLogged("MultiStorage not set");
            revert("MultiStorage not set");
        }
        if (listingAddresses.length > 4) {
            emit ErrorLogged("Too many listings, maximum 4");
            revert("Too many listings, maximum 4");
        }
        if (settleType > 1) {
            emit ErrorLogged("Invalid settle type, must be 0 or 1");
            revert("Invalid settle type, must be 0 or 1");
        }
        if (maxIterations == 0) {
            emit ErrorLogged("Max iterations cannot be zero");
            revert("Max iterations cannot be zero");
        }
        if (positionParams[1] > 1) {
            emit ErrorLogged("Invalid position type, must be 0 or 1");
            revert("Invalid position type, must be 0 or 1");
        }
        if (msg.value == 0) {
            emit ErrorLogged("Native amount cannot be zero");
            revert("Native amount cannot be zero");
        }
        if (tokenPath.length != 2) {
            emit ErrorLogged("Token path must contain start and end token");
            revert("Token path must contain start and end token");
        }

        address hopMaker = maker == address(0) ? msg.sender : maker;
        HopParams memory hopParams = HopParams({
            listingAddresses: listingAddresses,
            tokenPath: tokenPath,
            impactPercent: impactPercent,
            settleType: settleType,
            maxIterations: maxIterations
        });
        PositionParams memory posParams = PositionParams({
            listingAddress: listingAddress,
            positionId: positionParams[0],
            positionType: uint8(positionParams[1])
        });

        _executeExitHop(hopMaker, hopParams, posParams, true, true);
    }

    function isolatedExitHopToken(
        address[] memory listingAddresses,
        uint256 impactPercent,
        address[] memory tokenPath,
        uint8 settleType,
        uint256 maxIterations,
        address listingAddress,
        uint256[2] memory positionParams,
        address maker
    ) external nonReentrant {
        if (multiInitializer == address(0)) {
            emit ErrorLogged("MultiInitializer not set");
            revert("MultiInitializer not set");
        }
        if (cisExitDriver == address(0)) {
            emit ErrorLogged("CISExitDriver not set");
            revert("CISExitDriver not set");
        }
        if (cisLiquidationDriver == address(0)) {
            emit ErrorLogged("CISLiquidationDriver not set");
            revert("CISLiquidationDriver not set");
        }
        if (multiStorage == address(0)) {
            emit ErrorLogged("MultiStorage not set");
            revert("MultiStorage not set");
        }
        if (listingAddresses.length > 4) {
            emit ErrorLogged("Too many listings, maximum 4");
            revert("Too many listings, maximum 4");
        }
        if (settleType > 1) {
            emit ErrorLogged("Invalid settle type, must be 0 or 1");
            revert("Invalid settle type, must be 0 or 1");
        }
        if (maxIterations == 0) {
            emit ErrorLogged("Max iterations cannot be zero");
            revert("Max iterations cannot be zero");
        }
        if (positionParams[1] > 1) {
            emit ErrorLogged("Invalid position type, must be 0 or 1");
            revert("Invalid position type, must be 0 or 1");
        }
        if (tokenPath.length != 2) {
            emit ErrorLogged("Token path must contain start and end token");
            revert("Token path must contain start and end token");
        }

        address hopMaker = maker == address(0) ? msg.sender : maker;
        HopParams memory hopParams = HopParams({
            listingAddresses: listingAddresses,
            tokenPath: tokenPath,
            impactPercent: impactPercent,
            settleType: settleType,
            maxIterations: maxIterations
        });
        PositionParams memory posParams = PositionParams({
            listingAddress: listingAddress,
            positionId: positionParams[0],
            positionType: uint8(positionParams[1])
        });

        _executeExitHop(hopMaker, hopParams, posParams, false, false);
    }

    function isolatedExitHopNative(
        address[] memory listingAddresses,
        uint256 impactPercent,
        address[] memory tokenPath,
        uint8 settleType,
        uint256 maxIterations,
        address listingAddress,
        uint256[2] memory positionParams,
        address maker
    ) external payable nonReentrant {
        if (multiInitializer == address(0)) {
            emit ErrorLogged("MultiInitializer not set");
            revert("MultiInitializer not set");
        }
        if (cisExitDriver == address(0)) {
            emit ErrorLogged("CISExitDriver not set");
            revert("CISExitDriver not set");
        }
        if (cisLiquidationDriver == address(0)) {
            emit ErrorLogged("CISLiquidationDriver not set");
            revert("CISLiquidationDriver not set");
        }
        if (multiStorage == address(0)) {
            emit ErrorLogged("MultiStorage not set");
            revert("MultiStorage not set");
        }
        if (listingAddresses.length > 4) {
            emit ErrorLogged("Too many listings, maximum 4");
            revert("Too many listings, maximum 4");
        }
        if (settleType > 1) {
            emit ErrorLogged("Invalid settle type, must be 0 or 1");
            revert("Invalid settle type, must be 0 or 1");
        }
        if (maxIterations == 0) {
            emit ErrorLogged("Max iterations cannot be zero");
            revert("Max iterations cannot be zero");
        }
        if (positionParams[1] > 1) {
            emit ErrorLogged("Invalid position type, must be 0 or 1");
            revert("Invalid position type, must be 0 or 1");
        }
        if (msg.value == 0) {
            emit ErrorLogged("Native amount cannot be zero");
            revert("Native amount cannot be zero");
        }
        if (tokenPath.length != 2) {
            emit ErrorLogged("Token path must contain start and end token");
            revert("Token path must contain start and end token");
        }

        address hopMaker = maker == address(0) ? msg.sender : maker;
        HopParams memory hopParams = HopParams({
            listingAddresses: listingAddresses,
            tokenPath: tokenPath,
            impactPercent: impactPercent,
            settleType: settleType,
            maxIterations: maxIterations
        });
        PositionParams memory posParams = PositionParams({
            listingAddress: listingAddress,
            positionId: positionParams[0],
            positionType: uint8(positionParams[1])
        });

        _executeExitHop(hopMaker, hopParams, posParams, false, true);
    }

    function _validateHopParams(address hopMaker, HopParams memory hopParams, ExitHopCore memory coreParams, bool isCrossDriver) private {
        if (hopMaker == address(0)) {
            emit ErrorLogged("Invalid maker address");
            revert("Invalid maker address");
        }
        if (multiInitializer == address(0)) {
            emit ErrorLogged("MultiInitializer not set");
            revert("MultiInitializer not set");
        }
        if (multiController == address(0)) {
            emit ErrorLogged("MultiController not set");
            revert("MultiController not set");
        }
        if (multiStorage == address(0)) {
            emit ErrorLogged("MultiStorage not set");
            revert("MultiStorage not set");
        }
        if (isCrossDriver && (ccsExitDriver == address(0) || ccsLiquidationDriver == address(0))) {
            emit ErrorLogged("Cross drivers not set");
            revert("Cross drivers not set");
        }
        if (!isCrossDriver && (cisExitDriver == address(0) || cisLiquidationDriver == address(0))) {
            emit ErrorLogged("Isolated drivers not set");
            revert("Isolated drivers not set");
        }
        if (coreParams.listingAddress == address(0)) {
            emit ErrorLogged("Invalid listing address");
            revert("Invalid listing address");
        }
        if (hopParams.tokenPath.length != 2) {
            emit ErrorLogged("Token path must contain start and end token");
            revert("Token path must contain start and end token");
        }
    }

    function _transferHopTokens(address hopMaker, address startToken, uint256 totalAmount, bool isNative) private returns (uint256) {
        if (isNative) {
            if (msg.value != totalAmount) {
                emit ErrorLogged("Incorrect native token amount");
                revert("Incorrect native token amount");
            }
            (bool success, ) = multiInitializer.call{value: totalAmount}("");
            if (!success) {
                emit ErrorLogged("Native token transfer failed");
                revert("Native token transfer failed");
            }
            return totalAmount;
        } else {
            IERC20 token = IERC20(startToken);
            uint256 balanceBefore = token.balanceOf(address(this));
            if (!token.transferFrom(hopMaker, address(this), totalAmount)) {
                emit ErrorLogged("Token transfer failed");
                revert("Token transfer failed");
            }
            uint256 balanceAfter = token.balanceOf(address(this));
            uint256 actualAmount = balanceAfter - balanceBefore;
            if (!token.approve(multiInitializer, actualAmount)) {
                emit ErrorLogged("Token approval failed");
                revert("Token approval failed");
            }
            return actualAmount;
        }
    }

    function _initHop(address hopMaker, address startToken, uint256 actualAmount, bool isCrossDriver) private returns (HopExecutionData memory) {
        uint256 exitHopId = hopCount;
        return HopExecutionData({
            hopMaker: hopMaker,
            exitHopId: exitHopId,
            actualAmount: actualAmount,
            isCrossDriver: isCrossDriver
        });
    }

    function _executeHop(HopExecutionData memory execData, HopParams memory hopParams) private returns (uint256) {
        if (execData.isCrossDriver) {
            return IMultiInitializer(multiInitializer).hopToken(
                hopParams.listingAddresses,
                hopParams.impactPercent,
                hopParams.tokenPath,
                hopParams.settleType,
                hopParams.maxIterations
            );
        } else {
            return IMultiInitializer(multiInitializer).hopNative(
                hopParams.listingAddresses,
                hopParams.impactPercent,
                hopParams.tokenPath,
                hopParams.settleType,
                hopParams.maxIterations
            );
        }
    }

    function _continueHop(HopExecutionData memory execData, HopParams memory hopParams) private {
        try IMultiController(multiController).continueHop(execData.exitHopId, hopParams.maxIterations) {} catch Error(string memory reason) {
            exitHopsStatus[execData.exitHopId].status = 3;
            emit ErrorLogged(string(abi.encodePacked("Continue hop failed: ", reason)));
            emit ExitHopCancelled(execData.hopMaker, execData.exitHopId);
        }
    }

    function _initCrossHopNative(HopParams memory hopParams, uint256 actualAmount, address hopMaker, uint256 exitHopId) private returns (MultihopData memory) {
        HopExecutionData memory execData = _initHop(hopMaker, hopParams.tokenPath[0], actualAmount, true);
        uint256 multihopId = _executeHop(execData, hopParams);
        _continueHop(execData, hopParams);
        return MultihopData({
            multihopId: multihopId,
            actualAmount: actualAmount,
            status: exitHopsStatus[exitHopId].status
        });
    }

    function _initCrossHopToken(HopParams memory hopParams, uint256 actualAmount, address hopMaker, uint256 exitHopId) private returns (MultihopData memory) {
        HopExecutionData memory execData = _initHop(hopMaker, hopParams.tokenPath[0], actualAmount, true);
        uint256 multihopId = _executeHop(execData, hopParams);
        _continueHop(execData, hopParams);
        return MultihopData({
            multihopId: multihopId,
            actualAmount: actualAmount,
            status: exitHopsStatus[exitHopId].status
        });
    }

    function _initIsolatedHopNative(HopParams memory hopParams, uint256 actualAmount, address hopMaker, uint256 exitHopId) private returns (MultihopData memory) {
        HopExecutionData memory execData = _initHop(hopMaker, hopParams.tokenPath[0], actualAmount, false);
        uint256 multihopId = _executeHop(execData, hopParams);
        _continueHop(execData, hopParams);
        return MultihopData({
            multihopId: multihopId,
            actualAmount: actualAmount,
            status: exitHopsStatus[exitHopId].status
        });
    }

    function _initIsolatedHopToken(HopParams memory hopParams, uint256 actualAmount, address hopMaker, uint256 exitHopId) private returns (MultihopData memory) {
        HopExecutionData memory execData = _initHop(hopMaker, hopParams.tokenPath[0], actualAmount, false);
        uint256 multihopId = _executeHop(execData, hopParams);
        _continueHop(execData, hopParams);
        return MultihopData({
            multihopId: multihopId,
            actualAmount: actualAmount,
            status: exitHopsStatus[exitHopId].status
        });
    }

    function _updateHopStatus(MultihopData memory hopData, address hopMaker, uint256 exitHopId, bool isCrossDriver) private {
        if (hopData.status == 3) {
            exitHopsStatus[exitHopId].status = 3;
            return;
        }
        exitHopsCore[exitHopId].multihopId = hopData.multihopId;
        exitHopsStatus[exitHopId].status = hopData.status;
        emit ExitHopStarted(hopMaker, exitHopId, hopData.multihopId, isCrossDriver);
        IMultiController.HopOrderDetails memory details = IMultiController(multiController).getHopOrderDetails(hopData.multihopId);
        if (details.status == 2) {
            exitHopsStatus[exitHopId].status = 2;
            emit ExitHopCompleted(hopMaker, exitHopId);
        }
    }

    function _initMultihop(HopParams memory hopParams, bool isNative, address hopMaker, uint256 exitHopId) internal {
        ExitHopCore memory coreParams = exitHopsCore[exitHopId];
        _validateHopParams(hopMaker, hopParams, coreParams, exitHopsStatus[exitHopId].isCrossDriver);
        uint256 actualAmount = _transferHopTokens(hopMaker, hopParams.tokenPath[0], exitHopsTokens[exitHopId].actualAmount, isNative);
        MultihopData memory hopData;
        if (isNative && exitHopsStatus[exitHopId].isCrossDriver) {
            hopData = _initCrossHopNative(hopParams, actualAmount, hopMaker, exitHopId);
        } else if (!isNative && exitHopsStatus[exitHopId].isCrossDriver) {
            hopData = _initCrossHopToken(hopParams, actualAmount, hopMaker, exitHopId);
        } else if (isNative && !exitHopsStatus[exitHopId].isCrossDriver) {
            hopData = _initIsolatedHopNative(hopParams, actualAmount, hopMaker, exitHopId);
        } else {
            hopData = _initIsolatedHopToken(hopParams, actualAmount, hopMaker, exitHopId);
        }
        _updateHopStatus(hopData, hopMaker, exitHopId, exitHopsStatus[exitHopId].isCrossDriver);
    }

    function _executeExitHop(address hopMaker, HopParams memory hopParams, PositionParams memory posParams, bool isCrossDriver, bool isNative) internal {
        _validateHopParams(hopMaker, hopParams, ExitHopCore({
            maker: hopMaker,
            multihopId: 0,
            positionId: posParams.positionId,
            listingAddress: posParams.listingAddress
        }), isCrossDriver);

        ExitHopData memory hopData = _initExitHop(hopMaker, hopParams, posParams, isCrossDriver);
        hopData = _callDriver(hopMaker, posParams.positionId, isCrossDriver, hopData);
        if (exitHopsStatus[hopData.exitHopId].status == 3) return;

        (hopData.payoutSettled, hopData.actualAmount) = _checkPayout(hopData.exitHopId, hopData.listingAddress, posParams.positionType);
        if (!hopData.payoutSettled) {
            exitHopsStatus[hopData.exitHopId].status = 3;
            emit ErrorLogged("Payout not settled");
            emit ExitHopCancelled(hopMaker, hopData.exitHopId);
            return;
        }

        _callLiquidation(hopData.listingAddress, hopParams.maxIterations, isCrossDriver, hopMaker, hopData.exitHopId);
        if (exitHopsStatus[hopData.exitHopId].status == 3) return;

        _initMultihop(hopParams, isNative, hopMaker, hopData.exitHopId);
    }

    function _initExitHop(address hopMaker, HopParams memory hopParams, PositionParams memory posParams, bool isCrossDriver) internal returns (ExitHopData memory) {
        uint256 exitHopId = hopCount++;
        exitHopsCore[exitHopId] = ExitHopCore({
            maker: hopMaker,
            multihopId: 0,
            positionId: posParams.positionId,
            listingAddress: posParams.listingAddress
        });
        exitHopsTokens[exitHopId] = ExitHopTokens({
            startToken: hopParams.tokenPath[0],
            endToken: hopParams.tokenPath[1],
            payoutOrderId: 0,
            actualAmount: 0
        });
        exitHopsStatus[exitHopId] = ExitHopStatus({
            positionType: posParams.positionType,
            settleType: hopParams.settleType,
            status: 0,
            isCrossDriver: isCrossDriver
        });
        userHops[hopMaker].push(exitHopId);
        return ExitHopData({
            exitHopId: exitHopId,
            payoutSettled: false,
            multihopId: 0,
            listingAddress: posParams.listingAddress,
            actualAmount: 0
        });
    }

    function _callDriver(address hopMaker, uint256 positionId, bool isCrossDriver, ExitHopData memory hopData) internal returns (ExitHopData memory) {
        if (isCrossDriver) {
            ICCSExitDriver driver = ICCSExitDriver(ccsExitDriver);
            try driver.drift(positionId, hopMaker) {
                exitHopsTokens[hopData.exitHopId].payoutOrderId = ICCListingTemplate(hopData.listingAddress).getNextOrderId() - 1;
            } catch Error(string memory reason) {
                exitHopsStatus[hopData.exitHopId].status = 3;
                emit ErrorLogged(string(abi.encodePacked("CCSExitDriver drift failed: ", reason)));
                emit ExitHopCancelled(hopMaker, hopData.exitHopId);
                return hopData;
            }
        } else {
            ICISExitDriver driver = ICISExitDriver(cisExitDriver);
            try driver.drift(positionId, hopMaker) {
                exitHopsTokens[hopData.exitHopId].payoutOrderId = ICCListingTemplate(hopData.listingAddress).getNextOrderId() - 1;
            } catch Error(string memory reason) {
                exitHopsStatus[hopData.exitHopId].status = 3;
                emit ErrorLogged(string(abi.encodePacked("CISExitDriver drift failed: ", reason)));
                emit ExitHopCancelled(hopMaker, hopData.exitHopId);
                return hopData;
            }
        }
        return hopData;
    }

    function _checkPayout(uint256 exitHopId, address listingAddress, uint8 positionType) internal returns (bool, uint256) {
        ICCListingTemplate listing = ICCListingTemplate(listingAddress);
        address token = positionType == 0 ? listing.tokenB() : listing.tokenA();
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        if (positionType == 0) {
            ICCListingTemplate.LongPayoutStruct memory payout = listing.getLongPayout(exitHopsTokens[exitHopId].payoutOrderId);
            if (payout.status != 3) return (false, 0);
            listing.settleLongPayouts(listingAddress, 1);
        } else {
            ICCListingTemplate.ShortPayoutStruct memory payout = listing.getShortPayout(exitHopsTokens[exitHopId].payoutOrderId);
            if (payout.status != 3) return (false, 0);
            listing.settleShortPayouts(listingAddress, 1);
        }
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        uint256 actualAmount = balanceAfter - balanceBefore;
        exitHopsTokens[exitHopId].actualAmount = actualAmount;
        return (true, actualAmount);
    }

    function _callLiquidation(address listingAddress, uint256 maxIterations, bool isCrossDriver, address hopMaker, uint256 exitHopId) internal {
        if (isCrossDriver) {
            try ICCSLiquidationDriver(ccsLiquidationDriver).executeExits(listingAddress, maxIterations) {} catch Error(string memory reason) {
                exitHopsStatus[exitHopId].status = 3;
                emit ErrorLogged(string(abi.encodePacked("CCSLiquidationDriver executeExits failed: ", reason)));
                emit ExitHopCancelled(hopMaker, exitHopId);
            }
        } else {
            try ICISLiquidationDriver(cisLiquidationDriver).executeExits(listingAddress, maxIterations) {} catch Error(string memory reason) {
                exitHopsStatus[exitHopId].status = 3;
                emit ErrorLogged(string(abi.encodePacked("CISLiquidationDriver executeExits failed: ", reason)));
                emit ExitHopCancelled(hopMaker, exitHopId);
            }
        }
    }

    function _continueExitHops(address user, uint256 maxIterations, bool isCrossDriver) internal {
        if (multiController == address(0)) {
            emit ErrorLogged("MultiController not set");
            revert("MultiController not set");
        }
        if (multiStorage == address(0)) {
            emit ErrorLogged("MultiStorage not set");
            revert("MultiStorage not set");
        }
        if (user == address(0)) {
            emit ErrorLogged("User address cannot be zero");
            revert("User address cannot be zero");
        }
        if (maxIterations == 0) {
            emit ErrorLogged("Max iterations cannot be zero");
            revert("Max iterations cannot be zero");
        }

        uint256[] memory hopIds = userHops[user];
        uint256 processed = 0;
        IMultiController controller = IMultiController(multiController);
        for (uint256 i = 0; i < hopIds.length && processed < maxIterations; i++) {
            ExitHopStatus storage status = exitHopsStatus[hopIds[i]];
            if (status.status == 1 && status.isCrossDriver == isCrossDriver) {
                try controller.continueHop(exitHopsCore[hopIds[i]].multihopId, maxIterations) {
                    IMultiController.HopOrderDetails memory details = controller.getHopOrderDetails(exitHopsCore[hopIds[i]].multihopId);
                    if (details.status == 2) {
                        status.status = 2;
                        emit ExitHopCompleted(exitHopsCore[hopIds[i]].maker, hopIds[i]);
                    }
                    processed++;
                } catch Error(string memory reason) {
                    emit ErrorLogged(string(abi.encodePacked("Continue hop failed for hopId ", uint2str(exitHopsCore[hopIds[i]].multihopId), ": ", reason)));
                    status.status = 3;
                    emit ExitHopCancelled(exitHopsCore[hopIds[i]].maker, hopIds[i]);
                }
            }
        }
    }

    function _executeGlobalExitHops(uint256 maxIterations, bool isCrossDriver) internal {
        if (multiController == address(0)) {
            emit ErrorLogged("MultiController not set");
            revert("MultiController not set");
        }
        if (multiStorage == address(0)) {
            emit ErrorLogged("MultiStorage not set");
            revert("MultiStorage not set");
        }
        if (maxIterations == 0) {
            emit ErrorLogged("Max iterations cannot be zero");
            revert("Max iterations cannot be zero");
        }

        uint256 processed = 0;
        IMultiController controller = IMultiController(multiController);
        for (uint256 i = 0; i < hopCount && processed < maxIterations; i++) {
            ExitHopStatus storage status = exitHopsStatus[i];
            if (status.status == 1 && status.isCrossDriver == isCrossDriver) {
                try controller.continueHop(exitHopsCore[i].multihopId, maxIterations) {
                    IMultiController.HopOrderDetails memory details = controller.getHopOrderDetails(exitHopsCore[i].multihopId);
                    if (details.status == 2) {
                        status.status = 2;
                        emit ExitHopCompleted(exitHopsCore[i].maker, i);
                    }
                    processed++;
                } catch Error(string memory reason) {
                    emit ErrorLogged(string(abi.encodePacked("Global continue hop failed for hopId ", uint2str(exitHopsCore[i].multihopId), ": ", reason)));
                    status.status = 3;
                    emit ExitHopCancelled(exitHopsCore[i].maker, i);
                }
            }
        }
    }

    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 b = uint8(_i % 10) + 48;
            bstr[k] = bytes1(b);
            _i /= 10;
        }
        return string(bstr);
    }

    function _getExitHopCore(uint256 exitHopId) internal view returns (
        address maker,
        uint256 multihopId,
        uint256 positionId,
        address listingAddress
    ) {
        ExitHopCore memory core = exitHopsCore[exitHopId];
        return (
            core.maker,
            core.multihopId,
            core.positionId,
            core.listingAddress
        );
    }

    function _getExitHopTokens(uint256 exitHopId) internal view returns (
        address startToken,
        address endToken,
        uint256 payoutOrderId,
        uint256 actualAmount
    ) {
        ExitHopTokens memory tokens = exitHopsTokens[exitHopId];
        return (
            tokens.startToken,
            tokens.endToken,
            tokens.payoutOrderId,
            tokens.actualAmount
        );
    }

    function _getExitHopStatus(uint256 exitHopId) internal view returns (
        uint8 positionType,
        uint8 settleType,
        uint8 status,
        bool isCrossDriver
    ) {
        ExitHopStatus memory statusData = exitHopsStatus[exitHopId];
        return (
            statusData.positionType,
            statusData.settleType,
            statusData.status,
            statusData.isCrossDriver
        );
    }

    function getExitHopDetails(uint256 exitHopId) external view returns (
        address maker,
        uint256 multihopId,
        uint256 positionId,
        address listingAddress,
        uint8 positionType,
        uint256 payoutOrderId,
        address startToken,
        address endToken,
        uint8 settleType,
        uint8 status,
        bool isCrossDriver,
        uint256 actualAmount
    ) {
        (maker, multihopId, positionId, listingAddress) = _getExitHopCore(exitHopId);
        (startToken, endToken, payoutOrderId, actualAmount) = _getExitHopTokens(exitHopId);
        (positionType, settleType, status, isCrossDriver) = _getExitHopStatus(exitHopId);
    }

    function getUserExitHops(address user) external view returns (uint256[] memory) {
        return userHops[user];
    }

    function multiStorageView() external view returns (address) {
        return multiStorage;
    }

    function multiInitializerView() external view returns (address) {
        return multiInitializer;
    }

    function multiControllerView() external view returns (address) {
        return multiController;
    }

    function ccsExitDriverView() external view returns (address) {
        return ccsExitDriver;
    }

    function cisExitDriverView() external view returns (address) {
        return cisExitDriver;
    }

    function ccsLiquidationDriverView() external view returns (address) {
        return ccsLiquidationDriver;
    }

    function cisLiquidationDriverView() external view returns (address) {
        return cisLiquidationDriver;
    }

    function continueCrossExitHops(uint256 maxIterations) external nonReentrant {
        _continueExitHops(msg.sender, maxIterations, true);
    }

    function continueIsolatedExitHops(uint256 maxIterations) external nonReentrant {
        _continueExitHops(msg.sender, maxIterations, false);
    }

    function executeCrossExitHops(uint256 maxIterations) external nonReentrant {
        _executeGlobalExitHops(maxIterations, true);
    }

    function executeIsolatedExitHops(uint256 maxIterations) external nonReentrant {
        _executeGlobalExitHops(maxIterations, false);
    }
}