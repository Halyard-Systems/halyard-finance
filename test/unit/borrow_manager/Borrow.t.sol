// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "lib/forge-std/src/Test.sol";

import {DepositManager} from "../../../src/DepositManager.sol";
import {BorrowManager} from "../../../src/BorrowManager.sol";

import {BaseTest} from "../BaseTest.t.sol";

contract BorrowManagerTest is BaseTest {
    function test_ETHBorrow() public {
        uint256 borrowAmount = 0.1 ether; // Borrow less ETH to stay within LTV limits
        uint256 aliceBalanceBefore = alice.balance;

        // First, someone needs to deposit ETH so the contract has liquidity to borrow from
        vm.prank(bob);
        depositManager.deposit{value: 2 ether}(ETH_TOKEN_ID, 2 ether);

        // Alice needs to deposit collateral before borrowing (deposit USDC as collateral)
        // At $1 per USDC, and 50% LTV, need at least $200 collateral to borrow $100 ETH
        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, 200 * USDC_DECIMALS); // 200 USDC = $200 worth at $1 each

        // Mock Pyth data - need 3 price IDs to match 3 supported tokens
        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1)); // ETH price ID
        priceIds[1] = bytes32(uint256(2)); // USDC price ID
        priceIds[2] = bytes32(uint256(3)); // USDT price ID

        vm.prank(alice);
        borrowManager.borrow(ETH_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        assertEq(alice.balance, aliceBalanceBefore + borrowAmount);

        DepositManager.Asset memory config = depositManager.getAsset(ETH_TOKEN_ID);
        assertEq(config.totalBorrows, borrowAmount);
    }

    function test_USDCBorrow() public {
        // First, someone needs to deposit USDC so the contract has liquidity to borrow from
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        // Alice needs to deposit collateral before borrowing (deposit ETH as collateral)
        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether); // 5 ETH as collateral

        // Mock Pyth data - need 3 price IDs to match 3 supported tokens
        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1)); // ETH price ID
        priceIds[1] = bytes32(uint256(2)); // USDC price ID
        priceIds[2] = bytes32(uint256(3)); // USDT price ID

        uint256 borrowAmount = 1 * USDC_DECIMALS; // Borrow just 1 USDC to stay within LTV limits

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        assertEq(mockUSDC.balanceOf(alice), 10000 * USDC_DECIMALS + borrowAmount);

        DepositManager.Asset memory config = depositManager.getAsset(USDC_TOKEN_ID);
        assertEq(config.totalBorrows, borrowAmount);
    }

    function test_RepayETH() public {
        uint256 borrowAmount = 0.1 ether; // $100 worth of ETH

        // Setup: Bob deposits ETH liquidity, Alice deposits USDC collateral and borrows ETH
        vm.prank(bob);
        depositManager.deposit{value: 2 ether}(ETH_TOKEN_ID, 2 ether);

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, 200 * USDC_DECIMALS); // $200 worth of USDC collateral

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        vm.prank(alice);
        borrowManager.borrow(ETH_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        uint256 aliceBalanceAfterBorrow = alice.balance;
        uint256 contractBalanceBeforeRepay = address(depositManager).balance;

        // Check initial borrow amount is recorded correctly
        assertEq(borrowManager.userBorrowScaled(ETH_TOKEN_ID, alice), borrowAmount);

        // Alice repays the ETH
        vm.prank(alice);
        borrowManager.repay{value: borrowAmount}(ETH_TOKEN_ID, borrowAmount);

        // Check balances
        assertEq(alice.balance, aliceBalanceAfterBorrow - borrowAmount);
        assertEq(address(depositManager).balance, contractBalanceBeforeRepay + borrowAmount);

        // Check borrow state is cleared
        assertEq(borrowManager.userBorrowScaled(ETH_TOKEN_ID, alice), 0);

        DepositManager.Asset memory config = depositManager.getAsset(ETH_TOKEN_ID);
        assertEq(config.totalBorrows, 0);
    }

    function test_RepayUSDC() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;

        // Setup: Bob deposits USDC liquidity, Alice deposits ETH collateral and borrows USDC
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        uint256 aliceBalanceAfterBorrow = mockUSDC.balanceOf(alice);
        uint256 contractBalanceBeforeRepay = mockUSDC.balanceOf(address(depositManager));

        // Check initial borrow amount is recorded correctly
        assertEq(borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice), borrowAmount);

        // Alice approves and repays the USDC
        vm.prank(alice);
        mockUSDC.approve(address(depositManager), borrowAmount);

        vm.prank(alice);
        borrowManager.repay(USDC_TOKEN_ID, borrowAmount);

        // Check balances
        assertEq(mockUSDC.balanceOf(alice), aliceBalanceAfterBorrow - borrowAmount);
        assertEq(mockUSDC.balanceOf(address(depositManager)), contractBalanceBeforeRepay + borrowAmount);

        // Check borrow state is cleared
        assertEq(borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice), 0);

        DepositManager.Asset memory config = depositManager.getAsset(USDC_TOKEN_ID);
        assertEq(config.totalBorrows, 0);
    }

    function test_PartialRepay() public {
        uint256 borrowAmount = 100 * USDC_DECIMALS;
        uint256 repayAmount = 50 * USDC_DECIMALS; // Partial repay (50 USDC)

        // Setup borrow
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        uint256 scaledBorrowAfterBorrow = borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice);

        // Partial repay
        vm.prank(alice);
        mockUSDC.approve(address(depositManager), repayAmount);

        vm.prank(alice);
        borrowManager.repay(USDC_TOKEN_ID, repayAmount);

        // Check that scaled borrow is reduced but not zero
        uint256 scaledBorrowAfterRepay = borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice);
        assertGt(scaledBorrowAfterRepay, 0);
        assertLt(scaledBorrowAfterRepay, scaledBorrowAfterBorrow);

        DepositManager.Asset memory config = depositManager.getAsset(USDC_TOKEN_ID);
        assertEq(config.totalBorrows, borrowAmount - repayAmount);
    }

    function test_RepayExceedsBorrow() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;
        uint256 repayAmount = 2 * USDC_DECIMALS; // Try to repay more than borrowed

        // Setup borrow
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        // Try to repay more than borrowed - should fail
        vm.prank(alice);
        mockUSDC.approve(address(depositManager), repayAmount);

        vm.prank(alice);
        vm.expectRevert("Repay exceeds borrow");
        borrowManager.repay(USDC_TOKEN_ID, repayAmount);
    }

    function test_BorrowInsufficientCollateral() public {
        uint256 borrowAmount = 1000 * USDC_DECIMALS; // Very large borrow amount

        // Setup liquidity
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        // Alice deposits small collateral
        vm.prank(alice);
        depositManager.deposit{value: 0.1 ether}(ETH_TOKEN_ID, 0.1 ether); // Very small collateral

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        // Should fail due to insufficient collateral
        vm.prank(alice);
        vm.expectRevert("Insufficient collateral");
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);
    }

    function test_BorrowNoCollateral() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;

        // Setup liquidity but Alice has no collateral
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        // Should fail due to no collateral
        vm.prank(alice);
        vm.expectRevert("No collateral");
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);
    }

    function test_BorrowMismatchedPriceIds() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;

        // Setup
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](2); // Wrong number of price IDs
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));

        // Should fail due to mismatched tokens/prices
        vm.prank(alice);
        vm.expectRevert("Mismatched tokens/prices");
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);
    }

    function test_BorrowNegativePrice() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;

        // Setup
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        // Mock negative price for one of the tokens
        bytes memory negativePriceData = abi.encode(
            int64(-100000000), // Negative price
            uint64(0),
            int32(-8),
            uint256(block.timestamp)
        );
        vm.mockCall(
            mockPyth,
            abi.encodeWithSignature("getPriceNoOlderThan(bytes32,uint256)", bytes32(uint256(1)), uint256(300)),
            negativePriceData
        );

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        // Should fail due to negative price
        vm.prank(alice);
        vm.expectRevert("Negative price");
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);
    }

    function test_BorrowUSDTToken() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS; // USDT has same decimals as USDC

        // Setup: Bob deposits USDT liquidity, Alice deposits ETH collateral
        vm.prank(bob);
        depositManager.deposit(USDT_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        uint256 aliceBalanceBefore = mockUSDT.balanceOf(alice);

        vm.prank(alice);
        borrowManager.borrow(USDT_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        assertEq(mockUSDT.balanceOf(alice), aliceBalanceBefore + borrowAmount);

        DepositManager.Asset memory config = depositManager.getAsset(USDT_TOKEN_ID);
        assertEq(config.totalBorrows, borrowAmount);
    }

    function test_MultipleBorrowsSameUser() public {
        // Alice borrows from multiple tokens

        // Setup liquidity
        vm.prank(bob);
        depositManager.deposit{value: 10 ether}(ETH_TOKEN_ID, 10 ether);
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 5000 * USDC_DECIMALS);
        vm.prank(bob);
        depositManager.deposit(USDT_TOKEN_ID, 5000 * USDC_DECIMALS);

        // Alice deposits large collateral - need more for multiple borrows
        vm.prank(alice);
        depositManager.deposit{value: 100 ether}(ETH_TOKEN_ID, 100 ether); // Increased collateral

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        // Borrow smaller amounts to stay within LTV
        vm.prank(alice);
        borrowManager.borrow(
            USDC_TOKEN_ID,
            10 * USDC_DECIMALS, // Reduced from 100
            emptyPythData,
            priceIds
        );

        // Borrow USDT
        vm.prank(alice);
        borrowManager.borrow(
            USDT_TOKEN_ID,
            5 * USDC_DECIMALS, // Reduced from 50
            emptyPythData,
            priceIds
        );

        // Check both borrows are recorded
        assertGt(borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice), 0);
        assertGt(borrowManager.userBorrowScaled(USDT_TOKEN_ID, alice), 0);

        DepositManager.Asset memory usdcConfig = depositManager.getAsset(USDC_TOKEN_ID);
        assertEq(usdcConfig.totalBorrows, 10 * USDC_DECIMALS);

        DepositManager.Asset memory usdtConfig = depositManager.getAsset(USDT_TOKEN_ID);
        assertEq(usdtConfig.totalBorrows, 5 * USDC_DECIMALS);
    }

    function test_BorrowEvent() public {
        uint256 borrowAmount = 100 * USDC_DECIMALS;

        // Setup
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        // Expected collateral value: 5 ETH * $1000 = $5,000 (normalized: (5 ether * 1e11) / 1e8 = 5e21)
        uint256 expectedCollateralValue = (5 ether * 100000000000) / 1e8; // = 5 * 10^21

        // Expect the Borrowed event
        vm.expectEmit(true, true, false, true);
        emit BorrowManager.Borrowed(USDC_TOKEN_ID, alice, borrowAmount, expectedCollateralValue);

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);
    }

    function test_RepayEvent() public {
        uint256 borrowAmount = 100 * USDC_DECIMALS;

        // Setup borrow first
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        // Now test repay event
        vm.prank(alice);
        mockUSDC.approve(address(depositManager), borrowAmount);

        // Expect the Repaid event
        vm.expectEmit(true, true, false, true);
        emit BorrowManager.Repaid(USDC_TOKEN_ID, alice, borrowAmount);

        vm.prank(alice);
        borrowManager.repay(USDC_TOKEN_ID, borrowAmount);
    }

    function test_BorrowIndexInitialization() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;

        // Setup
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        // Check initial borrow index is 0
        assertEq(borrowManager.borrowIndex(USDC_TOKEN_ID), 0);

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        // After first borrow, index should be initialized to RAY
        assertEq(borrowManager.borrowIndex(USDC_TOKEN_ID), RAY);
    }

    function test_BorrowIndexAccrual() public {
        uint256 borrowAmount = 20 * USDC_DECIMALS; // Further reduced to stay within 50% LTV

        // Setup with higher utilization for significant interest
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 200 * USDC_DECIMALS); // 200 USDC liquidity

        vm.prank(alice);
        depositManager.deposit{value: 50 ether}(ETH_TOKEN_ID, 50 ether); // ETH collateral

        // Also add USDC collateral to increase total collateral value
        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, 1000 * USDC_DECIMALS); // USDC collateral

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        uint256 initialBorrowIndex = borrowManager.borrowIndex(USDC_TOKEN_ID);
        assertEq(initialBorrowIndex, RAY);

        // Advance time by 1 year
        vm.warp(block.timestamp + YEAR);

        // Trigger borrow index update by making another small borrow
        vm.prank(alice);
        borrowManager.borrow(
            USDC_TOKEN_ID,
            USDC_DECIMALS / 10, // 0.1 USDC - very small amount
            emptyPythData,
            priceIds
        );

        uint256 finalBorrowIndex = borrowManager.borrowIndex(USDC_TOKEN_ID);

        // Borrow index should have increased due to interest accrual
        assertGt(finalBorrowIndex, initialBorrowIndex, "Borrow index should increase over time");
        assertEq(initialBorrowIndex, 10000000000000000000 * 1e8);
        assertEq(finalBorrowIndex, 1021249999999999999950000000);
        console.log("Interest accrued factor:", (finalBorrowIndex * 1e18) / initialBorrowIndex);
    }

    function test_InterestAccrualOnRepay() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;

        // Setup
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);
        uint256 initialScaledBorrow = borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice);

        // Advance time
        vm.warp(block.timestamp + (YEAR / 4)); // 3 months

        // Calculate expected amount owed (should be more than initial borrow due to interest)
        uint256 expectedAmountOwed = (initialScaledBorrow * borrowManager.borrowIndex(USDC_TOKEN_ID)) / RAY;

        // Alice needs to approve more than the original borrow amount to cover interest
        vm.prank(alice);
        mockUSDC.approve(address(depositManager), expectedAmountOwed);

        // Repay should work with the accrued amount
        vm.prank(alice);
        borrowManager.repay(USDC_TOKEN_ID, borrowAmount); // Repay original amount

        // Check that scaled borrow is reduced appropriately
        uint256 finalScaledBorrow = borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice);

        assertLt(finalScaledBorrow, initialScaledBorrow);
        assertEq(initialScaledBorrow, 1000000);
        assertEq(finalScaledBorrow, 4985);
    }

    function test_ScaledBorrowCalculation() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;

        // Setup
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        uint256 borrowIndex = borrowManager.borrowIndex(USDC_TOKEN_ID);
        uint256 scaledBorrow = borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice);

        // Verify that scaled borrow * index = actual borrow amount
        uint256 actualBorrowAmount = (scaledBorrow * borrowIndex) / RAY;
        assertEq(actualBorrowAmount, borrowAmount, "Scaled borrow calculation should be correct");

        // Verify expected scaled amount
        uint256 expectedScaled = (borrowAmount * RAY) / borrowIndex;
        assertEq(scaledBorrow, expectedScaled, "Scaled borrow should match expected calculation");
    }

    function test_ZeroBorrowAmount() public {
        // Setup
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        // Try to borrow 0 amount
        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, 0, emptyPythData, priceIds);

        // Should succeed but with no effect
        assertEq(borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice), 0);

        DepositManager.Asset memory config = depositManager.getAsset(USDC_TOKEN_ID);
        assertEq(config.totalBorrows, 0);
    }

    function test_ZeroRepayAmount() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;

        // Setup borrow first
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        uint256 initialScaledBorrow = borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice);

        // Try to repay 0 amount
        vm.prank(alice);
        borrowManager.repay(USDC_TOKEN_ID, 0);

        // Should succeed but with no effect
        assertEq(borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice), initialScaledBorrow);
    }
}
