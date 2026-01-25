// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * RiskEngine (Hub-side)
 *
 * Responsibilities:
 * - Compute account values (collateral, borrow power, liquidation threshold)
 * - Validate borrow / withdraw / liquidation eligibility using oracle prices + risk params
 * - Perform the *PositionBook* reservations + create pendings (because PositionBook restricts these to RiskEngine)
 *
 * NOT responsible for:
 * - LayerZero receive/send (HubController)
 * - Debt interest accrual / borrowIndex (DebtManager)
 * - Position storage (PositionBook)
 * - Parameter storage (AssetRegistry) beyond reading configs
 *
 * IMPORTANT PRACTICAL NOTE (asset iteration):
 * Solidity can’t iterate a user’s mapping holdings on-chain. So this RiskEngine expects the caller
 * (your Router / UI / Keeper) to provide the set of collateral slots and debt assets to consider.
 * In production you typically maintain per-user “asset lists” in the ledger, or you restrict to
 * a small known set so the router can always supply a complete set.
 */

/// -----------------------------------------------------------------------
/// Interfaces (minimal, tailored to the PositionBook code you already have)
/// -----------------------------------------------------------------------

interface IPositionBook {
    // balances
    function collateralOf(address user, uint32 eid, address asset) external view returns (uint256);
    function reservedCollateralOf(address user, uint32 eid, address asset) external view returns (uint256);
    function availableCollateralOf(address user, uint32 eid, address asset) external view returns (uint256);

    function reservedDebtOf(address user, uint32 eid, address asset) external view returns (uint256);

    // reservations & pendings (RiskEngine-only on PositionBook)
    function reserveCollateral(address user, uint32 eid, address asset, uint256 amount) external;

    function createPendingBorrow(address user, uint32 srcEid, address debtAsset, uint256 amount, address receiver)
        external;

    function createPendingWithdraw(address user, uint32 srcEid, address asset, uint256 amount) external;
}

interface IDebtManager {
    /// @notice Returns the user's nominal debt for `asset` on chain `eid` (including accrued interest).
    function debtOf(address user, uint32 eid, address asset) external view returns (uint256);
}

interface IAssetRegistry {
    struct CollateralConfig {
        bool isSupported;
        uint16 ltvBps; // e.g. 8000 = 80%
        uint16 liqThresholdBps; // e.g. 8500 = 85%
        uint16 liqBonusBps; // not used by RiskEngine (LiquidationEngine uses it)
        uint8 decimals; // token decimals
        uint256 supplyCap; // optional, not enforced here
    }

    struct DebtConfig {
        bool isSupported;
        uint8 decimals; // token decimals
        uint256 borrowCap; // optional
    }

    function collateralConfig(uint32 eid, address asset) external view returns (CollateralConfig memory);
    function debtConfig(uint32 eid, address asset) external view returns (DebtConfig memory);
}

interface IOracle {
    /**
     * @notice Return price for asset in 1e18 units (e.g. USD price scaled by 1e18),
     * along with last update timestamp (unix seconds).
     *
     * Your Pyth adapter should provide this.
     */
    function getPriceE18(address asset) external view returns (uint256 priceE18, uint256 lastUpdatedAt);
}

