// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.22
// Changes:
// - v0.0.22: Refactored _depositToken and _depositNative into call tree with helper functions (_validateInputs, _fetchListingData, _fetchSlotData, _executeTokenTransfer, _executeNativeTransfer, _updateSlot). Added private DepositState struct and mapping for state management. Enhanced error messages and early validation. Updated compatibility comments.
// - v0.0.21: Updated _validateDeposit to use nextXSlotIDView/nextYSlotIDView for new slots, userXIndexView/userYIndexView for existing slots. Fixed _depositToken/_depositNative to claim fees for existing slots, reset dFeesAcc, and update allocation correctly.
// - v0.0.20: Modified _depositToken and _depositNative to check for existing slot, claim fees, reset dFeesAcc, and update slot allocation if found, else create new slot. Added depositor parameter for third-party deposits.
// - v0.0.19: Removed pool check in _validateDeposit to allow deposits in any pool state.
// - v0.0.18: Removed redundant isRouter checks, updated _executeTokenTransfer to use receivedAmount.
// Compatible with CCListingTemplate.sol (v0.1.0), CCMainPartial.sol (v0.0.14), CCLiquidityRouter.sol (v0.0.30), ICCLiquidity.sol (v0.0.5), ICCListing.sol (v0.0.7), CCLiquidityTemplate.sol (v0.1.1).

import "./CCMainPartial.sol";

