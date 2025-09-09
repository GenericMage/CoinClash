// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

/*
// Version: 0.1.26
// Changes:
// - v0.1.26: Reordered _executeWithdrawal to call _transferWithdrawalAmount before _updateWithdrawalAllocation to prevent slot allocation reduction if transactNative or transactToken fails.
// - v0.1.25: Refactored _executeWithdrawal to address stack too deep error by splitting into helper functions (_fetchWithdrawalData, _updateWithdrawalAllocation, _transferWithdrawalAmount). Extended WithdrawalContext to include totalAllocationDeduct and price. Removed redundant local variables, ensured non-reverting behavior, and maintained v0.1.23 functionality (minimal checks, event emission, optional compensationAmount).
// - v0.1.24: Removed _checkLiquidity, WithdrawalPrepData struct, _getLiquidityDetails, _validateSlot, and _calculateCompensation, as they are no longer used after v0.1.23 simplified withdrawal logic to skip liquidity checks and helper functions.
// - v0.1.23: Refactored _prepWithdrawal to accept compensationAmount, validate only ownership and total allocation (output + converted compensation). Refactored _executeWithdrawal to remove liquidity checks, ensure non-reverting behavior, emit events for all failures, and update slot allocation based on converted compensation amount.
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
    // Transfers primary and compensation amounts, emits events for success or failure
    ICCListing listingContract = ICCListing(context.listingAddress);
    ICCLiquidity liquidityTemplate = ICCLiquidity(listingContract.liquidityAddressView());

    // Transfer primary amount
    if (context.primaryAmount > 0) {
        address token = context.isX ? context.tokenA : context.tokenB;
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 denormalizedAmount = denormalize(context.primaryAmount, decimals);
        if (token == address(0)) {
            try liquidityTemplate.transactNative(context.depositor, denormalizedAmount, context.depositor) {
                emit TransferSuccessful(context.depositor, context.listingAddress, context.isX, context.index, token, denormalizedAmount);
            } catch (bytes memory reason) {
                emit WithdrawalFailed(context.depositor, context.listingAddress, context.isX, context.index, context.primaryAmount, string(abi.encodePacked("Native transfer failed: ", reason)));
            }
        } else {
            try liquidityTemplate.transactToken(context.depositor, token, denormalizedAmount, context.depositor) {
                emit TransferSuccessful(context.depositor, context.listingAddress, context.isX, context.index, token, denormalizedAmount);
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
            } catch (bytes memory reason) {
                emit WithdrawalFailed(context.depositor, context.listingAddress, !context.isX, context.index, context.compensationAmount, string(abi.encodePacked("Native compensation transfer failed: ", reason)));
            }
        } else {
            try liquidityTemplate.transactToken(context.depositor, token, denormalizedAmount, context.depositor) {
                emit TransferSuccessful(context.depositor, context.listingAddress, !context.isX, context.index, token, denormalizedAmount);
            } catch (bytes memory reason) {
                emit WithdrawalFailed(context.depositor, context.listingAddress, !context.isX, context.index, context.compensationAmount, string(abi.encodePacked("Token compensation transfer failed: ", reason)));
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