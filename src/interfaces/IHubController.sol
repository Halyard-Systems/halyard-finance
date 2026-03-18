// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

/**
 * @title IHubController
 * @notice Interface for HubController message sending functions
 * @dev Used by HubRouter to send commands to spokes
 */
interface IHubController {
    /// @notice Send CMD_RELEASE_WITHDRAW command to spoke
    function sendWithdrawCommand(
        uint32 dstEid,
        bytes32 withdrawId,
        address user,
        address receiver,
        address asset,
        uint256 amount,
        bytes calldata options,
        MessagingFee calldata fee,
        address refundAddress
    ) external payable;

    /// @notice Send CMD_RELEASE_BORROW command to spoke
    function sendBorrowCommand(
        uint32 dstEid,
        bytes32 borrowId,
        address user,
        address receiver,
        address asset,
        uint256 amount,
        bytes calldata options,
        MessagingFee calldata fee,
        address refundAddress
    ) external payable;

    /// @notice Send CMD_SEIZE_COLLATERAL command to spoke
    function sendSeizeCommand(
        uint32 dstEid,
        bytes32 liqId,
        address user,
        address liquidator,
        address asset,
        uint256 amount,
        bytes calldata options,
        MessagingFee calldata fee,
        address refundAddress
    ) external payable;

    /// @notice Quote the LZ fee for any hub->spoke command
    function quoteCommand(uint32 dstEid, bytes calldata options) external view returns (MessagingFee memory);
}
