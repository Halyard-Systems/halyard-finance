// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BaseTest} from "../../BaseTest.t.sol";
import {LiquidityVault} from "../../../src/spoke/LiquidityVault.sol";

contract LiquidityVaultTest is BaseTest {
    function test_SetController() public {
        vm.prank(admin);
        liquidityVault.setController(address(spokeController));
        assertEq(liquidityVault.controller(), address(spokeController));
    }

    function test_SetController_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        liquidityVault.setController(address(spokeController));
    }

    function test_SetPaused() public {
        vm.prank(admin);
        liquidityVault.setPaused(true);
        assertTrue(liquidityVault.paused());
    }

    function test_SetPaused_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        liquidityVault.setPaused(true);
    }

    function test_SetUseAllowlist() public {
        vm.prank(admin);
        liquidityVault.setUseAllowlist(true);
        assertTrue(liquidityVault.useAllowlist());
    }

    function test_SetUseAllowlist_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        liquidityVault.setUseAllowlist(true);
    }

    function test_SetAssetAllowed() public {
        vm.prank(admin);
        liquidityVault.setAssetAllowed(address(mockToken), true);
        assertTrue(liquidityVault.isAssetAllowed(address(mockToken)));
    }

    function test_SetAssetAllowed_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        liquidityVault.setAssetAllowed(address(mockToken), true);
        assertFalse(liquidityVault.isAssetAllowed(address(mockToken)));
    }

    function test_AddLiquiditySuccess() public {
        vm.startPrank(alice);
        mockToken.approve(address(liquidityVault), 100);
        liquidityVault.addLiquidity(address(mockToken), 100);
        vm.stopPrank();
        assertEq(mockToken.balanceOf(address(liquidityVault)), 100);
    }

    function test_AddLiquidity_Paused() public {
        vm.prank(admin);
        liquidityVault.setPaused(true);
        vm.startPrank(alice);
        mockToken.approve(address(liquidityVault), 100);
        vm.expectRevert(abi.encodeWithSelector(LiquidityVault.Paused.selector));
        liquidityVault.addLiquidity(address(mockToken), 100);
        vm.stopPrank();
        assertEq(mockToken.balanceOf(address(liquidityVault)), 0);
    }

    function test_AddLiquidity_InvalidAddress() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(LiquidityVault.InvalidAddress.selector));
        liquidityVault.addLiquidity(address(0), 100);
        vm.stopPrank();
        assertEq(mockToken.balanceOf(address(liquidityVault)), 0);
    }

    function test_AddLiquidity_InvalidAmount() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(LiquidityVault.InvalidAmount.selector));
        liquidityVault.addLiquidity(address(mockToken), 0);
        vm.stopPrank();
        assertEq(mockToken.balanceOf(address(liquidityVault)), 0);
    }

    function test_AddLiquidity_InvalidAllowlist() public {
        vm.startPrank(admin);
        liquidityVault.setUseAllowlist(true);
        liquidityVault.setAssetAllowed(address(mockToken), false);
        vm.stopPrank();

        vm.startPrank(alice);
        mockToken.approve(address(liquidityVault), 100);
        vm.expectRevert(abi.encodeWithSelector(LiquidityVault.InvalidAddress.selector));
        liquidityVault.addLiquidity(address(mockToken), 100);
        vm.stopPrank();
        assertEq(mockToken.balanceOf(address(liquidityVault)), 0);
    }

    function test_RemoveLiquiditySuccess() public {
        uint256 aliceBalanceBefore = mockToken.balanceOf(alice);

        vm.startPrank(alice);
        mockToken.approve(address(liquidityVault), 100);
        liquidityVault.addLiquidity(address(mockToken), 100);
        vm.stopPrank();

        vm.prank(admin);
        liquidityVault.removeLiquidity(address(mockToken), alice, 70);

        assertEq(mockToken.balanceOf(address(liquidityVault)), 30);
        assertEq(mockToken.balanceOf(alice), aliceBalanceBefore - 30);
    }

    function test_RemoveLiquidity_Paused() public {
        vm.prank(admin);
        liquidityVault.setPaused(true);
        vm.prank(alice);
        mockToken.approve(address(liquidityVault), 100);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(LiquidityVault.Paused.selector));
        liquidityVault.removeLiquidity(address(mockToken), alice, 70);
    }

    function test_RemoveLiquidity_InvalidAddress() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(LiquidityVault.InvalidAddress.selector));
        liquidityVault.removeLiquidity(address(0), alice, 70);
    }

    function test_RemoveLiquidity_InvalidAmount() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(LiquidityVault.InvalidAmount.selector));
        liquidityVault.removeLiquidity(address(mockToken), alice, 0);
    }

    function test_RemoveLiquidity_InvalidAllowlist() public {
        vm.startPrank(admin);
        liquidityVault.setUseAllowlist(true);
        liquidityVault.setAssetAllowed(address(mockToken), false);
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(LiquidityVault.InvalidAddress.selector));
        liquidityVault.removeLiquidity(address(mockToken), alice, 70);
    }

    function test_ReleaseBorrowSuccess() public {
        vm.startPrank(alice);
        mockToken.approve(address(liquidityVault), 100);
        liquidityVault.addLiquidity(address(mockToken), 100);
        vm.stopPrank();

        uint256 aliceBalanceBefore = mockToken.balanceOf(alice);
        bytes32 borrowId = keccak256("borrowId");
        uint256 amount = 70;

        vm.prank(address(spokeController));
        liquidityVault.releaseBorrow(borrowId, alice, alice, address(mockToken), amount);

        assertEq(mockToken.balanceOf(alice), aliceBalanceBefore + amount);
        assertEq(mockToken.balanceOf(address(liquidityVault)), 30);
    }

    function test_ReleaseBorrow_InvalidAddress() public {
        vm.startPrank(alice);
        mockToken.approve(address(liquidityVault), 100);
        liquidityVault.addLiquidity(address(mockToken), 100);
        vm.stopPrank();

        bytes32 borrowId = keccak256("borrowId");

        vm.expectRevert(abi.encodeWithSelector(LiquidityVault.InvalidAddress.selector));
        vm.prank(address(spokeController));
        liquidityVault.releaseBorrow(borrowId, alice, alice, address(0), 70);

        assertEq(mockToken.balanceOf(address(liquidityVault)), 100);
    }

    function test_ReleaseBorrow_InvalidAmount() public {
        vm.startPrank(alice);
        mockToken.approve(address(liquidityVault), 100);
        liquidityVault.addLiquidity(address(mockToken), 100);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(LiquidityVault.InvalidAmount.selector));
        vm.prank(address(spokeController));
        liquidityVault.releaseBorrow(keccak256("borrowId"), alice, alice, address(mockToken), 0);

        assertEq(mockToken.balanceOf(address(liquidityVault)), 100);
    }

    function test_ReleaseBorrow_InvalidAllowlist() public {
        vm.startPrank(alice);
        mockToken.approve(address(liquidityVault), 100);
        liquidityVault.addLiquidity(address(mockToken), 100);
        vm.stopPrank();

        vm.startPrank(admin);
        liquidityVault.setUseAllowlist(true);
        liquidityVault.setAssetAllowed(address(mockToken), false);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(LiquidityVault.InvalidAddress.selector));
        vm.prank(address(spokeController));
        liquidityVault.releaseBorrow(keccak256("borrowId"), alice, alice, address(mockToken), 70);

        assertEq(mockToken.balanceOf(address(liquidityVault)), 100);
    }

    function test_RepaySuccess() public {
        uint256 aliceBalanceBefore = mockToken.balanceOf(alice);

        vm.startPrank(alice);
        mockToken.approve(address(liquidityVault), 100);
        bytes32 repayId = keccak256("repayId");
        liquidityVault.repay(repayId, address(mockToken), 70, alice);
        vm.stopPrank();

        assertEq(mockToken.balanceOf(address(liquidityVault)), 70);
        assertEq(mockToken.balanceOf(alice), aliceBalanceBefore - 70);
    }

    function test_Repay_InvalidAddress() public {
        uint256 aliceBalanceBefore = mockToken.balanceOf(alice);

        vm.startPrank(alice);
        mockToken.approve(address(liquidityVault), 100);
        vm.expectRevert(abi.encodeWithSelector(LiquidityVault.InvalidAddress.selector));
        liquidityVault.repay(keccak256("repayId"), address(0), 70, alice);
        vm.stopPrank();

        assertEq(mockToken.balanceOf(alice), aliceBalanceBefore);
        assertEq(mockToken.balanceOf(address(liquidityVault)), 0);
    }

    function test_Repay_InvalidAmount() public {
        uint256 aliceBalanceBefore = mockToken.balanceOf(alice);

        vm.startPrank(alice);
        mockToken.approve(address(liquidityVault), 100);
        vm.expectRevert(abi.encodeWithSelector(LiquidityVault.InvalidAmount.selector));
        liquidityVault.repay(keccak256("repayId"), address(mockToken), 0, alice);
        vm.stopPrank();

        assertEq(mockToken.balanceOf(alice), aliceBalanceBefore);
        assertEq(mockToken.balanceOf(address(liquidityVault)), 0);
    }

    function test_Repay_InvalidAllowlist() public {
        uint256 aliceBalanceBefore = mockToken.balanceOf(alice);

        vm.startPrank(admin);
        liquidityVault.setUseAllowlist(true);
        liquidityVault.setAssetAllowed(address(mockToken), false);
        vm.stopPrank();

        vm.startPrank(alice);
        mockToken.approve(address(liquidityVault), 100);
        vm.expectRevert(abi.encodeWithSelector(LiquidityVault.InvalidAddress.selector));
        liquidityVault.repay(keccak256("repayId"), address(mockToken), 70, alice);
        vm.stopPrank();

        assertEq(mockToken.balanceOf(alice), aliceBalanceBefore);
        assertEq(mockToken.balanceOf(address(liquidityVault)), 0);
    }

    function test_RescueERC20Success() public {
        vm.startPrank(alice);
        mockToken.approve(address(liquidityVault), 100);
        liquidityVault.addLiquidity(address(mockToken), 100);
        vm.stopPrank();

        uint256 aliceBalanceBefore = mockToken.balanceOf(alice);
        uint256 liquidityVaultBalanceBefore = mockToken.balanceOf(address(liquidityVault));

        vm.prank(admin);
        liquidityVault.rescueERC20(address(mockToken), alice, 70);

        assertEq(mockToken.balanceOf(address(alice)), aliceBalanceBefore + 70);
        assertEq(mockToken.balanceOf(address(liquidityVault)), liquidityVaultBalanceBefore - 70);
    }

    function test_RescueERC20_InvalidAddress() public {
        uint256 aliceBalanceBefore = mockToken.balanceOf(alice);
        uint256 liquidityVaultBalanceBefore = mockToken.balanceOf(address(liquidityVault));

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(LiquidityVault.InvalidAddress.selector));
        liquidityVault.rescueERC20(address(0), alice, 70);

        assertEq(mockToken.balanceOf(alice), aliceBalanceBefore);
        assertEq(mockToken.balanceOf(address(liquidityVault)), liquidityVaultBalanceBefore);
    }

    function test_RescueERC20_InvalidAmount() public {
        uint256 aliceBalanceBefore = mockToken.balanceOf(alice);
        uint256 liquidityVaultBalanceBefore = mockToken.balanceOf(address(liquidityVault));

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(LiquidityVault.InvalidAmount.selector));
        liquidityVault.rescueERC20(address(mockToken), alice, 0);

        assertEq(mockToken.balanceOf(alice), aliceBalanceBefore);
        assertEq(mockToken.balanceOf(address(liquidityVault)), liquidityVaultBalanceBefore);
    }
}
