// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseIntegrationTest} from "./BaseIntegrationTest.t.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

contract WithdrawTest is BaseIntegrationTest {
    function test_WithdrawSuccess() public {
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 50e18;

        // First deposit collateral (prerequisite for withdrawal)
        // forge-lint: disable-next-line(unsafe-typecast)
        _depositAndCredit(alice, bytes32("deposit_1"), canonicalToken, depositAmount);

        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        // User requests withdrawal via HubRouter (not HubController)
        vm.prank(alice);
        hubRouter.withdrawAndNotify{value: 0.1 ether}(spokeEid, canonicalToken, withdrawAmount, bytes(""), fee);
    }
}
