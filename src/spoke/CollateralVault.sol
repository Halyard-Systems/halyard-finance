// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * CollateralVault (Spoke-side)
 *
 * Responsibilities:
 * - Custody collateral ERC20s on a spoke chain.
 * - Track per-user locked balances per asset (for accounting + for safe seizure/withdraw).
 * - Allow users to deposit (locks tokens).
 * - Allow ONLY the SpokeController to withdraw or seize locked collateral.
 *
 * Intended flow:
 * - User deposits on spoke -> vault records balance + (separately) SpokeController sends DEPOSIT_CREDITED message to hub.
 * - Hub later authorizes a withdraw/seize -> SpokeController receives CMD_* and calls vault.withdrawByController / seizeByController.
 *
 * Notes:
 * - The vault does NOT try to validate hub risk rules. It just enforces custody rules and controller-only releases.
 * - You can optionally restrict assets via allowlist, but many teams allow any ERC20 and rely on SpokeController/Hub to use only listed assets.
 */

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

contract CollateralVault is Ownable {
    // -----------------------------
    // Errors
    // -----------------------------
    error OnlyController();
    error InvalidAddress();
    error InvalidAmount();
    error InsufficientBalance(uint256 have, uint256 need);
    error TransferFailed();
    error Paused();

    // -----------------------------
    // Events
    // -----------------------------
    event ControllerSet(address indexed controller);
    event PausedSet(bool paused);

    event Deposited(address indexed payer, address indexed onBehalfOf, address indexed asset, uint256 amount);
    event Withdrawn(address indexed user, address indexed to, address indexed asset, uint256 amount);
    event Seized(address indexed user, address indexed to, address indexed asset, uint256 amount);

    // Optional allowlist events
    event AssetAllowed(address indexed asset, bool allowed);

    // -----------------------------
    // Admin / config
    // -----------------------------
    address public controller;
    bool public paused;

    // Optional asset allowlist (disabled by default if you never call setAssetAllowed)
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

    /// @notice Optional: enable/disable allowlist enforcement.
    function setUseAllowlist(bool enabled) external onlyOwner {
        useAllowlist = enabled;
    }

    /// @notice Optional: allow or disallow an asset if allowlist is enabled.
    function setAssetAllowed(address asset, bool allowed) external onlyOwner {
        if (asset == address(0)) revert InvalidAddress();
        isAssetAllowed[asset] = allowed;
        emit AssetAllowed(asset, allowed);
    }

    // -----------------------------
    // Storage: per-user locked balances
    // -----------------------------
    // locked[user][asset] => amount locked in this vault
    mapping(address => mapping(address => uint256)) private locked;

    function lockedBalanceOf(address user, address asset) external view returns (uint256) {
        return locked[user][asset];
    }

    // -----------------------------
    // User entry: deposit
    // -----------------------------

    /**
     * @notice Called by SpokeController to deposit collateral. Tokens are transferred into the vault
     *  and credited to `onBehalfOf`.
     * @param asset ERC20 token address
     * @param amount Amount in token units
     * @param onBehalfOf The user whose locked balance is credited and tokens transferred from
     */
    function deposit(address asset, uint256 amount, address onBehalfOf) external onlyController notPaused {
        if (asset == address(0) || onBehalfOf == address(0)) {
            revert InvalidAddress();
        }
        if (amount == 0) revert InvalidAmount();
        if (useAllowlist && !isAssetAllowed[asset]) revert InvalidAddress(); // keep errors simple; customize if you want

        // Pull tokens from the specified address
        if (!IERC20(asset).transferFrom(onBehalfOf, address(this), amount)) revert TransferFailed();

        // Credit locked balance
        locked[onBehalfOf][asset] += amount;

        emit Deposited(onBehalfOf, onBehalfOf, asset, amount);
    }

    // -----------------------------
    // Controller-only releases
    // -----------------------------

    /**
     * @notice Withdraw locked collateral to `to`. Only SpokeController can call.
     */
    function withdrawByController(address user, address to, address asset, uint256 amount)
        external
        onlyController
        notPaused
    {
        _debitAndTransfer(user, to, asset, amount);
        emit Withdrawn(user, to, asset, amount);
    }

    /**
     * @notice Seize locked collateral from `user` to `to`. Only SpokeController can call.
     * Semantically identical to withdraw, but separate event helps indexing/analytics.
     */
    function seizeByController(address user, address to, address asset, uint256 amount)
        external
        onlyController
        notPaused
    {
        _debitAndTransfer(user, to, asset, amount);
        emit Seized(user, to, asset, amount);
    }

    function _debitAndTransfer(address user, address to, address asset, uint256 amount) internal {
        if (user == address(0) || to == address(0) || asset == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (useAllowlist && !isAssetAllowed[asset]) revert InvalidAddress();

        uint256 bal = locked[user][asset];
        if (bal < amount) revert InsufficientBalance(bal, amount);
        locked[user][asset] = bal - amount;

        if (!IERC20(asset).transfer(to, amount)) revert TransferFailed();
    }

    // -----------------------------
    // Admin: rescue (non-collateral tokens / dust)
    // -----------------------------
    /**
     * @notice Rescue tokens from the vault.
     * WARNING: this can steal user collateral if misused; guard with timelock/multisig in production.
     * In production, many teams only allow rescuing tokens that are not enabled collateral assets.
     */
    function rescueERC20(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0) || to == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (!IERC20(token).transfer(to, amount)) revert TransferFailed();
    }
}
