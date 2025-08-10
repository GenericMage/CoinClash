/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-08-05: Split _transferMarginToListing into _transferMarginToListingNative and _transferMarginToListingToken, _updateMakerMargin into _updateMakerMarginNative and _updateMakerMarginToken; updated prepEnterLong and prepEnterShort to use respective helpers based on token type; version set to 0.0.18.
 - 2025-08-05: Fixed TypeError in prepEnterLong and prepEnterShort by capturing priceAtEntry from _parseEntryPriceInternal return values; version set to 0.0.17.
 - 2025-08-05: Created CCSEntryPartial.sol by extracting EntryContext, PrepPosition, and related functions from CCSPositionPartial.sol v0.0.15; consolidated interfaces; version set to 0.0.16.
 - 2025-08-05: Updated ICSStorage and ISSAgent interfaces; updated ISSListing interface, removing caller parameter; replaced hyphen-delimited CSUpdate with structured parameters; added try-catch for external calls; reordered prepEnterLong and prepEnterShort. Version set to 0.0.15.
*/

pragma solidity ^0.8.2;

import "../imports/IERC20.sol";
import "../imports/ReentrancyGuard.sol";

interface ISSListing {
    struct UpdateType {
        uint8 updateType; // 0: Balance, 1: Buy order, 2: Sell order, 3: Historical
        uint8 structId; // 0: Core, 1: Pricing, 2: Amounts
        uint256 index; // Order ID or balance slot (0: xBalance, 1: yBalance, 2: xVolume, 3: yVolume)
        uint256 value; // Normalized amount or price for historical data
        address addr; // Maker address for orders
        address recipient; // Recipient address for orders
        uint256 maxPrice; // Max price for pricing or packed xBalance/yBalance for historical
        uint256 minPrice; // Min price for pricing or packed xVolume/yVolume for historical
        uint256 amountSent; // Normalized amount of opposite token sent during settlement
    }
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function prices(uint256) external view returns (uint256);
    function liquidityAddressView() external view returns (address);
    function update(UpdateType[] calldata updates) external;
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
    function isValidListing(address listingAddress) external view returns (bool isValid, ListingDetails memory details);
}

interface ICSStorage {
    struct PositionCore1 {
        uint256 positionId; // Unique position identifier
        address listingAddress; // Listing contract address
        address makerAddress; // Position owner
        uint8 positionType; // 0 for long, 1 for short
    }
    struct CoreParams {
        uint256 positionId; // Position ID
        address listingAddress; // Listing contract address
        address makerAddress; // Position owner
        uint8 positionType; // 0 for long, 1 for short
        bool status1; // Active flag
        uint8 status2; // 0 for open, 1 for closed
    }
    struct PriceParams {
        uint256 minEntryPrice; // Minimum entry price
        uint256 maxEntryPrice; // Maximum entry price
        uint256 minPrice; // Minimum price
        uint256 priceAtEntry; // Entry price
        uint8 leverage; // Leverage multiplier
        uint256 liquidationPrice; // Liquidation price
    }
    struct MarginParams {
        uint256 initialMargin; // Initial margin
        uint256 taxedMargin; // Taxed margin
        uint256 excessMargin; // Excess margin
        uint256 fee; // Fee amount
        uint256 initialLoan; // Initial loan amount
    }
    struct ExitAndInterestParams {
        uint256 stopLossPrice; // Stop loss price
        uint256 takeProfitPrice; // Take profit price
        uint256 exitPrice; // Exit price
        uint256 leverageAmount; // Leveraged amount
        uint256 timestamp; // Update timestamp
    }
    struct MakerMarginParams {
        address token; // Position token
        address maker; // Position owner
        address marginToken; // Margin token
        uint256 marginAmount; // Margin amount, normalized
    }
    struct PositionArrayParams {
        address listingAddress; // Listing contract address
        uint8 positionType; // 0 for long, 1 for short
        bool addToPending; // Add to pending positions
        bool addToActive; // Add to active positions
    }
    struct HistoricalInterestParams {
        uint256 longIO; // Long open interest
        uint256 shortIO; // Short open interest
        uint256 timestamp; // Timestamp of interest update
    }
    function DECIMAL_PRECISION() external view returns (uint256);
    function positionCount() external view returns (uint256);
    function makerTokenMargin(address maker, address token) external view returns (uint256);
    function positionCore1(uint256 positionId) external view returns (PositionCore1 memory);
    function CSUpdate(
        uint256 positionId,
        CoreParams memory coreParams,
        PriceParams memory priceParams,
        MarginParams memory marginParams,
        ExitAndInterestParams memory exitAndInterestParams,
        MakerMarginParams memory makerMarginParams,
        PositionArrayParams memory positionArrayParams,
        HistoricalInterestParams memory historicalInterestParams
    ) external;
}

