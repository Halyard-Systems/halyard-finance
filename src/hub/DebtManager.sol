// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * DebtManager (Hub-side)
 *
 * Owns:
 * - borrowIndex (RAY, 1e27) per debt asset
 * - totalScaledDebt per debt asset
 * - userScaledDebt per user per debt asset
 * - lastAccrual timestamp per debt asset
 *
 * Provides:
 * - accrue(asset) : updates borrowIndex using an interest-rate model from AssetRegistry
 * - mintDebt(user, asset, amount) : called after a cross-chain borrow is confirmed
 * - burnDebt(user, asset, amount) : called after a repay is confirmed
 * - debtOf(user, asset) : nominal debt = scaled * index / RAY
 *
 * Note:
 * - amounts are in the debt token's native decimals (e.g., USDC 6 decimals).
 * - we use RAY math purely for index scaling; we do NOT normalize token amounts to 1e18.
 *
 * Security:
 * - only a permissioned caller (typically HubController or a Router) can mint/burn debt.
 * - accrue() is public (like Aave) and can be called by anyone.
 */

interface IAssetRegistryDebtRates {
    struct DebtConfig {
        bool isSupported;
        uint8 decimals;
        uint256 borrowCap; // optional; DebtManager can enforce it if you want
    }

    function debtConfig(uint32 eid, address asset) external view returns (DebtConfig memory);

    /**
     * @notice Borrow rate per second in RAY (1e27), e.g. 0.05 APR ~= 0.05 / 31536000 per second.
     * Keep it simple for MVP. Later you can swap this to a full utilization-based model.
     */
    function borrowRatePerSecondRay(uint32 eid, address debtAsset) external view returns (uint256);
}

