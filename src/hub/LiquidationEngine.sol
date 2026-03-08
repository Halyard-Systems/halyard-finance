// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {IOracle} from "../interfaces/IOracle.sol";

/**
 * LiquidationEngine (Hub-side)
 *
 * Purpose:
 * - Allow anyone to liquidate undercollateralized positions
 * - Validate liquidation eligibility using oracle prices + risk params from AssetRegistry
 * - Burn borrower's debt via DebtManager
 * - Create pending liquidation in PositionBook and send CMD_SEIZE_COLLATERAL to spoke
 *
 * Flow:
 *   Liquidator → LiquidationEngine.liquidate() (validate + burn debt + reserve collateral)
 *     → HubController.sendSeizeCommand() → Spoke (seize collateral → liquidator)
 *     → COLLATERAL_SEIZED receipt → HubController → HubRouter.finalizeLiquidation()
 *     → PositionBook.finalizePendingLiquidation() (debit collateral on success)
 */

/// @dev Minimal interface for PositionBook functions needed by LiquidationEngine
interface IPositionBookLiq {
    function availableCollateralOf(address user, uint32 eid, address asset) external view returns (uint256);
    function reservedDebtOf(address user, uint32 eid, address asset) external view returns (uint256);
    function createPendingLiquidation(
        bytes32 liqId,
        address user,
        uint32 seizeEid,
        address seizeAsset,
        uint256 seizeAmount,
        address liquidator
    ) external;
}

/// @dev Minimal interface for DebtManager functions needed by LiquidationEngine
interface IDebtManagerLiq {
    function debtOf(address user, uint32 eid, address asset) external view returns (uint256);
    function burnDebt(address user, uint32 eid, address asset, uint256 amount)
        external
        returns (uint256 scaledRemoved, uint256 nominalBurned);
}

/// @dev Minimal interface for AssetRegistry
interface IAssetRegistryLiq {
    struct CollateralConfig {
        bool isSupported;
        uint16 ltvBps;
        uint16 liqThresholdBps;
        uint16 liqBonusBps;
        uint8 decimals;
        uint256 supplyCap;
    }

    struct DebtConfig {
        bool isSupported;
        uint8 decimals;
        uint256 borrowCap;
    }

    function collateralConfig(uint32 eid, address asset) external view returns (CollateralConfig memory);
    function debtConfig(uint32 eid, address asset) external view returns (DebtConfig memory);
}

/// @dev Minimal interface for HubController seize command
interface IHubControllerLiq {
    function sendSeizeCommand(
        uint32 dstEid,
        bytes32 liqId,
        address user,
        address liquidator,
        address asset,
        uint256 amount,
        bytes calldata options,
        MessagingFee calldata fee,
        address refundAddress
    ) external payable;
}