contract CCSEntryPartial is ReentrancyGuard {
    uint256 public constant DECIMAL_PRECISION = 1e18;
    address public executionDriver;

    struct PrepPosition {
        uint256 fee; // Fee amount, normalized
        uint256 taxedMargin; // Taxed margin, normalized
        uint256 leverageAmount; // Leveraged amount, normalized
        uint256 initialLoan; // Initial loan amount, normalized
        uint256 liquidationPrice; // Liquidation price, normalized
    }

    struct EntryContext {
        uint256 positionId; // Unique position identifier
        address listingAddress; // Listing contract address
        uint256 minEntryPrice; // Minimum entry price, normalized
        uint256 maxEntryPrice; // Maximum entry price, normalized
        uint256 initialMargin; // Initial margin, normalized
        uint256 excessMargin; // Excess margin, normalized
        uint8 leverage; // Leverage multiplier
        uint8 positionType; // 0 for long, 1 for short
        address maker; // Position owner
        address token; // Position token
    }

    function setExecutionDriver(address _executionDriver) external onlyOwner {
        // Sets the execution driver address, restricted to owner
        require(_executionDriver != address(0), "Invalid execution driver address");
        executionDriver = _executionDriver;
    }

    function getExecutionDriver() external view returns (address executionDriverAddress) {
        // Returns the execution driver address
        return executionDriver;
    }

    function normalizePrice(address token, uint256 price) internal view returns (uint256 normalizedPrice) {
        // Normalizes price to 18 decimals based on token decimals
        if (token == address(0)) return price; // Native ETH has 18 decimals
        uint8 decimals = IERC20(token).decimals();
        if (decimals < 18) return price * (10 ** (18 - decimals));
        if (decimals > 18) return price / (10 ** (decimals - 18));
        return price;
    }

    function denormalizeAmount(address token, uint256 amount) internal view returns (uint256 denormalizedAmount) {
        // Denormalizes amount from 18 decimals to token decimals
        if (token == address(0)) return amount; // Native ETH has 18 decimals
        uint8 decimals = IERC20(token).decimals();
        return amount * (10 ** decimals) / DECIMAL_PRECISION;
    }

    function normalizeAmount(address token, uint256 amount) internal view returns (uint256 normalizedAmount) {
        // Normalizes amount to 18 decimals based on token decimals
        if (token == address(0)) return amount; // Native ETH has 18 decimals
        uint8 decimals = IERC20(token).decimals();
        return amount * DECIMAL_PRECISION / (10 ** decimals);
    }

    function computeFee(uint256 initialMargin, uint8 leverage) internal pure returns (uint256 fee) {
        // Computes fee as (leverage - 1)% of initial margin
        uint256 feePercent = uint256(leverage) - 1;
        return (initialMargin * feePercent * DECIMAL_PRECISION) / 100 / DECIMAL_PRECISION;
    }

    function _parseEntryPriceInternal(
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        address listingAddress
    ) internal view returns (uint256 currentPrice, uint256 minPrice, uint256 maxPrice, uint256 priceAtEntry) {
        // Fetches current price and validates against min/max entry prices
        try ISSListing(listingAddress).prices(0) returns (uint256 price) {
            currentPrice = price;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Price fetch failed: ", reason)));
        } catch {
            revert("Price fetch failed: Unknown error");
        }
        minPrice = minEntryPrice;
        maxPrice = maxEntryPrice;
        priceAtEntry = 0; // Pending status
        return (currentPrice, minPrice, maxPrice, priceAtEntry);
    }

    function _transferLiquidityFee(
        address listingAddress,
        address token,
        uint256 fee,
        uint8 positionType
    ) internal {
        // Transfers fee to liquidity contract and updates fees
        address liquidityAddr;
        try ISSListing(listingAddress).liquidityAddressView() returns (address addr) {
            liquidityAddr = addr;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Liquidity address fetch failed: ", reason)));
        } catch {
            revert("Liquidity address fetch failed: Unknown error");
        }
        require(liquidityAddr != address(0), "Invalid liquidity address");
        if (fee > 0) {
            uint256 denormalizedFee = denormalizeAmount(token, fee);
            if (token == address(0)) {
                // Native ETH transfer
                (bool success, ) = liquidityAddr.call{value: denormalizedFee}("");
                require(success, "Fee transfer to liquidity contract failed");
            } else {
                // ERC20 transfer
                uint256 balanceBefore = IERC20(token).balanceOf(liquidityAddr);
                try IERC20(token).transfer(liquidityAddr, denormalizedFee) returns (bool success) {
                    require(success, "Fee transfer to liquidity contract failed");
                } catch Error(string memory reason) {
                    revert(string(abi.encodePacked("Fee transfer failed: ", reason)));
                } catch {
                    revert("Fee transfer failed: Unknown error");
                }
                uint256 balanceAfter = IERC20(token).balanceOf(liquidityAddr);
                require(balanceAfter - balanceBefore == denormalizedFee, "Fee transfer balance mismatch");
            }
            try ISSLiquidityTemplate(liquidityAddr).addFees(address(this), positionType == 0, denormalizedFee) {
                // Fee added
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("Add fees failed: ", reason)));
            } catch {
                revert("Add fees failed: Unknown error");
            }
        }
    }

    function _transferMarginToListingNative(
        address listingAddress,
        address maker,
        uint256 taxedMargin,
        uint256 excessMargin,
        uint256 fee,
        uint8 positionType
    ) internal {
        // Transfers native ETH margin to execution driver and fee to liquidity contract
        uint256 transferAmount = taxedMargin + excessMargin;
        _transferLiquidityFee(listingAddress, address(0), fee, positionType);
        if (transferAmount > 0) {
            require(executionDriver != address(0), "Execution driver not set");
            uint256 denormalizedAmount = denormalizeAmount(address(0), transferAmount);
            require(msg.value >= denormalizedAmount, "Insufficient ETH sent");
            (bool success, ) = executionDriver.call{value: denormalizedAmount}("");
            require(success, "Margin transfer to execution driver failed");
            if (msg.value > denormalizedAmount) {
                (bool refundSuccess, ) = payable(maker).call{value: msg.value - denormalizedAmount}("");
                require(refundSuccess, "Refund of excess ETH failed");
            }
        }
    }

    function _transferMarginToListingToken(
        address token,
        address listingAddress,
        address maker,
        uint256 taxedMargin,
        uint256 excessMargin,
        uint256 fee,
        uint8 positionType
    ) internal {
        // Transfers ERC20 margin to execution driver and fee to liquidity contract
        uint256 transferAmount = taxedMargin + excessMargin;
        _transferLiquidityFee(listingAddress, token, fee, positionType);
        if (transferAmount > 0) {
            require(executionDriver != address(0), "Execution driver not set");
            uint256 denormalizedAmount = denormalizeAmount(token, transferAmount);
            uint256 balanceBefore = IERC20(token).balanceOf(executionDriver);
            try IERC20(token).transferFrom(maker, executionDriver, denormalizedAmount) returns (bool success) {
                require(success, "Margin transfer from maker to execution driver failed");
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("Margin transfer failed: ", reason)));
            } catch {
                revert("Margin transfer failed: Unknown error");
            }
            uint256 balanceAfter = IERC20(token).balanceOf(executionDriver);
            require(balanceAfter - balanceBefore == denormalizedAmount, "Margin transfer balance mismatch");
        }
    }

    function _checkLiquidityLimitLong(
        address listingAddress,
        uint256 initialLoan,
        uint8 leverage
    ) internal view returns (address tokenB) {
        // Checks liquidity limit for long position
        address liquidityAddr;
        try ISSListing(listingAddress).liquidityAddressView() returns (address addr) {
            liquidityAddr = addr;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Liquidity address fetch failed: ", reason)));
        } catch {
            revert("Liquidity address fetch failed: Unknown error");
        }
        ( , uint256 yLiquid, , ) = ISSLiquidityTemplate(liquidityAddr).liquidityDetailsView(address(this));
        uint256 limitPercent = 101 - uint256(leverage);
        uint256 limit = yLiquid * limitPercent / 100;
        require(initialLoan <= limit, "Initial loan exceeds liquidity limit for long position");
        try ISSListing(listingAddress).tokenB() returns (address token) {
            tokenB = token;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("TokenB fetch failed: ", reason)));
        } catch {
            revert("TokenB fetch failed: Unknown error");
        }
    }

    function _checkLiquidityLimitShort(
        address listingAddress,
        uint256 initialLoan,
        uint8 leverage
    ) internal view returns (address tokenA) {
        // Checks liquidity limit for short position
        address liquidityAddr;
        try ISSListing(listingAddress).liquidityAddressView() returns (address addr) {
            liquidityAddr = addr;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Liquidity address fetch failed: ", reason)));
        } catch {
            revert("Liquidity address fetch failed: Unknown error");
        }
        (uint256 xLiquid, , , ) = ISSLiquidityTemplate(liquidityAddr).liquidityDetailsView(address(this));
        uint256 limitPercent = 101 - uint256(leverage);
        uint256 limit = xLiquid * limitPercent / 100;
        require(initialLoan <= limit, "Initial loan exceeds liquidity limit for short position");
        try ISSListing(listingAddress).tokenA() returns (address token) {
            tokenA = token;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("TokenA fetch failed: ", reason)));
        } catch {
            revert("TokenA fetch failed: Unknown error");
        }
    }

    function _computeLoanAndLiquidationLong(
        uint256 leverageAmount,
        uint256 minPrice,
        address maker,
        address tokenA,
        ICSStorage storageContract
    ) internal view returns (uint256 initialLoan, uint256 liquidationPrice) {
        // Computes initial loan and liquidation price for long position
        initialLoan = leverageAmount / minPrice;
        uint256 marginRatio;
        try storageContract.makerTokenMargin(maker, tokenA) returns (uint256 margin) {
            marginRatio = margin / leverageAmount;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Maker margin fetch failed: ", reason)));
        } catch {
            revert("Maker margin fetch failed: Unknown error");
        }
        liquidationPrice = marginRatio < minPrice ? minPrice - marginRatio : 0;
    }

    function _computeLoanAndLiquidationShort(
        uint256 leverageAmount,
        uint256 minPrice,
        address maker,
        address tokenB,
        ICSStorage storageContract
    ) internal view returns (uint256 initialLoan, uint256 liquidationPrice) {
        // Computes initial loan and liquidation price for short position
        initialLoan = leverageAmount * minPrice;
        uint256 marginRatio;
        try storageContract.makerTokenMargin(maker, tokenB) returns (uint256 margin) {
            marginRatio = margin / leverageAmount;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Maker margin fetch failed: ", reason)));
        } catch {
            revert("Maker margin fetch failed: Unknown error");
        }
        liquidationPrice = minPrice + marginRatio;
    }

    function _updateMakerMarginNative(
        EntryContext memory context,
        uint256 taxedMargin,
        uint256 excessMargin,
        ICSStorage storageContract
    ) internal {
        // Updates maker margin in storage contract for native ETH
        uint256 transferAmount = taxedMargin + normalizeAmount(address(0), context.excessMargin);
        ICSStorage.MakerMarginParams memory makerMarginParams = ICSStorage.MakerMarginParams({
            token: address(0),
            maker: context.maker,
            marginToken: address(0),
            marginAmount: 0
        });
        try storageContract.makerTokenMargin(context.maker, address(0)) returns (uint256 margin) {
            makerMarginParams.marginAmount = margin + transferAmount;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Maker margin fetch failed: ", reason)));
        } catch {
            revert("Maker margin fetch failed: Unknown error");
        }
        try storageContract.CSUpdate(
            0,
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
        ) {
            // Margin updated
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("CSUpdate failed: ", reason)));
        } catch {
            revert("CSUpdate failed: Unknown error");
        }
    }

    function _updateMakerMarginToken(
        EntryContext memory context,
        uint256 taxedMargin,
        uint256 excessMargin,
        address marginToken,
        ICSStorage storageContract
    ) internal {
        // Updates maker margin in storage contract for ERC20 token
        uint256 transferAmount = taxedMargin + normalizeAmount(context.token, context.excessMargin);
        ICSStorage.MakerMarginParams memory makerMarginParams = ICSStorage.MakerMarginParams({
            token: address(0),
            maker: context.maker,
            marginToken: marginToken,
            marginAmount: 0
        });
        try storageContract.makerTokenMargin(context.maker, marginToken) returns (uint256 margin) {
            makerMarginParams.marginAmount = margin + transferAmount;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Maker margin fetch failed: ", reason)));
        } catch {
            revert("Maker margin fetch failed: Unknown error");
        }
        try storageContract.CSUpdate(
            0,
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
        ) {
            // Margin updated
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("CSUpdate failed: ", reason)));
        } catch {
            revert("CSUpdate failed: Unknown error");
        }
    }

    function prepEnterLong(
        EntryContext memory context,
        ICSStorage storageContract
    ) internal returns (PrepPosition memory params) {
        // Prepares parameters for entering a long position
        require(context.initialMargin > 0, "Initial margin must be greater than zero");
        require(context.leverage >= 2 && context.leverage <= 100, "Leverage must be between 2 and 100");
        address tokenA;
        try ISSListing(context.listingAddress).tokenA() returns (address token) {
            tokenA = token;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("TokenA fetch failed: ", reason)));
        } catch {
            revert("TokenA fetch failed: Unknown error");
        }
        (uint256 currentPrice, uint256 minPrice, uint256 maxPrice, uint256 priceAtEntry) = _parseEntryPriceInternal(
            normalizePrice(context.token, context.minEntryPrice),
            normalizePrice(context.token, context.maxEntryPrice),
            context.listingAddress
        );
        params.fee = computeFee(context.initialMargin, context.leverage);
        params.taxedMargin = normalizeAmount(context.token, context.initialMargin) - params.fee;
        params.leverageAmount = normalizeAmount(context.token, context.initialMargin) * uint256(context.leverage);
        if (context.token == address(0)) {
            _updateMakerMarginNative(context, params.taxedMargin, context.excessMargin, storageContract);
            _transferMarginToListingNative(
                context.listingAddress,
                context.maker,
                params.taxedMargin,
                normalizeAmount(context.token, context.excessMargin),
                params.fee,
                0
            );
        } else {
            _updateMakerMarginToken(context, params.taxedMargin, context.excessMargin, tokenA, storageContract);
            _transferMarginToListingToken(
                tokenA,
                context.listingAddress,
                context.maker,
                params.taxedMargin,
                normalizeAmount(context.token, context.excessMargin),
                params.fee,
                0
            );
        }
        (params.initialLoan, params.liquidationPrice) = _computeLoanAndLiquidationLong(
            params.leverageAmount,
            minPrice,
            context.maker,
            tokenA,
            storageContract
        );
        _checkLiquidityLimitLong(context.listingAddress, params.initialLoan, context.leverage);
        return params;
    }

    function prepEnterShort(
        EntryContext memory context,
        ICSStorage storageContract
    ) internal returns (PrepPosition memory params) {
        // Prepares parameters for entering a short position
        require(context.initialMargin > 0, "Initial margin must be greater than zero");
        require(context.leverage >= 2 && context.leverage <= 100, "Leverage must be between 2 and 100");
        address tokenB;
        try ISSListing(context.listingAddress).tokenB() returns (address token) {
            tokenB = token;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("TokenB fetch failed: ", reason)));
        } catch {
            revert("TokenB fetch failed: Unknown error");
        }
        (uint256 currentPrice, uint256 minPrice, uint256 maxPrice, uint256 priceAtEntry) = _parseEntryPriceInternal(
            normalizePrice(context.token, context.minEntryPrice),
            normalizePrice(context.token, context.maxEntryPrice),
            context.listingAddress
        );
        params.fee = computeFee(context.initialMargin, context.leverage);
        params.taxedMargin = normalizeAmount(context.token, context.initialMargin) - params.fee;
        params.leverageAmount = normalizeAmount(context.token, context.initialMargin) * uint256(context.leverage);
        if (context.token == address(0)) {
            _updateMakerMarginNative(context, params.taxedMargin, context.excessMargin, storageContract);
            _transferMarginToListingNative(
                context.listingAddress,
                context.maker,
                params.taxedMargin,
                normalizeAmount(context.token, context.excessMargin),
                params.fee,
                1
            );
        } else {
            _updateMakerMarginToken(context, params.taxedMargin, context.excessMargin, tokenB, storageContract);
            _transferMarginToListingToken(
                tokenB,
                context.listingAddress,
                context.maker,
                params.taxedMargin,
                normalizeAmount(context.token, context.excessMargin),
                params.fee,
                1
            );
        }
        (params.initialLoan, params.liquidationPrice) = _computeLoanAndLiquidationShort(
            params.leverageAmount,
            minPrice,
            context.maker,
            tokenB,
            storageContract
        );
        _checkLiquidityLimitShort(context.listingAddress, params.initialLoan, context.leverage);
        return params;
    }
}