// SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version 0.0.64: Resolved stack too deep in getExitHopDetails
// - Split getExitHopDetails into helpers (_getExitHopCore, _getExitHopTokens, _getExitHopStatus)
// - Each helper retrieves <=4 variables to reduce stack usage
// - Preserved functionality from v0.0.63 (_validateInputs fix, split ExitHop, x64 refactor)
// - Verified no SafeERC20, no virtuals/overrides, adhered to style guide

import "./imports/ReentrancyGuard.sol";

// IERC20 interface for token operations
interface IERC20 {
    function decimals() external view returns (uint8);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
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
    }
    function hopToken(address, address, address, address, uint256, address, address, uint8, uint256) external returns (uint256);
    function hopNative(address, address, address, address, uint256, address, address, uint8, uint256) external payable returns (uint256);
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
    // Constant for decimal precision
    uint256 public constant DECIMAL_PRECISION = 1e18;

    // State variables
    address public ccsExitDriver; // Address of CCSExitDriver contract
    address public cisExitDriver; // Address of CISExitDriver contract
    address public ccsLiquidationDriver; // Address of CCSLiquidationDriver contract
    address public cisLiquidationDriver; // Address of CISLiquidationDriver contract
    address public multiInitializer; // Address of MultiInitializer contract
    address public multiController; // Address of MultiController contract
    address public multiStorage; // Address of MultiStorage contract
    uint256 public hopCount; // Tracks total number of exit hops
    mapping(address => uint256[]) public userHops; // Maps user to their exit hop IDs
    mapping(uint256 => ExitHopCore) public exitHopsCore; // Core hop details
    mapping(uint256 => ExitHopTokens) public exitHopsTokens; // Token-related hop details
    mapping(uint256 => ExitHopStatus) public exitHopsStatus; // Status-related hop details

    // Struct for core exit hop details
    struct ExitHopCore {
        address maker; // Hop initiator
        uint256 multihopId; // Multihopper hop ID
        uint256 positionId; // Position ID to close
        address listingAddress; // Listing for position closure
    }

    // Struct for token-related exit hop details
    struct ExitHopTokens {
        address startToken; // Token received from position closure
        address endToken; // Expected end token from multihop
        uint256 payoutOrderId; // Order ID of payout from drift
    }

    // Struct for status-related exit hop details
    struct ExitHopStatus {
        uint8 positionType; // 0 for long, 1 for short
        uint8 settleType; // 0 = market, 1 = liquid
        uint8 status; // 0 = initializing, 1 = pending, 2 = completed, 3 = cancelled
        bool isCrossDriver; // True for CCSExitDriver, false for CISExitDriver
    }

    // Struct for hop parameters
    struct HopParams {
        address[] listingAddresses;
        address startToken;
        address endToken;
        uint256 impactPercent;
        uint8 settleType;
        uint256 maxIterations;
    }

    // Struct for position parameters
    struct PositionParams {
        address listingAddress;
        uint256 positionId;
        uint8 positionType;
    }

    // Struct for internal data passing in _executeExitHop
    struct ExitHopData {
        uint256 exitHopId;
        bool payoutSettled;
        uint256 multihopId;
        address listingAddress;
    }

    // Events
    event ExitHopStarted(address indexed maker, uint256 indexed exitHopId, uint256 multihopId, bool isCrossDriver);
    event ExitHopCompleted(address indexed maker, uint256 indexed exitHopId);
    event ExitHopCancelled(address indexed maker, uint256 indexed exitHopId);
    event ErrorLogged(string reason);

    // Constructor
    constructor() {}

    // Sets MultiStorage address
    function setMultiStorage(address _multiStorage) external onlyOwner {
        if (_multiStorage == address(0)) {
            emit ErrorLogged("MultiStorage address cannot be zero");
            revert("MultiStorage address cannot be zero");
        }
        multiStorage = _multiStorage; // Updates MultiStorage address
    }

    // Sets MultiInitializer address
    function setMultiInitializer(address _multiInitializer) external onlyOwner {
        if (_multiInitializer == address(0)) {
            emit ErrorLogged("MultiInitializer address cannot be zero");
            revert("MultiInitializer address cannot be zero");
        }
        multiInitializer = _multiInitializer; // Updates MultiInitializer address
    }

    // Sets MultiController address
    function setMultiController(address _multiController) external onlyOwner {
        if (_multiController == address(0)) {
            emit ErrorLogged("MultiController address cannot be zero");
            revert("MultiController address cannot be zero");
        }
        multiController = _multiController; // Updates MultiController address
    }

    // Sets CCSExitDriver address
    function setCCSExitDriver(address _ccsExitDriver) external onlyOwner {
        if (_ccsExitDriver == address(0)) {
            emit ErrorLogged("CCSExitDriver address cannot be zero");
            revert("CCSExitDriver address cannot be zero");
        }
        ccsExitDriver = _ccsExitDriver; // Updates CCSExitDriver address
    }

    // Sets CISExitDriver address
    function setCISExitDriver(address _cisExitDriver) external onlyOwner {
        if (_cisExitDriver == address(0)) {
            emit ErrorLogged("CISExitDriver address cannot be zero");
            revert("CISExitDriver address cannot be zero");
        }
        cisExitDriver = _cisExitDriver; // Updates CISExitDriver address
    }

    // Sets CCSLiquidationDriver address
    function setCCSLiquidationDriver(address _ccsLiquidationDriver) external onlyOwner {
        if (_ccsLiquidationDriver == address(0)) {
            emit ErrorLogged("CCSLiquidationDriver address cannot be zero");
            revert("CCSLiquidationDriver address cannot be zero");
        }
        ccsLiquidationDriver = _ccsLiquidationDriver; // Updates CCSLiquidationDriver address
    }

    // Sets CISLiquidationDriver address
    function setCISLiquidationDriver(address _cisLiquidationDriver) external onlyOwner {
        if (_cisLiquidationDriver == address(0)) {
            emit ErrorLogged("CISLiquidationDriver address cannot be zero");
            revert("CISLiquidationDriver address cannot be zero");
        }
        cisLiquidationDriver = _cisLiquidationDriver; // Updates CISLiquidationDriver address
    }

    // Initiates a position closure followed by CCSExitDriver multihop (ERC20)
    function crossExitHopToken(
        address[] memory listings,
        uint256 impactPercent,
        address[2] memory tokens,
        uint8 settleType,
        uint256 maxIterations,
        address listingAddress,
        uint256[2] memory positionParams,
        address maker
    ) external nonReentrant {
        // Early validation
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
        if (listings.length > 4) {
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

        // Prepare parameters
        address hopMaker = maker == address(0) ? msg.sender : maker;
        HopParams memory hopParams = HopParams({
            listingAddresses: listings,
            startToken: tokens[0],
            endToken: tokens[1],
            impactPercent: impactPercent,
            settleType: settleType,
            maxIterations: maxIterations
        });
        PositionParams memory posParams = PositionParams({
            listingAddress: listingAddress,
            positionId: positionParams[0],
            positionType: uint8(positionParams[1])
        });

        // Execute hop
        _executeExitHop(hopMaker, hopParams, posParams, true, false);
    }

    // Initiates a position closure followed by CCSExitDriver multihop (Native)
    function crossExitHopNative(
        address[] memory listings,
        uint256 impactPercent,
        address[2] memory tokens,
        uint8 settleType,
        uint256 maxIterations,
        address listingAddress,
        uint256[2] memory positionParams,
        address maker
    ) external payable nonReentrant {
        // Early validation
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
        if (listings.length > 4) {
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

        // Prepare parameters
        address hopMaker = maker == address(0) ? msg.sender : maker;
        HopParams memory hopParams = HopParams({
            listingAddresses: listings,
            startToken: tokens[0],
            endToken: tokens[1],
            impactPercent: impactPercent,
            settleType: settleType,
            maxIterations: maxIterations
        });
        PositionParams memory posParams = PositionParams({
            listingAddress: listingAddress,
            positionId: positionParams[0],
            positionType: uint8(positionParams[1])
        });

        // Execute hop
        _executeExitHop(hopMaker, hopParams, posParams, true, true);
    }

    // Initiates a position closure followed by CISExitDriver multihop (ERC20)
    function isolatedExitHopToken(
        address[] memory listings,
        uint256 impactPercent,
        address[2] memory tokens,
        uint8 settleType,
        uint256 maxIterations,
        address listingAddress,
        uint256[2] memory positionParams,
        address maker
    ) external nonReentrant {
        // Early validation
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
        if (listings.length > 4) {
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

        // Prepare parameters
        address hopMaker = maker == address(0) ? msg.sender : maker;
        HopParams memory hopParams = HopParams({
            listingAddresses: listings,
            startToken: tokens[0],
            endToken: tokens[1],
            impactPercent: impactPercent,
            settleType: settleType,
            maxIterations: maxIterations
        });
        PositionParams memory posParams = PositionParams({
            listingAddress: listingAddress,
            positionId: positionParams[0],
            positionType: uint8(positionParams[1])
        });

        // Execute hop
        _executeExitHop(hopMaker, hopParams, posParams, false, false);
    }

    // Initiates a position closure followed by CISExitDriver multihop (Native)
    function isolatedExitHopNative(
        address[] memory listings,
        uint256 impactPercent,
        address[2] memory tokens,
        uint8 settleType,
        uint256 maxIterations,
        address listingAddress,
        uint256[2] memory positionParams,
        address maker
    ) external payable nonReentrant {
        // Early validation
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
        if (listings.length > 4) {
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

        // Prepare parameters
        address hopMaker = maker == address(0) ? msg.sender : maker;
        HopParams memory hopParams = HopParams({
            listingAddresses: listings,
            startToken: tokens[0],
            endToken: tokens[1],
            impactPercent: impactPercent,
            settleType: settleType,
            maxIterations: maxIterations
        });
        PositionParams memory posParams = PositionParams({
            listingAddress: listingAddress,
            positionId: positionParams[0],
            positionType: uint8(positionParams[1])
        });

        // Execute hop
        _executeExitHop(hopMaker, hopParams, posParams, false, true);
    }

    // Validates input parameters for exit hop
    function _validateInputs(
        address hopMaker,
        HopParams memory hopParams,
        PositionParams memory posParams
    ) internal {
        if (hopMaker == address(0)) {
            emit ErrorLogged("Hop maker cannot be zero");
            revert("Hop maker cannot be zero");
        }
        if (posParams.listingAddress == address(0)) {
            emit ErrorLogged("Listing address cannot be zero");
            revert("Listing address cannot be zero");
        }
        if (hopParams.startToken == address(0) || hopParams.endToken == address(0)) {
            emit ErrorLogged("Token addresses cannot be zero");
            revert("Token addresses cannot be zero");
        }
        for (uint256 i = 0; i < hopParams.listingAddresses.length; i++) {
            if (hopParams.listingAddresses[i] == address(0)) {
                emit ErrorLogged("Listing address at index cannot be zero");
                revert("Listing address at index cannot be zero");
            }
        }
    }

    // Initializes exit hop data
    function _initExitHop(
        address hopMaker,
        HopParams memory hopParams,
        PositionParams memory posParams,
        bool isCrossDriver
    ) internal returns (ExitHopData memory) {
        uint256 exitHopId = hopCount++;
        exitHopsCore[exitHopId] = ExitHopCore({
            maker: hopMaker,
            multihopId: 0,
            positionId: posParams.positionId,
            listingAddress: posParams.listingAddress
        });
        exitHopsTokens[exitHopId] = ExitHopTokens({
            startToken: hopParams.startToken,
            endToken: hopParams.endToken,
            payoutOrderId: 0
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
            listingAddress: posParams.listingAddress
        });
    }

    // Calls drift on the appropriate driver
    function _callDriver(
        address hopMaker,
        uint256 positionId,
        bool isCrossDriver,
        ExitHopData memory hopData
    ) internal returns (ExitHopData memory) {
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

    // Checks payout settlement
    function _checkPayout(
        uint256 exitHopId,
        address listingAddress,
        uint8 positionType
    ) internal view returns (bool) {
        ICCListingTemplate listing = ICCListingTemplate(listingAddress);
        if (positionType == 0) {
            ICCListingTemplate.LongPayoutStruct memory payout = listing.getLongPayout(exitHopsTokens[exitHopId].payoutOrderId);
            return payout.status == 3; // 3 = Filled
        } else {
            ICCListingTemplate.ShortPayoutStruct memory payout = listing.getShortPayout(exitHopsTokens[exitHopId].payoutOrderId);
            return payout.status == 3; // 3 = Filled
        }
    }

    // Calls executeExits on liquidation driver
    function _callLiquidation(
        address listingAddress,
        uint256 maxIterations,
        bool isCrossDriver,
        address hopMaker,
        uint256 exitHopId
    ) internal {
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

    // Initiates multihop
    function _initMultihop(
        HopParams memory hopParams,
        bool isNative,
        address hopMaker,
        uint256 exitHopId
    ) internal {
        IMultiInitializer initializer = IMultiInitializer(multiInitializer);
        if (isNative) {
            try initializer.hopNative{value: msg.value}(
                hopParams.listingAddresses.length > 0 ? hopParams.listingAddresses[0] : address(0),
                hopParams.listingAddresses.length > 1 ? hopParams.listingAddresses[1] : address(0),
                hopParams.listingAddresses.length > 2 ? hopParams.listingAddresses[2] : address(0),
                hopParams.listingAddresses.length > 3 ? hopParams.listingAddresses[3] : address(0),
                hopParams.impactPercent,
                hopParams.startToken,
                hopParams.endToken,
                hopParams.settleType,
                hopParams.maxIterations
            ) returns (uint256 multihopId) {
                exitHopsCore[exitHopId].multihopId = multihopId;
                exitHopsStatus[exitHopId].status = 1; // Pending
                emit ExitHopStarted(hopMaker, exitHopId, multihopId, exitHopsStatus[exitHopId].isCrossDriver);
            } catch Error(string memory reason) {
                exitHopsStatus[exitHopId].status = 3;
                emit ErrorLogged(string(abi.encodePacked("MultiInitializer hopNative failed: ", reason)));
                emit ExitHopCancelled(hopMaker, exitHopId);
            }
        } else {
            try initializer.hopToken(
                hopParams.listingAddresses.length > 0 ? hopParams.listingAddresses[0] : address(0),
                hopParams.listingAddresses.length > 1 ? hopParams.listingAddresses[1] : address(0),
                hopParams.listingAddresses.length > 2 ? hopParams.listingAddresses[2] : address(0),
                hopParams.listingAddresses.length > 3 ? hopParams.listingAddresses[3] : address(0),
                hopParams.impactPercent,
                hopParams.startToken,
                hopParams.endToken,
                hopParams.settleType,
                hopParams.maxIterations
            ) returns (uint256 multihopId) {
                exitHopsCore[exitHopId].multihopId = multihopId;
                exitHopsStatus[exitHopId].status = 1; // Pending
                emit ExitHopStarted(hopMaker, exitHopId, multihopId, exitHopsStatus[exitHopId].isCrossDriver);
            } catch Error(string memory reason) {
                exitHopsStatus[exitHopId].status = 3;
                emit ErrorLogged(string(abi.encodePacked("MultiInitializer hopToken failed: ", reason)));
                emit ExitHopCancelled(hopMaker, exitHopId);
            }
        }
    }

    // Internal function to execute exit hop
    function _executeExitHop(
        address hopMaker,
        HopParams memory hopParams,
        PositionParams memory posParams,
        bool isCrossDriver,
        bool isNative
    ) internal {
        // Validate inputs
        _validateInputs(hopMaker, hopParams, posParams);

        // Initialize hop
        ExitHopData memory hopData = _initExitHop(hopMaker, hopParams, posParams, isCrossDriver);

        // Call driver
        hopData = _callDriver(hopMaker, posParams.positionId, isCrossDriver, hopData);
        if (exitHopsStatus[hopData.exitHopId].status == 3) return;

        // Check payout
        hopData.payoutSettled = _checkPayout(hopData.exitHopId, hopData.listingAddress, posParams.positionType);
        if (!hopData.payoutSettled) {
            exitHopsStatus[hopData.exitHopId].status = 3;
            emit ErrorLogged("Payout not settled");
            emit ExitHopCancelled(hopMaker, hopData.exitHopId);
            return;
        }

        // Call liquidation
        _callLiquidation(hopData.listingAddress, hopParams.maxIterations, isCrossDriver, hopMaker, hopData.exitHopId);
        if (exitHopsStatus[hopData.exitHopId].status == 3) return;

        // Initiate multihop
        _initMultihop(hopParams, isNative, hopMaker, hopData.exitHopId);
    }

    // Continues a user's pending exit hops
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
                    if (details.status == 2) { // Completed
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

    // Iterates over all pending exit hops globally
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
                    if (details.status == 2) { // Completed
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

    // Utility function to convert uint to string
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

    // Retrieves core exit hop details
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

    // Retrieves token-related exit hop details
    function _getExitHopTokens(uint256 exitHopId) internal view returns (
        address startToken,
        address endToken,
        uint256 payoutOrderId
    ) {
        ExitHopTokens memory tokens = exitHopsTokens[exitHopId];
        return (
            tokens.startToken,
            tokens.endToken,
            tokens.payoutOrderId
        );
    }

    // Retrieves status-related exit hop details
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

    // View function to get exit hop details
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
        bool isCrossDriver
    ) {
        // Fetch core details
        (maker, multihopId, positionId, listingAddress) = _getExitHopCore(exitHopId);

        // Fetch token details
        (startToken, endToken, payoutOrderId) = _getExitHopTokens(exitHopId);

        // Fetch status details
        (positionType, settleType, status, isCrossDriver) = _getExitHopStatus(exitHopId);
    }

    // View function to get user's exit hops
    function getUserExitHops(address user) external view returns (uint256[] memory) {
        return userHops[user];
    }

    // View function to get MultiStorage address
    function multiStorageView() external view returns (address) {
        return multiStorage;
    }

    // View function to get MultiInitializer address
    function multiInitializerView() external view returns (address) {
        return multiInitializer;
    }

    // View function to get MultiController address
    function multiControllerView() external view returns (address) {
        return multiController;
    }

    // View function to get CCSExitDriver address
    function ccsExitDriverView() external view returns (address) {
        return ccsExitDriver;
    }

    // View function to get CISExitDriver address
    function cisExitDriverView() external view returns (address) {
        return cisExitDriver;
    }

    // View function to get CCSLiquidationDriver address
    function ccsLiquidationDriverView() external view returns (address) {
        return ccsLiquidationDriver;
    }

    // View function to get CISLiquidationDriver address
    function cisLiquidationDriverView() external view returns (address) {
        return cisLiquidationDriver;
    }

    // Iterates over a user's pending CrossDriver exit hops
    function continueCrossExitHops(uint256 maxIterations) external nonReentrant {
        _continueExitHops(msg.sender, maxIterations, true);
    }

    // Iterates over a user's pending IsolatedDriver exit hops
    function continueIsolatedExitHops(uint256 maxIterations) external nonReentrant {
        _continueExitHops(msg.sender, maxIterations, false);
    }

    // Iterates over all pending CrossDriver exit hops globally
    function executeCrossExitHops(uint256 maxIterations) external nonReentrant {
        _executeGlobalExitHops(maxIterations, true);
    }

    // Iterates over all pending IsolatedDriver exit hops globally
    function executeIsolatedExitHops(uint256 maxIterations) external nonReentrant {
        _executeGlobalExitHops(maxIterations, false);
    }
}