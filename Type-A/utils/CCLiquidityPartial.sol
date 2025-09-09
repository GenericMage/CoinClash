// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

/*
// Version: 0.1.22
// Changes:
// - v0.1.22: Modified _checkLiquidity to only check xLiquid when isX = true and compensationAmount = 0.
// Added ValidationFailed and TransferSuccessful events for better debugging.
// - v0.1.21: Added try-catch for volumeBalances, prices, and liquidityAddressView.
 - Added ValidationFailed event for slot and liquidity validation failures.
 - Added TransferSuccessful event for successful primary and compensation transfers.
 - Minimized reverts in _executeWithdrawal, emitting WithdrawalFailed instead.
// - v0.1.20: Updated _executeWithdrawal to wrap liquidityDetailsView() in try-catch to catch failures and emit WithdrawalFailed with detailed error messages. Added validation for non-zero liquidityAddress from ICCListing.liquidityAddressView(). Retained prior change log.
// - v0.1.19: Added _checkLiquidity call in _executeWithdrawal to validate liquidity before transfers, emitting WithdrawalFailed on failure. Enhanced WithdrawalFailed event in _transferPrimaryToken and _transferCompensationToken to include token and liquidity contract addresses. Added detailed error logging in _updateSlotAllocation for ccUpdate failures.
// - v0.1.18: Updated _executeWithdrawal to use currentAllocation from _prepWithdrawal via PreparedWithdrawal to fix incorrect slot allocation updates. Added denormalization of primaryAmount and compensationAmount in _transferPrimaryToken and _transferCompensationToken to handle non-18-decimal tokens correctly.
// - v0.1.17: Fixed _executeWithdrawal to use liquidityAddress from ICCListing.liquidityAddressView() instead of casting listingAddress to ICCLiquidity. Removed redundant _validateSlotOwnership and _checkLiquidity calls, as _prepWithdrawal already validates listing and slot details.
// - v0.1.16: Refactored _prepWithdrawal to address stack too deep error by splitting into helper functions (_getLiquidityDetails, _validateSlot, _calculateCompensation). Used private struct WithdrawalPrepData to pass data across stages, reducing stack usage.
// - v0.1.15: Fixed _prepWithdrawal to call liquidityDetailsView() on liquidity contract (via listingContract.liquidityAddressView()) instead of listingAddress, correcting incorrect contract assumption.
// - v0.1.14: Replaced activeXLiquiditySlotsView and activeYLiquiditySlotsView with getActiveXLiquiditySlots and getActiveYLiquiditySlots in _validateDeposit to fix transaction failure due to removed view functions.
// - v0.1.12: Modified _executeFeeClaim to use updateType 6/7 for dFeesAcc, setting it to xFeesAcc/yFeesAcc from liquidityDetailsView, ensuring accurate fee accumulation tracking.
// - v0.1.11: Modified _executeFeeClaim to use updateType 6/7 instead of 2/3, updating dFeesAcc without altering slot allocation or liquidity.
// - v0.1.10: Replaced liquidityDetail() with liquidityDetailsView() in _executeWithdrawal to fix silent failure. Added error emission for liquidityDetailsView failure to improve debugging.
// - v0.1.9: Refactored _executeWithdrawal to address stack too deep error by splitting into helper functions. Introduced struct to manage data.
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
*/

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
    event NoFeesToClaim(address indexed depositor, address indexed listingAddress, bool isX, uint256 liquidityIndex);
    event FeeValidationFailed(address indexed depositor, address indexed listingAddress, bool isX, uint256 liquidityIndex, string reason);
    event ValidationFailed(address indexed depositor, address indexed listingAddress, bool isX, uint256 index, string reason);
    event TransferSuccessful(address indexed depositor, address indexed listingAddress, bool isX, uint256 index, address token, uint256 amount);

