// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.30
// Changes:
// - v0.0.30: Removed redundant ICCLiquidity interface to use inherited definition from CCMainPartial.sol, resolving DeclarationError for PreparedWithdrawal, _prepWithdrawal, and _executeWithdrawal. Updated compatibility comments to align with CCLiquidityPartial.sol v0.0.22.
// - v0.0.29: Added ICCLiquidity interface import (incorrectly), updated compatibility comments.
// - v0.0.28: Removed redundant queryDepositorFees function to use inherited implementation from CCLiquidityPartial.sol, resolving TypeError due to override conflict.
// - v0.0.27: Updated compatibility comments to align with CCLiquidityPartial.sol v0.0.21 and CCLiquidityTemplate.sol v0.1.1.
// - v0.0.26: Modified depositNativeToken and depositToken to update existing slot if depositor has one, claiming fees first and resetting dFeesAcc. Added depositor parameter for third-party deposits.
// Compatible with CCListingTemplate.sol (v0.1.0), CCMainPartial.sol (v0.0.14), CCLiquidityPartial.sol (v0.0.22), ICCLiquidity.sol (v0.0.5), ICCListing.sol (v0.0.7), CCLiquidityTemplate.sol (v0.1.1).

import "./utils/CCLiquidityPartial.sol";

contract CCLiquidityRouter is CCLiquidityPartial {
    event DepositTokenFailed(address indexed depositor, address token, uint256 amount, string reason);
    event DepositNativeFailed(address indexed depositor, uint256 amount, string reason);

    function depositNativeToken(address listingAddress, address depositor, uint256 inputAmount, bool isTokenA) external payable nonReentrant onlyValidListing(listingAddress) {
        // Deposits ETH to liquidity pool for specified depositor, updates existing slot if present, claims fees first
        _depositNative(listingAddress, depositor, inputAmount, isTokenA);
    }

    function depositToken(address listingAddress, address depositor, uint256 inputAmount, bool isTokenA) external nonReentrant onlyValidListing(listingAddress) {
        // Deposits ERC20 tokens to liquidity pool for specified depositor, updates existing slot if present, claims fees first
        _depositToken(listingAddress, depositor, inputAmount, isTokenA);
    }

    function withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX) external nonReentrant onlyValidListing(listingAddress) {
        // Withdraws tokens from liquidity pool for msg.sender
        ICCLiquidity.PreparedWithdrawal memory withdrawal = _prepWithdrawal(listingAddress, msg.sender, inputAmount, index, isX);
        _executeWithdrawal(listingAddress, msg.sender, index, isX, withdrawal);
    }

    function claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 /* volumeAmount */) external nonReentrant onlyValidListing(listingAddress) {
        // Claims fees from liquidity pool for msg.sender
        _processFeeShare(listingAddress, msg.sender, liquidityIndex, isX);
    }

    function changeDepositor(address listingAddress, bool isX, uint256 slotIndex, address newDepositor) external nonReentrant onlyValidListing(listingAddress) {
        // Changes depositor for a liquidity slot for msg.sender
        _changeDepositor(listingAddress, msg.sender, isX, slotIndex, newDepositor);
    }
}