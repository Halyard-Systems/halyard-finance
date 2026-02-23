// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OAppOptionsType3} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import {IMessageTypes} from "../interfaces/IMessageTypes.sol";
import {IPositionBook} from "../interfaces/IPositionBook.sol";
import {IHubRouter} from "../interfaces/IHubRouter.sol";

/**
 * HubController
 *
 * Uses Ownable (required for OApp) for admin functions and AccessManaged for restricted functions.
 *
 * Purpose:
 * - Receives and handles incoming LayerZero messages from trusted spoke controllers.
 * - Handles calls from HubRouter to send commands to spokes.
 * - Registers and manages spoke controllers.
 * - Pauses the HubController to prevent further messages from being processed.
 */
contract HubController is AccessManaged, OApp, OAppOptionsType3 {
    error Paused();
    error InvalidAddress();
    error InvalidMessageType(uint8 msgType, Origin origin);
    error InvalidSpoke(address expected, address actual);

    event DepositCredited(bytes32 indexed depositId, uint32 indexed srcEid);
    event WithdrawReleased(bytes32 indexed withdrawId, bool success);
    event PausedSet(bool paused);
    event SpokeSet(uint32 indexed eid, bytes32 spoke);
    event SpokeRemoved(uint32 indexed eid);
    event PositionBookSet(address indexed positionBook);
    event HubRouterSet(address indexed hubRouter);
    event BorrowReleased(bytes32 indexed borrowId, bool success);

    IPositionBook public positionBook;
    IHubRouter public hubRouter;

    // trusted remote OApp address per source eid
    mapping(uint32 => bytes32) public spoke;
    uint32[] public spokeEids;
    mapping(uint32 => uint256) private spokeEidIndex; // eid => index+1 (0 means not present)

    bool public paused;

    constructor(address _owner, address _lzEndpoint, address _authority)
        AccessManaged(_authority)
        OApp(_lzEndpoint, _owner)
        Ownable(_owner)
    {}

    /// -----------------------------------------------------------------------
    /// Admin / config
    /// -----------------------------------------------------------------------
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit PausedSet(_paused);
    }

    function setPositionBook(address _positionBook) external onlyOwner {
        if (_positionBook == address(0)) revert InvalidAddress();
        positionBook = IPositionBook(_positionBook);
        emit PositionBookSet(_positionBook);
    }

    function setHubRouter(address _hubRouter) external onlyOwner {
        if (_hubRouter == address(0)) revert InvalidAddress();
        hubRouter = IHubRouter(_hubRouter);
        emit HubRouterSet(_hubRouter);
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
        Origin calldata origin,
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
        bytes32 expectedSpoke = spoke[origin.srcEid];
        if (expectedSpoke == bytes32(0) || expectedSpoke != origin.sender) {
            address expectedAddr = address(uint160(uint256(expectedSpoke)));
            address actualAddr = address(uint160(uint256(origin.sender)));
            revert InvalidSpoke(expectedAddr, actualAddr);
        }

        if (paused) revert Paused();

        (uint8 msgType, bytes memory payload) = abi.decode(_message, (uint8, bytes));
        if (msgType == uint8(IMessageTypes.MsgType.DEPOSIT_CREDITED)) {
            _handleDepositCredited(payload);
        } else if (msgType == uint8(IMessageTypes.MsgType.WITHDRAW_RELEASED)) {
            _handleWithdrawReleased(payload);
        } else if (msgType == uint8(IMessageTypes.MsgType.BORROW_RELEASED)) {
            _handleBorrowReleased(payload);
        } else {
            revert InvalidMessageType(msgType, origin);
        }
    }

    function _handleDepositCredited(bytes memory payload) internal {
        (bytes32 depositId, address user, uint32 srcEid, address canonicalAsset, uint256 amount) =
            abi.decode(payload, (bytes32, address, uint32, address, uint256));

        positionBook.creditCollateral(user, srcEid, canonicalAsset, amount);
        emit DepositCredited(depositId, srcEid);
    }

    function _handleWithdrawReleased(bytes memory payload) internal {
        (bytes32 withdrawId, bool success,,,,) = abi.decode(payload, (bytes32, bool, address, uint32, address, uint256));

        hubRouter.finalizeWithdraw(withdrawId, success);
        emit WithdrawReleased(withdrawId, success);
    }

    function _handleBorrowReleased(bytes memory payload) internal {
        (bytes32 borrowId, bool success,,,,) =
            abi.decode(payload, (bytes32, bool, address, uint32, address, uint256));

        hubRouter.finalizeBorrow(borrowId, success);
        emit BorrowReleased(borrowId, success);
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // Command Functions (called by HubRouter to send commands to spokes)
    // ──────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Send CMD_RELEASE_WITHDRAW command to spoke
     * @dev Called by HubRouter after validating user's withdrawal request
     */
    function sendWithdrawCommand(
        uint32 dstEid,
        bytes32 withdrawId,
        address user,
        address receiver,
        address asset,
        uint256 amount,
        bytes calldata options,
        MessagingFee calldata fee,
        address refundAddress
    ) external payable restricted {
        bytes memory payload = abi.encode(withdrawId, user, receiver, asset, amount);
        bytes memory message = abi.encode(uint8(IMessageTypes.MsgType.CMD_RELEASE_WITHDRAW), payload);

        _lzSend(dstEid, message, options, fee, refundAddress);
    }

    /**
     * @notice Send CMD_RELEASE_BORROW command to spoke
     * @dev Called by HubRouter after validating user's borrow request
     */
    function sendBorrowCommand(
        uint32 dstEid,
        bytes32 borrowId,
        address user,
        address receiver,
        address asset,
        uint256 amount,
        bytes calldata options,
        MessagingFee calldata fee,
        address refundAddress
    ) external payable restricted {
        bytes memory payload = abi.encode(borrowId, user, receiver, asset, amount);
        bytes memory message = abi.encode(uint8(IMessageTypes.MsgType.CMD_RELEASE_BORROW), payload);

        _lzSend(dstEid, message, options, fee, refundAddress);
    }
}
