// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseTest} from "./BaseTest.t.sol";
import {PositionBook} from "../../src/hub/PositionBook.sol";

import {console} from "forge-std/console.sol";

contract PositionBookTest is BaseTest {
    function test_CollateralOf() public {
        vm.prank(address(hubController));
        positionBook.creditCollateral(alice, 1, address(0x123), 100);
        assertEq(positionBook.collateralOf(alice, 1, address(0x123)), 100);
    }

    // function test_ReservedCollateralOf() public {
    //     vm.prank(riskEngine);
    //     positionBook.reserveCollateral(alice, 1, address(0x123), 100);
    //     assertEq(positionBook.reservedCollateralOf(alice, 1, address(0x123)), 100);
    // }

    // function test_ReservedCollateralOf_InvalidAddress() public {
    //     vm.expectRevert(PositionBook.InvalidAddress.selector);
    //     positionBook.reservedCollateralOf(address(0), 1, address(0x123));
    // }

    // function test_ReservedCollateralOf_InvalidEid() public {
    //     vm.expectRevert(PositionBook.InvalidEid.selector);
    //     positionBook.reservedCollateralOf(alice, 0, address(0x123));
    // }

    // function test_ReservedCollateralOf_InvalidAmount() public {
    //     vm.expectRevert(PositionBook.InvalidAmount.selector);
    //     positionBook.reservedCollateralOf(alice, 1, address(0x123), 0);
    // }

    // function test_AvailableCollateralOf() public {
    //     vm.prank(hubAccessManager.ROLE_HUB_CONTROLLER());
    //     positionBook.creditCollateral(alice, 1, address(0x123), 100);
    //     vm.prank(hubAccessManager.ROLE_RISK_ENGINE());
    //     positionBook.reserveCollateral(alice, 1, address(0x123), 50);
    //     assertEq(positionBook.availableCollateralOf(alice, 1, address(0x123)), 50);
    // }

    // function test_AvailableCollateralOf_InvalidAddress() public {
    //     vm.expectRevert(PositionBook.InvalidAddress.selector);
    //     positionBook.availableCollateralOf(address(0), 1, address(0x123));
    // }

    // function test_AvailableCollateralOf_InvalidEid() public {
    //     vm.expectRevert(PositionBook.InvalidEid.selector);
    //     positionBook.availableCollateralOf(alice, 0, address(0x123));
    // }

    // function test_AvailableCollateralOf_InvalidAmount() public {
    //     vm.expectRevert(PositionBook.InvalidAmount.selector);
    //     positionBook.availableCollateralOf(alice, 1, address(0x123), 0);
    // }
}
