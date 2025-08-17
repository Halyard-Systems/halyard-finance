// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "lib/forge-std/src/Test.sol";

import {BorrowManager} from "../../src/BorrowManager.sol";
import {DepositManager} from "../../src/DepositManager.sol";
import {IStargateRouter} from "../../src/interfaces/IStargateRouter.sol";
import {MockERC20} from "../../test/mocks/MockERC20.sol";

contract BaseTest is Test {
    BorrowManager public borrowManager;
    DepositManager public depositManager;
    MockERC20 public mockUSDC;
    MockERC20 public mockUSDT;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public mockStargateRouter = address(0x123);
    address public mockPyth = address(0x456);

    uint256 public constant RAY = 1e27;
    uint256 public constant YEAR = 365 days;
    uint256 public constant USDC_DECIMALS = 1e6;
    uint256 public constant ETH_DECIMALS = 1e18;

    // Token IDs
    bytes32 public constant ETH_TOKEN_ID = keccak256(abi.encodePacked("ETH"));
    bytes32 public constant USDC_TOKEN_ID = keccak256(abi.encodePacked("USDC"));
    bytes32 public constant USDT_TOKEN_ID = keccak256(abi.encodePacked("USDT"));

    function setUp() public virtual {
        // Deploy mock tokens
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        mockUSDT = new MockERC20("Tether USD", "USDT", 6);

        // Mock Stargate router address and pool ID for testing
        uint256 mockPoolId = 1;
        depositManager = new DepositManager(mockStargateRouter, mockPoolId);

        // Deploy BorrowManager
        borrowManager = new BorrowManager(address(depositManager), mockPyth, 0.5e18);

        // Set up the test contract as the BorrowManager for testing
        depositManager.setBorrowManager(address(borrowManager));

        // Initialize tokens with default interest rate parameters
        depositManager.addToken(
            "ETH",
            address(0), // ETH is represented as address(0)
            18,
            0.01e27, // 1% base rate
            0.04e27, // 4% slope1
            0.08e27, // 8% slope2
            0.8e18, // 80% utilization kink
            0.1e27 // 10% reserve factor
        );

        depositManager.addToken(
            "USDC",
            address(mockUSDC), // Use mock USDC address
            6,
            0.02e27, // 2% base rate
            0.06e27, // 6% slope1
            0.12e27, // 12% slope2
            0.8e18, // 80% utilization kink
            0.1e27 // 10% reserve factor
        );

        depositManager.addToken(
            "USDT",
            address(mockUSDT), // Use mock USDT address
            6,
            0.015e27, // 1.5% base rate
            0.05e27, // 5% slope1
            0.1e27, // 10% slope2
            0.8e18, // 80% utilization kink
            0.1e27 // 10% reserve factor
        );

        // Mock the Stargate router addLiquidity call to always succeed
        vm.mockCall(mockStargateRouter, abi.encodeWithSelector(IStargateRouter.addLiquidity.selector), abi.encode());

        // Mock Pyth oracle calls
        // Mock getUpdateFee to return 0 (no fee for empty data)
        vm.mockCall(mockPyth, abi.encodeWithSignature("getUpdateFee(bytes[])", new bytes[](0)), abi.encode(uint256(0)));

        // Mock updatePriceFeeds to succeed
        vm.mockCall(mockPyth, abi.encodeWithSignature("updatePriceFeeds(bytes[])"), abi.encode());

        // Mock getPriceUnsafe for each price ID to return a valid PythStructs.Price
        // Return the struct fields directly as abi.encode does

        // ETH price: $1000
        bytes memory mockEthPriceData = abi.encode(
            int64(100000000000), // $1000 * 1e8 (Pyth uses 8 decimals)
            uint64(0), // confidence
            int32(-8), // exponent
            uint256(block.timestamp) // publish time
        );

        // USDC price: $1
        bytes memory mockUsdcPriceData = abi.encode(
            int64(100000000), // $1 * 1e8 (Pyth uses 8 decimals)
            uint64(0), // confidence
            int32(-8), // exponent
            uint256(block.timestamp) // publish time
        );

        // USDT price: $1
        bytes memory mockUsdtPriceData = abi.encode(
            int64(100000000), // $1 * 1e8 (Pyth uses 8 decimals)
            uint64(0), // confidence
            int32(-8), // exponent
            uint256(block.timestamp) // publish time
        );

        // Map price IDs to their respective price data
        // Assuming price ID 1 = ETH, 2 = USDC, 3 = USDT
        vm.mockCall(mockPyth, abi.encodeWithSignature("getPriceUnsafe(bytes32)", bytes32(uint256(1))), mockEthPriceData);
        vm.mockCall(
            mockPyth, abi.encodeWithSignature("getPriceUnsafe(bytes32)", bytes32(uint256(2))), mockUsdcPriceData
        );
        vm.mockCall(
            mockPyth, abi.encodeWithSignature("getPriceUnsafe(bytes32)", bytes32(uint256(3))), mockUsdtPriceData
        );

        // Give users some tokens
        mockUSDC.mint(alice, 10000 * USDC_DECIMALS);
        mockUSDC.mint(bob, 10000 * USDC_DECIMALS);
        mockUSDC.mint(charlie, 10000 * USDC_DECIMALS);

        mockUSDT.mint(alice, 10000 * USDC_DECIMALS);
        mockUSDT.mint(bob, 10000 * USDC_DECIMALS);
        mockUSDT.mint(charlie, 10000 * USDC_DECIMALS);

        // Give users some ETH
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);

        // Approve DepositManager to spend tokens
        vm.prank(alice);
        mockUSDC.approve(address(depositManager), type(uint256).max);
        vm.prank(bob);
        mockUSDC.approve(address(depositManager), type(uint256).max);
        vm.prank(charlie);
        mockUSDC.approve(address(depositManager), type(uint256).max);

        vm.prank(alice);
        mockUSDT.approve(address(depositManager), type(uint256).max);
        vm.prank(bob);
        mockUSDT.approve(address(depositManager), type(uint256).max);
        vm.prank(charlie);
        mockUSDT.approve(address(depositManager), type(uint256).max);
    }
}
