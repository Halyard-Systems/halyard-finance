// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OAppOptionsType3} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";

/**
 * SpokeController (Spoke-side) — LayerZero receiver/sender + orchestrator for:
 * - CollateralVault (custody of collateral deposits/withdrawals/seizures)
 * - LiquidityVault  (custody of borrow liquidity + push-driven repay notify)
 *
 * Implements:
 * - lzReceive(...) entrypoint for hub->spoke commands:
 *     CMD_RELEASE_BORROW
 *     CMD_RELEASE_WITHDRAW
 *     CMD_SEIZE_COLLATERAL
 * - onRepayNotified(...) hook called by LiquidityVault after successful repay transfer
 * - deposit helper to (optionally) send DEPOSIT_CREDITED immediately after a vault deposit
 *
 * Notes:
 * - LayerZero uses bytes32 sender identity; we store hub OApp as bytes32 trustedRemoteHub.
 * - This is LayerZero V2-style signature (Origin struct). Adapt if you’re on V1.
 * - For simplicity, sendMessage() is permissioned to owner. In practice:
 *     - you may allow anyone to call sendDepositReceipt() since it’s harmless,
 *       but keep it permissioned until you’re comfortable with anti-spam / fee handling.
 *
 * IMPORTANT:
 * - This contract assumes the hub uses canonical asset addresses (Ethereum home chain addresses).
 * - On the spoke, assets may be different addresses (bridged tokens). We map:
 *     canonicalAsset <-> spokeToken
 *   via a lightweight mapping stored here (or you can read it from a spoke-side registry).
 */

/// -----------------------------------------------------------------------
/// LayerZero V2 minimal types/interfaces
/// -----------------------------------------------------------------------

