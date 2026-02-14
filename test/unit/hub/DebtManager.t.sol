// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../../BaseTest.t.sol";
import {IAccessManaged} from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";

contract DebtManagerTest is BaseTest {
    function test_setAssetRegistry() public {
        vm.prank(admin);
        debtManager.setAssetRegistry(address(assetRegistry));
    }

    function test_setAssetRegistry_OnlyRestricted() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        debtManager.setAssetRegistry(address(assetRegistry));
    }
}
