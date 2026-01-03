// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/console.sol";

import {OApp, Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract SpokeController is OApp, ReentrancyGuard {  
    /// @notice Initialize with Endpoint V2 and owner address
    /// @param _lzEndpoint The local chain's LayerZero Endpoint V2 address
    /// @param _owner    The address permitted to configure this OApp
    constructor(address _lzEndpoint, address _owner)
        OApp(_lzEndpoint, _owner)
        Ownable(_owner)
    {}

    /// @dev Required by OApp - handles incoming LayerZero messages
    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata /*_message*/,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {
        // TODO: Implement cross-chain message handling
    }

    function deposit(address _token, uint256 _amount) external nonReentrant {
        // TODO: Implement deposit logic
    }

    function withdraw(address _token, uint256 _amount) external nonReentrant {
        // TODO: Implement withdraw logic
    }

    function borrow(address _token, uint256 _amount) external nonReentrant {
        // TODO: Implement borrow logic
    }
}