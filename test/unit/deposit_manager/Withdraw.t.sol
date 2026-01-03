// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DepositManager} from "../../../src/DepositManager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BaseTestOld} from "../BaseTestOld.t.sol";

contract WithdrawTest is BaseTestOld {
    function test_ETHWithdraw() public {
        uint256 depositAmount = 1 ether;
        uint256 withdrawAmount = 0.3 ether;
        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        depositManager.deposit{value: depositAmount}(ETH_TOKEN_ID, depositAmount);

        vm.prank(alice);
        depositManager.withdraw(ETH_TOKEN_ID, withdrawAmount);

        assertEq(depositManager.balanceOf(ETH_TOKEN_ID, alice), depositAmount - withdrawAmount);
        assertEq(alice.balance, aliceBalanceBefore - depositAmount + withdrawAmount);

        DepositManager.Asset memory config = depositManager.getAsset(ETH_TOKEN_ID);
        assertEq(config.totalDeposits, depositAmount - withdrawAmount);
    }

    function test_USDCWithdraw() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;
        uint256 withdrawAmount = 300 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);

        vm.prank(alice);
        depositManager.withdraw(USDC_TOKEN_ID, withdrawAmount);

        assertEq(depositManager.balanceOf(USDC_TOKEN_ID, alice), depositAmount - withdrawAmount);

        DepositManager.Asset memory config = depositManager.getAsset(USDC_TOKEN_ID);
        assertEq(config.totalDeposits, depositAmount - withdrawAmount);
    }

    function test_WithdrawZeroAmount() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);

        vm.prank(alice);
        depositManager.withdraw(USDC_TOKEN_ID, 0);

        assertEq(depositManager.balanceOf(USDC_TOKEN_ID, alice), depositAmount);

        DepositManager.Asset memory config = depositManager.getAsset(USDC_TOKEN_ID);
        assertEq(config.totalDeposits, depositAmount);
    }

    function test_WithdrawMoreThanBalance() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;
        uint256 withdrawAmount = 1500 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);

        vm.prank(alice);
        vm.expectRevert();
        depositManager.withdraw(USDC_TOKEN_ID, withdrawAmount);
    }

    function test_WithdrawFromZeroBalance() public {
        vm.prank(alice);
        vm.expectRevert();
        depositManager.withdraw(USDC_TOKEN_ID, 100 * USDC_DECIMALS);
    }

    function test_WithdrawExactBalance() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);

        vm.prank(alice);
        depositManager.withdraw(USDC_TOKEN_ID, depositAmount);

        assertEq(depositManager.balanceOf(USDC_TOKEN_ID, alice), 0);

        DepositManager.Asset memory config = depositManager.getAsset(USDC_TOKEN_ID);
        assertEq(config.totalDeposits, 0);
    }

    function test_EmergencyWithdraw() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);

        uint256 contractBalanceBefore = mockUSDC.balanceOf(address(depositManager));
        uint256 ownerBalanceBefore = mockUSDC.balanceOf(address(this));

        depositManager.emergencyWithdraw(USDC_TOKEN_ID, address(this));

        uint256 contractBalanceAfter = mockUSDC.balanceOf(address(depositManager));
        uint256 ownerBalanceAfter = mockUSDC.balanceOf(address(this));

        assertEq(contractBalanceAfter, 0, "Contract should be empty after emergency withdraw");
        assertEq(ownerBalanceAfter, ownerBalanceBefore + contractBalanceBefore, "Owner should receive all tokens");
    }

    function test_EmergencyWithdrawOnlyOwner() public {
        vm.prank(alice);
        // TODO: stub OwnableUnauthorizedAccount
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        depositManager.emergencyWithdraw(USDC_TOKEN_ID, alice);
    }

    function test_EmergencyWithdrawETH() public {
        uint256 depositAmount = 1 ether;

        vm.prank(alice);
        depositManager.deposit{value: depositAmount}(ETH_TOKEN_ID, depositAmount);

        uint256 contractBalanceBefore = address(depositManager).balance;
        uint256 aliceBalanceBefore = alice.balance;

        // Transfer to alice instead of the test contract (which can't receive ETH properly)
        depositManager.emergencyWithdraw(ETH_TOKEN_ID, alice);

        uint256 contractBalanceAfter = address(depositManager).balance;
        uint256 aliceBalanceAfter = alice.balance;

        assertEq(contractBalanceAfter, 0, "Contract should be empty after emergency withdraw");
        assertEq(aliceBalanceAfter, aliceBalanceBefore + contractBalanceBefore, "Alice should receive all ETH");
    }

    function test_EmergencyWithdrawETHOnlyOwner() public {
        vm.prank(alice);
        // TODO: stub OwnableUnauthorizedAccount
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        depositManager.emergencyWithdraw(ETH_TOKEN_ID, alice);
    }
}
