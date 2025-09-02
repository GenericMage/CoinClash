// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.8
// Changes:
// - v0.1.8: Modified _executeWithdrawal to support partial withdrawals by allowing user-specified amount to reduce slot allocation instead of setting it to 0.
// Added validation to ensure withdrawal amount does not exceed slot allocation.
// Retained xLiquid/yLiquid checks and error logging from v0.1.7.
// Updated WithdrawalFailed event to include slotIndex for better debugging.
// - v0.1.7: Added xLiquid/yLiquid checks in _executeWithdrawal before calling transactToken/transactNative.
// Modified _executeWithdrawal to revert with detailed error messages.
// Added WithdrawalFailed event.
// Ensured slot allocation updates via ccUpdate.
// - v0.1.6: Removed ccUpdate calls in xExecuteOut and yExecuteOut to prevent double reduction of xLiquid/yLiquid, as transactToken/transactNative already reduce liquidity, avoiding potential underflow.
// - v0.1.5: Modified _changeDepositor to use new updateType (4 for xSlot, 5 for ySlot) to update only depositor address without affecting xLiquid/yLiquid. Ensures correct slot depositor change and prevents unintended liquidity increase.
// - v0.1.4: Updated _changeDepositor to use ccUpdate directly for depositor changes, removing dependency on CCLiquidityTemplate.sol's changeSlotDepositor. Validates slot ownership and allocation before update.
// - v0.1.3: Updated _prepWithdrawal and _executeWithdrawal to use new internal xPrepOut, yPrepOut, xExecuteOut, and yExecuteOut functions, replacing calls to CCLiquidityTemplate.sol versions.
// - v0.1.2: Added xPrepOut, xExecuteOut, yPrepOut, yExecuteOut from CCLiquidityTemplate.sol, modified to use ccUpdate and transactNative/Token directly, ensuring msg.sender is router and updating slot/liquidity details.
// - v0.1.1: Updated _validateDeposit, _executeTokenTransfer, _executeNativeTransfer, _depositToken, and _depositNative to explicitly use depositInitiator (msg.sender) for fund transfers and depositor for slot assignment, clarifying roles.
// - v0.1.0: Bumped version
// - v0.0.19: Removed pool check (xAmount == 0 && yAmount == 0 || (isTokenA ? xAmount : yAmount) > 0) in _validateDeposit to allow deposits in any pool state. Updated compatibility comments.
// - v0.0.18: Removed redundant isRouter checks in _validateDeposit, _prepWithdrawal, _executeWithdrawal, _validateFeeClaim, as CCLiquidityTemplate validates routers[msg.sender]. Updated _executeTokenTransfer to use receivedAmount for transfer and balance checks, handling tax-on-transfer tokens.
// - v0.0.17: Removed listingId from FeeClaimContext and FeesClaimed event, updated _validateFeeClaim to remove getListingId call, as it’s unnecessary with onlyValidListing validation.
// Compatible with CCListingTemplate.sol (v0.0.10), CCMainPartial.sol (v0.0.10), CCLiquidityRouter.sol (v0.0.25), ICCLiquidity.sol (v0.0.4), ICCListing.sol (v0.0.7), CCLiquidityTemplate.sol (v0.0.20).

import "./CCMainPartial.sol";

