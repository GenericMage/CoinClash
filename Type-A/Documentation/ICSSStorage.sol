/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-07-18: Created ICSStorage interface with structs, mappings, state variables, functions, and events from CSStorage.sol, including single-sentence explanations for usage, parameters, and returns. Version set to 0.0.1.
*/

pragma solidity ^0.8.2;

interface ICSStorage {
    // Constant for normalizing amounts and prices across token decimals.
    function DECIMAL_PRECISION() external view returns (uint256);
    
    // Stores the address of the ISSAgent contract for listing validation.
    function agentAddress() external view returns (address);
    
    // Tracks the total number of positions created for unique position IDs.
    function positionCount() external view returns (uint256);
    
    // Stores core position data including ID, listing, maker, and type.
    struct PositionCore1 {
        uint256 positionId; // Unique identifier for the position.
        address listingAddress; // Address of the associated listing contract.
        address makerAddress; // Address of the position owner.
        uint8 positionType; // 0 for long, 1 for short.
    }
    
    // Tracks position status flags for active and closed states.
    struct PositionCore2 {
        bool status1; // True if position is active, false if pending.
        uint8 status2; // 0 for open, 1 for closed.
    }
    
    // Holds price-related data for position entry and leverage.
    struct PriceParams1 {
        uint256 minEntryPrice; // Minimum entry price, normalized.
        uint256 maxEntryPrice; // Maximum entry price, normalized.
        uint256 minPrice; // Minimum price at entry, normalized.
        uint256 priceAtEntry; // Actual entry price, normalized.
        uint8 leverage; // Leverage multiplier (2–100).
    }
    
    // Stores liquidation price for risk management.
    struct PriceParams2 {
        uint256 liquidationPrice; // Price at which position is liquidated, normalized.
    }
    
    // Manages margin details for position funding.
    struct MarginParams1 {
        uint256 initialMargin; // Initial margin provided, normalized.
        uint256 taxedMargin; // Margin after fees, normalized.
        uint256 excessMargin; // Additional margin, normalized.
        uint256 fee; // Fee charged for position, normalized.
    }
    
    // Tracks initial loan amount for leveraged positions.
    struct MarginParams2 {
        uint256 initialLoan; // Loan amount for leverage, normalized.
    }
    
    // Stores exit conditions for stop-loss and take-profit.
    struct ExitParams {
        uint256 stopLossPrice; // Stop-loss price, normalized.
        uint256 takeProfitPrice; // Take-profit price, normalized.
        uint256 exitPrice; // Actual exit price, normalized.
    }
    
    // Records leverage amount and timestamp for open interest tracking.
    struct OpenInterest {
        uint256 leverageAmount; // Leveraged position size, normalized.
        uint256 timestamp; // Timestamp of position creation or update.
    }
    
    // Tracks margin balances per maker and token, normalized to 1e18.
    function makerTokenMargin(address maker, address token) external view returns (uint256);
    
    // Lists tokens with non-zero margin balances for each maker.
    function makerMarginTokens(address maker) external view returns (address[] memory);
    
    // Stores core position data for a given position ID.
    function positionCore1(uint256 positionId) external view returns (PositionCore1 memory);
    
    // Stores status flags for a given position ID.
    function positionCore2(uint256 positionId) external view returns (PositionCore2 memory);
    
    // Stores price parameters for a given position ID.
    function priceParams1(uint256 positionId) external view returns (PriceParams1 memory);
    
    // Stores liquidation price for a given position ID.
    function priceParams2(uint256 positionId) external view returns (PriceParams2 memory);
    
    // Stores margin details for a given position ID.
    function marginParams1(uint256 positionId) external view returns (MarginParams1 memory);
    
    // Stores initial loan amount for a given position ID.
    function marginParams2(uint256 positionId) external view returns (MarginParams2 memory);
    
    // Stores exit conditions for a given position ID.
    function exitParams(uint256 positionId) external view returns (ExitParams memory);
    
    // Stores open interest data for a given position ID.
    function openInterest(uint256 positionId) external view returns (OpenInterest memory);
    
    // Lists position IDs by type (0 for long, 1 for short).
    function positionsByType(uint8 positionType) external view returns (uint256[] memory);
    
    // Tracks pending position IDs by listing address and position type.
    function pendingPositions(address listingAddress, uint8 positionType) external view returns (uint256[] memory);
    
