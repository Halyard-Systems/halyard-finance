// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {DepositManager} from "../src/DepositManager.sol";

contract DepositManagerScript is Script {
    DepositManager public depositManager;

    address STARGATE_ROUTER_SEPOLIA_TESTNET =
        0x2836045A50744FB50D3d04a9C8D18aD7B5012102;
    uint256 USDC_POOL_ID_SEPOLIA_TESTNET = 1;

    function setUp() public {}

    function run() public {
        // Get constructor parameters from environment or set defaults
        address stargateRouter = vm.envOr(
            "STARGATE_ROUTER",
            STARGATE_ROUTER_SEPOLIA_TESTNET
        ); // Example: Polygon Stargate Router
        uint256 poolId = vm.envOr("POOL_ID", uint256(1)); // USDC pool ID

        vm.startBroadcast();

        depositManager = new DepositManager(stargateRouter, poolId);

        console.log("DepositManager deployed at:", address(depositManager));
        console.log("Stargate Router:", stargateRouter);
        console.log("Pool ID:", poolId);

        vm.stopBroadcast();
    }
}
