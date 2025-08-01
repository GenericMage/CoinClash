// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.17
// Changes:
// - v0.0.17: Removed listingId from FeeClaimContext and FeesClaimed event, updated _validateFeeClaim to remove getListingId call, as it’s unnecessary with onlyValidListing validation. Updated compatibility comments.
// - v0.0.16: Modified _executeTokenTransfer and _executeNativeTransfer to transfer tokens/ETH to CCLiquidityTemplate. Added pre/post balance checks for tax-on-transfer tokens.
// - v0.0.15: Refactored _processFeeShare with FeeClaimContext struct and helper functions to reduce stack usage.
// Compatible with CCListingTemplate.sol (v0.0.10), CCMainPartial.sol (v0.0.10), CCLiquidityRouter.sol (v0.0.23), ICCLiquidity.sol (v0.0.4), ICCListing.sol (v0.0.7), CCLiquidityTemplate.sol (v0.0.20).

import "./CCMainPartial.sol";

contract CCLiquidityPartial is CCMainPartial {
    // Emitted when IERC20.transfer fails
    event TransferFailed(address indexed sender, address indexed token, uint256 amount, bytes reason);
    // Emitted when deposit fails
    event DepositFailed(address indexed depositor, address token, uint256 amount, string reason);
    // Emitted when fees are claimed
    event FeesClaimed(address indexed listingAddress, uint256 liquidityIndex, uint256 xFees, uint256 yFees);
    // Emitted when depositor is changed
    event SlotDepositorChanged(bool isX, uint256 indexed slotIndex, address indexed oldDepositor, address indexed newDepositor);
    // Emitted when deposit is received
    event DepositReceived(address indexed depositor, address token, uint256 amount, uint256 normalizedAmount);
    // Error for insufficient allowance
    error InsufficientAllowance(address sender, address token, uint256 required, uint256 available);

    // Struct to hold deposit data, reducing stack usage
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

    // Struct to hold fee claim data, reducing stack usage
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

    // Validates deposit inputs and fetches token/liquidity data
    function _validateDeposit(address listingAddress, address depositor, uint256 inputAmount, bool isTokenA) internal view returns (DepositContext memory) {
        ICCListing listingContract = ICCListing(listingAddress);
        address tokenAddress = isTokenA ? listingContract.tokenA() : listingContract.tokenB();
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        require(liquidityContract.isRouter(address(this)), "Router not registered");
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        require(xAmount == 0 && yAmount == 0 || (isTokenA ? xAmount : yAmount) > 0, "Invalid initial deposit");
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

    // Handles ERC20 token transfer and approval
    function _executeTokenTransfer(DepositContext memory context) internal returns (DepositContext memory) {
        require(context.tokenAddress != address(0), "Use depositNative for ETH");
        uint256 allowance = IERC20(context.tokenAddress).allowance(context.depositor, address(this));
        if (allowance < context.inputAmount) revert InsufficientAllowance(context.depositor, context.tokenAddress, context.inputAmount, allowance);
        uint256 preBalanceRouter = IERC20(context.tokenAddress).balanceOf(address(this));
        try IERC20(context.tokenAddress).transferFrom(context.depositor, address(this), context.inputAmount) {
        } catch (bytes memory reason) {
            emit TransferFailed(context.depositor, context.tokenAddress, context.inputAmount, reason);
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

    // Validates ETH amount for native deposit and forwards to liquidity template
    function _executeNativeTransfer(DepositContext memory context) internal returns (DepositContext memory) {
        require(context.tokenAddress == address(0), "Use depositToken for ERC20");
        require(context.inputAmount == msg.value, "Incorrect ETH amount");
        uint256 preBalanceTemplate = context.liquidityAddr.balance;
        (bool success, bytes memory reason) = context.liquidityAddr.call{value: context.inputAmount}("");
        if (!success) {
            emit TransferFailed(context.depositor, address(0), context.inputAmount, reason);
            revert("ETH transfer to liquidity template failed");
        }
        uint256 postBalanceTemplate = context.liquidityAddr.balance;
        context.receivedAmount = postBalanceTemplate - preBalanceTemplate;
        require(context.receivedAmount > 0, "No ETH received by liquidity template");
        context.normalizedAmount = normalize(context.receivedAmount, 18);
        return context;
    }

    // Creates and applies liquidity update
    function _updateDeposit(DepositContext memory context) internal {
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

    // Internal function to handle token deposit
    function _depositToken(address listingAddress, address depositor, uint256 inputAmount, bool isTokenA) internal returns (uint256) {
        DepositContext memory context = _validateDeposit(listingAddress, depositor, inputAmount, isTokenA);
        context = _executeTokenTransfer(context);
        _updateDeposit(context);
        return context.receivedAmount;
    }

    // Internal function to handle native ETH deposit
    function _depositNative(address listingAddress, address depositor, uint256 inputAmount, bool isTokenA) internal {
        DepositContext memory context = _validateDeposit(listingAddress, depositor, inputAmount, isTokenA);
        context = _executeNativeTransfer(context);
        _updateDeposit(context);
    }

    // Internal function to prepare withdrawal
    function _prepWithdrawal(address listingAddress, address depositor, uint256 inputAmount, uint256 index, bool isX) internal returns (ICCLiquidity.PreparedWithdrawal memory) {
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        require(liquidityContract.isRouter(address(this)), "Router not registered");
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

    // Internal function to execute withdrawal
    function _executeWithdrawal(address listingAddress, address depositor, uint256 index, bool isX, ICCLiquidity.PreparedWithdrawal memory withdrawal) internal {
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        require(liquidityContract.isRouter(address(this)), "Router not registered");
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

    // Validates fee claim inputs and fetches liquidity/slot data
    function _validateFeeClaim(address listingAddress, address depositor, uint256 liquidityIndex, bool isX) internal view returns (FeeClaimContext memory) {
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        require(liquidityContract.isRouter(address(this)), "Router not registered");
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

    // Calculates fee share based on liquidity contribution
    function _calculateFeeShare(FeeClaimContext memory context) internal pure returns (FeeClaimContext memory) {
        uint256 contributedFees = context.fees > context.dFeesAcc ? context.fees - context.dFeesAcc : 0;
        uint256 liquidityContribution = context.liquid > 0 ? (context.allocation * 1e18) / context.liquid : 0;
        context.feeShare = (contributedFees * liquidityContribution) / 1e18;
        context.feeShare = context.feeShare > context.fees ? context.fees : context.feeShare;
        return context;
    }

    // Applies updates and transfers fees
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

    // Internal function to process fee claims
    function _processFeeShare(address listingAddress, address depositor, uint256 liquidityIndex, bool isX) internal {
        FeeClaimContext memory context = _validateFeeClaim(listingAddress, depositor, liquidityIndex, isX);
        context = _calculateFeeShare(context);
        _executeFeeClaim(context);
    }

    // Internal function to change depositor
    function _changeDepositor(address listingAddress, address depositor, bool isX, uint256 slotIndex, address newDepositor) internal {
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        require(liquidityContract.isRouter(address(this)), "Router not registered");
        require(depositor != address(0), "Invalid depositor");
        require(newDepositor != address(0), "Invalid new depositor");
        try liquidityContract.changeSlotDepositor(depositor, isX, slotIndex, newDepositor) {
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Depositor change failed: ", reason)));
        }
    }
}