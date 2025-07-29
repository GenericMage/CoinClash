// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.11
// Changes:
// - v0.0.11: Fixed typo in yPrepOut (line 520), changed 'withrawAmountA' to 'withdrawAmountA' to resolve DeclarationError.
// - v0.0.10: Changed updateRegistry from internal to external to fix TypeError in depositToken, depositNative, xExecuteOut, and yExecuteOut.
// - v0.0.9: Changed globalizeUpdate from internal to external to fix TypeError in depositToken, depositNative, xExecuteOut, and yExecuteOut.
// - v0.0.8: Replaced ICCLiquidity interface with inline ICCListing interface, correcting getPrice and volumeBalances calls to match CCListingTemplate.sol v0.0.6.
// - v0.0.7: Updated updateRegistry to fetch registry address from ICCAgent.registryAddress.
// - v0.0.6: Added detailed revert strings in depositToken, depositNative, transactToken, transactNative, update, xExecuteOut, yExecuteOut, claimFees, addFees. Added DepositFailed and TransactFailed events.
// - v0.0.5: Replaced inline IERC20 interface with import from "../imports/IERC20.sol".
// - v0.0.4: Removed SafeERC20, used direct IERC20.transfer/transferFrom.
// - v0.0.3: Updated ICCAgent for native ETH pairs.
// - v0.0.2: Added support for zero-balance pool deposits.
// - v0.0.1: Fixed syntax errors, renamed to CCLiquidityTemplate.

import "../imports/ReentrancyGuard.sol";
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

