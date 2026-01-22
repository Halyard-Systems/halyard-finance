// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IMessageTypes
 * @notice Shared message types and interfaces for Hub <-> Spoke communication via LayerZero
 */
interface IMessageTypes {
    /// @notice Message types for LayerZero cross-chain communication
    enum MsgType {
        // spoke -> hub receipts
        DEPOSIT_CREDITED, // 0
        BORROW_RELEASED, // 1
        WITHDRAW_RELEASED, // 2
        REPAY_RECEIVED, // 3
        COLLATERAL_SEIZED, // 4
        // hub -> spoke commands
        CMD_RELEASE_BORROW, // 5
        CMD_RELEASE_WITHDRAW, // 6
        CMD_SEIZE_COLLATERAL // 7
    }
}
