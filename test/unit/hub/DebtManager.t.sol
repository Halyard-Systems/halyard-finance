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

    // ---------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------

    function _mockOracle() internal {
        vm.mockCall(mockOracle, abi.encodeWithSignature("getPriceE18(address)"), abi.encode(1000e18, block.timestamp));
    }

    function _mintDebt(address user, uint32 eid, address asset, uint256 amount) internal {
        vm.prank(address(hubRouter));
        debtManager.mintDebt(user, eid, asset, amount);
    }

    // ---------------------------------------------------------------
    // Debt asset tracking lifecycle
    // ---------------------------------------------------------------

    function test_TracksDebtAssets() public {
        _mockOracle();

        assertEq(debtManager.debtAssetsOf(alice).length, 0);

        _mintDebt(alice, 1, address(0x123), 50e18);
        assertEq(debtManager.debtAssetsOf(alice).length, 1);
        assertEq(debtManager.debtAssetsOf(alice)[0].eid, 1);
        assertEq(debtManager.debtAssetsOf(alice)[0].asset, address(0x123));

        // Mint more of same — should NOT duplicate
        _mintDebt(alice, 1, address(0x123), 25e18);
        assertEq(debtManager.debtAssetsOf(alice).length, 1);

        // Mint different asset
        _mintDebt(alice, 2, address(0x124), 30e18);
        assertEq(debtManager.debtAssetsOf(alice).length, 2);
    }

    function test_RemovesDebtAssetOnFullRepay() public {
        _mockOracle();

        _mintDebt(alice, 1, address(0x123), 50e18);
        assertEq(debtManager.debtAssetsOf(alice).length, 1);

        vm.prank(address(hubRouter));
        debtManager.burnDebt(alice, 1, address(0x123), 50e18);
        assertEq(debtManager.debtAssetsOf(alice).length, 0);
    }

    function test_KeepsDebtAssetOnPartialRepay() public {
        _mockOracle();

        _mintDebt(alice, 1, address(0x123), 50e18);
        assertEq(debtManager.debtAssetsOf(alice).length, 1);

        vm.prank(address(hubRouter));
        debtManager.burnDebt(alice, 1, address(0x123), 25e18);
        assertEq(debtManager.debtAssetsOf(alice).length, 1);
    }
}
