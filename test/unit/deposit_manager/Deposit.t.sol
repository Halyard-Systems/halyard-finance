// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DepositManager} from "../../../src/DepositManager.sol";

import {BaseTest} from "../BaseTest.t.sol";

contract DepositTest is BaseTest {
    function test_ETHDeposit() public {
        uint256 depositAmount = 1 ether;
        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        depositManager.deposit{value: depositAmount}(ETH_TOKEN_ID, depositAmount);

        assertEq(depositManager.balanceOf(ETH_TOKEN_ID, alice), depositAmount);
        assertEq(alice.balance, aliceBalanceBefore - depositAmount);

        DepositManager.Asset memory config = depositManager.getAsset(ETH_TOKEN_ID);
        assertEq(config.totalDeposits, depositAmount);
    }

    function test_USDCDeposit() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);

        assertEq(depositManager.balanceOf(USDC_TOKEN_ID, alice), depositAmount);

        DepositManager.Asset memory config = depositManager.getAsset(USDC_TOKEN_ID);
        assertEq(config.totalDeposits, depositAmount);
    }

    function test_USDTDeposit() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDT_TOKEN_ID, depositAmount);

        assertEq(depositManager.balanceOf(USDT_TOKEN_ID, alice), depositAmount);

        DepositManager.Asset memory config = depositManager.getAsset(USDT_TOKEN_ID);
        assertEq(config.totalDeposits, depositAmount);
    }

    function test_DepositZeroAmount() public {
        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, 0);

        assertEq(depositManager.balanceOf(USDC_TOKEN_ID, alice), 0);

        DepositManager.Asset memory config = depositManager.getAsset(USDC_TOKEN_ID);
        assertEq(config.totalDeposits, 0);
    }

    function test_DepositInsufficientAllowance() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        // Revoke allowance
        vm.prank(alice);
        mockUSDC.approve(address(depositManager), 0);

        vm.prank(alice);
        vm.expectRevert();
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);
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
        vm.expectRevert();
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);
    }

    function test_ETHDepositInsufficientValue() public {
        uint256 depositAmount = 1 ether;

        vm.prank(alice);
        vm.expectRevert("ETH amount mismatch");
        depositManager.deposit{value: 0.5 ether}(ETH_TOKEN_ID, depositAmount);
    }

    function test_ERC20DepositWithETHValue() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        vm.expectRevert("ETH not accepted for ERC20 deposits");
        depositManager.deposit{value: 1 ether}(USDC_TOKEN_ID, depositAmount);
    }

    function test_MultipleUserDeposits() public {
        uint256 aliceDeposit = 1000 * USDC_DECIMALS;
        uint256 bobDeposit = 500 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, aliceDeposit);

        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, bobDeposit);

        assertEq(depositManager.balanceOf(USDC_TOKEN_ID, alice), aliceDeposit);
        assertEq(depositManager.balanceOf(USDC_TOKEN_ID, bob), bobDeposit);

        DepositManager.Asset memory config = depositManager.getAsset(USDC_TOKEN_ID);
        assertEq(config.totalDeposits, aliceDeposit + bobDeposit);
    }

    function test_MultipleTokenDeposits() public {
        // Deposit different tokens
        vm.prank(alice);
        depositManager.deposit{value: 1 ether}(ETH_TOKEN_ID, 1 ether);

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, 1000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit(USDT_TOKEN_ID, 1000 * USDC_DECIMALS);

        // Check balances
        assertEq(depositManager.balanceOf(ETH_TOKEN_ID, alice), 1 ether);
        assertEq(depositManager.balanceOf(USDC_TOKEN_ID, alice), 1000 * USDC_DECIMALS);
        assertEq(depositManager.balanceOf(USDT_TOKEN_ID, alice), 1000 * USDC_DECIMALS);

        // Check total deposits for each token
        DepositManager.Asset memory ethConfig = depositManager.getAsset(ETH_TOKEN_ID);
        DepositManager.Asset memory usdcConfig = depositManager.getAsset(USDC_TOKEN_ID);
        DepositManager.Asset memory usdtConfig = depositManager.getAsset(USDT_TOKEN_ID);

        assertEq(ethConfig.totalDeposits, 1 ether);
        assertEq(usdcConfig.totalDeposits, 1000 * USDC_DECIMALS);
        assertEq(usdtConfig.totalDeposits, 1000 * USDC_DECIMALS);
    }

    function test_TokenNotSupported() public {
        bytes32 invalidTokenId = keccak256(abi.encodePacked("INVALID"));

        vm.prank(alice);
        vm.expectRevert();
        depositManager.deposit(invalidTokenId, 1000 * USDC_DECIMALS);
    }
}
