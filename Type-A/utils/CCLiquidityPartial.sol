// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

/*
// Version: 0.1.32
// Changes:
// - v0.1.32: Split FeeClaimContext into FeeClaimCore and FeeClaimDetails to fix stack too deep error. Added helper functions _fetchLiquidityDetails and _fetchSlotDetails in _validateFeeClaim. Updated _validateFeeClaim, _calculateFeeShare, _executeFeeClaim to use new structs. Updated _processFeeShare to use FeeClaimCore and FeeClaimDetails structs. 
// - v0.1.31: Streamlined FeeClaimContext by removing unused xBalance, liquid, fees fields. Updated _validateFeeClaim and _calculateFeeShare to use new struct. 
// - v0.1.30: Fixed _calculateFeeShare to use xFeesAcc/yFeesAcc instead of xFees/yFees for contributedFees calculation. Added xFeesAcc, yFeesAcc to FeeClaimContext struct. Fixed _validateFeeClaim to include xFeesAcc, yFeesAcc in constructor.
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
    uint256 totalAllocationDeduct; // Added to store total allocation to deduct
    uint256 price; // Added to store price for compensation conversion
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

    struct FeeClaimCore {
    address listingAddress;
    address depositor;
    uint256 liquidityIndex;
    bool isX;
    address liquidityAddr;
    address transferToken;
    uint256 feeShare;
}

struct FeeClaimDetails {
    uint256 xLiquid;
    uint256 yLiquid;
    uint256 xFees;
    uint256 yFees;
    uint256 xFeesAcc;
    uint256 yFeesAcc;
    uint256 allocation;
    uint256 dFeesAcc;
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

// Refactored _prepWithdrawal function  to accept user supplied compensation amount (with validation)
function _prepWithdrawal(address listingAddress, address depositor, uint256 outputAmount, uint256 compensationAmount, uint256 index, bool isX) internal returns (ICCLiquidity.PreparedWithdrawal memory) {
    // Prepares withdrawal, validates ownership and sufficient allocation (output + converted compensation)
    ICCListing listingContract = ICCListing(listingAddress);
    address liquidityAddr = listingContract.liquidityAddressView();
    ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
    ICCLiquidity.Slot memory slot = isX ? liquidityContract.getXSlotView(index) : liquidityContract.getYSlotView(index);
    
    if (slot.depositor != depositor) {
        emit ValidationFailed(depositor, listingAddress, isX, index, "Not slot owner");
        return ICCLiquidity.PreparedWithdrawal(0, 0);
    }
    if (slot.allocation == 0) {
        emit ValidationFailed(depositor, listingAddress, isX, index, "No allocation");
        return ICCLiquidity.PreparedWithdrawal(0, 0);
    }

    uint256 totalAllocationNeeded = outputAmount;
    if (compensationAmount > 0) {
        uint256 price;
        try listingContract.prices(0) returns (uint256 _price) {
            price = _price;
        } catch (bytes memory reason) {
            emit ValidationFailed(depositor, listingAddress, isX, index, string(abi.encodePacked("Price fetch failed: ", reason)));
            return ICCLiquidity.PreparedWithdrawal(0, 0);
        }
        uint256 convertedCompensation = isX ? (compensationAmount * 1e18) / price : (compensationAmount * price) / 1e18;
        totalAllocationNeeded += convertedCompensation;
    }

    if (totalAllocationNeeded > slot.allocation) {
        emit ValidationFailed(depositor, listingAddress, isX, index, "Insufficient allocation for output and compensation");
        return ICCLiquidity.PreparedWithdrawal(0, 0);
    }

    return ICCLiquidity.PreparedWithdrawal({
        amountA: isX ? outputAmount : compensationAmount,
        amountB: isX ? compensationAmount : outputAmount
    });
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

// Updated function to reorder transfer and allocation updates 
function _executeWithdrawal(address listingAddress, address depositor, uint256 index, bool isX, ICCLiquidity.PreparedWithdrawal memory withdrawal) internal {
    // Executes withdrawal, emits events for failures, updates slot allocation based on output + converted compensation
    WithdrawalContext memory context = WithdrawalContext({
        listingAddress: listingAddress,
        depositor: depositor,
        index: index,
        isX: isX,
        primaryAmount: isX ? withdrawal.amountA : withdrawal.amountB,
        compensationAmount: isX ? withdrawal.amountB : withdrawal.amountA,
        currentAllocation: 0,
        tokenA: address(0),
        tokenB: address(0),
        totalAllocationDeduct: 0,
        price: 0
    });

    // Fetch liquidity address, tokens, slot data, and price
    if (!_fetchWithdrawalData(context)) return;

    // Transfer primary and compensation amounts first to ensure transfers succeed before updating allocation
    _transferWithdrawalAmount(context);

    // Calculate and update slot allocation after successful transfers
    if (!_updateWithdrawalAllocation(context)) return;
}

function _fetchWithdrawalData(WithdrawalContext memory context) internal returns (bool) {
    // Fetches liquidity address, tokens, slot data, and price, emits events on failure
    ICCListing listingContract = ICCListing(context.listingAddress);
    address liquidityAddress;
    try listingContract.liquidityAddressView() returns (address addr) {
        liquidityAddress = addr;
    } catch (bytes memory reason) {
        emit ValidationFailed(context.depositor, context.listingAddress, context.isX, context.index, string(abi.encodePacked("liquidityAddressView failed: ", reason)));
        return false;
    }
    if (liquidityAddress == address(0)) {
        emit ValidationFailed(context.depositor, context.listingAddress, context.isX, context.index, "Invalid liquidity address");
        return false;
    }
    ICCLiquidity liquidityTemplate = ICCLiquidity(liquidityAddress);
    
    // Fetch token addresses
    context.tokenA = listingContract.tokenA();
    context.tokenB = listingContract.tokenB();

    // Fetch current allocation
    ICCLiquidity.Slot memory slot = context.isX ? liquidityTemplate.getXSlotView(context.index) : liquidityTemplate.getYSlotView(context.index);
    context.currentAllocation = slot.allocation;

    // Fetch price for compensation conversion
    if (context.compensationAmount > 0) {
        try listingContract.prices(0) returns (uint256 _price) {
            context.price = _price;
        } catch (bytes memory reason) {
            emit ValidationFailed(context.depositor, context.listingAddress, context.isX, context.index, string(abi.encodePacked("Price fetch failed: ", reason)));
            return false;
        }
    }
    return true;
}

function _updateWithdrawalAllocation(WithdrawalContext memory context) internal returns (bool) {
    // Calculates total allocation to deduct and updates slot, emits events on failure
    ICCListing listingContract = ICCListing(context.listingAddress);
    context.totalAllocationDeduct = context.primaryAmount;
    if (context.compensationAmount > 0 && context.price > 0) {
        uint256 convertedCompensation = context.isX ? (context.compensationAmount * 1e18) / context.price : (context.compensationAmount * context.price) / 1e18;
        context.totalAllocationDeduct += convertedCompensation;
        emit CompensationCalculated(context.depositor, context.listingAddress, context.isX, context.primaryAmount, context.compensationAmount);
    }

    if (context.totalAllocationDeduct > 0) {
        ICCLiquidity.UpdateType[] memory updates = new ICCLiquidity.UpdateType[](1);
        updates[0] = ICCLiquidity.UpdateType(context.isX ? 2 : 3, context.index, context.currentAllocation - context.totalAllocationDeduct, context.depositor, address(0));
        try ICCLiquidity(listingContract.liquidityAddressView()).ccUpdate(context.depositor, updates) {
        } catch (bytes memory reason) {
            emit WithdrawalFailed(context.depositor, context.listingAddress, context.isX, context.index, context.primaryAmount, string(abi.encodePacked("Slot update failed: ", reason)));
            return false;
        }
    }
    return true;
}

function _transferWithdrawalAmount(WithdrawalContext memory context) internal {
    // Transfers primary and compensation amounts, emits events for success or failure, reverts if compensation transfer fails when compensationAmount > 0
    ICCListing listingContract = ICCListing(context.listingAddress);
    ICCLiquidity liquidityTemplate = ICCLiquidity(listingContract.liquidityAddressView());
    bool primarySuccess = false;
    bool compensationSuccess = true; // Default to true if no compensation transfer is needed

    // Transfer primary amount
    if (context.primaryAmount > 0) {
        address token = context.isX ? context.tokenA : context.tokenB;
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 denormalizedAmount = denormalize(context.primaryAmount, decimals);
        if (token == address(0)) {
            try liquidityTemplate.transactNative(context.depositor, denormalizedAmount, context.depositor) {
                emit TransferSuccessful(context.depositor, context.listingAddress, context.isX, context.index, token, denormalizedAmount);
                primarySuccess = true;
            } catch (bytes memory reason) {
                emit WithdrawalFailed(context.depositor, context.listingAddress, context.isX, context.index, context.primaryAmount, string(abi.encodePacked("Native transfer failed: ", reason)));
            }
        } else {
            try liquidityTemplate.transactToken(context.depositor, token, denormalizedAmount, context.depositor) {
                emit TransferSuccessful(context.depositor, context.listingAddress, context.isX, context.index, token, denormalizedAmount);
                primarySuccess = true;
            } catch (bytes memory reason) {
                emit WithdrawalFailed(context.depositor, context.listingAddress, context.isX, context.index, context.primaryAmount, string(abi.encodePacked("Token transfer failed: ", reason)));
            }
        }
    }

    // Transfer compensation amount
    if (context.compensationAmount > 0) {
        address token = context.isX ? context.tokenB : context.tokenA;
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 denormalizedAmount = denormalize(context.compensationAmount, decimals);
        if (token == address(0)) {
            try liquidityTemplate.transactNative(context.depositor, denormalizedAmount, context.depositor) {
                emit TransferSuccessful(context.depositor, context.listingAddress, !context.isX, context.index, token, denormalizedAmount);
                compensationSuccess = true;
            } catch (bytes memory reason) {
                emit WithdrawalFailed(context.depositor, context.listingAddress, !context.isX, context.index, context.compensationAmount, string(abi.encodePacked("Native compensation transfer failed: ", reason)));
                compensationSuccess = false;
            }
        } else {
            try liquidityTemplate.transactToken(context.depositor, token, denormalizedAmount, context.depositor) {
                emit TransferSuccessful(context.depositor, context.listingAddress, !context.isX, context.index, token, denormalizedAmount);
                compensationSuccess = true;
            } catch (bytes memory reason) {
                emit WithdrawalFailed(context.depositor, context.listingAddress, !context.isX, context.index, context.compensationAmount, string(abi.encodePacked("Token compensation transfer failed: ", reason)));
                compensationSuccess = false;
            }
        }
    }

    // Revert if compensation transfer failed when compensationAmount > 0
    if (context.compensationAmount > 0 && !compensationSuccess) {
        revert("Compensation transfer failed, aborting withdrawal to prevent allocation update");
    }

    // Require primary transfer success if primaryAmount > 0
    if (context.primaryAmount > 0 && !primarySuccess) {
        revert("Primary transfer failed, aborting withdrawal to prevent allocation update");
    }
}

function _fetchLiquidityDetails(address liquidityAddr) private view returns (FeeClaimDetails memory) {
    // Fetches liquidity details from liquidity contract
    ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
    (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, uint256 xFeesAcc, uint256 yFeesAcc) = liquidityContract.liquidityDetailsView();
    return FeeClaimDetails({
        xLiquid: xLiquid,
        yLiquid: yLiquid,
        xFees: xFees,
        yFees: yFees,
        xFeesAcc: xFeesAcc,
        yFeesAcc: yFeesAcc,
        allocation: 0,
        dFeesAcc: 0
    });
}

function _fetchSlotDetails(address liquidityAddr, uint256 liquidityIndex, bool isX, address depositor) private view returns (FeeClaimDetails memory details) {
    // Fetches slot details and validates ownership
    ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
    ICCLiquidity.Slot memory slot = isX ? liquidityContract.getXSlotView(liquidityIndex) : liquidityContract.getYSlotView(liquidityIndex);
    require(slot.depositor == depositor, "Depositor not slot owner");
    details.allocation = slot.allocation;
    details.dFeesAcc = slot.dFeesAcc;
}

function _validateFeeClaim(address listingAddress, address depositor, uint256 liquidityIndex, bool isX) internal returns (FeeClaimCore memory, FeeClaimDetails memory) {
    // Validates fee claim parameters and ensures sufficient fees
    require(depositor != address(0), "Invalid depositor");
    ICCListing listingContract = ICCListing(listingAddress);
    address liquidityAddr = listingContract.liquidityAddressView();
    FeeClaimDetails memory details = _fetchLiquidityDetails(liquidityAddr);
    require(details.xLiquid > 0 || details.yLiquid > 0, "No liquidity available");
    details = _fetchSlotDetails(liquidityAddr, liquidityIndex, isX, depositor);
    require(details.allocation > 0, "No allocation for slot");
    uint256 fees = isX ? details.yFees : details.xFees;
    if (fees == 0) {
        emit FeeValidationFailed(depositor, listingAddress, isX, liquidityIndex, "No fees available");
        revert("No fees available");
    }
    return (
        FeeClaimCore({
            listingAddress: listingAddress,
            depositor: depositor,
            liquidityIndex: liquidityIndex,
            isX: isX,
            liquidityAddr: liquidityAddr,
            transferToken: isX ? listingContract.tokenB() : listingContract.tokenA(),
            feeShare: 0
        }),
        details
    );
}

function _calculateFeeShare(FeeClaimCore memory core, FeeClaimDetails memory details) internal pure returns (FeeClaimCore memory) {
    // Calculate fee share using xFeesAcc/yFeesAcc for contributed fees
    uint256 feesAcc = core.isX ? details.yFeesAcc : details.xFeesAcc;
    uint256 contributedFees = feesAcc > details.dFeesAcc ? feesAcc - details.dFeesAcc : 0;
    uint256 liquidityContribution = core.isX ? details.xLiquid : details.yLiquid;
    liquidityContribution = liquidityContribution > 0 ? (details.allocation * 1e18) / liquidityContribution : 0;
    core.feeShare = (contributedFees * liquidityContribution) / 1e18;
    core.feeShare = core.feeShare > (core.isX ? details.yFees : details.xFees) ? (core.isX ? details.yFees : details.xFees) : core.feeShare;
    return core;
}

function _executeFeeClaim(FeeClaimCore memory core, FeeClaimDetails memory details) internal {
    // Executes fee claim, updates fees and dFeesAcc, transfers fees
    if (core.feeShare == 0) {
        emit NoFeesToClaim(core.depositor, core.listingAddress, core.isX, core.liquidityIndex);
        return;
    }
    ICCLiquidity liquidityContract = ICCLiquidity(core.liquidityAddr);
    ICCLiquidity.UpdateType[] memory updates = new ICCLiquidity.UpdateType[](2);
    updates[0] = ICCLiquidity.UpdateType(core.isX ? 9 : 8, core.isX ? 1 : 0, core.feeShare, address(0), address(0));
    updates[1] = ICCLiquidity.UpdateType(core.isX ? 6 : 7, core.liquidityIndex, core.isX ? details.yFeesAcc : details.xFeesAcc, core.depositor, address(0));
    try liquidityContract.ccUpdate(core.depositor, updates) {
    } catch (bytes memory reason) {
        revert(string(abi.encodePacked("Fee claim update failed: ", reason)));
    }
    uint8 decimals = core.transferToken == address(0) ? 18 : IERC20(core.transferToken).decimals();
    uint256 denormalizedFee = denormalize(core.feeShare, decimals);
    if (core.transferToken == address(0)) {
        try liquidityContract.transactNative(core.depositor, denormalizedFee, core.depositor) {
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Fee claim transfer failed: ", reason)));
        }
    } else {
        try liquidityContract.transactToken(core.depositor, core.transferToken, denormalizedFee, core.depositor) {
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Fee claim transfer failed: ", reason)));
        }
    }
    emit FeesClaimed(core.listingAddress, core.liquidityIndex, core.isX ? 0 : core.feeShare, core.isX ? core.feeShare : 0);
}

    function _processFeeShare(address listingAddress, address depositor, uint256 liquidityIndex, bool isX) internal {
    // Processes fee share using new FeeClaimCore and FeeClaimDetails structs
    (FeeClaimCore memory core, FeeClaimDetails memory details) = _validateFeeClaim(listingAddress, depositor, liquidityIndex, isX);
    core = _calculateFeeShare(core, details);
    _executeFeeClaim(core, details);
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