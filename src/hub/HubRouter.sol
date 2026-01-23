// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {IHubController} from "../interfaces/IHubController.sol";
import {IPositionBook} from "../interfaces/IPositionBook.sol";

/**
 * @title HubRouter
 * @notice User-facing entrypoint for all hub actions (withdraw, borrow, repay)
 *
 * Architecture:
 * - HubRouter: Accepts user requests, validates, calls HubController to send commands
 * - HubController: Sends commands to spokes AND receives receipts/confirmations
 *
 * Message Flow:
 * User → HubRouter (validate) → HubController (send) → Spoke
 *                                     ↓ (receive receipt)
 *                            HubRouter.finalize() ← HubController
 *
 * This separation provides:
 * 1. Security blast radius - bugs in user flow don't affect message handling
 * 2. Different access control - user functions use pausable/nonReentrant vs onlyEndpoint
 * 3. Upgrade velocity - change UX without touching message receiver
 * 4. Operational safety - can pause user actions while keeping cross-chain receipts flowing
 */
contract HubRouter is Ownable, ReentrancyGuard, Pausable {
    // ──────────────────────────────────────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────────────────────────────────────
    error InvalidAddress();
    error InvalidAmount();
    error InsufficientCollateral();
    error WithdrawNotAllowed();
    error BorrowNotAllowed();

    // ──────────────────────────────────────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────────────────────────────────────
    event HubControllerSet(address indexed hubController);
    event PositionBookSet(address indexed positionBook);
    event RiskEngineSet(address indexed riskEngine);

    event WithdrawRequested(
        bytes32 indexed withdrawId, address indexed user, uint32 indexed dstEid, address asset, uint256 amount
    );

    event BorrowRequested(
        bytes32 indexed borrowId, address indexed user, uint32 indexed dstEid, address asset, uint256 amount
    );

    // ──────────────────────────────────────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────────────────────────────────────
    IHubController public hubController;
    IPositionBook public positionBook;
    address public riskEngine; // Will be interface once implemented

    // Track pending operations to prevent replay
    mapping(bytes32 => bool) public pendingWithdraws;
    mapping(bytes32 => bool) public pendingBorrows;

    // ──────────────────────────────────────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────────────────────────────────────
    constructor(address _owner) Ownable(_owner) {
        if (_owner == address(0)) revert InvalidAddress();
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // Admin Functions
    // ──────────────────────────────────────────────────────────────────────────────
    function setHubController(address _hubController) external onlyOwner {
        if (_hubController == address(0)) revert InvalidAddress();
        hubController = IHubController(_hubController);
        emit HubControllerSet(_hubController);
    }

    function setPositionBook(address _positionBook) external onlyOwner {
        if (_positionBook == address(0)) revert InvalidAddress();
        positionBook = IPositionBook(_positionBook);
        emit PositionBookSet(_positionBook);
    }

    function setRiskEngine(address _riskEngine) external onlyOwner {
        if (_riskEngine == address(0)) revert InvalidAddress();
        riskEngine = _riskEngine;
        emit RiskEngineSet(_riskEngine);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // User Functions - Withdrawal Flow
    // ──────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Request withdrawal of collateral from a spoke chain
     * @dev Flow:
     *   1. Validate user has sufficient collateral
     *   2. Check risk (health factor after withdrawal)
     *   3. Mark withdrawal as pending
     *   4. Send CMD_RELEASE_WITHDRAW to spoke
     *   5. Wait for WITHDRAW_RELEASED receipt from spoke (handled by HubController)
     *
     * @param withdrawId Unique identifier for this withdrawal
     * @param dstEid Destination spoke chain EID where collateral is held
     * @param asset Canonical asset address
     * @param amount Amount to withdraw
     * @param options LayerZero options
     * @param fee LayerZero messaging fee
     */
    function withdrawAndNotify(
        bytes32 withdrawId,
        uint32 dstEid,
        address asset,
        uint256 amount,
        bytes calldata options,
        MessagingFee calldata fee
    ) external payable nonReentrant whenNotPaused {
        if (withdrawId == bytes32(0)) revert InvalidAmount();
        if (asset == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (address(positionBook) == address(0)) revert InvalidAddress();
        if (address(hubController) == address(0)) revert InvalidAddress();

        address user = msg.sender;

        // TODO: Validate with RiskEngine
        // - Check user has sufficient collateral on dstEid
        // - Check health factor remains above threshold after withdrawal
        // if (!IRiskEngine(riskEngine).validateWithdraw(user, dstEid, asset, amount)) {
        //     revert WithdrawNotAllowed();
        // }

        // Mark as pending (will be finalized when HubController receives WITHDRAW_RELEASED)
        if (pendingWithdraws[withdrawId]) revert InvalidAmount(); // Already pending
        pendingWithdraws[withdrawId] = true;

        // Reserve the collateral in PositionBook (prevents double-withdrawal)
        // TODO: Add reserveCollateral to PositionBook
        // positionBook.reserveCollateral(user, dstEid, asset, amount);

        // Ask HubController to send CMD_RELEASE_WITHDRAW command to spoke
        hubController.sendWithdrawCommand{value: msg.value}(
            dstEid, withdrawId, user, user, asset, amount, options, fee, msg.sender
        );

        emit WithdrawRequested(withdrawId, user, dstEid, asset, amount);
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // User Functions - Borrow Flow
    // ──────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Request to borrow assets from a spoke chain
     * @dev Flow:
     *   1. Validate user has sufficient collateral
     *   2. Check risk (health factor after borrow)
     *   3. Mark borrow as pending
     *   4. Send CMD_RELEASE_BORROW to spoke
     *   5. Wait for BORROW_RELEASED receipt from spoke (handled by HubController)
     *
     * @param borrowId Unique identifier for this borrow
     * @param dstEid Destination spoke chain EID where liquidity is held
     * @param asset Canonical asset address
     * @param amount Amount to borrow
     * @param receiver Address to receive borrowed assets
     * @param options LayerZero options
     * @param fee LayerZero messaging fee
     */
    function borrowAndNotify(
        bytes32 borrowId,
        uint32 dstEid,
        address asset,
        uint256 amount,
        address receiver,
        bytes calldata options,
        MessagingFee calldata fee
    ) external payable nonReentrant whenNotPaused {
        if (borrowId == bytes32(0)) revert InvalidAmount();
        if (asset == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (receiver == address(0)) revert InvalidAddress();
        if (address(hubController) == address(0)) revert InvalidAddress();

        address user = msg.sender;

        // TODO: Validate with RiskEngine
        // - Check user has sufficient collateral across all chains
        // - Check health factor remains above threshold after borrow
        // - Check borrow doesn't exceed caps
        // if (!IRiskEngine(riskEngine).validateBorrow(user, dstEid, asset, amount)) {
        //     revert BorrowNotAllowed();
        // }

        // Mark as pending
        if (pendingBorrows[borrowId]) revert InvalidAmount(); // Already pending
        pendingBorrows[borrowId] = true;

        // Record the debt in PositionBook (will be finalized when receipt comes back)
        // TODO: Add createPendingBorrow to PositionBook
        // positionBook.createPendingBorrow(borrowId, user, dstEid, asset, amount);

        // Ask HubController to send CMD_RELEASE_BORROW command to spoke
        hubController.sendBorrowCommand{value: msg.value}(
            dstEid, borrowId, user, receiver, asset, amount, options, fee, msg.sender
        );

        emit BorrowRequested(borrowId, user, dstEid, asset, amount);
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // Finalization Functions (called by HubController after receipt)
    // ──────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Finalize a withdrawal after spoke confirmation
     * @dev Called by HubController after receiving WITHDRAW_RELEASED receipt
     */
    function finalizeWithdraw(bytes32 withdrawId, address user, uint32 srcEid, address asset, uint256 amount) external {
        // TODO: Add access control - only HubController should call this
        // if (msg.sender != address(hubController)) revert Unauthorized();

        // Clear pending state
        delete pendingWithdraws[withdrawId];

        // Finalize in PositionBook (debit collateral, unreserve)
        // TODO: positionBook.finalizeWithdraw(user, srcEid, asset, amount);
    }

    /**
     * @notice Finalize a borrow after spoke confirmation
     * @dev Called by HubController after receiving BORROW_RELEASED receipt
     */
    function finalizeBorrow(bytes32 borrowId, address user, uint32 srcEid, address asset, uint256 amount) external {
        // TODO: Add access control - only HubController should call this
        // if (msg.sender != address(hubController)) revert Unauthorized();

        // Clear pending state
        delete pendingBorrows[borrowId];

        // Finalize debt in PositionBook
        // TODO: positionBook.finalizeBorrow(borrowId, user, srcEid, asset, amount);
    }
}
