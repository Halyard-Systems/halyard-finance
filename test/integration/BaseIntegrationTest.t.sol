// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MessagingFee, Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {MessagingFee} from "lib/devtools/packages/oapp-evm/contracts/oapp/OApp.sol";

import {BaseTest} from "../BaseTest.t.sol";

contract BaseIntegrationTest is BaseTest {
    /// @notice Mock the LayerZero endpoint send call
    function _mockLzSend() internal {
        vm.mockCall(
            address(mockLzEndpoint),
            abi.encodeWithSignature("send((uint32,bytes32,bytes,bytes,bool),address)"),
            abi.encode(
                bytes32(uint256(1)), // guid
                uint64(1), // nonce
                MessagingFee({nativeFee: 0, lzTokenFee: 0})
            )
        );
    }

    /// @notice Complete deposit flow: spoke deposit + hub receipt
    /// @param user The user depositing
    /// @param depositId Unique deposit identifier
    /// @param asset The canonical asset address
    /// @param amount Amount to deposit
    /// @return The amount deposited
    function _depositAndCredit(address user, bytes32 depositId, address asset, uint256 amount)
        internal
        returns (uint256)
    {
        _mockLzSend();

        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        // Spoke side: User deposits
        vm.prank(user);
        spokeController.depositAndNotify{value: 0.1 ether}(depositId, asset, amount, bytes(""), fee);

        // Verify spoke state
        assertEq(collateralVault.lockedBalanceOf(user, address(mockToken)), amount);

        // Hub side: Simulate receipt of deposit message
        _simulateDepositReceipt(depositId, user, asset, amount);

        // Verify hub state
        assertEq(positionBook.collateralOf(user, spokeController.spokeEid(), asset), amount);

        return amount;
    }

    /// @notice Simulate the hub receiving a deposit receipt from spoke
    /// @param depositId Unique deposit identifier
    /// @param user The user who deposited
    /// @param asset The canonical asset address
    /// @param amount Amount deposited
    function _simulateDepositReceipt(bytes32 depositId, address user, address asset, uint256 amount) internal {
        uint32 srcEid = spokeController.spokeEid();
        bytes32 spokeSender = bytes32(uint256(uint160(address(spokeController))));

        // Build DEPOSIT_CREDITED message (msgType = 0)
        bytes memory payload = abi.encode(depositId, user, srcEid, asset, amount);
        bytes memory message = abi.encode(uint8(0), payload);

        // Simulate LayerZero delivering the message to hub
        vm.prank(address(mockLzEndpoint));
        hubController.lzReceive(
            Origin({srcEid: srcEid, sender: spokeSender, nonce: 1}),
            bytes32(uint256(1)), // guid
            message,
            address(0),
            bytes("")
        );
    }
}
