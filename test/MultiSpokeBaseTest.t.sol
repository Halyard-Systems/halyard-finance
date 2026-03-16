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

import {MessagingFee, Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {MessagingFee} from "lib/devtools/packages/oapp-evm/contracts/oapp/OApp.sol";

/// @title MultiSpokeBaseTest
/// @notice Extends the single-spoke BaseTest pattern to deploy hub + 3 spokes (ETH, ARB, BASE).
///         Each spoke has its own SpokeController, CollateralVault, LiquidityVault, and MockERC20 token.
contract MultiSpokeBaseTest is Test {
    // Hub contracts
    HubAccessManager public hubAccessManager;
    HubController public hubController;
    HubRouter public hubRouter;
    AssetRegistry public assetRegistry;
    PositionBook public positionBook;
    RiskEngine public riskEngine;
    LiquidationEngine public liquidationEngine;
    DebtManager public debtManager;

    // ETH spoke contracts
    CollateralVault public collateralVaultEth;
    LiquidityVault public liquidityVaultEth;
    SpokeController public spokeControllerEth;
    MockERC20 public mockTokenEth;

    // ARB spoke contracts
    CollateralVault public collateralVaultArb;
    LiquidityVault public liquidityVaultArb;
    SpokeController public spokeControllerArb;
    MockERC20 public mockTokenArb;

    // BASE spoke contracts
    CollateralVault public collateralVaultBase;
    LiquidityVault public liquidityVaultBase;
    SpokeController public spokeControllerBase;
    MockERC20 public mockTokenBase;

    // Test accounts
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public david = address(0x4);
    address public admin = address(0x5);

    MockLZEndpoint public mockLzEndpoint;
    address public mockOracle = makeAddr("oracle");

    // Canonical token addresses (used on hub for position tracking)
    address public canonicalTokenEth = makeAddr("canonical_token_eth");
    address public canonicalTokenArb = makeAddr("canonical_token_arb");
    address public canonicalTokenBase = makeAddr("canonical_token_base");

    // LayerZero EIDs
    uint32 public hubEid = 1;
    uint32 public ethEid = 10;
    uint32 public arbEid = 20;
    uint32 public baseEid = 30;

    function setUp() public virtual {
        // Deploy mock LayerZero endpoint
        mockLzEndpoint = new MockLZEndpoint();
        vm.mockCall(address(mockLzEndpoint), abi.encodeWithSignature("setDelegate(address)"), abi.encode());

        // Deploy mock tokens (one per spoke)
        mockTokenEth = new MockERC20("Mock Token ETH", "MTK_ETH", 18);
        mockTokenArb = new MockERC20("Mock Token ARB", "MTK_ARB", 18);
        mockTokenBase = new MockERC20("Mock Token BASE", "MTK_BASE", 18);

        vm.startPrank(admin);

        // ============================================================
        // Deploy Hub contracts
        // ============================================================
        hubAccessManager = new HubAccessManager(admin);
        hubController = new HubController(admin, address(mockLzEndpoint), address(hubAccessManager));
        hubRouter = new HubRouter(admin, address(hubAccessManager));

        assetRegistry = new AssetRegistry(address(hubAccessManager));
        _setupDefaultAssets(assetRegistry);

        positionBook = new PositionBook(address(hubAccessManager));
        positionBook.setAssetRegistry(address(assetRegistry));
        hubController.setPositionBook(address(positionBook));
        hubRouter.setPositionBook(address(positionBook));
        hubRouter.setHubController(address(hubController));

        debtManager = new DebtManager(address(hubAccessManager), address(assetRegistry));
        debtManager.setAssetRegistry(address(assetRegistry));

        riskEngine = new RiskEngine(address(hubAccessManager));
        riskEngine.setDependencies(address(positionBook), address(debtManager), address(assetRegistry), mockOracle);
        hubRouter.setRiskEngine(address(riskEngine));
        hubRouter.setDebtManager(address(debtManager));

        liquidationEngine = new LiquidationEngine(address(hubAccessManager));

        _setupPermissions(hubAccessManager);

        liquidationEngine.setDependencies(
            address(positionBook), address(debtManager), address(assetRegistry), mockOracle, address(hubController)
        );

        // ============================================================
        // Deploy ETH spoke
        // ============================================================
        spokeControllerEth = new SpokeController(admin, address(mockLzEndpoint));
        collateralVaultEth = new CollateralVault(admin, address(spokeControllerEth));
        liquidityVaultEth = new LiquidityVault(admin, address(spokeControllerEth));

        spokeControllerEth.setCollateralVault(address(collateralVaultEth));
        spokeControllerEth.setLiquidityVault(address(liquidityVaultEth));
        spokeControllerEth.configureHub(hubEid, bytes32(uint256(uint160(address(hubController)))));
        spokeControllerEth.configureSpokeEid(ethEid);
        spokeControllerEth.setTokenMapping(canonicalTokenEth, address(mockTokenEth));
        spokeControllerEth.setPeer(hubEid, bytes32(uint256(uint160(address(hubController)))));

        hubController.setSpoke(ethEid, bytes32(uint256(uint160(address(spokeControllerEth)))));
        hubController.setPeer(ethEid, bytes32(uint256(uint160(address(spokeControllerEth)))));

        // ============================================================
        // Deploy ARB spoke
        // ============================================================
        spokeControllerArb = new SpokeController(admin, address(mockLzEndpoint));
        collateralVaultArb = new CollateralVault(admin, address(spokeControllerArb));
        liquidityVaultArb = new LiquidityVault(admin, address(spokeControllerArb));

        spokeControllerArb.setCollateralVault(address(collateralVaultArb));
        spokeControllerArb.setLiquidityVault(address(liquidityVaultArb));
        spokeControllerArb.configureHub(hubEid, bytes32(uint256(uint160(address(hubController)))));
        spokeControllerArb.configureSpokeEid(arbEid);
        spokeControllerArb.setTokenMapping(canonicalTokenArb, address(mockTokenArb));
        spokeControllerArb.setPeer(hubEid, bytes32(uint256(uint160(address(hubController)))));

        hubController.setSpoke(arbEid, bytes32(uint256(uint160(address(spokeControllerArb)))));
        hubController.setPeer(arbEid, bytes32(uint256(uint160(address(spokeControllerArb)))));

        // ============================================================
        // Deploy BASE spoke
        // ============================================================
        spokeControllerBase = new SpokeController(admin, address(mockLzEndpoint));
        collateralVaultBase = new CollateralVault(admin, address(spokeControllerBase));
        liquidityVaultBase = new LiquidityVault(admin, address(spokeControllerBase));

        spokeControllerBase.setCollateralVault(address(collateralVaultBase));
        spokeControllerBase.setLiquidityVault(address(liquidityVaultBase));
        spokeControllerBase.configureHub(hubEid, bytes32(uint256(uint160(address(hubController)))));
        spokeControllerBase.configureSpokeEid(baseEid);
        spokeControllerBase.setTokenMapping(canonicalTokenBase, address(mockTokenBase));
        spokeControllerBase.setPeer(hubEid, bytes32(uint256(uint160(address(hubController)))));

        hubController.setSpoke(baseEid, bytes32(uint256(uint160(address(spokeControllerBase)))));
        hubController.setPeer(baseEid, bytes32(uint256(uint160(address(spokeControllerBase)))));

        hubController.setHubRouter(address(hubRouter));

        vm.stopPrank();

        // ============================================================
        // Fund test accounts
        // ============================================================
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        // Mint tokens to users for all 3 spokes
        mockTokenEth.mint(alice, 1_000_000e18);
        mockTokenEth.mint(bob, 1_000_000e18);
        mockTokenArb.mint(alice, 1_000_000e18);
        mockTokenArb.mint(bob, 1_000_000e18);
        mockTokenBase.mint(alice, 1_000_000e18);
        mockTokenBase.mint(bob, 1_000_000e18);

        // Mint tokens to spokeControllers and approve vaults
        _setupSpokeTokenApprovals(spokeControllerEth, mockTokenEth, collateralVaultEth);
        _setupSpokeTokenApprovals(spokeControllerArb, mockTokenArb, collateralVaultArb);
        _setupSpokeTokenApprovals(spokeControllerBase, mockTokenBase, collateralVaultBase);

        // User approvals for all vaults
        _setupUserApprovals(alice, mockTokenEth, collateralVaultEth, liquidityVaultEth);
        _setupUserApprovals(alice, mockTokenArb, collateralVaultArb, liquidityVaultArb);
        _setupUserApprovals(alice, mockTokenBase, collateralVaultBase, liquidityVaultBase);
        _setupUserApprovals(bob, mockTokenEth, collateralVaultEth, liquidityVaultEth);
        _setupUserApprovals(bob, mockTokenArb, collateralVaultArb, liquidityVaultArb);
        _setupUserApprovals(bob, mockTokenBase, collateralVaultBase, liquidityVaultBase);

        // Mock LZ send for cross-chain messaging
        vm.mockCall(
            address(mockLzEndpoint),
            abi.encodeWithSelector(bytes4(keccak256("send((uint32,bytes32,bytes,bytes,bool),address)"))),
            abi.encode(bytes32(0), uint64(0), uint256(0), uint256(0))
        );
    }

    // ================================================================
    // Internal helpers
    // ================================================================

    function _setupSpokeTokenApprovals(SpokeController sc, MockERC20 token, CollateralVault cv) internal {
        token.mint(address(sc), 1_000_000e18);
        vm.prank(address(sc));
        token.approve(address(cv), type(uint256).max);
    }

    function _setupUserApprovals(address user, MockERC20 token, CollateralVault cv, LiquidityVault lv) internal {
        vm.prank(user);
        token.approve(address(cv), type(uint256).max);
        vm.prank(user);
        token.approve(address(lv), type(uint256).max);
    }

    function buildFunctionSelector(bytes4 selector) internal pure returns (bytes4[] memory) {
        bytes4[] memory addfuncs = new bytes4[](1);
        addfuncs[0] = selector;
        return addfuncs;
    }

    function _setupDefaultAssets(AssetRegistry registry) internal {
        // ETH spoke assets
        registry.setCollateralConfig(
            ethEid,
            canonicalTokenEth,
            AssetRegistry.CollateralConfig({
                isSupported: true, ltvBps: 8000, liqThresholdBps: 8500, liqBonusBps: 500, decimals: 18, supplyCap: 0
            })
        );
        registry.setDebtConfig(
            ethEid, canonicalTokenEth, AssetRegistry.DebtConfig({isSupported: true, decimals: 18, borrowCap: 0})
        );
        registry.setBorrowRateApr(ethEid, canonicalTokenEth, 500);

        // ARB spoke assets
        registry.setCollateralConfig(
            arbEid,
            canonicalTokenArb,
            AssetRegistry.CollateralConfig({
                isSupported: true, ltvBps: 8000, liqThresholdBps: 8500, liqBonusBps: 500, decimals: 18, supplyCap: 0
            })
        );
        registry.setDebtConfig(
            arbEid, canonicalTokenArb, AssetRegistry.DebtConfig({isSupported: true, decimals: 18, borrowCap: 0})
        );
        registry.setBorrowRateApr(arbEid, canonicalTokenArb, 500);

        // BASE spoke assets
        registry.setCollateralConfig(
            baseEid,
            canonicalTokenBase,
            AssetRegistry.CollateralConfig({
                isSupported: true, ltvBps: 8000, liqThresholdBps: 8500, liqBonusBps: 500, decimals: 18, supplyCap: 0
            })
        );
        registry.setDebtConfig(
            baseEid, canonicalTokenBase, AssetRegistry.DebtConfig({isSupported: true, decimals: 18, borrowCap: 0})
        );
        registry.setBorrowRateApr(baseEid, canonicalTokenBase, 500);
    }

    function _setupPermissions(HubAccessManager accessManager) internal {
        accessManager.setTargetFunctionRole(
            address(hubController),
            buildFunctionSelector(hubController.sendWithdrawCommand.selector),
            accessManager.ROLE_ROUTER()
        );

        accessManager.setTargetFunctionRole(
            address(hubController),
            buildFunctionSelector(hubController.sendBorrowCommand.selector),
            accessManager.ROLE_ROUTER()
        );

        accessManager.setTargetFunctionRole(
            address(hubRouter),
            buildFunctionSelector(hubRouter.finalizeWithdraw.selector),
            accessManager.ROLE_HUB_CONTROLLER()
        );
        accessManager.setTargetFunctionRole(
            address(hubRouter),
            buildFunctionSelector(hubRouter.finalizeBorrow.selector),
            accessManager.ROLE_HUB_CONTROLLER()
        );
        accessManager.setTargetFunctionRole(
            address(hubRouter),
            buildFunctionSelector(hubRouter.finalizeRepay.selector),
            accessManager.ROLE_HUB_CONTROLLER()
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
            address(positionBook),
            buildFunctionSelector(positionBook.unreserveCollateral.selector),
            accessManager.ROLE_HUB_CONTROLLER()
        );
        accessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.clearBorrowReservation.selector),
            accessManager.ROLE_ROUTER()
        );
        accessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.createPendingWithdraw.selector),
            accessManager.ROLE_RISK_ENGINE()
        );
        accessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.finalizePendingWithdraw.selector),
            accessManager.ROLE_ROUTER()
        );
        accessManager.setTargetFunctionRole(
            address(positionBook),
            buildFunctionSelector(positionBook.finalizePendingBorrow.selector),
            accessManager.ROLE_ROUTER()
        );
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
            accessManager.ROLE_ROUTER()
        );

        accessManager.setTargetFunctionRole(
            address(hubRouter),
            buildFunctionSelector(hubRouter.finalizeLiquidation.selector),
            accessManager.ROLE_HUB_CONTROLLER()
        );

        accessManager.setTargetFunctionRole(
            address(hubController),
            buildFunctionSelector(hubController.sendSeizeCommand.selector),
            accessManager.ROLE_LIQUIDATION_ENGINE()
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

        accessManager.setTargetFunctionRole(
            address(debtManager), buildFunctionSelector(debtManager.mintDebt.selector), accessManager.ROLE_ROUTER()
        );
        accessManager.setTargetFunctionRole(
            address(debtManager), buildFunctionSelector(debtManager.burnDebt.selector), accessManager.ROLE_ROUTER()
        );

        accessManager.grantRole(accessManager.ROLE_ROUTER(), address(hubRouter), 0);
        accessManager.grantRole(accessManager.ROLE_HUB_CONTROLLER(), address(hubController), 0);
        accessManager.grantRole(accessManager.ROLE_ASSET_REGISTRY(), address(assetRegistry), 0);
        accessManager.grantRole(accessManager.ROLE_RISK_ENGINE(), address(riskEngine), 0);
        accessManager.grantRole(accessManager.ROLE_POSITION_BOOK(), address(positionBook), 0);
        accessManager.grantRole(accessManager.ROLE_LIQUIDATION_ENGINE(), address(liquidationEngine), 0);
        accessManager.grantRole(accessManager.ROLE_ROUTER(), address(liquidationEngine), 0);
    }

    // ================================================================
    // Cross-chain simulation helpers
    // ================================================================

    function _mockLzSend() internal {
        vm.mockCall(
            address(mockLzEndpoint),
            abi.encodeWithSignature("send((uint32,bytes32,bytes,bytes,bool),address)"),
            abi.encode(bytes32(uint256(1)), uint64(1), MessagingFee({nativeFee: 0, lzTokenFee: 0}))
        );
    }

    function _mockOraclePrice(address asset, uint256 priceE18) internal {
        vm.mockCall(
            mockOracle, abi.encodeWithSignature("getPriceE18(address)", asset), abi.encode(priceE18, block.timestamp)
        );
    }

    /// @notice Simulate deposit receipt on a specific spoke
    function _simulateDepositReceipt(SpokeController sc, bytes32 depositId, address user, address asset, uint256 amount)
        internal
    {
        uint32 srcEid = sc.spokeEid();
        bytes32 spokeSender = bytes32(uint256(uint160(address(sc))));

        bytes memory payload = abi.encode(depositId, user, srcEid, asset, amount);
        bytes memory message = abi.encode(uint8(0), payload);

        vm.prank(address(mockLzEndpoint));
        hubController.lzReceive(
            Origin({srcEid: srcEid, sender: spokeSender, nonce: 1}), bytes32(uint256(1)), message, address(0), bytes("")
        );
    }

    /// @notice Simulate borrow receipt from a specific spoke
    function _simulateBorrowReceipt(
        SpokeController sc,
        bytes32 borrowId,
        address user,
        address asset,
        uint256 amount,
        bool success
    ) internal {
        uint32 srcEid = sc.spokeEid();
        bytes32 spokeSender = bytes32(uint256(uint160(address(sc))));

        bytes memory payload = abi.encode(borrowId, success, user, srcEid, asset, amount);
        bytes memory message = abi.encode(uint8(1), payload);

        vm.prank(address(mockLzEndpoint));
        hubController.lzReceive(
            Origin({srcEid: srcEid, sender: spokeSender, nonce: 3}), bytes32(uint256(3)), message, address(0), bytes("")
        );
    }

    /// @notice Simulate withdraw receipt from a specific spoke
    function _simulateWithdrawReceipt(
        SpokeController sc,
        address user,
        address asset,
        uint256 amount,
        bool success,
        uint256 nonce
    ) internal {
        uint32 srcEid = sc.spokeEid();
        bytes32 spokeSender = bytes32(uint256(uint160(address(sc))));

        bytes32 withdrawId = keccak256(abi.encodePacked(user, srcEid, asset, amount, block.number, nonce));

        bytes memory payload = abi.encode(withdrawId, success, user, srcEid, asset, amount);
        bytes memory message = abi.encode(uint8(2), payload);

        vm.prank(address(mockLzEndpoint));
        hubController.lzReceive(
            Origin({srcEid: srcEid, sender: spokeSender, nonce: 2}), bytes32(uint256(2)), message, address(0), bytes("")
        );
    }

    /// @notice Simulate seize receipt from a specific spoke
    function _simulateSeizeReceipt(
        SpokeController sc,
        bytes32 liqId,
        address user,
        address seizeAsset,
        uint256 seizeAmount,
        address liquidator,
        bool success
    ) internal {
        uint32 srcEid = sc.spokeEid();
        bytes32 spokeSender = bytes32(uint256(uint160(address(sc))));

        bytes memory payload = abi.encode(liqId, success, user, srcEid, seizeAsset, seizeAmount, liquidator);
        bytes memory message = abi.encode(uint8(4), payload);

        vm.prank(address(mockLzEndpoint));
        hubController.lzReceive(
            Origin({srcEid: srcEid, sender: spokeSender, nonce: 5}), bytes32(uint256(5)), message, address(0), bytes("")
        );
    }

    /// @notice Simulate repay receipt from a specific spoke
    function _simulateRepayReceipt(SpokeController sc, bytes32 repayId, address user, address asset, uint256 amount)
        internal
    {
        uint32 srcEid = sc.spokeEid();
        bytes32 spokeSender = bytes32(uint256(uint160(address(sc))));

        bytes memory payload = abi.encode(repayId, user, srcEid, asset, amount);
        bytes memory message = abi.encode(uint8(3), payload);

        vm.prank(address(mockLzEndpoint));
        hubController.lzReceive(
            Origin({srcEid: srcEid, sender: spokeSender, nonce: 4}), bytes32(uint256(4)), message, address(0), bytes("")
        );
    }

    /// @notice Complete deposit flow on a specific spoke
    function _depositAndCredit(
        SpokeController sc,
        CollateralVault cv,
        MockERC20 token,
        address user,
        bytes32 depositId,
        address canonicalAsset,
        uint256 amount
    ) internal returns (uint256) {
        _mockLzSend();

        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        vm.prank(user);
        sc.depositAndNotify{value: 0.1 ether}(depositId, canonicalAsset, amount, bytes(""), fee);

        assertEq(cv.lockedBalanceOf(user, address(token)), amount);

        _simulateDepositReceipt(sc, depositId, user, canonicalAsset, amount);

        assertEq(positionBook.collateralOf(user, sc.spokeEid(), canonicalAsset), amount);

        return amount;
    }
}
