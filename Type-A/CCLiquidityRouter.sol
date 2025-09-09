// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.3
// Changes:
// - v0.1.3: Modified withdraw to accept compensationAmount parameter, passing it to _prepWithdrawal and _executeWithdrawal. Removed reverts, ensuring all failures emit events. Simplified to check only ownership and allocation.
// - v0.1.2: Added depositor parameter to depositToken and depositNativeToken, renamed inputAmount to outputAmount in withdraw function.
// - v0.1.1: Added depositor parameter to depositToken and depositNative to support third-party deposits. Renamed inputAmount to amount for clarity.
// - v0.1.0: Bumped version
// - v0.0.25: Removed invalid try-catch in depositNativeToken and depositToken, as _depositNative and _depositToken are internal. Errors are handled by internal reverts and DepositFailed event in CCLiquidityPartial. Updated compatibility comments.
// - v0.0.24: Fixed TypeError by removing 'this' from _depositNative and _depositToken calls.
// - v0.0.23: Updated to use CCLiquidityPartial.sol v0.0.17, removed listingId from FeesClaimed event.
// Compatible with CCListingTemplate.sol (v0.0.10), CCMainPartial.sol (v0.0.10), CCLiquidityPartial.sol (v0.0.17), ICCLiquidity.sol (v0.0.4), ICCListing.sol (v0.0.7), CCLiquidityTemplate.sol (v0.0.20).

import "./utils/CCLiquidityPartial.sol";

contract CCLiquidityRouter is CCLiquidityPartial {
    event DepositTokenFailed(address indexed depositor, address token, uint256 amount, string reason);
    event DepositNativeFailed(address indexed depositor, uint256 amount, string reason);

    function depositNativeToken(address listingAddress, address depositor, uint256 amount, bool isTokenA) external payable nonReentrant onlyValidListing(listingAddress) {
    // Deposits ETH to liquidity pool for specified depositor, supports zero-balance initialization
    _depositNative(listingAddress, depositor, amount, isTokenA);
}

    function depositToken(address listingAddress, address depositor, uint256 amount, bool isTokenA) external nonReentrant onlyValidListing(listingAddress) {
    // Deposits ERC20 tokens to liquidity pool for specified depositor, supports zero-balance initialization
    _depositToken(listingAddress, depositor, amount, isTokenA);
}

    function withdraw(address listingAddress, uint256 outputAmount, uint256 compensationAmount, uint256 index, bool isX) external nonReentrant onlyValidListing(listingAddress) {
    // Withdraws tokens from liquidity pool for msg.sender, with user-specified compensation amount
    ICCLiquidity.PreparedWithdrawal memory withdrawal = _prepWithdrawal(listingAddress, msg.sender, outputAmount, compensationAmount, index, isX);
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