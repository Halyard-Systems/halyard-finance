// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "lib/forge-std/src/Script.sol";

import {HubAccessManager} from "../src/hub/HubAccessManager.sol";
import {HubController} from "../src/hub/HubController.sol";
import {HubRouter} from "../src/hub/HubRouter.sol";
import {AssetRegistry} from "../src/hub/AssetRegistry.sol";
import {PositionBook} from "../src/hub/PositionBook.sol";
import {RiskEngine} from "../src/hub/RiskEngine.sol";
import {LiquidationEngine} from "../src/hub/LiquidationEngine.sol";
import {DebtManager} from "../src/hub/DebtManager.sol";
import {PythOracleAdapter} from "../src/hub/PythOracleAdapter.sol";
import {CollateralVault} from "../src/spoke/CollateralVault.sol";
import {LiquidityVault} from "../src/spoke/LiquidityVault.sol";
import {SpokeController} from "../src/spoke/SpokeController.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

// Import shared mock contracts from the single-spoke deployment
import {MockLZEndpointLocal, MockOracleLocal} from "./LocalDeploymentEth.s.sol";

/// @title LocalDeploymentMultiSpoke
/// @notice Deploys the full Halyard protocol (hub + 3 spokes: ETH, ARB, BASE) to a local Anvil node.
///         All spokes share one MockLZEndpointLocal which routes by EID.
///         Uses LZ V2 testnet EIDs: ETH=40161, ARB=40231, BASE=40245.
contract LocalDeploymentMultiSpokeScript is Script {
    // LZ V2 testnet EIDs
    uint32 constant HUB_EID = 40161;
    uint32 constant ETH_EID = 40161;
    uint32 constant ARB_EID = 40231;
    uint32 constant BASE_EID = 40245;

    function setUp() public {}

    function run() public {
        address deployer = msg.sender;

        console.log("=== Halyard Multi-Spoke Local Deployment ===");
        console.log("Deployer:", deployer);
        console.log("");

        vm.startBroadcast();

        // ============================================================
        // 1. Deploy mock LayerZero endpoint (shared across all spokes)
        // ============================================================
        MockLZEndpointLocal mockLzEndpoint = new MockLZEndpointLocal();
        console.log("MockLZEndpoint:", address(mockLzEndpoint));

        // ============================================================
        // 2. Deploy mock tokens per spoke
        // ============================================================
        // ETH spoke tokens
        MockERC20 usdcEth = new MockERC20("USD Coin (ETH)", "USDC", 6);
        MockERC20 wethEth = new MockERC20("Wrapped Ether (ETH)", "WETH", 18);

        // ARB spoke tokens
        MockERC20 usdcArb = new MockERC20("USD Coin (ARB)", "USDC", 6);
        MockERC20 wethArb = new MockERC20("Wrapped Ether (ARB)", "WETH", 18);

        // BASE spoke tokens
        MockERC20 usdcBase = new MockERC20("USD Coin (BASE)", "USDC", 6);
        MockERC20 wethBase = new MockERC20("Wrapped Ether (BASE)", "WETH", 18);

        console.log("ETH USDC:", address(usdcEth));
        console.log("ETH WETH:", address(wethEth));
        console.log("ARB USDC:", address(usdcArb));
        console.log("ARB WETH:", address(wethArb));
        console.log("BASE USDC:", address(usdcBase));
        console.log("BASE WETH:", address(wethBase));

        // Mint tokens to deployer for testing
        usdcEth.mint(deployer, 1_000_000e6);
        wethEth.mint(deployer, 1_000e18);
        usdcArb.mint(deployer, 1_000_000e6);
        wethArb.mint(deployer, 1_000e18);
        usdcBase.mint(deployer, 1_000_000e6);
        wethBase.mint(deployer, 1_000e18);

        // ============================================================
        // 3. Deploy Hub contracts
        // ============================================================
        HubAccessManager accessManager = new HubAccessManager(deployer);
        console.log("HubAccessManager:", address(accessManager));

        HubController hubController = new HubController(deployer, address(mockLzEndpoint), address(accessManager));
        console.log("HubController:", address(hubController));

        HubRouter hubRouter = new HubRouter(deployer, address(accessManager));
        console.log("HubRouter:", address(hubRouter));

        AssetRegistry assetRegistry = new AssetRegistry(address(accessManager));
        console.log("AssetRegistry:", address(assetRegistry));

        PositionBook positionBook = new PositionBook(address(accessManager));
        console.log("PositionBook:", address(positionBook));

        DebtManager debtManager = new DebtManager(address(accessManager), address(assetRegistry));
        console.log("DebtManager:", address(debtManager));

        RiskEngine riskEngine = new RiskEngine(address(accessManager));
        console.log("RiskEngine:", address(riskEngine));

        LiquidationEngine liquidationEngine = new LiquidationEngine(address(accessManager));
        console.log("LiquidationEngine:", address(liquidationEngine));

        MockOracleLocal mockOracle = new MockOracleLocal();
        // Set realistic prices for all spoke tokens
        mockOracle.setPrice(address(usdcEth), 1e18);     // $1
        mockOracle.setPrice(address(wethEth), 2000e18);   // $2,000
        mockOracle.setPrice(address(usdcArb), 1e18);      // $1
        mockOracle.setPrice(address(wethArb), 2000e18);    // $2,000
        mockOracle.setPrice(address(usdcBase), 1e18);      // $1
        mockOracle.setPrice(address(wethBase), 2000e18);   // $2,000
        console.log("MockOracle:", address(mockOracle));

        // ============================================================
        // 4. Configure asset registry (3 spokes x 2 assets = 6 pairs)
        // ============================================================
        _configureAssets(assetRegistry, ETH_EID, address(usdcEth), address(wethEth));
        _configureAssets(assetRegistry, ARB_EID, address(usdcArb), address(wethArb));
        _configureAssets(assetRegistry, BASE_EID, address(usdcBase), address(wethBase));
        console.log("Asset registry configured (6 collateral + 6 debt configs)");

        // ============================================================
        // 5. Wire hub contracts together
        // ============================================================
        positionBook.setAssetRegistry(address(assetRegistry));
        hubController.setPositionBook(address(positionBook));
        hubRouter.setPositionBook(address(positionBook));
        hubRouter.setHubController(address(hubController));

        debtManager.setAssetRegistry(address(assetRegistry));

        riskEngine.setDependencies(
            address(positionBook), address(debtManager), address(assetRegistry), address(mockOracle)
        );
        hubRouter.setRiskEngine(address(riskEngine));
        hubRouter.setDebtManager(address(debtManager));

        console.log("Hub contracts wired");

        // ============================================================
        // 6. Set up access control permissions
        // ============================================================
        _setupPermissions(
            accessManager,
            hubController,
            hubRouter,
            positionBook,
            riskEngine,
            debtManager,
            liquidationEngine,
            assetRegistry
        );
        console.log("Permissions configured");

        liquidationEngine.setDependencies(
            address(positionBook),
            address(debtManager),
            address(assetRegistry),
            address(mockOracle),
            address(hubController)
        );

        hubController.setHubRouter(address(hubRouter));

        // ============================================================
        // 7. Deploy 3 Spoke triplets
        // ============================================================

        // --- ETH Spoke ---
        (SpokeController scEth, CollateralVault cvEth, LiquidityVault lvEth) = _deploySpoke(
            deployer, address(mockLzEndpoint), hubController, HUB_EID, ETH_EID, address(usdcEth), address(wethEth)
        );
        console.log("ETH SpokeController:", address(scEth));
        console.log("ETH CollateralVault:", address(cvEth));
        console.log("ETH LiquidityVault:", address(lvEth));

        // --- ARB Spoke ---
        (SpokeController scArb, CollateralVault cvArb, LiquidityVault lvArb) = _deploySpoke(
            deployer, address(mockLzEndpoint), hubController, HUB_EID, ARB_EID, address(usdcArb), address(wethArb)
        );
        console.log("ARB SpokeController:", address(scArb));
        console.log("ARB CollateralVault:", address(cvArb));
        console.log("ARB LiquidityVault:", address(lvArb));

        // --- BASE Spoke ---
        (SpokeController scBase, CollateralVault cvBase, LiquidityVault lvBase) = _deploySpoke(
            deployer, address(mockLzEndpoint), hubController, HUB_EID, BASE_EID, address(usdcBase), address(wethBase)
        );
        console.log("BASE SpokeController:", address(scBase));
        console.log("BASE CollateralVault:", address(cvBase));
        console.log("BASE LiquidityVault:", address(lvBase));

        // ============================================================
        // 8. Register OApps with mock endpoint
        // ============================================================
        mockLzEndpoint.registerOApp(address(hubController), HUB_EID);
        mockLzEndpoint.registerOApp(address(scEth), ETH_EID);
        mockLzEndpoint.registerOApp(address(scArb), ARB_EID);
        mockLzEndpoint.registerOApp(address(scBase), BASE_EID);
        console.log("OApps registered with mock endpoint");

        // ============================================================
        // 9. Seed liquidity for borrowing
        // ============================================================
        usdcEth.mint(address(lvEth), 500_000e6);
        wethEth.mint(address(lvEth), 500e18);
        usdcArb.mint(address(lvArb), 500_000e6);
        wethArb.mint(address(lvArb), 500e18);
        usdcBase.mint(address(lvBase), 500_000e6);
        wethBase.mint(address(lvBase), 500e18);
        console.log("Liquidity seeded in all 3 spokes");

        vm.stopBroadcast();

        // ============================================================
        // Print summary for .env configuration
        // ============================================================
        console.log("");
        console.log("=== Frontend .env Configuration ===");
        console.log("");
        console.log("# --- Hub ---");
        console.log("VITE_HUB_CHAIN_ID=31337");
        console.log("VITE_HUB_ROUTER_ADDRESS=", address(hubRouter));
        console.log("VITE_RISK_ENGINE_ADDRESS=", address(riskEngine));
        console.log("VITE_POSITION_BOOK_ADDRESS=", address(positionBook));
        console.log("VITE_DEBT_MANAGER_ADDRESS=", address(debtManager));
        console.log("VITE_LIQUIDATION_ENGINE_ADDRESS=", address(liquidationEngine));
        console.log("VITE_PYTH_ORACLE_ADAPTER_ADDRESS=", address(mockOracle));
        console.log("");

        console.log("# --- Spoke: Ethereum ---");
        console.log("VITE_SPOKE_ETH_CHAIN_ID=31337");
        console.log("VITE_SPOKE_ETH_LZ_EID=40161");
        console.log("VITE_SPOKE_CONTROLLER_ETH_ADDRESS=", address(scEth));
        console.log("VITE_COLLATERAL_VAULT_ETH_ADDRESS=", address(cvEth));
        console.log("VITE_LIQUIDITY_VAULT_ETH_ADDRESS=", address(lvEth));
        _printAssets("ETH", address(usdcEth), address(wethEth));
        console.log("");

        console.log("# --- Spoke: Arbitrum ---");
        console.log("VITE_SPOKE_ARB_CHAIN_ID=31337");
        console.log("VITE_SPOKE_ARB_LZ_EID=40231");
        console.log("VITE_SPOKE_CONTROLLER_ARB_ADDRESS=", address(scArb));
        console.log("VITE_COLLATERAL_VAULT_ARB_ADDRESS=", address(cvArb));
        console.log("VITE_LIQUIDITY_VAULT_ARB_ADDRESS=", address(lvArb));
        _printAssets("ARB", address(usdcArb), address(wethArb));
        console.log("");

        console.log("# --- Spoke: Base ---");
        console.log("VITE_SPOKE_BASE_CHAIN_ID=31337");
        console.log("VITE_SPOKE_BASE_LZ_EID=40245");
        console.log("VITE_SPOKE_CONTROLLER_BASE_ADDRESS=", address(scBase));
        console.log("VITE_COLLATERAL_VAULT_BASE_ADDRESS=", address(cvBase));
        console.log("VITE_LIQUIDITY_VAULT_BASE_ADDRESS=", address(lvBase));
        _printAssets("BASE", address(usdcBase), address(wethBase));
    }

    // ================================================================
    // Internal helpers
    // ================================================================

    function _deploySpoke(
        address deployer,
        address lzEndpoint,
        HubController hubController,
        uint32 hubEid,
        uint32 spokeEid,
        address usdc,
        address weth
    ) internal returns (SpokeController sc, CollateralVault cv, LiquidityVault lv) {
        sc = new SpokeController(deployer, lzEndpoint);
        cv = new CollateralVault(deployer, address(sc));
        lv = new LiquidityVault(deployer, address(sc));

        // Configure spoke
        sc.setCollateralVault(address(cv));
        sc.setLiquidityVault(address(lv));
        sc.configureHub(hubEid, bytes32(uint256(uint160(address(hubController)))));
        sc.configureSpokeEid(spokeEid);

        // Map canonical asset addresses to spoke token addresses
        // (In local deployment, canonical = spoke token since same chain)
        sc.setTokenMapping(usdc, usdc);
        sc.setTokenMapping(weth, weth);

        // Set LayerZero peers (bidirectional trust)
        sc.setPeer(hubEid, bytes32(uint256(uint160(address(hubController)))));
        hubController.setSpoke(spokeEid, bytes32(uint256(uint160(address(sc)))));
        hubController.setPeer(spokeEid, bytes32(uint256(uint160(address(sc)))));
    }

    function _configureAssets(AssetRegistry registry, uint32 eid, address usdc, address weth) internal {
        // USDC as collateral
        registry.setCollateralConfig(
            eid,
            usdc,
            AssetRegistry.CollateralConfig({
                isSupported: true,
                ltvBps: 8000, // 80% LTV
                liqThresholdBps: 8500, // 85% liquidation threshold
                liqBonusBps: 500, // 5% liquidation bonus
                decimals: 6,
                supplyCap: 0
            })
        );

        // WETH as collateral
        registry.setCollateralConfig(
            eid,
            weth,
            AssetRegistry.CollateralConfig({
                isSupported: true,
                ltvBps: 7500, // 75% LTV
                liqThresholdBps: 8000, // 80% liquidation threshold
                liqBonusBps: 500, // 5% liquidation bonus
                decimals: 18,
                supplyCap: 0
            })
        );

        // USDC as borrowable
        registry.setDebtConfig(eid, usdc, AssetRegistry.DebtConfig({isSupported: true, decimals: 6, borrowCap: 0}));
        registry.setBorrowRateApr(eid, usdc, 500); // 5% APR

        // WETH as borrowable
        registry.setDebtConfig(eid, weth, AssetRegistry.DebtConfig({isSupported: true, decimals: 18, borrowCap: 0}));
        registry.setBorrowRateApr(eid, weth, 300); // 3% APR
    }

    function _printAssets(string memory chain, address usdc, address weth) internal pure {
        console.log("VITE_SPOKE_");
        console.log(chain);
        console.log("_ASSETS (paste as JSON):");
        console.log('[{"symbol":"USDC","decimals":6,"address":"', usdc);
        console.log('"},{"symbol":"WETH","decimals":18,"address":"', weth);
        console.log('"}]');
    }

    function buildFunctionSelector(bytes4 selector) internal pure returns (bytes4[] memory) {
        bytes4[] memory funcs = new bytes4[](1);
        funcs[0] = selector;
        return funcs;
    }

    function _setupPermissions(
        HubAccessManager accessManager,
        HubController hubController,
        HubRouter hubRouter,
        PositionBook positionBook,
        RiskEngine riskEngine,
        DebtManager debtManager,
        LiquidationEngine liquidationEngine,
        AssetRegistry assetRegistry
    ) internal {
        // HubController function permissions
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
            address(hubController),
            buildFunctionSelector(hubController.sendSeizeCommand.selector),
            accessManager.ROLE_LIQUIDATION_ENGINE()
        );

        // HubRouter function permissions
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
            address(hubRouter),
            buildFunctionSelector(hubRouter.finalizeLiquidation.selector),
            accessManager.ROLE_HUB_CONTROLLER()
        );

        // PositionBook function permissions
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

        // RiskEngine function permissions
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

        // DebtManager function permissions
        accessManager.setTargetFunctionRole(
            address(debtManager), buildFunctionSelector(debtManager.mintDebt.selector), accessManager.ROLE_ROUTER()
        );
        accessManager.setTargetFunctionRole(
            address(debtManager), buildFunctionSelector(debtManager.burnDebt.selector), accessManager.ROLE_ROUTER()
        );

        // Grant roles to contracts
        accessManager.grantRole(accessManager.ROLE_ROUTER(), address(hubRouter), 0);
        accessManager.grantRole(accessManager.ROLE_HUB_CONTROLLER(), address(hubController), 0);
        accessManager.grantRole(accessManager.ROLE_ASSET_REGISTRY(), address(assetRegistry), 0);
        accessManager.grantRole(accessManager.ROLE_RISK_ENGINE(), address(riskEngine), 0);
        accessManager.grantRole(accessManager.ROLE_POSITION_BOOK(), address(positionBook), 0);
        accessManager.grantRole(accessManager.ROLE_LIQUIDATION_ENGINE(), address(liquidationEngine), 0);
        accessManager.grantRole(accessManager.ROLE_ROUTER(), address(liquidationEngine), 0);
    }
}
