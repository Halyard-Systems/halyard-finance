// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../../BaseTest.t.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {RiskEngine} from "../../../src/hub/RiskEngine.sol";
import {LiquidationEngine} from "../../../src/hub/LiquidationEngine.sol";

/// @notice Tests that caller-supplied collateralSlots and debtSlots cannot omit positions
/// to game health factor calculations (C-3 fix validation).
contract SlotCompletenessTest is BaseTest {
    // ---------------------------------------------------------------
    // Setup helpers
    // ---------------------------------------------------------------

    function _mockOracle() internal {
        vm.mockCall(
            mockOracle,
            abi.encodeWithSignature("getPriceE18(address)"),
            abi.encode(1000e18, block.timestamp)
        );
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
    // RiskEngine: Borrower omits debt slots
    // ---------------------------------------------------------------

    function test_RiskEngine_RevertsBorrowWithEmptyDebtSlots_WhenDebtExists() public {
        _mockOracle();

        // Alice has collateral
        _creditCollateral(alice, 1, address(0x123), 100e18);

        // Alice already has debt (mint directly via DebtManager)
        _mintDebt(alice, 1, address(0x123), 50e18);

        // Alice tries to borrow more with empty debtSlots to hide existing debt
        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        RiskEngine.DebtSlot[] memory emptyDebtSlots = new RiskEngine.DebtSlot[](0);

        vm.prank(address(hubRouter));
        vm.expectRevert(
            abi.encodeWithSelector(RiskEngine.IncompleteDebtSlots.selector, uint32(1), address(0x123))
        );
        riskEngine.validateAndCreateBorrow(
            bytes32(keccak256("exploit_borrow")),
            alice, 1, address(0x123), 10e18, alice,
            collateralSlots, emptyDebtSlots
        );
    }

    function test_RiskEngine_RevertsBorrowWithPartialDebtSlots() public {
        _mockOracle();
        // Additional oracle mock for second asset
        vm.mockCall(
            mockOracle,
            abi.encodeWithSignature("getPriceE18(address)", address(0x124)),
            abi.encode(2000e18, block.timestamp)
        );

        // Alice has collateral
        _creditCollateral(alice, 1, address(0x123), 1000e18);

        // Alice has debt on TWO different assets
        _mintDebt(alice, 1, address(0x123), 50e18);
        _mintDebt(alice, 2, address(0x124), 30e18);

        // Alice tries to borrow including only one of her two debt positions
        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        RiskEngine.DebtSlot[] memory partialDebtSlots = new RiskEngine.DebtSlot[](1);
        partialDebtSlots[0] = RiskEngine.DebtSlot({eid: 1, asset: address(0x123)});
        // Missing: (2, 0x124)

        vm.prank(address(hubRouter));
        vm.expectRevert(
            abi.encodeWithSelector(RiskEngine.IncompleteDebtSlots.selector, uint32(2), address(0x124))
        );
        riskEngine.validateAndCreateBorrow(
            bytes32(keccak256("exploit_borrow_partial")),
            alice, 1, address(0x123), 10e18, alice,
            collateralSlots, partialDebtSlots
        );
    }

    function test_RiskEngine_AllowsEmptyDebtSlots_WhenNoDebtExists() public {
        _mockOracle();

        // Alice has collateral but no debt — empty debtSlots is fine
        _creditCollateral(alice, 1, address(0x123), 100e18);

        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        RiskEngine.DebtSlot[] memory emptyDebtSlots = new RiskEngine.DebtSlot[](0);

        vm.prank(address(hubRouter));
        // Should succeed — no debt to omit
        riskEngine.validateAndCreateBorrow(
            bytes32(keccak256("valid_borrow")),
            alice, 1, address(0x123), 10e18, alice,
            collateralSlots, emptyDebtSlots
        );
    }

    function test_RiskEngine_AllowsSuperset_DebtSlots() public {
        _mockOracle();

        // Alice has collateral and one debt position
        _creditCollateral(alice, 1, address(0x123), 1000e18);
        _mintDebt(alice, 1, address(0x123), 10e18);

        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        // Provide more slots than needed (includes the required one) — should be fine
        RiskEngine.DebtSlot[] memory supersetDebtSlots = new RiskEngine.DebtSlot[](2);
        supersetDebtSlots[0] = RiskEngine.DebtSlot({eid: 1, asset: address(0x123)});
        supersetDebtSlots[1] = RiskEngine.DebtSlot({eid: 2, asset: address(0x124)});

        vm.prank(address(hubRouter));
        riskEngine.validateAndCreateBorrow(
            bytes32(keccak256("valid_superset_borrow")),
            alice, 1, address(0x123), 5e18, alice,
            collateralSlots, supersetDebtSlots
        );
    }

    // ---------------------------------------------------------------
    // RiskEngine: Borrower omits collateral slots
    // ---------------------------------------------------------------

    function test_RiskEngine_RevertsWithdrawWithEmptyCollateralSlots_WhenCollateralExists() public {
        _mockOracle();

        // Alice has collateral
        _creditCollateral(alice, 1, address(0x123), 100e18);

        RiskEngine.CollateralSlot[] memory emptyCollateralSlots = new RiskEngine.CollateralSlot[](0);
        RiskEngine.DebtSlot[] memory debtSlots = new RiskEngine.DebtSlot[](0);

        vm.prank(address(hubRouter));
        vm.expectRevert(
            abi.encodeWithSelector(RiskEngine.IncompleteCollateralSlots.selector, uint32(1), address(0x123))
        );
        riskEngine.validateAndCreateWithdraw(
            bytes32(keccak256("exploit_withdraw")),
            alice, 1, address(0x123), 10e18, alice,
            emptyCollateralSlots, debtSlots
        );
    }

    function test_RiskEngine_RevertsWithPartialCollateralSlots() public {
        _mockOracle();
        vm.mockCall(
            mockOracle,
            abi.encodeWithSignature("getPriceE18(address)", address(0x124)),
            abi.encode(2000e18, block.timestamp)
        );

        // Alice has collateral on TWO chains
        _creditCollateral(alice, 1, address(0x123), 100e18);
        _creditCollateral(alice, 2, address(0x124), 50e18);

        // Only includes one collateral slot, omitting the second
        RiskEngine.CollateralSlot[] memory partialSlots = new RiskEngine.CollateralSlot[](1);
        partialSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        RiskEngine.DebtSlot[] memory debtSlots = new RiskEngine.DebtSlot[](0);

        vm.prank(address(hubRouter));
        vm.expectRevert(
            abi.encodeWithSelector(RiskEngine.IncompleteCollateralSlots.selector, uint32(2), address(0x124))
        );
        riskEngine.validateAndCreateWithdraw(
            bytes32(keccak256("exploit_partial_collateral")),
            alice, 1, address(0x123), 10e18, alice,
            partialSlots, debtSlots
        );
    }

    function test_RiskEngine_AllowsEmptyCollateralSlots_WhenNoCollateralExists() public {
        _mockOracle();

        // No collateral for alice — empty slots should be fine for accountData
        RiskEngine.CollateralSlot[] memory emptySlots = new RiskEngine.CollateralSlot[](0);
        RiskEngine.DebtSlot[] memory emptyDebtSlots = new RiskEngine.DebtSlot[](0);

        (uint256 cv, uint256 bp, uint256 lv, uint256 dv, uint256 hf) =
            riskEngine.accountData(alice, emptySlots, emptyDebtSlots);

        assertEq(cv, 0);
        assertEq(bp, 0);
        assertEq(lv, 0);
        assertEq(dv, 0);
        assertEq(hf, type(uint256).max);
    }

    // ---------------------------------------------------------------
    // RiskEngine: canBorrow view also validates
    // ---------------------------------------------------------------

    function test_RiskEngine_canBorrowRevertsWithIncompleteDebtSlots() public {
        _mockOracle();

        _creditCollateral(alice, 1, address(0x123), 1000e18);
        _mintDebt(alice, 1, address(0x123), 50e18);

        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        RiskEngine.DebtSlot[] memory emptyDebtSlots = new RiskEngine.DebtSlot[](0);

        vm.expectRevert(
            abi.encodeWithSelector(RiskEngine.IncompleteDebtSlots.selector, uint32(1), address(0x123))
        );
        riskEngine.canBorrow(alice, 1, address(0x123), 10e18, collateralSlots, emptyDebtSlots);
    }

    function test_RiskEngine_canWithdrawRevertsWithIncompleteCollateralSlots() public {
        _mockOracle();

        _creditCollateral(alice, 1, address(0x123), 100e18);
        _creditCollateral(alice, 2, address(0x124), 50e18);

        RiskEngine.CollateralSlot[] memory partialSlots = new RiskEngine.CollateralSlot[](1);
        partialSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        RiskEngine.DebtSlot[] memory debtSlots = new RiskEngine.DebtSlot[](0);

        vm.expectRevert(
            abi.encodeWithSelector(RiskEngine.IncompleteCollateralSlots.selector, uint32(2), address(0x124))
        );
        riskEngine.canWithdraw(alice, 1, address(0x123), 10e18, partialSlots, debtSlots);
    }

    // ---------------------------------------------------------------
    // RiskEngine: accountData view also validates
    // ---------------------------------------------------------------

    function test_RiskEngine_accountDataRevertsWithIncompleteSlots() public {
        _mockOracle();

        _creditCollateral(alice, 1, address(0x123), 100e18);
        _mintDebt(alice, 1, address(0x123), 50e18);

        // Missing collateral slot
        RiskEngine.CollateralSlot[] memory emptyCollateral = new RiskEngine.CollateralSlot[](0);
        RiskEngine.DebtSlot[] memory debtSlots = new RiskEngine.DebtSlot[](1);
        debtSlots[0] = RiskEngine.DebtSlot({eid: 1, asset: address(0x123)});

        vm.expectRevert(
            abi.encodeWithSelector(RiskEngine.IncompleteCollateralSlots.selector, uint32(1), address(0x123))
        );
        riskEngine.accountData(alice, emptyCollateral, debtSlots);

        // Missing debt slot
        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});
        RiskEngine.DebtSlot[] memory emptyDebt = new RiskEngine.DebtSlot[](0);

        vm.expectRevert(
            abi.encodeWithSelector(RiskEngine.IncompleteDebtSlots.selector, uint32(1), address(0x123))
        );
        riskEngine.accountData(alice, collateralSlots, emptyDebt);
    }

    // ---------------------------------------------------------------
    // LiquidationEngine: Liquidator omits collateral slots
    // ---------------------------------------------------------------

    function test_LiquidationEngine_RevertsWithEmptyCollateralSlots_WhenCollateralExists() public {
        _mockOracle();

        // Alice has collateral and debt
        _creditCollateral(alice, 1, address(0x123), 100e18);
        _mintDebt(alice, 1, address(0x123), 90e18);

        // Liquidator tries with empty collateral slots (would make health=0, always liquidatable)
        LiquidationEngine.CollateralSlot[] memory emptyCollateral = new LiquidationEngine.CollateralSlot[](0);
        LiquidationEngine.DebtSlot[] memory debtSlots = new LiquidationEngine.DebtSlot[](1);
        debtSlots[0] = LiquidationEngine.DebtSlot({eid: 1, asset: address(0x123)});

        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(LiquidationEngine.IncompleteCollateralSlots.selector, uint32(1), address(0x123))
        );
        liquidationEngine.liquidate(
            alice, 1, address(0x123), 50e18, 1, address(0x123),
            emptyCollateral, debtSlots, bytes(""), fee
        );
    }

    function test_LiquidationEngine_RevertsWithEmptyDebtSlots_WhenDebtExists() public {
        _mockOracle();

        _creditCollateral(alice, 1, address(0x123), 100e18);
        _mintDebt(alice, 1, address(0x123), 90e18);

        LiquidationEngine.CollateralSlot[] memory collateralSlots = new LiquidationEngine.CollateralSlot[](1);
        collateralSlots[0] = LiquidationEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        // Empty debt slots would make debtValue=0, health=max, blocking liquidation
        // But validation should revert before that
        LiquidationEngine.DebtSlot[] memory emptyDebt = new LiquidationEngine.DebtSlot[](0);

        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(LiquidationEngine.IncompleteDebtSlots.selector, uint32(1), address(0x123))
        );
        liquidationEngine.liquidate(
            alice, 1, address(0x123), 50e18, 1, address(0x123),
            collateralSlots, emptyDebt, bytes(""), fee
        );
    }

    function test_LiquidationEngine_RevertsWithPartialCollateralSlots() public {
        _mockOracle();
        vm.mockCall(
            mockOracle,
            abi.encodeWithSignature("getPriceE18(address)", address(0x124)),
            abi.encode(2000e18, block.timestamp)
        );

        // Alice has collateral on two chains
        _creditCollateral(alice, 1, address(0x123), 100e18);
        _creditCollateral(alice, 2, address(0x124), 50e18);
        _mintDebt(alice, 1, address(0x123), 90e18);

        // Only includes one collateral position (omitting the bigger one to reduce health)
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
            alice, 1, address(0x123), 50e18, 1, address(0x123),
            partialCollateral, debtSlots, bytes(""), fee
        );
    }

    // ---------------------------------------------------------------
    // DebtManager: debt asset tracking lifecycle
    // ---------------------------------------------------------------

    function test_DebtManager_TracksDebtAssets() public {
        _mockOracle();

        // No debt initially
        assertEq(debtManager.debtAssetsOf(alice).length, 0);

        // Mint debt
        _mintDebt(alice, 1, address(0x123), 50e18);
        assertEq(debtManager.debtAssetsOf(alice).length, 1);
        assertEq(debtManager.debtAssetsOf(alice)[0].eid, 1);
        assertEq(debtManager.debtAssetsOf(alice)[0].asset, address(0x123));

        // Mint more of same — should NOT duplicate
        _mintDebt(alice, 1, address(0x123), 25e18);
        assertEq(debtManager.debtAssetsOf(alice).length, 1);

        // Mint different asset
        _mintDebt(alice, 2, address(0x124), 30e18);
        assertEq(debtManager.debtAssetsOf(alice).length, 2);
    }

    function test_DebtManager_RemovesDebtAssetOnFullRepay() public {
        _mockOracle();

        _mintDebt(alice, 1, address(0x123), 50e18);
        assertEq(debtManager.debtAssetsOf(alice).length, 1);

        // Full repay (burn all debt)
        vm.prank(address(hubRouter));
        debtManager.burnDebt(alice, 1, address(0x123), 50e18);
        assertEq(debtManager.debtAssetsOf(alice).length, 0);
    }

    function test_DebtManager_KeepsDebtAssetOnPartialRepay() public {
        _mockOracle();

        _mintDebt(alice, 1, address(0x123), 50e18);
        assertEq(debtManager.debtAssetsOf(alice).length, 1);

        // Partial repay
        vm.prank(address(hubRouter));
        debtManager.burnDebt(alice, 1, address(0x123), 25e18);
        assertEq(debtManager.debtAssetsOf(alice).length, 1);
    }

    // ---------------------------------------------------------------
    // RiskEngine: successful flow with complete slots
    // ---------------------------------------------------------------

    function test_RiskEngine_BorrowSucceedsWithCompleteSlots() public {
        _mockOracle();

        _creditCollateral(alice, 1, address(0x123), 1000e18);
        _mintDebt(alice, 1, address(0x123), 10e18);

        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        RiskEngine.DebtSlot[] memory debtSlots = new RiskEngine.DebtSlot[](1);
        debtSlots[0] = RiskEngine.DebtSlot({eid: 1, asset: address(0x123)});

        vm.prank(address(hubRouter));
        // Should succeed — all positions included
        riskEngine.validateAndCreateBorrow(
            bytes32(keccak256("valid_complete_borrow")),
            alice, 1, address(0x123), 5e18, alice,
            collateralSlots, debtSlots
        );
    }
}
