// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseTest} from "./BaseTest.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {console} from "forge-std/console.sol";

contract HubControllerTest is BaseTest {
    function test_SetPaused() public {
        hubController.setPaused(true);
        assertTrue(hubController.paused());
    }

    function test_SetPaused_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        hubController.setPaused(true);
        assertFalse(hubController.paused());
    }

    function test_SetSpoke() public {
        bytes32 spokeAddr = bytes32(uint256(uint160(alice))); // Convert address to bytes32
        hubController.setSpoke(1, spokeAddr);
        assertEq(hubController.getSpoke(1), spokeAddr);
    }

    function test_SetSpoke_OnlyOwner() public {
        bytes32 spokeAddr = bytes32(uint256(uint160(alice)));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        hubController.setSpoke(1, spokeAddr);
    }

    function test_RemoveSpoke() public {
        bytes32 spokeAddr = bytes32(uint256(uint160(alice)));
        hubController.setSpoke(1, spokeAddr);
        hubController.removeSpoke(1);
        assertEq(hubController.getSpoke(1), bytes32(0));
    }

    function test_RemoveSpoke_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        hubController.removeSpoke(1);
    }

    function test_GetSpoke() public {
        bytes32 spokeAddr = bytes32(uint256(uint160(alice)));
        hubController.setSpoke(1, spokeAddr);
        assertEq(hubController.getSpoke(1), spokeAddr);
    }

    function test_GetSpokeEids() public {
        bytes32 spokeAddr = bytes32(uint256(uint160(alice)));
        hubController.setSpoke(1, spokeAddr);
        hubController.setSpoke(2, spokeAddr);

        uint32[] memory eids = hubController.getSpokeEids();
        assertEq(eids.length, 2);
        assertEq(eids[0], 1);
        assertEq(eids[1], 2);
    }
}
