// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.9
// Changes:
// - v0.0.9: Updated ICCListing interface to remove uint256 parameter from liquidityAddressView for compatibility with CCListingTemplate.sol v0.0.6.
// - v0.0.08: Modified checkValidListing to use contract's own agent state variable instead of listing's agentView, removed agentView call and require check for agent non-zero (line 273).
// - v0.0.07: Removed SafeERC20 import and usage, imported IERC20 from ../imports/.
// - v0.0.06: Updated ICCListing's transactNative to payable to resolve TypeError in CCUniPartial.sol.
// - v0.0.05: Updated ICCLiquidityTemplate, split transact/deposit, updated Slot timestamp to uint256.
// - v0.0.04: Integrated uniswapV2Router state variable and setters.
// - v0.0.03: Fixed DeclarationError in checkValidListing.
// - v0.0.02: Fixed TypeError in checkValidListing.
// - v0.0.01: Inlined ICCListing, split transact into token/native.
// Compatible with CCListingTemplate.sol (v0.0.6), CCOrderRouter.sol (v0.0.8), CCUniPartial.sol (v0.0.7), ICCLiquidity.sol, CCLiquidityRouter.sol (v0.0.14).

import "../imports/ReentrancyGuard.sol";
import "../imports/Ownable.sol";
import "../imports/IERC20.sol";

interface ICCListing {
    struct UpdateType {
        uint8 updateType; // 0=balance, 1=buy order, 2=sell order, 3=historical
        uint8 structId;   // 0=Core, 1=Pricing, 2=Amounts
        uint256 index;    // orderId or slot index
        uint256 value;    // principal or amount
        address addr;     // makerAddress
        address recipient; // recipientAddress
        uint256 maxPrice; // for Pricing struct
        uint256 minPrice; // for Pricing struct
        uint256 amountSent; // for Amounts struct
    }
    struct PayoutUpdate {
        uint8 payoutType; // 0=Long, 1=Short
        address recipient;
        uint256 required;
    }
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
    function prices(uint256 _listingId) external view returns (uint256);
    function volumeBalances(uint256 _listingId) external view returns (uint256 xBalance, uint256 yBalance);
    function liquidityAddressView() external view returns (address);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function ssUpdate(address caller, PayoutUpdate[] calldata updates) external;
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
    function getListingId() external view returns (uint256);
    function getNextOrderId() external view returns (uint256);
    function listingVolumeBalancesView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function listingPriceView() external view returns (uint256);
    function pendingBuyOrdersView() external view returns (uint256[] memory);
    function pendingSellOrdersView() external view returns (uint256[] memory);
    function makerPendingOrdersView(address maker) external view returns (uint256[] memory);
    function longPayoutByIndexView() external view returns (uint256[] memory);
    function shortPayoutByIndexView() external view returns (uint256[] memory);
    function userPayoutIDsView(address user) external view returns (uint256[] memory);
    function getLongPayout(uint256 orderId) external view returns (LongPayoutStruct memory);
    function getShortPayout(uint256 orderId) external view returns (ShortPayoutStruct memory);
    function getBuyOrderCore(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status);
    function getBuyOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice);
    function getBuyOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent);
    function getSellOrderCore(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status);
    function getSellOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice);
    function getSellOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent);
    function transactToken(address caller, address token, uint256 amount, address recipient) external returns (bool);
    function transactNative(address caller, uint256 amount, address recipient) external payable returns (bool);
    function uniswapV2PairView() external view returns (address);
    function setUniswapV2Pair(address _uniswapV2Pair) external;
    function setRouters(address[] memory _routers) external;
    function setListingId(uint256 _listingId) external;
    function setLiquidityAddress(address _liquidityAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setAgent(address _agent) external;
    function setRegistry(address _registryAddress) external;
    function update(address caller, UpdateType[] calldata updates) external;
    function agentView() external view returns (address);
}

