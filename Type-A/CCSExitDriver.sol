/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-08-08: Modified closeLongPosition and closeShortPosition to send payouts to msg.sender (Hyx) in drift; version set to 0.0.25.
 - 2025-08-07: Removed _prepDriftPayout and _prepDriftMargin to avoid override conflict, using CCSExitPartial.sol versions; version set to 0.0.24.
 - 2025-08-07: Refactored drift to use closeLongPosition/closeShortPosition, removed redundant _prepDriftCore, _prepDriftPayoutUpdate, _prepDriftCSUpdateParams; updated closeLongPosition/closeShortPosition for onlyHyx maker override; version set to 0.0.23.
 - 2025-08-07: Fixed TypeError by removing local PositionCore1 and PositionCore2 structs, using ICSStorage.PositionCore1 and ICSStorage.PositionCore2 directly; version set to 0.0.22.
 - 2025-08-07: Fixed DeclarationError by using this.cancelPosition, this.closeLongPosition, and this.closeShortPosition in bulk functions; version set to 0.0.21.
 - 2025-08-07: Rewrote closeAllLongs, closeAllShorts, cancelAllLongs, cancelAllShorts to use PositionsByAddressView and single-position functions; inlined ICSStorage structs and PositionsByAddressView; version set to 0.0.20.
 - 2025-08-07: Added cancelPosition, cancelAllLongs, cancelAllShorts, closeAllLongs, closeAllShorts, and events from CCSExtraDriver.sol; version set to 0.0.19.
 - 2025-08-05: Fixed TypeError by correcting ISSListing.prices calls; version set to 0.0.18.
 - 2025-08-05: Created CCSExitDriver by extracting closeLongPosition, closeShortPosition, drift, and helpers from CCSPositionDriver.sol; version set to 0.0.17.
*/

pragma solidity ^0.8.2;

import "./driverUtils/CCSExitPartial.sol";

