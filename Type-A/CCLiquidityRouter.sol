// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.12
// Changes:
// - v0.0.12: Removed redundant 'require(success)' in depositToken after transferFrom, as balance checks ensure transfer success.
// - v0.0.11: Removed duplicate TransferFailed event and InsufficientAllowance error declarations, inherited from CCLiquidityPartial.sol to fix DeclarationError.
// - v0.0.10: Removed SafeERC20 usage in depositToken, used IERC20.transferFrom directly; added allowance check with InsufficientAllowance error; added TransferFailed event for transferFrom failures; fixed ParserError by removing invalid string 'moleculartools.com' (line 158).
// - v0.0.9: Added support for zero-balance pool initialization in depositToken and depositNativeToken. Checks liquidityAmounts() to allow single-sided deposits if pool is uninitialized (lines 50-61, 81-92).
// - v0.0.8: Replaced tokenAddress with isTokenA boolean in depositToken and depositNativeToken to fetch token from listing (lines 48-49, 74-75).
// - v0.0.7: Fixed TypeError in depositNativeToken/depositToken by removing incorrect returns clause in try blocks.
// - v0.0.6: Fixed ParserError in depositNativeToken by correcting try block syntax.
// - v0.0.5: Removed inlined ICCListing/ICCLiquidity interfaces, imported from CCMainPartial.sol, aligned with ICCLiquidityTemplate.
// - v0.0.4: Split deposit into depositNative/depositToken, used separate ETH/ERC20 helpers.
// - v0.0.3: Used ICCListing/ICCLiquidity, replaced transact with token/native, inlined interfaces.
// - v0.0.2: Modified withdraw, claimFees, changeDepositor to use msg.sender.
// - v0.0.1: Initial creation from SSRouter.sol v0.0.

// Compatible with CCMainPartial.sol (v0.0.7), CCListing.sol (v0.0.3), ICCLiquidity.sol, CCLiquidityTemplate.sol (v0.0.2).

import "./utils/CCLiquidityPartial.sol";

