// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {DepositManager} from "../src/DepositManager.sol";

contract CheckDepositManagerTokensScript is Script {
    DepositManager public depositManager;

    function setUp() public {}

    function run() public {
        // Get the deployed DepositManager address from environment
        address payable depositManagerAddress = payable(vm.envAddress("DEPOSIT_MANAGER_ADDRESS"));

        console.log("Checking DepositManager at:", depositManagerAddress);

        // Get the DepositManager instance
        depositManager = DepositManager(depositManagerAddress);

        // Get all supported tokens
        bytes32[] memory supportedTokens = depositManager.getSupportedTokens();
        
        console.log("Number of supported tokens:", supportedTokens.length);
        
        for (uint i = 0; i < supportedTokens.length; i++) {
            bytes32 tokenId = supportedTokens[i];
            DepositManager.Asset memory asset = depositManager.getAsset(tokenId);
            
            console.log("=== Token", i + 1, "===");
            console.log("Token ID:");
            console.logBytes32(tokenId);
            console.log("Symbol:");
            console.log(asset.symbol);
            console.log("Token Address:");
            console.log(asset.tokenAddress);
            console.log("Decimals:");
            console.log(asset.decimals);
            console.log("Is Active:");
            console.log(asset.isActive);
            console.log("Total Deposits:");
            console.log(asset.totalDeposits);
            console.log("Total Borrows:");
            console.log(asset.totalBorrows);
            console.log("==================");
        }
    }
}