interface ICCLiquidityTemplate {
    struct UpdateType {
        uint8 updateType; // 0=balance, 1=fees, 2=xSlot, 3=ySlot
        uint256 index; // 0=xFees/xLiquid, 1=yFees/yLiquid, or slot index
        uint256 value; // Normalized amount or allocation
        address addr; // Depositor address
        address recipient; // Unused recipient address
    }
    struct PreparedWithdrawal {
        uint256 amountA; // Normalized withdrawal amount for token A
        uint256 amountB; // Normalized withdrawal amount for token B
    }
    struct Slot {
        address depositor; // Address of the slot owner
        address recipient; // Unused recipient address
        uint256 allocation; // Normalized liquidity allocation
        uint256 dFeesAcc; // Cumulative fees at deposit or last claim
        uint256 timestamp; // Slot creation timestamp
    }
    function volumeBalances(uint256 listingId) external view returns (uint256 xBalance, uint256 yBalance);
    function getPrice() external view returns (uint256);
    function getRegistryAddress() external view returns (address);
    function routers(address router) external view returns (bool);
    function setRouters(address[] memory _routers) external;
    function setListingId(uint256 _listingId) external;
    function setListingAddress(address _listingAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setAgent(address _agent) external;
    function update(address caller, UpdateType[] memory updates) external;
    function changeSlotDepositor(address caller, bool isX, uint256 slotIndex, address newDepositor) external;
    function depositToken(address caller, address token, uint256 amount) external;
    function depositNative(address caller, uint256 amount) external payable;
    function xPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);
    function xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external;
    function yPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);
    function yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external;
    function claimFees(address caller, address listingAddress, uint256 liquidityIndex, bool isX, uint256 volume) external;
    function transactToken(address caller, address token, uint256 amount, address recipient) external;
    function transactNative(address caller, uint256 amount, address recipient) external;
    function addFees(address caller, bool isX, uint256 fee) external;
    function updateLiquidity(address caller, bool isX, uint256 amount) external;
    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount);
    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, uint256 xFeesAcc, uint256 yFeesAcc);
    function activeXLiquiditySlotsView() external view returns (uint256[] memory);
    function activeYLiquiditySlotsView() external view returns (uint256[] memory);
    function userIndexView(address user) external view returns (uint256[] memory);
    function getXSlotView(uint256 index) external view returns (Slot memory);
    function getYSlotView(uint256 index) external view returns (Slot memory);
}

interface ICCAgent {
    function getListing(address tokenA, address tokenB) external view returns (address);
}

contract CCMainPartial is ReentrancyGuard, Ownable {
    address internal agent;
    address internal uniswapV2Router;

    struct BuyOrderDetails {
        uint256 orderId;
        address maker;
        address receiver;
        uint256 pending;
        uint256 filled;
        uint256 maxPrice;
        uint256 minPrice;
        uint8 status;
    }

    struct SellOrderDetails {
        uint256 orderId;
        address maker;
        address receiver;
        uint256 pending;
        uint256 filled;
        uint256 maxPrice;
        uint256 minPrice;
        uint8 status;
    }

    struct OrderClearData {
        uint256 id;
        bool isBuy;
        uint256 amount;
    }

    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        // Normalizes amount to 18 decimals
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (uint256(18) - uint256(decimals));
        else return amount / 10 ** (uint256(decimals) - uint256(18));
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        // Denormalizes amount from 18 decimals to token decimals
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10 ** (uint256(18) - uint256(decimals));
        else return amount * 10 ** (uint256(decimals) - uint256(18));
    }

    function checkValidListing(address listing) private view {
        // Validates listing against agent registry using contract's own agent
        ICCListing listingTemplate = ICCListing(listing);
        address tokenAAddress = listingTemplate.tokenA();
        address tokenBAddress = listingTemplate.tokenB();
        require(agent != address(0), "Contract agent not set");
        require(ICCAgent(agent).getListing(tokenAAddress, tokenBAddress) == listing, "Invalid listing");
    }

    modifier onlyValidListing(address listing) {
        checkValidListing(listing);
        _;
    }

    function setAgent(address newAgent) external onlyOwner {
        // Sets new agent address
        require(newAgent != address(0), "Invalid agent address");
        agent = newAgent;
    }

    function setUniswapV2Router(address newRouter) external onlyOwner {
        // Sets Uniswap V2 router address
        require(newRouter != address(0), "Invalid router address");
        uniswapV2Router = newRouter;
    }

    function agentView() external view returns (address) {
        // Returns current agent address
        return agent;
    }

    function uniswapV2RouterView() external view returns (address) {
        // Returns Uniswap V2 router address
        return uniswapV2Router;
    }
}