// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {IHubController} from "../interfaces/IHubController.sol";
import {IPositionBook} from "../interfaces/IPositionBook.sol";
import {IRiskEngine} from "../interfaces/IRiskEngine.sol";
import {IDebtManager} from "../interfaces/IDebtManager.sol";

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
contract HubRouter is Ownable, Pausable, AccessManaged {
    // ──────────────────────────────────────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────────────────────────────────────
    error InvalidAddress();
    error InvalidAmount();
    error InsufficientCollateral();
    error BorrowNotAllowed();

    // ──────────────────────────────────────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────────────────────────────────────
    event HubControllerSet(address indexed hubController);
    event PositionBookSet(address indexed positionBook);
    event RiskEngineSet(address indexed riskEngine);
    event DebtManagerSet(address indexed debtManager);

    event WithdrawRequested(address indexed user, uint32 indexed dstEid, address asset, uint256 amount);
    event WithdrawFinalized(bytes32 indexed withdrawId, address indexed user, bool success);

    event BorrowRequested(
        bytes32 indexed borrowId, address indexed user, uint32 indexed dstEid, address asset, uint256 amount
    );

    event BorrowFinalized(bytes32 indexed borrowId, address indexed user, bool success);

    // ──────────────────────────────────────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────────────────────────────────────
    IHubController public hubController;
    IPositionBook public positionBook;
    IRiskEngine public riskEngine;
    IDebtManager public debtManager;

    // ──────────────────────────────────────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────────────────────────────────────
    constructor(address _owner, address _authority) Ownable(_owner) AccessManaged(_authority) {
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
        riskEngine = IRiskEngine(_riskEngine);
        emit RiskEngineSet(_riskEngine);
    }

    function setDebtManager(address _debtManager) external onlyOwner {
        if (_debtManager == address(0)) revert InvalidAddress();
        debtManager = IDebtManager(_debtManager);
        emit DebtManagerSet(_debtManager);
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
     *   1. RiskEngine validates health factor using oracle prices for every asset
     *   2. RiskEngine reserves collateral and creates pending withdraw in PositionBook
     *   3. HubController sends CMD_RELEASE_WITHDRAW to spoke
     *   4. Wait for WITHDRAW_RELEASED receipt from spoke (handled by HubController)
     *
     * If the user has outstanding loans, the withdrawal must not push their
     * health factor below 1.0 (liquidation threshold). The RiskEngine calls
     * the oracle (Pyth) for every collateral and debt asset to compute the
     * account's total value before allowing the withdrawal.
     *
     * @param dstEid Destination spoke chain EID where collateral is held
     * @param asset Canonical asset address
     * @param amount Amount to withdraw
     * @param collateralSlots All collateral positions to consider for health factor
     * @param debtSlots All debt positions to consider for health factor
     * @param options LayerZero options
     * @param fee LayerZero messaging fee
     */
    function withdrawAndNotify(
        uint32 dstEid,
        address asset,
        uint256 amount,
        IRiskEngine.CollateralSlot[] calldata collateralSlots,
        IRiskEngine.DebtSlot[] calldata debtSlots,
        bytes calldata options,
        MessagingFee calldata fee
    ) external payable whenNotPaused {
        if (address(positionBook) == address(0)) revert InvalidAddress();
        if (address(hubController) == address(0)) revert InvalidAddress();
        if (address(riskEngine) == address(0)) revert InvalidAddress();
        if (asset == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        address user = msg.sender;
        bytes32 withdrawId = keccak256(abi.encodePacked(user, dstEid, asset, amount, block.number));

        // Validate health factor via oracle prices, reserve collateral, and create pending withdraw.
        riskEngine.validateAndCreateWithdraw(
            withdrawId, user, dstEid, asset, amount, user, collateralSlots, debtSlots
        );

        // Send CMD_RELEASE_WITHDRAW command to spoke
        hubController.sendWithdrawCommand{value: msg.value}(
            dstEid, withdrawId, user, user, asset, amount, options, fee, user
        );

        emit WithdrawRequested(user, dstEid, asset, amount);
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // User Functions - Borrow Flow
    // ──────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Request to borrow assets from a spoke chain
     * @dev Flow:
     *   1. RiskEngine validates health factor using oracle prices for every asset
     *   2. RiskEngine creates pending borrow in PositionBook (reserves debt headroom)
     *   3. HubController sends CMD_RELEASE_BORROW to spoke
     *   4. Wait for BORROW_RELEASED receipt from spoke (handled by HubController)
     *
     * Borrowed tokens are always sent to msg.sender (no delegated borrowing).
     * The borrowId is computed deterministically from the request parameters.
     *
     * @param dstEid Destination spoke chain EID where liquidity is held
     * @param asset Canonical asset address (debt asset)
     * @param amount Amount to borrow
     * @param collateralSlots All collateral positions to consider for health factor
     * @param debtSlots All debt positions to consider for health factor
     * @param options LayerZero options
     * @param fee LayerZero messaging fee
     */
    function borrowAndNotify(
        uint32 dstEid,
        address asset,
        uint256 amount,
        IRiskEngine.CollateralSlot[] calldata collateralSlots,
        IRiskEngine.DebtSlot[] calldata debtSlots,
        bytes calldata options,
        MessagingFee calldata fee
    ) external payable whenNotPaused {
        if (address(positionBook) == address(0)) revert InvalidAddress();
        if (address(hubController) == address(0)) revert InvalidAddress();
        if (address(riskEngine) == address(0)) revert InvalidAddress();
        if (asset == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        address user = msg.sender;
        bytes32 borrowId = keccak256(abi.encodePacked(user, dstEid, asset, amount, block.number));

        // Validate health factor via oracle prices and reserve debt headroom.
        // RiskEngine calls Pyth for every collateral and debt asset to compute
        // borrow power. Reverts if the new debt would exceed borrow power.
        // Also creates the pending borrow in PositionBook.
        riskEngine.validateAndCreateBorrow(
            borrowId, user, dstEid, asset, amount, user, collateralSlots, debtSlots
        );

        // Send CMD_RELEASE_BORROW command to spoke
        hubController.sendBorrowCommand{value: msg.value}(
            dstEid, borrowId, user, user, asset, amount, options, fee, user
        );

        emit BorrowRequested(borrowId, user, dstEid, asset, amount);
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // Finalization Functions (called by HubController after receipt)
    // ──────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Finalize a withdrawal after spoke confirmation
     * @dev Called by HubController after receiving WITHDRAW_RELEASED receipt.
     *   On success: PositionBook debits collateral and clears reservation.
     *   On failure: PositionBook just clears the reservation.
     */
    function finalizeWithdraw(bytes32 withdrawId, bool success) external restricted {
        (address user,,,,) = positionBook.finalizePendingWithdraw(withdrawId, success);

        emit WithdrawFinalized(withdrawId, user, success);
    }

    /**
     * @notice Finalize a borrow after spoke confirmation
     * @dev Called by HubController after receiving BORROW_RELEASED receipt.
     *   On success: mints debt via DebtManager and clears the reservation.
     *   On failure: PositionBook unreserves the debt headroom.
     */
    function finalizeBorrow(bytes32 borrowId, bool success) external restricted {
        (address user, uint32 dstEid, address asset, uint256 amount,,,) =
            positionBook.finalizePendingBorrow(borrowId, success);

        if (success) {
            debtManager.mintDebt(user, dstEid, asset, amount);
            positionBook.clearBorrowReservation(borrowId);
        }

        emit BorrowFinalized(borrowId, user, success);
    }
}
