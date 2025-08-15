// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.3
// Changes:
// - v0.1.3: Removed redundant view functions (activeXLiquiditySlotsView, activeYLiquiditySlotsView, getXSlotView, getYSlotView, routerAddressesView) as public mappings/arrays have auto-generated getters.
// - v0.1.2: Added changeSlotDepositor, addFees, userXIndexView, userYIndexView, getActiveXLiquiditySlots, getActiveYLiquiditySlots to match CCLiquidityTemplateDocs.md.
// - v0.1.1: Removed listingAddress() function to resolve DeclarationError, as public listingAddress variable auto-generates getter.
// - v0.0.22: Modified globalization to occur only in update function, fetching globalizer address from listing contract (ICCListingTemplate.globalizerAddressView). Removed globalizeLiquidity calls from updateLiquidity, transactToken, transactNative.
// - v0.0.21: Renamed getListingAddress(uint256) to listingAddress() with no parameters to match CCGlobalizer.sol (v0.2.0) expectations in globalizeLiquidity.
// - v0.0.20: Removed depositToken, depositNative, withdraw, claimFees, changeDepositor, moved to CCLiquidityRouter.sol v0.0.18. Moved globalizeUpdate to transactToken/transactNative, updateRegistry to update.
// - v0.0.19: Removed checkRouterInvolved, isRouter, replaced with routers mapping check.
// - v0.0.18: Refactored checkRouterInvolved for router validation.
// - v0.0.17: Modified checkRouterInvolved for router validation.
// Compatible with CCListingTemplate.sol (v0.1.4), CCMainPartial.sol (v0.0.14), CCLiquidityRouter.sol (v0.0.18), ICCLiquidity.sol (v0.0.4), ICCListing.sol (v0.0.7), CCGlobalizer.sol (v0.2.0).

import "../imports/IERC20.sol";

interface ICCListing {
    function prices(uint256) external view returns (uint256);
    function volumeBalances(uint256) external view returns (uint256 xBalance, uint256 yBalance);
    function globalizerAddressView() external view returns (address globalizerAddress);
}

interface ICCAgent {
    function registryAddress() external view returns (address);
}

interface ICCGlobalizer {
    function globalizeLiquidity(address depositor, address token) external;
}

