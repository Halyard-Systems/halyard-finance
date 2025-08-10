// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "lib/forge-std/src/Test.sol";

import {DepositManager} from "../../../src/DepositManager.sol";
import {BorrowManager} from "../../../src/BorrowManager.sol";

import {BaseTest} from "../BaseTest.t.sol";

contract AdminTest is BaseTest {
    function test_SetLtv() public {
        // Test setting valid LTV
        borrowManager.setLtv(0.7e18); // 70%
        assertEq(borrowManager.getLtv(), 0.7e18);

        // Test setting to 100%
        borrowManager.setLtv(1e18);
        assertEq(borrowManager.getLtv(), 1e18);

        // Test setting to 0%
        borrowManager.setLtv(0);
        assertEq(borrowManager.getLtv(), 0);
    }

    function test_SetLtv_OnlyOwner() public {
        // Test that non-owner cannot set LTV
        vm.prank(alice);
        vm.expectRevert("Not owner");
        borrowManager.setLtv(0.8e18);

        // Verify LTV hasn't changed
        assertEq(borrowManager.getLtv(), 0.5e18);
    }

    function test_SetLtv_InvalidValue() public {
        // Test that LTV > 100% is rejected
        vm.expectRevert("LTV must be <= 100%");
        borrowManager.setLtv(1.5e18); // 150%

        // Verify LTV hasn't changed
        assertEq(borrowManager.getLtv(), 0.5e18);
    }

    function test_GetLtv() public view {
        // Test getLtv returns correct value
        assertEq(borrowManager.getLtv(), 0.5e18);
    }

    function test_ReceiveETH() public {
        uint256 sendAmount = 1 ether;
        uint256 initialBalance = address(borrowManager).balance;

        // Send ETH to BorrowManager via receive function
        (bool success,) = address(borrowManager).call{value: sendAmount}("");
        assertTrue(success, "ETH transfer should succeed");

        // Check that BorrowManager received the ETH
        assertEq(address(borrowManager).balance, initialBalance + sendAmount);
    }
}