contract CCLiquidityPartial is CCMainPartial {
    event TransferFailed(address indexed sender, address indexed token, uint256 amount, bytes reason);
    event DepositFailed(address indexed depositor, address token, uint256 amount, string reason);
    event FeesClaimed(address indexed listingAddress, uint256 liquidityIndex, uint256 xFees, uint256 yFees);
    event SlotDepositorChanged(bool isX, uint256 indexed slotIndex, address indexed oldDepositor, address indexed newDepositor);
    event DepositReceived(address indexed depositor, address token, uint256 amount, uint256 normalizedAmount);
    error InsufficientAllowance(address sender, address token, uint256 required, uint256 available);
event WithdrawalFailed(address indexed depositor, address indexed listingAddress, bool isX, uint256 slotIndex, uint256 amount, string reason);
event CompensationCalculated(address indexed depositor, address indexed listingAddress, bool isX, uint256 primaryAmount, uint256 compensationAmount);

    struct DepositContext {
        address listingAddress;
        address depositor;
        uint256 inputAmount;
        bool isTokenA;
        address tokenAddress;
        address liquidityAddr;
        uint256 xAmount;
        uint256 yAmount;
        uint256 receivedAmount;
        uint256 normalizedAmount;
        uint256 index;
    }

    struct FeeClaimContext {
        address listingAddress;
        address depositor;
        uint256 liquidityIndex;
        bool isX;
        address liquidityAddr;
        uint256 xBalance;
        uint256 xLiquid;
        uint256 yLiquid;
        uint256 xFees;
        uint256 yFees;
        uint256 liquid;
        uint256 fees;
        uint256 allocation;
        uint256 dFeesAcc;
        address transferToken;
        uint256 feeShare;
    }

    function _validateDeposit(address listingAddress, address depositor, uint256 inputAmount, bool isTokenA) internal view returns (DepositContext memory) {
    // Validates deposit parameters, using depositor for slot assignment and msg.sender as depositInitiator
    ICCListing listingContract = ICCListing(listingAddress);
    address tokenAddress = isTokenA ? listingContract.tokenA() : listingContract.tokenB();
    address liquidityAddr = listingContract.liquidityAddressView();
    ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
    (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
    return DepositContext({
        listingAddress: listingAddress,
        depositor: depositor,
        inputAmount: inputAmount,
        isTokenA: isTokenA,
        tokenAddress: tokenAddress,
        liquidityAddr: liquidityAddr,
        xAmount: xAmount,
        yAmount: yAmount,
        receivedAmount: 0,
        normalizedAmount: 0,
        index: isTokenA ? liquidityContract.activeXLiquiditySlotsView().length : liquidityContract.activeYLiquiditySlotsView().length
    });
}

function _executeTokenTransfer(DepositContext memory context) internal returns (DepositContext memory) {
    // Transfers ERC20 tokens from depositInitiator (msg.sender) to liquidity template
    require(context.tokenAddress != address(0), "Use depositNative for ETH");
    address depositInitiator = msg.sender;
    uint256 allowance = IERC20(context.tokenAddress).allowance(depositInitiator, address(this));
    if (allowance < context.inputAmount) revert InsufficientAllowance(depositInitiator, context.tokenAddress, context.inputAmount, allowance);
    uint256 preBalanceRouter = IERC20(context.tokenAddress).balanceOf(address(this));
    try IERC20(context.tokenAddress).transferFrom(depositInitiator, address(this), context.inputAmount) {
    } catch (bytes memory reason) {
        emit TransferFailed(depositInitiator, context.tokenAddress, context.inputAmount, reason);
        revert("TransferFrom failed");
    }
    uint256 postBalanceRouter = IERC20(context.tokenAddress).balanceOf(address(this));
    context.receivedAmount = postBalanceRouter - preBalanceRouter;
    require(context.receivedAmount > 0, "No tokens received");
    uint256 preBalanceTemplate = IERC20(context.tokenAddress).balanceOf(context.liquidityAddr);
    try IERC20(context.tokenAddress).transfer(context.liquidityAddr, context.receivedAmount) {
    } catch (bytes memory reason) {
        emit TransferFailed(address(this), context.tokenAddress, context.receivedAmount, reason);
        revert("Transfer to liquidity template failed");
    }
    uint256 postBalanceTemplate = IERC20(context.tokenAddress).balanceOf(context.liquidityAddr);
    context.receivedAmount = postBalanceTemplate - preBalanceTemplate;
    require(context.receivedAmount > 0, "No tokens received by liquidity template");
    uint8 decimals = IERC20(context.tokenAddress).decimals();
    context.normalizedAmount = normalize(context.receivedAmount, decimals);
    return context;
}

function _executeNativeTransfer(DepositContext memory context) internal returns (DepositContext memory) {
    // Transfers native tokens (ETH) from depositInitiator (msg.sender) to liquidity template
    require(context.tokenAddress == address(0), "Use depositToken for ERC20");
    address depositInitiator = msg.sender;
    require(context.inputAmount == msg.value, "Incorrect ETH amount");
    uint256 preBalanceTemplate = context.liquidityAddr.balance;
    (bool success, bytes memory reason) = context.liquidityAddr.call{value: context.inputAmount}("");
    if (!success) {
        emit TransferFailed(depositInitiator, address(0), context.inputAmount, reason);
        revert("ETH transfer to liquidity template failed");
    }
    uint256 postBalanceTemplate = context.liquidityAddr.balance;
    context.receivedAmount = postBalanceTemplate - preBalanceTemplate;
    require(context.receivedAmount > 0, "No ETH received by liquidity template");
    context.normalizedAmount = normalize(context.receivedAmount, 18);
    return context;
}

    function _updateDeposit(DepositContext memory context) internal {
        ICCLiquidity liquidityContract = ICCLiquidity(context.liquidityAddr);
        ICCLiquidity.UpdateType[] memory updates = new ICCLiquidity.UpdateType[](1);
        updates[0] = ICCLiquidity.UpdateType(context.isTokenA ? 2 : 3, context.index, context.normalizedAmount, context.depositor, address(0));
        try liquidityContract.ccUpdate(context.depositor, updates) {
        } catch (bytes memory reason) {
            emit DepositFailed(context.depositor, context.tokenAddress, context.receivedAmount, string(reason));
            revert(string(abi.encodePacked("Deposit update failed: ", reason)));
        }
        emit DepositReceived(context.depositor, context.tokenAddress, context.receivedAmount, context.normalizedAmount);
    }

    function _depositToken(address listingAddress, address depositor, uint256 inputAmount, bool isTokenA) internal returns (uint256) {
    // Deposits ERC20 tokens from depositInitiator (msg.sender) to liquidity pool, assigns slot to depositor
    DepositContext memory context = _validateDeposit(listingAddress, depositor, inputAmount, isTokenA);
    context = _executeTokenTransfer(context);
    _updateDeposit(context);
    return context.receivedAmount;
}

function _depositNative(address listingAddress, address depositor, uint256 inputAmount, bool isTokenA) internal {
    // Deposits ETH from depositInitiator (msg.sender) to liquidity pool, assigns slot to depositor
    DepositContext memory context = _validateDeposit(listingAddress, depositor, inputAmount, isTokenA);
    context = _executeNativeTransfer(context);
    _updateDeposit(context);
}

    function _prepWithdrawal(address listingAddress, address depositor, uint256 amount, uint256 index, bool isX) internal view returns (ICCLiquidity.PreparedWithdrawal memory withdrawal) {
    // Prepares withdrawal, calculates compensation in opposite token if liquidity is insufficient
    ICCLiquidity liquidityTemplate = ICCLiquidity(listingAddress);
    (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, uint256 xFeesAcc, uint256 yFeesAcc) = liquidityTemplate.liquidityDetail();
    uint256 price = ICCListing(listingAddress).prices(0); // Get current price (tokenB/tokenA, normalized to 1e18)
    
    // Validate slot ownership and allocation
    uint256 currentAllocation;
    if (isX) {
        ICCLiquidity.Slot memory slot = liquidityTemplate.getXSlotView(index);
        require(slot.depositor == depositor, "Not slot owner");
        currentAllocation = slot.allocation;
    } else {
        ICCLiquidity.Slot memory slot = liquidityTemplate.getYSlotView(index);
        require(slot.depositor == depositor, "Not slot owner");
        currentAllocation = slot.allocation;
    }
    require(currentAllocation >= amount, "Withdrawal exceeds slot allocation");

    // Check liquidity and calculate compensation
    if (isX) {
        withdrawal.amountA = amount;
        if (xLiquid < amount) {
            // Compensate with tokenB
            uint256 shortfall = amount - xLiquid;
            withdrawal.amountB = (shortfall * price) / 1e18; // Convert shortfall to tokenB using price
        }
    } else {
        withdrawal.amountB = amount;
        if (yLiquid < amount) {
            // Compensate with tokenA
            uint256 shortfall = amount - yLiquid;
            withdrawal.amountA = (shortfall * 1e18) / price; // Convert shortfall to tokenA using price
        }
    }
    return withdrawal;
}

function _executeWithdrawal(address listingAddress, address depositor, uint256 index, bool isX, ICCLiquidity.PreparedWithdrawal memory withdrawal) internal {
    // Executes withdrawal with compensation, updates liquidity, and transfers tokens
    ICCLiquidity liquidityTemplate = ICCLiquidity(listingAddress);
    (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, uint256 xFeesAcc, uint256 yFeesAcc) = liquidityTemplate.liquidityDetail();
    address tokenA = ICCListing(listingAddress).tokenA();
    address tokenB = ICCListing(listingAddress).tokenB();
    uint256 primaryAmount = isX ? withdrawal.amountA : withdrawal.amountB;
    uint256 compensationAmount = isX ? withdrawal.amountB : withdrawal.amountA;

    // Check available liquidity
    if (isX && xLiquid < withdrawal.amountA) {
        emit WithdrawalFailed(depositor, listingAddress, isX, index, withdrawal.amountA, "Insufficient xLiquid");
        revert("Insufficient xLiquid");
    }
    if (!isX && yLiquid < withdrawal.amountB) {
        emit WithdrawalFailed(depositor, listingAddress, isX, index, withdrawal.amountB, "Insufficient yLiquid");
        revert("Insufficient yLiquid");
    }

    // Validate slot allocation
    uint256 currentAllocation;
    if (isX) {
        ICCLiquidity.Slot memory slot = liquidityTemplate.getXSlotView(index);
        require(slot.depositor == depositor, "Not slot owner");
        currentAllocation = slot.allocation;
    } else {
        ICCLiquidity.Slot memory slot = liquidityTemplate.getYSlotView(index);
        require(slot.depositor == depositor, "Not slot owner");
        currentAllocation = slot.allocation;
    }
    require(currentAllocation >= primaryAmount, "Withdrawal exceeds slot allocation");

    // Prepare update for slot allocation (partial withdrawal)
    ICCLiquidity.UpdateType[] memory updates = new ICCLiquidity.UpdateType[](1);
    updates[0] = ICCLiquidity.UpdateType({
        updateType: isX ? 2 : 3,
        index: index,
        value: currentAllocation - primaryAmount, // Reduce allocation
        addr: depositor, // Retain depositor for active slot
        recipient: address(0)
    });

    // Update liquidity and slot
    try liquidityTemplate.ccUpdate(depositor, updates) {
    } catch (bytes memory reason) {
        emit WithdrawalFailed(depositor, listingAddress, isX, index, primaryAmount, string(abi.encodePacked("Update failed: ", reason)));
        revert(string(abi.encodePacked("Update failed: ", reason)));
    }

    // Execute primary token transfer
    if (primaryAmount > 0) {
        if ((isX && tokenA == address(0)) || (!isX && tokenB == address(0))) {
            try liquidityTemplate.transactNative(depositor, primaryAmount, depositor) {
            } catch (bytes memory reason) {
                emit WithdrawalFailed(depositor, listingAddress, isX, index, primaryAmount, string(abi.encodePacked("Native transfer failed: ", reason)));
                revert(string(abi.encodePacked("Native transfer failed: ", reason)));
            }
        } else {
            try liquidityTemplate.transactToken(depositor, isX ? tokenA : tokenB, primaryAmount, depositor) {
            } catch (bytes memory reason) {
                emit WithdrawalFailed(depositor, listingAddress, isX, index, primaryAmount, string(abi.encodePacked("Token transfer failed: ", reason)));
                revert(string(abi.encodePacked("Token transfer failed: ", reason)));
            }
        }
    }

    // Execute compensation token transfer
    if (compensationAmount > 0) {
        emit CompensationCalculated(depositor, listingAddress, isX, primaryAmount, compensationAmount);
        if ((isX && tokenB == address(0)) || (!isX && tokenA == address(0))) {
            try liquidityTemplate.transactNative(depositor, compensationAmount, depositor) {
            } catch (bytes memory reason) {
                emit WithdrawalFailed(depositor, listingAddress, !isX, index, compensationAmount, string(abi.encodePacked("Native compensation transfer failed: ", reason)));
                revert(string(abi.encodePacked("Native compensation transfer failed: ", reason)));
            }
        } else {
            try liquidityTemplate.transactToken(depositor, isX ? tokenB : tokenA, compensationAmount, depositor) {
            } catch (bytes memory reason) {
                emit WithdrawalFailed(depositor, listingAddress, !isX, index, compensationAmount, string(abi.encodePacked("Token compensation transfer failed: ", reason)));
                revert(string(abi.encodePacked("Token compensation transfer failed: ", reason)));
            }
        }
    }
}

    function _validateFeeClaim(address listingAddress, address depositor, uint256 liquidityIndex, bool isX) internal view returns (FeeClaimContext memory) {
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        require(depositor != address(0), "Invalid depositor");
        (uint256 xBalance, ) = listingContract.volumeBalances(0);
        require(xBalance > 0, "Invalid listing balance");
        (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, , ) = liquidityContract.liquidityDetailsView();
        ICCLiquidity.Slot memory slot = isX ? liquidityContract.getXSlotView(liquidityIndex) : liquidityContract.getYSlotView(liquidityIndex);
        require(slot.depositor == depositor, "Depositor not slot owner");
        require(xLiquid > 0 || yLiquid > 0, "No liquidity available");
        require(slot.allocation > 0, "No allocation for slot");
        return FeeClaimContext({
            listingAddress: listingAddress,
            depositor: depositor,
            liquidityIndex: liquidityIndex,
            isX: isX,
            liquidityAddr: liquidityAddr,
            xBalance: xBalance,
            xLiquid: xLiquid,
            yLiquid: yLiquid,
            xFees: xFees,
            yFees: yFees,
            liquid: isX ? xLiquid : yLiquid,
            fees: isX ? yFees : xFees,
            allocation: slot.allocation,
            dFeesAcc: slot.dFeesAcc,
            transferToken: isX ? listingContract.tokenB() : listingContract.tokenA(),
            feeShare: 0
        });
    }

    function _calculateFeeShare(FeeClaimContext memory context) internal pure returns (FeeClaimContext memory) {
        uint256 contributedFees = context.fees > context.dFeesAcc ? context.fees - context.dFeesAcc : 0;
        uint256 liquidityContribution = context.liquid > 0 ? (context.allocation * 1e18) / context.liquid : 0;
        context.feeShare = (contributedFees * liquidityContribution) / 1e18;
        context.feeShare = context.feeShare > context.fees ? context.fees : context.feeShare;
        return context;
    }

    function _executeFeeClaim(FeeClaimContext memory context) internal {
        if (context.feeShare == 0) revert("No fees to claim");
        ICCLiquidity liquidityContract = ICCLiquidity(context.liquidityAddr);
        ICCLiquidity.UpdateType[] memory updates = new ICCLiquidity.UpdateType[](2);
        updates[0] = ICCLiquidity.UpdateType(1, context.isX ? 1 : 0, context.fees - context.feeShare, address(0), address(0));
        updates[1] = ICCLiquidity.UpdateType(context.isX ? 2 : 3, context.liquidityIndex, context.allocation, context.depositor, address(0));
        try liquidityContract.ccUpdate(context.depositor, updates) {
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Fee claim update failed: ", reason)));
        }
        uint8 decimals = context.transferToken == address(0) ? 18 : IERC20(context.transferToken).decimals();
        uint256 denormalizedFee = denormalize(context.feeShare, decimals);
        if (context.transferToken == address(0)) {
            try liquidityContract.transactNative(context.depositor, denormalizedFee, context.depositor) {
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Fee claim transfer failed: ", reason)));
            }
        } else {
            try liquidityContract.transactToken(context.depositor, context.transferToken, denormalizedFee, context.depositor) {
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Fee claim transfer failed: ", reason)));
            }
        }
        emit FeesClaimed(context.listingAddress, context.liquidityIndex, context.isX ? 0 : context.feeShare, context.isX ? context.feeShare : 0);
    }

    function _processFeeShare(address listingAddress, address depositor, uint256 liquidityIndex, bool isX) internal {
        FeeClaimContext memory context = _validateFeeClaim(listingAddress, depositor, liquidityIndex, isX);
        context = _calculateFeeShare(context);
        _executeFeeClaim(context);
    }

    function _changeDepositor(address listingAddress, address depositor, bool isX, uint256 slotIndex, address newDepositor) internal {
        // Changes depositor for a liquidity slot using ccUpdate with new updateType
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        require(depositor != address(0), "Invalid depositor");
        require(newDepositor != address(0), "Invalid new depositor");
        ICCLiquidity.Slot memory slot = isX ? liquidityContract.getXSlotView(slotIndex) : liquidityContract.getYSlotView(slotIndex);
        require(slot.depositor == depositor, "Depositor not slot owner");
        require(slot.allocation > 0, "Invalid slot");
        ICCLiquidity.UpdateType[] memory updates = new ICCLiquidity.UpdateType[](1);
        updates[0] = ICCLiquidity.UpdateType(isX ? 4 : 5, slotIndex, 0, newDepositor, address(0)); // Use updateType 4 for xSlot, 5 for ySlot
        try liquidityContract.ccUpdate(depositor, updates) {
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Depositor change failed: ", reason)));
        }
        emit SlotDepositorChanged(isX, slotIndex, depositor, newDepositor);
    }
  }