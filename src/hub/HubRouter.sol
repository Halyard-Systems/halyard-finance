// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {IHubController} from "../interfaces/IHubController.sol";
import {IPositionBook} from "../interfaces/IPositionBook.sol";
import {IRiskEngine} from "../interfaces/IRiskEngine.sol";

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

    event WithdrawRequested(address indexed user, uint32 indexed dstEid, address asset, uint256 amount);

    event BorrowRequested(
        bytes32 indexed borrowId, address indexed user, uint32 indexed dstEid, address asset, uint256 amount
    );

    // ──────────────────────────────────────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────────────────────────────────────
    IHubController public hubController;
    IPositionBook public positionBook;
    IRiskEngine public riskEngine;

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
     * @param dstEid Destination spoke chain EID where collateral is held
     * @param asset Canonical asset address
     * @param amount Amount to withdraw
     * @param options LayerZero options
     * @param fee LayerZero messaging fee
     */
    /**
     * @notice Request withdrawal of collateral from a spoke chain
     * @dev Flow:
     *   1. RiskEngine validates health factor using oracle prices for every asset
     *   2. RiskEngine reserves collateral in PositionBook (prevents double-withdrawal)
     *   3. HubController creates pending withdraw and sends CMD_RELEASE_WITHDRAW to spoke
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

        // Validate health factor via oracle prices and reserve collateral.
        // This calls Pyth (via the oracle adapter) for every collateral and debt asset
        // to compute total account value. If the user has loans, reverts if the
        // withdrawal would push the health factor below 1.0.
        riskEngine.validateAndCreateWithdraw(
            keccak256(abi.encodePacked(msg.sender, dstEid, asset, amount, block.number)),
            msg.sender,
            dstEid,
            asset,
            amount,
            msg.sender,
            collateralSlots,
            debtSlots
        );

        // Send CMD_RELEASE_WITHDRAW command to spoke (also creates pending withdraw in PositionBook)
        hubController.processWithdraw{value: msg.value}(dstEid, msg.sender, asset, amount, options, fee);

        emit WithdrawRequested(msg.sender, dstEid, asset, amount);
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
    ) external payable whenNotPaused {
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
    function finalizeWithdraw(
        bytes32,
        /* withdrawId */
        address user,
        uint32,
        /* srcEid */
        address,
        /* asset */
        uint256 /* amount */
    )
        external
        restricted
    {
        // Finalize in PositionBook (debit collateral, unreserve)
        // TODO: positionBook.finalizeWithdraw(user, srcEid, asset, amount);
    }

    /**
     * @notice Finalize a borrow after spoke confirmation
     * @dev Called by HubController after receiving BORROW_RELEASED receipt
     */
    function finalizeBorrow(
        bytes32 borrowId,
        address,
        /* user */
        uint32,
        /* srcEid */
        address,
        /* asset */
        uint256 /* amount */
    )
        external
        restricted
    {
        // Finalize debt in PositionBook
        // TODO: positionBook.finalizeBorrow(borrowId, user, srcEid, asset, amount);
    }
}
