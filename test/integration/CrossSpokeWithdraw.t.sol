// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MultiSpokeBaseTest} from "../MultiSpokeBaseTest.t.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {IRiskEngine} from "../../src/interfaces/IRiskEngine.sol";

contract CrossSpokeWithdrawTest is MultiSpokeBaseTest {
    /// @notice Deposit across ETH and ARB spokes, withdraw from ETH.
    ///         Risk engine correctly aggregates cross-spoke collateral.
    function test_WithdrawFromOneSpoke() public {
        uint256 depositEth = 100e18;
        uint256 depositArb = 50e18;
        uint256 withdrawAmount = 80e18;

        _mockOraclePrice(canonicalTokenEth, 1e18);
        _mockOraclePrice(canonicalTokenArb, 1e18);

        _depositAndCredit(
            spokeControllerEth, collateralVaultEth, mockTokenEth,
            alice, bytes32("dep_eth"), canonicalTokenEth, depositEth
        );
        _depositAndCredit(
            spokeControllerArb, collateralVaultArb, mockTokenArb,
            alice, bytes32("dep_arb"), canonicalTokenArb, depositArb
        );

        // Withdraw from ETH spoke (no debt, so full withdrawal should work)
        IRiskEngine.CollateralSlot[] memory collateralSlots = new IRiskEngine.CollateralSlot[](2);
        collateralSlots[0] = IRiskEngine.CollateralSlot({eid: ethEid, asset: canonicalTokenEth});
        collateralSlots[1] = IRiskEngine.CollateralSlot({eid: arbEid, asset: canonicalTokenArb});

        IRiskEngine.DebtSlot[] memory debtSlots = new IRiskEngine.DebtSlot[](0);

        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});
        _mockLzSend();

        vm.prank(alice);
        hubRouter.withdrawAndNotify{value: 0.1 ether}(
            ethEid, canonicalTokenEth, withdrawAmount, collateralSlots, debtSlots, bytes(""), fee
        );

        // Verify reservation
        assertEq(positionBook.reservedCollateralOf(alice, ethEid, canonicalTokenEth), withdrawAmount);

        // Simulate spoke confirming withdrawal
        _simulateWithdrawReceipt(spokeControllerEth, alice, canonicalTokenEth, withdrawAmount, true, 0);

        // ETH collateral reduced, ARB untouched
        assertEq(positionBook.collateralOf(alice, ethEid, canonicalTokenEth), depositEth - withdrawAmount);
        assertEq(positionBook.collateralOf(alice, arbEid, canonicalTokenArb), depositArb);
        assertEq(positionBook.reservedCollateralOf(alice, ethEid, canonicalTokenEth), 0);
    }

    /// @notice Deposit on ETH, borrow on ARB, then withdraw from ETH.
    ///         Withdraw is limited by outstanding cross-spoke debt.
    function test_WithdrawLimitedByCrossSpokDebt() public {
        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 60e18;

        _mockOraclePrice(canonicalTokenEth, 1e18);
        _mockOraclePrice(canonicalTokenArb, 1e18);

        // Deposit on ETH
        _depositAndCredit(
            spokeControllerEth, collateralVaultEth, mockTokenEth,
            alice, bytes32("dep_eth"), canonicalTokenEth, depositAmount
        );

        // Borrow from ARB using ETH collateral
        IRiskEngine.CollateralSlot[] memory colSlots = new IRiskEngine.CollateralSlot[](1);
        colSlots[0] = IRiskEngine.CollateralSlot({eid: ethEid, asset: canonicalTokenEth});

        IRiskEngine.DebtSlot[] memory debtSlots = new IRiskEngine.DebtSlot[](1);
        debtSlots[0] = IRiskEngine.DebtSlot({eid: arbEid, asset: canonicalTokenArb});

        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});
        _mockLzSend();

        bytes32 borrowId =
            keccak256(abi.encodePacked(alice, arbEid, canonicalTokenArb, borrowAmount, block.number, uint256(0)));

        vm.prank(alice);
        hubRouter.borrowAndNotify{value: 0.1 ether}(
            arbEid, canonicalTokenArb, borrowAmount, colSlots, debtSlots, bytes(""), fee
        );
        _simulateBorrowReceipt(spokeControllerArb, borrowId, alice, canonicalTokenArb, borrowAmount, true);

        // With 60e18 debt at 80% LTV, need 75e18 collateral minimum.
        // Withdrawing 30e18 leaves 70e18 < 75e18 needed → should fail
        _mockLzSend();

        vm.prank(alice);
        vm.expectRevert(); // InsufficientBorrowPower / health factor < 1
        hubRouter.withdrawAndNotify{value: 0.1 ether}(
            ethEid, canonicalTokenEth, 30e18, colSlots, debtSlots, bytes(""), fee
        );

        // But withdrawing 20e18 leaves 80e18 → borrow power = 64 > 60 debt → should work
        _mockLzSend();
        vm.prank(alice);
        hubRouter.withdrawAndNotify{value: 0.1 ether}(
            ethEid, canonicalTokenEth, 20e18, colSlots, debtSlots, bytes(""), fee
        );

        assertEq(positionBook.reservedCollateralOf(alice, ethEid, canonicalTokenEth), 20e18);
    }
}
