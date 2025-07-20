/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-07-20: Fixed ParserError by correcting 'giv' to 'address' in _validateAndInit function for tokenA declaration; moved executionDriver state variable, setExecutionDriver, and getExecutionDriver to CCSPositionPartial.sol to resolve DeclarationError in _transferMarginToListing. Version set to 0.0.12.
 - 2025-07-20: Added executionDriver state variable with setExecutionDriver (owner-only) and getExecutionDriver view functions; updated margin transfers in prepEnterLong and prepEnterShort to target executionDriver instead of listing contract; removed cancelPosition function and related logic as cancellation will be handled by executionDriver. Version set to 0.0.11.
 - 2025-07-19: Renamed `storageContract` parameter to `sContract` in _prepDriftCSUpdateParams, _executeDriftCSUpdate, _prepDriftPayout, and _prepDriftMargin functions to avoid shadowing the public state variable `storageContract`, resolving compiler warnings. Version set to 0.0.10.
 - 2025-07-19: Refactored _storeEntryData to address stack too deep error by splitting into dedicated internal helper functions (_prepCoreParams, _prepPriceParams, _prepMarginParams, _prepExitAndInterestParams, _prepMakerMarginParams, _prepPositionArrayParams) for each parameter group, each calling CSUpdate independently, leveraging CSStorage's incremental update capability. Version set to 0.0.9.
 - 2025-07-18: Refactored drift function to address stack too deep error by breaking it into internal helper functions (prep and execute pattern) sorted by parameter type, reducing stack usage while preserving functionality. Version set to 0.0.8.
 - 2025-07-18: Renamed all instances of "mux" to "Hyx" (array, functions, modifier, events, comments) to avoid confusion, as requested. Version set to 0.0.7.
 - 2025-07-18: Fixed TypeError in _storeEntryData by destructuring all four components from _parseEntryPriceInternal; updated to use complete ICSStorage interface from CCSPositionPartial.sol, including positionCore2. Version set to 0.0.6.
 - 2025-07-18: Fixed TypeError in _storeEntryData by explicitly destructuring tuple returned by _parseEntryPriceInternal to access priceAtEntry. Version set to 0.0.5.
 - 2025-07-18: Removed redundant ICSStorage interface, imported from CCSPositionPartial.sol, and updated onlyMux modifier to use local muxes array exclusively, removing invalid storageContract.muxes call. Version set to 0.0.4.
 - 2025-07-18: Added muxes array with addMux, removeMux, and getMuxes functions, restricted to onlyOwner, for local mux management. Version set to 0.0.3.
 - 2025-07-18: Fixed syntax error in _storeEntryData by correcting ternary operator for longIO assignment and updated ICSStorage interface to use string-based CSUpdate signature, adjusting all function calls to use hyphen-delimited strings. Version set to 0.0.2.
 - 2025-07-18: Created CCSPositionDriver contract by extracting position creation, cancellation, and closing functions from SSCrossDriver.sol and CSDPositionPartial.sol, integrating with CSStorage via CSUpdate. Version set to 0.0.1.
*/

pragma solidity ^0.8.2;

import "./driverUtils/CCSPositionPartial.sol";