contract DebtManager is AccessManaged, ReentrancyGuard {
    // -----------------------------
    // Constants / math helpers
    // -----------------------------
    uint256 internal constant RAY = 1e27;

    // -----------------------------
    // Errors
    // -----------------------------
    error OnlyMinter();
    error OnlyOwner();
    error InvalidAddress();
    error UnsupportedDebtAsset(address asset);
    error InvalidAmount();
    error AccrualOverflow();
    error DebtUnderflow();
    error CapExceeded(uint256 cap, uint256 nextTotalDebt);

    // -----------------------------
    // Events
    // -----------------------------
    event OwnerSet(address indexed owner);
    event MinterSet(address indexed minter);
    event AssetRegistrySet(address indexed registry);

    event Accrued(address indexed asset, uint256 prevIndex, uint256 newIndex, uint256 dt, uint256 ratePerSecondRay);
    event DebtMinted(
        address indexed user, uint256 indexed eid, address indexed asset, uint256 amount, uint256 scaledAdded
    );
    event DebtBurned(
        address indexed user, uint256 indexed eid, address indexed asset, uint256 amount, uint256 scaledRemoved
    );

    /// @notice authorized caller for mint/burn (usually HubController, or a Router/Facade)
    address public minter;

    address public owner;

    IAssetRegistryDebtRates public assetRegistry;

    modifier onlyMinter() {
        if (msg.sender != minter) revert OnlyMinter();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(address _owner, address _assetRegistry) AccessManaged(_owner) {
        if (_owner == address(0) || _assetRegistry == address(0)) revert InvalidAddress();
        assetRegistry = IAssetRegistryDebtRates(_assetRegistry);
        emit AssetRegistrySet(_assetRegistry);
    }

    function setOwner(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        owner = newOwner;
        emit OwnerSet(newOwner);
    }

    function setMinter(address _minter) external onlyOwner {
        if (_minter == address(0)) revert InvalidAddress();
        minter = _minter;
        emit MinterSet(_minter);
    }

    function setAssetRegistry(address _assetRegistry) external onlyOwner {
        if (_assetRegistry == address(0)) revert InvalidAddress();
        assetRegistry = IAssetRegistryDebtRates(_assetRegistry);
        emit AssetRegistrySet(_assetRegistry);
    }

    // -----------------------------
    // Storage (chain-aware: eid => asset => ...)
    // -----------------------------

    // borrowIndex[eid][asset] in RAY (1e27). Starts at 1e27.
    mapping(uint32 => mapping(address => uint256)) public borrowIndexRay;

    // lastAccrual[eid][asset] unix timestamp (seconds)
    mapping(uint32 => mapping(address => uint40)) public lastAccrual;

    // totalScaledDebt[eid][asset] in "scaled token units" (same decimals as token, but scaled by index)
    mapping(uint32 => mapping(address => uint256)) public totalScaledDebt;

    // userScaledDebt[user][eid][asset] in scaled token units
    mapping(address => mapping(uint32 => mapping(address => uint256))) public userScaledDebt;

    // -----------------------------
    // Views
    // -----------------------------

    function scaledDebtOf(address user, uint32 eid, address asset) external view returns (uint256) {
        return userScaledDebt[user][eid][asset];
    }

    /**
     * @notice Nominal debt using the *stored* index (may be slightly stale if accrue not called recently).
     * For exactness, call accrue(eid, asset) before reading (or have your Router do it).
     */
    function debtOf(address user, uint32 eid, address asset) public view returns (uint256) {
        uint256 idx = _indexOrInit(eid, asset);
        uint256 scaled = userScaledDebt[user][eid][asset];
        // nominal = scaled * idx / RAY
        return (scaled * idx) / RAY;
    }

    function totalDebt(uint32 eid, address asset) external view returns (uint256) {
        uint256 idx = _indexOrInit(eid, asset);
        return (totalScaledDebt[eid][asset] * idx) / RAY;
    }

    // -----------------------------
    // Accrual
    // -----------------------------

    /**
     * @notice Accrue interest for a debt asset on a specific chain.
     * Anyone can call this. Mutating ops call it internally too.
     *
     * index(t+dt) = index(t) * (RAY + ratePerSecondRay * dt) / RAY
     *
     * The index is updated via a per-accrual compound-style multiplier:
     * index = index * (1 + rate * dt), where each accrual compounds the interest.
     * This is equivalent to discrete compounding at each accrual interval.
     */
    function accrue(uint32 eid, address asset) external {
        _accrue(eid, asset);
    }

    function _accrue(uint32 eid, address asset) internal {
        IAssetRegistryDebtRates.DebtConfig memory dc = assetRegistry.debtConfig(eid, asset);
        if (!dc.isSupported) revert UnsupportedDebtAsset(asset);

        uint256 idx = _indexOrInit(eid, asset);
        uint40 last = lastAccrual[eid][asset];

        // Initialize lastAccrual on first touch
        if (last == 0) {
            lastAccrual[eid][asset] = uint40(block.timestamp);
            return;
        }

        uint256 dt = block.timestamp - uint256(last);
        if (dt == 0) return;

        uint256 ratePerSecondRay = assetRegistry.borrowRatePerSecondRay(eid, asset);

        // Defensive overflow check: ratePerSecondRay * dt
        if (ratePerSecondRay != 0 && dt > type(uint256).max / ratePerSecondRay) {
            revert AccrualOverflow();
        }
        uint256 rateTimesDt = ratePerSecondRay * dt;

        // Defensive overflow check: RAY + rateTimesDt
        if (rateTimesDt > type(uint256).max - RAY) {
            revert AccrualOverflow();
        }
        // multiplier = RAY + rate * dt
        uint256 multiplier = RAY + rateTimesDt;

        // Defensive overflow check: idx * multiplier
        if (multiplier != 0 && idx > type(uint256).max / multiplier) {
            revert AccrualOverflow();
        }
        // newIdx = idx * multiplier / RAY
        uint256 newIdx = (idx * multiplier) / RAY;
        if (newIdx < idx) revert AccrualOverflow(); // sanity

        borrowIndexRay[eid][asset] = newIdx;
        lastAccrual[eid][asset] = uint40(block.timestamp);

        emit Accrued(asset, idx, newIdx, dt, ratePerSecondRay);
    }

    // -----------------------------
    // Mint / Burn (called by hub after cross-chain confirmations)
    // -----------------------------

    /**
     * @notice Mint nominal debt for a user on a specific chain.
     * Caller should be HubController/Router after BORROW_RELEASED(success=true).
     * Converts nominal `amount` into scaled units at current index, then adds to user/total.
     *
     * scaledAdded = amount * RAY / index
     */
    function mintDebt(address user, uint32 eid, address asset, uint256 amount)
        external
        onlyMinter
        returns (uint256 scaledAdded)
    {
        if (user == address(0) || asset == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        _accrue(eid, asset);

        // Optional: enforce borrowCap in nominal terms
        IAssetRegistryDebtRates.DebtConfig memory dc = assetRegistry.debtConfig(eid, asset);
        if (!dc.isSupported) revert UnsupportedDebtAsset(asset);

        if (dc.borrowCap != 0) {
            uint256 idx = _indexOrInit(eid, asset);
            uint256 currentTotalNominal = (totalScaledDebt[eid][asset] * idx) / RAY;
            uint256 nextTotalNominal = currentTotalNominal + amount;
            if (nextTotalNominal > dc.borrowCap) revert CapExceeded(dc.borrowCap, nextTotalNominal);
        }

        uint256 idxNow = _indexOrInit(eid, asset);
        scaledAdded = (amount * RAY) / idxNow;
        // If index is huge, scaledAdded could be 0 for tiny amounts; reject to avoid dust weirdness
        if (scaledAdded == 0) revert InvalidAmount();

        userScaledDebt[user][eid][asset] += scaledAdded;
        totalScaledDebt[eid][asset] += scaledAdded;

        emit DebtMinted(user, uint256(eid), asset, amount, scaledAdded);
    }

    /**
     * @notice Burn nominal debt for a user on a specific chain (repay).
     * Caller after REPAY_RECEIVED.
     *
     * scaledRemoved = amount * RAY / index
     *
     * If user repays more than they owe, we clamp to their full debt (common UX behavior).
     */
    function burnDebt(address user, uint32 eid, address asset, uint256 amount)
        external
        onlyMinter
        returns (uint256 scaledRemoved, uint256 nominalBurned)
    {
        if (user == address(0) || asset == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        _accrue(eid, asset);

        uint256 idxNow = _indexOrInit(eid, asset);
        uint256 userScaled = userScaledDebt[user][eid][asset];
        if (userScaled == 0) return (0, 0);

        // Compute requested scaled removal
        uint256 requestedScaled = (amount * RAY) / idxNow;

        // If requestedScaled is 0 but amount > 0, treat as dust and burn nothing.
        if (requestedScaled == 0) return (0, 0);

        if (requestedScaled >= userScaled) {
            // Clamp to full repay
            scaledRemoved = userScaled;
            nominalBurned = (scaledRemoved * idxNow) / RAY;

            userScaledDebt[user][eid][asset] = 0;

            uint256 tot = totalScaledDebt[eid][asset];
            if (tot < scaledRemoved) revert DebtUnderflow();
            totalScaledDebt[eid][asset] = tot - scaledRemoved;
        } else {
            scaledRemoved = requestedScaled;
            nominalBurned = amount; // approximately; exact would be scaledRemoved*idx/RAY

            userScaledDebt[user][eid][asset] = userScaled - scaledRemoved;

            uint256 tot2 = totalScaledDebt[eid][asset];
            if (tot2 < scaledRemoved) revert DebtUnderflow();
            totalScaledDebt[eid][asset] = tot2 - scaledRemoved;
        }

        emit DebtBurned(user, uint256(eid), asset, nominalBurned, scaledRemoved);
    }

    // -----------------------------
    // Internal: index init
    // -----------------------------

    function _indexOrInit(uint32 eid, address asset) internal view returns (uint256) {
        uint256 idx = borrowIndexRay[eid][asset];
        return idx == 0 ? RAY : idx;
    }
}
