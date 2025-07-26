// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.1 (initial Iteration )
// Changes:
// - v0.0.1: changed "SS" prefix to "CC", now uses updated CCLiquidityTemplate. 

import "./utils/CCLiquidityTemplate.sol";

contract CCLiquidityLogic {
    function deploy(bytes32 salt) external returns (address) {
        address liquidityAddress = address(new CCLiquidityTemplate{salt: salt}());
        return liquidityAddress;
    }
}