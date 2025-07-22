/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 Recent Changes:
 - 2025-07-20: Created ISIStorage interface for SIStorage.sol, defining external functions, structs, mappings, state variables, and events with single-sentence explanations; version set to 0.0.1.
*/

pragma solidity ^0.8.2;

interface ISIStorage {
    // State Variables
    // DECIMAL_PRECISION: Constant for normalizing amounts and prices to 1e18.
    function DECIMAL_PRECISION() external view returns (uint256);
    // agent: Stores the address of the ISSAgent contract for listing validation.
    function agent() external view returns (address);
    // historicalInterestHeight: Tracks the current block height for open interest updates.
    function historicalInterestHeight() external view returns (uint256);
    // positionCount: Counter for tracking the total number of positions.
    function positionCount() external view returns (uint256);
    // muxes: Maps addresses to boolean indicating authorized mux contracts.
    function muxes(address) external view returns (bool);

    // Structs
    // PositionCoreBase: Stores core position data including maker, listing, ID, and type.
    struct PositionCoreBase {
        address makerAddress; // Address of the position owner
        address listingAddress; // Address of the listing contract
        uint256 positionId; // Unique identifier for the position
        uint8 positionType; // 0 for long, 1 for short
    }

    // PositionCoreStatus: Tracks position status for pending/executable and open/closed/cancelled states.
    struct PositionCoreStatus {
        bool status1; // False for pending, true for executable
        uint8 status2; // 0 for open, 1 for closed, 2 for cancelled
    }

    // PriceParams: Holds price-related data for position entry and closure.
    struct PriceParams {
        uint256 priceMin; // Minimum entry price, normalized to 1e18
        uint256 priceMax; // Maximum entry price, normalized to 1e18
        uint256 priceAtEntry; // Actual entry price, normalized to 1e18
        uint256 priceClose; // Close price, normalized to 1e18
    }

    // MarginParams: Manages margin details for the position.
    struct MarginParams {
        uint256 marginInitial; // Initial margin, normalized to 1e18
        uint256 marginTaxed; // Margin after fees, normalized to 1e18
        uint256 marginExcess; // Additional margin, normalized to 1e18
    }

    // LeverageParams: Stores leverage-related data for the position.
    struct LeverageParams {
        uint8 leverageVal; // Leverage multiplier (2-100)
        uint256 leverageAmount; // Leveraged position size, normalized to 1e18
        uint256 loanInitial; // Initial loan amount, normalized to 1e18
    }

    // RiskParams: Contains risk management parameters for the position.
    struct RiskParams {
        uint256 priceLiquidation; // Price triggering liquidation, normalized to 1e18
        uint256 priceStopLoss; // Stop-loss price, normalized to 1e18
        uint256 priceTakeProfit; // Take-profit price, normalized to 1e18
    }

    // Mappings
    // positionCoreBase: Maps position ID to core position data.
    function positionCoreBase(uint256) external view returns (PositionCoreBase memory);
    // positionCoreStatus: Maps position ID to status data.
    function positionCoreStatus(uint256) external view returns (PositionCoreStatus memory);
    // priceParams: Maps position ID to price parameters.
    function priceParams(uint256) external view returns (PriceParams memory);
    // marginParams: Maps position ID to margin parameters.
    function marginParams(uint256) external view returns (MarginParams memory);
    // leverageParams: Maps position ID to leverage parameters.
    function leverageParams(uint256) external view returns (LeverageParams memory);
    // riskParams: Maps position ID to risk parameters.
    function riskParams(uint256) external view returns (RiskParams memory);
    // pendingPositions: Maps listing address and position type to array of pending position IDs.
    function pendingPositions(address, uint8) external view returns (uint256[] memory);
    // positionsByType: Maps position type to array of active position IDs.
    function positionsByType(uint8) external view returns (uint256[] memory);
    // positionToken: Maps position ID to margin token address (tokenA for long, tokenB for short).
    function positionToken(uint256) external view returns (address);
    // longIOByHeight: Maps block height to long open interest.
    function longIOByHeight(uint256) external view returns (uint256);
    // shortIOByHeight: Maps block height to short open interest.
    function shortIOByHeight(uint256) external view returns (uint256);
    // historicalInterestTimestamps: Maps block height to timestamp of interest updates.
    function historicalInterestTimestamps(uint256) external view returns (uint256);

