// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BaseHubTest} from "./BaseHubTest.t.sol";
import {RiskEngine} from "../../../src/hub/RiskEngine.sol";

import {console} from "forge-std/console.sol";

// TODO: need more tests, and the tests here need review
contract RiskEngineTest is BaseHubTest {
    function test_AccountData() public {
        // Create a mock oracle address
        address mockOracle = makeAddr("oracle");
        // TODO: replace with real DebtManager
        address tempDebManager = makeAddr("debtManager");

        // Mock the oracle's getPriceE18 function to return a price
        vm.mockCall(
            mockOracle,
            abi.encodeWithSignature("getPriceE18(address)"),
            abi.encode(1e18, block.timestamp) // price = 1e18 (1 USD), timestamp = now
        );

        // Set RiskEngine dependencies
        riskEngine.setDependencies(
            address(positionBook),
            address(tempDebManager), // or mock address if DebtManager not deployed
            address(assetRegistry),
            mockOracle
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
        // Create a mock oracle address
        address mockOracle = makeAddr("oracle");
        // TODO: replace with real DebtManager
        address tempDebManager = makeAddr("debtManager");

        // Mock the oracle's getPriceE18 function to return a price
        vm.mockCall(
            mockOracle,
            abi.encodeWithSignature("getPriceE18(address)"),
            abi.encode(1000e18, block.timestamp) // price = 1e18 (1 USD), timestamp = now
        );

        // Set RiskEngine dependencies
        riskEngine.setDependencies(
            address(positionBook),
            address(tempDebManager), // or mock address if DebtManager not deployed
            address(assetRegistry),
            mockOracle
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

        // Set RiskEngine dependencies
        // riskEngine.setDependencies(
        //     address(positionBook),
        //     address(tempDebtManager), // or mock address if DebtManager not deployed
        //     address(assetRegistry),
        //     mockOracle
        // );

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

        // Set RiskEngine dependencies
        riskEngine.setDependencies(
            address(positionBook),
            address(tempDebtManager), // or mock address if DebtManager not deployed
            address(assetRegistry),
            mockOracle
        );

        // Credit collateral to alice (must prank as hubController which has ROLE_HUB_CONTROLLER)
        vm.prank(address(hubController));
        positionBook.creditCollateral(alice, 1, address(0x123), 100000e18); // 100000 tokens

        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        // Create debt slots array (empty for this test)
        RiskEngine.DebtSlot[] memory debtSlots = new RiskEngine.DebtSlot[](0);

        vm.prank(router);
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

        // Set RiskEngine dependencies
        // riskEngine.setDependencies(
        //     address(positionBook),
        //     address(tempDebtManager),
        //     address(assetRegistry),
        //     mockOracle
        // );

        // Credit collateral to alice (must prank as hubController which has ROLE_HUB_CONTROLLER)
        vm.prank(address(hubController));
        positionBook.creditCollateral(alice, 1, address(0x123), 100000e18); // 100000 tokens

        RiskEngine.CollateralSlot[] memory collateralSlots = new RiskEngine.CollateralSlot[](1);
        collateralSlots[0] = RiskEngine.CollateralSlot({eid: 1, asset: address(0x123)});

        // Create debt slots array (empty for this test)
        RiskEngine.DebtSlot[] memory debtSlots = new RiskEngine.DebtSlot[](0);

        vm.prank(router);
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
}