    // Maps position ID to margin token (tokenA for long, tokenB for short).
    function positionToken(uint256 positionId) external view returns (address);
    
    // Tracks long open interest by block height.
    function longIOByHeight(uint256 height) external view returns (uint256);
    
    // Tracks short open interest by block height.
    function shortIOByHeight(uint256 height) external view returns (uint256);
    
    // Stores timestamps for open interest updates by block height.
    function historicalInterestTimestamps(uint256 height) external view returns (uint256);
    
    // Tracks authorized mux contracts for position updates.
    function muxes(address mux) external view returns (bool);
    
    // Emitted when a position is closed with its ID, maker, and payout amount.
    event PositionClosed(uint256 indexed positionId, address indexed maker, uint256 payout);
    
    // Emitted when a mux is authorized to update positions.
    event MuxAdded(address indexed mux);
    
    // Emitted when a mux is removed from authorized list.
    event MuxRemoved(address indexed mux);
    
    // Updates the ISSAgent address for listing validation, restricted to owner.
    function setAgent(address newAgentAddress) external;
    
    // Authorizes a mux contract to call update functions, restricted to owner.
    function addMux(address mux) external;
    
    // Revokes a mux contract’s authorization, restricted to owner.
    function removeMux(address mux) external;
    
    // Returns an array of authorized mux addresses.
    function getMuxesView() external view returns (address[] memory);
    
    // Updates position data using hyphen-delimited strings, restricted to muxes.
    function CSUpdate(
        uint256 positionId,
        string memory coreParams,
        string memory priceParams,
        string memory marginParams,
        string memory exitAndInterestParams,
        string memory makerMarginParams,
        string memory positionArrayParams,
        string memory historicalInterestParams
    ) external;
    
    // Removes a position from pending or active arrays, restricted to muxes.
    function removePositionIndex(uint256 positionId, uint8 positionType, address listingAddress) external;
    
    // Removes a token from a maker’s margin token list if balance is zero, restricted to muxes.
    function removeToken(address maker, address token) external;
    
    // Returns all position data (core, price, margin, exit, token) for a given ID.
    function positionByIndex(uint256 positionId) external view returns (
        PositionCore1 memory core1,
        PositionCore2 memory core2,
        PriceParams1 memory price1,
        PriceParams2 memory price2,
        MarginParams1 memory margin1,
        MarginParams2 memory margin2,
        ExitParams memory exit,
        address token
    );
    
    // Returns position IDs by type starting at an index, up to maxIterations.
    function PositionsByTypeView(uint8 positionType, uint256 startIndex, uint256 maxIterations) external view returns (uint256[] memory positionIds);
    
    // Returns pending position IDs for a maker starting at an index, up to maxIterations.
    function PositionsByAddressView(address maker, uint256 startIndex, uint256 maxIterations) external view returns (uint256[] memory positionIds);
    
    // Returns the count of active positions (status1 true, status2 0).
    function TotalActivePositionsView() external view returns (uint256 count);
    
    // Returns open interest and timestamps for a range of block heights.
    function queryInterest(uint256 startIndex, uint256 maxIterations) external view returns (
        uint256[] memory longIO,
        uint256[] memory shortIO,
        uint256[] memory timestamps
    );
    
    // Returns tokens and margins for a maker starting at an index, up to maxIterations.
    function makerMarginIndex(address maker, uint256 startIndex, uint256 maxIterations) external view returns (address[] memory tokens, uint256[] memory margins);
    
    // Returns margin ratio, liquidation distance, and estimated profit/loss for a position.
    function PositionHealthView(uint256 positionId) external view returns (
        uint256 marginRatio,
        uint256 distanceToLiquidation,
        uint256 estimatedProfitLoss
    );
    
    // Returns makers and margins for a listing’s tokenB from position types.
    function AggregateMarginByToken(address tokenA, address tokenB, uint256 startIndex, uint256 maxIterations) external view returns (address[] memory makers, uint256[] memory margins);
    
    // Returns leverage amounts and timestamps for open positions in a listing.
    function OpenInterestTrend(address listingAddress, uint256 startIndex, uint256 maxIterations) external view returns (uint256[] memory leverageAmounts, uint256[] memory timestamps);
    
    // Counts positions within 5% of liquidation price for a listing.
    function LiquidationRiskCount(address listingAddress, uint256 maxIterations) external view returns (uint256 count);
}