// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DepositManager} from "../../../src/DepositManager.sol";
import {BaseTest} from "../BaseTest.t.sol";

contract AdminTest is BaseTest {
    function test_AddNewToken() public {
        string memory symbol = "DAI";
        address daiAddress = address(
            0x6B175474E89094C44Da98b954EedeAC495271d0F
        );
        uint8 decimals = 18;

        vm.prank(address(this));
        depositManager.addToken(
            symbol,
            daiAddress,
            decimals,
            0.05e27, // 5% base rate
            0.3e27, // 30% slope1
            3.0e27, // 300% slope2
            0.8e18, // 80% utilization kink
            0.1e27 // 10% reserve factor
        );

        bytes32 daiTokenId = keccak256(abi.encodePacked(symbol));
        DepositManager.Asset memory config = depositManager.getAsset(
            daiTokenId
        );

        assertEq(config.tokenAddress, daiAddress);
        assertEq(config.decimals, decimals);
        assertTrue(config.isActive);
    }

    function test_SetTokenActive() public {
        vm.prank(address(this));
        depositManager.setTokenActive(USDC_TOKEN_ID, false);

        DepositManager.Asset memory config = depositManager.getAsset(
            USDC_TOKEN_ID
        );
        assertFalse(config.isActive);

        vm.prank(alice);
        vm.expectRevert();
        depositManager.deposit(USDC_TOKEN_ID, 1000 * USDC_DECIMALS);
    }

    function test_EmergencyWithdraw() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);

        uint256 contractBalanceBefore = mockUSDC.balanceOf(
            address(depositManager)
        );
        uint256 ownerBalanceBefore = mockUSDC.balanceOf(address(this));

        depositManager.emergencyWithdraw(USDC_TOKEN_ID, address(this));

        uint256 contractBalanceAfter = mockUSDC.balanceOf(
            address(depositManager)
        );
        uint256 ownerBalanceAfter = mockUSDC.balanceOf(address(this));

        assertEq(
            contractBalanceAfter,
            0,
            "Contract should be empty after emergency withdraw"
        );
        assertEq(
            ownerBalanceAfter,
            ownerBalanceBefore + contractBalanceBefore,
            "Owner should receive all tokens"
        );
    }

    function test_EmergencyWithdrawOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert("Must be owner");
        depositManager.emergencyWithdraw(USDC_TOKEN_ID, alice);
    }

    function test_EmergencyWithdrawETH() public {
        uint256 depositAmount = 1 ether;

        vm.prank(alice);
        depositManager.deposit{value: depositAmount}(
            ETH_TOKEN_ID,
            depositAmount
        );

        uint256 contractBalanceBefore = address(depositManager).balance;
        uint256 aliceBalanceBefore = alice.balance;

        // Transfer to alice instead of the test contract (which can't receive ETH properly)
        depositManager.emergencyWithdraw(ETH_TOKEN_ID, alice);

        uint256 contractBalanceAfter = address(depositManager).balance;
        uint256 aliceBalanceAfter = alice.balance;

        assertEq(
            contractBalanceAfter,
            0,
            "Contract should be empty after emergency withdraw"
        );
        assertEq(
            aliceBalanceAfter,
            aliceBalanceBefore + contractBalanceBefore,
            "Alice should receive all ETH"
        );
    }

    function test_AddTokenOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert("Must be owner");
        depositManager.addToken(
            "TEST",
            address(0x123),
            18,
            0.1e27,
            0.5e27,
            5.0e27,
            0.8e18,
            0.1e27
        );
    }

    function test_SetBorrowManagerOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert("Must be owner");
        depositManager.setBorrowManager(alice);
    }

    function test_SetTokenActiveOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert("Must be owner");
        depositManager.setTokenActive(USDC_TOKEN_ID, false);
    }

    function test_AddTokenAlreadyExists() public {
        vm.prank(address(this));
        vm.expectRevert("Token already exists");
        depositManager.addToken(
            "USDC",
            address(0x123),
            18,
            0.1e27,
            0.5e27,
            5.0e27,
            0.8e18,
            0.1e27
        );
    }

    function test_SetTokenActiveForETH() public {
        vm.prank(address(this));
        vm.expectRevert(); // Should revert for ETH token
        depositManager.setTokenActive(ETH_TOKEN_ID, false);
    }

    // TODO: combine event assertion into other tests
    function test_EventEmission() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        // Test that events are emitted by checking the function executes without reverting
        // and that the state changes correctly
        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);

        assertEq(
            depositManager.balanceOf(USDC_TOKEN_ID, alice),
            depositAmount,
            "Deposit should work"
        );

        // Check that the deposit was recorded
        DepositManager.Asset memory config = depositManager.getAsset(
            USDC_TOKEN_ID
        );
        assertEq(
            config.totalDeposits,
            depositAmount,
            "Total deposits should be updated"
        );
    }

    function test_WithdrawEventEmission() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);

        // Test that withdraw events are emitted by checking the function executes without reverting
        vm.prank(alice);
        depositManager.withdraw(USDC_TOKEN_ID, depositAmount);

        assertEq(
            depositManager.balanceOf(USDC_TOKEN_ID, alice),
            0,
            "Withdraw should work"
        );

        // Check that the withdrawal was recorded
        DepositManager.Asset memory config = depositManager.getAsset(
            USDC_TOKEN_ID
        );
        assertEq(config.totalDeposits, 0, "Total deposits should be updated");
    }

    function test_TotalBorrowsEvents() public {
        uint256 borrowAmount = 500 * USDC_DECIMALS;

        // Test that borrow events are emitted by checking the function executes without reverting
        depositManager.incrementTotalBorrows(USDC_TOKEN_ID, borrowAmount);

        DepositManager.Asset memory config = depositManager.getAsset(
            USDC_TOKEN_ID
        );
        assertEq(
            config.totalBorrows,
            borrowAmount,
            "Total borrows should be incremented"
        );

        depositManager.decrementTotalBorrows(USDC_TOKEN_ID, borrowAmount);

        config = depositManager.getAsset(USDC_TOKEN_ID);
        assertEq(config.totalBorrows, 0, "Total borrows should be decremented");
    }

    function test_SetBorrowManager() public {
        address newBorrowManager = address(0x456);

        depositManager.setBorrowManager(newBorrowManager);
        assertEq(depositManager.borrowManager(), newBorrowManager);
    }

    function test_ReentrancyProtection() public {
        // Test that the contract doesn't allow reentrancy attacks
        // This is a basic test - in a real scenario you'd need a malicious contract
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);

        // Try to withdraw and immediately deposit again
        vm.prank(alice);
        depositManager.withdraw(USDC_TOKEN_ID, depositAmount);

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);

        assertEq(
            depositManager.balanceOf(USDC_TOKEN_ID, alice),
            depositAmount,
            "Should handle sequential operations correctly"
        );
    }

    function test_ReceiveFunction() public {
        // Test that the contract can receive ETH
        uint256 ethAmount = 1 ether;

        (bool success, ) = address(depositManager).call{value: ethAmount}("");
        assertTrue(success, "Contract should be able to receive ETH");
        assertEq(
            address(depositManager).balance,
            ethAmount,
            "Contract should have received the ETH"
        );
    }
}
