// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BaseTest} from "../../BaseTest.t.sol";
import {IAccessManaged} from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import {DebtManager} from "../../../src/hub/DebtManager.sol";
import {IAssetRegistryDebtRates} from "../../../src/hub/DebtManager.sol";

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
