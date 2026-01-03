// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {DepositManager} from "../src/DepositManager.sol";
import "lib/forge-std/src/console.sol";
import "lib/forge-std/src/Script.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract TransferTokensEth is Script {
    // Mainnet USDC and a known whale
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDC_WHALE = 0x64F23F66C82e6B77916ad435f09511d608fD8EEa;

    // Mainnet USDT and a known whale
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant USDT_WHALE = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    // Local contracts will be deployed to these addresses
    address constant BORROW_MANAGER = 0x74ef79CFC735A10436eF9D4808547df0Ce38f788;
    address payable constant DEPOSIT_MANAGER = payable(0x2e590d65Dd357a7565EfB5ffB329F8465F18c494);

    address recipient = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function run() external {
        vm.startBroadcast(USDC_WHALE);

        // The recipient -- replace with one of your anvil accounts!
        uint256 amount = 1_000_000e6; // 1000000 USDC, 6 decimals

        // Transfer USDC
        bool success = IERC20(USDC).transfer(recipient, amount);
        require(success, "USDCTransfer failed");

        vm.stopBroadcast();

        vm.startBroadcast(USDT_WHALE);

        uint256 amountUSDT = 1_000_000e6; // 1000000 USDT, 6 decimals

        // Transfer USDT using low-level call (USDT doesn't return bool) USDT is not a standard ERC20 token
        (bool successUSDT, bytes memory data) = USDT.call(abi.encodeWithSelector(IERC20.transfer.selector, recipient, amountUSDT));
        require(successUSDT && (data.length == 0 || abi.decode(data, (bool))), "USDT Transfer failed");

        console.log("Recipient USDT Balance", IERC20(USDT).balanceOf(recipient));

        vm.stopBroadcast();

        // Deposit USDC in the DepositManager contract
        vm.startBroadcast(recipient);

        console.log("Depositing ETH in the DepositManager contract");

        // Deposit ETH in the DepositManager contract
        bytes32 ETH_TOKEN_ID = keccak256(abi.encodePacked("ETH"));
        DepositManager(DEPOSIT_MANAGER).deposit{value: 10e18}(ETH_TOKEN_ID, 10e18);

        console.log("Deposited 10 ETH in the DepositManager contract");

        // Deposit USDC in the DepositManager contract
        bytes32 USDC_TOKEN_ID = keccak256(abi.encodePacked("USDC"));
        IERC20(USDC).approve(DEPOSIT_MANAGER, 10000e6);
        DepositManager(DEPOSIT_MANAGER).deposit(USDC_TOKEN_ID, 10000e6);

        console.log("Deposited USDC in the DepositManager contract");

        vm.stopBroadcast();
    }
}
