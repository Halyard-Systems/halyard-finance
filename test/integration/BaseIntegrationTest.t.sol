// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "lib/forge-std/src/Test.sol";

import {HubAccessManager} from "../../src/hub/HubAccessManager.sol";
import {HubController} from "../../src/hub/HubController.sol";
import {AssetRegistry} from "../../src/hub/AssetRegistry.sol";
import {PositionBook} from "../../src/hub/PositionBook.sol";
import {RiskEngine} from "../../src/hub/RiskEngine.sol";
import {LiquidationEngine} from "../../src/hub/LiquidationEngine.sol";
import {DebtManager} from "../../src/hub/DebtManager.sol";

import {CollateralVault} from "../../src/spoke/CollateralVault.sol";
import {LiquidityVault} from "../../src/spoke/LiquidityVault.sol";
import {SpokeController} from "../../src/spoke/SpokeController.sol";

contract BaseIntegrationTest is Test {
    // Hub contracts
    HubAccessManager public hubAccessManager;
    HubController public hubController;
    AssetRegistry public assetRegistry;
    PositionBook public positionBook;
    RiskEngine public riskEngine;
    LiquidationEngine public liquidationEngine;
    DebtManager public debtManager;

    // Spoke contracts
    CollateralVault public collateralVault;
    LiquidityVault public liquidityVault;
    SpokeController public spokeController;

    // Test accounts
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public david = address(0x4);
    address public admin = address(0x5);

    address public mockLzEndpoint = makeAddr("lzEndpoint");
    address public mockOracle = makeAddr("oracle");
    // TODO: replace with a router implementation
    address public router = address(this);

    function setUp() public virtual {
        // Put bytecode at mock addresses so calls don't fail with "non-contract address"
        vm.etch(mockLzEndpoint, hex"00");

        // Mock LZ endpoint setDelegate (called in OAppCore constructor)
        vm.mockCall(mockLzEndpoint, abi.encodeWithSignature("setDelegate(address)"), abi.encode());

        vm.startPrank(admin);

        // Deploy Hub contracts
        hubAccessManager = new HubAccessManager(admin);
        hubController = new HubController(admin, mockLzEndpoint);
        assetRegistry = new AssetRegistry(address(hubAccessManager));
        _setupDefaultAssets(assetRegistry);

        positionBook = new PositionBook(address(hubAccessManager));

        debtManager = new DebtManager(address(hubAccessManager), address(assetRegistry));
        debtManager.setAssetRegistry(address(assetRegistry));

        riskEngine = new RiskEngine(address(hubAccessManager));
        riskEngine.setDependencies(address(positionBook), address(debtManager), address(assetRegistry), mockOracle);

        liquidationEngine = new LiquidationEngine(address(hubAccessManager));
        _setupLiquidationEngine(liquidationEngine);

        _setupPermissions(hubAccessManager);

        // Deploy Spoke contracts
        spokeController = new SpokeController(admin, mockLzEndpoint);
        collateralVault = new CollateralVault(admin, address(spokeController));
        liquidityVault = new LiquidityVault(admin, address(spokeController));

        // Configure spokeController
        spokeController.setCollateralVault(address(collateralVault));
        spokeController.setLiquidityVault(address(liquidityVault));

        address canonicalToken = makeAddr("canonical_token");
        address spokeToken = makeAddr("spoke_token");
        uint32 hubEid = 1;
        uint32 spokeEid = 10;

        spokeController.setCollateralVault(address(collateralVault));
        spokeController.setLiquidityVault(address(liquidityVault));
        spokeController.configureHub(hubEid, bytes32("test_hub"));
        spokeController.configureSpokeEid(spokeEid);
        spokeController.setTokenMapping(canonicalToken, spokeToken);
        spokeController.setPeer(hubEid, bytes32("test_hub"));

        vm.stopPrank();
    }

    function buildFunctionSelector(bytes4 selector) internal pure returns (bytes4[] memory) {
        bytes4[] memory addfuncs = new bytes4[](1);
        addfuncs[0] = selector;
        return addfuncs;
    }

    function _setupLiquidationEngine(LiquidationEngine engine) internal {
        engine.setCollateralConfig(
            1,
            address(0x123),
            LiquidationEngine.CollateralConfig({
                isSupported: true, ltvBps: 8000, liqThresholdBps: 8500, liqBonusBps: 500, decimals: 18, supplyCap: 0
            })
        );
        engine.setCollateralConfig(
            2,
            address(0x124),
            LiquidationEngine.CollateralConfig({
                isSupported: true, ltvBps: 8000, liqThresholdBps: 8500, liqBonusBps: 500, decimals: 18, supplyCap: 0
            })
        );
        engine.setDebtConfig(
            address(0x123), LiquidationEngine.DebtConfig({isSupported: true, decimals: 18, borrowCap: 0})
        );
        engine.setDebtConfig(
            address(0x124), LiquidationEngine.DebtConfig({isSupported: true, decimals: 18, borrowCap: 0})
        );
    }

    function _setupDefaultAssets(AssetRegistry registry) internal {
        registry.setCollateralConfig(
            1,
            address(0x123),
            AssetRegistry.CollateralConfig({
                isSupported: true, ltvBps: 8000, liqThresholdBps: 8500, liqBonusBps: 500, decimals: 18, supplyCap: 0
            })
        );

        registry.setCollateralConfig(
            2,
            address(0x124),
            AssetRegistry.CollateralConfig({
                isSupported: true, ltvBps: 8000, liqThresholdBps: 8500, liqBonusBps: 500, decimals: 18, supplyCap: 0
            })
        );

        registry.setDebtConfig(
            1, address(0x123), AssetRegistry.DebtConfig({isSupported: true, decimals: 18, borrowCap: 0})
        );

        registry.setDebtConfig(
            2, address(0x124), AssetRegistry.DebtConfig({isSupported: true, decimals: 18, borrowCap: 0})
        );

        registry.setBorrowRateApr(1, address(0x123), 1000);
        registry.setBorrowRateApr(2, address(0x124), 500);
    }

    function _setupPermissions(HubAccessManager accessManager) internal {
        accessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.creditCollateral.selector),
            accessManager.ROLE_HUB_CONTROLLER()
        );
        accessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.reserveCollateral.selector),
            accessManager.ROLE_RISK_ENGINE()
        );
        accessManager.setTargetFunctionRole(
            address(assetRegistry),
            buildFunctionSelector(positionBook.unreserveCollateral.selector),
            accessManager.ROLE_HUB_CONTROLLER()
        );
        accessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.clearBorrowReservation.selector),
            accessManager.ROLE_HUB_CONTROLLER()
        );
        accessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.createPendingWithdraw.selector),
            accessManager.ROLE_RISK_ENGINE()
        );
        accessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.finalizePendingWithdraw.selector),
            accessManager.ROLE_HUB_CONTROLLER()
        );
        // TODO: should be router? verify that router calls validateAndCreateBorrow and createPendingBorrow
        accessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.createPendingBorrow.selector),
            accessManager.ROLE_RISK_ENGINE()
        );
        accessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.createPendingLiquidation.selector),
            accessManager.ROLE_LIQUIDATION_ENGINE()
        );

        accessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.finalizePendingLiquidation.selector),
            accessManager.ROLE_HUB_CONTROLLER()
        );

        accessManager.setTargetFunctionRole(
            address(riskEngine),
            buildFunctionSelector(riskEngine.validateAndCreateBorrow.selector),
            accessManager.ROLE_ROUTER()
        );

        accessManager.setTargetFunctionRole(
            address(riskEngine),
            buildFunctionSelector(riskEngine.validateAndCreateWithdraw.selector),
            accessManager.ROLE_ROUTER()
        );

        accessManager.grantRole(accessManager.ROLE_HUB_CONTROLLER(), address(hubController), 0);
        accessManager.grantRole(accessManager.ROLE_ASSET_REGISTRY(), address(assetRegistry), 0);
        accessManager.grantRole(accessManager.ROLE_RISK_ENGINE(), address(riskEngine), 0);
        accessManager.grantRole(accessManager.ROLE_ROUTER(), router, 0);
    }
}