interface ILayerZeroEndpointV2 {
    function send(
        uint32 _dstEid,
        bytes32 _receiver,
        bytes calldata _message,
        bytes calldata _options,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable;
}

/// -----------------------------------------------------------------------
/// Vault interfaces
/// -----------------------------------------------------------------------

interface ICollateralVault {
    function deposit(address asset, uint256 amount, address onBehalfOf) external;
    function withdrawByController(address user, address to, address asset, uint256 amount) external;
    function seizeByController(address user, address to, address asset, uint256 amount) external;
}

interface ILiquidityVault {
    function releaseBorrow(bytes32 borrowId, address user, address receiver, address asset, uint256 amount) external;
}

/// Push-driven hook from LiquidityVault
interface ISpokeRepayController {
    function onRepayNotified(bytes32 repayId, address payer, address onBehalfOf, address asset, uint256 amount) external;
}

/// -----------------------------------------------------------------------
/// SpokeController
/// -----------------------------------------------------------------------
contract SpokeController is ISpokeRepayController, OApp, OAppOptionsType3, ReentrancyGuard {
    // -----------------------------
    // Errors
    // -----------------------------
    error UntrustedHub(uint32 srcEid, bytes32 sender);
    error AlreadyProcessed(bytes32 msgId);
    error InvalidAddress();
    error InvalidAmount();
    error InvalidPayload();
    error OnlyLiquidityVault();
    error AssetNotMapped(address spokeOrCanonical);
    error VaultCallFailed();

    // -----------------------------
    // Events
    // -----------------------------

    event HubConfigured(uint32 indexed hubEid, bytes32 indexed hubOApp);

    event CollateralVaultSet(address indexed vault);
    event LiquidityVaultSet(address indexed vault);

    event TokenMappingSet(address indexed canonicalAsset, address indexed spokeToken);

    event MessageProcessed(
        bytes32 indexed msgId, uint32 indexed srcEid, bytes32 indexed sender, uint64 nonce, uint8 msgType
    );

    event ReceiptSent(uint8 indexed msgType, bytes32 indexed requestId);

    // -----------------------------
    // Admin / config
    // -----------------------------
    uint32 public hubEid; // Ethereum hub EID
    bytes32 public trustedRemoteHub; // bytes32(uint256(uint160(hubControllerAddress)))

    ICollateralVault public collateralVault;
    ILiquidityVault public liquidityVault;

    // replay protection for inbound messages
    mapping(bytes32 => bool) public processed;

    constructor(address _owner, address _lzEndpoint) OApp(_lzEndpoint, _owner) Ownable(_owner) {
        if (_lzEndpoint == address(0) || _owner == address(0)) revert InvalidAddress();
    }

    /// @notice Configure hub identity (chain + trusted sender OApp).
    function configureHub(uint32 _hubEid, bytes32 _hubOApp) external onlyOwner {
        if (_hubEid == 0) revert InvalidAmount();
        if (_hubOApp == bytes32(0)) revert InvalidAmount();
        hubEid = _hubEid;
        trustedRemoteHub = _hubOApp;
        emit HubConfigured(_hubEid, _hubOApp);
    }

    function setCollateralVault(address v) external onlyOwner {
        if (v == address(0)) revert InvalidAddress();
        collateralVault = ICollateralVault(v);
        emit CollateralVaultSet(v);
    }

    function setLiquidityVault(address v) external onlyOwner {
        if (v == address(0)) revert InvalidAddress();
        liquidityVault = ILiquidityVault(v);
        emit LiquidityVaultSet(v);
    }

    // -----------------------------
    // Asset mapping (canonical <-> spoke token)
    // -----------------------------
    // canonicalToSpoke[canonical] = spoke token address
    mapping(address => address) public canonicalToSpoke;
    // spokeToCanonical[spoke] = canonical asset address
    mapping(address => address) public spokeToCanonical;

    function setTokenMapping(address canonicalAsset, address spokeToken) external onlyOwner {
        if (canonicalAsset == address(0) || spokeToken == address(0)) revert InvalidAddress();
        canonicalToSpoke[canonicalAsset] = spokeToken;
        spokeToCanonical[spokeToken] = canonicalAsset;
        emit TokenMappingSet(canonicalAsset, spokeToken);
    }

    function _requireMappedSpoke(address spokeToken) internal view returns (address canonicalAsset) {
        canonicalAsset = spokeToCanonical[spokeToken];
        if (canonicalAsset == address(0)) revert AssetNotMapped(spokeToken);
    }

    function _requireMappedCanonical(address canonicalAsset) internal view returns (address spokeToken) {
        spokeToken = canonicalToSpoke[canonicalAsset];
        if (spokeToken == address(0)) revert AssetNotMapped(canonicalAsset);
    }

    // -----------------------------
    // Message types (must match hub)
    // -----------------------------
    enum MsgType {
        // spoke -> hub receipts
        DEPOSIT_CREDITED,
        BORROW_RELEASED,
        WITHDRAW_RELEASED,
        REPAY_RECEIVED,
        COLLATERAL_SEIZED,

        // hub -> spoke commands
        CMD_RELEASE_BORROW,
        CMD_RELEASE_WITHDRAW,
        CMD_SEIZE_COLLATERAL
    }

    // -----------------------------
    // LayerZero inbound: hub -> spoke commands
    // -----------------------------
    /// @notice Override the internal _lzReceive hook from OAppReceiver
    /// @dev The base OApp.lzReceive() already verifies msg.sender == endpoint
    function _lzReceive(
        Origin calldata origin,
        bytes32, /*_guid*/
        bytes calldata message,
        address, /*_executor*/
        bytes calldata /*_extraData*/
    )
        internal
        override
    {
        if (origin.srcEid != hubEid || origin.sender != trustedRemoteHub) {
            revert UntrustedHub(origin.srcEid, origin.sender);
        }

        bytes32 msgId = keccak256(abi.encodePacked(origin.srcEid, origin.sender, origin.nonce));
        if (processed[msgId]) revert AlreadyProcessed(msgId);
        processed[msgId] = true;

        (uint8 msgType, bytes memory payload) = abi.decode(message, (uint8, bytes));

        if (msgType == uint8(MsgType.CMD_RELEASE_BORROW)) {
            _handleReleaseBorrow(payload);
        } else if (msgType == uint8(MsgType.CMD_RELEASE_WITHDRAW)) {
            _handleReleaseWithdraw(payload);
        } else if (msgType == uint8(MsgType.CMD_SEIZE_COLLATERAL)) {
            _handleSeizeCollateral(payload);
        } else {
            revert InvalidPayload();
        }

        emit MessageProcessed(msgId, origin.srcEid, origin.sender, origin.nonce, msgType);
    }

    // -----------------------------
    // Command handlers (call vaults + send receipts)
    // -----------------------------

    /**
     * Payload (suggested):
     *   (bytes32 borrowId, address user, address receiver, address canonicalAsset, uint256 amount)
     */
    function _handleReleaseBorrow(bytes memory payload) internal {
        if (address(liquidityVault) == address(0)) revert InvalidAddress();

        (bytes32 borrowId, address user, address receiver, address canonicalAsset, uint256 amount) =
            abi.decode(payload, (bytes32, address, address, address, uint256));

        address spokeToken = _requireMappedCanonical(canonicalAsset);

        bool success = true;
        // try/catch to avoid reverting lzReceive; we want to send a failure receipt instead.
        try liquidityVault.releaseBorrow(borrowId, user, receiver, spokeToken, amount) {
            success = true;
        } catch {
            success = false;
        }

        // Send BORROW_RELEASED receipt to hub
        // Receipt payload:
        //   (bytes32 borrowId, bool success, address user, uint32 dstEid, address canonicalAsset, uint256 amount)
        bytes memory receiptPayload = abi.encode(
            borrowId,
            success,
            user,
            hubEid,
            /* not used by hub, but keeps schema */
            canonicalAsset,
            amount
        );
        _sendReceipt(uint8(MsgType.BORROW_RELEASED), receiptPayload, borrowId);
    }

    /**
     * Payload (suggested):
     *   (bytes32 withdrawId, address user, address receiver, address canonicalAsset, uint256 amount)
     */
    function _handleReleaseWithdraw(bytes memory payload) internal {
        if (address(collateralVault) == address(0)) revert InvalidAddress();

        (bytes32 withdrawId, address user, address receiver, address canonicalAsset, uint256 amount) =
            abi.decode(payload, (bytes32, address, address, address, uint256));

        address spokeToken = _requireMappedCanonical(canonicalAsset);

        bool success = true;
        try collateralVault.withdrawByController(user, receiver, spokeToken, amount) {
            success = true;
        } catch {
            success = false;
        }

        // Receipt payload:
        //   (bytes32 withdrawId, bool success, address user, uint32 dstEid, address canonicalAsset, uint256 amount)
        bytes memory receiptPayload = abi.encode(
            withdrawId,
            success,
            user,
            hubEid,
            /* not used by hub */
            canonicalAsset,
            amount
        );
        _sendReceipt(uint8(MsgType.WITHDRAW_RELEASED), receiptPayload, withdrawId);
    }

    /**
     * Payload (suggested):
     *   (bytes32 liqId, address user, address liquidator, address canonicalAsset, uint256 amount)
     *
     * This seizes collateral from `user` and transfers to `liquidator`.
     */
    function _handleSeizeCollateral(bytes memory payload) internal {
        if (address(collateralVault) == address(0)) revert InvalidAddress();

        (bytes32 liqId, address user, address liquidator, address canonicalAsset, uint256 amount) =
            abi.decode(payload, (bytes32, address, address, address, uint256));

        address spokeToken = _requireMappedCanonical(canonicalAsset);

        bool success = true;
        try collateralVault.seizeByController(user, liquidator, spokeToken, amount) {
            success = true;
        } catch {
            success = false;
        }

        // Receipt payload:
        //   (bytes32 liqId, bool success, address user, uint32 seizeEid, address canonicalAsset, uint256 amount, address liquidator)
        bytes memory receiptPayload = abi.encode(
            liqId,
            success,
            user,
            hubEid,
            /* placeholder */
            canonicalAsset,
            amount,
            liquidator
        );
        _sendReceipt(uint8(MsgType.COLLATERAL_SEIZED), receiptPayload, liqId);
    }

    // -----------------------------
    // Push-driven repay hook (LiquidityVault -> SpokeController -> Hub)
    // -----------------------------
    function onRepayNotified(bytes32 repayId, address payer, address onBehalfOf, address spokeAsset, uint256 amount)
        external
        override
    {
        if (msg.sender != address(liquidityVault)) revert OnlyLiquidityVault();
        if (repayId == bytes32(0)) revert InvalidAmount();
        if (payer == address(0) || onBehalfOf == address(0) || spokeAsset == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        address canonicalAsset = _requireMappedSpoke(spokeAsset);

        // Receipt payload on hub:
        //   (bytes32 repayId, address user, uint32 srcEid, address canonicalAsset, uint256 amount)
        // NOTE: srcEid should be THIS chain’s EID. If you want it, store `spokeEid` in this contract.
        // For now, we omit srcEid and let hub infer from origin.srcEid if desired. But our HubController
        // handler expects a uint32 srcEid — so we store it.
        //
        // Add spokeEid to config for correctness:
        //   configureSpokeEid(uint32 _spokeEid)
        //
        // For now we’ll require it.
        uint32 spokeEid_ = spokeEid;
        if (spokeEid_ == 0) revert InvalidAmount();

        bytes memory receiptPayload = abi.encode(repayId, onBehalfOf, spokeEid_, canonicalAsset, amount);
        _sendReceipt(uint8(MsgType.REPAY_RECEIVED), receiptPayload, repayId);
    }

    // -----------------------------
    // Spoke EID config (needed for repay receipt payload)
    // -----------------------------
    uint32 public spokeEid;

    function configureSpokeEid(uint32 _spokeEid) external onlyOwner {
        if (_spokeEid == 0) revert InvalidAmount();
        spokeEid = _spokeEid;
    }

    /**
     *  This is the primary way to deposit; it transfer the tokens to the collateral
     *  vault and then sends the DEPOSIT_CREDITED message to the hub.
     *
     *  Payload to hub:
     *   (bytes32 depositId, address user, uint32 srcEid, address canonicalAsset, uint256 amount)
     */
    function depositAndNotify(
        bytes32 depositId,
        address canonicalAsset,
        uint256 amount,
        bytes calldata options,
        MessagingFee calldata fee
    ) external payable {
        if (depositId == bytes32(0)) revert InvalidAmount();
        if (canonicalAsset == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (spokeEid == 0) revert InvalidAmount();
        if (address(collateralVault) == address(0)) revert InvalidAddress();

        address spokeToken = _requireMappedCanonical(canonicalAsset);

        // User must have approved CollateralVault, because vault pulls tokens directly from user.
        // Pass msg.sender as the 'from' address so vault knows who to pull tokens from.
        collateralVault.deposit(spokeToken, amount, msg.sender);

        bytes memory payload = abi.encode(depositId, msg.sender, spokeEid, canonicalAsset, amount);
        _sendMessageToHub(uint8(MsgType.DEPOSIT_CREDITED), payload, options, fee, msg.sender);

        emit ReceiptSent(uint8(MsgType.DEPOSIT_CREDITED), depositId);
    }

    // -----------------------------
    // Outbound messaging helpers
    // -----------------------------

    /// @dev Send a receipt to hub using stored hub config; uses empty options by default.
    function _sendReceipt(uint8 msgType, bytes memory payload, bytes32 requestId) internal {
        // For receipts we often keep options empty and require caller to prepay msg.value to cover fees.
        // In real systems you quote fees and pass options; for now we use defaults.
        bytes memory envelope = abi.encode(msgType, payload);

        // With LZ V2 you should provide options/fee. For a minimal example we use:
        // - options: empty
        // - fee: nativeFee = msg.value, lzTokenFee = 0
        // - refund: owner
        MessagingFee memory fee = MessagingFee({nativeFee: msg.value, lzTokenFee: 0});

        //endpoint.send{value: msg.value}(hubEid, trustedRemoteHub, envelope, bytes(""), fee, owner);
        _lzSend(hubEid, envelope, bytes(""), fee, msg.sender);
        emit ReceiptSent(msgType, requestId);
    }

    function _sendMessageToHub(
        uint8 msgType,
        bytes memory payload,
        bytes calldata options,
        MessagingFee calldata fee,
        address refundAddress
    ) internal {
        bytes memory envelope = abi.encode(msgType, payload);
        _lzSend(hubEid, envelope, options, fee, refundAddress);
        //send{value: msg.value}(hubEid, trustedRemoteHub, envelope, options, fee, refundAddress);
    }
}
