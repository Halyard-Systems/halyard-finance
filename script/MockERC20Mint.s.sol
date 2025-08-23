// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract MockERC20MintScript is Script {
    function setUp() public {}

    function run() public {
        // Get minting parameters from environment or use defaults
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        address recipient = vm.envOr("RECIPIENT_ADDRESS", msg.sender);
        uint256 amount = vm.envOr("MINT_AMOUNT", uint256(1000 * 10**18)); // Default 1000 tokens

        console.log("=== MockERC20 Minting Configuration ===");
        console.log("Token Address:", tokenAddress);
        console.log("Recipient Address:", recipient);
        console.log("Mint Amount:", amount);
        console.log("Caller Address:", msg.sender);
        console.log("");

        // Load the deployed MockERC20 contract
        MockERC20 token = MockERC20(tokenAddress);

        // Verify the token exists by checking its name
        string memory tokenName = token.name();
        string memory tokenSymbol = token.symbol();
        uint8 tokenDecimals = token.decimals();

        console.log("=== Token Information ===");
        console.log("Token Name:", tokenName);
        console.log("Token Symbol:", tokenSymbol);
        console.log("Token Decimals:", tokenDecimals);
        console.log("Current Total Supply:", token.balanceOf(address(0))); // MockERC20 doesn't track total supply, so we check balance of zero address
        console.log("Recipient Current Balance:", token.balanceOf(recipient));
        console.log("");

        vm.startBroadcast();

        console.log("Minting tokens...");
        token.mint(recipient, amount);

        vm.stopBroadcast();

        console.log("=== Minting Results ===");
        console.log("New Recipient Balance:", token.balanceOf(recipient));
        console.log("Mint successful!");
    }
}
