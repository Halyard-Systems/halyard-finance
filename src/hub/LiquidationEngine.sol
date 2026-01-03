// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * AssetRegistry (Hub-side) — in the 6-contract hub design.
 *
 * Purpose:
 * - Single source of truth for what assets are supported
 * - Risk params for collateral (LTV, liquidation threshold/bonus, caps)
 * - Config for debt assets (decimals, borrow caps)
 * - Oracle staleness settings (max price age)
 * - Interest-rate settings for DebtManager (borrowRatePerSecondRay)
 * - Cross-chain token mapping: (eid, canonicalAsset) -> spokeTokenAddress
 *
 * Notes:
 * - This registry uses "canonicalAsset" addresses as keys. In a pure multi-chain system you may
 *   define canonical assets as Ethereum addresses (home chain) and map each chain’s token address to that.
 * - For MVP, assume the canonical asset address is the L1 (Ethereum) token address. For non-L1 chains,
 *   the spoke token address can be a bridged representation. The mapping lives here.
 *
 * Governance / admin:
 * - For now, simple owner-based access control.
 * - In production, put this behind a timelock / governor.
 */

contract LiquidationEngine {
    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------
    uint256 internal constant RAY = 1e27;

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------
    error OnlyOwner();
    error InvalidAddress();
    error InvalidEid();
    error InvalidBps();
    error InvalidDecimals();
    error UnsupportedAsset();
    error RateTooHigh(uint256 ratePerSecondRay);
    error InvalidMaxAge();

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------
    event OwnerSet(address indexed owner);

    event CollateralConfigured(uint32 indexed eid, address indexed asset, CollateralConfig config);
    event CollateralDisabled(uint32 indexed eid, address indexed asset);

    event DebtConfigured(address indexed asset, DebtConfig config);
    event DebtDisabled(address indexed asset);

    event SpokeTokenSet(uint32 indexed eid, address indexed canonicalAsset, address indexed spokeToken);
    event MaxPriceAgeSet(address indexed asset, uint256 maxAgeSeconds);
    event BorrowRateSet(address indexed asset, uint256 ratePerSecondRay);

    // ---------------------------------------------------------------------
    // Ownership
    // ---------------------------------------------------------------------
    address public owner;

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(address _owner) {
        if (_owner == address(0)) revert InvalidAddress();
        owner = _owner;
        emit OwnerSet(_owner);
    }

    function setOwner(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        owner = newOwner;
        emit OwnerSet(newOwner);
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

    // Debt config is global per canonical debt asset
    mapping(address => DebtConfig) private _debtConfig;

    // Cross-chain token address mapping: spokeTokenAddress[eid][canonicalAsset] => spoke token address
    mapping(uint32 => mapping(address => address)) private _spokeTokenAddress;

    // Oracle staleness settings: maxPriceAgeSeconds[asset] => seconds (0 disables staleness check)
    mapping(address => uint256) private _maxPriceAgeSeconds;

    // DebtManager interest-rate settings: borrowRatePerSecondRay[asset] => ray per second
    // Simple MVP rate model: fixed per asset. You can swap later to curves/utilization models.
    mapping(address => uint256) private _borrowRatePerSecondRay;

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function collateralConfig(uint32 eid, address asset) external view returns (CollateralConfig memory) {
        return _collateralConfig[eid][asset];
    }

    function debtConfig(address asset) external view returns (DebtConfig memory) {
        return _debtConfig[asset];
    }

    function spokeTokenAddress(uint32 eid, address canonicalAsset) external view returns (address) {
        return _spokeTokenAddress[eid][canonicalAsset];
    }

    function maxPriceAgeSeconds(address asset) external view returns (uint256) {
        return _maxPriceAgeSeconds[asset];
    }

    function borrowRatePerSecondRay(address asset) external view returns (uint256) {
        return _borrowRatePerSecondRay[asset];
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
    ) external onlyOwner {
        if (eid == 0) revert InvalidEid();
        if (asset == address(0)) revert InvalidAddress();
        _validateCollateralConfig(cfg);

        _collateralConfig[eid][asset] = cfg;
        emit CollateralConfigured(eid, asset, cfg);
    }

    function disableCollateral(uint32 eid, address asset) external onlyOwner {
        if (eid == 0) revert InvalidEid();
        if (asset == address(0)) revert InvalidAddress();

        CollateralConfig storage c = _collateralConfig[eid][asset];
        c.isSupported = false;
        emit CollateralDisabled(eid, asset);
    }

    function _validateCollateralConfig(CollateralConfig calldata cfg) internal pure {
        // ltv <= liqThreshold is typical (or equal). liqThreshold should not exceed 100%.
        if (cfg.ltvBps > 10_000 || cfg.liqThresholdBps > 10_000 || cfg.liqBonusBps > 10_000) revert InvalidBps();
        if (cfg.ltvBps > cfg.liqThresholdBps) revert InvalidBps();
        if (cfg.decimals > 36) revert InvalidDecimals(); // generous upper bound
        // supplyCap can be 0 (no cap)
    }

    // ---------------------------------------------------------------------
    // Admin: debt configs (global)
    // ---------------------------------------------------------------------

    function setDebtConfig(address asset, DebtConfig calldata cfg) external onlyOwner {
        if (asset == address(0)) revert InvalidAddress();
        _validateDebtConfig(cfg);

        _debtConfig[asset] = cfg;
        emit DebtConfigured(asset, cfg);
    }

    function disableDebt(address asset) external onlyOwner {
        if (asset == address(0)) revert InvalidAddress();
        DebtConfig storage d = _debtConfig[asset];
        d.isSupported = false;
        emit DebtDisabled(asset);
    }

    function _validateDebtConfig(DebtConfig calldata cfg) internal pure {
        if (cfg.decimals > 36) revert InvalidDecimals();
        // borrowCap can be 0 (no cap)
    }

    // ---------------------------------------------------------------------
    // Admin: cross-chain token mapping
    // ---------------------------------------------------------------------

    /**
     * @notice Set the spoke token address for a canonical asset on a given chain EID.
     * Example: eid=Arbitrum, canonicalAsset=USDC (Ethereum), spokeToken=USDC.e on Arbitrum.
     */
    function setSpokeTokenAddress(uint32 eid, address canonicalAsset, address spokeToken) external onlyOwner {
        if (eid == 0) revert InvalidEid();
        if (canonicalAsset == address(0) || spokeToken == address(0)) revert InvalidAddress();

        _spokeTokenAddress[eid][canonicalAsset] = spokeToken;
        emit SpokeTokenSet(eid, canonicalAsset, spokeToken);
    }

    // ---------------------------------------------------------------------
    // Admin: oracle staleness policy
    // ---------------------------------------------------------------------

    /**
     * @notice Set max price age for an asset in seconds. 0 disables staleness checks.
     */
    function setMaxPriceAgeSeconds(address asset, uint256 maxAgeSeconds_) external onlyOwner {
        if (asset == address(0)) revert InvalidAddress();
        // prevent silly max values (optional)
        if (maxAgeSeconds_ > 365 days) revert InvalidMaxAge();

        _maxPriceAgeSeconds[asset] = maxAgeSeconds_;
        emit MaxPriceAgeSet(asset, maxAgeSeconds_);
    }

    // ---------------------------------------------------------------------
    // Admin: interest-rate settings for DebtManager (fixed per-asset for MVP)
    // ---------------------------------------------------------------------

    /**
     * @notice Set per-second borrow rate in RAY (1e27).
     *
     * Example:
     *  - 5% APR ~= 0.05 / 31536000 = 1.585e-9 per second
     *  - In RAY: ratePerSecondRay ~= 1.585e-9 * 1e27 = 1.585e18
     *
     * We guard against absurd rates.
     */
    function setBorrowRatePerSecondRay(address asset, uint256 ratePerSecondRay_) external onlyOwner {
        if (asset == address(0)) revert InvalidAddress();

        // Arbitrary safety limit: <= 500% APR.
        // 500% APR = 5.0 per year
        // Per second: 5.0 / 31536000 ≈ 1.586e-7
        // In RAY: 1.586e-7 * 1e27 ≈ 1.586e20 = 1586e17
        if (ratePerSecondRay_ > 1586e17) revert RateTooHigh(ratePerSecondRay_); // ~500% APR

        _borrowRatePerSecondRay[asset] = ratePerSecondRay_;
        emit BorrowRateSet(asset, ratePerSecondRay_);
    }
    
    function isSupportedCollateral(uint32 eid, address asset) external view returns (bool) {
        return _collateralConfig[eid][asset].isSupported;
    }

    function isSupportedDebt(address asset) external view returns (bool) {
        return _debtConfig[asset].isSupported;
    }
}
