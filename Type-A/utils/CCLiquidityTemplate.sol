// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.20
// Changes:
// - v0.0.20: Removed depositToken, depositNative, withdraw (xPrepOut, yPrepOut, xExecuteOut, yExecuteOut), claimFees, and changeDepositor, moved to CCLiquidityRouter.sol v0.0.18 via CCLiquidityPartial.sol v0.0.13. Moved globalizeUpdate calls to transactToken and transactNative, updateRegistry calls to update. Updated compatibility comments.
// - v0.0.19: Removed checkRouterInvolved and isRouter, replaced with require(routers[msg.sender], "Router only").
// - v0.0.18: Refactored checkRouterInvolved to check routers mapping.
// - v0.0.17: Modified checkRouterInvolved for router validation.
// Compatible with CCListingTemplate.sol (v0.0.10), CCMainPartial.sol (v0.0.10), CCLiquidityRouter.sol (v0.0.18), ICCLiquidity.sol (v0.0.4), ICCListing.sol (v0.0.7).

import "../imports/IERC20.sol";

interface ICCListing {
    function prices(uint256) external view returns (uint256);
    function volumeBalances(uint256) external view returns (uint256 xBalance, uint256 yBalance);
}

interface ICCAgent {
    function globalizeLiquidity(
        uint256 listingId,
        address tokenA,
        address tokenB,
        address user,
        uint256 amount,
        bool isDeposit
    ) external;
    function registryAddress() external view returns (address);
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
    mapping(address => uint256[]) public userIndex;