interface ITokenRegistry {
    function initializeBalances(address token, address[] memory users) external;
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
        uint256 xLiquid; // Normalized tokenA liquidity
        uint256 yLiquid; // Normalized tokenB liquidity
        uint256 xFees; // Normalized tokenA fees
        uint256 yFees; // Normalized tokenB fees
        uint256 xFeesAcc; // Accumulated tokenA fees
        uint256 yFeesAcc; // Accumulated tokenB fees
    }

    struct Slot {
        address depositor; // Address providing liquidity
        address recipient; // Address receiving withdrawals
        uint256 allocation; // Normalized liquidity amount
        uint256 dFeesAcc; // Accumulated fees at deposit
        uint256 timestamp; // Deposit timestamp
    }

    struct UpdateType {
        uint8 updateType; // 0: Liquidity, 1: Fees, 2: xSlot, 3: ySlot
        uint256 index; // Slot index or 0/1 for x/y fees/liquidity
        uint256 value; // Normalized amount
        address addr; // Depositor address
        address recipient; // Recipient address
    }

    struct PreparedWithdrawal {
        uint256 amountA; // Normalized tokenA withdrawal amount
        uint256 amountB; // Normalized tokenB withdrawal amount
    }

    LiquidityDetails public liquidityDetail;
    mapping(uint256 => Slot) public xLiquiditySlots;
    mapping(uint256 => Slot) public yLiquiditySlots;
    uint256[] public activeXLiquiditySlots;
    uint256[] public activeYLiquiditySlots;
    mapping(address => uint256[]) private userIndex;

    event LiquidityUpdated(uint256 indexed listingId, uint256 xLiquid, uint256 yLiquid);
    event FeesUpdated(uint256 indexed listingId, uint256 xFees, uint256 yFees);
    event SlotDepositorChanged(bool isX, uint256 indexed slotIndex, address indexed oldDepositor, address indexed newDepositor);
    event GlobalizeUpdateFailed(address indexed depositor, uint256 listingId, bool isX, uint256 amount, bytes reason);
    event UpdateRegistryFailed(address indexed depositor, bool isX, bytes reason);
    event TransactFailed(address indexed depositor, address token, uint256 amount, string reason);

    // Normalizes amount to 1e18 based on token decimals
    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (uint256(18) - uint256(decimals));
        else return amount / 10 ** (uint256(decimals) - uint256(18));
    }

    // Denormalizes amount from 1e18 to token decimals
    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10 ** (uint256(18) - uint256(decimals));
        else return amount * 10 ** (uint256(decimals) - uint256(18));
    }

    // Sets authorized routers
    function setRouters(address[] memory _routers) external {
        require(!routersSet, "Routers already set");
        require(_routers.length > 0, "No routers provided");
        for (uint256 i = 0; i < _routers.length; i++) {
            require(_routers[i] != address(0), "Invalid router address");
            routers[_routers[i]] = true;
            routerAddresses.push(_routers[i]);
        }
        routersSet = true;
    }

    // Sets listing ID
    function setListingId(uint256 _listingId) external {
        require(listingId == 0, "Listing ID already set");
        listingId = _listingId;
    }

    // Sets listing contract address
    function setListingAddress(address _listingAddress) external {
        require(listingAddress == address(0), "Listing already set");
        require(_listingAddress != address(0), "Invalid listing address");
        listingAddress = _listingAddress;
    }

    // Sets tokenA and tokenB addresses
    function setTokens(address _tokenA, address _tokenB) external {
        require(tokenA == address(0) && tokenB == address(0), "Tokens already set");
        require(_tokenA != _tokenB, "Tokens must be different");
        require(_tokenA != address(0) || _tokenB != address(0), "Both tokens cannot be zero");
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    // Sets agent contract address
    function setAgent(address _agent) external {
        require(agent == address(0), "Agent already set");
        require(_agent != address(0), "Invalid agent address");
        agent = _agent;
    }

    // Updates liquidity or fees
    function update(address depositor, UpdateType[] memory updates) external {
        require(routers[msg.sender], "Router only");
        LiquidityDetails storage details = liquidityDetail;
        address globalizer = ICCListing(listingAddress).globalizerAddressView();
        require(globalizer != address(0), "Globalizer not set");
        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0) {
                if (u.index == 0) details.xLiquid = u.value;
                else if (u.index == 1) details.yLiquid = u.value;
                else revert("Invalid balance index");
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
                    userIndex[u.addr].push(u.index);
                } else if (u.addr == address(0)) {
                    slot.depositor = address(0);
                    slot.allocation = 0;
                    slot.dFeesAcc = 0;
                    for (uint256 j = 0; j < userIndex[slot.depositor].length; j++) {
                        if (userIndex[slot.depositor][j] == u.index) {
                            userIndex[slot.depositor][j] = userIndex[slot.depositor][userIndex[slot.depositor].length - 1];
                            userIndex[slot.depositor].pop();
                            break;
                        }
                    }
                }
                slot.allocation = u.value;
                details.xLiquid += u.value;
                try ICCGlobalizer(globalizer).globalizeLiquidity(u.addr, tokenA) {} catch (bytes memory reason) {
                    emit GlobalizeUpdateFailed(u.addr, listingId, true, u.value, reason);
                }
            } else if (u.updateType == 3) {
                Slot storage slot = yLiquiditySlots[u.index];
                if (slot.depositor == address(0) && u.addr != address(0)) {
                    slot.depositor = u.addr;
                    slot.timestamp = block.timestamp;
                    slot.dFeesAcc = details.xFeesAcc;
                    activeYLiquiditySlots.push(u.index);
                    userIndex[u.addr].push(u.index);
                } else if (u.addr == address(0)) {
                    slot.depositor = address(0);
                    slot.allocation = 0;
                    slot.dFeesAcc = 0;
                    for (uint256 j = 0; j < userIndex[slot.depositor].length; j++) {
                        if (userIndex[slot.depositor][j] == u.index) {
                            userIndex[slot.depositor][j] = userIndex[slot.depositor][userIndex[slot.depositor].length - 1];
                            userIndex[slot.depositor].pop();
                            break;
                        }
                    }
                }
                slot.allocation = u.value;
                details.yLiquid += u.value;
                try ICCGlobalizer(globalizer).globalizeLiquidity(u.addr, tokenB) {} catch (bytes memory reason) {
                    emit GlobalizeUpdateFailed(u.addr, listingId, false, u.value, reason);
                }
            } else revert("Invalid update type");
        }
        emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
        if (agent != address(0)) {
            address[] memory users = new address[](1);
            users[0] = depositor;
            try ITokenRegistry(ICCAgent(agent).registryAddress()).initializeBalances(tokenA, users) {} catch (bytes memory reason) {
                emit UpdateRegistryFailed(depositor, true, reason);
            }
            try ITokenRegistry(ICCAgent(agent).registryAddress()).initializeBalances(tokenB, users) {} catch (bytes memory reason) {
                emit UpdateRegistryFailed(depositor, false, reason);
            }
        }
    }

    // Updates liquidity balance
    function updateLiquidity(address depositor, bool isX, uint256 amount) external {
        require(routers[msg.sender], "Router only");
        LiquidityDetails storage details = liquidityDetail;
        if (isX) {
            details.xLiquid += amount;
        } else {
            details.yLiquid += amount;
        }
        emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
    }

    // Transfers slot ownership
    function changeSlotDepositor(address depositor, bool isX, uint256 slotIndex, address newDepositor) external {
        require(routers[msg.sender], "Router only");
        require(depositor != address(0) && newDepositor != address(0), "Invalid depositor");
        Slot storage slot = isX ? xLiquiditySlots[slotIndex] : yLiquiditySlots[slotIndex];
        require(slot.depositor == depositor, "Depositor not slot owner");
        address globalizer = ICCListing(listingAddress).globalizerAddressView();
        require(globalizer != address(0), "Globalizer not set");
        slot.depositor = newDepositor;
        for (uint256 i = 0; i < userIndex[depositor].length; i++) {
            if (userIndex[depositor][i] == slotIndex) {
                userIndex[depositor][i] = userIndex[depositor][userIndex[depositor].length - 1];
                userIndex[depositor].pop();
                break;
            }
        }
        userIndex[newDepositor].push(slotIndex);
        emit SlotDepositorChanged(isX, slotIndex, depositor, newDepositor);
        try ICCGlobalizer(globalizer).globalizeLiquidity(depositor, isX ? tokenA : tokenB) {} catch (bytes memory reason) {
            emit GlobalizeUpdateFailed(depositor, listingId, isX, slot.allocation, reason);
        }
        try ICCGlobalizer(globalizer).globalizeLiquidity(newDepositor, isX ? tokenA : tokenB) {} catch (bytes memory reason) {
            emit GlobalizeUpdateFailed(newDepositor, listingId, isX, slot.allocation, reason);
        }
    }

    // Adds fees to xFees or yFees
    function addFees(address depositor, bool isX, uint256 fee) external {
        require(routers[msg.sender], "Router only");
        require(fee > 0, "Non-zero fee required");
        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType({
            updateType: 1,
            index: isX ? 0 : 1,
            value: fee,
            addr: depositor,
            recipient: address(0)
        });
        try this.update(depositor, updates) {
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Fee update failed: ", reason)));
        }
    }

    // Prepares withdrawal for tokenA
    function xPrepOut(address depositor, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory) {
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

    // Executes withdrawal for tokenA
    function xExecuteOut(address depositor, uint256 index, PreparedWithdrawal memory withdrawal) external {
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

    // Prepares withdrawal for tokenB
    function yPrepOut(address depositor, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory) {
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

    // Executes withdrawal for tokenB
    function yExecuteOut(address depositor, uint256 index, PreparedWithdrawal memory withdrawal) external {
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

    // Transfers ERC20 tokens
    function transactToken(address depositor, address token, uint256 amount, address recipient) external {
        require(routers[msg.sender], "Router only");
        require(token != address(0), "Invalid token");
        try IERC20(token).transfer(recipient, amount) {
        } catch (bytes memory reason) {
            emit TransactFailed(depositor, token, amount, string(abi.encodePacked("Token transfer failed: ", reason)));
        }
    }

    // Transfers native ETH
    function transactNative(address depositor, uint256 amount, address recipient) external {
        require(routers[msg.sender], "Router only");
        (bool success, bytes memory reason) = recipient.call{value: amount}("");
        if (!success) {
            emit TransactFailed(depositor, address(0), amount, string(abi.encodePacked("Native transfer failed: ", reason)));
        }
    }

    // Returns total liquidity amounts
    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount) {
        LiquidityDetails memory details = liquidityDetail;
        return (details.xLiquid, details.yLiquid);
    }

    // Returns liquidity details
    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, uint256 xFeesAcc, uint256 yFeesAcc) {
        LiquidityDetails memory details = liquidityDetail;
        return (details.xLiquid, details.yLiquid, details.xFees, details.yFees, details.xFeesAcc, details.yFeesAcc);
    }

    // Returns active x liquidity slots with pagination
    function getActiveXLiquiditySlots(uint256 maxIterations) external view returns (uint256[] memory slots) {
        uint256 length = activeXLiquiditySlots.length;
        uint256 iterations = maxIterations < length ? maxIterations : length;
        slots = new uint256[](iterations);
        for (uint256 i = 0; i < iterations; i++) {
            slots[i] = activeXLiquiditySlots[i];
        }
        return slots;
    }

    // Returns active y liquidity slots with pagination
    function getActiveYLiquiditySlots(uint256 maxIterations) external view returns (uint256[] memory slots) {
        uint256 length = activeYLiquiditySlots.length;
        uint256 iterations = maxIterations < length ? maxIterations : length;
        slots = new uint256[](iterations);
        for (uint256 i = 0; i < iterations; i++) {
            slots[i] = activeYLiquiditySlots[i];
        }
        return slots;
    }

    // Returns user x slot indices
    function userXIndexView(address user) external view returns (uint256[] memory indices) {
        uint256[] memory userIndices = userIndex[user];
        uint256 count = 0;
        for (uint256 i = 0; i < userIndices.length; i++) {
            if (xLiquiditySlots[userIndices[i]].depositor == user) {
                count++;
            }
        }
        indices = new uint256[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < userIndices.length; i++) {
            if (xLiquiditySlots[userIndices[i]].depositor == user) {
                indices[j] = userIndices[i];
                j++;
            }
        }
        return indices;
    }

    // Returns user y slot indices
    function userYIndexView(address user) external view returns (uint256[] memory indices) {
        uint256[] memory userIndices = userIndex[user];
        uint256 count = 0;
        for (uint256 i = 0; i < userIndices.length; i++) {
            if (yLiquiditySlots[userIndices[i]].depositor == user) {
                count++;
            }
        }
        indices = new uint256[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < userIndices.length; i++) {
            if (yLiquiditySlots[userIndices[i]].depositor == user) {
                indices[j] = userIndices[i];
                j++;
            }
        }
        return indices;
    }
}