// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "lib/forge-std/src/Test.sol";
import {DepositManager} from "../src/DepositManager.sol";
import {IStargateRouter} from "../src/interfaces/IStargateRouter.sol";

contract DepositManagerTest is Test {
    DepositManager public depositManager;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public mockStargateRouter = address(0x123);

    uint256 public constant RAY = 1e27;
    uint256 public constant YEAR = 365 days;

    function setUp() public {
        // Mock Stargate router address and pool ID for testing
        uint256 mockPoolId = 1;
        depositManager = new DepositManager(mockStargateRouter, mockPoolId);

        // Mock the Stargate router addLiquidity call to always succeed
        vm.mockCall(
            mockStargateRouter,
            abi.encodeWithSelector(IStargateRouter.addLiquidity.selector),
            abi.encode()
        );
    }

    function test_InitialState() public view {
        assertEq(depositManager.RAY(), RAY);
        assertEq(depositManager.baseRate(), 0.02e27); // 2%
        assertEq(depositManager.slope1(), 0.1e27); // 10%
        assertEq(depositManager.slope2(), 3.0e27); // 300%
        assertEq(depositManager.kink(), 0.8e18); // 80%
        assertEq(depositManager.reserveFactor(), 0.1e27); // 10%
        assertEq(depositManager.liquidityIndex(), RAY);
        assertEq(depositManager.totalScaledSupply(), 0);
        assertEq(depositManager.totalDeposits(), 0);
        assertEq(depositManager.totalBorrows(), 0);
        assertEq(address(depositManager.stargateRouter()), address(0x123));
        assertEq(depositManager.poolId(), 1);
    }

    function test_Deposit() public {
        uint256 depositAmount = 1000e18;

        vm.prank(alice);
        depositManager.deposit(depositAmount);

        assertEq(depositManager.balanceOf(alice), depositAmount);
        assertEq(depositManager.totalDeposits(), depositAmount);
        assertEq(depositManager.totalScaledSupply(), depositAmount);
        assertEq(depositManager.scaledBalance(alice), depositAmount);
    }

    function test_MultipleDeposits() public {
        uint256 aliceDeposit = 1000e18;
        uint256 bobDeposit = 500e18;

        vm.prank(alice);
        depositManager.deposit(aliceDeposit);

        vm.prank(bob);
        depositManager.deposit(bobDeposit);

        assertEq(depositManager.balanceOf(alice), aliceDeposit);
        assertEq(depositManager.balanceOf(bob), bobDeposit);
        assertEq(depositManager.totalDeposits(), aliceDeposit + bobDeposit);
        assertEq(depositManager.totalScaledSupply(), aliceDeposit + bobDeposit);
    }

    function test_Withdraw() public {
        uint256 depositAmount = 1000e18;
        uint256 withdrawAmount = 300e18;

        vm.prank(alice);
        depositManager.deposit(depositAmount);

        vm.prank(alice);
        depositManager.withdraw(withdrawAmount);

        assertEq(
            depositManager.balanceOf(alice),
            depositAmount - withdrawAmount
        );
        assertEq(
            depositManager.totalDeposits(),
            depositAmount - withdrawAmount
        );
        assertEq(
            depositManager.totalScaledSupply(),
            depositAmount - withdrawAmount
        );
    }

    function test_WithdrawMoreThanBalance() public {
        uint256 depositAmount = 1000e18;
        uint256 withdrawAmount = 1500e18;

        vm.prank(alice);
        depositManager.deposit(depositAmount);

        vm.prank(alice);
        vm.expectRevert(); // Should revert due to underflow
        depositManager.withdraw(withdrawAmount);
    }

    function test_InterestAccrual() public {
        uint256 depositAmount = 1000e18;

        vm.prank(alice);
        depositManager.deposit(depositAmount);

        // Create borrows organically to create utilization
        vm.prank(charlie);
        depositManager.borrow(500e18); // 50% utilization

        // Advance time by 1 year
        vm.warp(block.timestamp + YEAR);

        // Trigger interest accrual by making a deposit
        vm.prank(bob);
        depositManager.deposit(100e18);

        // Alice should have earned interest
        uint256 aliceBalance = depositManager.balanceOf(alice);
        assertGt(
            aliceBalance,
            depositAmount,
            "Alice should have earned interest"
        );

        // Check that liquidity index increased
        assertGt(
            depositManager.liquidityIndex(),
            RAY,
            "Liquidity index should have increased"
        );
    }

    function test_CalculateSupplyRate_BelowKink() public {
        // Test utilization below kink (80%)
        // We can't directly call _calculateSupplyRate as it's internal
        // But we can test it indirectly through the deposit mechanism

        // Set up deposits and borrows organically
        vm.prank(alice);
        depositManager.deposit(1000e18);

        vm.prank(charlie);
        depositManager.borrow(500e18); // 50% utilization

        vm.warp(block.timestamp + YEAR);

        vm.prank(bob);
        depositManager.deposit(100e18);

        uint256 aliceBalance = depositManager.balanceOf(alice);
        assertGt(
            aliceBalance,
            1000e18,
            "Should earn interest at below-kink rate"
        );
    }

    function test_CalculateSupplyRate_AboveKink() public {
        // Test utilization above kink (80%)
        // Set up deposits and borrows organically
        vm.prank(alice);
        depositManager.deposit(1000e18);

        vm.prank(charlie);
        depositManager.borrow(900e18); // 90% utilization

        vm.warp(block.timestamp + YEAR);

        vm.prank(bob);
        depositManager.deposit(100e18);

        uint256 aliceBalance = depositManager.balanceOf(alice);
        assertGt(
            aliceBalance,
            1000e18,
            "Should earn interest at above-kink rate"
        );
    }

    function test_ZeroUtilization() public {
        uint256 depositAmount = 1000e18;

        vm.prank(alice);
        depositManager.deposit(depositAmount);

        // No borrows, so utilization is 0
        vm.warp(block.timestamp + YEAR);

        vm.prank(bob);
        depositManager.deposit(100e18);

        uint256 aliceBalance = depositManager.balanceOf(alice);
        assertEq(
            aliceBalance,
            depositAmount,
            "Should not earn interest with 0 utilization"
        );
        assertEq(
            depositManager.liquidityIndex(),
            RAY,
            "Liquidity index should remain unchanged"
        );
    }

    function test_UpdateLiquidityIndex_NoTimePassed() public {
        uint256 depositAmount = 1000e18;

        vm.prank(alice);
        depositManager.deposit(depositAmount);

        uint256 initialIndex = depositManager.liquidityIndex();

        // Make another deposit immediately (no time passed)
        vm.prank(bob);
        depositManager.deposit(100e18);

        assertEq(
            depositManager.liquidityIndex(),
            initialIndex,
            "Index should not change when no time passed"
        );
    }

    function test_ComplexScenario() public {
        // Alice deposits 1000 tokens
        vm.prank(alice);
        depositManager.deposit(1000e18);

        // Set up some borrows for 60% utilization
        vm.prank(charlie);
        depositManager.borrow(600e18);

        // Advance 6 months
        vm.warp(block.timestamp + (6 * 30 days));

        // Bob deposits 500 tokens
        vm.prank(bob);
        depositManager.deposit(500e18);

        // Charlie deposits 300 tokens
        vm.prank(charlie);
        depositManager.deposit(300e18);

        // Advance another 6 months
        vm.warp(block.timestamp + (6 * 30 days));

        // Alice withdraws 200 tokens
        vm.prank(alice);
        depositManager.withdraw(200e18);

        // Check final balances
        uint256 aliceBalance = depositManager.balanceOf(alice);
        uint256 bobBalance = depositManager.balanceOf(bob);
        uint256 charlieBalance = depositManager.balanceOf(charlie);

        assertGt(
            aliceBalance,
            800e18,
            "Alice should have earned interest on her remaining balance"
        );
        assertGt(bobBalance, 500e18, "Bob should have earned interest");
        assertGt(charlieBalance, 300e18, "Charlie should have earned interest");

        // Total deposits should be correct
        assertEq(
            depositManager.totalDeposits(),
            1000e18 + 500e18 + 300e18 - 200e18
        );
    }

    function test_Revert_WithdrawFromZeroBalance() public {
        vm.prank(alice);
        vm.expectRevert();
        depositManager.withdraw(100e18);
    }

    function test_EdgeCase_VerySmallDeposit() public {
        uint256 tinyDeposit = 1; // 1 wei

        vm.prank(alice);
        depositManager.deposit(tinyDeposit);

        assertEq(depositManager.balanceOf(alice), tinyDeposit);
        assertEq(depositManager.totalDeposits(), tinyDeposit);
    }

    function test_EdgeCase_VeryLargeDeposit() public {
        uint256 largeDeposit = type(uint128).max; // Large but safe number

        vm.prank(alice);
        depositManager.deposit(largeDeposit);

        assertEq(depositManager.balanceOf(alice), largeDeposit);
        assertEq(depositManager.totalDeposits(), largeDeposit);
    }
}
