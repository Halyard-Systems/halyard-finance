// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract MockERC20DeploymentScript is Script {
    function setUp() public {}

    function run() public {
        // Get deployment parameters from environment or use defaults
        string memory tokenName = vm.envString("TOKEN_NAME");
        string memory tokenSymbol = vm.envString("TOKEN_SYMBOL");
        uint8 tokenDecimals = uint8(vm.envUint("TOKEN_DECIMALS"));

        console.log("=== MockERC20 Deployment Configuration ===");
        console.log("Token Name:", tokenName);
        console.log("Token Symbol:", tokenSymbol);
        console.log("Token Decimals:", tokenDecimals);
        console.log("Deployer Address:", msg.sender);
        console.log("");

        vm.startBroadcast();

        console.log("Deploying MockERC20...");
        MockERC20 mockToken = new MockERC20(tokenName, tokenSymbol, tokenDecimals);

        vm.stopBroadcast();

        console.log("=== Deployment Results ===");
        console.log("MockERC20 deployed at:", address(mockToken));
        console.log("Token Name:", mockToken.name());
        console.log("Token Symbol:", mockToken.symbol());
        console.log("Token Decimals:", mockToken.decimals());
    }
}
