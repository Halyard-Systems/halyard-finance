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
    function createPendingWithdraw(bytes32 withdrawId, address user, uint32 srcEid, address asset, uint256 amount)
        external;

    /// @notice Finalize a pending withdraw after spoke receipt.
    function finalizePendingWithdraw(bytes32 withdrawId, bool success) external;

    /// @notice Finalize a pending borrow after spoke receipt.
    function finalizePendingBorrow(bytes32 borrowId, bool success)
        external
        returns (address user, uint32 dstEid, address asset, uint256 amount, address receiver, bool exists, bool finalized);

    /// @notice Clear debt reservation after DebtManager mints debt.
    function clearBorrowReservation(bytes32 borrowId) external;
}