contract LiquidationEngine is AccessManaged, ReentrancyGuard {
    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------
    uint256 internal constant BPS = 10_000;

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------
    error InvalidAddress();
    error InvalidEid();
    error InvalidBps();
    error InvalidDecimals();
    error InvalidAmount();
    error UnsupportedAsset();
    error NotLiquidatable(uint256 healthFactorE18);
    error InsufficientSeizableCollateral(uint256 available, uint256 required);
    error PriceUnavailable(address asset);
    error UnsupportedCollateral(uint32 eid, address asset);
    error UnsupportedDebtAsset(uint32 eid, address asset);

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------
    event DependenciesSet(
        address indexed positionBook,
        address indexed debtManager,
        address indexed assetRegistry,
        address oracle,
        address hubController
    );

    event LiquidationInitiated(
        bytes32 indexed liqId,
        address indexed liquidator,
        address indexed user,
        uint32 debtEid,
        address debtAsset,
        uint256 debtRepaid,
        uint32 seizeEid,
        address seizeAsset,
        uint256 seizeAmount
    );

    // ---------------------------------------------------------------------
    // Liquidation types (matching RiskEngine pattern)
    // ---------------------------------------------------------------------
    struct CollateralSlot {
        uint32 eid;
        address asset;
    }

    struct DebtSlot {
        uint32 eid;
        address asset;
    }

    // ---------------------------------------------------------------------
    // Dependencies
    // ---------------------------------------------------------------------
    IPositionBookLiq public positionBook;
    IDebtManagerLiq public debtManager;
    IAssetRegistryLiq public assetRegistry;
    IOracle public oracle;
    IHubControllerLiq public hubController;

    constructor(address _authority) AccessManaged(_authority) {}

    function setDependencies(
        address _positionBook,
        address _debtManager,
        address _assetRegistry,
        address _oracle,
        address _hubController
    ) external restricted {
        if (
            _positionBook == address(0) || _debtManager == address(0) || _assetRegistry == address(0)
                || _oracle == address(0) || _hubController == address(0)
        ) {
            revert InvalidAddress();
        }
        positionBook = IPositionBookLiq(_positionBook);
        debtManager = IDebtManagerLiq(_debtManager);
        assetRegistry = IAssetRegistryLiq(_assetRegistry);
        oracle = IOracle(_oracle);
        hubController = IHubControllerLiq(_hubController);
        emit DependenciesSet(_positionBook, _debtManager, _assetRegistry, _oracle, _hubController);
    }

    // ---------------------------------------------------------------------
    // Liquidation
    // ---------------------------------------------------------------------

    /**
     * @notice Liquidate an undercollateralized position.
     * @dev Anyone can call this. The caller (liquidator) receives seized collateral
     *   on the spoke chain with a configurable liquidation bonus from AssetRegistry.
     *
     * Flow:
     *   1. Compute health factor using oracle prices — must be < 1.0
     *   2. Compute seize amount: debtRepayValue * (1 + liqBonusBps/10000) in collateral terms
     *   3. Burn borrower's debt via DebtManager
     *   4. Reserve collateral and create pending liquidation in PositionBook
     *   5. Send CMD_SEIZE_COLLATERAL to spoke via HubController
     *
     * @param user Account to liquidate
     * @param debtEid Chain where the debt was borrowed
     * @param debtAsset Canonical debt asset to repay
     * @param debtRepayAmount Amount of debt to repay (in debt asset units)
     * @param seizeEid Chain where collateral will be seized
     * @param seizeAsset Canonical collateral asset to seize
     * @param collateralSlots All collateral positions for health factor computation
     * @param debtSlots All debt positions for health factor computation
     * @param options LayerZero options for the seize command
     * @param fee LayerZero messaging fee
     */
    function liquidate(
        address user,
        uint32 debtEid,
        address debtAsset,
        uint256 debtRepayAmount,
        uint32 seizeEid,
        address seizeAsset,
        CollateralSlot[] calldata collateralSlots,
        DebtSlot[] calldata debtSlots,
        bytes calldata options,
        MessagingFee calldata fee
    ) external payable nonReentrant {
        if (user == address(0) || debtAsset == address(0) || seizeAsset == address(0)) {
            revert InvalidAddress();
        }
        if (debtRepayAmount == 0) revert InvalidAmount();

        // 1. Validate account is undercollateralized (health factor < 1.0)
        uint256 healthFactorE18 = _computeHealthFactor(user, collateralSlots, debtSlots);
        if (healthFactorE18 >= 1e18) revert NotLiquidatable(healthFactorE18);

        // 2. Get configs and compute seize amount with bonus
        IAssetRegistryLiq.CollateralConfig memory cc = assetRegistry.collateralConfig(seizeEid, seizeAsset);
        if (!cc.isSupported) revert UnsupportedCollateral(seizeEid, seizeAsset);

        IAssetRegistryLiq.DebtConfig memory dc = assetRegistry.debtConfig(debtEid, debtAsset);
        if (!dc.isSupported) revert UnsupportedDebtAsset(debtEid, debtAsset);

        uint256 seizeAmount = _computeSeizeAmount(debtAsset, debtRepayAmount, dc.decimals, seizeAsset, cc);

        // 3. Verify enough collateral is available
        uint256 available = positionBook.availableCollateralOf(user, seizeEid, seizeAsset);
        if (available < seizeAmount) revert InsufficientSeizableCollateral(available, seizeAmount);

        // 4. Burn borrower's debt
        debtManager.burnDebt(user, debtEid, debtAsset, debtRepayAmount);

        // 5. Create pending liquidation (reserves collateral)
        address liquidator = msg.sender;
        bytes32 liqId = keccak256(
            abi.encodePacked(liquidator, user, debtEid, debtAsset, debtRepayAmount, seizeEid, seizeAsset, block.number)
        );

        positionBook.createPendingLiquidation(liqId, user, seizeEid, seizeAsset, seizeAmount, liquidator);

        // 6. Send CMD_SEIZE_COLLATERAL to spoke
        hubController.sendSeizeCommand{value: msg.value}(
            seizeEid, liqId, user, liquidator, seizeAsset, seizeAmount, options, fee, liquidator
        );

        emit LiquidationInitiated(
            liqId, liquidator, user, debtEid, debtAsset, debtRepayAmount, seizeEid, seizeAsset, seizeAmount
        );
    }

    // ---------------------------------------------------------------------
    // Internal: health factor computation
    // ---------------------------------------------------------------------

    /**
     * @notice Compute health factor = liquidationValue / debtValue.
     * @dev Returns type(uint256).max if no debt.
     */
    function _computeHealthFactor(
        address user,
        CollateralSlot[] calldata collateralSlots,
        DebtSlot[] calldata debtSlots
    ) internal view returns (uint256) {
        uint256 liquidationValueE18 = _liquidationValue(user, collateralSlots);
        uint256 debtValueE18 = _debtValue(user, debtSlots);

        if (debtValueE18 == 0) return type(uint256).max;
        return (liquidationValueE18 * 1e18) / debtValueE18;
    }

    function _liquidationValue(address user, CollateralSlot[] calldata collateralSlots)
        internal
        view
        returns (uint256 liquidationValueE18)
    {
        for (uint256 i = 0; i < collateralSlots.length; i++) {
            CollateralSlot calldata slot = collateralSlots[i];
            IAssetRegistryLiq.CollateralConfig memory cc = assetRegistry.collateralConfig(slot.eid, slot.asset);
            if (!cc.isSupported) revert UnsupportedCollateral(slot.eid, slot.asset);

            uint256 amount = positionBook.availableCollateralOf(user, slot.eid, slot.asset);
            if (amount == 0) continue;

            uint256 valueE18 = _valueE18(slot.asset, amount, cc.decimals);
            liquidationValueE18 += (valueE18 * cc.liqThresholdBps) / BPS;
        }
    }

    function _debtValue(address user, DebtSlot[] calldata debtSlots) internal view returns (uint256 debtValueE18) {
        for (uint256 i = 0; i < debtSlots.length; i++) {
            DebtSlot calldata slot = debtSlots[i];
            IAssetRegistryLiq.DebtConfig memory dc = assetRegistry.debtConfig(slot.eid, slot.asset);
            if (!dc.isSupported) revert UnsupportedDebtAsset(slot.eid, slot.asset);

            uint256 nominalDebt = debtManager.debtOf(user, slot.eid, slot.asset);
            uint256 reservedNominal = positionBook.reservedDebtOf(user, slot.eid, slot.asset);
            uint256 totalNominal = nominalDebt + reservedNominal;
            if (totalNominal == 0) continue;

            debtValueE18 += _valueE18(slot.asset, totalNominal, dc.decimals);
        }
    }

    // ---------------------------------------------------------------------
    // Internal: seize amount computation
    // ---------------------------------------------------------------------

    /**
     * @notice Compute how much collateral to seize for a given debt repayment.
     * @dev seizeAmount = debtRepayValue * (1 + liqBonusBps/10000) / collateralPrice
     *   The liqBonusBps comes from AssetRegistry's collateral config, making it configurable per asset.
     */
    function _computeSeizeAmount(
        address debtAsset,
        uint256 debtRepayAmount,
        uint8 debtDecimals,
        address seizeAsset,
        IAssetRegistryLiq.CollateralConfig memory cc
    ) internal view returns (uint256) {
        // Value of debt being repaid (in E18 units)
        uint256 debtValueE18 = _valueE18(debtAsset, debtRepayAmount, debtDecimals);

        // Apply liquidation bonus: seizeValue = debtValue * (10000 + bonusBps) / 10000
        uint256 seizeValueE18 = (debtValueE18 * (BPS + cc.liqBonusBps)) / BPS;

        // Convert value back to collateral token units
        (uint256 collateralPriceE18,) = oracle.getPriceE18(seizeAsset);
        if (collateralPriceE18 == 0) revert PriceUnavailable(seizeAsset);

        return (seizeValueE18 * (10 ** uint256(cc.decimals))) / collateralPriceE18;
    }

    function _valueE18(address asset, uint256 amount, uint8 decimals) internal view returns (uint256) {
        (uint256 priceE18,) = oracle.getPriceE18(asset);
        if (priceE18 == 0) revert PriceUnavailable(asset);
        return (amount * priceE18) / (10 ** uint256(decimals));
    }
}
