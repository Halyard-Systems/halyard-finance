// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {HubController} from "../../src/hub/HubController.sol";
import {AssetRegistry} from "../../src/hub/AssetRegistry.sol";

/// @title RegisterSpokesOnHub
/// @notice Runs on the hub chain (Sepolia) to register all 3 spokes.
///         Calls setSpoke() + setPeer() for each spoke EID, and registers assets in AssetRegistry.
///         Requires env vars for each spoke: SPOKE_CONTROLLER_ETH, SPOKE_CONTROLLER_ARB, SPOKE_CONTROLLER_BASE
///         and asset addresses: USDC_ETH, WETH_ETH, USDC_ARB, WETH_ARB, USDC_BASE, WETH_BASE
contract RegisterSpokesOnHubScript is Script {
    function run() public {
        address hubControllerAddr = vm.envAddress("HUB_CONTROLLER_ADDRESS");
        address assetRegistryAddr = vm.envAddress("ASSET_REGISTRY_ADDRESS");

        HubController hubController = HubController(payable(hubControllerAddr));
        AssetRegistry assetRegistry = AssetRegistry(assetRegistryAddr);

        // Spoke controllers (bytes32-encoded addresses)
        address scEth = vm.envAddress("SPOKE_CONTROLLER_ETH");
        address scArb = vm.envAddress("SPOKE_CONTROLLER_ARB");
        address scBase = vm.envAddress("SPOKE_CONTROLLER_BASE");

        // LZ V2 testnet EIDs
        uint32 ethEid = 40161;
        uint32 arbEid = 40231;
        uint32 baseEid = 40245;

        // Asset addresses per spoke
        address usdcEth = vm.envAddress("USDC_ETH");
        address wethEth = vm.envAddress("WETH_ETH");
        address usdcArb = vm.envAddress("USDC_ARB");
        address wethArb = vm.envAddress("WETH_ARB");
        address usdcBase = vm.envAddress("USDC_BASE");
        address wethBase = vm.envAddress("WETH_BASE");

        console.log("=== Register Spokes on Hub ===");

        vm.startBroadcast();

        // Register ETH spoke
        _registerSpoke(hubController, ethEid, scEth);
        _configureAssets(assetRegistry, ethEid, usdcEth, wethEth);
        console.log("ETH spoke registered (EID: 40161)");

        // Register ARB spoke
        _registerSpoke(hubController, arbEid, scArb);
        _configureAssets(assetRegistry, arbEid, usdcArb, wethArb);
        console.log("ARB spoke registered (EID: 40231)");

        // Register BASE spoke
        _registerSpoke(hubController, baseEid, scBase);
        _configureAssets(assetRegistry, baseEid, usdcBase, wethBase);
        console.log("BASE spoke registered (EID: 40245)");

        vm.stopBroadcast();

        console.log("");
        console.log("All 3 spokes registered on hub.");
    }

    function _registerSpoke(HubController hubController, uint32 eid, address spokeController) internal {
        bytes32 spokeBytes = bytes32(uint256(uint160(spokeController)));
        hubController.setSpoke(eid, spokeBytes);
        hubController.setPeer(eid, spokeBytes);
    }

    function _configureAssets(AssetRegistry registry, uint32 eid, address usdc, address weth) internal {
        // USDC as collateral
        registry.setCollateralConfig(
            eid,
            usdc,
            AssetRegistry.CollateralConfig({
                isSupported: true,
                ltvBps: 8000,
                liqThresholdBps: 8500,
                liqBonusBps: 500,
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
                ltvBps: 7500,
                liqThresholdBps: 8000,
                liqBonusBps: 500,
                decimals: 18,
                supplyCap: 0
            })
        );

        // USDC as borrowable
        registry.setDebtConfig(eid, usdc, AssetRegistry.DebtConfig({isSupported: true, decimals: 6, borrowCap: 0}));
        registry.setBorrowRateApr(eid, usdc, 500);

        // WETH as borrowable
        registry.setDebtConfig(eid, weth, AssetRegistry.DebtConfig({isSupported: true, decimals: 18, borrowCap: 0}));
        registry.setBorrowRateApr(eid, weth, 300);
    }
}
