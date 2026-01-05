// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OAppOptionsType3} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";

import "forge-std/console.sol";

/**
 * HubController
 *
 * Purpose:
 * - Receives and handles incoming LayerZero messages from trusted spoke controllers.
 * - Registers and manages spoke controllers.
 * - Pauses the HubController to prevent further messages from being processed.
 */
contract HubController is OApp, OAppOptionsType3, ReentrancyGuard {
    error Paused();
    error InvalidSpoke(address expected, address actual);

    event PausedSet(bool paused);
    event SpokeSet(uint32 indexed eid, bytes32 spoke);
    event SpokeRemoved(uint32 indexed eid);

    // trusted remote OApp address per source eid
    mapping(uint32 => bytes32) public spoke;
    uint32[] public spokeEids;
    mapping(uint32 => uint256) private spokeEidIndex; // eid => index+1 (0 means not present)

    bool public paused;

    constructor(address _owner, address _lzEndpoint) OApp(_lzEndpoint, _owner) Ownable(_owner) {}

    /// -----------------------------------------------------------------------
    /// Admin / config
    /// -----------------------------------------------------------------------
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit PausedSet(_paused);
    }

    function setSpoke(uint32 _eid, bytes32 _spoke) external onlyOwner {
        if (spokeEidIndex[_eid] == 0) {
            // New spoke - add to array
            spokeEids.push(_eid);
            spokeEidIndex[_eid] = spokeEids.length; // Store index+1
        }
        spoke[_eid] = _spoke;
        emit SpokeSet(_eid, _spoke);
    }

    function removeSpoke(uint32 _eid) external onlyOwner {
        uint256 indexPlusOne = spokeEidIndex[_eid];
        if (indexPlusOne > 0) {
            // Swap and pop for O(1) removal
            uint256 index = indexPlusOne - 1;
            uint256 lastIndex = spokeEids.length - 1;
            if (index != lastIndex) {
                uint32 lastEid = spokeEids[lastIndex];
                spokeEids[index] = lastEid;
                spokeEidIndex[lastEid] = indexPlusOne;
            }
            spokeEids.pop();
            delete spokeEidIndex[_eid];
        }
        delete spoke[_eid];
        emit SpokeRemoved(_eid);
    }

    /// -----------------------------------------------------------------------
    /// Views
    /// -----------------------------------------------------------------------
    function getSpoke(uint32 _eid) external view returns (bytes32) {
        return spoke[_eid];
    }

    function getSpokeEids() external view returns (uint32[] memory) {
        return spokeEids;
    }

    function getSpokeCount() external view returns (uint256) {
        return spokeEids.length;
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // Receive business logic
    //
    // Override _lzReceive to decode the incoming bytes and apply your logic.
    // The base OAppReceiver.lzReceive ensures:
    //   • Only the LayerZero Endpoint can call this method
    //
    // This implementation validates that the sender is a registered spoke.
    // To register a spoke, call setSpoke(eid, spokeAddress)
    // ──────────────────────────────────────────────────────────────────────────────

    /// @notice Invoked by OAppReceiver when EndpointV2.lzReceive is called
    /// @dev   _origin    Metadata (source chain, sender address, nonce)
    /// @dev   _guid      Global unique ID for tracking this message
    /// @param _message   ABI-encoded bytes (the string we sent earlier)
    /// @dev   _executor  Executor address that delivered the message
    /// @dev   _extraData Additional data from the Executor (unused here)
    function _lzReceive(
        Origin calldata _origin,
        bytes32,
        /*_guid*/
        bytes calldata _message,
        address,
        /*_executor*/
        bytes calldata /*_extraData*/
    )
        internal
        override
    {
        // Validate that the sender is a registered spoke before any message decoding or state changes
        bytes32 expectedSpoke = spoke[_origin.srcEid];
        if (expectedSpoke == bytes32(0) || expectedSpoke != _origin.sender) {
            address expectedAddr = address(uint160(uint256(expectedSpoke)));
            address actualAddr = address(uint160(uint256(_origin.sender)));
            revert InvalidSpoke(expectedAddr, actualAddr);
        }

        if (paused) revert Paused();
        // Decode the incoming bytes into a string
        // You can use abi.decode, abi.decodePacked, or directly splice bytes
        // if you know the format of your data structures
        string memory _string = abi.decode(_message, (string));

        // Custom logic goes here
        console.log("Received message:", _string);
    }
}