/// -----------------------------------------------------------------------
/// RiskEngine
/// -----------------------------------------------------------------------
contract RiskEngine is AccessManaged, ReentrancyGuard {
    // -----------------------------
    // Errors
    // -----------------------------
    error InvalidAddress();
    error InvalidAmount();
    error UnsupportedCollateral(uint32 eid, address asset);
    error UnsupportedDebtAsset(address asset);
    error PriceUnavailable(address asset);
    error InsufficientBorrowPower(uint256 borrowPowerE18, uint256 nextDebtValueE18);
    error WouldBeUndercollateralized(uint256 liqValueE18, uint256 nextDebtValueE18);
    error InsufficientAvailableCollateral(uint256 available, uint256 requested);
    error DuplicateCollateralSlot(uint32 eid, address asset);

    // -----------------------------
    // Events
    // -----------------------------
    event DependenciesSet(
        address indexed positionBook, address indexed debtManager, address indexed assetRegistry, address oracle
    );

    // -----------------------------
    // Admin / pointers
    // -----------------------------
    IPositionBook public positionBook;
    IDebtManager public debtManager;
    IAssetRegistry public assetRegistry;
    IOracle public oracle;

    constructor(address _authority) AccessManaged(_authority) {
        if (_authority == address(0)) revert InvalidAddress();
    }

    /**
     * @notice Set the dependencies for the RiskEngine.
     * - Restricted to default ADMIN role
     */
    function setDependencies(address _positionBook, address _debtManager, address _assetRegistry, address _oracle)
        external
        restricted
    {
        if (
            _positionBook == address(0) || _debtManager == address(0) || _assetRegistry == address(0)
                || _oracle == address(0)
        ) {
            revert InvalidAddress();
        }
        positionBook = IPositionBook(_positionBook);
        debtManager = IDebtManager(_debtManager);
        assetRegistry = IAssetRegistry(_assetRegistry);
        oracle = IOracle(_oracle);
        emit DependenciesSet(_positionBook, _debtManager, _assetRegistry, _oracle);
    }

    // -----------------------------
    // Types for “asset set” input
    // -----------------------------
    struct CollateralSlot {
        uint32 eid; // chain EID where collateral is custodied
        address asset; // collateral token address (canonical registry key)
    }

    struct DebtSlot {
        uint32 eid; // chain EID where debt was borrowed to
        address asset; // debt token address (canonical registry key)
    }

    // -----------------------------
    // Public view: account data
    // -----------------------------

    /**
     * @notice Compute the user’s collateral value, borrow power, liquidation threshold value, and total debt value,
     * all in 1e18 “USD” units (or whatever unit your oracle uses).
     *
     * `collateralSlots` must include every collateral position you want considered.
     * `debtSlots` should include every possible debt slot the user may have borrowed (or you track this elsewhere).
     */
    function accountData(address user, CollateralSlot[] calldata collateralSlots, DebtSlot[] calldata debtSlots)
        external
        view
        returns (
            uint256 collateralValueE18,
            uint256 borrowPowerE18,
            uint256 liquidationValueE18,
            uint256 debtValueE18,
            uint256 healthFactorE18
        )
    {
        (collateralValueE18, borrowPowerE18, liquidationValueE18) = _collateralSums(user, collateralSlots);
        debtValueE18 = _debtSum(user, debtSlots);

        // Health factor = liquidationValue / debtValue (both in E18)
        // If no debt, treat as "infinite" — return max uint
        if (debtValueE18 == 0) {
            healthFactorE18 = type(uint256).max;
        } else {
            healthFactorE18 = (liquidationValueE18 * 1e18) / debtValueE18;
        }
    }

    // -----------------------------
    // Validation helpers (view)
    // -----------------------------

    function canBorrow(
        address user,
        uint32 dstEid,
        address debtAsset,
        uint256 borrowAmount,
        CollateralSlot[] calldata collateralSlots,
        DebtSlot[] calldata debtSlots
    ) external view returns (bool ok, uint256 nextHealthFactorE18) {
        if (borrowAmount == 0) revert InvalidAmount();

        // Ensure supported debt asset on destination chain
        IAssetRegistry.DebtConfig memory dc = assetRegistry.debtConfig(dstEid, debtAsset);
        if (!dc.isSupported) revert UnsupportedDebtAsset(debtAsset);

        (, uint256 borrowPowerE18,) = _collateralSums(user, collateralSlots);
        uint256 debtValueE18 = _debtSum(user, debtSlots);

        uint256 borrowValueE18 = _valueE18Token(debtAsset, borrowAmount, dc.decimals);
        uint256 nextDebtValueE18 = debtValueE18 + borrowValueE18;

        if (nextDebtValueE18 == 0) {
            return (true, type(uint256).max);
        }
        nextHealthFactorE18 = (borrowPowerE18 * 1e18) / nextDebtValueE18;
        ok = nextHealthFactorE18 >= 1e18;
    }

    function canWithdraw(
        address user,
        uint32 eid,
        address collateralAsset,
        uint256 withdrawAmount,
        CollateralSlot[] calldata collateralSlots,
        DebtSlot[] calldata debtSlots
    ) external view returns (bool ok, uint256 nextHealthFactorE18) {
        if (withdrawAmount == 0) revert InvalidAmount();

        // Start from current sums
        (uint256 collateralValueE18, uint256 borrowPowerE18, uint256 liqValueE18) =
            _collateralSums(user, collateralSlots);
        uint256 debtValueE18 = _debtSum(user, debtSlots);

        // Remove withdrawAmount from that slot’s contribution (using its config)
        IAssetRegistry.CollateralConfig memory cc = assetRegistry.collateralConfig(eid, collateralAsset);
        if (!cc.isSupported) revert UnsupportedCollateral(eid, collateralAsset);

        uint256 withdrawValueE18 = _valueE18Token(collateralAsset, withdrawAmount, cc.decimals);

        // subtract from totals (guard underflow)
        if (withdrawValueE18 > collateralValueE18) collateralValueE18 = 0;
        else collateralValueE18 -= withdrawValueE18;

        // Borrow power uses LTV
        uint256 withdrawBorrowPowerE18 = (withdrawValueE18 * cc.ltvBps) / 10_000;
        if (withdrawBorrowPowerE18 > borrowPowerE18) borrowPowerE18 = 0;
        else borrowPowerE18 -= withdrawBorrowPowerE18;

        // Liquidation value uses liq threshold
        uint256 withdrawLiqValueE18 = (withdrawValueE18 * cc.liqThresholdBps) / 10_000;
        if (withdrawLiqValueE18 > liqValueE18) liqValueE18 = 0;
        else liqValueE18 -= withdrawLiqValueE18;

        // If debt exists, must stay safe at liquidation threshold
        if (debtValueE18 == 0) {
            ok = true;
            nextHealthFactorE18 = type(uint256).max;
        } else {
            nextHealthFactorE18 = (liqValueE18 * 1e18) / debtValueE18;
            ok = nextHealthFactorE18 >= 1e18;
        }
    }

    // -----------------------------
    // State-changing entrypoints (called by your Router)
    // These do: validate -> reserve/create pending in PositionBook
    // -----------------------------

    /**
     * @notice Validate and create a pending borrow.
     * - Reserves debt headroom via PositionBook.createPendingBorrow (which increments reservedDebt).
     * - Your Router should then instruct HubController to send CMD_RELEASE_BORROW to the spoke.
     * - Restricted to ROLE_ROUTER
     *
     * `debtSlots` should include debtAsset (and any other assets user might already owe).
     */
    function validateAndCreateBorrow(
        bytes32 borrowId,
        address user,
        uint32 srcEid,
        address debtAsset,
        uint256 amount,
        address receiver,
        CollateralSlot[] calldata collateralSlots,
        DebtSlot[] calldata debtSlots
    ) external restricted {
        if (borrowId == bytes32(0)) revert InvalidAmount();
        if (user == address(0) || receiver == address(0) || debtAsset == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (srcEid == 0) revert InvalidAmount();

        // Supported debt asset on destination chain
        IAssetRegistry.DebtConfig memory dc = assetRegistry.debtConfig(srcEid, debtAsset);
        if (!dc.isSupported) revert UnsupportedDebtAsset(debtAsset);

        // Compute borrow power using LTV (not liquidation threshold)
        (, uint256 borrowPowerE18,) = _collateralSums(user, collateralSlots);

        uint256 currentDebtValueE18 = _debtSum(user, debtSlots);
        uint256 newBorrowValueE18 = _valueE18Token(debtAsset, amount, dc.decimals);
        uint256 nextDebtValueE18 = currentDebtValueE18 + newBorrowValueE18;

        if (nextDebtValueE18 > borrowPowerE18) {
            revert InsufficientBorrowPower(borrowPowerE18, nextDebtValueE18);
        }

        // Create pending + reserve debt in PositionBook (RiskEngine-only).
        positionBook.createPendingBorrow(user, srcEid, debtAsset, amount, receiver);
    }

    /**
     * @notice Validate and create a pending withdraw.
     * - Reserves collateral (PositionBook.reserveCollateral)
     * - Creates pending withdraw (PositionBook.createPendingWithdraw)
     * - Router then asks HubController to send CMD_RELEASE_WITHDRAW to the spoke.
     * - Restricted to ROLE_ROUTER
     */
    function validateAndCreateWithdraw(
        bytes32 withdrawId,
        address user,
        uint32 srcEid,
        address collateralAsset,
        uint256 amount,
        address receiver,
        CollateralSlot[] calldata collateralSlots,
        DebtSlot[] calldata debtSlots
    ) external restricted {
        if (withdrawId == bytes32(0)) revert InvalidAmount();
        if (user == address(0) || receiver == address(0) || collateralAsset == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (srcEid == 0) revert InvalidAmount();

        // Check supported collateral and available balance
        IAssetRegistry.CollateralConfig memory cc = assetRegistry.collateralConfig(srcEid, collateralAsset);
        if (!cc.isSupported) revert UnsupportedCollateral(srcEid, collateralAsset);

        uint256 available = positionBook.availableCollateralOf(user, srcEid, collateralAsset);
        if (available < amount) revert InsufficientAvailableCollateral(available, amount);

        // Ensure withdraw keeps user safe at liquidation threshold (health factor >= 1.0)
        (bool ok,) = this.canWithdraw(user, srcEid, collateralAsset, amount, collateralSlots, debtSlots);
        if (!ok) {
            revert WouldBeUndercollateralized(0, 0);
        }

        // Reserve collateral and create pending
        // TODO: this happens elsewhere
        //positionBook.reserveCollateral(user, srcEid, collateralAsset, amount);
        //positionBook.createPendingWithdraw(user, srcEid, collateralAsset, amount);
    }

    // -----------------------------
    // Internal: collateral sums
    // -----------------------------
    /// @notice Computes aggregate collateral value, borrow power, and liquidation value.
    /// @dev Reverts with DuplicateCollateralSlot if the same (eid, asset) pair appears more than once
    ///      in collateralSlots. This prevents double-counting collateral. Uses an in-memory array
    ///      to track seen pairs (O(n²) but acceptable for typical small slot counts) to avoid
    ///      storage writes.
    function _collateralSums(address user, CollateralSlot[] calldata collateralSlots)
        internal
        view
        returns (uint256 collateralValueE18, uint256 borrowPowerE18, uint256 liquidationValueE18)
    {
        uint256 n = collateralSlots.length;

        // Track seen (eid, asset) pairs to prevent duplicate counting
        bytes32[] memory seenKeys = new bytes32[](n);
        uint256 seenCount = 0;

        for (uint256 i = 0; i < n; i++) {
            CollateralSlot calldata slot = collateralSlots[i];

            // Check for duplicates and add to seen list
            seenKeys[seenCount] = _validateUniqueCollateralSlot(seenKeys, seenCount, slot.eid, slot.asset);
            seenCount++;

            IAssetRegistry.CollateralConfig memory cc = assetRegistry.collateralConfig(slot.eid, slot.asset);
            if (!cc.isSupported) revert UnsupportedCollateral(slot.eid, slot.asset);

            // Use available collateral (excludes reserved withdrawals/seizures in-flight)
            uint256 amount = positionBook.availableCollateralOf(user, slot.eid, slot.asset);
            if (amount == 0) continue;

            // Calculate value and accumulate results
            uint256 valueE18 = _valueE18Token(slot.asset, amount, cc.decimals);

            collateralValueE18 += valueE18;
            borrowPowerE18 += (valueE18 * cc.ltvBps) / 10_000;
            liquidationValueE18 += (valueE18 * cc.liqThresholdBps) / 10_000;
        }
    }

    /// @notice Validates that a collateral slot hasn't been seen before and returns its unique key
    /// @dev Reverts with DuplicateCollateralSlot if the (eid, asset) pair already exists in seenKeys
    /// @param seenKeys Array of previously seen slot keys
    /// @param seenCount Number of entries currently in seenKeys
    /// @param eid Chain EID for the collateral
    /// @param asset Asset address for the collateral
    /// @return key The unique key for this (eid, asset) pair
    function _validateUniqueCollateralSlot(bytes32[] memory seenKeys, uint256 seenCount, uint32 eid, address asset)
        internal
        pure
        returns (bytes32 key)
    {
        key = keccak256(abi.encodePacked(eid, asset));

        for (uint256 j = 0; j < seenCount; j++) {
            if (seenKeys[j] == key) revert DuplicateCollateralSlot(eid, asset);
        }
    }

    // -----------------------------
    // Internal: debt sum (includes reservedDebt)
    // -----------------------------
    function _debtSum(address user, DebtSlot[] calldata debtSlots) internal view returns (uint256 debtValueE18) {
        uint256 n = debtSlots.length;

        for (uint256 i = 0; i < n; i++) {
            DebtSlot calldata slot = debtSlots[i];
            if (slot.asset == address(0)) continue;

            IAssetRegistry.DebtConfig memory dc = assetRegistry.debtConfig(slot.eid, slot.asset);
            if (!dc.isSupported) revert UnsupportedDebtAsset(slot.asset);

            uint256 nominalDebt = debtManager.debtOf(user, slot.eid, slot.asset);
            uint256 reservedNominal = positionBook.reservedDebtOf(user, slot.eid, slot.asset); // in-flight borrows
            uint256 totalNominal = nominalDebt + reservedNominal;
            if (totalNominal == 0) continue;

            debtValueE18 += _valueE18Token(slot.asset, totalNominal, dc.decimals);
        }
    }

    // TODO: implement against actual oracle
    function _valueE18Token(address asset, uint256 amount, uint8 decimals) internal view returns (uint256) {
        uint256 ts;
        uint256 priceE18;

        (priceE18, ts) = oracle.getPriceE18(asset);
        if (priceE18 == 0) revert PriceUnavailable(asset);

        return (amount * priceE18) / (10 ** uint256(decimals));
    }
}
