// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";

import {HubAccessManager} from "./HubAccessManager.sol";

/**
 * AssetRegistry (Hub-side)
 * TODO: disabling debt and collateral should allow payback/withdrawal
 * TODO: review config change consequences
 *
 *
 * Purpose:
 * - Single source of truth for what assets are supported
 * - Risk params for collateral per chain (LTV, liquidation threshold/bonus, caps)
 * - Config for debt assets per chain (decimals, borrow caps, interest rates)
 *
 * Notes:
 * - This registry uses "canonicalAsset" addresses as keys. In a pure multi-chain system you may
 *   define canonical assets as Ethereum addresses (home chain) and map each chain's token address to that.
 */

contract AssetRegistry is AccessManaged {
    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------
    uint256 public constant RAY = 1e27;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------
    error InvalidAddress();
    error InvalidAuthority();
    error InvalidEid();
    error InvalidBps();
    error InvalidDecimals();
    error UnsupportedAsset();
    error RateTooHigh(uint256 ratePerSecondRay);

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------
    modifier validEid(uint32 eid) {
        if (eid == 0) revert InvalidEid();
        _;
    }

    modifier validAsset(address asset) {
        if (asset == address(0)) revert InvalidAddress();
        _;
    }

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------
    event CollateralConfigured(uint32 indexed eid, address indexed asset, CollateralConfig config);
    event CollateralDisabled(uint32 indexed eid, address indexed asset);

    event DebtConfigured(uint32 indexed eid, address indexed asset, DebtConfig config);
    event DebtDisabled(uint32 indexed eid, address indexed asset);

    event SpokeTokenSet(uint32 indexed eid, address indexed canonicalAsset, address indexed spokeToken);
    event MaxPriceAgeSet(address indexed asset, uint256 maxAgeSeconds);
    event BorrowRateSet(uint32 indexed eid, address indexed asset, uint256 ratePerSecondRay);

    constructor(address _authority) {
        if (_authority == address(0)) revert InvalidAuthority();
        AccessManaged(_authority);
    }

    // ---------------------------------------------------------------------
    // Config structs
    // ---------------------------------------------------------------------

    struct CollateralConfig {
        bool isSupported;

        // Risk params in basis points (bps)
        uint16 ltvBps;          // max borrow power contribution
        uint16 liqThresholdBps; // liquidation threshold contribution
        uint16 liqBonusBps;     // bonus paid to liquidator (LiquidationEngine uses)

        // Token decimals (for value calculations)
        uint8 decimals;

        // Optional caps (in token units)
        uint256 supplyCap;      // max total collateral allowed for this asset on this eid
    }

    struct DebtConfig {
        bool isSupported;
        uint8 decimals;

        // Optional caps (in token units)
        uint256 borrowCap;      // max total debt allowed for this asset
    }

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    // Collateral is chain-specific (the same canonical asset might have different risk on different chains).
    // collateralConfig[eid][canonicalAsset] => config
    mapping(uint32 => mapping(address => CollateralConfig)) private _collateralConfig;

    // Debt config is chain-specific per canonical debt asset (same as collateral)
    // debtConfig[eid][canonicalAsset] => config
    mapping(uint32 => mapping(address => DebtConfig)) private _debtConfig;

    // DebtManager interest-rate settings: borrowRatePerSecondRay[eid][asset] => ray per second
    // Simple MVP rate model: fixed per asset per chain. You can swap later to curves/utilization models.
    mapping(uint32 => mapping(address => uint256)) private _borrowRatePerSecondRay;

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function collateralConfig(uint32 eid, address asset) external view returns (CollateralConfig memory) {
        return _collateralConfig[eid][asset];
    }

    function debtConfig(uint32 eid, address asset) external view returns (DebtConfig memory) {
        return _debtConfig[eid][asset];
    }

    function borrowRatePerSecondRay(uint32 eid, address asset) external view returns (uint256) {
        return _borrowRatePerSecondRay[eid][asset];
    }

    // ---------------------------------------------------------------------
    // Admin: collateral configs (per chain)
    // ---------------------------------------------------------------------

    /**
     * @notice Configure (or update) a collateral asset for a specific chain EID.
     */
    function setCollateralConfig(
        uint32 eid,
        address asset,
        CollateralConfig calldata cfg
    ) external restricted validEid(eid) validAsset(asset) {
        _validateCollateralConfig(cfg);
        _collateralConfig[eid][asset] = cfg;
        emit CollateralConfigured(eid, asset, cfg);
    }

    function disableCollateral(uint32 eid, address asset) external restricted validEid(eid) validAsset(asset) {
        CollateralConfig storage c = _collateralConfig[eid][asset];
    function _validateCollateralConfig(CollateralConfig calldata cfg) internal pure {
        if (cfg.decimals == 0 || cfg.decimals > 36) revert InvalidDecimals();

        // ltv <= liqThreshold is typical (or equal). liqThreshold should not exceed 100%.
        if (cfg.ltvBps > 10_000 || cfg.liqThresholdBps > 10_000 || cfg.liqBonusBps > 10_000) revert InvalidBps();
        if (cfg.ltvBps > cfg.liqThresholdBps) revert InvalidBps();
        // supplyCap can be 0 (no cap)
    }
        if (cfg.ltvBps > cfg.liqThresholdBps) revert InvalidBps();
        if (cfg.decimals > 36) revert InvalidDecimals(); // generous upper bound
        // supplyCap can be 0 (no cap)
    }

    // ---------------------------------------------------------------------
    // Admin: debt configs (per chain)
    // ---------------------------------------------------------------------

    /**
     * @notice Configure (or update) a debt asset for a specific chain EID.
     */
    function setDebtConfig(uint32 eid, address asset, DebtConfig calldata cfg) external restricted validEid(eid) validAsset(asset) {
        _validateDebtConfig(cfg);
        _debtConfig[eid][asset] = cfg;
        emit DebtConfigured(eid, asset, cfg);
    }

    function disableDebt(uint32 eid, address asset) external restricted validEid(eid) validAsset(asset) {
        DebtConfig storage d = _debtConfig[eid][asset];
        d.isSupported = false;
        emit DebtDisabled(eid, asset);
    }

    function _validateDebtConfig(DebtConfig calldata cfg) internal pure {
        if (cfg.decimals == 0) revert InvalidDecimals();
        if (cfg.decimals > 36) revert InvalidDecimals();
        // borrowCap can be 0 (no cap)
    }

    // ---------------------------------------------------------------------
    // Admin: interest-rate settings for DebtManager (fixed per-asset for MVP)
    // ---------------------------------------------------------------------

    /**
     * @notice Set per-second borrow rate in basis points (bps) for a specific chain.
     *
     * Example:
     *  - 5% APR = 500 bps
     *
     */
    function setBorrowRateApr(uint32 eid, address asset, uint256 aprBps) external restricted validEid(eid) validAsset(asset) {
        if (aprBps > 50000) revert RateTooHigh(aprBps);  // Cap at 500%
        
        uint256 ratePerSecondRay = (aprBps * RAY) / (10000 * SECONDS_PER_YEAR);
        _borrowRatePerSecondRay[eid][asset] = ratePerSecondRay;
        emit BorrowRateSet(eid, asset, ratePerSecondRay);
    }

    // ---------------------------------------------------------------------
    // Optional helpers
    // ---------------------------------------------------------------------

    function isSupportedCollateral(uint32 eid, address asset) external view returns (bool) {
        return _collateralConfig[eid][asset].isSupported;
    }

    function isSupportedDebt(uint32 eid, address asset) external view returns (bool) {
        return _debtConfig[eid][asset].isSupported;
    }
}
