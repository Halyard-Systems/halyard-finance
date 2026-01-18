// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * LiquidityVault (Spoke-side, PUSH-DRIVEN repay)
 *
 * Responsibilities:
 * - Custody borrowable liquidity on a spoke chain.
 * - Allow ONLY the SpokeController to release borrow funds to a receiver (hub-authorized borrow).
 * - Allow users to repay; on repay, immediately CALL the SpokeController to notify the hub (push-driven).
 *
 * Push-driven repay means:
 * - No off-chain watcher required to notice Repayed events.
 * - Vault calls controller.onRepayNotified(...) after the token transfer succeeds.
 *
 * Security considerations:
 * - controller call happens AFTER tokens are received.
 * - controller is a trusted contract in your system; still, we use nonReentrant to avoid weirdness.
 * - If controller notification fails, the whole repay reverts (tokens transfer is reverted too).
 */

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

interface ISpokeRepayController {
    /**
     * @notice Called by LiquidityVault after a successful repay transfer.
     * The controller should send a LayerZero message to the hub.
     *
     * repayId: unique identifier used for hub-side dedupe (and analytics).
     * payer:   who paid on the spoke
     * onBehalfOf: whose debt should be reduced on hub
     * asset:   debt token on this spoke (or canonical asset depending on your mapping approach)
     * amount:  token amount received
     */
    function onRepayNotified(bytes32 repayId, address payer, address onBehalfOf, address asset, uint256 amount) external;
}

contract LiquidityVault is Ownable, ReentrancyGuard {
    // -----------------------------
    // Errors
    // -----------------------------
    error OnlyController();
    error InvalidAddress();
    error InvalidAmount();
    error InsufficientLiquidity(uint256 available, uint256 requested);
    error TransferFailed();
    error NotifyFailed();
    error Paused();

    // -----------------------------
    // Events
    // -----------------------------
    event ControllerSet(address indexed controller);
    event PausedSet(bool paused);

    event LiquidityAdded(address indexed payer, address indexed asset, uint256 amount);
    event LiquidityRemoved(address indexed to, address indexed asset, uint256 amount);

    event BorrowReleased(
        bytes32 indexed borrowId, address indexed user, address indexed receiver, address asset, uint256 amount
    );
    event Repayed(
        bytes32 indexed repayId, address indexed payer, address indexed onBehalfOf, address asset, uint256 amount
    );

    event AssetAllowed(address indexed asset, bool allowed);
    event UseAllowlistSet(bool enabled);

    // -----------------------------
    // Admin / config
    // -----------------------------
    address public controller; // SpokeController
    bool public paused;

    // Optional asset allowlist
    bool public useAllowlist;
    mapping(address => bool) public isAssetAllowed;

    modifier onlyController() {
        if (msg.sender != controller) revert OnlyController();
        _;
    }

    modifier notPaused() {
        if (paused) revert Paused();
        _;
    }

    constructor(address _owner, address _controller) Ownable(_owner) {
        if (_owner == address(0) || _controller == address(0)) revert InvalidAddress();
        controller = _controller;
        emit ControllerSet(_controller);
    }

    function setController(address newController) external onlyOwner {
        if (newController == address(0)) revert InvalidAddress();
        controller = newController;
        emit ControllerSet(newController);
    }

    function setPaused(bool p) external onlyOwner {
        paused = p;
        emit PausedSet(p);
    }

    function setUseAllowlist(bool enabled) external onlyOwner {
        useAllowlist = enabled;
        emit UseAllowlistSet(enabled);
    }

    function setAssetAllowed(address asset, bool allowed) external onlyOwner {
        if (asset == address(0)) revert InvalidAddress();
        isAssetAllowed[asset] = allowed;
        emit AssetAllowed(asset, allowed);
    }

    // -----------------------------
    // Owner: seed / withdraw liquidity
    // -----------------------------

    function addLiquidity(address asset, uint256 amount) external notPaused nonReentrant {
        if (asset == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (useAllowlist && !isAssetAllowed[asset]) revert InvalidAddress();

        if (!IERC20(asset).transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        emit LiquidityAdded(msg.sender, asset, amount);
    }

    function removeLiquidity(address asset, address to, uint256 amount) external onlyOwner notPaused nonReentrant {
        if (asset == address(0) || to == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (useAllowlist && !isAssetAllowed[asset]) revert InvalidAddress();

        if (!IERC20(asset).transfer(to, amount)) revert TransferFailed();
        emit LiquidityRemoved(to, asset, amount);
    }

    // -----------------------------
    // Controller-only: release borrow funds
    // -----------------------------

    function releaseBorrow(bytes32 borrowId, address user, address receiver, address asset, uint256 amount)
        external
        onlyController
        notPaused
        nonReentrant
    {
        if (borrowId == bytes32(0)) revert InvalidAmount();
        if (user == address(0) || receiver == address(0) || asset == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (useAllowlist && !isAssetAllowed[asset]) revert InvalidAddress();

        uint256 bal = IERC20(asset).balanceOf(address(this));
        if (bal < amount) revert InsufficientLiquidity(bal, amount);

        if (!IERC20(asset).transfer(receiver, amount)) revert TransferFailed();
        emit BorrowReleased(borrowId, user, receiver, asset, amount);
    }

    // -----------------------------
    // User: repay (push-driven)
    // -----------------------------

    /**
     * @notice Repay by transferring debt tokens into this vault, then immediately notifying SpokeController.
     * If controller notification fails, the whole tx reverts (no tokens move).
     *
     * repayId should be unique. A common pattern is:
     *   repayId = keccak256(abi.encodePacked(block.chainid, msg.sender, onBehalfOf, asset, amount, userNonce))
     */
    function repay(bytes32 repayId, address asset, uint256 amount, address onBehalfOf) external notPaused nonReentrant {
        if (repayId == bytes32(0)) revert InvalidAmount();
        if (asset == address(0) || onBehalfOf == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (useAllowlist && !isAssetAllowed[asset]) revert InvalidAddress();

        // Pull tokens first
        if (!IERC20(asset).transferFrom(msg.sender, address(this), amount)) revert TransferFailed();

        // Notify controller (push)
        // If this reverts, the transferFrom is reverted too.
        try ISpokeRepayController(controller).onRepayNotified(repayId, msg.sender, onBehalfOf, asset, amount) {
        // ok
        }
        catch {
            revert NotifyFailed();
        }

        emit Repayed(repayId, msg.sender, onBehalfOf, asset, amount);
    }

    // -----------------------------
    // Admin: rescue tokens (dust / wrong transfers)
    // -----------------------------
    function rescueERC20(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (token == address(0) || to == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (!IERC20(token).transfer(to, amount)) revert TransferFailed();
    }
}
