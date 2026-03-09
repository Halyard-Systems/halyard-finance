// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../../BaseTest.t.sol";
import {HubRouter} from "../../../src/hub/HubRouter.sol";
import {IRiskEngine} from "../../../src/interfaces/IRiskEngine.sol";
import {IAccessManaged} from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

contract HubRouterTest is BaseTest {
    // ---------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------

    function test_Constructor_SetsOwner() public view {
        assertEq(hubRouter.owner(), admin);
    }

    function test_Constructor_RevertsOnZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OwnableInvalidOwner(address)")), address(0)));
        new HubRouter(address(0), address(hubAccessManager));
    }

    // ---------------------------------------------------------------
    // Admin: setHubController
    // ---------------------------------------------------------------

    function test_SetHubController() public {
        address newController = makeAddr("newController");
        vm.prank(admin);
        hubRouter.setHubController(newController);
        assertEq(address(hubRouter.hubController()), newController);
    }

    function test_SetHubController_RevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(HubRouter.InvalidAddress.selector);
        hubRouter.setHubController(address(0));
    }

    function test_SetHubController_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        hubRouter.setHubController(makeAddr("x"));
    }

    // ---------------------------------------------------------------
    // Admin: setPositionBook
    // ---------------------------------------------------------------

    function test_SetPositionBook() public {
        address newPB = makeAddr("newPB");
        vm.prank(admin);
        hubRouter.setPositionBook(newPB);
        assertEq(address(hubRouter.positionBook()), newPB);
    }

    function test_SetPositionBook_RevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(HubRouter.InvalidAddress.selector);
        hubRouter.setPositionBook(address(0));
    }

    function test_SetPositionBook_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        hubRouter.setPositionBook(makeAddr("x"));
    }

    // ---------------------------------------------------------------
    // Admin: setRiskEngine
    // ---------------------------------------------------------------

    function test_SetRiskEngine() public {
        address newRE = makeAddr("newRE");
        vm.prank(admin);
        hubRouter.setRiskEngine(newRE);
        assertEq(address(hubRouter.riskEngine()), newRE);
    }

    function test_SetRiskEngine_RevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(HubRouter.InvalidAddress.selector);
        hubRouter.setRiskEngine(address(0));
    }

    function test_SetRiskEngine_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        hubRouter.setRiskEngine(makeAddr("x"));
    }

    // ---------------------------------------------------------------
    // Admin: setDebtManager
    // ---------------------------------------------------------------

    function test_SetDebtManager() public {
        address newDM = makeAddr("newDM");
        vm.prank(admin);
        hubRouter.setDebtManager(newDM);
        assertEq(address(hubRouter.debtManager()), newDM);
    }

    function test_SetDebtManager_RevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(HubRouter.InvalidAddress.selector);
        hubRouter.setDebtManager(address(0));
    }

    function test_SetDebtManager_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        hubRouter.setDebtManager(makeAddr("x"));
    }

    // ---------------------------------------------------------------
    // Admin: pause / unpause
    // ---------------------------------------------------------------

    function test_Pause() public {
        vm.prank(admin);
        hubRouter.pause();
        assertTrue(hubRouter.paused());
    }

    function test_Unpause() public {
        vm.startPrank(admin);
        hubRouter.pause();
        hubRouter.unpause();
        vm.stopPrank();
        assertFalse(hubRouter.paused());
    }

    function test_Pause_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        hubRouter.pause();
    }

    function test_Unpause_OnlyOwner() public {
        vm.prank(admin);
        hubRouter.pause();

        vm.prank(alice);
        vm.expectRevert();
        hubRouter.unpause();
    }

    // ---------------------------------------------------------------
    // withdrawAndNotify validations
    // ---------------------------------------------------------------

    function test_WithdrawAndNotify_RevertsWhenPaused() public {
        vm.prank(admin);
        hubRouter.pause();

        IRiskEngine.CollateralSlot[] memory cs = new IRiskEngine.CollateralSlot[](0);
        IRiskEngine.DebtSlot[] memory ds = new IRiskEngine.DebtSlot[](0);
        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        vm.prank(alice);
        vm.expectRevert();
        hubRouter.withdrawAndNotify(spokeEid, canonicalToken, 1e18, cs, ds, bytes(""), fee);
    }

    function test_WithdrawAndNotify_RevertsOnZeroAsset() public {
        IRiskEngine.CollateralSlot[] memory cs = new IRiskEngine.CollateralSlot[](0);
        IRiskEngine.DebtSlot[] memory ds = new IRiskEngine.DebtSlot[](0);
        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        vm.prank(alice);
        vm.expectRevert(HubRouter.InvalidAddress.selector);
        hubRouter.withdrawAndNotify(spokeEid, address(0), 1e18, cs, ds, bytes(""), fee);
    }

    function test_WithdrawAndNotify_RevertsOnZeroAmount() public {
        IRiskEngine.CollateralSlot[] memory cs = new IRiskEngine.CollateralSlot[](0);
        IRiskEngine.DebtSlot[] memory ds = new IRiskEngine.DebtSlot[](0);
        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        vm.prank(alice);
        vm.expectRevert(HubRouter.InvalidAmount.selector);
        hubRouter.withdrawAndNotify(spokeEid, canonicalToken, 0, cs, ds, bytes(""), fee);
    }

    // ---------------------------------------------------------------
    // borrowAndNotify validations
    // ---------------------------------------------------------------

    function test_BorrowAndNotify_RevertsWhenPaused() public {
        vm.prank(admin);
        hubRouter.pause();

        IRiskEngine.CollateralSlot[] memory cs = new IRiskEngine.CollateralSlot[](0);
        IRiskEngine.DebtSlot[] memory ds = new IRiskEngine.DebtSlot[](0);
        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        vm.prank(alice);
        vm.expectRevert();
        hubRouter.borrowAndNotify(spokeEid, canonicalToken, 1e18, cs, ds, bytes(""), fee);
    }

    function test_BorrowAndNotify_RevertsOnZeroAsset() public {
        IRiskEngine.CollateralSlot[] memory cs = new IRiskEngine.CollateralSlot[](0);
        IRiskEngine.DebtSlot[] memory ds = new IRiskEngine.DebtSlot[](0);
        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        vm.prank(alice);
        vm.expectRevert(HubRouter.InvalidAddress.selector);
        hubRouter.borrowAndNotify(spokeEid, address(0), 1e18, cs, ds, bytes(""), fee);
    }

    function test_BorrowAndNotify_RevertsOnZeroAmount() public {
        IRiskEngine.CollateralSlot[] memory cs = new IRiskEngine.CollateralSlot[](0);
        IRiskEngine.DebtSlot[] memory ds = new IRiskEngine.DebtSlot[](0);
        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        vm.prank(alice);
        vm.expectRevert(HubRouter.InvalidAmount.selector);
        hubRouter.borrowAndNotify(spokeEid, canonicalToken, 0, cs, ds, bytes(""), fee);
    }

    // ---------------------------------------------------------------
    // Finalization: access control
    // ---------------------------------------------------------------

    function test_FinalizeWithdraw_OnlyRestricted() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        hubRouter.finalizeWithdraw(bytes32(0), true);
    }

    function test_FinalizeBorrow_OnlyRestricted() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        hubRouter.finalizeBorrow(bytes32(0), true);
    }

    function test_FinalizeRepay_OnlyRestricted() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        hubRouter.finalizeRepay(bytes32(0), alice, 1, address(0x123), 100);
    }

    function test_FinalizeLiquidation_OnlyRestricted() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        hubRouter.finalizeLiquidation(bytes32(0), true);
    }
}
