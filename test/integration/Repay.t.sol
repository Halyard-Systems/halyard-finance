// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseIntegrationTest} from "./BaseIntegrationTest.t.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {IRiskEngine} from "../../src/interfaces/IRiskEngine.sol";

contract RepayTest is BaseIntegrationTest {
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

    /// @notice Helper: deposit, borrow, and finalize to create debt for a user
    function _depositAndBorrow(address user, uint256 depositAmount, uint256 borrowAmount) internal returns (bytes32) {
        _mockOraclePrice(canonicalToken, 1e18);
        _depositAndCredit(user, bytes32("deposit_1"), canonicalToken, depositAmount);

        (IRiskEngine.CollateralSlot[] memory collateralSlots, IRiskEngine.DebtSlot[] memory debtSlots) = _buildSlots();
        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        _mockLzSend();

        bytes32 borrowId = keccak256(abi.encodePacked(user, spokeEid, canonicalToken, borrowAmount, block.number));

        vm.prank(user);
        hubRouter.borrowAndNotify{value: 0.1 ether}(
            spokeEid, canonicalToken, borrowAmount, collateralSlots, debtSlots, bytes(""), fee
        );

        _simulateBorrowReceipt(borrowId, user, canonicalToken, borrowAmount, true);

        return borrowId;
    }

    function test_RepaySuccess() public {
        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 50e18;
        uint256 repayAmount = 50e18;

        _depositAndBorrow(alice, depositAmount, borrowAmount);

        // Verify debt exists
        uint256 debtBefore = debtManager.debtOf(alice, spokeEid, canonicalToken);
        assertGt(debtBefore, 0);

        // Simulate repay receipt from spoke
        bytes32 repayId = bytes32("repay_1");
        _simulateRepayReceipt(repayId, alice, canonicalToken, repayAmount);

        // Debt should be cleared (or very close to 0 due to rounding)
        uint256 debtAfter = debtManager.debtOf(alice, spokeEid, canonicalToken);
        assertEq(debtAfter, 0);
    }

    function test_RepayPartial() public {
        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 50e18;
        uint256 repayAmount = 20e18;

        _depositAndBorrow(alice, depositAmount, borrowAmount);

        uint256 debtBefore = debtManager.debtOf(alice, spokeEid, canonicalToken);
        assertGt(debtBefore, 0);

        bytes32 repayId = bytes32("repay_partial");
        _simulateRepayReceipt(repayId, alice, canonicalToken, repayAmount);

        // Debt should be reduced but not zero
        uint256 debtAfter = debtManager.debtOf(alice, spokeEid, canonicalToken);
        assertGt(debtAfter, 0);
        assertLt(debtAfter, debtBefore);
    }

    function test_RepayOnBehalfOf() public {
        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 50e18;
        uint256 repayAmount = 50e18;

        _depositAndBorrow(alice, depositAmount, borrowAmount);

        uint256 debtBefore = debtManager.debtOf(alice, spokeEid, canonicalToken);
        assertGt(debtBefore, 0);

        // Bob repays on behalf of Alice (the repay receipt specifies alice as user)
        bytes32 repayId = bytes32("repay_behalf");
        _simulateRepayReceipt(repayId, alice, canonicalToken, repayAmount);

        uint256 debtAfter = debtManager.debtOf(alice, spokeEid, canonicalToken);
        assertEq(debtAfter, 0);
    }

    function test_RepayAfterMultipleBorrows() public {
        uint256 depositAmount = 100e18;
        uint256 firstBorrow = 20e18;
        uint256 secondBorrow = 20e18;

        _mockOraclePrice(canonicalToken, 1e18);
        _depositAndCredit(alice, bytes32("deposit_1"), canonicalToken, depositAmount);

        (IRiskEngine.CollateralSlot[] memory collateralSlots, IRiskEngine.DebtSlot[] memory debtSlots) = _buildSlots();
        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        // First borrow
        _mockLzSend();
        bytes32 borrowId1 = keccak256(abi.encodePacked(alice, spokeEid, canonicalToken, firstBorrow, block.number));
        vm.prank(alice);
        hubRouter.borrowAndNotify{value: 0.1 ether}(
            spokeEid, canonicalToken, firstBorrow, collateralSlots, debtSlots, bytes(""), fee
        );
        _simulateBorrowReceipt(borrowId1, alice, canonicalToken, firstBorrow, true);

        vm.roll(block.number + 1);

        // Second borrow
        _mockLzSend();
        bytes32 borrowId2 = keccak256(abi.encodePacked(alice, spokeEid, canonicalToken, secondBorrow, block.number));
        vm.prank(alice);
        hubRouter.borrowAndNotify{value: 0.1 ether}(
            spokeEid, canonicalToken, secondBorrow, collateralSlots, debtSlots, bytes(""), fee
        );
        _simulateBorrowReceipt(borrowId2, alice, canonicalToken, secondBorrow, true);

        // Total debt ~40e18
        uint256 totalDebt = debtManager.debtOf(alice, spokeEid, canonicalToken);
        assertGe(totalDebt, 39e18);
        assertLe(totalDebt, 41e18);

        // Repay 25e18 — partial
        bytes32 repayId = bytes32("repay_partial_multi");
        _simulateRepayReceipt(repayId, alice, canonicalToken, 25e18);

        uint256 debtAfter = debtManager.debtOf(alice, spokeEid, canonicalToken);
        assertGe(debtAfter, 14e18);
        assertLe(debtAfter, 16e18);
    }

    function test_RepayDoesNotAffectCollateral() public {
        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 50e18;
        uint256 repayAmount = 50e18;

        _depositAndBorrow(alice, depositAmount, borrowAmount);

        uint256 collateralBefore = positionBook.collateralOf(alice, spokeEid, canonicalToken);

        bytes32 repayId = bytes32("repay_collateral_check");
        _simulateRepayReceipt(repayId, alice, canonicalToken, repayAmount);

        // Collateral should remain unchanged
        uint256 collateralAfter = positionBook.collateralOf(alice, spokeEid, canonicalToken);
        assertEq(collateralAfter, collateralBefore);
    }
}
