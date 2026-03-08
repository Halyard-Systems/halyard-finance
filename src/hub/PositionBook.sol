// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
/**
 * PositionBook (Hub-side) - storage for user positions.
 *
 * Responsibility:
 * - Store collateral balances per user per chain (EID) per asset.
 * - Store pending cross-chain actions (borrow/withdraw/liquidation) and reservations to make async flows safe.
 * - Provide read APIs for RiskEngine and LiquidationEngine to evaluate positions.
 *
 * Not responsible for:
 * - Interest accrual / borrowIndex (DebtManager owns that)
 * - Health factor / pricing (RiskEngine owns that, using Pyth or oracle adapter)
 * - LayerZero receive/send (HubController owns that)
 *
 * Typical call graph:
 * - Users call high-level protocol entrypoints (often a "Router" or LiquidationEngine / a Facade).
 * - HubController finalizes pending actions after receiving receipts from spokes.
 * - RiskEngine reads PositionBook + DebtManager to validate actions.
 *
 * This contract uses simple access control with explicit roles. In a production system you'd
 * likely move to OpenZeppelin AccessControl, but this is deliberately dependency-light.
 */

contract PositionBook is AccessManaged {
    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------
    //error OnlyHubController();
    //error OnlyRiskEngine();
    //error OnlyLiquidationEngine();
    error BorrowAlreadyPending();
    error BorrowNotFinalized();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidEid();
    error UnknownPending(bytes32 id);
    error AlreadyFinalized(bytes32 id);
    error NotEnoughCollateral(uint256 available, uint256 required);
    error NotPending(bytes32 id);
    error ReservationUnderflow();
    error CollateralUnderflow();
    error CollateralOverflow(); // (rare) included for completeness
    error DebtAssetNotConfigured(); // if you choose to store allowed debt assets here (optional)
    error WithdrawAlreadyPending();

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------
    // event OwnerSet(address indexed owner);
    // event HubControllerSet(address indexed hubController);
    // event RiskEngineSet(address indexed riskEngine);
    // event LiquidationEngineSet(address indexed liquidationEngine);

    event CollateralCredited(address user, uint32 indexed eid, address indexed asset, uint256 amount);
    event CollateralDebited(address user, uint32 indexed eid, address indexed asset, uint256 amount);

    event BorrowPendingCreated(address user, uint32 indexed dstEid, address asset, uint256 amount, address receiver);
    event BorrowPendingFinalized(address user, bool success);

    event WithdrawPendingCreated(address indexed user, uint32 indexed srcEid, address asset, uint256 amount);
    event WithdrawPendingFinalized(address user, bool success);

    event LiquidationPendingCreated(
        bytes32 indexed liqId,
        address indexed user,
        uint32 indexed seizeEid,
        address seizeAsset,
        uint256 seizeAmount,
        address liquidator
    );
    event LiquidationPendingFinalized(bytes32 indexed liqId, bool success);

    // ---------------------------------------------------------------------
    // Roles / pointers
    // ---------------------------------------------------------------------
    // address public hubController;       // LayerZero receiver/dispatcher (finalizes receipts)
    // address public riskEngine;          // validates (read-only here; may also call "reserve" helpers)
    // address public liquidationEngine;   // creates liquidation pendings

    // modifier onlyHubController() {
    //     if (msg.sender != hubController) revert OnlyHubController();
    //     _;
    // }

    // modifier onlyRiskEngine() {
    //     if (msg.sender != riskEngine) revert OnlyRiskEngine();
    //     _;
    // }

    // modifier onlyLiquidationEngine() {
    //     if (msg.sender != liquidationEngine) revert OnlyLiquidationEngine();
    //     _;
    // }

    // constructor(address _owner) Ownable(_owner) {
    //     if (_owner == address(0)) revert InvalidAddress();
    // }

    constructor(address _authority) AccessManaged(_authority) {
        if (_authority == address(0)) revert InvalidAddress();
    }

    struct ChainAsset {
        uint32 eid;
        address asset;
    }

    // ---------------------------------------------------------------------
    // Canonical collateral balances (hub-side book)
    // ---------------------------------------------------------------------
    // collateral[user][eid][asset] => amount
    mapping(address => mapping(uint32 => mapping(address => uint256))) private _collateral;

    // Track which (eid, asset) pairs each user has collateral in
    mapping(address => ChainAsset[]) private _collateralAssets;
    mapping(address => mapping(uint32 => mapping(address => bool))) private _hasCollateralAsset;

    // reservedCollateral[user][eid][asset] => amount reserved for pending withdraw or pending seizure
    mapping(address => mapping(uint32 => mapping(address => uint256))) private _reservedCollateral;

    function collateralOf(address user, uint32 eid, address asset) external view returns (uint256) {
        return _collateral[user][eid][asset];
    }

    function collateralAssetsOf(address user) external view returns (ChainAsset[] memory) {
        return _collateralAssets[user];
    }

    function reservedCollateralOf(address user, uint32 eid, address asset) external view returns (uint256) {
        return _reservedCollateral[user][eid][asset];
    }

    function availableCollateralOf(address user, uint32 eid, address asset) public view returns (uint256) {
        uint256 bal = _collateral[user][eid][asset];
        uint256 res = _reservedCollateral[user][eid][asset];
        unchecked {
            return bal > res ? bal - res : 0;
        }
    }

    /// @notice Credit collateral after a spoke deposit receipt.
    /// Called by HubController upon receiving DEPOSIT_CREDITED.
    function creditCollateral(address user, uint32 eid, address asset, uint256 amount) external restricted {
        if (user == address(0) || asset == address(0)) revert InvalidAddress();
        if (eid == 0) revert InvalidEid();
        if (amount == 0) revert InvalidAmount();

        _collateral[user][eid][asset] += amount;

        // Track this asset if not already tracked
        if (!_hasCollateralAsset[user][eid][asset]) {
            _collateralAssets[user].push(ChainAsset({eid: eid, asset: asset}));
            _hasCollateralAsset[user][eid][asset] = true;
        }

        emit CollateralCredited(user, eid, asset, amount);
    }

    /// @notice Internal debit used only during finalization, after spoke confirms funds moved.
    function _debitCollateral(address user, uint32 eid, address asset, uint256 amount) internal {
        uint256 bal = _collateral[user][eid][asset];
        if (bal < amount) revert CollateralUnderflow();
        _collateral[user][eid][asset] = bal - amount;

        // If balance is now zero, remove from tracking
        if (_collateral[user][eid][asset] == 0 && _hasCollateralAsset[user][eid][asset]) {
            _removeCollateralAsset(user, eid, asset);
            _hasCollateralAsset[user][eid][asset] = false;
        }

        emit CollateralDebited(user, eid, asset, amount);
    }

    /// @notice Reserve collateral for a pending withdraw.
    /// Invoked by RiskEngine after it approves withdraw intent.
    function reserveCollateral(address user, uint32 eid, address asset, uint256 amount) external restricted {
        if (user == address(0) || asset == address(0)) revert InvalidAddress();
        if (eid == 0) revert InvalidEid();
        if (amount == 0) revert InvalidAmount();

        uint256 avail = availableCollateralOf(user, eid, asset);
        if (avail < amount) revert ReservationUnderflow();
        _reservedCollateral[user][eid][asset] += amount;
    }

    /// @notice Release collateral reservation (on failure or cancellation).
    function unreserveCollateral(address user, uint32 eid, address asset, uint256 amount) external restricted {
        if (user == address(0) || asset == address(0)) revert InvalidAddress();
        if (eid == 0) revert InvalidEid();
        if (amount == 0) revert InvalidAmount();

        uint256 res = _reservedCollateral[user][eid][asset];
        if (res < amount) revert ReservationUnderflow();
        _reservedCollateral[user][eid][asset] = res - amount;
    }

    // ---------------------------------------------------------------------
    // Pending borrows (hub-reserved debt; actual debt minted by DebtManager on success)
    // ---------------------------------------------------------------------

    struct PendingBorrow {
        address user;
        uint32 dstEid;
        address asset; // debt asset (on destination chain)
        uint256 amount; // nominal amount (token units)
        address receiver; // where spoke releases funds
        bool exists;
        bool finalized;
    }

    mapping(bytes32 => PendingBorrow) public pendingBorrow;

    // reservedDebt[user][eid][asset] => nominal reserved while borrow is in-flight
    mapping(address => mapping(uint32 => mapping(address => uint256))) private _reservedDebt;

    function reservedDebtOf(address user, uint32 eid, address asset) external view returns (uint256) {
        return _reservedDebt[user][eid][asset];
    }

    /// @notice Create a pending borrow and reserve debt headroom while the spoke releases funds.
    /// Called by a router after RiskEngine approves the borrow.
    function createPendingBorrow(
        bytes32 borrowId,
        address user,
        uint32 dstEid,
        address debtAsset,
        uint256 amount,
        address receiver
    ) external restricted {
        if (user == address(0) || debtAsset == address(0) || receiver == address(0)) {
            revert InvalidAddress();
        }
        if (dstEid == 0) revert InvalidEid();
        if (amount == 0) revert InvalidAmount();

        PendingBorrow storage p = pendingBorrow[borrowId];
        if (p.exists) revert BorrowAlreadyPending(); // already exists

        pendingBorrow[borrowId] = PendingBorrow({
            user: user,
            dstEid: dstEid,
            asset: debtAsset,
            amount: amount,
            receiver: receiver,
            exists: true,
            finalized: false
        });

        _reservedDebt[user][dstEid][debtAsset] += amount;

        emit BorrowPendingCreated(user, dstEid, debtAsset, amount, receiver);
    }

    /// @notice Finalize a pending borrow after spoke receipt.
    /// On success: keeps the reservation until DebtManager mints debt (caller should mint immediately).
    /// On failure: releases reservation and marks finalized.
    ///
    /// Called by HubController upon BORROW_RELEASED receipt.
    function finalizePendingBorrow(bytes32 borrowId, bool success)
        external
        restricted
        returns (PendingBorrow memory p)
    {
        PendingBorrow storage s = pendingBorrow[borrowId];
        if (!s.exists) revert UnknownPending(borrowId);
        if (s.finalized) revert AlreadyFinalized(borrowId);

        s.finalized = true;

        if (!success) {
            // release reserved debt since funds weren't delivered
            uint256 res = _reservedDebt[s.user][s.dstEid][s.asset];
            if (res < s.amount) revert ReservationUnderflow();
            _reservedDebt[s.user][s.dstEid][s.asset] = res - s.amount;
        }

        emit BorrowPendingFinalized(s.user, success);
        return s;
    }

    /// @notice After DebtManager mints the real debt (on success), clear the reservation.
    /// You can call this from the same finalize handler in HubController.
    function clearBorrowReservation(bytes32 borrowId) external restricted {
        PendingBorrow storage s = pendingBorrow[borrowId];
        if (!s.exists) revert UnknownPending(borrowId);
        if (!s.finalized) revert BorrowNotFinalized();

        uint256 res = _reservedDebt[s.user][s.dstEid][s.asset];
        if (res < s.amount) revert ReservationUnderflow();
        _reservedDebt[s.user][s.dstEid][s.asset] = res - s.amount;
    }

    // ---------------------------------------------------------------------
    // Pending withdraws (reserve collateral until spoke releases)
    // ---------------------------------------------------------------------

    struct PendingWithdraw {
        address user;
        uint32 srcEid; // chain where collateral is held / to be released from
        address asset;
        uint256 amount;
        bool exists;
    }

    mapping(bytes32 => PendingWithdraw) public pendingWithdraw;

    /// @notice Create pending withdraw. Assumes reserveCollateral(...) was already performed
    /// by RiskEngine after validating health factor using oracle prices.
    /// Called by HubController after RiskEngine approval.
    function createPendingWithdraw(bytes32 withdrawId, address user, uint32 srcEid, address asset, uint256 amount)
        external
        restricted
    {
        if (user == address(0) || asset == address(0)) revert InvalidAddress();
        if (srcEid == 0) revert InvalidEid();
        if (amount == 0) revert InvalidAmount();

        PendingWithdraw storage p = pendingWithdraw[withdrawId];
        if (p.exists) revert WithdrawAlreadyPending();

        pendingWithdraw[withdrawId] =
            PendingWithdraw({user: user, srcEid: srcEid, asset: asset, amount: amount, exists: true});

        emit WithdrawPendingCreated(user, srcEid, asset, amount);
    }

    /// @notice Finalize a withdraw after spoke receipt.
    /// On success: debit collateral + reduce reservation.
    /// On failure: just reduce reservation.
    ///
    /// Called by HubController upon WITHDRAW_RELEASED receipt.
    function finalizePendingWithdraw(bytes32 withdrawId, bool success)
        external
        restricted
        returns (address user, uint32 srcEid, address asset, uint256 amount, bool exists)
    {
        PendingWithdraw storage s = pendingWithdraw[withdrawId];
        if (!s.exists) revert UnknownPending(withdrawId);

        // Copy to memory before clearing storage
        user = s.user;
        srcEid = s.srcEid;
        asset = s.asset;
        amount = s.amount;
        exists = s.exists;

        // Always remove the reservation for this withdraw
        uint256 res = _reservedCollateral[user][srcEid][asset];
        if (res < amount) revert ReservationUnderflow();
        _reservedCollateral[user][srcEid][asset] = res - amount;

        if (success) {
            _debitCollateral(user, srcEid, asset, amount);
        }

        // Clear pending state so user can withdraw again
        delete pendingWithdraw[withdrawId];

        emit WithdrawPendingFinalized(user, success);
    }

    // ---------------------------------------------------------------------
    // Pending liquidation (reserve collateral to be seized until spoke confirms)
    // ---------------------------------------------------------------------

    struct PendingLiquidation {
        address user; // account being liquidated
        uint32 seizeEid; // chain where collateral is seized
        address seizeAsset;
        uint256 seizeAmount;
        address liquidator;
        bool exists;
        bool finalized;
    }

    mapping(bytes32 => PendingLiquidation) public pendingLiquidation;

    /// @notice Create pending liquidation. Typically called by LiquidationEngine after it decides seize amounts.
    /// This reserves collateral so the user can’t withdraw it while seizure is in-flight.
    function createPendingLiquidation(
        bytes32 liqId,
        address user,
        uint32 seizeEid,
        address seizeAsset,
        uint256 seizeAmount,
        address liquidator
    ) external restricted {
        if (liqId == bytes32(0)) revert InvalidAmount();
        if (user == address(0) || seizeAsset == address(0) || liquidator == address(0)) revert InvalidAddress();
        if (seizeEid == 0) revert InvalidEid();
        if (seizeAmount == 0) revert InvalidAmount();

        PendingLiquidation storage p = pendingLiquidation[liqId];
        if (p.exists) revert NotPending(liqId);

        // Reserve collateral to be seized
        uint256 avail = availableCollateralOf(user, seizeEid, seizeAsset);
        if (avail < seizeAmount) revert ReservationUnderflow();
        _reservedCollateral[user][seizeEid][seizeAsset] += seizeAmount;

        pendingLiquidation[liqId] = PendingLiquidation({
            user: user,
            seizeEid: seizeEid,
            seizeAsset: seizeAsset,
            seizeAmount: seizeAmount,
            liquidator: liquidator,
            exists: true,
            finalized: false
        });

        emit LiquidationPendingCreated(liqId, user, seizeEid, seizeAsset, seizeAmount, liquidator);
    }

    /// @notice Finalize pending liquidation after spoke seizure receipt.
    /// On success: debit collateral and drop reservation.
    /// On failure: just drop reservation.
    ///
    /// Called by HubController upon COLLATERAL_SEIZED receipt.
    function finalizePendingLiquidation(bytes32 liqId, bool success)
        external
        restricted
        returns (PendingLiquidation memory l)
    {
        PendingLiquidation storage s = pendingLiquidation[liqId];
        if (!s.exists) revert UnknownPending(liqId);
        if (s.finalized) revert AlreadyFinalized(liqId);
        s.finalized = true;

        // remove reservation
        uint256 res = _reservedCollateral[s.user][s.seizeEid][s.seizeAsset];
        if (res < s.seizeAmount) revert ReservationUnderflow();
        _reservedCollateral[s.user][s.seizeEid][s.seizeAsset] = res - s.seizeAmount;

        if (success) {
            _debitCollateral(s.user, s.seizeEid, s.seizeAsset, s.seizeAmount);
        }

        emit LiquidationPendingFinalized(liqId, success);
        return s;
    }

    // ---------------------------------------------------------------------
    // Bulk read helpers (optional but useful for RiskEngine)
    // ---------------------------------------------------------------------

    /// @notice Read multiple collateral balances in one call (for off-chain / RiskEngine convenience).
    function batchCollateralOf(address user, uint32[] calldata eids, address[] calldata assets)
        external
        view
        returns (uint256[] memory balances, uint256[] memory reserved, uint256[] memory available)
    {
        if (eids.length != assets.length) revert InvalidAmount();
        uint256 n = eids.length;
        balances = new uint256[](n);
        reserved = new uint256[](n);
        available = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            uint32 eid = eids[i];
            address asset = assets[i];
            uint256 b = _collateral[user][eid][asset];
            uint256 r = _reservedCollateral[user][eid][asset];
            balances[i] = b;
            reserved[i] = r;
            available[i] = b > r ? b - r : 0;
        }
    }

    /// @notice Check if a ChainAsset exists in the array
    function _containsChainAsset(ChainAsset[] storage assets, uint32 eid, address asset) internal view returns (bool) {
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].eid == eid && assets[i].asset == asset) {
                return true;
            }
        }
        return false;
    }

    /// @notice Remove a ChainAsset from the array (swap and pop for gas efficiency)
    function _removeCollateralAsset(address user, uint32 eid, address asset) internal {
        ChainAsset[] storage assets = _collateralAssets[user];
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].eid == eid && assets[i].asset == asset) {
                // Swap with last element and pop
                if (i != assets.length - 1) {
                    assets[i] = assets[assets.length - 1];
                }
                assets.pop();
                return;
            }
        }
    }
}
