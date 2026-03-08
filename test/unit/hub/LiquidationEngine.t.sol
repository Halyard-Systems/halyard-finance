// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../../BaseTest.t.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {IAccessManaged} from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import {LiquidationEngine} from "../../../src/hub/LiquidationEngine.sol";

contract LiquidationEngineTest is BaseTest {
    function test_setDependencies() public {
        assertEq(address(liquidationEngine.positionBook()), address(positionBook));
        assertEq(address(liquidationEngine.debtManager()), address(debtManager));
        assertEq(address(liquidationEngine.oracle()), mockOracle);
        assertEq(address(liquidationEngine.hubController()), address(hubController));
    }

    function test_setDependencies_OnlyRestricted() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        liquidationEngine.setDependencies(
            address(positionBook), address(debtManager), address(assetRegistry), mockOracle, address(hubController)
        );
    }

    function test_setDependencies_RejectsZeroAddress() public {
        LiquidationEngine engine = new LiquidationEngine(address(hubAccessManager));
        vm.prank(admin);
        vm.expectRevert(LiquidationEngine.InvalidAddress.selector);
        engine.setDependencies(
            address(0), address(debtManager), address(assetRegistry), mockOracle, address(hubController)
        );
    }

    function test_liquidate_RevertsOnZeroAddress() public {
        LiquidationEngine.CollateralSlot[] memory cs = new LiquidationEngine.CollateralSlot[](0);
        LiquidationEngine.DebtSlot[] memory ds = new LiquidationEngine.DebtSlot[](0);
        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        vm.prank(bob);
        vm.expectRevert(LiquidationEngine.InvalidAddress.selector);
        liquidationEngine.liquidate(address(0), spokeEid, canonicalToken, 50e18, spokeEid, canonicalToken, cs, ds, bytes(""), fee);
    }

    function test_liquidate_RevertsOnZeroAmount() public {
        LiquidationEngine.CollateralSlot[] memory cs = new LiquidationEngine.CollateralSlot[](0);
        LiquidationEngine.DebtSlot[] memory ds = new LiquidationEngine.DebtSlot[](0);
        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        vm.prank(bob);
        vm.expectRevert(LiquidationEngine.InvalidAmount.selector);
        liquidationEngine.liquidate(alice, spokeEid, canonicalToken, 0, spokeEid, canonicalToken, cs, ds, bytes(""), fee);
    }
}
