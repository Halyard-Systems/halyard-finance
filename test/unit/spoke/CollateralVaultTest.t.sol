// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BaseSpokeTest} from "./BaseSpokeTest.t.sol";

contract CollateralVaultTest is BaseSpokeTest {
    function test_SetController() public {
        collateralVault.setController(address(spokeController));
        assertEq(collateralVault.controller(), address(spokeController));
    }

    function test_SetController_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        collateralVault.setController(address(spokeController));
    }

    function test_SetPaused() public {
        collateralVault.setPaused(true);
        assertTrue(collateralVault.paused());
    }

    function test_SetPaused_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        collateralVault.setPaused(true);
    }

    function test_SetUseAllowlist() public {
        collateralVault.setUseAllowlist(true);
        assertTrue(collateralVault.useAllowlist());
    }

    function test_SetUseAllowlist_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        collateralVault.setUseAllowlist(true);
    }

    function test_SetAssetAllowed() public {
        collateralVault.setAssetAllowed(address(mockToken), true);
        assertTrue(collateralVault.isAssetAllowed(address(mockToken)));
    }

    function test_SetAssetAllowed_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        collateralVault.setAssetAllowed(address(mockToken), true);
    }

    function test_DepositSuccess() public {
        vm.prank(address(spokeController));
        collateralVault.deposit(address(mockToken), 100, alice);
        assertEq(collateralVault.lockedBalanceOf(alice, address(mockToken)), 100);
    }
}