    event LiquidityUpdated(uint256 indexed listingId, uint256 xLiquid, uint256 yLiquid);
    event FeesUpdated(uint256 indexed listingId, uint256 xFees, uint256 yFees);
    event SlotDepositorChanged(bool isX, uint256 indexed slotIndex, address indexed oldDepositor, address indexed newDepositor);
    event GlobalizeUpdateFailed(address indexed depositor, uint256 listingId, bool isX, uint256 amount, bytes reason);
    event UpdateRegistryFailed(address indexed depositor, bool isX, bytes reason);
    event TransactFailed(address indexed depositor, address token, uint256 amount, string reason);

    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (uint256(18) - uint256(decimals));
        else return amount / 10 ** (uint256(decimals) - uint256(18));
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10 ** (uint256(18) - uint256(decimals));
        else return amount * 10 ** (uint256(decimals) - uint256(18));
    }

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

    function setListingId(uint256 _listingId) external {
        require(listingId == 0, "Listing ID already set");
        listingId = _listingId;
    }

    function setListingAddress(address _listingAddress) external {
        require(listingAddress == address(0), "Listing already set");
        require(_listingAddress != address(0), "Invalid listing address");
        listingAddress = _listingAddress;
    }

    function setTokens(address _tokenA, address _tokenB) external {
        require(tokenA == address(0) && tokenB == address(0), "Tokens already set");
        require(_tokenA != _tokenB, "Tokens must be different");
        require(_tokenA != address(0) || _tokenB != address(0), "Both tokens cannot be zero");
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function setAgent(address _agent) external {
        require(agent == address(0), "Agent already set");
        require(_agent != address(0), "Invalid agent address");
        agent = _agent;
    }

    function update(address depositor, UpdateType[] memory updates) external {
        require(routers[msg.sender], "Router only");
        LiquidityDetails storage details = liquidityDetail;
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
            } else revert("Invalid update type");
        }
        if (agent != address(0)) {
            address registry;
            try ICCAgent(agent).registryAddress{gas: 1_000_000}() returns (address reg) {
                registry = reg;
            } catch (bytes memory reason) {
                emit UpdateRegistryFailed(depositor, updates[0].updateType == 2, reason);
                revert(string(abi.encodePacked("Agent registry fetch failed: ", reason)));
            }
            if (registry != address(0)) {
                address token = updates[0].updateType == 2 ? tokenA : tokenB;
                address[] memory users = new address[](1);
                users[0] = depositor;
                try ITokenRegistry(registry).initializeBalances{gas: 1_000_000}(token, users) {
                } catch (bytes memory reason) {
                    emit UpdateRegistryFailed(depositor, updates[0].updateType == 2, reason);
                    revert(string(abi.encodePacked("Registry update failed: ", reason)));
                }
            }
        }
        emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
    }

    function changeSlotDepositor(address depositor, bool isX, uint256 slotIndex, address newDepositor) external {
        require(routers[msg.sender], "Router only");
        require(newDepositor != address(0), "Invalid new depositor");
        require(depositor != address(0), "Invalid depositor");
        Slot storage slot = isX ? xLiquiditySlots[slotIndex] : yLiquiditySlots[slotIndex];
        require(slot.depositor == depositor, "Depositor not slot owner");
        require(slot.allocation > 0, "Invalid slot");
        address oldDepositor = slot.depositor;
        slot.depositor = newDepositor;
        for (uint256 i = 0; i < userIndex[oldDepositor].length; i++) {
            if (userIndex[oldDepositor][i] == slotIndex) {
                userIndex[oldDepositor][i] = userIndex[oldDepositor][userIndex[oldDepositor].length - 1];
                userIndex[oldDepositor].pop();
                break;
            }
        }
        userIndex[newDepositor].push(slotIndex);
        emit SlotDepositorChanged(isX, slotIndex, oldDepositor, newDepositor);
    }

    function addFees(address depositor, bool isX, uint256 fee) external {
        require(routers[msg.sender], "Router only");
        if (fee == 0) revert("Zero fee amount");
        LiquidityDetails storage details = liquidityDetail;
        UpdateType[] memory feeUpdates = new UpdateType[](1);
        feeUpdates[0] = UpdateType(1, isX ? 0 : 1, fee, address(0), address(0));
        if (isX) {
            details.xFeesAcc += fee;
        } else {
            details.yFeesAcc += fee;
        }
        try this.update(depositor, feeUpdates) {
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Fee update failed: ", reason)));
        }
        emit FeesUpdated(listingId, details.xFees, details.yFees);
    }

    function transactToken(address depositor, address token, uint256 amount, address recipient) external {
        require(routers[msg.sender], "Router only");
        require(token == tokenA || token == tokenB, "Invalid token");
        require(token != address(0), "Use transactNative for ETH");
        require(amount > 0, "Zero amount");
        require(recipient != address(0), "Invalid recipient");
        LiquidityDetails storage details = liquidityDetail;
        uint8 decimals = IERC20(token).decimals();
        if (decimals == 0) revert("Invalid token decimals");
        uint256 normalizedAmount = normalize(amount, decimals);
        if (token == tokenA) {
            if (details.xLiquid < normalizedAmount) revert("Insufficient xLiquid balance");
            details.xLiquid -= normalizedAmount;
        } else {
            if (details.yLiquid < normalizedAmount) revert("Insufficient yLiquid balance");
            details.yLiquid -= normalizedAmount;
        }
        try IERC20(token).transfer(recipient, amount) returns (bool) {
        } catch (bytes memory reason) {
            emit TransactFailed(depositor, token, amount, "Token transfer failed");
            revert("Token transfer failed");
        }
        if (agent != address(0)) {
            try ICCAgent(agent).globalizeLiquidity{gas: 1_000_000}(
                listingId,
                tokenA,
                tokenB,
                depositor,
                normalizedAmount,
                false
            ) {
            } catch (bytes memory reason) {
                emit GlobalizeUpdateFailed(depositor, listingId, token == tokenA, amount, reason);
                revert(string(abi.encodePacked("Globalize update failed: ", reason)));
            }
        }
        emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
    }

    function transactNative(address depositor, uint256 amount, address recipient) external {
        require(routers[msg.sender], "Router only");
        require(tokenA == address(0) || tokenB == address(0), "No native token in pair");
        require(amount > 0, "Zero amount");
        require(recipient != address(0), "Invalid recipient");
        LiquidityDetails storage details = liquidityDetail;
        uint256 normalizedAmount = normalize(amount, 18);
        if (tokenA == address(0)) {
            if (details.xLiquid < normalizedAmount) revert("Insufficient xLiquid balance");
            details.xLiquid -= normalizedAmount;
        } else {
            if (details.yLiquid < normalizedAmount) revert("Insufficient yLiquid balance");
            details.yLiquid -= normalizedAmount;
        }
        (bool success, bytes memory reason) = recipient.call{value: amount}("");
        if (!success) {
            emit TransactFailed(depositor, address(0), amount, "ETH transfer failed");
            revert("ETH transfer failed");
        }
        if (agent != address(0)) {
            try ICCAgent(agent).globalizeLiquidity{gas: 1_000_000}(
                listingId,
                tokenA,
                tokenB,
                depositor,
                normalizedAmount,
                false
            ) {
            } catch (bytes memory reason) {
                emit GlobalizeUpdateFailed(depositor, listingId, tokenA == address(0), amount, reason);
                revert(string(abi.encodePacked("Globalize update failed: ", reason)));
            }
        }
        emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
    }

    function updateLiquidity(address depositor, bool isX, uint256 amount) external {
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

    function getListingAddress(uint256) external view returns (address) {
        return listingAddress;
    }

    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount) {
        LiquidityDetails memory details = liquidityDetail;
        return (details.xLiquid, details.yLiquid);
    }

    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, uint256 xFeesAcc, uint256 yFeesAcc) {
        LiquidityDetails memory details = liquidityDetail;
        return (details.xLiquid, details.yLiquid, details.xFees, details.yFees, details.xFeesAcc, details.yFeesAcc);
    }

    function activeXLiquiditySlotsView() external view returns (uint256[] memory) {
        return activeXLiquiditySlots;
    }

    function activeYLiquiditySlotsView() external view returns (uint256[] memory) {
        return activeYLiquiditySlots;
    }

    function userIndexView(address user) external view returns (uint256[] memory) {
        return userIndex[user];
    }

    function getXSlotView(uint256 index) external view returns (Slot memory) {
        return xLiquiditySlots[index];
    }

    function getYSlotView(uint256 index) external view returns (Slot memory) {
        return yLiquiditySlots[index];
    }

    function routerAddressesView() external view returns (address[] memory) {
        return routerAddresses;
    }
}