    // Events
    // PositionClosed: Emitted when a position is closed with its ID, maker, and payout amount.
    event PositionClosed(uint256 indexed positionId, address indexed maker, uint256 payout);
    // MuxAdded: Emitted when a mux address is authorized.
    event MuxAdded(address indexed mux);
    // MuxRemoved: Emitted when a mux address is deauthorized.
    event MuxRemoved(address indexed mux);

    // External Functions
    // setAgent: Sets the ISSAgent address for listing validation.
    function setAgent(address newAgentAddress) external;
    // addMux: Authorizes a mux contract to update positions.
    function addMux(address mux) external;
    // removeMux: Deauthorizes a mux contract from updating positions.
    function removeMux(address mux) external;
    // getMuxesView: Returns an array of authorized mux addresses.
    function getMuxesView() external view returns (address[] memory);
    // SIUpdate: Updates position data for an authorized mux using encoded parameters.
    function SIUpdate(
        uint256 positionId,
        string memory coreParams,
        string memory priceData,
        string memory marginData,
        string memory leverageAndRiskParams,
        string memory tokenAndInterestParams,
        string memory positionArrayParams
    ) external;
    // removePositionIndex: Removes a position ID from pending or active arrays for an authorized mux.
    function removePositionIndex(uint256 positionId, uint8 positionType, address listingAddress) external;
    // positionByIndex: Returns all position data for a given position ID.
    function positionByIndex(uint256 positionId) external view returns (
        PositionCoreBase memory coreBase,
        PositionCoreStatus memory coreStatus,
        PriceParams memory price,
        MarginParams memory margin,
        LeverageParams memory leverage,
        RiskParams memory risk,
        address token
    );
    // PositionsByTypeView: Returns active position IDs for a given type starting at an index, up to maxIterations.
    function PositionsByTypeView(uint8 positionType, uint256 startIndex, uint256 maxIterations) external view returns (uint256[] memory positionIds);
    // PositionsByAddressView: Returns pending position IDs for a maker starting at an index, up to maxIterations.
    function PositionsByAddressView(address maker, uint256 startIndex, uint256 maxIterations) external view returns (uint256[] memory positionIds);
    // TotalActivePositionsView: Returns the count of active positions.
    function TotalActivePositionsView() external view returns (uint256 count);
    // queryInterest: Returns open interest and timestamps from a starting block height, up to maxIterations.
    function queryInterest(uint256 startIndex, uint256 maxIterations) external view returns (
        uint256[] memory longIO,
        uint256[] memory shortIO,
        uint256[] memory timestamps
    );
    // PositionHealthView: Returns margin ratio, liquidation distance, and estimated profit/loss for a position.
    function PositionHealthView(uint256 positionId) external view returns (
        uint256 marginRatio,
        uint256 distanceToLiquidation,
        uint256 estimatedProfitLoss
    );
    // AggregateMarginByToken: Returns maker addresses and initial margins for a token pair, up to maxIterations.
    function AggregateMarginByToken(
        address tokenA,
        address tokenB,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (address[] memory makers, uint256[] memory margins);
    // OpenInterestTrend: Returns leverage amounts and timestamps for open positions of a listing, up to maxIterations.
    function OpenInterestTrend(
        address listingAddress,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (uint256[] memory leverageAmounts, uint256[] memory timestamps);
    // LiquidationRiskCount: Returns the count of positions at liquidation risk for a listing, up to maxIterations.
    function LiquidationRiskCount(address listingAddress, uint256 maxIterations) external view returns (uint256 count);
}