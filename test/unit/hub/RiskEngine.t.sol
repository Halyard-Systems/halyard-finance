// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../../BaseTest.t.sol";
import {RiskEngine} from "../../../src/hub/RiskEngine.sol";

// TODO: need more tests, and the tests here need review
contract RiskEngineTest is BaseTest {
    function test_AccountData() public {
        // Mock the oracle's getPriceE18 function to return a price
        vm.mockCall(
            mockOracle,
            abi.encodeWithSignature("getPriceE18(address)"),
            abi.encode(1e18, block.timestamp) // price = 1e18 (1 USD), timestamp = now
        );

        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        // Create debt slots array (empty for this test)
        RiskEngine.DebtSlot[] memory debtSlots = new RiskEngine.DebtSlot[](0);

        vm.prank(address(hubController));
        (
            uint256 collateralValueE18,
            uint256 borrowPowerE18,
            uint256 liquidationValueE18,
            uint256 debtValueE18,
            uint256 healthFactorE18
        ) = riskEngine.accountData(alice, collateralSlots, debtSlots);

        assertEq(collateralValueE18, 0);
        assertEq(borrowPowerE18, 0);
        assertEq(liquidationValueE18, 0);
        assertEq(debtValueE18, 0);
        assertEq(healthFactorE18, type(uint256).max);
    }

    function test_canBorrow() public {
        // Mock the oracle's getPriceE18 function to return a price
        vm.mockCall(
            mockOracle,
            abi.encodeWithSignature("getPriceE18(address)"),
            abi.encode(1000e18, block.timestamp) // price = 1e18 (1 USD), timestamp = now
        );

        // Credit collateral to alice (must prank as hubController which has ROLE_HUB_CONTROLLER)
        vm.prank(address(hubController));
        positionBook.creditCollateral(alice, 1, address(0x123), 10e18); // 10 tokens

        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        // Create debt slots array (empty for this test)
        RiskEngine.DebtSlot[] memory debtSlots = new RiskEngine.DebtSlot[](0);

        vm.prank(address(hubController));
        (bool ok, uint256 nextHealthFactorE18) =
            riskEngine.canBorrow(alice, 1, address(0x123), 100, collateralSlots, debtSlots);

        assertEq(ok, true);
        assertEq(nextHealthFactorE18, 80000000000000000e18);
    }

    // TODO: test for values
    function test_canWithdraw() public {
        // Mock the oracle's getPriceE18 function to return a price
        vm.mockCall(
            mockOracle,
            abi.encodeWithSignature("getPriceE18(address)"),
            abi.encode(1000e18, block.timestamp) // price = 1e18 (1 USD), timestamp = now
        );

        // Credit collateral to alice (must prank as hubController which has ROLE_HUB_CONTROLLER)
        vm.prank(address(hubController));
        positionBook.creditCollateral(alice, 1, address(0x123), 10e18); // 10 tokens

        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        // Create debt slots array (empty for this test)
        RiskEngine.DebtSlot[] memory debtSlots = new RiskEngine.DebtSlot[](0);

        vm.prank(address(hubController));
        (bool ok, uint256 nextHealthFactorE18) =
            riskEngine.canWithdraw(alice, 1, address(0x123), 10e18, collateralSlots, debtSlots);

        assertEq(ok, true);
        assertEq(nextHealthFactorE18, type(uint256).max);
    }

    function test_validateAndCreateBorrow() public {
        // Mock the oracle's getPriceE18 function to return a price
        vm.mockCall(
            mockOracle,
            abi.encodeWithSignature("getPriceE18(address)"),
            abi.encode(1000e18, block.timestamp) // price = 1e18 (1 USD), timestamp = now
        );

        // Credit collateral to alice (must prank as hubController which has ROLE_HUB_CONTROLLER)
        vm.prank(address(hubController));
        positionBook.creditCollateral(alice, 1, address(0x123), 100000e18); // 100000 tokens

        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        // Create debt slots array (empty for this test)
        RiskEngine.DebtSlot[] memory debtSlots = new RiskEngine.DebtSlot[](0);

        vm.prank(address(hubRouter));
        riskEngine.validateAndCreateBorrow(
            bytes32(keccak256("test_validateAndCreateBorrow")),
            alice,
            1,
            address(0x123),
            10e18,
            address(0x123),
            collateralSlots,
            debtSlots
        );

        assertEq(positionBook.reservedDebtOf(alice, 1, address(0x123)), 10e18);
    }

    function test_validateAndCreateWithdraw() public {
        // Mock the oracle's getPriceE18 function to return a price
        vm.mockCall(
            mockOracle,
            abi.encodeWithSignature("getPriceE18(address)"),
            abi.encode(1000e18, block.timestamp) // price = 1000 USD, timestamp = now
        );

        // Credit collateral to alice (must prank as hubController which has ROLE_HUB_CONTROLLER)
        vm.prank(address(hubController));
        positionBook.creditCollateral(alice, 1, address(0x123), 100000e18); // 100000 tokens

        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        // Create debt slots array (empty for this test)
        RiskEngine.DebtSlot[] memory debtSlots = new RiskEngine.DebtSlot[](0);

        vm.prank(address(hubRouter));
        riskEngine.validateAndCreateWithdraw(
            bytes32(keccak256("test_validateAndCreateWithdraw")),
            alice,
            1,
            address(0x123),
            10e18,
            address(0x123),
            collateralSlots,
            debtSlots
        );

        assertEq(positionBook.reservedCollateralOf(alice, 1, address(0x123)), 10e18);
    }

    function test_validateAndCreateWithdraw_TwoCollateralAssets() public {
        // Asset A at $1000, Asset B at $2500 — different prices to verify
        // the oracle is called per-asset and values are summed correctly
        vm.mockCall(
            mockOracle,
            abi.encodeWithSignature("getPriceE18(address)", address(0x123)),
            abi.encode(1000e18, block.timestamp)
        );
        vm.mockCall(
            mockOracle,
            abi.encodeWithSignature("getPriceE18(address)", address(0x124)),
            abi.encode(2500e18, block.timestamp)
        );

        // Credit two collateral assets on different chains
        vm.prank(address(hubController));
        positionBook.creditCollateral(alice, 1, address(0x123), 50e18); // 50 tokens @ $1000 = $50,000
        vm.prank(address(hubController));
        positionBook.creditCollateral(alice, 2, address(0x124), 20e18); // 20 tokens @ $2500 = $50,000

        // Both collateral positions included in the slots
        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](2);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});
        collateralSlots[1] = RiskEngine.CollateralSlot({eid: 2, asset: address(0x124)});

        RiskEngine.DebtSlot[] memory debtSlots = new RiskEngine.DebtSlot[](0);

        // Withdraw 30 tokens of asset A (leaves 20 tokens = $20,000 of A + $50,000 of B)
        vm.prank(address(hubRouter));
        riskEngine.validateAndCreateWithdraw(
            bytes32(keccak256("test_two_assets")), alice, 1, address(0x123), 30e18, alice, collateralSlots, debtSlots
        );

        // Only asset A on chain 1 should be reserved
        assertEq(positionBook.reservedCollateralOf(alice, 1, address(0x123)), 30e18);
        assertEq(positionBook.availableCollateralOf(alice, 1, address(0x123)), 20e18);

        // Asset B untouched
        assertEq(positionBook.reservedCollateralOf(alice, 2, address(0x124)), 0);
        assertEq(positionBook.availableCollateralOf(alice, 2, address(0x124)), 20e18);
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
    // Slot completeness: Borrower omits debt slots
    // ---------------------------------------------------------------

    function test_RevertsBorrowWithEmptyDebtSlots_WhenDebtExists() public {
        _mockOracle();

        _creditCollateral(alice, 1, address(0x123), 100e18);
        _mintDebt(alice, 1, address(0x123), 50e18);

        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        RiskEngine.DebtSlot[] memory emptyDebtSlots = new RiskEngine.DebtSlot[](0);

        vm.prank(address(hubRouter));
        vm.expectRevert(abi.encodeWithSelector(RiskEngine.IncompleteDebtSlots.selector, uint32(1), address(0x123)));
        riskEngine.validateAndCreateBorrow(
            bytes32(keccak256("exploit_borrow")),
            alice,
            1,
            address(0x123),
            10e18,
            alice,
            collateralSlots,
            emptyDebtSlots
        );
    }

    function test_RevertsBorrowWithPartialDebtSlots() public {
        _mockOracle();
        vm.mockCall(
            mockOracle,
            abi.encodeWithSignature("getPriceE18(address)", address(0x124)),
            abi.encode(2000e18, block.timestamp)
        );

        _creditCollateral(alice, 1, address(0x123), 1000e18);
        _mintDebt(alice, 1, address(0x123), 50e18);
        _mintDebt(alice, 2, address(0x124), 30e18);

        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        RiskEngine.DebtSlot[] memory partialDebtSlots = new RiskEngine.DebtSlot[](1);
        partialDebtSlots[0] = RiskEngine.DebtSlot({eid: 1, asset: address(0x123)});

        vm.prank(address(hubRouter));
        vm.expectRevert(abi.encodeWithSelector(RiskEngine.IncompleteDebtSlots.selector, uint32(2), address(0x124)));
        riskEngine.validateAndCreateBorrow(
            bytes32(keccak256("exploit_borrow_partial")),
            alice,
            1,
            address(0x123),
            10e18,
            alice,
            collateralSlots,
            partialDebtSlots
        );
    }

    function test_AllowsEmptyDebtSlots_WhenNoDebtExists() public {
        _mockOracle();

        _creditCollateral(alice, 1, address(0x123), 100e18);

        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        RiskEngine.DebtSlot[] memory emptyDebtSlots = new RiskEngine.DebtSlot[](0);

        vm.prank(address(hubRouter));
        riskEngine.validateAndCreateBorrow(
            bytes32(keccak256("valid_borrow")), alice, 1, address(0x123), 10e18, alice, collateralSlots, emptyDebtSlots
        );
    }

    function test_AllowsSuperset_DebtSlots() public {
        _mockOracle();

        _creditCollateral(alice, 1, address(0x123), 1000e18);
        _mintDebt(alice, 1, address(0x123), 10e18);

        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        RiskEngine.DebtSlot[] memory supersetDebtSlots = new RiskEngine.DebtSlot[](2);
        supersetDebtSlots[0] = RiskEngine.DebtSlot({eid: 1, asset: address(0x123)});
        supersetDebtSlots[1] = RiskEngine.DebtSlot({eid: 2, asset: address(0x124)});

        vm.prank(address(hubRouter));
        riskEngine.validateAndCreateBorrow(
            bytes32(keccak256("valid_superset_borrow")),
            alice,
            1,
            address(0x123),
            5e18,
            alice,
            collateralSlots,
            supersetDebtSlots
        );
    }

    // ---------------------------------------------------------------
    // Slot completeness: Borrower omits collateral slots
    // ---------------------------------------------------------------

    function test_RevertsWithdrawWithEmptyCollateralSlots_WhenCollateralExists() public {
        _mockOracle();

        _creditCollateral(alice, 1, address(0x123), 100e18);

        RiskEngine.CollateralSlot[] memory emptyCollateralSlots = new RiskEngine.CollateralSlot[](0);
        RiskEngine.DebtSlot[] memory debtSlots = new RiskEngine.DebtSlot[](0);

        vm.prank(address(hubRouter));
        vm.expectRevert(
            abi.encodeWithSelector(RiskEngine.IncompleteCollateralSlots.selector, uint32(1), address(0x123))
        );
        riskEngine.validateAndCreateWithdraw(
            bytes32(keccak256("exploit_withdraw")),
            alice,
            1,
            address(0x123),
            10e18,
            alice,
            emptyCollateralSlots,
            debtSlots
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

        RiskEngine.CollateralSlot[] memory partialSlots = new RiskEngine.CollateralSlot[](1);
        partialSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        RiskEngine.DebtSlot[] memory debtSlots = new RiskEngine.DebtSlot[](0);

        vm.prank(address(hubRouter));
        vm.expectRevert(
            abi.encodeWithSelector(RiskEngine.IncompleteCollateralSlots.selector, uint32(2), address(0x124))
        );
        riskEngine.validateAndCreateWithdraw(
            bytes32(keccak256("exploit_partial_collateral")),
            alice,
            1,
            address(0x123),
            10e18,
            alice,
            partialSlots,
            debtSlots
        );
    }

    function test_AllowsEmptyCollateralSlots_WhenNoCollateralExists() public {
        _mockOracle();

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
    // Slot completeness: canBorrow / canWithdraw views
    // ---------------------------------------------------------------

    function test_canBorrowRevertsWithIncompleteDebtSlots() public {
        _mockOracle();

        _creditCollateral(alice, 1, address(0x123), 1000e18);
        _mintDebt(alice, 1, address(0x123), 50e18);

        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        RiskEngine.DebtSlot[] memory emptyDebtSlots = new RiskEngine.DebtSlot[](0);

        vm.expectRevert(abi.encodeWithSelector(RiskEngine.IncompleteDebtSlots.selector, uint32(1), address(0x123)));
        riskEngine.canBorrow(alice, 1, address(0x123), 10e18, collateralSlots, emptyDebtSlots);
    }

    function test_canWithdrawRevertsWithIncompleteCollateralSlots() public {
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
    // Slot completeness: accountData view
    // ---------------------------------------------------------------

    function test_accountDataRevertsWithIncompleteSlots() public {
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

        vm.expectRevert(abi.encodeWithSelector(RiskEngine.IncompleteDebtSlots.selector, uint32(1), address(0x123)));
        riskEngine.accountData(alice, collateralSlots, emptyDebt);
    }

    // ---------------------------------------------------------------
    // Duplicate debt slots
    // ---------------------------------------------------------------

    function test_RevertsDuplicateDebtSlots() public {
        _mockOracle();

        _creditCollateral(alice, 1, address(0x123), 1000e18);
        _mintDebt(alice, 1, address(0x123), 50e18);

        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        RiskEngine.DebtSlot[] memory duplicateDebtSlots = new RiskEngine.DebtSlot[](3);
        duplicateDebtSlots[0] = RiskEngine.DebtSlot({eid: 1, asset: address(0x123)});
        duplicateDebtSlots[1] = RiskEngine.DebtSlot({eid: 1, asset: address(0x123)});
        duplicateDebtSlots[2] = RiskEngine.DebtSlot({eid: 1, asset: address(0x123)});

        vm.expectRevert(abi.encodeWithSelector(RiskEngine.DuplicateDebtSlot.selector, uint32(1), address(0x123)));
        riskEngine.accountData(alice, collateralSlots, duplicateDebtSlots);
    }

    function test_RevertsDuplicateDebtSlots_canBorrow() public {
        _mockOracle();

        _creditCollateral(alice, 1, address(0x123), 1000e18);
        _mintDebt(alice, 1, address(0x123), 50e18);

        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        RiskEngine.DebtSlot[] memory duplicateDebtSlots = new RiskEngine.DebtSlot[](2);
        duplicateDebtSlots[0] = RiskEngine.DebtSlot({eid: 1, asset: address(0x123)});
        duplicateDebtSlots[1] = RiskEngine.DebtSlot({eid: 1, asset: address(0x123)});

        vm.expectRevert(abi.encodeWithSelector(RiskEngine.DuplicateDebtSlot.selector, uint32(1), address(0x123)));
        riskEngine.canBorrow(alice, 1, address(0x123), 10e18, collateralSlots, duplicateDebtSlots);
    }

    // ---------------------------------------------------------------
    // Slot completeness: successful flow
    // ---------------------------------------------------------------

    function test_BorrowSucceedsWithCompleteSlots() public {
        _mockOracle();

        _creditCollateral(alice, 1, address(0x123), 1000e18);
        _mintDebt(alice, 1, address(0x123), 10e18);

        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        RiskEngine.DebtSlot[] memory debtSlots = new RiskEngine.DebtSlot[](1);
        debtSlots[0] = RiskEngine.DebtSlot({eid: 1, asset: address(0x123)});

        vm.prank(address(hubRouter));
        riskEngine.validateAndCreateBorrow(
            bytes32(keccak256("valid_complete_borrow")),
            alice,
            1,
            address(0x123),
            5e18,
            alice,
            collateralSlots,
            debtSlots
        );
    }
}
