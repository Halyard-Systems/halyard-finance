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
    function finalizePendingWithdraw(bytes32 withdrawId, bool success)
        external
        returns (address user, uint32 srcEid, address asset, uint256 amount, bool exists);

    /// @notice Finalize a pending borrow after spoke receipt.
    function finalizePendingBorrow(bytes32 borrowId, bool success)
        external
        returns (
            address user,
            uint32 dstEid,
            address asset,
            uint256 amount,
            address receiver,
            bool exists,
            bool finalized
        );

    /// @notice Clear debt reservation after DebtManager mints debt.
    function clearBorrowReservation(bytes32 borrowId) external;

    /// @notice Create a pending liquidation (reserves collateral for seizure, stores debt for deferred burn).
    function createPendingLiquidation(
        bytes32 liqId,
        address user,
        uint32 seizeEid,
        address seizeAsset,
        uint256 seizeAmount,
        address liquidator,
        uint32 debtEid,
        address debtAsset,
        uint256 debtRepayAmount
    ) external;

    /// @notice Finalize a pending liquidation after spoke receipt.
    function finalizePendingLiquidation(bytes32 liqId, bool success)
        external
        returns (
            address user,
            uint32 seizeEid,
            address seizeAsset,
            uint256 seizeAmount,
            address liquidator,
            uint32 debtEid,
            address debtAsset,
            uint256 debtRepayAmount,
            bool exists,
            bool finalized
        );

    /// @notice Get available collateral (total minus reserved).
    function availableCollateralOf(address user, uint32 eid, address asset) external view returns (uint256);

    /// @notice Get reserved debt for in-flight borrows.
    function reservedDebtOf(address user, uint32 eid, address asset) external view returns (uint256);
}
