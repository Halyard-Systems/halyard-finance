// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "lib/forge-std/src/console.sol";
import "lib/forge-std/src/Script.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract TransferUSDC is Script {
    // Mainnet USDC and a known whale
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDC_WHALE = 0x64F23F66C82e6B77916ad435f09511d608fD8EEa;

    address recipient = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function run() external {
        vm.startBroadcast(USDC_WHALE);

        // The recipient -- replace with one of your anvil accounts!
        uint256 amount = 1_000_000e6; // 1000000 USDC, 6 decimals

        // Transfer USDC
        bool success = IERC20(USDC).transfer(recipient, amount);
        require(success, "Transfer failed");

        // Log balances (optional)
        console.log("Recipient USDC Balance", IERC20(USDC).balanceOf(recipient));
        vm.stopBroadcast();
    }
}
