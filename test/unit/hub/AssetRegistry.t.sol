// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BaseTest} from "../../BaseTest.t.sol";
import {IAccessManaged} from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import {AssetRegistry} from "../../../src/hub/AssetRegistry.sol";

import {console} from "forge-std/console.sol";

contract AssetRegistryTest is BaseTest {
    function test_SetCollateralConfig() public {
        AssetRegistry.CollateralConfig memory config = AssetRegistry.CollateralConfig({
            isSupported: true, ltvBps: 8000, liqThresholdBps: 8500, liqBonusBps: 500, decimals: 18, supplyCap: 0
        });

        vm.prank(admin);
        assetRegistry.setCollateralConfig(1, address(0x123), config);

        AssetRegistry.CollateralConfig memory result = assetRegistry.collateralConfig(1, address(0x123));
        assertEq(result.ltvBps, 8000);
        assertEq(result.liqThresholdBps, 8500);
        assertEq(result.liqBonusBps, 500);
        assertEq(result.decimals, 18);
        assertEq(result.supplyCap, 0);
    }

    function test_SetCollateralConfig_OnlyRestricted() public {
        AssetRegistry.CollateralConfig memory config = AssetRegistry.CollateralConfig({
            isSupported: true, ltvBps: 8000, liqThresholdBps: 8500, liqBonusBps: 500, decimals: 18, supplyCap: 0
        });

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        assetRegistry.setCollateralConfig(1, address(0x123), config);
    }

    function test_DisableCollateral() public {
        // First set a config
        AssetRegistry.CollateralConfig memory config = AssetRegistry.CollateralConfig({
            isSupported: true, ltvBps: 8000, liqThresholdBps: 8500, liqBonusBps: 500, decimals: 18, supplyCap: 0
        });
        vm.startPrank(admin);
        assetRegistry.setCollateralConfig(1, address(0x123), config);
        // Now disable it

        assetRegistry.disableCollateral(1, address(0x123));
        vm.stopPrank();
        assertEq(assetRegistry.collateralConfig(1, address(0x123)).isSupported, false);
    }

    function test_DisableCollateral_OnlyRestricted() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        assetRegistry.disableCollateral(1, address(0x123));
    }

    function test_SetDebtConfig() public {
        AssetRegistry.DebtConfig memory config =
            AssetRegistry.DebtConfig({isSupported: true, decimals: 18, borrowCap: 0});

        vm.prank(admin);
        assetRegistry.setDebtConfig(1, address(0x123), config);

        AssetRegistry.DebtConfig memory result = assetRegistry.debtConfig(1, address(0x123));
        assertEq(result.isSupported, true);
        assertEq(result.decimals, 18);
        assertEq(result.borrowCap, 0);
    }

    function test_SetDebtConfig_OnlyRestricted() public {
        AssetRegistry.DebtConfig memory config =
            AssetRegistry.DebtConfig({isSupported: true, decimals: 18, borrowCap: 0});
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        assetRegistry.setDebtConfig(1, address(0x123), config);
    }

    function test_DisableDebt() public {
        AssetRegistry.DebtConfig memory config =
            AssetRegistry.DebtConfig({isSupported: true, decimals: 18, borrowCap: 0});

        vm.startPrank(admin);
        assetRegistry.setDebtConfig(1, address(0x123), config);
        assetRegistry.disableDebt(1, address(0x123));
        vm.stopPrank();
        assertEq(assetRegistry.debtConfig(1, address(0x123)).isSupported, false);
    }

    function test_DisableDebt_OnlyRestricted() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        assetRegistry.disableDebt(1, address(0x123));
    }

    function test_SetBorrowRateApr() public {
        vm.prank(admin);
        assetRegistry.setBorrowRateApr(1, address(0x123), 1000);
        assertEq(assetRegistry.borrowRatePerSecondRay(1, address(0x123)), 3170979198376458650);
    }

    function test_SetBorrowRateApr_OnlyRestricted() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        assetRegistry.setBorrowRateApr(1, address(0x123), 1000);
    }
}
