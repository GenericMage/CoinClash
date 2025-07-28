// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.0.3
// Changes:
// - v0.0.3: Added price impact restrictions in settleBuyLiquid and settleSellLiquid, using Uniswap V2 reserve data to ensure hypothetical price changes stay within order bounds.
// - v0.0.2: Removed SafeERC20 usage, used IERC20 from CCMainPartial, removed redundant require success checks for transfers.
// - v0.0.1: Created CCLiquidRouter.sol, extracted settleBuyLiquid and settleSellLiquid from CCSettlementRouter.sol.
// Compatible with ICCListing.sol (v0.0.3), ICCLiquidity.sol, CCMainPartial.sol (v0.0.07), CCLiquidPartial.sol (v0.0.3).

import "./utils/CCLiquidPartial.sol";

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
}

contract CCLiquidRouter is CCLiquidPartial {
    struct SwapImpactContext {
        uint256 reserveIn;
        uint256 reserveOut;
        uint8 decimalsIn;
        uint8 decimalsOut;
        uint256 normalizedReserveIn;
        uint256 normalizedReserveOut;
        uint256 amountInAfterFee;
        uint256 price;
        uint256 amountOut;
    }

    function _getSwapReserves(address listingAddress, bool isBuyOrder) private view returns (SwapImpactContext memory context) {
        // Retrieves reserves and decimals for swap impact calculation
        ICCListing listingContract = ICCListing(listingAddress);
        address pairAddress = listingContract.uniswapV2PairView();
        require(pairAddress != address(0), "Uniswap V2 pair not set");
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        address token0 = pair.token0();
        bool isToken0In = isBuyOrder ? listingContract.tokenB() == token0 : listingContract.tokenA() == token0;
        context.reserveIn = isToken0In ? uint256(reserve0) : uint256(reserve1);
        context.reserveOut = isToken0In ? uint256(reserve1) : uint256(reserve0);
        context.decimalsIn = isBuyOrder ? listingContract.decimalsB() : listingContract.decimalsA();
        context.decimalsOut = isBuyOrder ? listingContract.decimalsA() : listingContract.decimalsB();
        context.normalizedReserveIn = normalize(context.reserveIn, context.decimalsIn);
        context.normalizedReserveOut = normalize(context.reserveOut, context.decimalsOut);
    }

    function _computeSwapImpact(address listingAddress, uint256 inputAmount, bool isBuyOrder) private view returns (uint256 price, uint256 amountOut) {
        // Computes swap impact price using Uniswap V2 formula
        SwapImpactContext memory context = _getSwapReserves(listingAddress, isBuyOrder);
        require(context.normalizedReserveIn > 0 && context.normalizedReserveOut > 0, "Zero reserves");
        context.amountInAfterFee = (inputAmount * 997) / 1000; // 0.3% fee
        context.amountOut = (context.amountInAfterFee * context.normalizedReserveOut) /
                           (context.normalizedReserveIn + context.amountInAfterFee);
        context.price = context.amountOut > 0 ? (inputAmount * 1e18) / context.amountOut : type(uint256).max;
        amountOut = denormalize(context.amountOut, context.decimalsOut);
        price = context.price;
    }

    function settleBuyLiquid(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Settles multiple buy order liquidations up to maxIterations, with price impact restrictions
        ICCListing listingContract = ICCListing(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.pendingBuyOrdersView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ICCListing.UpdateType[] memory tempUpdates = new ICCListing.UpdateType[](iterationCount * 3);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            (uint256 pendingAmount, , ) = listingContract.getBuyOrderAmounts(orderIdentifiers[i]);
            (uint256 maxPrice, uint256 minPrice) = listingContract.getBuyOrderPricing(orderIdentifiers[i]);
            (uint256 price, ) = _computeSwapImpact(listingAddress, pendingAmount, true);
            if (price >= minPrice && price <= maxPrice) {
                ICCListing.UpdateType[] memory updates = executeSingleBuyLiquid(listingAddress, orderIdentifiers[i]);
                if (updates.length > 0) {
                    for (uint256 j = 0; j < updates.length; j++) {
                        tempUpdates[updateIndex++] = updates[j];
                    }
                }
            }
        }
        ICCListing.UpdateType[] memory finalUpdates = new ICCListing.UpdateType[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalUpdates[i] = tempUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.update(address(this), finalUpdates);
        }
    }

    function settleSellLiquid(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Settles multiple sell order liquidations up to maxIterations, with price impact restrictions
        ICCListing listingContract = ICCListing(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.pendingSellOrdersView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ICCListing.UpdateType[] memory tempUpdates = new ICCListing.UpdateType[](iterationCount * 3);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            (uint256 pendingAmount, , ) = listingContract.getSellOrderAmounts(orderIdentifiers[i]);
            (uint256 maxPrice, uint256 minPrice) = listingContract.getSellOrderPricing(orderIdentifiers[i]);
            (uint256 price, ) = _computeSwapImpact(listingAddress, pendingAmount, false);
            if (price >= minPrice && price <= maxPrice) {
                ICCListing.UpdateType[] memory updates = executeSingleSellLiquid(listingAddress, orderIdentifiers[i]);
                if (updates.length > 0) {
                    for (uint256 j = 0; j < updates.length; j++) {
                        tempUpdates[updateIndex++] = updates[j];
                    }
                }
            }
        }
        ICCListing.UpdateType[] memory finalUpdates = new ICCListing.UpdateType[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalUpdates[i] = tempUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.update(address(this), finalUpdates);
        }
    }
}