// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.10
// Changes:
// - v0.0.10: Relaxed liquidity check in depositToken and depositNativeToken to allow deposits if listingId is valid and tokens are set, removing restrictive xAmount/yAmount check (lines 53-55, 81-83).
// - v0.0.9: Added support for zero-balance pool initialization in depositToken and depositNativeToken.
// - v0.0.8: Replaced tokenAddress with isTokenA boolean in depositToken and depositNativeToken.
// - v0.0.7: Fixed TypeError in depositNativeToken/depositToken by removing incorrect returns clause.
// - v0.0.6: Fixed ParserError in depositNativeToken by correcting try block syntax.
// - v0.0.5: Removed inlined ICCListing/ICCLiquidity, imported from CCMainPartial.sol.
// - v0.0.4: Split deposit into depositNative/depositToken.
// - v0.0.3: Used ICCListing/ICCLiquidity, replaced transact with token/native.
// - v0.0.2: Modified withdraw, claimFees, changeDepositor to use msg.sender.
// - v0.0.1: Initial creation from SSRouter.sol v0.0.

// Compatible with CCMainPartial.sol (v0.0.6), CCListing.sol (v0.0.3), ICCLiquidity.sol, CCLiquidityTemplate.sol (v0.0.2).

import "./utils/CCLiquidityPartial.sol";

contract CCLiquidityRouter is CCLiquidityPartial {
    using SafeERC20 for IERC20;

    function depositNativeToken(address listingAddress, uint256 inputAmount, bool isTokenA) external payable nonReentrant onlyValidListing(listingAddress) {
        // Deposits ETH to liquidity pool for msg.sender, allows deposits if listing is valid
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(0);
        require(liquidityAddr != address(0), "Invalid liquidity address");
        ICCLiquidityTemplate liquidityContract = ICCLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(msg.value == inputAmount, "Incorrect ETH amount");
        address tokenAddress = isTokenA ? listingContract.tokenA() : listingContract.tokenB();
        require(tokenAddress == address(0), "Use depositToken for ERC20");
        // Validate listingId to ensure pool is initialized
        require(listingContract.getListingId() > 0, "Invalid listing ID");
        try liquidityContract.depositNative{value: inputAmount}(msg.sender, inputAmount) {
            // No return value to check
        } catch {
            revert("Native deposit failed");
        }
    }

    function depositToken(address listingAddress, uint256 inputAmount, bool isTokenA) external nonReentrant onlyValidListing(listingAddress) {
        // Deposits ERC20 tokens to liquidity pool for msg.sender, allows deposits if listing is valid
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(0);
        require(liquidityAddr != address(0), "Invalid liquidity address");
        ICCLiquidityTemplate liquidityContract = ICCLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        address tokenAddress = isTokenA ? listingContract.tokenA() : listingContract.tokenB();
        require(tokenAddress != address(0), "Use depositNative for ETH");
        // Validate listingId to ensure pool is initialized
        require(listingContract.getListingId() > 0, "Invalid listing ID");
        uint256 preBalance = IERC20(tokenAddress).balanceOf(address(this));
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), inputAmount);
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