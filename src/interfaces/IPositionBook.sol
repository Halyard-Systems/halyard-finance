// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPositionBook
 * @notice Interface for PositionBook functionality
 */
interface IPositionBook {
    /// @notice Credit collateral to a user's position after a spoke deposit receipt.
    function creditCollateral(address user, uint32 srcEid, address asset, uint256 amount) external;

    /// @notice Request a withdraw.
    function createPendingWithdraw(address user, uint32 srcEid, address asset, uint256 amount) external;
}
