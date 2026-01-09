// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseTest} from "./BaseTest.t.sol";
import {IAccessManaged} from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import {LiquidationEngine} from "../../src/hub/LiquidationEngine.sol";

contract LiquidationEngineTest is BaseTest {
    function test_setCollateralConfig() public {
        liquidationEngine.setCollateralConfig(
            1,
            address(0x123),
            LiquidationEngine.CollateralConfig({
                isSupported: true, ltvBps: 8000, liqThresholdBps: 8500, liqBonusBps: 500, decimals: 18, supplyCap: 0
            })
        );
    }

    function test_setCollateralConfig_OnlyRestricted() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        liquidationEngine.setCollateralConfig(
            1,
            address(0x123),
            LiquidationEngine.CollateralConfig({
                isSupported: true, ltvBps: 8000, liqThresholdBps: 8500, liqBonusBps: 500, decimals: 18, supplyCap: 0
            })
        );
    }

    function test_disableCollateral() public {
        liquidationEngine.disableCollateral(1, address(0x123));
    }

    function test_disableCollateral_OnlyRestricted() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        liquidationEngine.disableCollateral(1, address(0x123));
    }

    function test_setDebtConfig() public {
        liquidationEngine.setDebtConfig(
            address(0x123), LiquidationEngine.DebtConfig({isSupported: true, decimals: 18, borrowCap: 0})
        );
    }

    function test_setDebtConfig_OnlyRestricted() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        liquidationEngine.setDebtConfig(
            address(0x123), LiquidationEngine.DebtConfig({isSupported: true, decimals: 18, borrowCap: 0})
        );
    }

    function test_disableDebt() public {
        liquidationEngine.disableDebt(address(0x123));
    }

    function test_disableDebt_OnlyRestricted() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        liquidationEngine.disableDebt(address(0x123));
    }

    function test_setSpokeTokenAddress() public {
        liquidationEngine.setSpokeTokenAddress(1, address(0x123), address(0x124));
    }

    function test_setSpokeTokenAddress_OnlyRestricted() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        liquidationEngine.setSpokeTokenAddress(1, address(0x123), address(0x124));
    }

    function test_setBorrowRatePerSecondRay() public {
        liquidationEngine.setBorrowRatePerSecondRay(address(0x123), 1000);
    }

    function test_setBorrowRatePerSecondRay_OnlyRestricted() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        liquidationEngine.setBorrowRatePerSecondRay(address(0x123), 1000);
    }
}
