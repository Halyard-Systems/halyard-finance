// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {DepositManager} from "../src/DepositManager.sol";

contract AddTokenToDepositManagerScript is Script {
    DepositManager public depositManager;

    function setUp() public {}

    function run() public {
        // Get the deployed DepositManager address from environment
        address payable depositManagerAddress = payable(vm.envAddress("DEPOSIT_MANAGER_ADDRESS"));

        // Get token parameters from environment or set defaults
        string memory symbol = vm.envString("ADD_TOKEN_SYMBOL");
        address tokenAddress = vm.envAddress("ADD_TOKEN_ADDRESS");
        uint8 decimals = uint8(vm.envUint("ADD_TOKEN_DECIMALS"));

        // Get protocol parameters from environment or set defaults
        uint256 baseRate = vm.envOr("ADD_TOKEN_BASE_RATE", uint256(0.05e27)); // Default 0.05 tokens
        uint256 slope1 = vm.envOr("ADD_TOKEN_SLOPE1", uint256(0.3e27)); // Default 0.3 tokens
        uint256 slope2 = vm.envOr("ADD_TOKEN_SLOPE2", uint256(3.0e27)); // Default 3.0 tokens
        uint256 kink = vm.envOr("ADD_TOKEN_KINK", uint256(0.8e18)); // Default 80%
        uint256 reserveFactor = vm.envOr("ADD_TOKEN_RESERVE_FACTOR", uint256(0.1e27)); // Default 10%

        console.log("Adding token to DepositManager at:", depositManagerAddress);
        console.log("Symbol:", symbol);
        console.log("Token Address:", tokenAddress);
        console.log("Token Decimals:", decimals);
        console.log("Base Rate:", baseRate);
        console.log("Slope1:", slope1);
        console.log("Slope2:", slope2);
        console.log("Kink:", kink);
        console.log("Reserve Factor:", reserveFactor);

        vm.startBroadcast();

        // Get the DepositManager instance
        depositManager = DepositManager(depositManagerAddress);

        // Add the token to the protocol
        depositManager.addToken(symbol, tokenAddress, decimals, baseRate, slope1, slope2, kink, reserveFactor);

        console.log("Token", symbol, "successfully added to protocol");

        vm.stopBroadcast();
    }
}
