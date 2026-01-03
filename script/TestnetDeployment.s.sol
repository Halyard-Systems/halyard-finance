// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {DepositManager} from "../src/DepositManager.sol";
import {BorrowManager} from "../src/BorrowManager.sol";

contract TestnetDeploymentScript is Script {
    DepositManager public depositManager;
    BorrowManager public borrowManager;

    // Sepolia Testnet addresses
    address constant LAYERZERO_ENDPOINT_V2_SEPOLIA = 0x3C22696570886A815a339A2c43DC18b3eb4420A1;
    address public PYTH_SEPOLIA = 0xDd24F84d36BF92C65F92307595335bdFab5Bbd21;
    address constant STARGATE_ROUTER_SEPOLIA = 0x2836045A50744FB50D3d04a9C8D18aD7B5012102;

    function setUp() public {}

    function run() public {
        uint256 liquidationThreshold = vm.envOr("LIQUIDATION_THRESHOLD", uint256(0.8e18)); // 80%
        uint256 updateFee = vm.envOr("PYTH_UPDATE_FEE", uint256(1000000000000000)); // 0.001 ETH
        uint256 validTime = vm.envOr("PYTH_VALID_TIME", uint256(60)); // 1 minutes

        console.log("=== Testnet Deployment Configuration ===");
        console.log("Liquidation Threshold:", liquidationThreshold);
        console.log("Pyth Update Fee:", updateFee);
        console.log("Pyth Valid Time:", validTime);
        console.log("========================================");

        address deployer = msg.sender;

        vm.startBroadcast();

        // Deploy DepositManager
        console.log("Deploying DepositManager...");
        // Pool ID is not currently used
        depositManager = new DepositManager(LAYERZERO_ENDPOINT_V2_SEPOLIA, deployer);
        console.log("DepositManager deployed at:", address(depositManager));

        // Deploy BorrowManager
        console.log("Deploying BorrowManager...");
        borrowManager = new BorrowManager(address(depositManager), PYTH_SEPOLIA, liquidationThreshold);
        console.log("BorrowManager deployed at:", address(borrowManager));

        // Link DepositManager and BorrowManager
        depositManager.setBorrowManager(address(borrowManager));
        console.log("BorrowManager linked to DepositManager");

        vm.stopBroadcast();

        console.log("=== Deployment Summary ===");
        console.log("DepositManager:", address(depositManager));
        console.log("BorrowManager:", address(borrowManager));
        console.log("==========================");
    }
}
