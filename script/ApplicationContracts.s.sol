// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {DepositManager} from "../src/DepositManager.sol";
import {BorrowManager} from "../src/BorrowManager.sol";
import {MockPyth} from "../node_modules/@pythnetwork/pyth-sdk-solidity/MockPyth.sol";

contract ApplicationContractsScript is Script {
    DepositManager public depositManager;

    address USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    //address STARGATE_ROUTER_SEPOLIA_TESTNET =
    //    0x2836045A50744FB50D3d04a9C8D18aD7B5012102;

    address STARGATE_ROUTER_MAINNET =
        0x8731d54E9D02c286767d56ac03e8037C07e01e98;
    //address STARGATE_USDC_POOL_MAINNET =
    //    0xc026395860Db2d07ee33e05fE50ed7bD583189C7;

    uint256 USDC_POOL_ID_SEPOLIA_TESTNET = 1;

    function setUp() public {}

    function run() public {
        // Get constructor parameters from environment or set defaults
        address stargateRouter = vm.envOr(
            "STARGATE_ROUTER",
            STARGATE_ROUTER_MAINNET
        );
        uint256 poolId = vm.envOr("POOL_ID", uint256(1)); // USDC pool ID

        vm.startBroadcast();

        depositManager = new DepositManager(stargateRouter, poolId);

        depositManager.addToken(
            "ETH",
            address(0),
            18,
            0.1e27,
            0.5e27,
            5.0e27,
            0.8e18,
            0.1e27
        );
        console.log("ETH token added to protocol");
        depositManager.addToken(
            "USDC",
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            6,
            0.05e27,
            0.3e27,
            3.0e27,
            0.8e18,
            0.1e27
        );
        console.log("USDC token added to protocol");
        depositManager.addToken(
            "USDT",
            0xdAC17F958D2ee523a2206206994597C13D831ec7,
            6,
            0.05e27,
            0.3e27,
            3.0e27,
            0.8e18,
            0.1e27
        );
        console.log("USDT token added to protocol");

        console.log("DepositManager deployed at:", address(depositManager));
        console.log("Stargate Router:", stargateRouter);
        console.log("Pool ID:", poolId);

        // Deploy MockPyth
        MockPyth mockPyth = new MockPyth(
            // Valid for 3 minutes
            180,
            // Update fee in wei (1000000000000000000 = 1 ETH)
            1000000000000000
        );

        // Optional: pre-set a test feed
        // ETH/USD price id
        bytes32 priceId = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
        uint64 publishTime = uint64(block.timestamp);
        bytes memory updateData = mockPyth.createPriceFeedUpdateData(
            priceId,
            123 * 1e8,
            100,
            -8,
            123 * 1e8,
            100,
            publishTime,
            publishTime - 60
        );
        bytes[] memory updateArray = new bytes[](1);
        updateArray[0] = updateData;

        uint fee = mockPyth.getUpdateFee(updateArray);
        console.log("Pyth fees paid", fee);

        mockPyth.updatePriceFeeds{value: fee}(updateArray);

        console.log("MockPyth deployed at:", address(mockPyth));

        // Deploy BorrowManager
        BorrowManager borrowManager = new BorrowManager(
            address(depositManager),
            address(mockPyth)
        );
        console.log("BorrowManager deployed at:", address(borrowManager));

        depositManager.setBorrowManager(address(borrowManager));
        console.log("BorrowManager set as borrow manager");

        vm.stopBroadcast();
    }
}