contract CCLiquidityRouter is CCLiquidityPartial {
    function depositNativeToken(address listingAddress, uint256 inputAmount, bool isTokenA) external payable nonReentrant onlyValidListing(listingAddress) {
        // Deposits ETH to liquidity pool for msg.sender, supports zero-balance initialization
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(0);
        ICCLiquidityTemplate liquidityContract = ICCLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(msg.value == inputAmount, "Incorrect ETH amount");
        address tokenAddress = isTokenA ? listingContract.tokenA() : listingContract.tokenB();
        require(tokenAddress == address(0), "Use depositToken for ERC20");
        // Check if pool is uninitialized
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        require(xAmount == 0 && yAmount == 0 || (isTokenA ? xAmount : yAmount) > 0, "Invalid initial deposit");
        try liquidityContract.depositNative{value: inputAmount}(msg.sender, inputAmount) {
            // No return value to check
        } catch {
            revert("Native deposit failed");
        }
    }

    function depositToken(address listingAddress, uint256 inputAmount, bool isTokenA) external nonReentrant onlyValidListing(listingAddress) {
        // Deposits ERC20 tokens to liquidity pool for msg.sender, supports zero-balance initialization
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(0);
        ICCLiquidityTemplate liquidityContract = ICCLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        address tokenAddress = isTokenA ? listingContract.tokenA() : listingContract.tokenB();
        require(tokenAddress != address(0), "Use depositNative for ETH");
        // Check if pool is uninitialized
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        require(xAmount == 0 && yAmount == 0 || (isTokenA ? xAmount : yAmount) > 0, "Invalid initial deposit");
        // Check allowance before transfer
        uint256 allowance = IERC20(tokenAddress).allowance(msg.sender, address(this));
        if (allowance < inputAmount) {
            revert InsufficientAllowance(msg.sender, tokenAddress, inputAmount, allowance);
        }
        uint256 preBalance = IERC20(tokenAddress).balanceOf(address(this));
        try IERC20(tokenAddress).transferFrom(msg.sender, address(this), inputAmount) returns (bool) {
            // Balance checks below ensure transfer success
        } catch (bytes memory reason) {
            emit TransferFailed(msg.sender, tokenAddress, inputAmount, reason);
            revert("TransferFrom failed with reason");
        }
        uint256 postBalance = IERC20(tokenAddress).balanceOf(address(this));
        uint256 receivedAmount = postBalance - preBalance;
        require(receivedAmount > 0, "No tokens received");
        IERC20(tokenAddress).approve(liquidityAddr, receivedAmount);
        try liquidityContract.depositToken(msg.sender, tokenAddress, receivedAmount) {
            // No return value to check
        } catch {
            revert("Token deposit failed");
        }
    }

    function withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX) external nonReentrant onlyValidListing(listingAddress) {
        // Withdraws tokens from liquidity pool for msg.sender
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(0);
        ICCLiquidityTemplate liquidityContract = ICCLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(msg.sender != address(0), "Invalid caller address");
        ICCLiquidityTemplate.PreparedWithdrawal memory withdrawal;
        if (isX) {
            try liquidityContract.xPrepOut(msg.sender, inputAmount, index) returns (ICCLiquidityTemplate.PreparedWithdrawal memory result) {
                withdrawal = result;
            } catch {
                revert("Withdrawal preparation failed");
            }
            try liquidityContract.xExecuteOut(msg.sender, index, withdrawal) {
                // No return value to check
            } catch {
                revert("Withdrawal execution failed");
            }
        } else {
            try liquidityContract.yPrepOut(msg.sender, inputAmount, index) returns (ICCLiquidityTemplate.PreparedWithdrawal memory result) {
                withdrawal = result;
            } catch {
                revert("Withdrawal preparation failed");
            }
            try liquidityContract.yExecuteOut(msg.sender, index, withdrawal) {
                // No return value to check
            } catch {
                revert("Withdrawal execution failed");
            }
        }
    }

    function claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount) external nonReentrant onlyValidListing(listingAddress) {
        // Claims fees from liquidity pool for msg.sender
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(0);
        ICCLiquidityTemplate liquidityContract = ICCLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(msg.sender != address(0), "Invalid caller address");
        try liquidityContract.claimFees(msg.sender, listingAddress, liquidityIndex, isX, volumeAmount) {
            // No return value to check
        } catch {
            revert("Claim fees failed");
        }
    }

    function changeDepositor(address listingAddress, bool isX, uint256 slotIndex, address newDepositor) external nonReentrant onlyValidListing(listingAddress) {
        // Changes depositor for a liquidity slot for msg.sender
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(0);
        ICCLiquidityTemplate liquidityContract = ICCLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(msg.sender != address(0), "Invalid caller address");
        require(newDepositor != address(0), "Invalid new depositor");
        try liquidityContract.changeSlotDepositor(msg.sender, isX, slotIndex, newDepositor) {
            // No return value to check
        } catch {
            revert("Failed to change depositor");
        }
    }

    function settleLongLiquid(address listingAddress, uint256 maxIterations) external nonReentrant onlyValidListing(listingAddress) {
        // Settles multiple long liquidations up to maxIterations
        ICCListing listingContract = ICCListing(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.longPayoutByIndexView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ICCListing.PayoutUpdate[] memory tempUpdates = new ICCListing.PayoutUpdate[](iterationCount);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; ++i) {
            ICCListing.PayoutUpdate[] memory updates = settleSingleLongLiquid(listingAddress, orderIdentifiers[i]);
            if (updates.length == 0) continue;
            tempUpdates[updateIndex++] = updates[0];
        }
        ICCListing.PayoutUpdate[] memory finalUpdates = new ICCListing.PayoutUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; ++i) {
            finalUpdates[i] = tempUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.ssUpdate(address(this), finalUpdates);
        }
    }

    function settleShortLiquid(address listingAddress, uint256 maxIterations) external nonReentrant onlyValidListing(listingAddress) {
        // Settles multiple short liquidations up to maxIterations
        ICCListing listingContract = ICCListing(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.shortPayoutByIndexView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ICCListing.PayoutUpdate[] memory tempUpdates = new ICCListing.PayoutUpdate[](iterationCount);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; ++i) {
            ICCListing.PayoutUpdate[] memory updates = settleSingleShortLiquid(listingAddress, orderIdentifiers[i]);
            if (updates.length == 0) continue;
            tempUpdates[updateIndex++] = updates[0];
        }
        ICCListing.PayoutUpdate[] memory finalUpdates = new ICCListing.PayoutUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; ++i) {
            finalUpdates[i] = tempUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.ssUpdate(address(this), finalUpdates);
        }
    }

    function settleLongPayouts(address listingAddress, uint256 maxIterations) external nonReentrant onlyValidListing(listingAddress) {
        // Executes long payouts
        executeLongPayouts(listingAddress, maxIterations);
    }

    function settleShortPayouts(address listingAddress, uint256 maxIterations) external nonReentrant onlyValidListing(listingAddress) {
        // Executes short payouts
        executeShortPayouts(listingAddress, maxIterations);
    }
}