contract CCSPositionDriver is CCSPositionPartial {
    // Storage contract instance
    ICSStorage public storageContract;
    address public agentAddress;

    // Array to store authorized Hyx addresses
    address[] private hyxes;

    // Events for position actions
    event PositionEntered(uint256 indexed positionId, address indexed maker, uint8 positionType);
    event PositionClosed(uint256 indexed positionId, address indexed maker, uint256 payout);
    event HyxAdded(address indexed hyx);
    event HyxRemoved(address indexed hyx);

    // Modifier to restrict functions to authorized Hyxes
    modifier onlyHyx() {
        bool isHyx = false;
        for (uint256 i = 0; i < hyxes.length; i++) {
            if (hyxes[i] == msg.sender) {
                isHyx = true;
                break;
            }
        }
        require(isHyx, "Caller is not a Hyx");
        _;
    }

    // Sets storage contract address
    function setStorageContract(address _storageContract) external onlyOwner {
        require(_storageContract != address(0), "Invalid storage address");
        storageContract = ICSStorage(_storageContract);
    }

    // Sets agent address
    function setAgent(address newAgentAddress) external onlyOwner {
        require(newAgentAddress != address(0), "Invalid agent address");
        agentAddress = newAgentAddress;
    }

    // Adds a new Hyx to the array
    function addHyx(address hyx) external onlyOwner {
        require(hyx != address(0), "Invalid Hyx address");
        for (uint256 i = 0; i < hyxes.length; i++) {
            require(hyxes[i] != hyx, "Hyx already exists");
        }
        hyxes.push(hyx);
        emit HyxAdded(hyx);
    }

    // Removes a Hyx from the array
    function removeHyx(address hyx) external onlyOwner {
        require(hyx != address(0), "Invalid Hyx address");
        for (uint256 i = 0; i < hyxes.length; i++) {
            if (hyxes[i] == hyx) {
                hyxes[i] = hyxes[hyxes.length - 1];
                hyxes.pop();
                emit HyxRemoved(hyx);
                return;
            }
        }
        revert("Hyx not found");
    }

    // Returns the list of Hyxes
    function getHyxes() external view returns (address[] memory) {
        return hyxes;
    }

    // Validates and initializes position data
    function _validateAndInit(
        address listingAddress,
        uint8 positionType
    ) internal returns (address maker, address token) {
        uint256 positionId = storageContract.positionCount() + 1;
        require(storageContract.positionCore1(positionId).positionId == 0, "Position ID exists");
        address tokenA = ISSListing(listingAddress).tokenA();
        address tokenB = ISSListing(listingAddress).tokenB();
        address expectedListing = ISSAgent(agentAddress).getListing(tokenA, tokenB);
        require(expectedListing == listingAddress, "Invalid listing");
        maker = msg.sender;
        token = positionType == 0 ? tokenA : tokenB;
        return (maker, token);
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
        context = EntryContext({
            positionId: positionId,
            listingAddress: listingAddress,
            minEntryPrice: minEntryPrice,
            maxEntryPrice: maxEntryPrice,
            initialMargin: initialMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            positionType: positionType,
            maker: address(0),
            token: address(0)
        });
        return context;
    }

    // Validates entry context
    function _validateEntry(
        EntryContext memory context
    ) internal returns (EntryContext memory) {
        require(context.initialMargin > 0, "Invalid margin");
        require(context.leverage >= 2 && context.leverage <= 100, "Invalid leverage");
        (context.maker, context.token) = _validateAndInit(context.listingAddress, context.positionType);
        return context;
    }

    // Computes entry parameters
    function _computeEntryParams(
        EntryContext memory context
    ) internal returns (PrepPosition memory params) {
        if (context.positionType == 0) {
            params = prepEnterLong(context, storageContract);
        } else {
            params = prepEnterShort(context, storageContract);
        }
        return params;
    }

    // Prepares core parameters for CSUpdate
    function _prepCoreParams(
        uint256 positionId,
        address listingAddress,
        address maker,
        uint8 positionType
    ) internal {
        string memory coreParams = string(abi.encodePacked(
            positionId, "-", listingAddress, "-", toString(maker), "-", uint256(positionType)
        ));
        storageContract.CSUpdate(
            positionId,
            coreParams,
            "", // priceParams
            "", // marginParams
            "", // exitAndInterestParams
            "", // makerMarginParams
            "", // positionArrayParams
            ""  // historicalInterestParams
        );
    }

    // Prepares price parameters for CSUpdate
    function _prepPriceParams(
        uint256 positionId,
        address token,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 liquidationPrice,
        uint8 leverage
    ) internal {
        (,, uint256 minPrice, uint256 priceAtEntry) = _parseEntryPriceInternal(
            normalizePrice(token, minEntryPrice),
            normalizePrice(token, maxEntryPrice),
            storageContract.positionCore1(positionId).listingAddress
        );
        string memory priceParams = string(abi.encodePacked(
            normalizePrice(token, minEntryPrice), "-",
            normalizePrice(token, maxEntryPrice), "-",
            minPrice, "-",
            priceAtEntry, "-",
            uint256(leverage)
        ));
        storageContract.CSUpdate(
            positionId,
            "", // coreParams
            priceParams,
            "", // marginParams
            "", // exitAndInterestParams
            "", // makerMarginParams
            "", // positionArrayParams
            ""  // historicalInterestParams
        );
    }

    // Prepares margin parameters for CSUpdate
    function _prepMarginParams(
        uint256 positionId,
        address token,
        uint256 initialMargin,
        uint256 taxedMargin,
        uint256 excessMargin,
        uint256 fee,
        uint256 initialLoan
    ) internal {
        string memory marginParams = string(abi.encodePacked(
            normalizeAmount(token, initialMargin), "-",
            taxedMargin, "-",
            normalizeAmount(token, excessMargin), "-",
            fee, "-",
            normalizeAmount(token, initialLoan)
        ));
        storageContract.CSUpdate(
            positionId,
            "", // coreParams
            "", // priceParams
            marginParams,
            "", // exitAndInterestParams
            "", // makerMarginParams
            "", // positionArrayParams
            ""  // historicalInterestParams
        );
    }

    // Prepares exit and interest parameters for CSUpdate
    function _prepExitAndInterestParams(
        uint256 positionId,
        address token,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        uint256 leverageAmount
    ) internal {
        string memory exitAndInterestParams = string(abi.encodePacked(
            normalizePrice(token, stopLossPrice), "-",
            normalizePrice(token, takeProfitPrice), "-",
            uint256(0), "-", // exitPrice
            leverageAmount, "-",
            block.timestamp
        ));
        storageContract.CSUpdate(
            positionId,
            "", // coreParams
            "", // priceParams
            "", // marginParams
            exitAndInterestParams,
            "", // makerMarginParams
            "", // positionArrayParams
            ""  // historicalInterestParams
        );
    }

    // Prepares maker margin parameters for CSUpdate
    function _prepMakerMarginParams(
        uint256 positionId,
        address maker,
        address marginToken
    ) internal {
        string memory makerMarginParams = string(abi.encodePacked(
            toString(maker), "-",
            toString(marginToken), "-",
            storageContract.makerTokenMargin(maker, marginToken)
        ));
        storageContract.CSUpdate(
            positionId,
            "", // coreParams
            "", // priceParams
            "", // marginParams
            "", // exitAndInterestParams
            makerMarginParams,
            "", // positionArrayParams
            ""  // historicalInterestParams
        );
    }

    // Prepares position array parameters for CSUpdate
    function _prepPositionArrayParams(
        uint256 positionId,
        uint8 positionType,
        uint256 leverageAmount
    ) internal {
        string memory positionArrayParams = string(abi.encodePacked(
            positionType == 0 ? leverageAmount : uint256(0), "-",
            positionType == 1 ? leverageAmount : uint256(0), "-",
            block.timestamp
        ));
        storageContract.CSUpdate(
            positionId,
            "", // coreParams
            "", // priceParams
            "", // marginParams
            "", // exitAndInterestParams
            "", // makerMarginParams
            positionArrayParams,
            ""  // historicalInterestParams
        );
    }

    // Stores entry data via multiple CSUpdate calls
    function _storeEntryData(
        EntryContext memory context,
        PrepPosition memory prep,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) internal {
        // Update core parameters
        _prepCoreParams(
            context.positionId,
            context.listingAddress,
            context.maker,
            context.positionType
        );

        // Update price parameters
        _prepPriceParams(
            context.positionId,
            context.token,
            context.minEntryPrice,
            context.maxEntryPrice,
            prep.liquidationPrice,
            context.leverage
        );

        // Update margin parameters
        _prepMarginParams(
            context.positionId,
            context.token,
            context.initialMargin,
            prep.taxedMargin,
            context.excessMargin,
            prep.fee,
            prep.initialLoan
        );

        // Update exit and interest parameters
        _prepExitAndInterestParams(
            context.positionId,
            context.token,
            stopLossPrice,
            takeProfitPrice,
            prep.leverageAmount
        );

        // Update maker margin parameters
        _prepMakerMarginParams(
            context.positionId,
            context.maker,
            context.positionType == 0 ? ISSListing(context.listingAddress).tokenA() : ISSListing(context.listingAddress).tokenB()
        );

        // Update position array parameters
        _prepPositionArrayParams(
            context.positionId,
            context.positionType,
            prep.leverageAmount
        );
    }

    // Initiates position entry
    function _initiateEntry(
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        uint8 positionType
    ) internal nonReentrant {
        uint256 positionId = storageContract.positionCount() + 1;
        EntryContext memory context = _prepareEntryContext(
            listingAddress,
            positionId,
            minEntryPrice,
            maxEntryPrice,
            initialMargin,
            excessMargin,
            leverage,
            positionType
        );
        context = _validateEntry(context);
        PrepPosition memory params = _computeEntryParams(context);
        _storeEntryData(context, params, stopLossPrice, takeProfitPrice);
        emit PositionEntered(positionId, context.maker, positionType);
    }

    // Enters a long position
    function enterLong(
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external {
        _initiateEntry(
            listingAddress,
            minEntryPrice,
            maxEntryPrice,
            initialMargin,
            excessMargin,
            leverage,
            stopLossPrice,
            takeProfitPrice,
            0
        );
    }

    // Enters a short position
    function enterShort(
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external {
        _initiateEntry(
            listingAddress,
            minEntryPrice,
            maxEntryPrice,
            initialMargin,
            excessMargin,
            leverage,
            stopLossPrice,
            takeProfitPrice,
            1
        );
    }

    // Closes a long position
    function closeLongPosition(uint256 positionId) external nonReentrant {
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
        require(core1.positionId == positionId, "Invalid position");
        require(core2.status2 == 0, "Position closed");
        require(core1.makerAddress == msg.sender, "Not maker");
        address tokenB = ISSListing(core1.listingAddress).tokenB();
        uint256 payout = _computePayoutLong(positionId, core1.listingAddress, tokenB, storageContract);
        ICSStorage.MarginParams1 memory margin1 = storageContract.marginParams1(positionId);
        _deductMarginAndRemoveToken(
            core1.makerAddress,
            ISSListing(core1.listingAddress).tokenA(),
            margin1.taxedMargin,
            margin1.excessMargin,
            storageContract
        );
        _executePayoutUpdate(positionId, core1.listingAddress, payout, core1.positionType, core1.makerAddress, tokenB);
        string memory coreParams = string(abi.encodePacked(
            positionId, "-", core1.listingAddress, "-", toString(core1.makerAddress), "-", uint256(core1.positionType)
        ));
        string memory priceParams = string(abi.encodePacked(
            storageContract.priceParams1(positionId).minEntryPrice, "-",
            storageContract.priceParams1(positionId).maxEntryPrice, "-",
            storageContract.priceParams1(positionId).minPrice, "-",
            storageContract.priceParams1(positionId).priceAtEntry, "-",
            uint256(storageContract.priceParams1(positionId).leverage)
        ));
        string memory marginParams = string(abi.encodePacked(
            margin1.initialMargin, "-",
            margin1.taxedMargin, "-",
            margin1.excessMargin, "-",
            margin1.fee, "-",
            storageContract.marginParams2(positionId).initialLoan
        ));
        string memory exitAndInterestParams = string(abi.encodePacked(
            storageContract.exitParams(positionId).stopLossPrice, "-",
            storageContract.exitParams(positionId).takeProfitPrice, "-",
            normalizePrice(tokenB, ISSListing(core1.listingAddress).prices(core1.listingAddress)), "-",
            storageContract.openInterest(positionId).leverageAmount, "-",
            storageContract.openInterest(positionId).timestamp
        ));
        string memory makerMarginParams = string(abi.encodePacked(
            toString(core1.makerAddress), "-",
            toString(ISSListing(core1.listingAddress).tokenA()), "-",
            storageContract.makerTokenMargin(core1.makerAddress, ISSListing(core1.listingAddress).tokenA())
        ));
        storageContract.CSUpdate(
            positionId,
            coreParams,
            priceParams,
            marginParams,
            exitAndInterestParams,
            makerMarginParams,
            "", // positionArrayParams
            ""  // historicalInterestParams
        );
        storageContract.removePositionIndex(positionId, core1.positionType, core1.listingAddress);
        emit PositionClosed(positionId, core1.makerAddress, payout);
    }

    // Closes a short position
    function closeShortPosition(uint256 positionId) external nonReentrant {
        ICSStorage.PositionCore1 memory core1 = storageContract.positionCore1(positionId);
        ICSStorage.PositionCore2 memory core2 = storageContract.positionCore2(positionId);
        require(core1.positionId == positionId, "Invalid position");
        require(core2.status2 == 0, "Position closed");
        require(core1.makerAddress == msg.sender, "Not maker");
        address tokenA = ISSListing(core1.listingAddress).tokenA();
        uint256 payout = _computePayoutShort(positionId, core1.listingAddress, tokenA, storageContract);
        ICSStorage.MarginParams1 memory margin1 = storageContract.marginParams1(positionId);
        _deductMarginAndRemoveToken(
            core1.makerAddress,
            ISSListing(core1.listingAddress).tokenB(),
            margin1.taxedMargin,
            margin1.excessMargin,
            storageContract
        );
        _executePayoutUpdate(positionId, core1.listingAddress, payout, core1.positionType, core1.makerAddress, tokenA);
        string memory coreParams = string(abi.encodePacked(
            positionId, "-", core1.listingAddress, "-", toString(core1.makerAddress), "-", uint256(core1.positionType)
        ));
        string memory priceParams = string(abi.encodePacked(
            storageContract.priceParams1(positionId).minEntryPrice, "-",
            storageContract.priceParams1(positionId).maxEntryPrice, "-",
            storageContract.priceParams1(positionId).minPrice, "-",
            storageContract.priceParams1(positionId).priceAtEntry, "-",
            uint256(storageContract.priceParams1(positionId).leverage)
        ));
        string memory marginParams = string(abi.encodePacked(
            margin1.initialMargin, "-",
            margin1.taxedMargin, "-",
            margin1.excessMargin, "-",
            margin1.fee, "-",
            storageContract.marginParams2(positionId).initialLoan
        ));
        string memory exitAndInterestParams = string(abi.encodePacked(
            storageContract.exitParams(positionId).stopLossPrice, "-",
            storageContract.exitParams(positionId).takeProfitPrice, "-",
            normalizePrice(tokenA, ISSListing(core1.listingAddress).prices(core1.listingAddress)), "-",
            storageContract.openInterest(positionId).leverageAmount, "-",
            storageContract.openInterest(positionId).timestamp
        ));
        string memory makerMarginParams = string(abi.encodePacked(
            toString(core1.makerAddress), "-",
            toString(ISSListing(core1.listingAddress).tokenB()), "-",
            storageContract.makerTokenMargin(core1.makerAddress, ISSListing(core1.listingAddress).tokenB())
        ));
        storageContract.CSUpdate(
            positionId,
            coreParams,
            priceParams,
            marginParams,
            exitAndInterestParams,
            makerMarginParams,
            "", // positionArrayParams
            ""  // historicalInterestParams
        );
        storageContract.removePositionIndex(positionId, core1.positionType, core1.listingAddress);
        emit PositionClosed(positionId, core1.makerAddress, payout);
    }

    // Allows any address to create positions on behalf of a maker
    function drive(
        address maker,
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        uint8 positionType
    ) external nonReentrant {
        require(maker != address(0), "Invalid maker address");
        require(positionType <= 1, "Invalid position type");
        uint256 positionId = storageContract.positionCount() + 1;
        EntryContext memory context = _prepareEntryContext(
            listingAddress,
            positionId,
            minEntryPrice,
            maxEntryPrice,
            initialMargin,
            excessMargin,
            leverage,
            positionType
        );
        context.maker = maker; // Override maker from msg.sender to provided maker
        context = _validateEntry(context);
        PrepPosition memory params = _computeEntryParams(context);
        _storeEntryData(context, params, stopLossPrice, takeProfitPrice);
        emit PositionEntered(positionId, maker, positionType);
    }

    // Prepares core parameters for drift function
    function _prepDriftCore(
        uint256 positionId,
        address maker
    ) internal view returns (ICSStorage.PositionCore1 memory core1, ICSStorage.PositionCore2 memory core2) {
        core1 = storageContract.positionCore1(positionId);
        core2 = storageContract.positionCore2(positionId);
        require(core1.positionId == positionId, "Invalid position");
        require(core2.status2 == 0, "Position closed");
        require(core1.makerAddress == maker, "Maker mismatch");
    }

    // Prepares payout and token for drift function
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

    // Prepares margin parameters for drift function
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

    // Prepares payout update for drift function
    function _prepDriftPayoutUpdate(
        uint256 positionId,
        ICSStorage.PositionCore1 memory core1,
        uint256 payout,
        address token
    ) internal {
        ISSListing.PayoutUpdate[] memory updates = new ISSListing.PayoutUpdate[](1);
        updates[0] = ISSListing.PayoutUpdate({
            payoutType: core1.positionType,
            recipient: msg.sender, // Payout to Hyx
            required: denormalizeAmount(token, payout)
        });
        ISSListing(core1.listingAddress).ssUpdate(address(this), updates);
    }

    // Prepares CSUpdate parameters for drift function
    function _prepDriftCSUpdateParams(
        uint256 positionId,
        ICSStorage.PositionCore1 memory core1,
        ICSStorage.MarginParams1 memory margin1,
        address token,
        ICSStorage sContract
    ) internal view returns (
        string memory coreParams,
        string memory priceParams,
        string memory marginParams,
        string memory exitAndInterestParams,
        string memory makerMarginParams
    ) {
        coreParams = string(abi.encodePacked(
            positionId, "-", core1.listingAddress, "-", toString(core1.makerAddress), "-", uint256(core1.positionType)
        ));
        priceParams = string(abi.encodePacked(
            sContract.priceParams1(positionId).minEntryPrice, "-",
            sContract.priceParams1(positionId).maxEntryPrice, "-",
            sContract.priceParams1(positionId).minPrice, "-",
            sContract.priceParams1(positionId).priceAtEntry, "-",
            uint256(sContract.priceParams1(positionId).leverage)
        ));
        marginParams = string(abi.encodePacked(
            margin1.initialMargin, "-",
            margin1.taxedMargin, "-",
            margin1.excessMargin, "-",
            margin1.fee, "-",
            sContract.marginParams2(positionId).initialLoan
        ));
        exitAndInterestParams = string(abi.encodePacked(
            sContract.exitParams(positionId).stopLossPrice, "-",
            sContract.exitParams(positionId).takeProfitPrice, "-",
            normalizePrice(token, ISSListing(core1.listingAddress).prices(core1.listingAddress)), "-",
            sContract.openInterest(positionId).leverageAmount, "-",
            sContract.openInterest(positionId).timestamp
        ));
        makerMarginParams = string(abi.encodePacked(
            toString(core1.makerAddress), "-",
            toString(core1.positionType == 0 ? ISSListing(core1.listingAddress).tokenA() : ISSListing(core1.listingAddress).tokenB()), "-",
            sContract.makerTokenMargin(
                core1.makerAddress,
                core1.positionType == 0 ? ISSListing(core1.listingAddress).tokenA() : ISSListing(core1.listingAddress).tokenB()
            )
        ));
    }

    // Executes CSUpdate for drift function
    function _executeDriftCSUpdate(
        uint256 positionId,
        string memory coreParams,
        string memory priceParams,
        string memory marginParams,
        string memory exitAndInterestParams,
        string memory makerMarginParams,
        ICSStorage sContract
    ) internal {
        sContract.CSUpdate(
            positionId,
            coreParams,
            priceParams,
            marginParams,
            exitAndInterestParams,
            makerMarginParams,
            "", // positionArrayParams
            ""  // historicalInterestParams
        );
    }

    // Allows Hyxes to close a specific position on behalf of a maker, sending payout to Hyx
    function drift(uint256 positionId, address maker) external nonReentrant onlyHyx {
        // Prepare core data
        (ICSStorage.PositionCore1 memory core1, ICSStorage.PositionCore2 memory core2) = _prepDriftCore(positionId, maker);

        // Prepare payout and token
        (uint256 payout, address token) = _prepDriftPayout(positionId, core1, storageContract);

        // Prepare margin and deduct
        (ICSStorage.MarginParams1 memory margin1, address marginToken) = _prepDriftMargin(positionId, core1, storageContract);

        // Prepare payout update
        _prepDriftPayoutUpdate(positionId, core1, payout, token);

        // Prepare CSUpdate parameters
        (string memory coreParams, string memory priceParams, string memory marginParams, string memory exitAndInterestParams, string memory makerMarginParams) = 
            _prepDriftCSUpdateParams(positionId, core1, margin1, token, storageContract);

        // Execute CSUpdate
        _executeDriftCSUpdate(positionId, coreParams, priceParams, marginParams, exitAndInterestParams, makerMarginParams, storageContract);

        // Remove position index
        storageContract.removePositionIndex(positionId, core1.positionType, core1.listingAddress);

        // Emit event
        emit PositionClosed(positionId, maker, payout);
    }
}