// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.16
// Changes:
// - v0.0.16: Updated to align with ICCLiquidity.sol v0.0.4 and ICCListing.sol v0.0.7. Replaced 'caller' with 'depositor' in function calls to liquidityContract. Ensured unused 'depositor' in addFees is retained for consistency. Updated ssUpdate call in settleLongLiquid and settleShortLiquid to remove 'caller' parameter.
// - v0.0.15: Added DepositTokenFailed and DepositNativeFailed events, captured revert reasons as strings.
// - v0.0.14: Removed duplicated ICCListing/ICCLiquidityTemplate interfaces, used CCMainPartial.sol.
// - v0.0.13: Updated ICCListing interface, removed uint256 from liquidityAddressView.
// - v0.0.12: Removed redundant require(success) in depositToken.
// - v0.0.11: Removed duplicate TransferFailed/InsufficientAllowance declarations.
// - v0.0.10: Removed SafeERC20, added allowance checks.
// - v0.0.9: Added zero-balance pool initialization support.
// - v0.0.8: Replaced tokenAddress with isTokenA boolean.
// - v0.0.7: Fixed TypeError in deposit functions.
// - v0.0.6: Fixed ParserError in depositNativeToken.
// - v0.0.5: Imported interfaces from CCMainPartial.sol.
// - v0.0.4: Split deposit into native/token functions.
// - v0.0.3: Used ICCListing/ICCLiquidity interfaces.
// - v0.0.2: Modified withdraw/claimFees/changeDepositor to use msg.sender.
// - v0.0.1: Created from SSRouter.sol.

import "./utils/CCLiquidityPartial.sol";

contract CCLiquidityRouter is CCLiquidityPartial {
    event DepositTokenFailed(address indexed depositor, address token, uint256 amount, string reason);
    event DepositNativeFailed(address indexed depositor, uint256 amount, string reason);

    function depositNativeToken(address listingAddress, uint256 inputAmount, bool isTokenA) external payable nonReentrant onlyValidListing(listingAddress) {
        // Deposits ETH to liquidity pool for msg.sender, supports zero-balance initialization
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        require(liquidityContract.isRouter(address(this)), "Router not registered");
        require(msg.value == inputAmount, "Incorrect ETH amount");
        address tokenAddress = isTokenA ? listingContract.tokenA() : listingContract.tokenB();
        require(tokenAddress == address(0), "Use depositToken for ERC20");
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        require(xAmount == 0 && yAmount == 0 || (isTokenA ? xAmount : yAmount) > 0, "Invalid initial deposit");
        try liquidityContract.depositNative(msg.sender, inputAmount) {
            // No return value
        } catch (bytes memory reason) {
            emit DepositNativeFailed(msg.sender, inputAmount, string(reason));
            revert(string(abi.encodePacked("Native deposit failed: ", reason)));
        }
    }

    function depositToken(address listingAddress, uint256 inputAmount, bool isTokenA) external nonReentrant onlyValidListing(listingAddress) {
        // Deposits ERC20 tokens to liquidity pool for msg.sender, supports zero-balance initialization
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        require(liquidityContract.isRouter(address(this)), "Router not registered");
        address tokenAddress = isTokenA ? listingContract.tokenA() : listingContract.tokenB();
        require(tokenAddress != address(0), "Use depositNative for ETH");
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        require(xAmount == 0 && yAmount == 0 || (isTokenA ? xAmount : yAmount) > 0, "Invalid initial deposit");
        uint256 allowance = IERC20(tokenAddress).allowance(msg.sender, address(this));
        if (allowance < inputAmount) {
            revert InsufficientAllowance(msg.sender, tokenAddress, inputAmount, allowance);
        }
        uint256 preBalance = IERC20(tokenAddress).balanceOf(address(this));
        try IERC20(tokenAddress).transferFrom(msg.sender, address(this), inputAmount) {
            // Balance checks ensure success
        } catch (bytes memory reason) {
            emit TransferFailed(msg.sender, tokenAddress, inputAmount, reason);
            revert("TransferFrom failed");
        }
        uint256 postBalance = IERC20(tokenAddress).balanceOf(address(this));
        uint256 receivedAmount = postBalance - preBalance;
        require(receivedAmount > 0, "No tokens received");
        IERC20(tokenAddress).approve(liquidityAddr, receivedAmount);
        try liquidityContract.depositToken(msg.sender, tokenAddress, receivedAmount) {
            // No return value
        } catch (bytes memory reason) {
            emit DepositTokenFailed(msg.sender, tokenAddress, receivedAmount, string(reason));
            revert(string(abi.encodePacked("Token deposit failed: ", reason)));
        }
    }

    function withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX) external nonReentrant onlyValidListing(listingAddress) {
        // Withdraws tokens from liquidity pool for msg.sender
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        require(liquidityContract.isRouter(address(this)), "Router not registered");
        require(msg.sender != address(0), "Invalid depositor address");
        ICCLiquidity.PreparedWithdrawal memory withdrawal;
        if (isX) {
            try liquidityContract.xPrepOut(msg.sender, inputAmount, index) returns (ICCLiquidity.PreparedWithdrawal memory result) {
                withdrawal = result;
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Withdrawal preparation failed: ", reason)));
            }
            try liquidityContract.xExecuteOut(msg.sender, index, withdrawal) {
                // No return value
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Withdrawal execution failed: ", reason)));
            }
        } else {
            try liquidityContract.yPrepOut(msg.sender, inputAmount, index) returns (ICCLiquidity.PreparedWithdrawal memory result) {
                withdrawal = result;
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Withdrawal preparation failed: ", reason)));
            }
            try liquidityContract.yExecuteOut(msg.sender, index, withdrawal) {
                // No return value
            } catch (bytes memory reason) {
                revert(string(abi.encodePacked("Withdrawal execution failed: ", reason)));
            }
        }
    }

    function claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount) external nonReentrant onlyValidListing(listingAddress) {
        // Claims fees from liquidity pool for msg.sender
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        require(liquidityContract.isRouter(address(this)), "Router not registered");
        require(msg.sender != address(0), "Invalid depositor address");
        try liquidityContract.claimFees(msg.sender, listingAddress, liquidityIndex, isX, volumeAmount) {
            // No return value
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Claim fees failed: ", reason)));
        }
    }

    function changeDepositor(address listingAddress, bool isX, uint256 slotIndex, address newDepositor) external nonReentrant onlyValidListing(listingAddress) {
        // Changes depositor for a liquidity slot for msg.sender
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        require(liquidityContract.isRouter(address(this)), "Router not registered");
        require(msg.sender != address(0), "Invalid depositor address");
        require(newDepositor != address(0), "Invalid new depositor");
        try liquidityContract.changeSlotDepositor(msg.sender, isX, slotIndex, newDepositor) {
            // No return value
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Depositor change failed: ", reason)));
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
            listingContract.ssUpdate(finalUpdates);
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
            listingContract.ssUpdate(finalUpdates);
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