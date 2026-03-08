// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseIntegrationTest} from "./BaseIntegrationTest.t.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {IRiskEngine} from "../../src/interfaces/IRiskEngine.sol";
import {LiquidationEngine} from "../../src/hub/LiquidationEngine.sol";
import {AssetRegistry} from "../../src/hub/AssetRegistry.sol";

contract LiquidationTest is BaseIntegrationTest {
    function _buildRiskSlots()
        internal
        view
        returns (IRiskEngine.CollateralSlot[] memory collateralSlots, IRiskEngine.DebtSlot[] memory debtSlots)
    {
        collateralSlots = new IRiskEngine.CollateralSlot[](1);
        collateralSlots[0] = IRiskEngine.CollateralSlot({eid: spokeEid, asset: canonicalToken});

        debtSlots = new IRiskEngine.DebtSlot[](1);
        debtSlots[0] = IRiskEngine.DebtSlot({eid: spokeEid, asset: canonicalToken});
    }

    function _buildLiqSlots()
        internal
        view
        returns (
            LiquidationEngine.CollateralSlot[] memory collateralSlots,
            LiquidationEngine.DebtSlot[] memory debtSlots
        )
    {
        collateralSlots = new LiquidationEngine.CollateralSlot[](1);
        collateralSlots[0] = LiquidationEngine.CollateralSlot({eid: spokeEid, asset: canonicalToken});

        debtSlots = new LiquidationEngine.DebtSlot[](1);
        debtSlots[0] = LiquidationEngine.DebtSlot({eid: spokeEid, asset: canonicalToken});
    }

    /// @notice Helper: deposit, borrow, and finalize to create debt for a user
    function _depositAndBorrow(address user, uint256 depositAmount, uint256 borrowAmount) internal returns (bytes32) {
        _mockOraclePrice(canonicalToken, 1e18);
        _depositAndCredit(user, bytes32("deposit_1"), canonicalToken, depositAmount);

        (IRiskEngine.CollateralSlot[] memory collateralSlots, IRiskEngine.DebtSlot[] memory debtSlots) =
            _buildRiskSlots();
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

    /// @notice Make a position liquidatable by advancing time so interest accrual
    ///   pushes debt above the liquidation threshold.
    ///   With same-asset collateral/debt, price changes cancel out, so we rely on interest.
    ///   100 collateral, 80 debt, liqThreshold 85%, 5% APR:
    ///   After ~2 years, debt ≈ 88.4 → HF = 85/88.4 ≈ 0.96 < 1.0
    function _makePositionLiquidatable() internal {
        // Advance 2 years so interest compounds debt beyond liquidation threshold
        vm.warp(block.timestamp + 730 days);
        // Accrue interest
        debtManager.accrue(spokeEid, canonicalToken);
    }

    function test_LiquidationSuccess() public {
        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 80e18;

        _depositAndBorrow(alice, depositAmount, borrowAmount);
        _makePositionLiquidatable();
        _mockOraclePrice(canonicalToken, 1e18);

        (LiquidationEngine.CollateralSlot[] memory cs, LiquidationEngine.DebtSlot[] memory ds) = _buildLiqSlots();
        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        _mockLzSend();

        uint256 debtBefore = debtManager.debtOf(alice, spokeEid, canonicalToken);
        assertGt(debtBefore, 85e18); // Debt grew past liq threshold

        uint256 debtToRepay = 40e18;

        // Bob liquidates Alice
        vm.prank(bob);
        liquidationEngine.liquidate{value: 0.1 ether}(
            alice, spokeEid, canonicalToken, debtToRepay, spokeEid, canonicalToken, cs, ds, bytes(""), fee
        );

        // Verify debt was reduced
        uint256 debtAfter = debtManager.debtOf(alice, spokeEid, canonicalToken);
        assertLt(debtAfter, debtBefore);

        // Compute expected liqId
        bytes32 expectedLiqId = keccak256(
            abi.encodePacked(bob, alice, spokeEid, canonicalToken, debtToRepay, spokeEid, canonicalToken, block.number)
        );

        // Verify pending liquidation was created (collateral reserved)
        assertGt(positionBook.reservedCollateralOf(alice, spokeEid, canonicalToken), 0);

        // seizeAmount = debtToRepay * (10000 + 500) / 10000 = 42e18 (same asset, same price)
        uint256 expectedSeize = (debtToRepay * 10500) / 10000;

        // Simulate spoke confirming seizure
        _simulateSeizeReceipt(expectedLiqId, alice, canonicalToken, expectedSeize, bob, true);

        // Verify collateral was debited
        uint256 collateralAfter = positionBook.collateralOf(alice, spokeEid, canonicalToken);
        assertEq(collateralAfter, depositAmount - expectedSeize);

        // Reservation should be cleared
        assertEq(positionBook.reservedCollateralOf(alice, spokeEid, canonicalToken), 0);
    }

    function test_LiquidationRevertsIfHealthy() public {
        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 50e18; // Well within LTV

        _depositAndBorrow(alice, depositAmount, borrowAmount);

        // No time advance — account is healthy
        _mockOraclePrice(canonicalToken, 1e18);

        (LiquidationEngine.CollateralSlot[] memory cs, LiquidationEngine.DebtSlot[] memory ds) = _buildLiqSlots();
        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        vm.prank(bob);
        vm.expectRevert(); // NotLiquidatable
        liquidationEngine.liquidate{value: 0.1 ether}(
            alice, spokeEid, canonicalToken, 20e18, spokeEid, canonicalToken, cs, ds, bytes(""), fee
        );
    }

    function test_LiquidationWithBonus() public {
        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 80e18;

        _depositAndBorrow(alice, depositAmount, borrowAmount);
        _makePositionLiquidatable();
        _mockOraclePrice(canonicalToken, 1e18);

        (LiquidationEngine.CollateralSlot[] memory cs, LiquidationEngine.DebtSlot[] memory ds) = _buildLiqSlots();
        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        _mockLzSend();

        uint256 debtToRepay = 20e18;

        vm.prank(bob);
        liquidationEngine.liquidate{value: 0.1 ether}(
            alice, spokeEid, canonicalToken, debtToRepay, spokeEid, canonicalToken, cs, ds, bytes(""), fee
        );

        // The liquidation bonus is 500 bps (5%) from AssetRegistry config
        // seizeAmount = debtToRepay * (10000 + 500) / 10000 = 20 * 1.05 = 21e18
        bytes32 liqId = keccak256(
            abi.encodePacked(bob, alice, spokeEid, canonicalToken, debtToRepay, spokeEid, canonicalToken, block.number)
        );

        uint256 expectedSeize = (debtToRepay * 10500) / 10000;
        _simulateSeizeReceipt(liqId, alice, canonicalToken, expectedSeize, bob, true);

        // Alice lost exactly 21e18 collateral (20e18 debt value + 5% bonus)
        assertEq(positionBook.collateralOf(alice, spokeEid, canonicalToken), depositAmount - expectedSeize);
    }

    function test_LiquidationSeizeFailsOnSpoke() public {
        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 80e18;

        _depositAndBorrow(alice, depositAmount, borrowAmount);
        _makePositionLiquidatable();
        _mockOraclePrice(canonicalToken, 1e18);

        (LiquidationEngine.CollateralSlot[] memory cs, LiquidationEngine.DebtSlot[] memory ds) = _buildLiqSlots();
        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        _mockLzSend();

        uint256 debtToRepay = 40e18;
        uint256 collateralBefore = positionBook.collateralOf(alice, spokeEid, canonicalToken);

        vm.prank(bob);
        liquidationEngine.liquidate{value: 0.1 ether}(
            alice, spokeEid, canonicalToken, debtToRepay, spokeEid, canonicalToken, cs, ds, bytes(""), fee
        );

        bytes32 liqId = keccak256(
            abi.encodePacked(bob, alice, spokeEid, canonicalToken, debtToRepay, spokeEid, canonicalToken, block.number)
        );

        uint256 expectedSeize = (debtToRepay * 10500) / 10000;

        // Spoke fails to seize — success=false
        _simulateSeizeReceipt(liqId, alice, canonicalToken, expectedSeize, bob, false);

        // Collateral should NOT be debited (reservation cleared only)
        assertEq(positionBook.collateralOf(alice, spokeEid, canonicalToken), collateralBefore);
        assertEq(positionBook.reservedCollateralOf(alice, spokeEid, canonicalToken), 0);
    }

    function test_AnyoneCanLiquidate() public {
        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 80e18;

        _depositAndBorrow(alice, depositAmount, borrowAmount);
        _makePositionLiquidatable();
        _mockOraclePrice(canonicalToken, 1e18);

        (LiquidationEngine.CollateralSlot[] memory cs, LiquidationEngine.DebtSlot[] memory ds) = _buildLiqSlots();
        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        _mockLzSend();

        // Charlie (who has no special role) can liquidate
        vm.deal(charlie, 100 ether);
        vm.prank(charlie);
        liquidationEngine.liquidate{value: 0.1 ether}(
            alice, spokeEid, canonicalToken, 10e18, spokeEid, canonicalToken, cs, ds, bytes(""), fee
        );

        // Debt should be reduced
        assertLt(
            debtManager.debtOf(alice, spokeEid, canonicalToken),
            debtManager.debtOf(alice, spokeEid, canonicalToken) + 10e18
        );
    }

    function test_LiquidationConfigurableBonus() public {
        // Change the bonus to 10% (1000 bps) via AssetRegistry
        vm.prank(admin);
        assetRegistry.setCollateralConfig(
            spokeEid,
            canonicalToken,
            AssetRegistry.CollateralConfig({
                isSupported: true,
                ltvBps: 8000,
                liqThresholdBps: 8500,
                liqBonusBps: 1000, // 10% bonus
                decimals: 18,
                supplyCap: 0
            })
        );

        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 80e18;

        _depositAndBorrow(alice, depositAmount, borrowAmount);
        _makePositionLiquidatable();
        _mockOraclePrice(canonicalToken, 1e18);

        (LiquidationEngine.CollateralSlot[] memory cs, LiquidationEngine.DebtSlot[] memory ds) = _buildLiqSlots();
        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        _mockLzSend();

        uint256 debtToRepay = 20e18;

        vm.prank(bob);
        liquidationEngine.liquidate{value: 0.1 ether}(
            alice, spokeEid, canonicalToken, debtToRepay, spokeEid, canonicalToken, cs, ds, bytes(""), fee
        );

        bytes32 liqId = keccak256(
            abi.encodePacked(bob, alice, spokeEid, canonicalToken, debtToRepay, spokeEid, canonicalToken, block.number)
        );

        // With 10% bonus: seizeAmount = 20 * 1.10 = 22e18
        uint256 expectedSeize = (debtToRepay * 11000) / 10000;
        _simulateSeizeReceipt(liqId, alice, canonicalToken, expectedSeize, bob, true);

        assertEq(positionBook.collateralOf(alice, spokeEid, canonicalToken), depositAmount - expectedSeize);
    }
}