contract CCLiquidityTemplate is ReentrancyGuard {
    mapping(address => bool) public routers;
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

    struct FeeClaimContext {
        address caller;
        bool isX;
        uint256 liquid;
        uint256 allocation;
        uint256 fees;
        uint256 dFeesAcc;
        uint256 liquidityIndex;
    }

    LiquidityDetails public liquidityDetail;
    mapping(uint256 => Slot) public xLiquiditySlots;
    mapping(uint256 => Slot) public yLiquiditySlots;
    uint256[] public activeXLiquiditySlots;
    uint256[] public activeYLiquiditySlots;
    mapping(address => uint256[]) public userIndex;

    event LiquidityUpdated(uint256 indexed listingId, uint256 xLiquid, uint256 yLiquid);
    event FeesUpdated(uint256 indexed listingId, uint256 xFees, uint256 yFees);
    event FeesClaimed(uint256 indexed listingId, uint256 liquidityIndex, uint256 xFees, uint256 yFees);
    event SlotDepositorChanged(bool isX, uint256 indexed slotIndex, address indexed oldDepositor, address indexed newDepositor);
    event GlobalizeUpdateFailed(address indexed caller, uint256 listingId, bool isX, uint256 amount, bytes reason);
    event UpdateRegistryFailed(address indexed caller, bool isX, bytes reason);
    event DepositReceived(address indexed caller, address token, uint256 amount, uint256 normalizedAmount);
    event DepositFailed(address indexed caller, address token, uint256 amount, string reason);
    event TransactFailed(address indexed caller, address token, uint256 amount, string reason);

    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        // Normalizes amount to 18 decimals
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (uint256(18) - uint256(decimals));
        else return amount / 10 ** (uint256(decimals) - uint256(18));
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        // Denormalizes amount from 18 decimals
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10 ** (uint256(18) - uint256(decimals));
        else return amount * 10 ** (uint256(decimals) - uint256(18));
    }

    function _claimFeeShare(
        uint256 fees,
        uint256 dFeesAcc,
        uint256 liquid,
        uint256 allocation
    ) private pure returns (uint256 feeShare, UpdateType[] memory updates) {
        // Calculates fee share for a slot
        updates = new UpdateType[](2);
        uint256 contributedFees = fees > dFeesAcc ? fees - dFeesAcc : 0;
        uint256 liquidityContribution = liquid > 0 ? (allocation * 1e18) / liquid : 0;
        feeShare = (contributedFees * liquidityContribution) / 1e18;
        feeShare = feeShare > fees ? fees : feeShare;
        return (feeShare, updates);
    }

    function _processFeeClaim(FeeClaimContext memory context) internal {
        // Processes fee claim for a slot
        (uint256 feeShare, UpdateType[] memory updates) = _claimFeeShare(
            context.fees,
            context.dFeesAcc,
            context.liquid,
            context.allocation
        );
        if (feeShare == 0) revert("No fees to claim");
        address transferToken = context.isX ? tokenA : tokenB;
        updates[0] = UpdateType(1, context.isX ? 1 : 0, context.fees - feeShare, address(0), address(0));
        updates[1] = UpdateType(context.isX ? 2 : 3, context.liquidityIndex, context.allocation, context.caller, address(0));
        Slot storage slot = context.isX ? xLiquiditySlots[context.liquidityIndex] : yLiquiditySlots[context.liquidityIndex];
        slot.dFeesAcc = context.isX ? liquidityDetail.yFeesAcc : liquidityDetail.xFeesAcc;
        try this.update(context.caller, updates) {
            // Successful update
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Fee claim update failed: ", reason)));
        }
        try this.transactToken(context.caller, transferToken, feeShare, context.caller) {
            // Successful transfer
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Fee claim transfer failed: ", reason)));
        }
        emit FeesClaimed(listingId, context.liquidityIndex, context.isX ? feeShare : 0, context.isX ? 0 : feeShare);
    }

    function setRouters(address[] memory _routers) external {
        // Sets router addresses
        require(!routersSet, "Routers already set");
        require(_routers.length > 0, "No routers provided");
        for (uint256 i = 0; i < _routers.length; i++) {
            require(_routers[i] != address(0), "Invalid router address");
            routers[_routers[i]] = true;
        }
        routersSet = true;
    }

    function setListingId(uint256 _listingId) external {
        // Sets listing ID
        require(listingId == 0, "Listing ID already set");
        listingId = _listingId;
    }

    function setListingAddress(address _listingAddress) external {
        // Sets listing address
        require(listingAddress == address(0), "Listing already set");
        require(_listingAddress != address(0), "Invalid listing address");
        listingAddress = _listingAddress;
    }

    function setTokens(address _tokenA, address _tokenB) external {
        // Sets token addresses
        require(tokenA == address(0) && tokenB == address(0), "Tokens already set");
        require(_tokenA != _tokenB, "Tokens must be different");
        require(_tokenA != address(0) || _tokenB != address(0), "Both tokens cannot be zero");
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function setAgent(address _agent) external {
        // Sets agent address
        require(agent == address(0), "Agent already set");
        require(_agent != address(0), "Invalid agent address");
        agent = _agent;
    }

    function update(address caller, UpdateType[] memory updates) external nonReentrant {
        // Updates balances, fees, or slots
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
        emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
    }

    function globalizeUpdate(address caller, bool isX, uint256 amount, bool isDeposit) external {
        // Updates agent with liquidity changes
        if (agent == address(0)) revert("Agent not set");
        address token = isX ? tokenA : tokenB;
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 normalizedAmount = normalize(amount, decimals);
        try ICCAgent(agent).globalizeLiquidity(
            listingId,
            tokenA,
            tokenB,
            caller,
            normalizedAmount,
            isDeposit
        ) {} catch (bytes memory reason) {
            emit GlobalizeUpdateFailed(caller, listingId, isX, amount, reason);
            revert(string(abi.encodePacked("Globalize update failed: ", reason)));
        }
    }

    function updateRegistry(address caller, bool isX) external {
        // Updates token registry using agent
        if (agent == address(0)) revert("Agent not set");
        address registry;
        try ICCAgent(agent).registryAddress() returns (address reg) {
            registry = reg;
        } catch (bytes memory reason) {
            emit UpdateRegistryFailed(caller, isX, reason);
            revert(string(abi.encodePacked("Agent registry fetch failed: ", reason)));
        }
        if (registry == address(0)) revert("Registry not set");
        address token = isX ? tokenA : tokenB;
        address[] memory users = new address[](1);
        users[0] = caller;
        try ITokenRegistry(registry).initializeBalances(token, users) {} catch (bytes memory reason) {
            emit UpdateRegistryFailed(caller, isX, reason);
            revert(string(abi.encodePacked("Registry update failed: ", reason)));
        }
    }

    function changeSlotDepositor(address caller, bool isX, uint256 slotIndex, address newDepositor) external nonReentrant {
        // Changes slot depositor
        require(routers[msg.sender], "Router only");
        require(newDepositor != address(0), "Invalid new depositor");
        require(caller != address(0), "Invalid caller");
        Slot storage slot = isX ? xLiquiditySlots[slotIndex] : yLiquiditySlots[slotIndex];
        require(slot.depositor == caller, "Caller not depositor");
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

    function depositToken(address caller, address token, uint256 amount) external nonReentrant {
        // Handles ERC20 token deposits
        require(routers[msg.sender], "Router only");
        require(token == tokenA || token == tokenB, "Invalid token");
        require(token != address(0), "Use depositNative for ETH");
        require(caller != address(0), "Invalid caller");
        uint8 decimals = IERC20(token).decimals();
        if (decimals == 0) revert("Invalid token decimals");
        uint256 preBalance = IERC20(token).balanceOf(address(this));
        try IERC20(token).transferFrom(msg.sender, address(this), amount) returns (bool) {
            // Balance checks ensure success
        } catch (bytes memory reason) {
            emit DepositFailed(caller, token, amount, "TransferFrom failed");
            revert("Token transferFrom failed");
        }
        uint256 postBalance = IERC20(token).balanceOf(address(this));
        uint256 receivedAmount = postBalance - preBalance;
        if (receivedAmount == 0) revert("No tokens received");
        uint256 normalizedAmount = normalize(receivedAmount, decimals);
        UpdateType[] memory updates = new UpdateType[](1);
        uint256 index = token == tokenA ? activeXLiquiditySlots.length : activeYLiquiditySlots.length;
        updates[0] = UpdateType(token == tokenA ? 2 : 3, index, normalizedAmount, caller, address(0));
        try this.update(caller, updates) {
            // Successful update
        } catch (bytes memory reason) {
            emit DepositFailed(caller, token, receivedAmount, "Update failed");
            revert(string(abi.encodePacked("Deposit update failed: ", reason)));
        }
        try this.globalizeUpdate(caller, token == tokenA, receivedAmount, true) {
            // Successful globalize
        } catch (bytes memory reason) {
            emit DepositFailed(caller, token, receivedAmount, "Globalize update failed");
            revert(string(abi.encodePacked("Globalize update failed: ", reason)));
        }
        try this.updateRegistry(caller, token == tokenA) {
            // Successful registry update
        } catch (bytes memory reason) {
            emit DepositFailed(caller, token, receivedAmount, "Registry update failed");
            revert(string(abi.encodePacked("Registry update failed: ", reason)));
        }
        emit DepositReceived(caller, token, receivedAmount, normalizedAmount);
    }

    function depositNative(address caller, uint256 amount) external payable nonReentrant {
        // Handles ETH deposits
        require(routers[msg.sender], "Router only");
        require(tokenA == address(0) || tokenB == address(0), "No native token in pair");
        require(caller != address(0), "Invalid caller");
        require(msg.value == amount, "Incorrect ETH amount");
        uint256 normalizedAmount = normalize(amount, 18);
        UpdateType[] memory updates = new UpdateType[](1);
        uint256 index = tokenA == address(0) ? activeXLiquiditySlots.length : activeYLiquiditySlots.length;
        updates[0] = UpdateType(tokenA == address(0) ? 2 : 3, index, normalizedAmount, caller, address(0));
        try this.update(caller, updates) {
            // Successful update
        } catch (bytes memory reason) {
            emit DepositFailed(caller, address(0), amount, "Update failed");
            revert(string(abi.encodePacked("Deposit update failed: ", reason)));
        }
        try this.globalizeUpdate(caller, tokenA == address(0), amount, true) {
            // Successful globalize
        } catch (bytes memory reason) {
            emit DepositFailed(caller, address(0), amount, "Globalize update failed");
            revert(string(abi.encodePacked("Globalize update failed: ", reason)));
        }
        try this.updateRegistry(caller, tokenA == address(0)) {
            // Successful registry update
        } catch (bytes memory reason) {
            emit DepositFailed(caller, address(0), amount, "Registry update failed");
            revert(string(abi.encodePacked("Registry update failed: ", reason)));
        }
        emit DepositReceived(caller, address(0), amount, normalizedAmount);
    }

    function xPrepOut(address caller, uint256 amount, uint256 index) external nonReentrant returns (PreparedWithdrawal memory) {
        // Prepares x-token withdrawal
        require(routers[msg.sender], "Router only");
        require(caller != address(0), "Invalid caller");
        LiquidityDetails storage details = liquidityDetail;
        Slot storage slot = xLiquiditySlots[index];
        require(slot.depositor == caller, "Caller not depositor");
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

    function xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external nonReentrant {
        // Executes x-token withdrawal
        require(routers[msg.sender], "Router only");
        require(caller != address(0), "Invalid caller");
        Slot storage slot = xLiquiditySlots[index];
        require(slot.depositor == caller, "Caller not depositor");
        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(2, index, slot.allocation - withdrawal.amountA, slot.depositor, address(0));
        try this.update(caller, updates) {
            // Successful update
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Withdrawal update failed: ", reason)));
        }
        if (withdrawal.amountA > 0) {
            uint8 decimalsA = tokenA == address(0) ? 18 : IERC20(tokenA).decimals();
            uint256 amountA = denormalize(withdrawal.amountA, decimalsA);
            if (tokenA == address(0)) {
                try this.transactNative(caller, amountA, caller) {
                    // Successful transfer
                } catch (bytes memory reason) {
                    revert(string(abi.encodePacked("Native withdrawal failed: ", reason)));
                }
            } else {
                try this.transactToken(caller, tokenA, amountA, caller) {
                    // Successful transfer
                } catch (bytes memory reason) {
                    revert(string(abi.encodePacked("Token withdrawal failed: ", reason)));
                }
            }
            try this.globalizeUpdate(caller, true, withdrawal.amountA, false) {
                // Successful globalize
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Globalize update failed: ", reason)));
            }
            try this.updateRegistry(caller, true) {
                // Successful registry update
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Registry update failed: ", reason)));
            }
        }
        if (withdrawal.amountB > 0) {
            uint8 decimalsB = tokenB == address(0) ? 18 : IERC20(tokenB).decimals();
            uint256 amountB = denormalize(withdrawal.amountB, decimalsB);
            if (tokenB == address(0)) {
                try this.transactNative(caller, amountB, caller) {
                    // Successful transfer
                } catch (bytes memory reason) {
                    revert(string(abi.encodePacked("Native withdrawal failed: ", reason)));
                }
            } else {
                try this.transactToken(caller, tokenB, amountB, caller) {
                    // Successful transfer
                } catch (bytes memory reason) {
                    revert(string(abi.encodePacked("Token withdrawal failed: ", reason)));
                }
            }
            try this.globalizeUpdate(caller, false, withdrawal.amountB, false) {
                // Successful globalize
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Globalize update failed: ", reason)));
            }
            try this.updateRegistry(caller, false) {
                // Successful registry update
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Registry update failed: ", reason)));
            }
        }
    }

    function yPrepOut(address caller, uint256 amount, uint256 index) external nonReentrant returns (PreparedWithdrawal memory) {
        // Prepares y-token withdrawal
        require(routers[msg.sender], "Router only");
        require(caller != address(0), "Invalid caller");
        LiquidityDetails storage details = liquidityDetail;
        Slot storage slot = yLiquiditySlots[index];
        require(slot.depositor == caller, "Caller not depositor");
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

    function yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external nonReentrant {
        // Executes y-token withdrawal
        require(routers[msg.sender], "Router only");
        require(caller != address(0), "Invalid caller");
        Slot storage slot = yLiquiditySlots[index];
        require(slot.depositor == caller, "Caller not depositor");
        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(3, index, slot.allocation - withdrawal.amountB, slot.depositor, address(0));
        try this.update(caller, updates) {
            // Successful update
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Withdrawal update failed: ", reason)));
        }
        if (withdrawal.amountB > 0) {
            uint8 decimalsB = tokenB == address(0) ? 18 : IERC20(tokenB).decimals();
            uint256 amountB = denormalize(withdrawal.amountB, decimalsB);
            if (tokenB == address(0)) {
                try this.transactNative(caller, amountB, caller) {
                    // Successful transfer
                } catch (bytes memory reason) {
                    revert(string(abi.encodePacked("Native withdrawal failed: ", reason)));
                }
            } else {
                try this.transactToken(caller, tokenB, amountB, caller) {
                    // Successful transfer
                } catch (bytes memory reason) {
                    revert(string(abi.encodePacked("Token withdrawal failed: ", reason)));
                }
            }
            try this.globalizeUpdate(caller, false, withdrawal.amountB, false) {
                // Successful globalize
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Globalize update failed: ", reason)));
            }
            try this.updateRegistry(caller, false) {
                // Successful registry update
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Registry update failed: ", reason)));
            }
        }
        if (withdrawal.amountA > 0) {
            uint8 decimalsA = tokenA == address(0) ? 18 : IERC20(tokenA).decimals();
            uint256 amountA = denormalize(withdrawal.amountA, decimalsA);
            if (tokenA == address(0)) {
                try this.transactNative(caller, amountA, caller) {
                    // Successful transfer
                } catch (bytes memory reason) {
                    revert(string(abi.encodePacked("Native withdrawal failed: ", reason)));
                }
            } else {
                try this.transactToken(caller, tokenA, amountA, caller) {
                    // Successful transfer
                } catch (bytes memory reason) {
                    revert(string(abi.encodePacked("Token withdrawal failed: ", reason)));
                }
            }
            try this.globalizeUpdate(caller, true, withdrawal.amountA, false) {
                // Successful globalize
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Globalize update failed: ", reason)));
            }
            try this.updateRegistry(caller, true) {
                // Successful registry update
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Registry update failed: ", reason)));
            }
        }
    }

    function claimFees(address caller, address _listingAddress, uint256 liquidityIndex, bool isX, uint256 /* volume */) external nonReentrant {
        // Claims fees for a slot
        require(routers[msg.sender], "Router only");
        require(_listingAddress == listingAddress, "Invalid listing address");
        require(caller != address(0), "Invalid caller");
        uint256 xBalance;
        try ICCListing(_listingAddress).volumeBalances(0) returns (uint256 xBal, uint256) {
            xBalance = xBal;
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Volume balances fetch failed: ", reason)));
        }
        if (xBalance == 0) revert("Invalid listing balance");
        FeeClaimContext memory context;
        context.caller = caller;
        context.isX = isX;
        context.liquidityIndex = liquidityIndex;
        LiquidityDetails storage details = liquidityDetail;
        Slot storage slot = isX ? xLiquiditySlots[liquidityIndex] : yLiquiditySlots[liquidityIndex];
        require(slot.depositor == caller, "Caller not depositor");
        context.liquid = isX ? details.xLiquid : details.yLiquid;
        context.fees = isX ? details.yFees : details.xFees;
        context.allocation = slot.allocation;
        context.dFeesAcc = slot.dFeesAcc;
        if (context.liquid == 0) revert("No liquidity available");
        if (context.allocation == 0) revert("No allocation for slot");
        _processFeeClaim(context);
    }

    function addFees(address caller, bool isX, uint256 fee) external nonReentrant {
        // Adds fees to pool
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
        try this.update(caller, feeUpdates) {
            // Successful update
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Fee update failed: ", reason)));
        }
        emit FeesUpdated(listingId, details.xFees, details.yFees);
    }

    function transactToken(address caller, address token, uint256 amount, address recipient) external nonReentrant {
        // Handles ERC20 transfers
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
            // Successful transfer
        } catch (bytes memory reason) {
            emit TransactFailed(caller, token, amount, "Token transfer failed");
            revert("Token transfer failed");
        }
        emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
    }

    function transactNative(address caller, uint256 amount, address recipient) external nonReentrant {
        // Handles ETH transfers
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
            emit TransactFailed(caller, address(0), amount, "ETH transfer failed");
            revert("ETH transfer failed");
        }
        emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
    }

    function updateLiquidity(address caller, bool isX, uint256 amount) external nonReentrant {
        // Updates liquidity balances
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

    function getListingAddress(uint256) external view returns (address) {
        // Returns listing address
        return listingAddress;
    }

    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount) {
        // Returns liquidity amounts
        LiquidityDetails memory details = liquidityDetail;
        return (details.xLiquid, details.yLiquid);
    }

    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, uint256 xFeesAcc, uint256 yFeesAcc) {
        // Returns liquidity details
        LiquidityDetails memory details = liquidityDetail;
        return (details.xLiquid, details.yLiquid, details.xFees, details.yFees, details.xFeesAcc, details.yFeesAcc);
    }

    function activeXLiquiditySlotsView() external view returns (uint256[] memory) {
        // Returns active x-token slots
        return activeXLiquiditySlots;
    }

    function activeYLiquiditySlotsView() external view returns (uint256[] memory) {
        // Returns active y-token slots
        return activeYLiquiditySlots;
    }

    function userIndexView(address user) external view returns (uint256[] memory) {
        // Returns user's slot indices
        return userIndex[user];
    }

    function getXSlotView(uint256 index) external view returns (Slot memory) {
        // Returns x-token slot details
        return xLiquiditySlots[index];
    }

    function getYSlotView(uint256 index) external view returns (Slot memory) {
        // Returns y-token slot details
        return yLiquiditySlots[index];
    }
}