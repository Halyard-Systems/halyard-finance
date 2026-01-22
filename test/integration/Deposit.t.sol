// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {BaseIntegrationTest} from "./BaseIntegrationTest.t.sol";
import {MessagingFee, Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {SpokeController} from "../../src/spoke/SpokeController.sol";

contract DepositTest is BaseIntegrationTest {
    function test_DepositSuccess() public {
        vm.mockCall(
            address(mockLzEndpoint),
            abi.encodeWithSignature("send((uint32,bytes32,bytes,bytes,bool),address)"),
            abi.encode(
                bytes32(uint256(1)), // guid
                uint64(1), // nonce
                MessagingFee({nativeFee: 0, lzTokenFee: 0}) // Correct struct
            )
        );

        uint256 depositAmount = 100e18;

        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        vm.prank(alice);
        spokeController.depositAndNotify{value: 0.1 ether}(
            bytes32("test"), canonicalToken, depositAmount, bytes(""), fee
        );

        assertEq(collateralVault.lockedBalanceOf(alice, address(mockToken)), depositAmount);

        // Build the correct message payload that matches what the spoke sends
        // MsgType.DEPOSIT_CREDITED = 0, payload = (bytes32 depositId, address user, uint32 srcEid, address canonicalAsset, uint256 amount)
        uint32 srcEid = spokeController.spokeEid();
        bytes32 spokeSender = bytes32(uint256(uint160(address(spokeController))));
        bytes memory payload = abi.encode(bytes32("test"), alice, srcEid, canonicalToken, depositAmount);
        bytes memory depositCreditedMessage = abi.encode(uint8(0), payload); // msgType = 0 (DEPOSIT_CREDITED)

        // Message sent from the spoke is mocked; simulate the message being received by the hub
        // IMPORTANT: Build all data BEFORE pranking, as prank only affects the next call
        vm.prank(address(mockLzEndpoint));
        hubController.lzReceive(
            Origin({srcEid: srcEid, sender: spokeSender, nonce: 1}),
            bytes32(uint256(1)), // guid
            depositCreditedMessage,
            address(0),
            bytes("")
        );

        assertEq(positionBook.collateralOf(alice, srcEid, canonicalToken), depositAmount);
    }
}
