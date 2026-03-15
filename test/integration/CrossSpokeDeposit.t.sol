// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MultiSpokeBaseTest} from "../MultiSpokeBaseTest.t.sol";

contract CrossSpokeDepositTest is MultiSpokeBaseTest {
    /// @notice Deposit on ETH spoke, then deposit on ARB spoke.
    ///         Verify PositionBook tracks both (ethEid, asset) and (arbEid, asset).
    function test_DepositOnTwoSpokes() public {
        uint256 depositAmountEth = 100e18;
        uint256 depositAmountArb = 200e18;

        // Deposit on ETH spoke
        _depositAndCredit(
            spokeControllerEth, collateralVaultEth, mockTokenEth,
            alice, bytes32("dep_eth_1"), canonicalTokenEth, depositAmountEth
        );

        // Deposit on ARB spoke
        _depositAndCredit(
            spokeControllerArb, collateralVaultArb, mockTokenArb,
            alice, bytes32("dep_arb_1"), canonicalTokenArb, depositAmountArb
        );

        // Verify hub tracks both positions independently
        assertEq(positionBook.collateralOf(alice, ethEid, canonicalTokenEth), depositAmountEth);
        assertEq(positionBook.collateralOf(alice, arbEid, canonicalTokenArb), depositAmountArb);

        // Positions on other spokes should be zero
        assertEq(positionBook.collateralOf(alice, baseEid, canonicalTokenBase), 0);
    }

    /// @notice Deposit on all 3 spokes and verify independent tracking.
    function test_DepositOnAllThreeSpokes() public {
        uint256 amountEth = 50e18;
        uint256 amountArb = 150e18;
        uint256 amountBase = 300e18;

        _depositAndCredit(
            spokeControllerEth, collateralVaultEth, mockTokenEth,
            alice, bytes32("dep_eth"), canonicalTokenEth, amountEth
        );
        _depositAndCredit(
            spokeControllerArb, collateralVaultArb, mockTokenArb,
            alice, bytes32("dep_arb"), canonicalTokenArb, amountArb
        );
        _depositAndCredit(
            spokeControllerBase, collateralVaultBase, mockTokenBase,
            alice, bytes32("dep_base"), canonicalTokenBase, amountBase
        );

        assertEq(positionBook.collateralOf(alice, ethEid, canonicalTokenEth), amountEth);
        assertEq(positionBook.collateralOf(alice, arbEid, canonicalTokenArb), amountArb);
        assertEq(positionBook.collateralOf(alice, baseEid, canonicalTokenBase), amountBase);
    }

    /// @notice Two different users deposit on different spokes.
    function test_DifferentUsersDepositOnDifferentSpokes() public {
        uint256 aliceAmount = 100e18;
        uint256 bobAmount = 200e18;

        _depositAndCredit(
            spokeControllerEth, collateralVaultEth, mockTokenEth,
            alice, bytes32("alice_dep"), canonicalTokenEth, aliceAmount
        );
        _depositAndCredit(
            spokeControllerArb, collateralVaultArb, mockTokenArb,
            bob, bytes32("bob_dep"), canonicalTokenArb, bobAmount
        );

        // Alice has collateral only on ETH spoke
        assertEq(positionBook.collateralOf(alice, ethEid, canonicalTokenEth), aliceAmount);
        assertEq(positionBook.collateralOf(alice, arbEid, canonicalTokenArb), 0);

        // Bob has collateral only on ARB spoke
        assertEq(positionBook.collateralOf(bob, arbEid, canonicalTokenArb), bobAmount);
        assertEq(positionBook.collateralOf(bob, ethEid, canonicalTokenEth), 0);
    }
}
