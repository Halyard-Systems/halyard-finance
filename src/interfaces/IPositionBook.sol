// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IPositionBook
 * @notice Interface for PositionBook functionality
 */
interface IPositionBook {
    /// @notice Credit collateral to a user's position after a spoke deposit receipt.
    function creditCollateral(address user, uint32 srcEid, address asset, uint256 amount) external;
}
