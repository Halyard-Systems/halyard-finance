// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BaseIntegrationTest} from "./BaseIntegrationTest.t.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {SpokeController} from "../../src/spoke/SpokeController.sol";

contract DepositTest is BaseIntegrationTest {
    function test_DepositSuccess() public {
        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        vm.prank(alice);
        spokeController.depositAndNotify{value: 0.1 ether}(bytes32("test"), canonicalToken, 100e18, bytes(""), fee);

        // Check that tokens were locked in the vault for alice
        assertEq(collateralVault.lockedBalanceOf(alice, address(mockToken)), 100e18);
    }
}
