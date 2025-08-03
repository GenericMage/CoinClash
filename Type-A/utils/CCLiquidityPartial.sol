// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.21
// Changes:
// - v0.0.21: Updated _validateDeposit to use nextXSlotIDView/nextYSlotIDView for new slots, userXIndexView/userYIndexView for existing slots. Fixed _depositToken/_depositNative to claim fees for existing slots, reset dFeesAcc, and update allocation correctly. Updated compatibility comments.
// - v0.0.20: Modified _depositToken and _depositNative to check for existing slot, claim fees, reset dFeesAcc, and update slot allocation if found, else create new slot. Added depositor parameter for third-party deposits.
// - v0.0.19: Removed pool check in _validateDeposit to allow deposits in any pool state.
// - v0.0.18: Removed redundant isRouter checks, updated _executeTokenTransfer to use receivedAmount.
// Compatible with CCListingTemplate.sol (v0.1.0), CCMainPartial.sol (v0.0.12), CCLiquidityRouter.sol (v0.0.27), ICCLiquidity.sol (v0.0.5), ICCListing.sol (v0.0.7), CCLiquidityTemplate.sol (v0.1.1).

import "./CCMainPartial.sol";

contract CCLiquidityPartial is CCMainPartial {
    event TransferFailed(address indexed sender, address indexed token, uint256 amount, bytes reason);
    event DepositFailed(address indexed depositor, address token, uint256 amount, string reason);
    event FeesClaimed(address indexed listingAddress, uint256 liquidityIndex, uint256 xFees, uint256 yFees);
    event SlotDepositorChanged(bool isX, uint256 indexed slotIndex, address indexed oldDepositor, address indexed newDepositor);
    event DepositReceived(address indexed depositor, address token, uint256 amount, uint256 normalizedAmount);
    error InsufficientAllowance(address sender, address token, uint256 required, uint256 available);

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
        // Validates deposit, assigns index from userX/YIndexView for existing slots or nextX/YSlotIDView for new slots
        ICCListing listingContract = ICCListing(listingAddress);
        address tokenAddress = isTokenA ? listingContract.tokenA() : listingContract.tokenB();
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        uint256 index;
        uint256[] memory userIndices = isTokenA ? liquidityContract.userXIndexView(depositor) : liquidityContract.userYIndexView(depositor);
        if (userIndices.length > 0) {
            index = userIndices[0]; // Use first existing slot
        } else {
            index = isTokenA ? liquidityContract.nextXSlotIDView() : liquidityContract.nextYSlotIDView(); // New slot ID
        }
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
            index: index
        });
    }

    function _executeTokenTransfer(DepositContext memory context) internal returns (DepositContext memory) {
        // Executes ERC20 token transfer with pre/post balance checks
        require(context.tokenAddress != address(0), "Use depositNative for ETH");
        uint256 allowance = IERC20(context.tokenAddress).allowance(msg.sender, address(this));
        if (allowance < context.inputAmount) revert InsufficientAllowance(msg.sender, context.tokenAddress, context.inputAmount, allowance);
        uint256 preBalanceRouter = IERC20(context.tokenAddress).balanceOf(address(this));
        try IERC20(context.tokenAddress).transferFrom(msg.sender, address(this), context.inputAmount) {
        } catch (bytes memory reason) {
            emit TransferFailed(msg.sender, context.tokenAddress, context.inputAmount, reason);
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
        // Executes ETH transfer with pre/post balance checks
        require(context.tokenAddress == address(0), "Use depositToken for ERC20");
        require(context.inputAmount == msg.value, "Incorrect ETH amount");
        uint256 preBalanceTemplate = context.liquidityAddr.balance;
        (bool success, bytes memory reason) = context.liquidityAddr.call{value: context.inputAmount}("");
        if (!success) {
            emit TransferFailed(msg.sender, address(0), context.inputAmount, reason);
            revert("ETH transfer to liquidity template failed");
        }
        uint256 postBalanceTemplate = context.liquidityAddr.balance;
        context.receivedAmount = postBalanceTemplate - preBalanceTemplate;
        require(context.receivedAmount > 0, "No ETH received by liquidity template");
        context.normalizedAmount = normalize(context.receivedAmount, 18);
        return context;
    }

    function _updateDeposit(DepositContext memory context) internal {
        // Updates liquidity slot with normalized amount
        ICCLiquidity liquidityContract = ICCLiquidity(context.liquidityAddr);
        ICCLiquidity.UpdateType[] memory updates = new ICCLiquidity.UpdateType[](1);
        updates[0] = ICCLiquidity.UpdateType(context.isTokenA ? 2 : 3, context.index, context.normalizedAmount, context.depositor, address(0));
        try liquidityContract.update(context.depositor, updates) {
        } catch (bytes memory reason) {
            emit DepositFailed(context.depositor, context.tokenAddress, context.receivedAmount, string(reason));
            revert(string(abi.encodePacked("Deposit update failed: ", reason)));
        }
        emit DepositReceived(context.depositor, context.tokenAddress, context.receivedAmount, context.normalizedAmount);
    }

    function _depositToken(address listingAddress, address depositor, uint256 inputAmount, bool isTokenA) internal returns (uint256) {
        // Handles ERC20 token deposit, claims fees and updates existing slot or creates new
        DepositContext memory context = _validateDeposit(listingAddress, depositor, inputAmount, isTokenA);
        ICCLiquidity liquidityContract = ICCLiquidity(context.liquidityAddr);
        uint256[] memory indices = isTokenA ? liquidityContract.userXIndexView(depositor) : liquidityContract.userYIndexView(depositor);
        if (indices.length > 0) {
            // Claim fees for existing slot and reset dFeesAcc
            _processFeeShare(listingAddress, depositor, indices[0], isTokenA);
            ICCLiquidity.Slot memory slot = isTokenA ? liquidityContract.getXSlotView(indices[0]) : liquidityContract.getYSlotView(indices[0]);
            context.index = indices[0];
            context = _executeTokenTransfer(context);
            context.normalizedAmount += slot.allocation; // Add to existing allocation
            ICCLiquidity.UpdateType[] memory updates = new ICCLiquidity.UpdateType[](1);
            updates[0] = ICCLiquidity.UpdateType(isTokenA ? 2 : 3, context.index, context.normalizedAmount, context.depositor, address(0));
            try liquidityContract.update(context.depositor, updates) {
            } catch (bytes memory reason) {
                emit DepositFailed(context.depositor, context.tokenAddress, context.receivedAmount, string(reason));
                revert(string(abi.encodePacked("Deposit update failed: ", reason)));
            }
            emit DepositReceived(context.depositor, context.tokenAddress, context.receivedAmount, context.normalizedAmount);
        } else {
            context = _executeTokenTransfer(context);
            _updateDeposit(context);
        }
        return context.receivedAmount;
    }

    function _depositNative(address listingAddress, address depositor, uint256 inputAmount, bool isTokenA) internal {
        // Handles ETH deposit, claims fees and updates existing slot or creates new
        DepositContext memory context = _validateDeposit(listingAddress, depositor, inputAmount, isTokenA);
        ICCLiquidity liquidityContract = ICCLiquidity(context.liquidityAddr);
        uint256[] memory indices = isTokenA ? liquidityContract.userXIndexView(depositor) : liquidityContract.userYIndexView(depositor);
        if (indices.length > 0) {
            // Claim fees for existing slot and reset dFeesAcc
            _processFeeShare(listingAddress, depositor, indices[0], isTokenA);
            ICCLiquidity.Slot memory slot = isTokenA ? liquidityContract.getXSlotView(indices[0]) : liquidityContract.getYSlotView(indices[0]);
            context.index = indices[0];
            context = _executeNativeTransfer(context);
            context.normalizedAmount += slot.allocation; // Add to existing allocation
            ICCLiquidity.UpdateType[] memory updates = new ICCLiquidity.UpdateType[](1);
            updates[0] = ICCLiquidity.UpdateType(isTokenA ? 2 : 3, context.index, context.normalizedAmount, context.depositor, address(0));
            try liquidityContract.update(context.depositor, updates) {
            } catch (bytes memory reason) {
                emit DepositFailed(context.depositor, context.tokenAddress, context.receivedAmount, string(reason));
                revert(string(abi.encodePacked("Deposit update failed: ", reason)));
            }
            emit DepositReceived(context.depositor, context.tokenAddress, context.receivedAmount, context.normalizedAmount);
        } else {
            context = _executeNativeTransfer(context);
            _updateDeposit(context);
        }
    }

    function _prepWithdrawal(address listingAddress, address depositor, uint256 inputAmount, uint256 index, bool isX) internal returns (ICCLiquidity.PreparedWithdrawal memory) {
        // Prepares withdrawal, calls xPrepOut or yPrepOut
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        require(depositor != address(0), "Invalid depositor");
        if (isX) {
            try liquidityContract.xPrepOut(depositor, inputAmount, index) returns (ICCLiquidity.PreparedWithdrawal memory result) {
                return result;
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Withdrawal preparation failed: ", reason)));
            }
        } else {
            try liquidityContract.yPrepOut(depositor, inputAmount, index) returns (ICCLiquidity.PreparedWithdrawal memory result) {
                return result;
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Withdrawal preparation failed: ", reason)));
            }
        }
    }

    function _executeWithdrawal(address listingAddress, address depositor, uint256 index, bool isX, ICCLiquidity.PreparedWithdrawal memory withdrawal) internal {
        // Executes withdrawal, calls xExecuteOut or yExecuteOut
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        if (isX) {
            try liquidityContract.xExecuteOut(depositor, index, withdrawal) {
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Withdrawal execution failed: ", reason)));
            }
        } else {
            try liquidityContract.yExecuteOut(depositor, index, withdrawal) {
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Withdrawal execution failed: ", reason)));
            }
        }
    }

    function _validateFeeClaim(address listingAddress, address depositor, uint256 liquidityIndex, bool isX) internal view returns (FeeClaimContext memory) {
        // Validates fee claim parameters
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
        // Calculates fee share based on allocation and liquidity
        uint256 contributedFees = context.fees > context.dFeesAcc ? context.fees - context.dFeesAcc : 0;
        uint256 liquidityContribution = context.liquid > 0 ? (context.allocation * 1e18) / context.liquid : 0;
        context.feeShare = (contributedFees * liquidityContribution) / 1e18;
        context.feeShare = context.feeShare > context.fees ? context.fees : context.feeShare;
        return context;
    }

    function _executeFeeClaim(FeeClaimContext memory context) internal {
        // Executes fee claim, updates fees and slot
        if (context.feeShare == 0) revert("No fees to claim");
        ICCLiquidity liquidityContract = ICCLiquidity(context.liquidityAddr);
        ICCLiquidity.UpdateType[] memory updates = new ICCLiquidity.UpdateType[](2);
        updates[0] = ICCLiquidity.UpdateType(1, context.isX ? 1 : 0, context.fees - context.feeShare, address(0), address(0));
        updates[1] = ICCLiquidity.UpdateType(context.isX ? 2 : 3, context.liquidityIndex, context.allocation, context.depositor, address(0));
        try liquidityContract.update(context.depositor, updates) {
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
        // Processes fee share claim
        FeeClaimContext memory context = _validateFeeClaim(listingAddress, depositor, liquidityIndex, isX);
        context = _calculateFeeShare(context);
        _executeFeeClaim(context);
    }

    function _changeDepositor(address listingAddress, address depositor, bool isX, uint256 slotIndex, address newDepositor) internal {
        // Changes slot depositor
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        require(depositor != address(0), "Invalid depositor");
        require(newDepositor != address(0), "Invalid new depositor");
        try liquidityContract.changeSlotDepositor(depositor, isX, slotIndex, newDepositor) {
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Depositor change failed: ", reason)));
        }
    }

    function queryDepositorFees(address listingAddress, address depositor, uint256 liquidityIndex, bool isX) external view onlyValidListing(listingAddress) returns (uint256 feeShare) {
        // Queries pending fees for a depositor
        FeeClaimContext memory context = _validateFeeClaim(listingAddress, depositor, liquidityIndex, isX);
        context = _calculateFeeShare(context);
        return context.feeShare;
    }
}