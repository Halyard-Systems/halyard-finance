// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseIntegrationTest} from "./BaseIntegrationTest.t.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {IRiskEngine} from "../../src/interfaces/IRiskEngine.sol";
import {RiskEngine} from "../../src/hub/RiskEngine.sol";

contract BorrowTest is BaseIntegrationTest {
    function _buildSlots()
        internal
        view
        returns (IRiskEngine.CollateralSlot[] memory collateralSlots, IRiskEngine.DebtSlot[] memory debtSlots)
    {
        collateralSlots = new IRiskEngine.CollateralSlot[](1);
        collateralSlots[0] = IRiskEngine.CollateralSlot({eid: spokeEid, asset: canonicalToken});

        debtSlots = new IRiskEngine.DebtSlot[](1);
        debtSlots[0] = IRiskEngine.DebtSlot({eid: spokeEid, asset: canonicalToken});
    }

    function test_BorrowSuccess() public {
        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 50e18; // 50% of 80% LTV = well within limits

        _mockOraclePrice(canonicalToken, 1e18);
        _depositAndCredit(alice, bytes32("deposit_1"), canonicalToken, depositAmount);

        (IRiskEngine.CollateralSlot[] memory collateralSlots, IRiskEngine.DebtSlot[] memory debtSlots) = _buildSlots();
        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        _mockLzSend();

        // Compute expected borrowId (same formula as HubRouter)
        bytes32 expectedBorrowId =
            keccak256(abi.encodePacked(alice, spokeEid, canonicalToken, borrowAmount, block.number));

        vm.prank(alice);
        hubRouter.borrowAndNotify{value: 0.1 ether}(
            spokeEid, canonicalToken, borrowAmount, collateralSlots, debtSlots, bytes(""), fee
        );

        // Verify intermediate state: pending borrow created, debt reserved
        assertEq(positionBook.reservedDebtOf(alice, spokeEid, canonicalToken), borrowAmount);

        // Simulate spoke confirming borrow release
        _simulateBorrowReceipt(expectedBorrowId, alice, canonicalToken, borrowAmount, true);

        // Verify final state: debt minted, reservation cleared
        assertGt(debtManager.debtOf(alice, spokeEid, canonicalToken), 0);
        assertEq(positionBook.reservedDebtOf(alice, spokeEid, canonicalToken), 0);
    }

    function test_BorrowFailsInsufficientCollateral() public {
        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 90e18; // 90% > 80% LTV, should fail

        _mockOraclePrice(canonicalToken, 1e18);
        _depositAndCredit(alice, bytes32("deposit_1"), canonicalToken, depositAmount);

        (IRiskEngine.CollateralSlot[] memory collateralSlots, IRiskEngine.DebtSlot[] memory debtSlots) = _buildSlots();
        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        _mockLzSend();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(RiskEngine.InsufficientBorrowPower.selector, 80e18, 90e18)
        );
        hubRouter.borrowAndNotify{value: 0.1 ether}(
            spokeEid, canonicalToken, borrowAmount, collateralSlots, debtSlots, bytes(""), fee
        );
    }

    function test_BorrowFailsOnSpoke() public {
        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 50e18;

        _mockOraclePrice(canonicalToken, 1e18);
        _depositAndCredit(alice, bytes32("deposit_1"), canonicalToken, depositAmount);

        (IRiskEngine.CollateralSlot[] memory collateralSlots, IRiskEngine.DebtSlot[] memory debtSlots) = _buildSlots();
        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        _mockLzSend();

        bytes32 expectedBorrowId =
            keccak256(abi.encodePacked(alice, spokeEid, canonicalToken, borrowAmount, block.number));

        vm.prank(alice);
        hubRouter.borrowAndNotify{value: 0.1 ether}(
            spokeEid, canonicalToken, borrowAmount, collateralSlots, debtSlots, bytes(""), fee
        );

        // Debt is reserved while borrow is in-flight
        assertEq(positionBook.reservedDebtOf(alice, spokeEid, canonicalToken), borrowAmount);

        // Spoke fails (e.g., insufficient liquidity) — success=false
        _simulateBorrowReceipt(expectedBorrowId, alice, canonicalToken, borrowAmount, false);

        // Debt reservation cleared, no debt minted
        assertEq(positionBook.reservedDebtOf(alice, spokeEid, canonicalToken), 0);
        assertEq(debtManager.debtOf(alice, spokeEid, canonicalToken), 0);
    }

    function test_BorrowWithExistingDebt() public {
        uint256 depositAmount = 100e18;
        uint256 firstBorrow = 30e18;
        uint256 secondBorrow = 30e18;

        _mockOraclePrice(canonicalToken, 1e18);
        _depositAndCredit(alice, bytes32("deposit_1"), canonicalToken, depositAmount);

        (IRiskEngine.CollateralSlot[] memory collateralSlots, IRiskEngine.DebtSlot[] memory debtSlots) = _buildSlots();
        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        // First borrow
        _mockLzSend();
        bytes32 borrowId1 =
            keccak256(abi.encodePacked(alice, spokeEid, canonicalToken, firstBorrow, block.number));

        vm.prank(alice);
        hubRouter.borrowAndNotify{value: 0.1 ether}(
            spokeEid, canonicalToken, firstBorrow, collateralSlots, debtSlots, bytes(""), fee
        );
        _simulateBorrowReceipt(borrowId1, alice, canonicalToken, firstBorrow, true);

        // Advance block so the second borrow produces a distinct borrowId
        // (borrowId includes block.number, so same-block same-amount borrows collide)
        vm.roll(block.number + 1);

        // Second borrow (cumulative debt = 60e18 < 80e18 borrow power)
        _mockLzSend();
        bytes32 borrowId2 =
            keccak256(abi.encodePacked(alice, spokeEid, canonicalToken, secondBorrow, block.number));

        vm.prank(alice);
        hubRouter.borrowAndNotify{value: 0.1 ether}(
            spokeEid, canonicalToken, secondBorrow, collateralSlots, debtSlots, bytes(""), fee
        );
        _simulateBorrowReceipt(borrowId2, alice, canonicalToken, secondBorrow, true);

        // Total debt should be ~60e18 (both borrows)
        assertGe(debtManager.debtOf(alice, spokeEid, canonicalToken), 59e18);
        assertLe(debtManager.debtOf(alice, spokeEid, canonicalToken), 61e18);
    }

    function test_BorrowWithPendingWithdraw() public {
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 50e18;
        uint256 borrowAmount = 40e18; // Would be fine with 100e18 collateral, but not with 50e18

        _mockOraclePrice(canonicalToken, 1e18);
        _depositAndCredit(alice, bytes32("deposit_1"), canonicalToken, depositAmount);

        // No debt slots needed for withdraw-only
        IRiskEngine.CollateralSlot[] memory collateralSlots = new IRiskEngine.CollateralSlot[](1);
        collateralSlots[0] = IRiskEngine.CollateralSlot({eid: spokeEid, asset: canonicalToken});
        IRiskEngine.DebtSlot[] memory emptyDebtSlots = new IRiskEngine.DebtSlot[](0);

        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        // Initiate withdrawal (reserves 50e18 collateral, leaves 50e18 available)
        _mockLzSend();
        vm.prank(alice);
        hubRouter.withdrawAndNotify{value: 0.1 ether}(
            spokeEid, canonicalToken, withdrawAmount, collateralSlots, emptyDebtSlots, bytes(""), fee
        );

        // Now try to borrow 40e18 — available collateral is 50e18, borrow power = 50*0.8 = 40e18
        // But debt of 40e18 equals borrow power of 40e18 exactly, health factor = 1.0 which should pass
        (, IRiskEngine.DebtSlot[] memory debtSlots) = _buildSlots();

        _mockLzSend();
        vm.prank(alice);
        hubRouter.borrowAndNotify{value: 0.1 ether}(
            spokeEid, canonicalToken, borrowAmount, collateralSlots, debtSlots, bytes(""), fee
        );

        // Borrow at exactly borrow power limit should succeed (health factor = 1.0)
        assertEq(positionBook.reservedDebtOf(alice, spokeEid, canonicalToken), borrowAmount);

        // But 41e18 would fail — verify the limit
        _mockLzSend();
        vm.prank(alice);
        vm.expectRevert(); // InsufficientBorrowPower
        hubRouter.borrowAndNotify{value: 0.1 ether}(
            spokeEid, canonicalToken, 41e18, collateralSlots, debtSlots, bytes(""), fee
        );
    }
}
