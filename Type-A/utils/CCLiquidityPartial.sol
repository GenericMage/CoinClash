// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.16
// Changes:
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

// Helper function to fetch liquidity details
function _getLiquidityDetails(address listingAddress) private view returns (WithdrawalPrepData memory data) {
    ICCListing listingContract = ICCListing(listingAddress);
    data.liquidityAddr = listingContract.liquidityAddressView();
    ICCLiquidity liquidityTemplate = ICCLiquidity(data.liquidityAddr);
    (uint256 xLiquid, uint256 yLiquid, , , , ) = liquidityTemplate.liquidityDetailsView();
    data.xLiquid = xLiquid;
    data.yLiquid = yLiquid;
    data.price = listingContract.prices(0); // tokenB/tokenA, normalized to 1e18
    return data;
}

// Helper function to validate slot ownership and allocation
function _validateSlot(address depositor, uint256 index, bool isX, address liquidityAddr) private view returns (uint256 currentAllocation) {
    ICCLiquidity liquidityTemplate = ICCLiquidity(liquidityAddr);
    if (isX) {
        ICCLiquidity.Slot memory slot = liquidityTemplate.getXSlotView(index);
        require(slot.depositor == depositor, "Not slot owner");
        currentAllocation = slot.allocation;
    } else {
        ICCLiquidity.Slot memory slot = liquidityTemplate.getYSlotView(index);
        require(slot.depositor == depositor, "Not slot owner");
        currentAllocation = slot.allocation;
    }
    return currentAllocation;
}

// Helper function to calculate compensation
function _calculateCompensation(uint256 amount, bool isX, WithdrawalPrepData memory data) private pure returns (ICCLiquidity.PreparedWithdrawal memory withdrawal) {
    if (isX) {
        withdrawal.amountA = amount;
        if (data.xLiquid < amount) {
            uint256 shortfall = amount - data.xLiquid;
            withdrawal.amountB = (shortfall * data.price) / 1e18; // Compensate with tokenB
        }
    } else {
        withdrawal.amountB = amount;
        if (data.yLiquid < amount) {
            uint256 shortfall = amount - data.yLiquid;
            withdrawal.amountA = (shortfall * 1e18) / data.price; // Compensate with tokenA
        }
    }
    return withdrawal;
}

// Refactored _prepWithdrawal function
function _prepWithdrawal(address listingAddress, address depositor, uint256 amount, uint256 index, bool isX) internal view returns (ICCLiquidity.PreparedWithdrawal memory withdrawal) {
    // Prepares withdrawal, calculates compensation in opposite token if liquidity is insufficient
    WithdrawalPrepData memory data = _getLiquidityDetails(listingAddress);
    data.currentAllocation = _validateSlot(depositor, index, isX, data.liquidityAddr);
    require(data.currentAllocation >= amount, "Withdrawal exceeds slot allocation");
    withdrawal = _calculateCompensation(amount, isX, data);
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
    // Checks available liquidity
    if (context.isX && xLiquid < context.primaryAmount) {
        emit WithdrawalFailed(context.depositor, context.listingAddress, context.isX, context.index, context.primaryAmount, "Insufficient xLiquid");
        revert("Insufficient xLiquid");
    }
    if (!context.isX && yLiquid < context.primaryAmount) {
        emit WithdrawalFailed(context.depositor, context.listingAddress, context.isX, context.index, context.primaryAmount, "Insufficient yLiquid");
        revert("Insufficient yLiquid");
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
        emit WithdrawalFailed(context.depositor, context.listingAddress, context.isX, context.index, context.primaryAmount, string(abi.encodePacked("Update failed: ", reason)));
        revert(string(abi.encodePacked("Update failed: ", reason)));
    }
}

