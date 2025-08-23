/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Version: 0.1.3
 Changes:
 - v0.1.3: Removed duplicate subtraction in transactToken and transactNative, as xExecuteOut/yExecuteOut already handle subtraction via update calls. Modified balance checks in transactToken and transactNative to use xLiquid/yLiquid instead of total contract balance, ensuring fees are excluded from liquidity operations. Maintained compatibility with CCGlobalizer.sol v0.2.1, CCSEntryPartial.sol v0.0.18.
 - v0.1.2: Integrated update function calls with updateType == 0 for subtraction. No new updateType added. Maintained fee segregation and compatibility with CCGlobalizer.sol v0.2.1, CCSEntryPartial.sol v0.0.18.
 - v0.1.1: Added globalizeUpdate internal function to encapsulate globalization calls, extracted from transactToken and transactNative. Integrated into update function to handle deposits from liquidity router. No other changes to maintain compatibility.
 - Removed globalizerAddress state variable, updated transactToken and transactNative to fetch globalizer address directly from ICCAgent(agent).globalizerAddress() within each call, aligning with registry update pattern in update function. Compatible with CCGlobalizer.sol v0.2.1.
 - v0.1.0: Added globalizerAddress state variable, updated transactToken and transactNative to fetch globalizer address from agent and call ICCGlobalizer.globalizeLiquidity. Maintained compatibility with CCSEntryPartial.sol v0.0.18 and ICCGlobalizer v0.2.1.
 - v0.0.21: Adjusted globalizeLiquidity call in transactToken and transactNative for ICCGlobalizer v0.2.1. Added view functions userXIndexView, userYIndexView, getActiveXLiquiditySlots, getActiveYLiquiditySlots.
 - v0.0.20: Removed depositToken, depositNative, withdraw, claimFees, changeDepositor, moved to CCLiquidityRouter.sol v0.0.18 via CCLiquidityPartial.sol v0.0.13.
 - v0.0.19: Removed checkRouterInvolved and isRouter, replaced with require(routers[msg.sender], "Router only").
 Compatible with CCListingTemplate.sol (v0.0.10), CCMainPartial.sol (v0.0.10), CCLiquidityRouter.sol (v0.0.25), ICCLiquidity.sol (v0.0.4), ICCListing.sol (v0.0.7), CCSEntryPartial.sol (v0.0.18), CCGlobalizer.sol (v0.2.1).
*/

pragma solidity ^0.8.2;

import "../imports/IERC20.sol";

interface ICCListing {
    function prices(uint256) external view returns (uint256);
    function volumeBalances(uint256) external view returns (uint256 xBalance, uint256 yBalance);
}

interface ICCAgent {
    function globalizerAddress() external view returns (address);
    function registryAddress() external view returns (address);
}

interface ITokenRegistry {
    function initializeBalances(address token, address[] memory users) external;
}

interface ICCGlobalizer {
    function globalizeLiquidity(address depositor, address token) external;
}

