// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MultiSpokeBaseTest} from "../MultiSpokeBaseTest.t.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {IRiskEngine} from "../../src/interfaces/IRiskEngine.sol";
import {LiquidationEngine} from "../../src/hub/LiquidationEngine.sol";

contract CrossSpokeLiquidationTest is MultiSpokeBaseTest {
    /// @notice Collateral on ETH spoke, debt on ARB spoke.
    ///         Liquidator seizes ETH collateral to cover ARB debt.
    function test_CrossSpokeLiquidation() public {
        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 80e18;

        _mockOraclePrice(canonicalTokenEth, 1e18);
        _mockOraclePrice(canonicalTokenArb, 1e18);

        // Alice deposits on ETH spoke
        _depositAndCredit(
            spokeControllerEth,
            collateralVaultEth,
            mockTokenEth,
            alice,
            bytes32("dep_eth"),
            canonicalTokenEth,
            depositAmount
        );

        // Alice borrows from ARB spoke using ETH collateral
        IRiskEngine.CollateralSlot[] memory riskColSlots = new IRiskEngine.CollateralSlot[](1);
        riskColSlots[0] = IRiskEngine.CollateralSlot({eid: ethEid, asset: canonicalTokenEth});

        IRiskEngine.DebtSlot[] memory riskDebtSlots = new IRiskEngine.DebtSlot[](1);
        riskDebtSlots[0] = IRiskEngine.DebtSlot({eid: arbEid, asset: canonicalTokenArb});

        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});
        _mockLzSend();

        uint256 nonce = hubRouter.nonces(alice);
        bytes32 borrowId =
            keccak256(abi.encodePacked(alice, arbEid, canonicalTokenArb, borrowAmount, block.number, nonce));

        vm.prank(alice);
        hubRouter.borrowAndNotify{value: 0.1 ether}(
            arbEid, canonicalTokenArb, borrowAmount, riskColSlots, riskDebtSlots, bytes(""), fee
        );

        _simulateBorrowReceipt(spokeControllerArb, borrowId, alice, canonicalTokenArb, borrowAmount, true);

        // Advance time to make position liquidatable (5% APR, 2 years → debt ~88.4 > 85% threshold)
        vm.warp(block.timestamp + 730 days);
        debtManager.accrue(arbEid, canonicalTokenArb);

        uint256 debtBefore = debtManager.debtOf(alice, arbEid, canonicalTokenArb);
        assertGt(debtBefore, 85e18);

        // Build liquidation slots: seize ETH collateral to cover ARB debt
        LiquidationEngine.CollateralSlot[] memory liqColSlots = new LiquidationEngine.CollateralSlot[](1);
        liqColSlots[0] = LiquidationEngine.CollateralSlot({eid: ethEid, asset: canonicalTokenEth});

        LiquidationEngine.DebtSlot[] memory liqDebtSlots = new LiquidationEngine.DebtSlot[](1);
        liqDebtSlots[0] = LiquidationEngine.DebtSlot({eid: arbEid, asset: canonicalTokenArb});

        _mockLzSend();

        uint256 debtToRepay = 40e18;

        vm.prank(bob);
        liquidationEngine.liquidate{value: 0.1 ether}(
            alice,
            arbEid,
            canonicalTokenArb,
            debtToRepay, // debt to repay (ARB spoke)
            ethEid,
            canonicalTokenEth, // collateral to seize (ETH spoke)
            liqColSlots,
            liqDebtSlots,
            bytes(""),
            fee
        );

        // Collateral should be reserved on ETH spoke
        assertGt(positionBook.reservedCollateralOf(alice, ethEid, canonicalTokenEth), 0);

        // Compute expected liqId
        bytes32 liqId = keccak256(
            abi.encodePacked(
                bob,
                alice,
                arbEid,
                canonicalTokenArb,
                debtToRepay,
                ethEid,
                canonicalTokenEth,
                block.number,
                liquidationEngine.nonces(bob) - 1
            )
        );

        uint256 expectedSeize = (debtToRepay * 10500) / 10000;

        // Simulate ETH spoke confirming seizure
        _simulateSeizeReceipt(spokeControllerEth, liqId, alice, canonicalTokenEth, expectedSeize, bob, true);

        // Debt on ARB should be burned
        uint256 debtAfter = debtManager.debtOf(alice, arbEid, canonicalTokenArb);
        assertLt(debtAfter, debtBefore);

        // Collateral on ETH should be reduced
        uint256 collateralAfter = positionBook.collateralOf(alice, ethEid, canonicalTokenEth);
        assertEq(collateralAfter, depositAmount - expectedSeize);

        // Reservation cleared
        assertEq(positionBook.reservedCollateralOf(alice, ethEid, canonicalTokenEth), 0);
    }

    /// @notice Healthy cross-spoke position cannot be liquidated.
    function test_CrossSpokeLiquidationRevertsIfHealthy() public {
        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 50e18; // Well within LTV

        _mockOraclePrice(canonicalTokenEth, 1e18);
        _mockOraclePrice(canonicalTokenArb, 1e18);

        _depositAndCredit(
            spokeControllerEth,
            collateralVaultEth,
            mockTokenEth,
            alice,
            bytes32("dep_eth"),
            canonicalTokenEth,
            depositAmount
        );

        IRiskEngine.CollateralSlot[] memory riskColSlots = new IRiskEngine.CollateralSlot[](1);
        riskColSlots[0] = IRiskEngine.CollateralSlot({eid: ethEid, asset: canonicalTokenEth});

        IRiskEngine.DebtSlot[] memory riskDebtSlots = new IRiskEngine.DebtSlot[](1);
        riskDebtSlots[0] = IRiskEngine.DebtSlot({eid: arbEid, asset: canonicalTokenArb});

        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});
        _mockLzSend();

        bytes32 borrowId =
            keccak256(abi.encodePacked(alice, arbEid, canonicalTokenArb, borrowAmount, block.number, uint256(0)));

        vm.prank(alice);
        hubRouter.borrowAndNotify{value: 0.1 ether}(
            arbEid, canonicalTokenArb, borrowAmount, riskColSlots, riskDebtSlots, bytes(""), fee
        );
        _simulateBorrowReceipt(spokeControllerArb, borrowId, alice, canonicalTokenArb, borrowAmount, true);

        // No time advance — account is healthy
        LiquidationEngine.CollateralSlot[] memory liqColSlots = new LiquidationEngine.CollateralSlot[](1);
        liqColSlots[0] = LiquidationEngine.CollateralSlot({eid: ethEid, asset: canonicalTokenEth});

        LiquidationEngine.DebtSlot[] memory liqDebtSlots = new LiquidationEngine.DebtSlot[](1);
        liqDebtSlots[0] = LiquidationEngine.DebtSlot({eid: arbEid, asset: canonicalTokenArb});

        vm.prank(bob);
        vm.expectRevert(); // NotLiquidatable
        liquidationEngine.liquidate{value: 0.1 ether}(
            alice,
            arbEid,
            canonicalTokenArb,
            20e18,
            ethEid,
            canonicalTokenEth,
            liqColSlots,
            liqDebtSlots,
            bytes(""),
            fee
        );
    }
}
