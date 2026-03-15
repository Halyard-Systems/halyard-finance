// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MultiSpokeBaseTest} from "../MultiSpokeBaseTest.t.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {IRiskEngine} from "../../src/interfaces/IRiskEngine.sol";

contract CrossSpokeBorrowTest is MultiSpokeBaseTest {
    /// @notice Deposit collateral on ETH spoke, borrow from ARB spoke.
    ///         Hub validates cross-spoke collateral and sends borrow command to ARB.
    function test_DepositEthBorrowArb() public {
        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 50e18;

        _mockOraclePrice(canonicalTokenEth, 1e18);
        _mockOraclePrice(canonicalTokenArb, 1e18);

        // Deposit collateral on ETH spoke
        _depositAndCredit(
            spokeControllerEth, collateralVaultEth, mockTokenEth,
            alice, bytes32("dep_eth"), canonicalTokenEth, depositAmount
        );

        // Build slots: collateral on ETH, debt on ARB
        IRiskEngine.CollateralSlot[] memory collateralSlots = new IRiskEngine.CollateralSlot[](1);
        collateralSlots[0] = IRiskEngine.CollateralSlot({eid: ethEid, asset: canonicalTokenEth});

        IRiskEngine.DebtSlot[] memory debtSlots = new IRiskEngine.DebtSlot[](1);
        debtSlots[0] = IRiskEngine.DebtSlot({eid: arbEid, asset: canonicalTokenArb});

        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        _mockLzSend();

        bytes32 expectedBorrowId =
            keccak256(abi.encodePacked(alice, arbEid, canonicalTokenArb, borrowAmount, block.number, uint256(0)));

        vm.prank(alice);
        hubRouter.borrowAndNotify{value: 0.1 ether}(
            arbEid, canonicalTokenArb, borrowAmount, collateralSlots, debtSlots, bytes(""), fee
        );

        // Verify debt reserved on ARB spoke
        assertEq(positionBook.reservedDebtOf(alice, arbEid, canonicalTokenArb), borrowAmount);

        // Simulate ARB spoke confirming borrow
        _simulateBorrowReceipt(spokeControllerArb, expectedBorrowId, alice, canonicalTokenArb, borrowAmount, true);

        // Verify debt minted on ARB, collateral still on ETH
        assertGt(debtManager.debtOf(alice, arbEid, canonicalTokenArb), 0);
        assertEq(positionBook.collateralOf(alice, ethEid, canonicalTokenEth), depositAmount);
        assertEq(positionBook.reservedDebtOf(alice, arbEid, canonicalTokenArb), 0);
    }

    /// @notice Deposit on ETH, deposit on BASE, borrow from ARB using both as collateral.
    function test_MultiSpokeCollateralBorrow() public {
        uint256 depositEth = 60e18;
        uint256 depositBase = 40e18;
        uint256 borrowAmount = 70e18; // 70 < (60 + 40) * 80% = 80

        _mockOraclePrice(canonicalTokenEth, 1e18);
        _mockOraclePrice(canonicalTokenBase, 1e18);
        _mockOraclePrice(canonicalTokenArb, 1e18);

        _depositAndCredit(
            spokeControllerEth, collateralVaultEth, mockTokenEth,
            alice, bytes32("dep_eth"), canonicalTokenEth, depositEth
        );
        _depositAndCredit(
            spokeControllerBase, collateralVaultBase, mockTokenBase,
            alice, bytes32("dep_base"), canonicalTokenBase, depositBase
        );

        // Collateral from 2 spokes, debt on 1
        IRiskEngine.CollateralSlot[] memory collateralSlots = new IRiskEngine.CollateralSlot[](2);
        collateralSlots[0] = IRiskEngine.CollateralSlot({eid: ethEid, asset: canonicalTokenEth});
        collateralSlots[1] = IRiskEngine.CollateralSlot({eid: baseEid, asset: canonicalTokenBase});

        IRiskEngine.DebtSlot[] memory debtSlots = new IRiskEngine.DebtSlot[](1);
        debtSlots[0] = IRiskEngine.DebtSlot({eid: arbEid, asset: canonicalTokenArb});

        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});
        _mockLzSend();

        bytes32 borrowId =
            keccak256(abi.encodePacked(alice, arbEid, canonicalTokenArb, borrowAmount, block.number, uint256(0)));

        vm.prank(alice);
        hubRouter.borrowAndNotify{value: 0.1 ether}(
            arbEid, canonicalTokenArb, borrowAmount, collateralSlots, debtSlots, bytes(""), fee
        );

        _simulateBorrowReceipt(spokeControllerArb, borrowId, alice, canonicalTokenArb, borrowAmount, true);

        // All collateral intact, debt on ARB
        assertEq(positionBook.collateralOf(alice, ethEid, canonicalTokenEth), depositEth);
        assertEq(positionBook.collateralOf(alice, baseEid, canonicalTokenBase), depositBase);
        assertGt(debtManager.debtOf(alice, arbEid, canonicalTokenArb), 0);
    }

    /// @notice Borrow fails when cross-spoke collateral is insufficient.
    function test_CrossSpokeBorrowFailsInsufficientCollateral() public {
        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 90e18; // 90 > 100 * 80% = 80

        _mockOraclePrice(canonicalTokenEth, 1e18);
        _mockOraclePrice(canonicalTokenArb, 1e18);

        _depositAndCredit(
            spokeControllerEth, collateralVaultEth, mockTokenEth,
            alice, bytes32("dep_eth"), canonicalTokenEth, depositAmount
        );

        IRiskEngine.CollateralSlot[] memory collateralSlots = new IRiskEngine.CollateralSlot[](1);
        collateralSlots[0] = IRiskEngine.CollateralSlot({eid: ethEid, asset: canonicalTokenEth});

        IRiskEngine.DebtSlot[] memory debtSlots = new IRiskEngine.DebtSlot[](1);
        debtSlots[0] = IRiskEngine.DebtSlot({eid: arbEid, asset: canonicalTokenArb});

        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});
        _mockLzSend();

        vm.prank(alice);
        vm.expectRevert(); // InsufficientBorrowPower
        hubRouter.borrowAndNotify{value: 0.1 ether}(
            arbEid, canonicalTokenArb, borrowAmount, collateralSlots, debtSlots, bytes(""), fee
        );
    }
}