contract CCLiquidityPartial is CCMainPartial {
    event TransferFailed(address indexed sender, address indexed token, uint256 amount, bytes reason);
    event DepositFailed(address indexed depositor, address token, uint256 amount, string reason);
    event FeesClaimed(address indexed listingAddress, uint256 liquidityIndex, uint256 xFees, uint256 yFees);
    event SlotDepositorChanged(bool isX, uint256 indexed slotIndex, address indexed oldDepositor, address indexed newDepositor);
    event DepositReceived(address indexed depositor, address token, uint256 amount, uint256 normalizedAmount);
    error InsufficientAllowance(address sender, address token, uint256 required, uint256 available);
    error InvalidInput(string reason);
    error InvalidListingState(string reason);
    error InvalidLiquidityContract(string reason);
    error SlotUpdateFailed(string reason);

    struct DepositState {
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
        bool hasExistingSlot;
        uint256 existingAllocation;
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

    mapping(address => DepositState) private depositStates;

    function _validateInputs(address listingAddress, address depositor, uint256 inputAmount, bool isTokenA) private pure returns (DepositState memory state) {
        if (listingAddress == address(0)) revert InvalidInput("Zero listing address");
        if (depositor == address(0)) revert InvalidInput("Zero depositor address");
        if (inputAmount == 0) revert InvalidInput("Zero input amount");
        return DepositState({
            listingAddress: listingAddress,
            depositor: depositor,
            inputAmount: inputAmount,
            isTokenA: isTokenA,
            tokenAddress: address(0),
            liquidityAddr: address(0),
            xAmount: 0,
            yAmount: 0,
            receivedAmount: 0,
            normalizedAmount: 0,
            index: 0,
            hasExistingSlot: false,
            existingAllocation: 0
        });
    }

    function _fetchListingData(DepositState memory state) private view returns (DepositState memory) {
        ICCListing listingContract = ICCListing(state.listingAddress);
        state.tokenAddress = state.isTokenA ? listingContract.tokenA() : listingContract.tokenB();
        if (state.tokenAddress == address(0) && !state.isTokenA) revert InvalidListingState("Use depositNative for ETH");
        state.liquidityAddr = listingContract.liquidityAddressView();
        if (state.liquidityAddr == address(0)) revert InvalidListingState("Invalid liquidity address");
        ICCLiquidity liquidityContract = ICCLiquidity(state.liquidityAddr);
        (state.xAmount, state.yAmount) = liquidityContract.liquidityAmounts();
        return state;
    }

    function _fetchSlotData(DepositState memory state) private view returns (DepositState memory) {
        ICCLiquidity liquidityContract = ICCLiquidity(state.liquidityAddr);
        uint256[] memory userIndices = state.isTokenA ? liquidityContract.userXIndexView(state.depositor) : liquidityContract.userYIndexView(state.depositor);
        if (userIndices.length > 0) {
            state.hasExistingSlot = true;
            state.index = userIndices[0];
            ICCLiquidity.Slot memory slot = state.isTokenA ? liquidityContract.getXSlotView(state.index) : liquidityContract.getYSlotView(state.index);
            if (slot.depositor != state.depositor) revert InvalidLiquidityContract("Slot depositor mismatch");
            state.existingAllocation = slot.allocation;
        } else {
            state.index = state.isTokenA ? liquidityContract.nextXSlotIDView() : liquidityContract.nextYSlotIDView();
        }
        return state;
    }

    function _executeTokenTransfer(DepositState memory state) private returns (DepositState memory) {
        if (state.tokenAddress == address(0)) revert InvalidInput("Use depositNative for ETH");
        uint256 allowance = IERC20(state.tokenAddress).allowance(msg.sender, address(this));
        if (allowance < state.inputAmount) revert InsufficientAllowance(msg.sender, state.tokenAddress, state.inputAmount, allowance);
        uint256 preBalanceRouter = IERC20(state.tokenAddress).balanceOf(address(this));
        try IERC20(state.tokenAddress).transferFrom(msg.sender, address(this), state.inputAmount) {
        } catch (bytes memory reason) {
            emit TransferFailed(msg.sender, state.tokenAddress, state.inputAmount, reason);
            revert("TransferFrom failed");
        }
        uint256 postBalanceRouter = IERC20(state.tokenAddress).balanceOf(address(this));
        state.receivedAmount = postBalanceRouter - preBalanceRouter;
        if (state.receivedAmount == 0) revert InvalidLiquidityContract("No tokens received by router");
        uint256 preBalanceTemplate = IERC20(state.tokenAddress).balanceOf(state.liquidityAddr);
        try IERC20(state.tokenAddress).transfer(state.liquidityAddr, state.receivedAmount) {
        } catch (bytes memory reason) {
            emit TransferFailed(address(this), state.tokenAddress, state.receivedAmount, reason);
            revert("Transfer to liquidity template failed");
        }
        uint256 postBalanceTemplate = IERC20(state.tokenAddress).balanceOf(state.liquidityAddr);
        state.receivedAmount = postBalanceTemplate - preBalanceTemplate;
        if (state.receivedAmount == 0) revert InvalidLiquidityContract("No tokens received by liquidity template");
        uint8 decimals = IERC20(state.tokenAddress).decimals();
        state.normalizedAmount = normalize(state.receivedAmount, decimals);
        return state;
    }

    function _executeNativeTransfer(DepositState memory state) private returns (DepositState memory) {
        if (state.tokenAddress != address(0)) revert InvalidInput("Use depositToken for ERC20");
        if (state.inputAmount != msg.value) revert InvalidInput("Incorrect ETH amount");
        uint256 preBalanceTemplate = state.liquidityAddr.balance;
        (bool success, bytes memory reason) = state.liquidityAddr.call{value: state.inputAmount}("");
        if (!success) {
            emit TransferFailed(msg.sender, address(0), state.inputAmount, reason);
            revert("ETH transfer to liquidity template failed");
        }
        uint256 postBalanceTemplate = state.liquidityAddr.balance;
        state.receivedAmount = postBalanceTemplate - preBalanceTemplate;
        if (state.receivedAmount == 0) revert InvalidLiquidityContract("No ETH received by liquidity template");
        state.normalizedAmount = normalize(state.receivedAmount, 18);
        return state;
    }

    function _updateSlot(DepositState memory state) private {
        ICCLiquidity liquidityContract = ICCLiquidity(state.liquidityAddr);
        ICCLiquidity.UpdateType[] memory updates = new ICCLiquidity.UpdateType[](1);
        updates[0] = ICCLiquidity.UpdateType(state.isTokenA ? 2 : 3, state.index, state.normalizedAmount, state.depositor, address(0));
        try liquidityContract.update(state.depositor, updates) {
        } catch (bytes memory reason) {
            emit DepositFailed(state.depositor, state.tokenAddress, state.receivedAmount, string(reason));
            revert SlotUpdateFailed(string(abi.encodePacked("Deposit update failed: ", reason)));
        }
        emit DepositReceived(state.depositor, state.tokenAddress, state.receivedAmount, state.normalizedAmount);
    }

    function _validateDeposit(address listingAddress, address depositor, uint256 inputAmount, bool isTokenA) internal view returns (DepositContext memory) {
        DepositState memory state = _validateInputs(listingAddress, depositor, inputAmount, isTokenA);
        state = _fetchListingData(state);
        state = _fetchSlotData(state);
        return DepositContext({
            listingAddress: state.listingAddress,
            depositor: state.depositor,
            inputAmount: state.inputAmount,
            isTokenA: state.isTokenA,
            tokenAddress: state.tokenAddress,
            liquidityAddr: state.liquidityAddr,
            xAmount: state.xAmount,
            yAmount: state.yAmount,
            receivedAmount: state.receivedAmount,
            normalizedAmount: state.normalizedAmount,
            index: state.index
        });
    }

    function _executeTokenTransfer(DepositContext memory context) internal returns (DepositContext memory) {
        DepositState memory state = depositStates[msg.sender];
        state = _validateInputs(context.listingAddress, context.depositor, context.inputAmount, context.isTokenA);
        state.tokenAddress = context.tokenAddress;
        state.liquidityAddr = context.liquidityAddr;
        state.xAmount = context.xAmount;
        state.yAmount = context.yAmount;
        state = _executeTokenTransfer(state);
        context.receivedAmount = state.receivedAmount;
        context.normalizedAmount = state.normalizedAmount;
        delete depositStates[msg.sender];
        return context;
    }

    function _executeNativeTransfer(DepositContext memory context) internal returns (DepositContext memory) {
        DepositState memory state = depositStates[msg.sender];
        state = _validateInputs(context.listingAddress, context.depositor, context.inputAmount, context.isTokenA);
        state.tokenAddress = context.tokenAddress;
        state.liquidityAddr = context.liquidityAddr;
        state.xAmount = context.xAmount;
        state.yAmount = context.yAmount;
        state = _executeNativeTransfer(state);
        context.receivedAmount = state.receivedAmount;
        context.normalizedAmount = state.normalizedAmount;
        delete depositStates[msg.sender];
        return context;
    }

    function _updateDeposit(DepositContext memory context) internal {
        DepositState memory state = depositStates[msg.sender];
        state = _validateInputs(context.listingAddress, context.depositor, context.inputAmount, context.isTokenA);
        state.tokenAddress = context.tokenAddress;
        state.liquidityAddr = context.liquidityAddr;
        state.receivedAmount = context.receivedAmount;
        state.normalizedAmount = context.normalizedAmount;
        state.index = context.index;
        _updateSlot(state);
        delete depositStates[msg.sender];
    }

    function _depositToken(address listingAddress, address depositor, uint256 inputAmount, bool isTokenA) internal returns (uint256) {
        DepositState memory state = _validateInputs(listingAddress, depositor, inputAmount, isTokenA);
        state = _fetchListingData(state);
        state = _fetchSlotData(state);
        depositStates[msg.sender] = state;
        if (state.hasExistingSlot) {
            _processFeeShare(listingAddress, depositor, state.index, isTokenA);
            state.normalizedAmount += state.existingAllocation;
        }
        state = _executeTokenTransfer(state);
        _updateSlot(state);
        uint256 receivedAmount = state.receivedAmount;
        delete depositStates[msg.sender];
        return receivedAmount;
    }

    function _depositNative(address listingAddress, address depositor, uint256 inputAmount, bool isTokenA) internal {
        DepositState memory state = _validateInputs(listingAddress, depositor, inputAmount, isTokenA);
        state = _fetchListingData(state);
        state = _fetchSlotData(state);
        depositStates[msg.sender] = state;
        if (state.hasExistingSlot) {
            _processFeeShare(listingAddress, depositor, state.index, isTokenA);
            state.normalizedAmount += state.existingAllocation;
        }
        state = _executeNativeTransfer(state);
        _updateSlot(state);
        delete depositStates[msg.sender];
    }

    function _validateFeeClaim(address listingAddress, address depositor, uint256 liquidityIndex, bool isX) internal view returns (FeeClaimContext memory) {
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        if (depositor == address(0)) revert InvalidInput("Invalid depositor");
        (uint256 xBalance, ) = listingContract.volumeBalances(0);
        if (xBalance == 0) revert InvalidListingState("Invalid listing balance");
        (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, , ) = liquidityContract.liquidityDetailsView();
        ICCLiquidity.Slot memory slot = isX ? liquidityContract.getXSlotView(liquidityIndex) : liquidityContract.getYSlotView(liquidityIndex);
        if (slot.depositor != depositor) revert InvalidLiquidityContract("Depositor not slot owner");
        if (xLiquid == 0 && yLiquid == 0) revert InvalidLiquidityContract("No liquidity available");
        if (slot.allocation == 0) revert InvalidLiquidityContract("No allocation for slot");
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
        FeeClaimContext memory context = _validateFeeClaim(listingAddress, depositor, liquidityIndex, isX);
        context = _calculateFeeShare(context);
        _executeFeeClaim(context);
    }

    function _changeDepositor(address listingAddress, address depositor, bool isX, uint256 slotIndex, address newDepositor) internal {
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        if (depositor == address(0)) revert InvalidInput("Invalid depositor");
        if (newDepositor == address(0)) revert InvalidInput("Invalid new depositor");
        try liquidityContract.changeSlotDepositor(depositor, isX, slotIndex, newDepositor) {
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Depositor change failed: ", reason)));
        }
    }

    function queryDepositorFees(address listingAddress, address depositor, uint256 liquidityIndex, bool isX) external view onlyValidListing(listingAddress) returns (uint256 feeShare) {
        FeeClaimContext memory context = _validateFeeClaim(listingAddress, depositor, liquidityIndex, isX);
        context = _calculateFeeShare(context);
        return context.feeShare;
    }

    function _prepWithdrawal(address listingAddress, address depositor, uint256 inputAmount, uint256 index, bool isX) internal returns (ICCLiquidity.PreparedWithdrawal memory) {
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        if (depositor == address(0)) revert InvalidInput("Invalid depositor");
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
}