contract CCLiquidityTemplate {
    mapping(address => bool) public routers;
    address[] public routerAddresses;
    bool public routersSet;
    address public listingAddress;
    address public tokenA;
    address public tokenB;
    uint256 public listingId;
    address public agent;

    struct LiquidityDetails {
        uint256 xLiquid;
        uint256 yLiquid;
        uint256 xFees;
        uint256 yFees;
        uint256 xFeesAcc;
        uint256 yFeesAcc;
    }

    struct Slot {
        address depositor;
        address recipient;
        uint256 allocation;
        uint256 dFeesAcc;
        uint256 timestamp;
    }

    struct UpdateType {
        uint8 updateType;
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
    }

    struct PreparedWithdrawal {
        uint256 amountA;
        uint256 amountB;
    }

    LiquidityDetails public liquidityDetail;
    mapping(uint256 => Slot) public xLiquiditySlots;
    mapping(uint256 => Slot) public yLiquiditySlots;
    uint256[] public activeXLiquiditySlots;
    uint256[] public activeYLiquiditySlots;
    mapping(address => uint256[]) public userXIndex;
    mapping(address => uint256[]) public userYIndex;

    event LiquidityUpdated(uint256 indexed listingId, uint256 xLiquid, uint256 yLiquid);
    event FeesUpdated(uint256 indexed listingId, uint256 xFees, uint256 yFees);
    event SlotDepositorChanged(bool isX, uint256 indexed slotIndex, address indexed oldDepositor, address indexed newDepositor);
    event GlobalizeUpdateFailed(address indexed depositor, uint256 listingId, bool isX, uint256 amount, bytes reason);
    event UpdateRegistryFailed(address indexed depositor, bool isX, bytes reason);
    event TransactFailed(address indexed depositor, address token, uint256 amount, string reason);

    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256 normalizedAmount) {
        // Normalizes amount to 18 decimals
        if (decimals == 18) return amount;
        if (decimals < 18) return amount * 10 ** (18 - decimals);
        return amount / 10 ** (decimals - 18);
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256 denormalizedAmount) {
        // Denormalizes amount from 18 decimals
        if (decimals == 18) return amount;
        if (decimals < 18) return amount / 10 ** (18 - decimals);
        return amount * 10 ** (decimals - 18);
    }

    function globalizeUpdate(address depositor, address token, bool isX, uint256 amount) internal {
        // Handles globalization calls to ICCGlobalizer
        if (agent != address(0)) {
            address globalizer;
            try ICCAgent(agent).globalizerAddress{gas: 1000000}() returns (address glob) {
                globalizer = glob;
            } catch (bytes memory reason) {
                emit GlobalizeUpdateFailed(depositor, listingId, isX, amount, reason);
                revert(string(abi.encodePacked("Globalizer address fetch failed: ", reason)));
            }
            if (globalizer != address(0)) {
                try ICCGlobalizer(globalizer).globalizeLiquidity(depositor, token) {
                } catch (bytes memory reason) {
                    emit GlobalizeUpdateFailed(depositor, listingId, isX, amount, reason);
                    revert(string(abi.encodePacked("Globalize update failed: ", reason)));
                }
            }
        }
    }

    function setRouters(address[] memory _routers) external {
        // Sets router addresses, callable once
        require(!routersSet, "Routers already set");
        require(_routers.length > 0, "No routers provided");
        for (uint256 i = 0; i < _routers.length; i++) {
            require(_routers[i] != address(0), "Invalid router address");
            routers[_routers[i]] = true;
            routerAddresses.push(_routers[i]);
        }
        routersSet = true;
    }

    function setListingId(uint256 _listingId) external {
        // Sets listing ID, callable once
        require(listingId == 0, "Listing ID already set");
        listingId = _listingId;
    }

    function setListingAddress(address _listingAddress) external {
        // Sets listing address, callable once
        require(listingAddress == address(0), "Listing already set");
        require(_listingAddress != address(0), "Invalid listing address");
        listingAddress = _listingAddress;
    }

    function setTokens(address _tokenA, address _tokenB) external {
        // Sets token pair, callable once
        require(tokenA == address(0) && tokenB == address(0), "Tokens already set");
        require(_tokenA != _tokenB, "Tokens must be different");
        require(_tokenA != address(0) || _tokenB != address(0), "Both tokens cannot be zero");
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function setAgent(address _agent) external {
        // Sets agent address, callable once
        require(agent == address(0), "Agent already set");
        require(_agent != address(0), "Invalid agent address");
        agent = _agent;
    }

    function update(address depositor, UpdateType[] memory updates) external {
        // Updates liquidity and slot details
        require(routers[msg.sender], "Router only");
        LiquidityDetails storage details = liquidityDetail;
        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0) {
                if (u.index == 0) {
                    require(details.xLiquid >= u.value, "Insufficient xLiquid");
                    details.xLiquid = u.value;
                } else if (u.index == 1) {
                    require(details.yLiquid >= u.value, "Insufficient yLiquid");
                    details.yLiquid = u.value;
                } else revert("Invalid balance index");
            } else if (u.updateType == 1) {
                if (u.index == 0) {
                    details.xFees += u.value;
                    emit FeesUpdated(listingId, details.xFees, details.yFees);
                } else if (u.index == 1) {
                    details.yFees += u.value;
                    emit FeesUpdated(listingId, details.xFees, details.yFees);
                } else revert("Invalid fee index");
            } else if (u.updateType == 2) {
                Slot storage slot = xLiquiditySlots[u.index];
                if (slot.depositor == address(0) && u.addr != address(0)) {
                    slot.depositor = u.addr;
                    slot.timestamp = block.timestamp;
                    slot.dFeesAcc = details.yFeesAcc;
                    activeXLiquiditySlots.push(u.index);
                    userXIndex[u.addr].push(u.index);
                } else if (u.addr == address(0)) {
                    slot.depositor = address(0);
                    slot.allocation = 0;
                    slot.dFeesAcc = 0;
                    for (uint256 j = 0; j < userXIndex[slot.depositor].length; j++) {
                        if (userXIndex[slot.depositor][j] == u.index) {
                            userXIndex[slot.depositor][j] = userXIndex[slot.depositor][userXIndex[slot.depositor].length - 1];
                            userXIndex[slot.depositor].pop();
                            break;
                        }
                    }
                }
                slot.allocation = u.value;
                details.xLiquid += u.value;
                globalizeUpdate(depositor, tokenA, true, u.value);
            } else if (u.updateType == 3) {
                Slot storage slot = yLiquiditySlots[u.index];
                if (slot.depositor == address(0) && u.addr != address(0)) {
                    slot.depositor = u.addr;
                    slot.timestamp = block.timestamp;
                    slot.dFeesAcc = details.xFeesAcc;
                    activeYLiquiditySlots.push(u.index);
                    userYIndex[u.addr].push(u.index);
                } else if (u.addr == address(0)) {
                    slot.depositor = address(0);
                    slot.allocation = 0;
                    slot.dFeesAcc = 0;
                    for (uint256 j = 0; j < userYIndex[slot.depositor].length; j++) {
                        if (userYIndex[slot.depositor][j] == u.index) {
                            userYIndex[slot.depositor][j] = userYIndex[slot.depositor][userYIndex[slot.depositor].length - 1];
                            userYIndex[slot.depositor].pop();
                            break;
                        }
                    }
                }
                slot.allocation = u.value;
                details.yLiquid += u.value;
                globalizeUpdate(depositor, tokenB, false, u.value);
            } else revert("Invalid update type");
        }
        if (agent != address(0)) {
            address registry;
            try ICCAgent(agent).registryAddress{gas: 1000000}() returns (address reg) {
                registry = reg;
            } catch (bytes memory reason) {
                emit UpdateRegistryFailed(depositor, updates[0].updateType == 2, reason);
                revert(string(abi.encodePacked("Agent registry fetch failed: ", reason)));
            }
            if (registry != address(0)) {
                address token = updates[0].updateType == 2 ? tokenA : tokenB;
                address[] memory users = new address[](1);
                users[0] = depositor;
                try ITokenRegistry(registry).initializeBalances{gas: 1000000}(token, users) {
                } catch (bytes memory reason) {
                    emit UpdateRegistryFailed(depositor, updates[0].updateType == 2, reason);
                    revert(string(abi.encodePacked("Registry update failed: ", reason)));
                }
            }
        }
        emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
    }

    function changeSlotDepositor(address depositor, bool isX, uint256 slotIndex, address newDepositor) external {
        // Changes depositor for a liquidity slot
        require(routers[msg.sender], "Router only");
        require(newDepositor != address(0), "Invalid new depositor");
        require(depositor != address(0), "Invalid depositor");
        Slot storage slot = isX ? xLiquiditySlots[slotIndex] : yLiquiditySlots[slotIndex];
        require(slot.depositor == depositor, "Depositor not slot owner");
        require(slot.allocation > 0, "Invalid slot");
        address oldDepositor = slot.depositor;
        slot.depositor = newDepositor;
        mapping(address => uint256[]) storage index = isX ? userXIndex : userYIndex;
        for (uint256 i = 0; i < index[oldDepositor].length; i++) {
            if (index[oldDepositor][i] == slotIndex) {
                index[oldDepositor][i] = index[oldDepositor][index[oldDepositor].length - 1];
                index[oldDepositor].pop();
                break;
            }
        }
        index[newDepositor].push(slotIndex);
        emit SlotDepositorChanged(isX, slotIndex, oldDepositor, newDepositor);
    }

    function transactToken(address depositor, address token, uint256 amount, address recipient) external {
        // Transfers ERC20 tokens to recipient for withdrawal
        require(routers[msg.sender], "Router only");
        require(token != address(0), "Invalid token address");
        uint8 decimals = IERC20(token).decimals();
        uint256 normalizedAmount = normalize(amount, decimals);
        LiquidityDetails storage details = liquidityDetail;
        bool isTokenA = token == tokenA;
        if (isTokenA) {
            require(details.xLiquid >= normalizedAmount, "Insufficient xLiquid");
        } else {
            require(details.yLiquid >= normalizedAmount, "Insufficient yLiquid");
        }
        if (IERC20(token).balanceOf(address(this)) < amount) {
            emit TransactFailed(depositor, token, amount, "Insufficient contract balance");
            revert("Insufficient contract balance");
        }
        if (!IERC20(token).transfer(recipient, amount)) {
            emit TransactFailed(depositor, token, amount, "Transfer failed");
            revert("Transfer failed");
        }
        globalizeUpdate(depositor, token, isTokenA, normalizedAmount);
    }

    function transactNative(address depositor, uint256 amount, address recipient) external payable {
        // Transfers native tokens (ETH) to recipient for withdrawal
        require(routers[msg.sender], "Router only");
        uint256 normalizedAmount = normalize(amount, 18);
        LiquidityDetails storage details = liquidityDetail;
        bool isTokenA = tokenA == address(0);
        if (isTokenA) {
            require(details.xLiquid >= normalizedAmount, "Insufficient xLiquid");
        } else {
            require(details.yLiquid >= normalizedAmount, "Insufficient yLiquid");
        }
        if (address(this).balance < amount) {
            emit TransactFailed(depositor, address(0), amount, "Insufficient contract balance");
            revert("Insufficient contract balance");
        }
        (bool success, bytes memory reason) = recipient.call{value: amount}("");
        if (!success) {
            emit TransactFailed(depositor, address(0), amount, string(reason));
            revert(string(abi.encodePacked("Native transfer failed: ", reason)));
        }
        globalizeUpdate(depositor, address(0), isTokenA, normalizedAmount);
    }

    function updateLiquidity(address depositor, bool isX, uint256 amount) external {
        // Updates liquidity balance
        require(routers[msg.sender], "Router only");
        LiquidityDetails storage details = liquidityDetail;
        if (isX) {
            if (details.xLiquid < amount) revert("Insufficient xLiquid balance");
            details.xLiquid -= amount;
        } else {
            if (details.yLiquid < amount) revert("Insufficient yLiquid balance");
            details.yLiquid -= amount;
        }
        emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
    }

    function xPrepOut(address depositor, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory withdrawal) {
        // Prepares withdrawal for xLiquidity slot
        require(routers[msg.sender], "Router only");
        require(depositor != address(0), "Invalid depositor");
        LiquidityDetails storage details = liquidityDetail;
        Slot storage slot = xLiquiditySlots[index];
        require(slot.depositor == depositor, "Depositor not slot owner");
        require(slot.allocation >= amount, "Amount exceeds allocation");
        uint256 withdrawAmountA = amount > details.xLiquid ? details.xLiquid : amount;
        uint256 deficit = amount > withdrawAmountA ? amount - withdrawAmountA : 0;
        uint256 withdrawAmountB = 0;
        if (deficit > 0) {
            uint256 currentPrice;
            try ICCListing(listingAddress).prices(0) returns (uint256 price) {
                currentPrice = price;
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Price fetch failed: ", reason)));
            }
            if (currentPrice == 0) return PreparedWithdrawal(withdrawAmountA, 0);
            uint256 compensation = (deficit * 1e18) / currentPrice;
            withdrawAmountB = compensation > details.yLiquid ? details.yLiquid : compensation;
        }
        return PreparedWithdrawal(withdrawAmountA, withdrawAmountB);
    }

    function xExecuteOut(address depositor, uint256 index, PreparedWithdrawal memory withdrawal) external {
        // Executes withdrawal for xLiquidity slot
        require(routers[msg.sender], "Router only");
        require(depositor != address(0), "Invalid depositor");
        Slot storage slot = xLiquiditySlots[index];
        require(slot.depositor == depositor, "Depositor not slot owner");
        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(2, index, slot.allocation - withdrawal.amountA, slot.depositor, address(0));
        try this.update(depositor, updates) {
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Withdrawal update failed: ", reason)));
        }
        if (withdrawal.amountA > 0) {
            uint8 decimalsA = tokenA == address(0) ? 18 : IERC20(tokenA).decimals();
            uint256 amountA = denormalize(withdrawal.amountA, decimalsA);
            if (tokenA == address(0)) {
                try this.transactNative(depositor, amountA, depositor) {
                } catch (bytes memory reason) {
                    revert(string(abi.encodePacked("Native withdrawal failed: ", reason)));
                }
            } else {
                try this.transactToken(depositor, tokenA, amountA, depositor) {
                } catch (bytes memory reason) {
                    revert(string(abi.encodePacked("Token withdrawal failed: ", reason)));
                }
            }
        }
        if (withdrawal.amountB > 0) {
            uint8 decimalsB = tokenB == address(0) ? 18 : IERC20(tokenB).decimals();
            uint256 amountB = denormalize(withdrawal.amountB, decimalsB);
            if (tokenB == address(0)) {
                try this.transactNative(depositor, amountB, depositor) {
                } catch (bytes memory reason) {
                    revert(string(abi.encodePacked("Native withdrawal failed: ", reason)));
                }
            } else {
                try this.transactToken(depositor, tokenB, amountB, depositor) {
                } catch (bytes memory reason) {
                    revert(string(abi.encodePacked("Token withdrawal failed: ", reason)));
                }
            }
        }
    }

    function yPrepOut(address depositor, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory withdrawal) {
        // Prepares withdrawal for yLiquidity slot
        require(routers[msg.sender], "Router only");
        require(depositor != address(0), "Invalid depositor");
        LiquidityDetails storage details = liquidityDetail;
        Slot storage slot = yLiquiditySlots[index];
        require(slot.depositor == depositor, "Depositor not slot owner");
        require(slot.allocation >= amount, "Amount exceeds allocation");
        uint256 withdrawAmountB = amount > details.yLiquid ? details.yLiquid : amount;
        uint256 deficit = amount > withdrawAmountB ? amount - withdrawAmountB : 0;
        uint256 withdrawAmountA = 0;
        if (deficit > 0) {
            uint256 currentPrice;
            try ICCListing(listingAddress).prices(0) returns (uint256 price) {
                currentPrice = price;
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Price fetch failed: ", reason)));
            }
            if (currentPrice == 0) return PreparedWithdrawal(0, withdrawAmountB);
            uint256 compensation = (deficit * currentPrice) / 1e18;
            withdrawAmountA = compensation > details.xLiquid ? details.xLiquid : compensation;
        }
        return PreparedWithdrawal(withdrawAmountA, withdrawAmountB);
    }

    function yExecuteOut(address depositor, uint256 index, PreparedWithdrawal memory withdrawal) external {
        // Executes withdrawal for yLiquidity slot
        require(routers[msg.sender], "Router only");
        require(depositor != address(0), "Invalid depositor");
        Slot storage slot = yLiquiditySlots[index];
        require(slot.depositor == depositor, "Depositor not slot owner");
        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(3, index, slot.allocation - withdrawal.amountB, slot.depositor, address(0));
        try this.update(depositor, updates) {
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Withdrawal update failed: ", reason)));
        }
        if (withdrawal.amountB > 0) {
            uint8 decimalsB = tokenB == address(0) ? 18 : IERC20(tokenB).decimals();
            uint256 amountB = denormalize(withdrawal.amountB, decimalsB);
            if (tokenB == address(0)) {
                try this.transactNative(depositor, amountB, depositor) {
                } catch (bytes memory reason) {
                    revert(string(abi.encodePacked("Native withdrawal failed: ", reason)));
                }
            } else {
                try this.transactToken(depositor, tokenB, amountB, depositor) {
                } catch (bytes memory reason) {
                    revert(string(abi.encodePacked("Token withdrawal failed: ", reason)));
                }
            }
        }
        if (withdrawal.amountA > 0) {
            uint8 decimalsA = tokenA == address(0) ? 18 : IERC20(tokenA).decimals();
            uint256 amountA = denormalize(withdrawal.amountA, decimalsA);
            if (tokenA == address(0)) {
                try this.transactNative(depositor, amountA, depositor) {
                } catch (bytes memory reason) {
                    revert(string(abi.encodePacked("Native withdrawal failed: ", reason)));
                }
            } else {
                try this.transactToken(depositor, tokenA, amountA, depositor) {
                } catch (bytes memory reason) {
                    revert(string(abi.encodePacked("Token withdrawal failed: ", reason)));
                }
            }
        }
    }

    function getListingAddress(uint256) external view returns (address listingAddressReturn) {
        // Returns listing address
        return listingAddress;
    }

    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount) {
        // Returns liquidity amounts
        LiquidityDetails memory details = liquidityDetail;
        return (details.xLiquid, details.yLiquid);
    }

    function liquidityDetailsView(address) external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees) {
        // Returns liquidity details for CCSEntryPartial compatibility
        LiquidityDetails memory details = liquidityDetail;
        return (details.xLiquid, details.yLiquid, details.xFees, details.yFees);
    }

    function activeXLiquiditySlotsView() external view returns (uint256[] memory slots) {
        // Returns active xLiquidity slots
        return activeXLiquiditySlots;
    }

    function activeYLiquiditySlotsView() external view returns (uint256[] memory slots) {
        // Returns active yLiquidity slots
        return activeYLiquiditySlots;
    }

    function userXIndexView(address user) external view returns (uint256[] memory indices) {
        // Returns user's xLiquidity slot indices
        return userXIndex[user];
    }

    function userYIndexView(address user) external view returns (uint256[] memory indices) {
        // Returns user's yLiquidity slot indices
        return userYIndex[user];
    }

    function getActiveXLiquiditySlots() external view returns (uint256[] memory slots) {
        // Returns active xLiquidity slots
        return activeXLiquiditySlots;
    }

    function getActiveYLiquiditySlots() external view returns (uint256[] memory slots) {
        // Returns active yLiquidity slots
        return activeYLiquiditySlots;
    }

    function getXSlotView(uint256 index) external view returns (Slot memory slot) {
        // Returns xLiquidity slot details
        return xLiquiditySlots[index];
    }

    function getYSlotView(uint256 index) external view returns (Slot memory slot) {
        // Returns yLiquidity slot details
        return yLiquiditySlots[index];
    }

    function routerAddressesView() external view returns (address[] memory addresses) {
        // Returns router addresses
        return routerAddresses;
    }
}