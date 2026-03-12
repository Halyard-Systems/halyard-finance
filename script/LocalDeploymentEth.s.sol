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

/// @title LocalDeploymentEth
/// @notice Deploys the full Halyard protocol (hub + spoke) to a local Anvil node.
///         Both hub and spoke are deployed on the same chain for local testing.
///         Uses a minimal mock LZ endpoint since cross-chain messaging is simulated locally.
contract LocalDeploymentEthScript is Script {
    function setUp() public {}

    function run() public {
        address deployer = msg.sender;

        // LayerZero EIDs (matching Sepolia / local conventions)
        uint32 hubEid = 40161; // Sepolia LZ EID
        uint32 spokeEid = 40161; // Same chain for local

        console.log("=== Halyard Local Deployment ===");
        console.log("Deployer:", deployer);
        console.log("");

        vm.startBroadcast();

        // ============================================================
        // 1. Deploy mock LayerZero endpoint (minimal contract that accepts ETH)
        // ============================================================
        MockLZEndpointLocal mockLzEndpoint = new MockLZEndpointLocal();
        console.log("MockLZEndpoint:", address(mockLzEndpoint));

        // ============================================================
        // 2. Deploy mock tokens
        // ============================================================
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 weth = new MockERC20("Wrapped Ether", "WETH", 18);
        console.log("USDC:", address(usdc));
        console.log("WETH:", address(weth));

        // Mint tokens to deployer for testing
        usdc.mint(deployer, 1_000_000e6);
        weth.mint(deployer, 1_000e18);

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

        // Deploy a mock oracle (just a contract that can receive calls)
        MockOracleLocal mockOracle = new MockOracleLocal();
        console.log("MockOracle:", address(mockOracle));

        // ============================================================
        // 4. Configure asset registry
        // ============================================================

        // USDC as collateral on spoke
        assetRegistry.setCollateralConfig(
            spokeEid,
            address(usdc),
            AssetRegistry.CollateralConfig({
                isSupported: true,
                ltvBps: 8000, // 80% LTV
                liqThresholdBps: 8500, // 85% liquidation threshold
                liqBonusBps: 500, // 5% liquidation bonus
                decimals: 6,
                supplyCap: 0 // no cap
            })
        );

        // WETH as collateral on spoke
        assetRegistry.setCollateralConfig(
            spokeEid,
            address(weth),
            AssetRegistry.CollateralConfig({
                isSupported: true,
                ltvBps: 7500, // 75% LTV
                liqThresholdBps: 8000, // 80% liquidation threshold
                liqBonusBps: 500, // 5% liquidation bonus
                decimals: 18,
                supplyCap: 0
            })
        );

        // USDC as borrowable asset
        assetRegistry.setDebtConfig(
            spokeEid, address(usdc), AssetRegistry.DebtConfig({isSupported: true, decimals: 6, borrowCap: 0})
        );
        assetRegistry.setBorrowRateApr(spokeEid, address(usdc), 500); // 5% APR

        // WETH as borrowable asset
        assetRegistry.setDebtConfig(
            spokeEid, address(weth), AssetRegistry.DebtConfig({isSupported: true, decimals: 18, borrowCap: 0})
        );
        assetRegistry.setBorrowRateApr(spokeEid, address(weth), 300); // 3% APR

        console.log("Asset registry configured");

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

        // Set LiquidationEngine dependencies (after permissions)
        liquidationEngine.setDependencies(
            address(positionBook),
            address(debtManager),
            address(assetRegistry),
            address(mockOracle),
            address(hubController)
        );

        // ============================================================
        // 7. Deploy Spoke contracts
        // ============================================================
        SpokeController spokeController = new SpokeController(deployer, address(mockLzEndpoint));
        console.log("SpokeController:", address(spokeController));

        CollateralVault collateralVault = new CollateralVault(deployer, address(spokeController));
        console.log("CollateralVault:", address(collateralVault));

        LiquidityVault liquidityVault = new LiquidityVault(deployer, address(spokeController));
        console.log("LiquidityVault:", address(liquidityVault));

        // ============================================================
        // 8. Configure spoke
        // ============================================================
        spokeController.setCollateralVault(address(collateralVault));
        spokeController.setLiquidityVault(address(liquidityVault));
        spokeController.configureHub(hubEid, bytes32(uint256(uint160(address(hubController)))));
        spokeController.configureSpokeEid(spokeEid);

        // Map canonical asset addresses to spoke token addresses
        // (In local deployment, canonical = spoke token since same chain)
        spokeController.setTokenMapping(address(usdc), address(usdc));
        spokeController.setTokenMapping(address(weth), address(weth));

        // Set LayerZero peers (bidirectional trust)
        spokeController.setPeer(hubEid, bytes32(uint256(uint160(address(hubController)))));
        hubController.setSpoke(spokeEid, bytes32(uint256(uint160(address(spokeController)))));
        hubController.setPeer(spokeEid, bytes32(uint256(uint160(address(spokeController)))));
        hubController.setHubRouter(address(hubRouter));

        console.log("Spoke configured");

        // ============================================================
        // 9. Seed liquidity for borrowing
        // ============================================================
        // Mint tokens to liquidity vault so borrows can be fulfilled
        usdc.mint(address(liquidityVault), 500_000e6);
        weth.mint(address(liquidityVault), 500e18);
        console.log("Liquidity seeded");

        vm.stopBroadcast();

        // ============================================================
        // Print summary for .env configuration
        // ============================================================
        console.log("");
        console.log("=== Frontend .env Configuration ===");
        console.log("VITE_HUB_CHAIN_ID=31337");
        console.log("VITE_HUB_ROUTER_ADDRESS=", address(hubRouter));
        console.log("VITE_RISK_ENGINE_ADDRESS=", address(riskEngine));
        console.log("VITE_POSITION_BOOK_ADDRESS=", address(positionBook));
        console.log("VITE_DEBT_MANAGER_ADDRESS=", address(debtManager));
        console.log("VITE_LIQUIDATION_ENGINE_ADDRESS=", address(liquidationEngine));
        console.log("VITE_PYTH_ORACLE_ADAPTER_ADDRESS=", address(mockOracle));
        console.log("");
        console.log("VITE_SPOKE_ETH_CHAIN_ID=31337");
        console.log("VITE_SPOKE_ETH_LZ_EID=40161");
        console.log("VITE_SPOKE_CONTROLLER_ETH_ADDRESS=", address(spokeController));
        console.log("VITE_COLLATERAL_VAULT_ETH_ADDRESS=", address(collateralVault));
        console.log("VITE_LIQUIDITY_VAULT_ETH_ADDRESS=", address(liquidityVault));
        console.log("");
        console.log("Mock Tokens:");
        console.log("  USDC:", address(usdc));
        console.log("  WETH:", address(weth));
        console.log("");
        console.log("VITE_SPOKE_ETH_ASSETS (paste as JSON):");
        console.log('[{"symbol":"USDC","decimals":6,"address":"', address(usdc));
        console.log('"},{"symbol":"WETH","decimals":18,"address":"', address(weth));
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
        // LiquidationEngine also needs ROLE_ROUTER to call DebtManager.burnDebt
        accessManager.grantRole(accessManager.ROLE_ROUTER(), address(liquidationEngine), 0);
    }
}

/// @notice Minimal mock LZ endpoint for local deployment (accepts ETH, no-ops on all calls)
contract MockLZEndpointLocal {
    receive() external payable {}
    fallback() external payable {}
}

/// @notice Minimal mock oracle for local deployment
/// @dev Returns a fixed price of $1 (1e18) for any asset. Override getPrice for custom values.
contract MockOracleLocal {
    /// @notice Returns price in 1e18 format. Defaults to $1 for all assets.
    function getPrice(address) external pure returns (uint256) {
        return 1e18;
    }

    receive() external payable {}
    fallback() external payable {}
}
