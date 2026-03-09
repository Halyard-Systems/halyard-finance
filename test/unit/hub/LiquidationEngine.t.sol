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
        liquidationEngine.liquidate(
            address(0), spokeEid, canonicalToken, 50e18, spokeEid, canonicalToken, cs, ds, bytes(""), fee
        );
    }

    function test_liquidate_RevertsOnZeroAmount() public {
        LiquidationEngine.CollateralSlot[] memory cs = new LiquidationEngine.CollateralSlot[](0);
        LiquidationEngine.DebtSlot[] memory ds = new LiquidationEngine.DebtSlot[](0);
        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        vm.prank(bob);
        vm.expectRevert(LiquidationEngine.InvalidAmount.selector);
        liquidationEngine.liquidate(
            alice, spokeEid, canonicalToken, 0, spokeEid, canonicalToken, cs, ds, bytes(""), fee
        );
    }

    // ---------------------------------------------------------------
    // Helpers for slot completeness tests
    // ---------------------------------------------------------------

    function _mockOracle() internal {
        vm.mockCall(mockOracle, abi.encodeWithSignature("getPriceE18(address)"), abi.encode(1000e18, block.timestamp));
    }

    function _creditCollateral(address user, uint32 eid, address asset, uint256 amount) internal {
        vm.prank(address(hubController));
        positionBook.creditCollateral(user, eid, asset, amount);
    }

    function _mintDebt(address user, uint32 eid, address asset, uint256 amount) internal {
        vm.prank(address(hubRouter));
        debtManager.mintDebt(user, eid, asset, amount);
    }

    // ---------------------------------------------------------------
    // Slot completeness: Liquidator omits collateral slots
    // ---------------------------------------------------------------

    function test_RevertsWithEmptyCollateralSlots_WhenCollateralExists() public {
        _mockOracle();

        _creditCollateral(alice, 1, address(0x123), 100e18);
        _mintDebt(alice, 1, address(0x123), 90e18);

        LiquidationEngine.CollateralSlot[] memory emptyCollateral = new LiquidationEngine.CollateralSlot[](0);
        LiquidationEngine.DebtSlot[] memory debtSlots = new LiquidationEngine.DebtSlot[](1);
        debtSlots[0] = LiquidationEngine.DebtSlot({eid: 1, asset: address(0x123)});

        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(LiquidationEngine.IncompleteCollateralSlots.selector, uint32(1), address(0x123))
        );
        liquidationEngine.liquidate(
            alice, 1, address(0x123), 50e18, 1, address(0x123), emptyCollateral, debtSlots, bytes(""), fee
        );
    }

    function test_RevertsWithEmptyDebtSlots_WhenDebtExists() public {
        _mockOracle();

        _creditCollateral(alice, 1, address(0x123), 100e18);
        _mintDebt(alice, 1, address(0x123), 90e18);

        LiquidationEngine.CollateralSlot[] memory collateralSlots = new LiquidationEngine.CollateralSlot[](1);
        collateralSlots[0] = LiquidationEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        LiquidationEngine.DebtSlot[] memory emptyDebt = new LiquidationEngine.DebtSlot[](0);

        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(LiquidationEngine.IncompleteDebtSlots.selector, uint32(1), address(0x123))
        );
        liquidationEngine.liquidate(
            alice, 1, address(0x123), 50e18, 1, address(0x123), collateralSlots, emptyDebt, bytes(""), fee
        );
    }

    function test_RevertsWithPartialCollateralSlots() public {
        _mockOracle();
        vm.mockCall(
            mockOracle,
            abi.encodeWithSignature("getPriceE18(address)", address(0x124)),
            abi.encode(2000e18, block.timestamp)
        );

        _creditCollateral(alice, 1, address(0x123), 100e18);
        _creditCollateral(alice, 2, address(0x124), 50e18);
        _mintDebt(alice, 1, address(0x123), 90e18);

        LiquidationEngine.CollateralSlot[] memory partialCollateral = new LiquidationEngine.CollateralSlot[](1);
        partialCollateral[0] = LiquidationEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        LiquidationEngine.DebtSlot[] memory debtSlots = new LiquidationEngine.DebtSlot[](1);
        debtSlots[0] = LiquidationEngine.DebtSlot({eid: 1, asset: address(0x123)});

        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(LiquidationEngine.IncompleteCollateralSlots.selector, uint32(2), address(0x124))
        );
        liquidationEngine.liquidate(
            alice, 1, address(0x123), 50e18, 1, address(0x123), partialCollateral, debtSlots, bytes(""), fee
        );
    }

    // ---------------------------------------------------------------
    // Duplicate slots
    // ---------------------------------------------------------------

    function test_RevertsDuplicateDebtSlots() public {
        _mockOracle();

        _creditCollateral(alice, 1, address(0x123), 100e18);
        _mintDebt(alice, 1, address(0x123), 90e18);

        LiquidationEngine.CollateralSlot[] memory collateralSlots = new LiquidationEngine.CollateralSlot[](1);
        collateralSlots[0] = LiquidationEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        LiquidationEngine.DebtSlot[] memory duplicateDebtSlots = new LiquidationEngine.DebtSlot[](3);
        duplicateDebtSlots[0] = LiquidationEngine.DebtSlot({eid: 1, asset: address(0x123)});
        duplicateDebtSlots[1] = LiquidationEngine.DebtSlot({eid: 1, asset: address(0x123)});
        duplicateDebtSlots[2] = LiquidationEngine.DebtSlot({eid: 1, asset: address(0x123)});

        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(LiquidationEngine.DuplicateDebtSlot.selector, uint32(1), address(0x123)));
        liquidationEngine.liquidate(
            alice, 1, address(0x123), 50e18, 1, address(0x123), collateralSlots, duplicateDebtSlots, bytes(""), fee
        );
    }

    function test_RevertsDuplicateCollateralSlots() public {
        _mockOracle();

        _creditCollateral(alice, 1, address(0x123), 100e18);
        _mintDebt(alice, 1, address(0x123), 90e18);

        LiquidationEngine.CollateralSlot[] memory duplicateCollateral = new LiquidationEngine.CollateralSlot[](2);
        duplicateCollateral[0] = LiquidationEngine.CollateralSlot({eid: 1, asset: address(0x123)});
        duplicateCollateral[1] = LiquidationEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        LiquidationEngine.DebtSlot[] memory debtSlots = new LiquidationEngine.DebtSlot[](1);
        debtSlots[0] = LiquidationEngine.DebtSlot({eid: 1, asset: address(0x123)});

        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(LiquidationEngine.DuplicateCollateralSlot.selector, uint32(1), address(0x123))
        );
        liquidationEngine.liquidate(
            alice, 1, address(0x123), 50e18, 1, address(0x123), duplicateCollateral, debtSlots, bytes(""), fee
        );
    }
}
