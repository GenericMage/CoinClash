/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-08-05: Split enterLong into enterLongNative and enterLongToken, enterShort into enterShortNative and enterShortToken, drive into driveNative and driveToken; added receive function for ETH; version set to 0.0.17.
 - 2025-08-05: Fixed DeclarationError in _prepMarginParams by replacing undeclared priceParams with marginParams in CSUpdate call; version set to 0.0.16.
 - 2025-08-05: Created CCSEntryDriver.sol by extracting position entry logic from CCSPositionDriver.sol v0.0.14; updated imports to CCSEntryPartial.sol; version set to 0.0.15.
 - 2025-08-05: Updated ISSListing and ICSStorage interfaces to match ICCListingTemplate and ICSStorage; replaced hyphen-delimited CSUpdate calls with structured parameters; updated _validateAndInit to use isValidListing; removed caller from ISSListing.update and ssUpdate; version set to 0.0.14.
*/

pragma solidity ^0.8.2;

import "../driverUtils/CCSEntryPartial.sol";

contract CCSEntryDriver is CCSEntryPartial {
    ICSStorage public storageContract;
    address public agentAddress;
    address[] private hyxes;

    event PositionEntered(uint256 indexed positionId, address indexed maker, uint8 positionType);
    event HyxAdded(address indexed hyx);
    event HyxRemoved(address indexed hyx);

    modifier onlyHyx() {
        // Restricts access to authorized Hyx addresses
        bool isHyx = false;
        for (uint256 i = 0; i < hyxes.length; i++) {
            if (hyxes[i] == msg.sender) {
                isHyx = true;
                break;
            }
        }
        require(isHyx, "Caller is not an authorized Hyx");
        _;
    }

    receive() external payable {
        // Allows contract to receive ETH for native transactions
    }

    function setStorageContract(address _storageContract) external onlyOwner {
        // Sets the storage contract address, restricted to owner
        require(_storageContract != address(0), "Invalid storage contract address");
        storageContract = ICSStorage(_storageContract);
    }

    function setAgent(address newAgentAddress) external onlyOwner {
        // Sets the agent address, restricted to owner
        require(newAgentAddress != address(0), "Invalid agent address");
        agentAddress = newAgentAddress;
    }

    function addHyx(address hyx) external onlyOwner {
        // Adds a Hyx address to the authorized list, restricted to owner
        require(hyx != address(0), "Invalid Hyx address");
        for (uint256 i = 0; i < hyxes.length; i++) {
            require(hyxes[i] != hyx, "Hyx already exists");
        }
        hyxes.push(hyx);
        emit HyxAdded(hyx);
    }

    function removeHyx(address hyx) external onlyOwner {
        // Removes a Hyx address from the authorized list, restricted to owner
        require(hyx != address(0), "Invalid Hyx address");
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

    function getHyxes() external view returns (address[] memory hyxesList) {
        // Returns the list of authorized Hyx addresses
        return hyxes;
    }

    function _validateAndInit(
        address listingAddress,
        uint8 positionType
    ) internal returns (address maker, address token) {
        // Validates listing and initializes position parameters
        uint256 positionId = storageContract.positionCount() + 1;
        require(storageContract.positionCore1(positionId).positionId == 0, "Position ID already exists");
        (bool isValid, ISSAgent.ListingDetails memory details) = ISSAgent(agentAddress).isValidListing(listingAddress);
        require(isValid, "Invalid listing address");
        maker = msg.sender;
        token = positionType == 0 ? details.tokenA : details.tokenB;
        return (maker, token);
    }

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
        // Prepares entry context struct with provided parameters
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

    function _validateEntry(
        EntryContext memory context
    ) internal returns (EntryContext memory) {
        // Validates entry parameters and sets maker and token
        require(context.initialMargin > 0, "Initial margin must be greater than zero");
        require(context.leverage >= 2 && context.leverage <= 100, "Leverage must be between 2 and 100");
        (context.maker, context.token) = _validateAndInit(context.listingAddress, context.positionType);
        return context;
    }

    function _computeEntryParams(
        EntryContext memory context
    ) internal returns (PrepPosition memory params) {
        // Computes entry parameters based on position type
        if (context.positionType == 0) {
            params = prepEnterLong(context, storageContract);
        } else {
            params = prepEnterShort(context, storageContract);
        }
        return params;
    }

    function _prepCoreParams(
        uint256 positionId,
        address listingAddress,
        address maker,
        uint8 positionType
    ) internal {
        // Prepares core parameters for storage update
        ICSStorage.CoreParams memory coreParams = ICSStorage.CoreParams({
            positionId: positionId,
            listingAddress: listingAddress,
            makerAddress: maker,
            positionType: positionType,
            status1: false,
            status2: 0
        });
        storageContract.CSUpdate(
            positionId,
            coreParams,
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
            ICSStorage.MakerMarginParams({
                token: address(0),
                maker: address(0),
                marginToken: address(0),
                marginAmount: 0
            }),
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
        );
    }

    function _prepPriceParams(
        uint256 positionId,
        address token,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 liquidationPrice,
        uint8 leverage
    ) internal {
        // Prepares price parameters for storage update
        (,, uint256 minPrice, uint256 priceAtEntry) = _parseEntryPriceInternal(
            normalizePrice(token, minEntryPrice),
            normalizePrice(token, maxEntryPrice),
            storageContract.positionCore1(positionId).listingAddress
        );
        ICSStorage.PriceParams memory priceParams = ICSStorage.PriceParams({
            minEntryPrice: normalizePrice(token, minEntryPrice),
            maxEntryPrice: normalizePrice(token, maxEntryPrice),
            minPrice: minPrice,
            priceAtEntry: priceAtEntry,
            leverage: leverage,
            liquidationPrice: liquidationPrice
        });
        storageContract.CSUpdate(
            positionId,
            ICSStorage.CoreParams({
                positionId: 0,
                listingAddress: address(0),
                makerAddress: address(0),
                positionType: 0,
                status1: false,
                status2: 0
            }),
            priceParams,
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
            ICSStorage.MakerMarginParams({
                token: address(0),
                maker: address(0),
                marginToken: address(0),
                marginAmount: 0
            }),
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
        );
    }

    function _prepMarginParams(
        uint256 positionId,
        address token,
        uint256 initialMargin,
        uint256 taxedMargin,
        uint256 excessMargin,
        uint256 fee,
        uint256 initialLoan
    ) internal {
        // Prepares margin parameters for storage update
        ICSStorage.MarginParams memory marginParams = ICSStorage.MarginParams({
            initialMargin: normalizeAmount(token, initialMargin),
            taxedMargin: taxedMargin,
            excessMargin: normalizeAmount(token, excessMargin),
            fee: fee,
            initialLoan: normalizeAmount(token, initialLoan)
        });
        storageContract.CSUpdate(
            positionId,
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
            marginParams,
            ICSStorage.ExitAndInterestParams({
                stopLossPrice: 0,
                takeProfitPrice: 0,
                exitPrice: 0,
                leverageAmount: 0,
                timestamp: 0
            }),
            ICSStorage.MakerMarginParams({
                token: address(0),
                maker: address(0),
                marginToken: address(0),
                marginAmount: 0
            }),
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
        );
    }

    function _prepExitAndInterestParams(
        uint256 positionId,
        address token,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        uint256 leverageAmount
    ) internal {
        // Prepares exit and interest parameters for storage update
        ICSStorage.ExitAndInterestParams memory exitAndInterestParams = ICSStorage.ExitAndInterestParams({
            stopLossPrice: normalizePrice(token, stopLossPrice),
            takeProfitPrice: normalizePrice(token, takeProfitPrice),
            exitPrice: 0,
            leverageAmount: leverageAmount,
            timestamp: block.timestamp
        });
        storageContract.CSUpdate(
            positionId,
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
            exitAndInterestParams,
            ICSStorage.MakerMarginParams({
                token: address(0),
                maker: address(0),
                marginToken: address(0),
                marginAmount: 0
            }),
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
        );
    }

    function _prepMakerMarginParams(
        uint256 positionId,
        address maker,
        address marginToken
    ) internal {
        // Prepares maker margin parameters for storage update
        ICSStorage.MakerMarginParams memory makerMarginParams = ICSStorage.MakerMarginParams({
            token: marginToken,
            maker: maker,
            marginToken: marginToken,
            marginAmount: storageContract.makerTokenMargin(maker, marginToken)
        });
        storageContract.CSUpdate(
            positionId,
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
        );
    }

    function _prepPositionArrayParams(
        uint256 positionId,
        uint8 positionType,
        uint256 leverageAmount
    ) internal {
        // Prepares position array parameters for storage update
        ICSStorage.PositionArrayParams memory positionArrayParams = ICSStorage.PositionArrayParams({
            listingAddress: storageContract.positionCore1(positionId).listingAddress,
            positionType: positionType,
            addToPending: true,
            addToActive: false
        });
        ICSStorage.HistoricalInterestParams memory historicalInterestParams = ICSStorage.HistoricalInterestParams({
            longIO: positionType == 0 ? leverageAmount : 0,
            shortIO: positionType == 1 ? leverageAmount : 0,
            timestamp: block.timestamp
        });
        storageContract.CSUpdate(
            positionId,
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
            ICSStorage.MakerMarginParams({
                token: address(0),
                maker: address(0),
                marginToken: address(0),
                marginAmount: 0
            }),
            positionArrayParams,
            historicalInterestParams
        );
    }

    function _storeEntryData(
        EntryContext memory context,
        PrepPosition memory prep,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) internal {
        // Stores entry data by calling individual parameter preparation functions
        _prepCoreParams(context.positionId, context.listingAddress, context.maker, context.positionType);
        _prepPriceParams(context.positionId, context.token, context.minEntryPrice, context.maxEntryPrice, prep.liquidationPrice, context.leverage);
        _prepMarginParams(context.positionId, context.token, context.initialMargin, prep.taxedMargin, context.excessMargin, prep.fee, prep.initialLoan);
        _prepExitAndInterestParams(context.positionId, context.token, stopLossPrice, takeProfitPrice, prep.leverageAmount);
        _prepMakerMarginParams(context.positionId, context.maker, context.positionType == 0 ? ISSListing(context.listingAddress).tokenA() : ISSListing(context.listingAddress).tokenB());
        _prepPositionArrayParams(context.positionId, context.positionType, prep.leverageAmount);
    }

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
        // Initiates position entry process
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

    function enterLongNative(
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external payable {
        // Initiates a long position entry with native ETH
        require(msg.value > 0, "Must send ETH for initial margin");
        _initiateEntry(listingAddress, minEntryPrice, maxEntryPrice, msg.value, excessMargin, leverage, stopLossPrice, takeProfitPrice, 0);
    }

    function enterLongToken(
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external {
        // Initiates a long position entry with ERC20 token
        _initiateEntry(listingAddress, minEntryPrice, maxEntryPrice, initialMargin, excessMargin, leverage, stopLossPrice, takeProfitPrice, 0);
    }

    function enterShortNative(
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external payable {
        // Initiates a short position entry with native ETH
        require(msg.value > 0, "Must send ETH for initial margin");
        _initiateEntry(listingAddress, minEntryPrice, maxEntryPrice, msg.value, excessMargin, leverage, stopLossPrice, takeProfitPrice, 1);
    }

    function enterShortToken(
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external {
        // Initiates a short position entry with ERC20 token
        _initiateEntry(listingAddress, minEntryPrice, maxEntryPrice, initialMargin, excessMargin, leverage, stopLossPrice, takeProfitPrice, 1);
    }

    function driveNative(
        address maker,
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        uint8 positionType
    ) external payable nonReentrant onlyHyx {
        // Initiates a position entry with native ETH for a specified maker, restricted to Hyx
        require(maker != address(0), "Invalid maker address");
        require(positionType <= 1, "Invalid position type");
        require(msg.value > 0, "Must send ETH for initial margin");
        uint256 positionId = storageContract.positionCount() + 1;
        EntryContext memory context = _prepareEntryContext(
            listingAddress,
            positionId,
            minEntryPrice,
            maxEntryPrice,
            msg.value,
            excessMargin,
            leverage,
            positionType
        );
        context.maker = maker;
        context = _validateEntry(context);
        PrepPosition memory params = _computeEntryParams(context);
        _storeEntryData(context, params, stopLossPrice, takeProfitPrice);
        emit PositionEntered(positionId, maker, positionType);
    }

    function driveToken(
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
    ) external nonReentrant onlyHyx {
        // Initiates a position entry with ERC20 token for a specified maker, restricted to Hyx
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
        context.maker = maker;
        context = _validateEntry(context);
        PrepPosition memory params = _computeEntryParams(context);
        _storeEntryData(context, params, stopLossPrice, takeProfitPrice);
        emit PositionEntered(positionId, maker, positionType);
    }
}