function _transferPrimaryToken(WithdrawalContext memory context, ICCLiquidity liquidityTemplate) private {
    // Transfers primary token
    if (context.primaryAmount > 0) {
        address token = context.isX ? context.tokenA : context.tokenB;
        if (token == address(0)) {
            try liquidityTemplate.transactNative(context.depositor, context.primaryAmount, context.depositor) {
            } catch (bytes memory reason) {
                emit WithdrawalFailed(context.depositor, context.listingAddress, context.isX, context.index, context.primaryAmount, string(abi.encodePacked("Native transfer failed: ", reason)));
                revert(string(abi.encodePacked("Native transfer failed: ", reason)));
            }
        } else {
            try liquidityTemplate.transactToken(context.depositor, token, context.primaryAmount, context.depositor) {
            } catch (bytes memory reason) {
                emit WithdrawalFailed(context.depositor, context.listingAddress, context.isX, context.index, context.primaryAmount, string(abi.encodePacked("Token transfer failed: ", reason)));
                revert(string(abi.encodePacked("Token transfer failed: ", reason)));
            }
        }
    }
}

function _transferCompensationToken(WithdrawalContext memory context, ICCLiquidity liquidityTemplate) private {
    // Transfers compensation token
    if (context.compensationAmount > 0) {
        emit CompensationCalculated(context.depositor, context.listingAddress, context.isX, context.primaryAmount, context.compensationAmount);
        address token = context.isX ? context.tokenB : context.tokenA;
        if (token == address(0)) {
            try liquidityTemplate.transactNative(context.depositor, context.compensationAmount, context.depositor) {
            } catch (bytes memory reason) {
                emit WithdrawalFailed(context.depositor, context.listingAddress, !context.isX, context.index, context.compensationAmount, string(abi.encodePacked("Native compensation transfer failed: ", reason)));
                revert(string(abi.encodePacked("Native compensation transfer failed: ", reason)));
            }
        } else {
            try liquidityTemplate.transactToken(context.depositor, token, context.compensationAmount, context.depositor) {
            } catch (bytes memory reason) {
                emit WithdrawalFailed(context.depositor, context.listingAddress, !context.isX, context.index, context.compensationAmount, string(abi.encodePacked("Token compensation transfer failed: ", reason)));
                revert(string(abi.encodePacked("Token compensation transfer failed: ", reason)));
            }
        }
    }
}

// Updated function to replace the existing _executeWithdrawal
function _executeWithdrawal(address listingAddress, address depositor, uint256 index, bool isX, ICCLiquidity.PreparedWithdrawal memory withdrawal) internal {
    // Executes withdrawal with compensation, updates liquidity, and transfers tokens
    ICCLiquidity liquidityTemplate = ICCLiquidity(listingAddress);
    uint256 xLiquid;
    uint256 yLiquid;
    try liquidityTemplate.liquidityDetailsView() returns (uint256 _xLiquid, uint256 _yLiquid, uint256, uint256, uint256, uint256) {
        xLiquid = _xLiquid;
        yLiquid = _yLiquid;
    } catch (bytes memory reason) {
        emit WithdrawalFailed(depositor, listingAddress, isX, index, isX ? withdrawal.amountA : withdrawal.amountB, string(abi.encodePacked("Liquidity details fetch failed: ", reason)));
        revert(string(abi.encodePacked("Liquidity details fetch failed: ", reason)));
    }
    WithdrawalContext memory context = WithdrawalContext({
        listingAddress: listingAddress,
        depositor: depositor,
        index: index,
        isX: isX,
        primaryAmount: isX ? withdrawal.amountA : withdrawal.amountB,
        compensationAmount: isX ? withdrawal.amountB : withdrawal.amountA,
        currentAllocation: 0,
        tokenA: ICCListing(listingAddress).tokenA(),
        tokenB: ICCListing(listingAddress).tokenB()
    });

    context = _validateSlotOwnership(context, liquidityTemplate);
    _checkLiquidity(context, xLiquid, yLiquid);
    _updateSlotAllocation(context, liquidityTemplate);
    _transferPrimaryToken(context, liquidityTemplate);
    _transferCompensationToken(context, liquidityTemplate);
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
  }