struct WithdrawalContext {
    address listingAddress;
    address depositor;
    uint256 index;
    bool isX;
    uint256 primaryAmount;
    uint256 compensationAmount;
    uint256 currentAllocation;
    address tokenA;
    address tokenB;
}
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
    
    struct WithdrawalPrepData {
    address liquidityAddr;
    uint256 xLiquid;
    uint256 yLiquid;
    uint256 price;
    uint256 currentAllocation;
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
        index: isTokenA ? liquidityContract.getActiveXLiquiditySlots().length : liquidityContract.getActiveYLiquiditySlots().length
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

// Adjustrd _getLiquidityDetails to take listingAddress and isX, return (WithdrawalPrepData, bool).
function _getLiquidityDetails(address listingAddress, bool isX) private returns (WithdrawalPrepData memory prepData, bool success) {
    prepData = WithdrawalPrepData({
        liquidityAddr: address(0),
        xLiquid: 0,
        yLiquid: 0,
        price: 0,
        currentAllocation: 0
    });
    ICCListing listingContract = ICCListing(listingAddress);
    address liquidityAddr;
    try listingContract.liquidityAddressView() returns (address addr) {
        if (addr == address(0)) {
            emit ValidationFailed(msg.sender, listingAddress, isX, 0, "Invalid liquidity address returned");
            return (prepData, false);
        }
        liquidityAddr = addr;
        prepData.liquidityAddr = addr;
    } catch (bytes memory reason) {
        emit ValidationFailed(msg.sender, listingAddress, isX, 0, string(abi.encodePacked("liquidityAddressView failed: ", reason)));
        return (prepData, false);
    }
    ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
    try liquidityContract.liquidityDetailsView() returns (uint256 xLiquid, uint256 yLiquid, uint256, uint256, uint256, uint256) {
        prepData.xLiquid = xLiquid;
        prepData.yLiquid = yLiquid;
    } catch (bytes memory reason) {
        emit ValidationFailed(msg.sender, listingAddress, isX, 0, string(abi.encodePacked("liquidityDetailsView failed: ", reason)));
        return (prepData, false);
    }
    try listingContract.prices(0) returns (uint256 price) {
        prepData.price = price;
    } catch (bytes memory reason) {
        emit ValidationFailed(msg.sender, listingAddress, isX, 0, string(abi.encodePacked("prices failed: ", reason)));
        return (prepData, false);
    }
    return (prepData, true);
}

// Adjusted  _validateSlot to take correct parameters, use try-catch only on external calls.
// Refactored _validateSlot to use if-else with separate try/catch for getXSlotView and getYSlotView to comply with Solidity's external call restrictions.
function _validateSlot(address depositor, uint256 index, bool isX, address liquidityAddr) private returns (uint256 currentAllocation, bool success) {
    // Validates slot ownership and returns allocation, using try/catch for external calls only
    ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
    ICCLiquidity.Slot memory slot;
    if (isX) {
        // Direct external call to getXSlotView with try/catch
        try liquidityContract.getXSlotView(index) returns (ICCLiquidity.Slot memory _slot) {
            slot = _slot;
        } catch (bytes memory reason) {
            emit ValidationFailed(depositor, address(0), isX, index, string(abi.encodePacked("getXSlotView failed: ", reason)));
            return (0, false);
        }
    } else {
        // Direct external call to getYSlotView with try/catch
        try liquidityContract.getYSlotView(index) returns (ICCLiquidity.Slot memory _slot) {
            slot = _slot;
        } catch (bytes memory reason) {
            emit ValidationFailed(depositor, address(0), isX, index, string(abi.encodePacked("getYSlotView failed: ", reason)));
            return (0, false);
        }
    }
    // Validate ownership without try/catch (internal check)
    if (slot.depositor != depositor) {
        emit ValidationFailed(depositor, address(0), isX, index, "Depositor not slot owner");
        return (0, false);
    }
    return (slot.allocation, true);
}

// Adjusted to take WithdrawalContext and WithdrawalPrepData, return (ICCLiquidity.PreparedWithdrawal, bool).
function _calculateCompensation(WithdrawalContext memory context, WithdrawalPrepData memory prepData) private returns (ICCLiquidity.PreparedWithdrawal memory withdrawal, bool success) {
    withdrawal = ICCLiquidity.PreparedWithdrawal({ amountA: 0, amountB: 0 });
    success = false;
    if (prepData.price == 0) {
        emit ValidationFailed(context.depositor, context.listingAddress, context.isX, context.index, "Zero price returned");
        return (withdrawal, false);
    }
    uint256 xBalance;
    uint256 yBalance;
    try ICCListing(context.listingAddress).volumeBalances(0) returns (uint256 _xBalance, uint256 _yBalance) {
        xBalance = _xBalance;
        yBalance = _yBalance;
    } catch (bytes memory reason) {
        emit ValidationFailed(context.depositor, context.listingAddress, context.isX, context.index, string(abi.encodePacked("volumeBalances failed: ", reason)));
        return (withdrawal, false);
    }
    uint256 compensation;
    if (context.isX) {
        withdrawal.amountA = context.primaryAmount;
        compensation = (context.primaryAmount * prepData.price) / 1e18;
        if (compensation > yBalance) {
            emit ValidationFailed(context.depositor, context.listingAddress, context.isX, context.index, "Insufficient yBalance for compensation");
            return (withdrawal, false);
        }
        withdrawal.amountB = compensation;
    } else {
        withdrawal.amountB = context.primaryAmount;
        compensation = (context.primaryAmount * 1e18) / prepData.price;
        if (compensation > xBalance) {
            emit ValidationFailed(context.depositor, context.listingAddress, context.isX, context.index, "Insufficient xBalance for compensation");
            return (withdrawal, false);
        }
        withdrawal.amountA = compensation;
    }
    success = true;
    return (withdrawal, success);
}

// Refactored _prepWithdrawal function  to properly destructure tuples and handle success flags
function _prepWithdrawal(address listingAddress, address depositor, uint256 amount, uint256 index, bool isX) internal returns (ICCLiquidity.PreparedWithdrawal memory) {
    WithdrawalPrepData memory data;
    bool getSuccess;
    (data, getSuccess) = _getLiquidityDetails(listingAddress, isX);
    if (!getSuccess) {
        revert("Prep failed: liquidity details");
    }
    uint256 currentAllocation;
    bool slotSuccess;
    (currentAllocation, slotSuccess) = _validateSlot(depositor, index, isX, data.liquidityAddr);
    if (!slotSuccess) {
        revert("Prep failed: slot validation");
    }
    data.currentAllocation = currentAllocation;
    if (currentAllocation < amount) {
        revert("Insufficient slot allocation");
    }
    WithdrawalContext memory context = WithdrawalContext({
        listingAddress: listingAddress,
        depositor: depositor,
        index: index,
        isX: isX,
        primaryAmount: amount,
        compensationAmount: 0, // Will be calculated
        currentAllocation: currentAllocation,
        tokenA: ICCListing(listingAddress).tokenA(),
        tokenB: ICCListing(listingAddress).tokenB()
    });
    ICCLiquidity.PreparedWithdrawal memory withdrawal;
    bool calcSuccess;
    (withdrawal, calcSuccess) = _calculateCompensation(context, data);
    if (!calcSuccess) {
        revert("Prep failed: compensation calculation");
    }
    context.compensationAmount = isX ? withdrawal.amountB : withdrawal.amountA;
    return withdrawal;
}

function _validateSlotOwnership(WithdrawalContext memory context, ICCLiquidity liquidityTemplate) private view returns (WithdrawalContext memory) {
    // Validates slot ownership and allocation
    if (context.isX) {
        ICCLiquidity.Slot memory slot = liquidityTemplate.getXSlotView(context.index);
        require(slot.depositor == context.depositor, "Not slot owner");
        context.currentAllocation = slot.allocation;
    } else {
        ICCLiquidity.Slot memory slot = liquidityTemplate.getYSlotView(context.index);
        require(slot.depositor == context.depositor, "Not slot owner");
        context.currentAllocation = slot.allocation;
    }
    require(context.currentAllocation >= context.primaryAmount, "Withdrawal exceeds slot allocation");
    return context;
}

function _checkLiquidity(WithdrawalContext memory context, uint256 xLiquid, uint256 yLiquid) internal {
    // Checks available liquidity, only validates xLiquid for isX withdrawals with no compensation
    if (context.isX && context.primaryAmount > xLiquid) {
        emit WithdrawalFailed(context.depositor, context.listingAddress, context.isX, context.index, context.primaryAmount, "Insufficient xLiquid in liquidity contract");
        return;
    }
    if (!context.isX && context.primaryAmount > yLiquid) {
        emit WithdrawalFailed(context.depositor, context.listingAddress, context.isX, context.index, context.primaryAmount, "Insufficient yLiquid in liquidity contract");
        return;
    }
    if (context.compensationAmount > 0) {
        if (context.isX && context.compensationAmount > yLiquid) {
            emit WithdrawalFailed(context.depositor, context.listingAddress, context.isX, context.index, context.compensationAmount, "Insufficient yLiquid for compensation");
            return;
        }
        if (!context.isX && context.compensationAmount > xLiquid) {
            emit WithdrawalFailed(context.depositor, context.listingAddress, context.isX, context.index, context.compensationAmount, "Insufficient xLiquid for compensation");
            return;
        }
    }
}

function _updateSlotAllocation(WithdrawalContext memory context, ICCLiquidity liquidityTemplate) private {
    // Updates slot allocation for partial withdrawal
    ICCLiquidity.UpdateType[] memory updates = new ICCLiquidity.UpdateType[](1);
    updates[0] = ICCLiquidity.UpdateType({
        updateType: context.isX ? 2 : 3,
        index: context.index,
        value: context.currentAllocation - context.primaryAmount,
        addr: context.depositor,
        recipient: address(0)
    });
    try liquidityTemplate.ccUpdate(context.depositor, updates) {
    } catch (bytes memory reason) {
        string memory errorMsg = string(abi.encodePacked("Slot update failed for ", context.isX ? "xSlot" : "ySlot", " index ", uint2str(context.index), ": ", reason));
        emit WithdrawalFailed(context.depositor, context.listingAddress, context.isX, context.index, context.primaryAmount, errorMsg);
        revert(errorMsg);
    }
}

function _transferPrimaryToken(WithdrawalContext memory context, ICCLiquidity liquidityTemplate) private {
    // Transfers primary token, denormalizing amount based on token decimals
    if (context.primaryAmount > 0) {
        address token = context.isX ? context.tokenA : context.tokenB;
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 denormalizedAmount = denormalize(context.primaryAmount, decimals);
        if (token == address(0)) {
            try liquidityTemplate.transactNative(context.depositor, denormalizedAmount, context.depositor) {
            } catch (bytes memory reason) {
                string memory errorMsg = string(abi.encodePacked("Native transfer failed for token ", uint2str(uint160(token)), " from liquidity contract ", uint2str(uint160(address(liquidityTemplate))), ": ", reason));
                emit WithdrawalFailed(context.depositor, context.listingAddress, context.isX, context.index, context.primaryAmount, errorMsg);
                revert(errorMsg);
            }
        } else {
            try liquidityTemplate.transactToken(context.depositor, token, denormalizedAmount, context.depositor) {
            } catch (bytes memory reason) {
                string memory errorMsg = string(abi.encodePacked("Token transfer failed for token ", uint2str(uint160(token)), " from liquidity contract ", uint2str(uint160(address(liquidityTemplate))), ": ", reason));
                emit WithdrawalFailed(context.depositor, context.listingAddress, context.isX, context.index, context.primaryAmount, errorMsg);
                revert(errorMsg);
            }
        }
    }
}

function _transferCompensationToken(WithdrawalContext memory context, ICCLiquidity liquidityTemplate) private {
    // Transfers compensation token, denormalizing amount based on token decimals
    if (context.compensationAmount > 0) {
        emit CompensationCalculated(context.depositor, context.listingAddress, context.isX, context.primaryAmount, context.compensationAmount);
        address token = context.isX ? context.tokenB : context.tokenA;
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 denormalizedAmount = denormalize(context.compensationAmount, decimals);
        if (token == address(0)) {
            try liquidityTemplate.transactNative(context.depositor, denormalizedAmount, context.depositor) {
            } catch (bytes memory reason) {
                string memory errorMsg = string(abi.encodePacked("Native compensation transfer failed for token ", uint2str(uint160(token)), " from liquidity contract ", uint2str(uint160(address(liquidityTemplate))), ": ", reason));
                emit WithdrawalFailed(context.depositor, context.listingAddress, !context.isX, context.index, context.compensationAmount, errorMsg);
                revert(errorMsg);
            }
        } else {
            try liquidityTemplate.transactToken(context.depositor, token, denormalizedAmount, context.depositor) {
            } catch (bytes memory reason) {
                string memory errorMsg = string(abi.encodePacked("Token compensation transfer failed for token ", uint2str(uint160(token)), " from liquidity contract ", uint2str(uint160(address(liquidityTemplate))), ": ", reason));
                emit WithdrawalFailed(context.depositor, context.listingAddress, !context.isX, context.index, context.compensationAmount, errorMsg);
                revert(errorMsg);
            }
        }
    }
}

// Updated function to ensure non-reverting behaviour 
function _executeWithdrawal(address listingAddress, address depositor, uint256 index, bool isX, ICCLiquidity.PreparedWithdrawal memory withdrawal) internal {
    ICCListing listingContract = ICCListing(listingAddress);
    address liquidityAddress;
    try listingContract.liquidityAddressView() returns (address addr) {
        if (addr == address(0)) {
            emit ValidationFailed(depositor, listingAddress, isX, index, "Invalid liquidity address returned");
            return;
        }
        liquidityAddress = addr;
    } catch (bytes memory reason) {
        emit ValidationFailed(depositor, listingAddress, isX, index, string(abi.encodePacked("liquidityAddressView failed: ", reason)));
        return;
    }
    ICCLiquidity liquidityTemplate = ICCLiquidity(liquidityAddress);
    uint256 currentAllocation;
    bool slotValid;
    (currentAllocation, slotValid) = _validateSlot(depositor, index, isX, liquidityAddress);
    if (!slotValid) return;
    if (currentAllocation < (isX ? withdrawal.amountA : withdrawal.amountB)) {
        emit ValidationFailed(depositor, listingAddress, isX, index, "Insufficient slot allocation");
        return;
    }
    WithdrawalContext memory context = WithdrawalContext({
        listingAddress: listingAddress,
        depositor: depositor,
        index: index,
        isX: isX,
        primaryAmount: isX ? withdrawal.amountA : withdrawal.amountB,
        compensationAmount: isX ? withdrawal.amountB : withdrawal.amountA,
        currentAllocation: currentAllocation,
        tokenA: listingContract.tokenA(),
        tokenB: listingContract.tokenB()
    });
    uint256 xLiquid;
    uint256 yLiquid;
    try liquidityTemplate.liquidityDetailsView() returns (uint256 _xLiquid, uint256 _yLiquid, uint256, uint256, uint256, uint256) {
        xLiquid = _xLiquid;
        yLiquid = _yLiquid;
    } catch (bytes memory reason) {
        emit WithdrawalFailed(context.depositor, context.listingAddress, context.isX, context.index, context.primaryAmount, string(abi.encodePacked("liquidityDetailsView failed: ", reason)));
        return;
    }
    _checkLiquidity(context, xLiquid, yLiquid);
    _updateSlotAllocation(context, liquidityTemplate);
    if (context.primaryAmount > 0) {
        address token = context.isX ? context.tokenA : context.tokenB;
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 denormalizedAmount = denormalize(context.primaryAmount, decimals);
        if (token == address(0)) {
            try liquidityTemplate.transactNative(context.depositor, denormalizedAmount, context.depositor) {
                emit TransferSuccessful(context.depositor, context.listingAddress, context.isX, context.index, token, denormalizedAmount);
            } catch (bytes memory reason) {
                emit WithdrawalFailed(context.depositor, context.listingAddress, context.isX, context.index, context.primaryAmount, string(abi.encodePacked("Native transfer failed: ", reason)));
                return;
            }
        } else {
            try liquidityTemplate.transactToken(context.depositor, token, denormalizedAmount, context.depositor) {
                emit TransferSuccessful(context.depositor, context.listingAddress, context.isX, context.index, token, denormalizedAmount);
            } catch (bytes memory reason) {
                emit WithdrawalFailed(context.depositor, context.listingAddress, context.isX, context.index, context.primaryAmount, string(abi.encodePacked("Token transfer failed: ", reason)));
                return;
            }
        }
    }
    if (context.compensationAmount > 0) {
        emit CompensationCalculated(context.depositor, context.listingAddress, context.isX, context.primaryAmount, context.compensationAmount);
        address token = context.isX ? context.tokenB : context.tokenA;
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 denormalizedAmount = denormalize(context.compensationAmount, decimals);
        if (token == address(0)) {
            try liquidityTemplate.transactNative(context.depositor, denormalizedAmount, context.depositor) {
                emit TransferSuccessful(context.depositor, context.listingAddress, !context.isX, context.index, token, denormalizedAmount);
            } catch (bytes memory reason) {
                emit WithdrawalFailed(context.depositor, context.listingAddress, !context.isX, context.index, context.compensationAmount, string(abi.encodePacked("Native compensation transfer failed: ", reason)));
                return;
            }
        } else {
            try liquidityTemplate.transactToken(context.depositor, token, denormalizedAmount, context.depositor) {
                emit TransferSuccessful(context.depositor, context.listingAddress, !context.isX, context.index, token, denormalizedAmount);
            } catch (bytes memory reason) {
                emit WithdrawalFailed(context.depositor, context.listingAddress, !context.isX, context.index, context.compensationAmount, string(abi.encodePacked("Token compensation transfer failed: ", reason)));
                return;
            }
        }
    }
}

function _validateFeeClaim(address listingAddress, address depositor, uint256 liquidityIndex, bool isX) internal returns (FeeClaimContext memory) {

    // Validates fee claim parameters and ensures sufficient fees

    ICCListing listingContract = ICCListing(listingAddress);

    address liquidityAddr = listingContract.liquidityAddressView();

    ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);

    require(depositor != address(0), "Invalid depositor");

    (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, , ) = liquidityContract.liquidityDetailsView();

    ICCLiquidity.Slot memory slot = isX ? liquidityContract.getXSlotView(liquidityIndex) : liquidityContract.getYSlotView(liquidityIndex);

    require(slot.depositor == depositor, "Depositor not slot owner");

    require(xLiquid > 0 || yLiquid > 0, "No liquidity available");

    require(slot.allocation > 0, "No allocation for slot");

    uint256 fees = isX ? yFees : xFees;

    if (fees == 0) {

        emit FeeValidationFailed(depositor, listingAddress, isX, liquidityIndex, "No fees available");

        revert("No fees available");

    }

    return FeeClaimContext({

        listingAddress: listingAddress,

        depositor: depositor,

        liquidityIndex: liquidityIndex,

        isX: isX,

        liquidityAddr: liquidityAddr,

        xBalance: 0, // Unused, retained for compatibility

        xLiquid: xLiquid,

        yLiquid: yLiquid,

        xFees: xFees,

        yFees: yFees,

        liquid: isX ? xLiquid : yLiquid,

        fees: fees,

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

    // Executes fee claim, updates fees and dFeesAcc to xFeesAcc/yFeesAcc, and transfers fees

    if (context.feeShare == 0) {

        emit NoFeesToClaim(context.depositor, context.listingAddress, context.isX, context.liquidityIndex);

        return;

    }

    ICCLiquidity liquidityContract = ICCLiquidity(context.liquidityAddr);

    uint256 xFeesAcc;

    uint256 yFeesAcc;

    try liquidityContract.liquidityDetailsView() returns (uint256, uint256, uint256, uint256, uint256 _xFeesAcc, uint256 _yFeesAcc) {

        xFeesAcc = _xFeesAcc;

        yFeesAcc = _yFeesAcc;

    } catch (bytes memory reason) {

        revert(string(abi.encodePacked("Liquidity details fetch failed: ", reason)));

    }

    ICCLiquidity.UpdateType[] memory updates = new ICCLiquidity.UpdateType[](2);

    updates[0] = ICCLiquidity.UpdateType(1, context.isX ? 1 : 0, context.fees - context.feeShare, address(0), address(0));

    updates[1] = ICCLiquidity.UpdateType(context.isX ? 6 : 7, context.liquidityIndex, context.isX ? yFeesAcc : xFeesAcc, context.depositor, address(0));

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
    
    function uint2str(uint256 _i) internal pure returns (string memory) {
    if (_i == 0) return "0";
    uint256 j = _i;
    uint256 length;
    while (j != 0) {
        length++;
        j /= 10;
    }
    bytes memory bstr = new bytes(length);
    uint256 k = length;
    j = _i;
    while (j != 0) {
        bstr[--k] = bytes1(uint8(48 + j % 10));
        j /= 10;
    }
    return string(bstr);
}
  }