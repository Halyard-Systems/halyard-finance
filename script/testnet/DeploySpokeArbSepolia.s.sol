// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {SpokeController} from "../../src/spoke/SpokeController.sol";
import {CollateralVault} from "../../src/spoke/CollateralVault.sol";
import {LiquidityVault} from "../../src/spoke/LiquidityVault.sol";

/// @title DeploySpokeArbSepolia
/// @notice Deploys an ARB spoke on Arbitrum Sepolia using the real LayerZero EndpointV2.
///         Requires env vars: LZ_ENDPOINT, HUB_EID, HUB_CONTROLLER (bytes32),
///         SPOKE_EID, USDC_ADDRESS, WETH_ADDRESS, CANONICAL_USDC, CANONICAL_WETH
contract DeploySpokeArbSepoliaScript is Script {
    function run() public {
        address deployer = msg.sender;

        address lzEndpoint = vm.envAddress("LZ_ENDPOINT");
        uint32 hubEid = uint32(vm.envUint("HUB_EID"));
        bytes32 hubController = vm.envBytes32("HUB_CONTROLLER");
        uint32 spokeEid = uint32(vm.envUint("SPOKE_EID"));
        address usdc = vm.envAddress("USDC_ADDRESS");
        address weth = vm.envAddress("WETH_ADDRESS");
        address canonicalUsdc = vm.envAddress("CANONICAL_USDC");
        address canonicalWeth = vm.envAddress("CANONICAL_WETH");

        console.log("=== Deploy ARB Spoke on Arbitrum Sepolia ===");
        console.log("Deployer:", deployer);
        console.log("LZ Endpoint:", lzEndpoint);
        console.log("Hub EID:", hubEid);
        console.log("Spoke EID:", spokeEid);

        vm.startBroadcast();

        SpokeController sc = new SpokeController(deployer, lzEndpoint);
        CollateralVault cv = new CollateralVault(deployer, address(sc));
        LiquidityVault lv = new LiquidityVault(deployer, address(sc));

        sc.setCollateralVault(address(cv));
        sc.setLiquidityVault(address(lv));
        sc.configureHub(hubEid, hubController);
        sc.configureSpokeEid(spokeEid);
        sc.setTokenMapping(canonicalUsdc, usdc);
        sc.setTokenMapping(canonicalWeth, weth);
        sc.setPeer(hubEid, hubController);

        vm.stopBroadcast();

        console.log("");
        console.log("SpokeController:", address(sc));
        console.log("CollateralVault:", address(cv));
        console.log("LiquidityVault:", address(lv));
        console.log("");
        console.log("Next: Register this spoke on the hub with RegisterSpokesOnHub.s.sol");
    }
}
