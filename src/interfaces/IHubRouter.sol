// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IHubRouter
 * @notice Interface for HubRouter finalization functions
 * @dev Used by HubController to finalize user operations after receiving spoke receipts
 */
interface IHubRouter {
    /// @notice Finalize a withdrawal after spoke sends WITHDRAW_RELEASED receipt
    function finalizeWithdraw(bytes32 withdrawId, address user, uint32 srcEid, address asset, uint256 amount) external;

    /// @notice Finalize a borrow after spoke sends BORROW_RELEASED receipt
    function finalizeBorrow(bytes32 borrowId, address user, uint32 srcEid, address asset, uint256 amount) external;
}
