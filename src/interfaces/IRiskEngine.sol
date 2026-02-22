// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IRiskEngine
 * @notice Interface for RiskEngine functions called by HubRouter
 */
interface IRiskEngine {
    struct CollateralSlot {
        uint32 eid;
        address asset;
    }

    struct DebtSlot {
        uint32 eid;
        address asset;
    }

    function validateAndCreateWithdraw(
        bytes32 withdrawId,
        address user,
        uint32 srcEid,
        address collateralAsset,
        uint256 amount,
        address receiver,
        CollateralSlot[] calldata collateralSlots,
        DebtSlot[] calldata debtSlots
    ) external;
}
