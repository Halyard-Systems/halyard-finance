// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {DepositManager} from "../src/DepositManager.sol";
import {BorrowManager} from "../src/BorrowManager.sol";

contract TestnetDeploymentScript is Script {
    DepositManager public depositManager;
    BorrowManager public borrowManager;

    // Sepolia Testnet Pyth address
    address public PYTH_SEPOLIA = 0xDd24F84d36BF92C65F92307595335bdFab5Bbd21;

    // Testnet addresses
    address constant STARGATE_ROUTER_SEPOLIA = 0x2836045A50744FB50D3d04a9C8D18aD7B5012102;
    // address constant STARGATE_ROUTER_ARBITRUM_SEPOLIA = 0x2a6C4aE6c3F6f91E8ec7C2f40bAD9351a0108A81;
    // address constant STARGATE_ROUTER_BASE_SEPOLIA = 0x2a6C4aE6c3F6f91E8ec7C2f40bAD9351a0108A81;

    // Testnet token addresses (Sepolia)
    // address constant USDC_SEPOLIA = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    // address constant USDT_SEPOLIA = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0;
    // address constant WETH_SEPOLIA = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;

    // Pool IDs for different testnets
    uint256 constant USDC_POOL_ID_SEPOLIA = 1;
    uint256 constant USDC_POOL_ID_ARBITRUM_SEPOLIA = 1;
    uint256 constant USDC_POOL_ID_BASE_SEPOLIA = 1;

    function setUp() public {}

    // function _getNetworkConfig()
    //     internal
    //     view
    //     returns (address router, uint256 poolId, address usdc, address usdt, address weth)
    // {
    //     string memory network = vm.envOr("NETWORK", "sepolia");

    //     if (keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("sepolia"))) {
    //         router = STARGATE_ROUTER_SEPOLIA;
    //         poolId = USDC_POOL_ID_SEPOLIA;
    //         // usdc = USDC_SEPOLIA;
    //         // usdt = USDT_SEPOLIA;
    //         // weth = WETH_SEPOLIA;
    //     } else if (keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("arbitrum-sepolia"))) {
    //         router = STARGATE_ROUTER_ARBITRUM_SEPOLIA;
    //         poolId = USDC_POOL_ID_ARBITRUM_SEPOLIA;
    //         // usdc = USDC_SEPOLIA;
    //         // usdt = USDT_SEPOLIA;
    //         // weth = WETH_SEPOLIA;
    //     } else if (keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("base-sepolia"))) {
    //         router = STARGATE_ROUTER_BASE_SEPOLIA;
    //         poolId = USDC_POOL_ID_BASE_SEPOLIA;
    //         // usdc = USDC_SEPOLIA;
    //         // usdt = USDT_SEPOLIA;
    //         // weth = WETH_SEPOLIA;
    //     } else {
    //         revert("Unsupported network");
    //     }
    // }

    function run() public {
        // Get network configuration
        // (address stargateRouter, uint256 poolId) =
        //     _getNetworkConfig();

        // Get deployment parameters from environment or use defaults
        uint256 liquidationThreshold = vm.envOr("LIQUIDATION_THRESHOLD", uint256(0.8e18)); // 80%
        uint256 updateFee = vm.envOr("PYTH_UPDATE_FEE", uint256(1000000000000000)); // 0.001 ETH
        uint256 validTime = vm.envOr("PYTH_VALID_TIME", uint256(180)); // 3 minutes

        console.log("=== Testnet Deployment Configuration ===");
        //console.log("Stargate Router:", stargateRouter);
        //console.log("Pool ID:", poolId);
        // console.log("USDC Token:", usdcToken);
        // console.log("USDT Token:", usdtToken);
        // console.log("WETH Token:", wethToken);
        console.log("Liquidation Threshold:", liquidationThreshold);
        console.log("Pyth Update Fee:", updateFee);
        console.log("Pyth Valid Time:", validTime);
        console.log("========================================");

        vm.startBroadcast();

        // Deploy DepositManager
        console.log("Deploying DepositManager...");
        // Pool ID is not currently used
        depositManager = new DepositManager(STARGATE_ROUTER_SEPOLIA, 1);
        console.log("DepositManager deployed at:", address(depositManager));

        // Add tokens to DepositManager with testnet-appropriate parameters
        // ETH (native token)
        // depositManager.addToken(
        //     "ETH",
        //     address(0), // Native ETH
        //     18,
        //     0.1e27, // minDeposit: 0.1 ETH
        //     0.5e27, // maxDeposit: 0.5 ETH
        //     5.0e27, // maxTotalDeposit: 5 ETH
        //     0.8e18, // collateralRatio: 80%
        //     0.1e27 // liquidationPenalty: 10%
        // );
        // console.log("ETH token added to protocol");

        // // USDC
        // depositManager.addToken(
        //     "USDC",
        //     usdcToken,
        //     6,
        //     100e6, // minDeposit: 100 USDC
        //     1000e6, // maxDeposit: 1000 USDC
        //     10000e6, // maxTotalDeposit: 10000 USDC
        //     0.8e18, // collateralRatio: 80%
        //     0.1e27 // liquidationPenalty: 10%
        // );
        // console.log("USDC token added to protocol");

        // // USDT
        // depositManager.addToken(
        //     "USDT",
        //     usdtToken,
        //     6,
        //     100e6, // minDeposit: 100 USDT
        //     1000e6, // maxDeposit: 1000 USDT
        //     10000e6, // maxTotalDeposit: 10000 USDT
        //     0.8e18, // collateralRatio: 80%
        //     0.1e27 // liquidationPenalty: 10%
        // );
        // console.log("USDT token added to protocol");

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
