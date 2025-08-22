// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "lib/forge-std/src/Script.sol";

contract MockERC20DeploymentScript is Script {
    function setUp() public {}

    function run() public {
        MockERC20 mockToken;

        vm.startBroadcast();
        console.log("Deploying TOKEN MockERC20...");
        mockToken =
            new MockERC20(vm.envString("TOKEN_NAME"), vm.envString("TOKEN_SYMBOL"), vm.envUint("TOKEN_DECIMALS"));
        console.log("MockERC20 %s deployed at:", vm.envString("TOKEN_NAME"), address(mockToken));
    }
}
