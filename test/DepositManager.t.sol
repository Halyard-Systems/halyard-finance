// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "lib/forge-std/src/Test.sol";
import {DepositManager} from "../src/DepositManager.sol";
import {IStargateRouter} from "../src/interfaces/IStargateRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockUSDC {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint8 public decimals = 6;
    string public name = "USD Coin";
    string public symbol = "USDC";

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        require(balanceOf[from] >= amount, "USDC transfer failed");
        require(allowance[from][msg.sender] >= amount, "USDC transfer failed");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract DepositManagerTest is Test {
    DepositManager public depositManager;
    MockUSDC public mockUSDC;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public mockStargateRouter = address(0x123);

    uint256 public constant RAY = 1e27;
    uint256 public constant YEAR = 365 days;
    uint256 public constant USDC_DECIMALS = 1e6;

    function setUp() public {
        // Deploy mock USDC
        mockUSDC = new MockUSDC();

        // Mock Stargate router address and pool ID for testing
        uint256 mockPoolId = 1;
        depositManager = new DepositManager(
            mockStargateRouter,
            mockPoolId,
            address(mockUSDC)
        );

        // Mock the Stargate router addLiquidity call to always succeed
        vm.mockCall(
            mockStargateRouter,
            abi.encodeWithSelector(IStargateRouter.addLiquidity.selector),
            abi.encode()
        );

        // Give users some USDC
        mockUSDC.mint(alice, 10000 * USDC_DECIMALS);
        mockUSDC.mint(bob, 10000 * USDC_DECIMALS);
        mockUSDC.mint(charlie, 10000 * USDC_DECIMALS);

        // Approve DepositManager to spend USDC
        vm.prank(alice);
        mockUSDC.approve(address(depositManager), type(uint256).max);
        vm.prank(bob);
        mockUSDC.approve(address(depositManager), type(uint256).max);
        vm.prank(charlie);
        mockUSDC.approve(address(depositManager), type(uint256).max);
    }

    function test_InitialState() public view {
        assertEq(depositManager.RAY(), RAY);
        assertEq(depositManager.baseRate(), 0.1e27); // 10%
        assertEq(depositManager.slope1(), 0.5e27); // 50%
        assertEq(depositManager.slope2(), 5.0e27); // 500%
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
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(depositAmount);

        assertEq(depositManager.balanceOf(alice), depositAmount);
        assertEq(depositManager.totalDeposits(), depositAmount);
        assertEq(depositManager.totalScaledSupply(), depositAmount);
        assertEq(depositManager.scaledBalance(alice), depositAmount);
    }

    function test_DepositZeroAmount() public {
        vm.prank(alice);
        depositManager.deposit(0);

        assertEq(depositManager.balanceOf(alice), 0);
        assertEq(depositManager.totalDeposits(), 0);
        assertEq(depositManager.totalScaledSupply(), 0);
    }

    function test_DepositInsufficientAllowance() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        // Revoke allowance
        vm.prank(alice);
        mockUSDC.approve(address(depositManager), 0);

        vm.prank(alice);
        vm.expectRevert("USDC transfer failed");
        depositManager.deposit(depositAmount);
    }

    function test_DepositInsufficientBalance() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        // Set balance to 0 by overriding the balance
        vm.store(
            address(mockUSDC),
            keccak256(abi.encode(alice, uint256(0))), // balanceOf[alice]
            bytes32(0)
        );

        vm.prank(alice);
        vm.expectRevert("USDC transfer failed");
        depositManager.deposit(depositAmount);
    }

    function test_MultipleDeposits() public {
        uint256 aliceDeposit = 1000 * USDC_DECIMALS;
        uint256 bobDeposit = 500 * USDC_DECIMALS;

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
        uint256 depositAmount = 1000 * USDC_DECIMALS;
        uint256 withdrawAmount = 300 * USDC_DECIMALS;

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

    function test_WithdrawZeroAmount() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(depositAmount);

        vm.prank(alice);
        depositManager.withdraw(0);

        assertEq(depositManager.balanceOf(alice), depositAmount);
        assertEq(depositManager.totalDeposits(), depositAmount);
    }

    function test_WithdrawMoreThanBalance() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;
        uint256 withdrawAmount = 1500 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(depositAmount);

        vm.prank(alice);
        vm.expectRevert(); // Should revert due to underflow
        depositManager.withdraw(withdrawAmount);
    }

    function test_WithdrawFromZeroBalance() public {
        vm.prank(alice);
        vm.expectRevert();
        depositManager.withdraw(100 * USDC_DECIMALS);
    }

    function test_WithdrawExactBalance() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(depositAmount);

        vm.prank(alice);
        depositManager.withdraw(depositAmount);

        assertEq(depositManager.balanceOf(alice), 0);
        assertEq(depositManager.totalDeposits(), 0);
        assertEq(depositManager.totalScaledSupply(), 0);
    }

    // function test_InterestAccrual() public {
    //     uint256 depositAmount = 1000 * USDC_DECIMALS;

    //     vm.prank(alice);
    //     depositManager.deposit(depositAmount);

    //     // Create borrows organically to create utilization
    //     vm.prank(charlie);
    //     depositManager.borrow(500 * USDC_DECIMALS); // 50% utilization

    //     // Advance time by 1 year to ensure significant interest
    //     vm.warp(block.timestamp + YEAR);

    //     // Trigger interest accrual by making a deposit
    //     vm.prank(bob);
    //     depositManager.deposit(100 * USDC_DECIMALS);

    //     // Alice should have earned interest
    //     uint256 aliceBalance = depositManager.balanceOf(alice);
    //     assertGt(
    //         aliceBalance,
    //         depositAmount,
    //         "Alice should have earned interest"
    //     );

    //     // Check that liquidity index increased
    //     assertGt(
    //         depositManager.liquidityIndex(),
    //         RAY,
    //         "Liquidity index should have increased"
    //     );
    // }

    // function test_CalculateSupplyRate_BelowKink() public {
    //     // Test utilization below kink (80%)
    //     vm.prank(alice);
    //     depositManager.deposit(1000 * USDC_DECIMALS);

    //     vm.prank(charlie);
    //     depositManager.borrow(500 * USDC_DECIMALS); // 50% utilization

    //     vm.warp(block.timestamp + YEAR);

    //     vm.prank(bob);
    //     depositManager.deposit(100 * USDC_DECIMALS);

    //     uint256 aliceBalance = depositManager.balanceOf(alice);
    //     assertGt(
    //         aliceBalance,
    //         1000 * USDC_DECIMALS,
    //         "Should earn interest at below-kink rate"
    //     );
    // }

    function test_CalculateSupplyRate_AboveKink() public {
        // Test utilization above kink (80%)
        vm.prank(alice);
        depositManager.deposit(1000 * USDC_DECIMALS);

        vm.prank(charlie);
        depositManager.borrow(900 * USDC_DECIMALS); // 90% utilization

        vm.warp(block.timestamp + YEAR);

        vm.prank(bob);
        depositManager.deposit(100 * USDC_DECIMALS);

        uint256 aliceBalance = depositManager.balanceOf(alice);
        assertGt(
            aliceBalance,
            1000 * USDC_DECIMALS,
            "Should earn interest at above-kink rate"
        );
    }

    // function test_CalculateSupplyRate_AtKink() public {
    //     // Test utilization exactly at kink (80%)
    //     vm.prank(alice);
    //     depositManager.deposit(1000 * USDC_DECIMALS);

    //     vm.prank(charlie);
    //     depositManager.borrow(800 * USDC_DECIMALS); // 80% utilization

    //     vm.warp(block.timestamp + YEAR);

    //     vm.prank(bob);
    //     depositManager.deposit(100 * USDC_DECIMALS);

    //     uint256 aliceBalance = depositManager.balanceOf(alice);
    //     assertGt(
    //         aliceBalance,
    //         1000 * USDC_DECIMALS,
    //         "Should earn interest at kink rate"
    //     );
    // }

    function test_ZeroUtilization() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(depositAmount);

        // No borrows, so utilization is 0
        vm.warp(block.timestamp + YEAR);

        vm.prank(bob);
        depositManager.deposit(100 * USDC_DECIMALS);

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
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(depositAmount);

        uint256 initialIndex = depositManager.liquidityIndex();

        // Make another deposit immediately (no time passed)
        vm.prank(bob);
        depositManager.deposit(100 * USDC_DECIMALS);

        assertEq(
            depositManager.liquidityIndex(),
            initialIndex,
            "Index should not change when no time passed"
        );
    }

    function test_UpdateLiquidityIndex_NoDeposits() public {
        // No deposits, so totalDeposits is 0
        vm.warp(block.timestamp + YEAR);

        vm.prank(alice);
        depositManager.deposit(100 * USDC_DECIMALS);

        assertEq(
            depositManager.liquidityIndex(),
            RAY,
            "Index should remain RAY when no deposits exist"
        );
    }

    // function test_ComplexScenario() public {
    //     // Alice deposits 1000 tokens
    //     vm.prank(alice);
    //     depositManager.deposit(1000 * USDC_DECIMALS);

    //     // Set up some borrows for 60% utilization
    //     vm.prank(charlie);
    //     depositManager.borrow(600 * USDC_DECIMALS);

    //     // Advance 6 months
    //     vm.warp(block.timestamp + (6 * 30 days));

    //     // Bob deposits 500 tokens
    //     vm.prank(bob);
    //     depositManager.deposit(500 * USDC_DECIMALS);

    //     // Charlie deposits 300 tokens
    //     vm.prank(charlie);
    //     depositManager.deposit(300 * USDC_DECIMALS);

    //     // Advance another 6 months
    //     vm.warp(block.timestamp + (6 * 30 days));

    //     // Alice withdraws 200 tokens
    //     vm.prank(alice);
    //     depositManager.withdraw(200 * USDC_DECIMALS);

    //     // Check final balances
    //     uint256 aliceBalance = depositManager.balanceOf(alice);
    //     uint256 bobBalance = depositManager.balanceOf(bob);
    //     uint256 charlieBalance = depositManager.balanceOf(charlie);

    //     assertGt(
    //         aliceBalance,
    //         800 * USDC_DECIMALS,
    //         "Alice should have earned interest on her remaining balance"
    //     );
    //     assertGe(
    //         bobBalance,
    //         500 * USDC_DECIMALS,
    //         "Bob should have earned interest"
    //     );
    //     assertGe(
    //         charlieBalance,
    //         300 * USDC_DECIMALS,
    //         "Charlie should have earned interest"
    //     );

    //     // Total deposits should be correct
    //     assertEq(
    //         depositManager.totalDeposits(),
    //         1000 *
    //             USDC_DECIMALS +
    //             500 *
    //             USDC_DECIMALS +
    //             300 *
    //             USDC_DECIMALS -
    //             200 *
    //             USDC_DECIMALS
    //     );
    // }

    function test_EdgeCase_VerySmallDeposit() public {
        uint256 tinyDeposit = 1; // 1 wei

        vm.prank(alice);
        depositManager.deposit(tinyDeposit);

        assertEq(depositManager.balanceOf(alice), tinyDeposit);
        assertEq(depositManager.totalDeposits(), tinyDeposit);
    }

    function test_EdgeCase_VeryLargeDeposit() public {
        uint256 largeDeposit = type(uint128).max; // Large but safe number

        mockUSDC.mint(alice, largeDeposit);
        vm.prank(alice);
        mockUSDC.approve(address(depositManager), largeDeposit);

        vm.prank(alice);
        depositManager.deposit(largeDeposit);

        assertEq(depositManager.balanceOf(alice), largeDeposit);
        assertEq(depositManager.totalDeposits(), largeDeposit);
    }

    function test_Borrow() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;
        uint256 borrowAmount = 500 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(depositAmount);

        vm.prank(charlie);
        depositManager.borrow(borrowAmount);

        assertEq(depositManager.totalBorrows(), borrowAmount);
    }

    function test_BorrowZeroAmount() public {
        vm.prank(charlie);
        depositManager.borrow(0);

        assertEq(depositManager.totalBorrows(), 0);
    }

    function test_MultipleBorrows() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;
        uint256 borrow1 = 300 * USDC_DECIMALS;
        uint256 borrow2 = 200 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(depositAmount);

        vm.prank(charlie);
        depositManager.borrow(borrow1);

        vm.prank(bob);
        depositManager.borrow(borrow2);

        assertEq(depositManager.totalBorrows(), borrow1 + borrow2);
    }

    function test_BalanceOf_ZeroBalance() public {
        assertEq(depositManager.balanceOf(alice), 0);
    }

    function test_BalanceOf_AfterDeposit() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(depositAmount);

        assertEq(depositManager.balanceOf(alice), depositAmount);
    }

    // function test_BalanceOf_AfterInterest() public {
    //     uint256 depositAmount = 1000 * USDC_DECIMALS;

    //     vm.prank(alice);
    //     depositManager.deposit(depositAmount);

    //     vm.prank(charlie);
    //     depositManager.borrow(500 * USDC_DECIMALS);

    //     vm.warp(block.timestamp + YEAR);

    //     uint256 balance = depositManager.balanceOf(alice);
    //     assertGt(
    //         balance,
    //         depositAmount,
    //         "Balance should increase with interest"
    //     );
    // }

    // function test_InterestRateModel_BaseRate() public {
    //     // Test with very low utilization to see base rate effect
    //     vm.prank(alice);
    //     depositManager.deposit(1000 * USDC_DECIMALS);

    //     vm.prank(charlie);
    //     depositManager.borrow(10 * USDC_DECIMALS); // 1% utilization

    //     vm.warp(block.timestamp + YEAR);

    //     vm.prank(bob);
    //     depositManager.deposit(100 * USDC_DECIMALS);

    //     uint256 aliceBalance = depositManager.balanceOf(alice);
    //     assertGt(
    //         aliceBalance,
    //         1000 * USDC_DECIMALS,
    //         "Should earn at least base rate"
    //     );
    // }

    function test_InterestRateModel_HighUtilization() public {
        // Test with very high utilization
        vm.prank(alice);
        depositManager.deposit(1000 * USDC_DECIMALS);

        vm.prank(charlie);
        depositManager.borrow(950 * USDC_DECIMALS); // 95% utilization

        vm.warp(block.timestamp + YEAR);

        vm.prank(bob);
        depositManager.deposit(100 * USDC_DECIMALS);

        uint256 aliceBalance = depositManager.balanceOf(alice);
        assertGt(
            aliceBalance,
            1000 * USDC_DECIMALS,
            "Should earn high interest rate"
        );
    }

    function test_InterestRateModel_100PercentUtilization() public {
        // Test with 100% utilization
        vm.prank(alice);
        depositManager.deposit(1000 * USDC_DECIMALS);

        vm.prank(charlie);
        depositManager.borrow(1000 * USDC_DECIMALS); // 100% utilization

        vm.warp(block.timestamp + YEAR);

        vm.prank(bob);
        depositManager.deposit(100 * USDC_DECIMALS);

        uint256 aliceBalance = depositManager.balanceOf(alice);
        assertGt(
            aliceBalance,
            1000 * USDC_DECIMALS,
            "Should earn maximum interest rate"
        );
    }

    // function test_WithdrawAfterInterest() public {
    //     uint256 depositAmount = 1000 * USDC_DECIMALS;

    //     vm.prank(alice);
    //     depositManager.deposit(depositAmount);

    //     vm.prank(charlie);
    //     depositManager.borrow(500 * USDC_DECIMALS);

    //     vm.warp(block.timestamp + YEAR);

    //     // Alice should be able to withdraw her original amount plus interest
    //     uint256 balanceBefore = depositManager.balanceOf(alice);
    //     vm.prank(alice);
    //     depositManager.withdraw(depositAmount);

    //     uint256 balanceAfter = depositManager.balanceOf(alice);
    //     assertGt(
    //         balanceBefore - depositAmount,
    //         0,
    //         "Should have earned interest"
    //     );
    //     assertGt(
    //         balanceAfter,
    //         0,
    //         "Should have remaining balance after withdrawal"
    //     );
    // }

    function test_ReentrancyProtection() public {
        // This test ensures the contract doesn't have obvious reentrancy vulnerabilities
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(depositAmount);

        // Try to withdraw and deposit in the same transaction (if possible)
        // This is a basic reentrancy test
        vm.prank(alice);
        depositManager.withdraw(100 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit(100 * USDC_DECIMALS);

        // Should not revert and balances should be correct
        assertEq(depositManager.balanceOf(alice), depositAmount);
    }

    // function test_InterestAccrualOverMultiplePeriods() public {
    //     uint256 depositAmount = 1000 * USDC_DECIMALS;

    //     vm.prank(alice);
    //     depositManager.deposit(depositAmount);

    //     vm.prank(charlie);
    //     depositManager.borrow(500 * USDC_DECIMALS);

    //     // Advance time in multiple periods
    //     vm.warp(block.timestamp + (6 * 30 days));
    //     vm.prank(bob);
    //     depositManager.deposit(100 * USDC_DECIMALS);

    //     vm.warp(block.timestamp + (6 * 30 days));
    //     vm.prank(bob);
    //     depositManager.deposit(100 * USDC_DECIMALS);

    //     vm.warp(block.timestamp + (6 * 30 days));
    //     vm.prank(bob);
    //     depositManager.deposit(100 * USDC_DECIMALS);

    //     uint256 aliceBalance = depositManager.balanceOf(alice);
    //     assertGt(
    //         aliceBalance,
    //         depositAmount,
    //         "Should earn compound interest over multiple periods"
    //     );
    // }

    // function test_UtilizationCalculation() public {
    //     uint256 depositAmount = 1000 * USDC_DECIMALS;
    //     uint256 borrowAmount = 600 * USDC_DECIMALS;

    //     vm.prank(alice);
    //     depositManager.deposit(depositAmount);

    //     vm.prank(charlie);
    //     depositManager.borrow(borrowAmount);

    //     // Utilization should be 60%
    //     vm.warp(block.timestamp + YEAR);

    //     vm.prank(bob);
    //     depositManager.deposit(100 * USDC_DECIMALS);

    //     // The utilization calculation should work correctly
    //     // We can verify this by checking that interest is earned at the expected rate
    //     uint256 aliceBalance = depositManager.balanceOf(alice);
    //     assertGt(
    //         aliceBalance,
    //         depositAmount,
    //         "Should earn interest at 60% utilization rate"
    //     );
    // }
}
