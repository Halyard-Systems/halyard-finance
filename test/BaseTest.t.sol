// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {HubAccessManager} from "../src/hub/HubAccessManager.sol";
import {HubController} from "../src/hub/HubController.sol";
import {HubRouter} from "../src/hub/HubRouter.sol";
import {AssetRegistry} from "../src/hub/AssetRegistry.sol";
import {PositionBook} from "../src/hub/PositionBook.sol";
import {RiskEngine} from "../src/hub/RiskEngine.sol";
import {LiquidationEngine} from "../src/hub/LiquidationEngine.sol";
import {DebtManager} from "../src/hub/DebtManager.sol";
import {CollateralVault} from "../src/spoke/CollateralVault.sol";
import {LiquidityVault} from "../src/spoke/LiquidityVault.sol";
import {SpokeController} from "../src/spoke/SpokeController.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockLZEndpoint} from "./mocks/MockLZEndpoint.sol";

contract BaseTest is Test {
    // Hub contracts
    HubAccessManager public hubAccessManager;
    HubController public hubController;
    HubRouter public hubRouter;
    AssetRegistry public assetRegistry;
    PositionBook public positionBook;
    RiskEngine public riskEngine;
    LiquidationEngine public liquidationEngine;
    DebtManager public debtManager;

    // Spoke contracts
    CollateralVault public collateralVault;
    LiquidityVault public liquidityVault;
    SpokeController public spokeController;
    MockERC20 public mockToken;

    // Test accounts
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public david = address(0x4);
    address public admin = address(0x5);

    MockLZEndpoint public mockLzEndpoint;
    address public mockOracle = makeAddr("oracle");

    // Token addresses
    address public canonicalToken = makeAddr("canonical_token");
    address public spokeToken = makeAddr("spoke_token");

    // LayerZero Infra
    uint32 public hubEid = 1;
    uint32 public spokeEid = 10;

    function setUp() public virtual {
        // Deploy mock LayerZero endpoint (must happen before other contracts)
        mockLzEndpoint = new MockLZEndpoint();

        // Mock the LayerZero endpoint setDelegate function (called in OAppCore constructor)
        vm.mockCall(address(mockLzEndpoint), abi.encodeWithSignature("setDelegate(address)"), abi.encode());

        // Deploy mock token (before prank so test contract is owner)
        mockToken = new MockERC20("Mock Token", "MTK", 18);

        vm.startPrank(admin);

        // Deploy Hub contracts
        hubAccessManager = new HubAccessManager(admin);
        hubController = new HubController(admin, address(mockLzEndpoint), address(hubAccessManager));
        hubRouter = new HubRouter(admin);

        assetRegistry = new AssetRegistry(address(hubAccessManager));
        _setupDefaultAssets(assetRegistry);

        positionBook = new PositionBook(address(hubAccessManager));
        hubController.setPositionBook(address(positionBook));
        hubRouter.setPositionBook(address(positionBook));
        hubRouter.setHubController(address(hubController));

        debtManager = new DebtManager(address(hubAccessManager), address(assetRegistry));
        debtManager.setAssetRegistry(address(assetRegistry));

        riskEngine = new RiskEngine(address(hubAccessManager));
        riskEngine.setDependencies(address(positionBook), address(debtManager), address(assetRegistry), mockOracle);
        hubRouter.setRiskEngine(address(riskEngine));

        liquidationEngine = new LiquidationEngine(address(hubAccessManager));
        _setupLiquidationEngine(liquidationEngine);

        _setupPermissions(hubAccessManager);

        // Deploy Spoke contracts
        spokeController = new SpokeController(admin, address(mockLzEndpoint));

        collateralVault = new CollateralVault(admin, address(spokeController));
        liquidityVault = new LiquidityVault(admin, address(spokeController));

        // Configure spokeController
        spokeController.setCollateralVault(address(collateralVault));
        spokeController.setLiquidityVault(address(liquidityVault));
        // forge-lint: disable-next-line(unsafe-typecast)
        spokeController.configureHub(hubEid, bytes32("test_hub"));
        spokeController.configureSpokeEid(spokeEid);
        // Map canonical token to actual mock token
        spokeController.setTokenMapping(canonicalToken, address(mockToken));
        spokeController.setPeer(hubEid, bytes32(uint256(uint160(address(hubController)))));

        hubController.setSpoke(spokeEid, bytes32(uint256(uint160(address(spokeController)))));
        hubController.setPeer(spokeEid, bytes32(uint256(uint160(address(spokeController)))));

        vm.stopPrank();

        // Give users ETH for gas/fees
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        // Setup test tokens for users
        mockToken.mint(alice, 1_000_000e18);
        mockToken.mint(bob, 1_000_000e18);

        // Mint tokens to spokeController and approve collateralVault
        // (depositAndNotify calls vault.deposit, where msg.sender is spokeController)
        mockToken.mint(address(spokeController), 1_000_000e18);
        vm.prank(address(spokeController));
        mockToken.approve(address(collateralVault), type(uint256).max);

        // Users approve the vaults for deposits
        vm.prank(alice);
        mockToken.approve(address(collateralVault), type(uint256).max);
        vm.prank(alice);
        mockToken.approve(address(liquidityVault), type(uint256).max);

        vm.prank(bob);
        mockToken.approve(address(collateralVault), type(uint256).max);
        vm.prank(bob);
        mockToken.approve(address(liquidityVault), type(uint256).max);

        // Mock LayerZero endpoint send for cross-chain messaging tests
        vm.mockCall(
            address(mockLzEndpoint),
            abi.encodeWithSelector(bytes4(keccak256("send((uint32,bytes32,bytes,bytes,bool),address)"))),
            abi.encode(bytes32(0), uint64(0), uint256(0), uint256(0))
        );
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

        // Register canonical token on spoke chain (used in integration tests)
        registry.setCollateralConfig(
            spokeEid,
            canonicalToken,
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
            address(hubController),
            buildFunctionSelector(hubController.processWithdraw.selector),
            accessManager.ROLE_ROUTER()
        );

        accessManager.setTargetFunctionRole(
            address(hubController),
            buildFunctionSelector(hubController.sendBorrowCommand.selector),
            accessManager.ROLE_ROUTER()
        );

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
            accessManager.ROLE_HUB_CONTROLLER()
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

        accessManager.grantRole(accessManager.ROLE_ROUTER(), address(hubRouter), 0);
        accessManager.grantRole(accessManager.ROLE_HUB_CONTROLLER(), address(hubController), 0);
        accessManager.grantRole(accessManager.ROLE_ASSET_REGISTRY(), address(assetRegistry), 0);
        accessManager.grantRole(accessManager.ROLE_RISK_ENGINE(), address(riskEngine), 0);
        accessManager.grantRole(accessManager.ROLE_POSITION_BOOK(), address(positionBook), 0);
    }
}
