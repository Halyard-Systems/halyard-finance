// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseIntegrationTest} from "./BaseIntegrationTest.t.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {IRiskEngine} from "../../src/interfaces/IRiskEngine.sol";

contract WithdrawTest is BaseIntegrationTest {
    function test_WithdrawSuccess() public {
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 50e18;

        // Mock oracle: $1 per token for all collateral/debt pricing
        _mockOraclePrice(canonicalToken, 1e18);

        // First deposit collateral (prerequisite for withdrawal)
        _depositAndCredit(alice, bytes32("deposit_1"), canonicalToken, depositAmount);

        // Build collateral slots (alice has one position: canonicalToken on spokeEid)
        IRiskEngine.CollateralSlot[] memory collateralSlots = new IRiskEngine.CollateralSlot[](1);
        collateralSlots[0] = IRiskEngine.CollateralSlot({eid: spokeEid, asset: canonicalToken});

        // No debt positions
        IRiskEngine.DebtSlot[] memory debtSlots = new IRiskEngine.DebtSlot[](0);

        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        // Mock LZ send for the withdraw command
        _mockLzSend();

        // User requests withdrawal via HubRouter
        vm.prank(alice);
        hubRouter.withdrawAndNotify{value: 0.1 ether}(
            spokeEid, canonicalToken, withdrawAmount, collateralSlots, debtSlots, bytes(""), fee
        );

        // Verify intermediate state: collateral reserved, pending withdraw created
        assertEq(positionBook.collateralOf(alice, spokeEid, canonicalToken), depositAmount);
        assertEq(positionBook.reservedCollateralOf(alice, spokeEid, canonicalToken), withdrawAmount);
        assertEq(positionBook.availableCollateralOf(alice, spokeEid, canonicalToken), depositAmount - withdrawAmount);

        // Simulate spoke confirming the withdrawal (WITHDRAW_RELEASED receipt)
        _simulateWithdrawReceipt(alice, canonicalToken, withdrawAmount, true);

        // Verify final state: collateral debited, reservation cleared, no pending
        assertEq(positionBook.collateralOf(alice, spokeEid, canonicalToken), depositAmount - withdrawAmount);
        assertEq(positionBook.reservedCollateralOf(alice, spokeEid, canonicalToken), 0);
        assertEq(positionBook.availableCollateralOf(alice, spokeEid, canonicalToken), depositAmount - withdrawAmount);
    }
}