contract CCSExitDriver is CCSExitPartial {
    ICSStorage public storageContract;
    address public agentAddress;
    address[] private hyxes;

    event PositionClosed(uint256 indexed positionId, address indexed maker, uint256 payout); // Emitted when a position is closed
    event PositionCancelled(uint256 indexed positionId, address indexed maker); // Emitted when a position is cancelled
    event AllLongsCancelled(address indexed maker, uint256 processed); // Emitted when all long positions are cancelled
    event AllShortsCancelled(address indexed maker, uint256 processed); // Emitted when all short positions are cancelled
    event AllLongsClosed(address indexed maker, uint256 processed); // Emitted when all long positions are closed
    event AllShortsClosed(address indexed maker, uint256 processed); // Emitted when all short positions are closed
    event HyxAdded(address indexed hyx); // Emitted when a Hyx is added
    event HyxRemoved(address indexed hyx); // Emitted when a Hyx is removed

    modifier onlyHyx() {
        bool isHyx = false;
        for (uint256 i = 0; i < hyxes.length; i++) {
            if (hyxes[i] == msg.sender) {
                isHyx = true;
                break;
            }
        }
        require(isHyx, "Caller is not an authorized Hyx"); // Restricts to authorized Hyx
        _;
    }

    // Constructor initializes storage contract
    constructor(address _storageContract) {
        require(_storageContract != address(0), "Invalid storage contract address"); // Validates storage
        storageContract = ICSStorage(_storageContract);
    }

    // Sets the storage contract address
    function setStorageContract(address _storageContract) external onlyOwner {
        require(_storageContract != address(0), "Invalid storage contract address"); // Validates storage
        storageContract = ICSStorage(_storageContract);
    }

    // Sets the agent address for listing validation
    function setAgent(address newAgentAddress) external onlyOwner {
        require(newAgentAddress != address(0), "Invalid agent address"); // Validates agent
        agentAddress = newAgentAddress;
    }

    // Adds a Hyx address to the authorized list
    function addHyx(address hyx) external onlyOwner {
        require(hyx != address(0), "Invalid Hyx address"); // Validates Hyx
        for (uint256 i = 0; i < hyxes.length; i++) {
            require(hyxes[i] != hyx, "Hyx already exists"); // Prevents duplicates
        }
        hyxes.push(hyx);
        emit HyxAdded(hyx);
    }

    // Removes a Hyx address from the authorized list
    function removeHyx(address hyx) external onlyOwner {
        require(hyx != address(0), "Invalid Hyx address"); // Validates Hyx
        for (uint256 i = 0; i < hyxes.length; i++) {
            if (hyxes[i] == hyx) {
                hyxes[i] = hyxes[hyxes.length - 1];
                hyxes.pop();
                emit HyxRemoved(hyx);
                return;
            }
        }
        revert("Hyx not found in authorized list");
    }

    // Returns the list of authorized Hyx addresses
    function getHyxes() external view returns (address[] memory hyxesList) {
        hyxesList = hyxes; // Returns current Hyx list
        return hyxesList;
    }

    // Cancels a single position
    function cancelPosition(uint256 positionId) external nonReentrant {
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
        require(core1.positionId == positionId, "Position ID does not exist"); // Validates position
        require(core2.status2 == 0, "Position is already closed"); // Ensures open
        require(!core2.status1, "Cannot cancel active position"); // Ensures not active
        require(core1.makerAddress == msg.sender, "Caller is not the position maker"); // Validates maker
        (address token, address listingAddress, uint256 marginAmount, uint256 denormalizedAmount, bool isValid) = _prepareCancelPosition(positionId, msg.sender, core1.positionType, storageContract);
        require(isValid, "Invalid position for cancellation"); // Ensures valid
        _updatePositionParams(positionId, storageContract);
        _updateMarginAndIndex(positionId, msg.sender, token, marginAmount, listingAddress, core1.positionType, storageContract);
        ISSListing.ListingPayoutUpdate[] memory updates = new ISSListing.ListingPayoutUpdate[](1);
        updates[0] = ISSListing.ListingPayoutUpdate({
            payoutType: core1.positionType,
            recipient: msg.sender,
            required: denormalizedAmount
        });
        try ISSListing(listingAddress).ssUpdate(updates) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Failed to update payout: ", reason)));
        }
        emit PositionCancelled(positionId, msg.sender);
    }

    // Cancels all long positions up to maxIterations
    function cancelAllLongs(uint256 maxIterations, uint256 startIndex) external nonReentrant {
        address maker = msg.sender;
        require(maker != address(0), "Maker address cannot be zero"); // Validates maker
        uint256 processed = 0;
        uint256[] memory positionIds;
        try storageContract.PositionsByAddressView(maker, startIndex, maxIterations) returns (uint256[] memory ids) {
            positionIds = ids;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Failed to fetch positions: ", reason)));
        }
        for (uint256 i = 0; i < positionIds.length && processed < maxIterations && gasleft() >= 50000; i++) {
            uint256 positionId = positionIds[i];
            ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
            ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
            if (core1.positionType != 0 || core2.status2 != 0 || core2.status1 || core1.makerAddress != maker) continue;
            this.cancelPosition(positionId);
            processed++;
        }
        emit AllLongsCancelled(maker, processed);
    }

    // Cancels all short positions up to maxIterations
    function cancelAllShorts(uint256 maxIterations, uint256 startIndex) external nonReentrant {
        address maker = msg.sender;
        require(maker != address(0), "Maker address cannot be zero"); // Validates maker
        uint256 processed = 0;
        uint256[] memory positionIds;
        try storageContract.PositionsByAddressView(maker, startIndex, maxIterations) returns (uint256[] memory ids) {
            positionIds = ids;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Failed to fetch positions: ", reason)));
        }
        for (uint256 i = 0; i < positionIds.length && processed < maxIterations && gasleft() >= 50000; i++) {
            uint256 positionId = positionIds[i];
            ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
            ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
            if (core1.positionType != 1 || core2.status2 != 0 || core2.status1 || core1.makerAddress != maker) continue;
            this.cancelPosition(positionId);
            processed++;
        }
        emit AllShortsCancelled(maker, processed);
    }

    // Closes a long position, computes payout, and updates state
    function closeLongPosition(uint256 positionId, address maker) external nonReentrant {
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
        require(core1.positionId == positionId, "Invalid position ID"); // Validates position
        require(core2.status2 == 0, "Position already closed"); // Ensures open
        require(core2.status1, "Position is not active"); // Ensures active
        bool isHyx = false;
        for (uint256 i = 0; i < hyxes.length; i++) {
            if (hyxes[i] == msg.sender) {
                isHyx = true;
                break;
            }
        }
        require(isHyx || core1.makerAddress == msg.sender, "Caller is not authorized or position maker"); // Validates caller
        require(core1.makerAddress == maker, "Maker address mismatch"); // Validates maker
        address tokenB = ISSListing(core1.listingAddress).tokenB();
        require(tokenB != address(0), "Token B address cannot be zero"); // Validates token
        uint256 payout = _computePayoutLong(positionId, core1.listingAddress, tokenB, storageContract);
        ICSStorage.MarginParams1 memory margin1 = storageContract.marginParams1(positionId);
        _deductMarginAndRemoveToken(
            core1.makerAddress,
            ISSListing(core1.listingAddress).tokenA(),
            margin1.taxedMargin,
            margin1.excessMargin,
            storageContract
        );
        _executePayoutUpdate(positionId, core1.listingAddress, payout, core1.positionType, msg.sender, tokenB);
        ICSStorage.CoreParams memory coreParams = ICSStorage.CoreParams({
            positionId: positionId,
            listingAddress: core1.listingAddress,
            makerAddress: core1.makerAddress,
            positionType: core1.positionType,
            status1: core2.status1,
            status2: 1
        });
        ICSStorage.PriceParams memory priceParams = ICSStorage.PriceParams({
            minEntryPrice: storageContract.priceParams1(positionId).minEntryPrice,
            maxEntryPrice: storageContract.priceParams1(positionId).maxEntryPrice,
            minPrice: storageContract.priceParams1(positionId).minPrice,
            priceAtEntry: storageContract.priceParams1(positionId).priceAtEntry,
            leverage: storageContract.priceParams1(positionId).leverage,
            liquidationPrice: storageContract.priceParams2(positionId).liquidationPrice
        });
        ICSStorage.MarginParams memory marginParams = ICSStorage.MarginParams({
            initialMargin: margin1.initialMargin,
            taxedMargin: margin1.taxedMargin,
            excessMargin: margin1.excessMargin,
            fee: margin1.fee,
            initialLoan: storageContract.marginParams2(positionId).initialLoan
        });
        ICSStorage.ExitAndInterestParams memory exitAndInterestParams = ICSStorage.ExitAndInterestParams({
            stopLossPrice: storageContract.exitParams(positionId).stopLossPrice,
            takeProfitPrice: storageContract.exitParams(positionId).takeProfitPrice,
            exitPrice: normalizePrice(tokenB, ISSListing(core1.listingAddress).prices(0)),
            leverageAmount: storageContract.openInterest(positionId).leverageAmount,
            timestamp: storageContract.openInterest(positionId).timestamp
        });
        ICSStorage.MakerMarginParams memory makerMarginParams = ICSStorage.MakerMarginParams({
            token: ISSListing(core1.listingAddress).tokenA(),
            maker: core1.makerAddress,
            marginToken: ISSListing(core1.listingAddress).tokenA(),
            marginAmount: storageContract.makerTokenMargin(core1.makerAddress, ISSListing(core1.listingAddress).tokenA())
        });
        try storageContract.CSUpdate(
            positionId,
            coreParams,
            priceParams,
            marginParams,
            exitAndInterestParams,
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
        try storageContract.removePositionIndex(positionId, core1.positionType, core1.listingAddress) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Failed to remove position index: ", reason)));
        }
        emit PositionClosed(positionId, core1.makerAddress, payout);
    }

    // Closes a short position, computes payout, and updates state
    function closeShortPosition(uint256 positionId, address maker) external nonReentrant {
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
        require(core1.positionId == positionId, "Invalid position ID"); // Validates position
        require(core2.status2 == 0, "Position already closed"); // Ensures open
        require(core2.status1, "Position is not active"); // Ensures active
        bool isHyx = false;
        for (uint256 i = 0; i < hyxes.length; i++) {
            if (hyxes[i] == msg.sender) {
                isHyx = true;
                break;
            }
        }
        require(isHyx || core1.makerAddress == msg.sender, "Caller is not authorized or position maker"); // Validates caller
        require(core1.makerAddress == maker, "Maker address mismatch"); // Validates maker
        address tokenA = ISSListing(core1.listingAddress).tokenA();
        require(tokenA != address(0), "Token A address cannot be zero"); // Validates token
        uint256 payout = _computePayoutShort(positionId, core1.listingAddress, tokenA, storageContract);
        ICSStorage.MarginParams1 memory margin1 = storageContract.marginParams1(positionId);
        _deductMarginAndRemoveToken(
            core1.makerAddress,
            ISSListing(core1.listingAddress).tokenB(),
            margin1.taxedMargin,
            margin1.excessMargin,
            storageContract
        );
        _executePayoutUpdate(positionId, core1.listingAddress, payout, core1.positionType, msg.sender, tokenA);
        ICSStorage.CoreParams memory coreParams = ICSStorage.CoreParams({
            positionId: positionId,
            listingAddress: core1.listingAddress,
            makerAddress: core1.makerAddress,
            positionType: core1.positionType,
            status1: core2.status1,
            status2: 1
        });
        ICSStorage.PriceParams memory priceParams = ICSStorage.PriceParams({
            minEntryPrice: storageContract.priceParams1(positionId).minEntryPrice,
            maxEntryPrice: storageContract.priceParams1(positionId).maxEntryPrice,
            minPrice: storageContract.priceParams1(positionId).minPrice,
            priceAtEntry: storageContract.priceParams1(positionId).priceAtEntry,
            leverage: storageContract.priceParams1(positionId).leverage,
            liquidationPrice: storageContract.priceParams2(positionId).liquidationPrice
        });
        ICSStorage.MarginParams memory marginParams = ICSStorage.MarginParams({
            initialMargin: margin1.initialMargin,
            taxedMargin: margin1.taxedMargin,
            excessMargin: margin1.excessMargin,
            fee: margin1.fee,
            initialLoan: storageContract.marginParams2(positionId).initialLoan
        });
        ICSStorage.ExitAndInterestParams memory exitAndInterestParams = ICSStorage.ExitAndInterestParams({
            stopLossPrice: storageContract.exitParams(positionId).stopLossPrice,
            takeProfitPrice: storageContract.exitParams(positionId).takeProfitPrice,
            exitPrice: normalizePrice(tokenA, ISSListing(core1.listingAddress).prices(0)),
            leverageAmount: storageContract.openInterest(positionId).leverageAmount,
            timestamp: storageContract.openInterest(positionId).timestamp
        });
        ICSStorage.MakerMarginParams memory makerMarginParams = ICSStorage.MakerMarginParams({
            token: ISSListing(core1.listingAddress).tokenB(),
            maker: core1.makerAddress,
            marginToken: ISSListing(core1.listingAddress).tokenB(),
            marginAmount: storageContract.makerTokenMargin(core1.makerAddress, ISSListing(core1.listingAddress).tokenB())
        });
        try storageContract.CSUpdate(
            positionId,
            coreParams,
            priceParams,
            marginParams,
            exitAndInterestParams,
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
        try storageContract.removePositionIndex(positionId, core1.positionType, core1.listingAddress) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Failed to remove position index: ", reason)));
        }
        emit PositionClosed(positionId, core1.makerAddress, payout);
    }

    // Closes all long positions up to maxIterations
    function closeAllLongs(uint256 maxIterations, uint256 startIndex) external nonReentrant {
        address maker = msg.sender;
        require(maker != address(0), "Maker address cannot be zero"); // Validates maker
        uint256 processed = 0;
        uint256[] memory positionIds;
        try storageContract.PositionsByAddressView(maker, startIndex, maxIterations) returns (uint256[] memory ids) {
            positionIds = ids;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Failed to fetch positions: ", reason)));
        }
        for (uint256 i = 0; i < positionIds.length && processed < maxIterations && gasleft() >= 50000; i++) {
            uint256 positionId = positionIds[i];
            ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
            ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
            if (core1.positionType != 0 || core2.status2 != 0 || !core2.status1 || core1.makerAddress != maker) continue;
            this.closeLongPosition(positionId, maker);
            processed++;
        }
        emit AllLongsClosed(maker, processed);
    }

    // Closes all short positions up to maxIterations
    function closeAllShorts(uint256 maxIterations, uint256 startIndex) external nonReentrant {
        address maker = msg.sender;
        require(maker != address(0), "Maker address cannot be zero"); // Validates maker
        uint256 processed = 0;
        uint256[] memory positionIds;
        try storageContract.PositionsByAddressView(maker, startIndex, maxIterations) returns (uint256[] memory ids) {
            positionIds = ids;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Failed to fetch positions: ", reason)));
        }
        for (uint256 i = 0; i < positionIds.length && processed < maxIterations && gasleft() >= 50000; i++) {
            uint256 positionId = positionIds[i];
            ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
            ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
            if (core1.positionType != 1 || core2.status2 != 0 || !core2.status1 || core1.makerAddress != maker) continue;
            this.closeShortPosition(positionId, maker);
            processed++;
        }
        emit AllShortsClosed(maker, processed);
    }

    // Executes drift for a position, restricted to authorized Hyx contracts
    function drift(uint256 positionId, address maker) external nonReentrant onlyHyx {
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        require(core1.positionId == positionId, "Invalid position ID"); // Validates position
        require(core1.makerAddress == maker, "Maker address mismatch"); // Validates maker
        if (core1.positionType == 0) {
            this.closeLongPosition(positionId, maker);
        } else {
            this.closeShortPosition(positionId, maker);
        }
    }
}