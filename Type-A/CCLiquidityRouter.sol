// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.2 (Updated)
// Changes:
// - v0.0.2: Modified withdraw, claimFees, and changeDepositor to use msg.sender instead of user parameter for enhanced security and interface simplicity, aligning with SSRouter.sol v0.0.62 and OMFRouter.sol v0.0.78.
// - v0.0.1: Created CCLiquidityRouter.sol by extracting deposit, withdraw, claimFees, changeDepositor, settleLongLiquid, settleShortLiquid, settleLongPayouts, and settleShortPayouts from SSRouter.sol v0.0.61.
// - v0.0.1: Imported SSSettlementPartial.sol v0.0.58 to reuse settleSingleLongLiquid, settleSingleShortLiquid, executeLongPayouts, and executeShortPayouts.
// - v0.0.1: Inherited SSSettlementPartial.sol to access payout-related functions and SSMainPartial.sol v0.0.25 for normalize, denormalize, and onlyValidListing.
// - v0.0.1: Included SafeERC20 usage and ReentrancyGuard for security.
// Compatible with SSListingTemplate.sol (v0.0.10), SSLiquidityTemplate.sol (v0.0.6), SSMainPartial.sol (v0.0.25), SSOrderPartial.sol (v0.0.19), SSSettlementPartial.sol (v0.0.58).

import "./utils/SSSettlementPartial.sol";

contract CCLiquidityRouter is SSSettlementPartial {
    using SafeERC20 for IERC20;

    function deposit(address listingAddress, bool isTokenA, uint256 inputAmount, address user) external payable onlyValidListing(listingAddress) nonReentrant {
        // Deposits tokens or ETH to liquidity pool
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(user != address(0), "Invalid user address");
        address tokenAddress = isTokenA ? listingContract.tokenA() : listingContract.tokenB();
        if (tokenAddress == address(0)) {
            require(msg.value == inputAmount, "Incorrect ETH amount");
            try liquidityContract.deposit{value: inputAmount}(user, tokenAddress, inputAmount) {} catch {
                revert("Deposit failed");
            }
        } else {
            uint256 preBalance = IERC20(tokenAddress).balanceOf(address(this));
            IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), inputAmount);
            uint256 postBalance = IERC20(tokenAddress).balanceOf(address(this));
            uint256 receivedAmount = postBalance - preBalance;
            require(receivedAmount > 0, "No tokens received");
            IERC20(tokenAddress).approve(liquidityAddr, receivedAmount);
            try liquidityContract.deposit(user, tokenAddress, receivedAmount) {} catch {
                revert("Deposit failed");
            }
        }
    }

    function withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX) external onlyValidListing(listingAddress) nonReentrant {
        // Withdraws tokens from liquidity pool for msg.sender
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(msg.sender != address(0), "Invalid caller address");
        ISSLiquidityTemplate.PreparedWithdrawal memory withdrawal;
        if (isX) {
            try liquidityContract.xPrepOut(msg.sender, inputAmount, index) returns (ISSLiquidityTemplate.PreparedWithdrawal memory w) {
                withdrawal = w;
            } catch {
                revert("Withdrawal preparation failed");
            }
            try liquidityContract.xExecuteOut(msg.sender, index, withdrawal) {} catch {
                revert("Withdrawal execution failed");
            }
        } else {
            try liquidityContract.yPrepOut(msg.sender, inputAmount, index) returns (ISSLiquidityTemplate.PreparedWithdrawal memory w) {
                withdrawal = w;
            } catch {
                revert("Withdrawal preparation failed");
            }
            try liquidityContract.yExecuteOut(msg.sender, index, withdrawal) {} catch {
                revert("Withdrawal execution failed");
            }
        }
    }

    function claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount) external onlyValidListing(listingAddress) nonReentrant {
        // Claims fees from liquidity pool for msg.sender
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(msg.sender != address(0), "Invalid caller address");
        try liquidityContract.claimFees(msg.sender, listingAddress, liquidityIndex, isX, volumeAmount) {} catch {
            revert("Claim fees failed");
        }
    }

    function changeDepositor(
        address listingAddress,
        bool isX,
        uint256 slotIndex,
        address newDepositor
    ) external onlyValidListing(listingAddress) nonReentrant {
        // Changes depositor for a liquidity slot for msg.sender
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(msg.sender != address(0), "Invalid caller address");
        require(newDepositor != address(0), "Invalid new depositor");
        try liquidityContract.changeSlotDepositor(msg.sender, isX, slotIndex, newDepositor) {} catch {
            revert("Failed to change depositor");
        }
    }

    function settleLongLiquid(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Settles multiple long liquidations up to maxIterations
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        uint256[] memory orderIdentifiers = listingContract.longPayoutByIndexView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ISSListingTemplate.PayoutUpdate[] memory tempPayoutUpdates = new ISSListingTemplate.PayoutUpdate[](iterationCount);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            ISSListingTemplate.PayoutUpdate[] memory updates = settleSingleLongLiquid(listingAddress, orderIdentifiers[i]);
            if (updates.length == 0) {
                continue;
            }
            tempPayoutUpdates[updateIndex++] = updates[0];
        }
        ISSListingTemplate.PayoutUpdate[] memory finalPayoutUpdates = new ISSListingTemplate.PayoutUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalPayoutUpdates[i] = tempPayoutUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.ssUpdate(address(this), finalPayoutUpdates);
        }
    }

    function settleShortLiquid(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Settles multiple short liquidations up to maxIterations
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        uint256[] memory orderIdentifiers = listingContract.shortPayoutByIndexView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ISSListingTemplate.PayoutUpdate[] memory tempPayoutUpdates = new ISSListingTemplate.PayoutUpdate[](iterationCount);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            ISSListingTemplate.PayoutUpdate[] memory updates = settleSingleShortLiquid(listingAddress, orderIdentifiers[i]);
            if (updates.length == 0) {
                continue;
            }
            tempPayoutUpdates[updateIndex++] = updates[0];
        }
        ISSListingTemplate.PayoutUpdate[] memory finalPayoutUpdates = new ISSListingTemplate.PayoutUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalPayoutUpdates[i] = tempPayoutUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.ssUpdate(address(this), finalPayoutUpdates);
        }
    }

    function settleLongPayouts(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Executes long payouts
        executeLongPayouts(listingAddress, maxIterations);
    }

    function settleShortPayouts(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Executes short payouts
        executeShortPayouts(listingAddress, maxIterations);
    }
}