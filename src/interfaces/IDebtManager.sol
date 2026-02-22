// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IDebtManager
 * @notice Interface for DebtManager debt minting
 */
interface IDebtManager {
    function mintDebt(address user, uint32 eid, address asset, uint256 amount)
        external
        returns (uint256 scaledAdded);
}
