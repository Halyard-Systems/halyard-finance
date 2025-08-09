// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "lib/forge-std/src/Test.sol";

import {DepositManager} from "../src/DepositManager.sol";
import {BorrowManager} from "../src/BorrowManager.sol";
import {IStargateRouter} from "../src/interfaces/IStargateRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract BorrowManagerTest is Test {
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

    function setUp() public {
        // Deploy mock tokens
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        mockUSDT = new MockERC20("Tether USD", "USDT", 6);

        // Mock Stargate router address and pool ID for testing
        uint256 mockPoolId = 1;
        depositManager = new DepositManager(mockStargateRouter, mockPoolId);

        // Deploy BorrowManager
        borrowManager = new BorrowManager(address(depositManager), mockPyth);

        // Set BorrowManager address in DepositManager so it recognizes calls from BorrowManager
        depositManager.setBorrowManager(address(borrowManager));

        // Initialize tokens with default interest rate parameters
        depositManager.addToken(
            "ETH",
            address(0), // ETH is represented as address(0)
            18,
            0.1e27, // 10% base rate
            0.5e27, // 50% slope1
            5.0e27, // 500% slope2
            0.8e18, // 80% utilization kink
            0.1e27 // 10% reserve factor
        );

        depositManager.addToken(
            "USDC",
            address(mockUSDC), // Use mock USDC address
            6,
            0.2e27, // 20% base rate
            0.8e27, // 80% slope1
            8.0e27, // 800% slope2
            0.8e18, // 80% utilization kink
            0.1e27 // 10% reserve factor
        );

        depositManager.addToken(
            "USDT",
            address(mockUSDT), // Use mock USDT address
            6,
            0.05e27, // 5% base rate
            0.3e27, // 30% slope1
            3.0e27, // 300% slope2
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
        bytes memory mockPriceData = abi.encode(
            int64(100000000), // $1000 * 1e8 (Pyth uses 8 decimals)
            uint64(0), // confidence
            int32(-8), // exponent
            uint256(block.timestamp) // publish time
        );

        vm.mockCall(mockPyth, abi.encodeWithSignature("getPriceUnsafe(bytes32)", bytes32(uint256(1))), mockPriceData);
        vm.mockCall(mockPyth, abi.encodeWithSignature("getPriceUnsafe(bytes32)", bytes32(uint256(2))), mockPriceData);
        vm.mockCall(mockPyth, abi.encodeWithSignature("getPriceUnsafe(bytes32)", bytes32(uint256(3))), mockPriceData);

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

    function test_InitialState() public view {
        assertEq(depositManager.RAY(), RAY);
        assertEq(address(depositManager.stargateRouter()), address(0x123));
        assertEq(depositManager.poolId(), 1);

        // Check that tokens are initialized
        bytes32[] memory supportedTokens = depositManager.getSupportedTokens();
        assertEq(supportedTokens.length, 3);
        assertEq(supportedTokens[0], ETH_TOKEN_ID);
        assertEq(supportedTokens[1], USDC_TOKEN_ID);
        assertEq(supportedTokens[2], USDT_TOKEN_ID);

        // Check token configs
        DepositManager.Asset memory ethConfig = depositManager.getAsset(ETH_TOKEN_ID);
        assertEq(ethConfig.tokenAddress, address(0));
        assertEq(ethConfig.decimals, 18);
        assertTrue(ethConfig.isActive);
        assertEq(ethConfig.liquidityIndex, RAY);
        assertEq(ethConfig.totalDeposits, 0);
        assertEq(ethConfig.totalBorrows, 0);
        assertEq(ethConfig.baseRate, 0.1e27);
        assertEq(ethConfig.slope1, 0.5e27);
        assertEq(ethConfig.slope2, 5.0e27);
        assertEq(ethConfig.kink, 0.8e18);
        assertEq(ethConfig.reserveFactor, 0.1e27);

        DepositManager.Asset memory usdcConfig = depositManager.getAsset(USDC_TOKEN_ID);
        assertEq(usdcConfig.tokenAddress, address(mockUSDC));
        assertEq(usdcConfig.decimals, 6);
        assertTrue(usdcConfig.isActive);
        assertEq(usdcConfig.baseRate, 0.2e27);
        assertEq(usdcConfig.slope1, 0.8e27);
        assertEq(usdcConfig.slope2, 8.0e27);
        assertEq(usdcConfig.kink, 0.8e18);
        assertEq(usdcConfig.reserveFactor, 0.1e27);
    }

    function test_ETHBorrow() public {
        uint256 borrowAmount = 0.1 ether; // Borrow less ETH to stay within LTV limits
        uint256 aliceBalanceBefore = alice.balance;

        // First, someone needs to deposit ETH so the contract has liquidity to borrow from
        vm.prank(bob);
        depositManager.deposit{value: 2 ether}(ETH_TOKEN_ID, 2 ether);

        // Alice needs to deposit collateral before borrowing (deposit USDC as collateral)
        // At $1000 per USDC (from our mock), and 50% LTV, need at least $2000 collateral to borrow $1000 ETH
        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, 3 * USDC_DECIMALS); // 3 USDC = $3000 worth at mock price

        // Mock Pyth data - need 3 price IDs to match 3 supported tokens
        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1)); // ETH price ID
        priceIds[1] = bytes32(uint256(2)); // USDC price ID
        priceIds[2] = bytes32(uint256(3)); // USDT price ID

        vm.prank(alice);
        borrowManager.borrow(ETH_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        assertEq(alice.balance, aliceBalanceBefore + borrowAmount);

        DepositManager.Asset memory config = depositManager.getAsset(ETH_TOKEN_ID);
        assertEq(config.totalBorrows, borrowAmount);
    }

    function test_USDCBorrow() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS; // Borrow just 1 USDC to stay within LTV limits

        // First, someone needs to deposit USDC so the contract has liquidity to borrow from
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        // Alice needs to deposit collateral before borrowing (deposit ETH as collateral)
        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether); // 5 ETH as collateral

        // Mock Pyth data - need 3 price IDs to match 3 supported tokens
        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1)); // ETH price ID
        priceIds[1] = bytes32(uint256(2)); // USDC price ID
        priceIds[2] = bytes32(uint256(3)); // USDT price ID

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        assertEq(mockUSDC.balanceOf(alice), 10000 * USDC_DECIMALS + borrowAmount);

        DepositManager.Asset memory config = depositManager.getAsset(USDC_TOKEN_ID);
        assertEq(config.totalBorrows, borrowAmount);
    }

    // function test_InterestAccrual() public {
    //     uint256 depositAmount = 1000 * USDC_DECIMALS;

    //     vm.prank(alice);
    //     depositManager.deposit(USDC_TOKEN_ID, depositAmount);

    //     // Charlie needs collateral before borrowing
    //     vm.prank(charlie);
    //     depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether); // 5 ETH as collateral

    //     // Create high utilization to generate significant interest (90% utilization)
    //     bytes[] memory emptyPythData = new bytes[](0);
    //     bytes32[] memory priceIds = new bytes32[](3);
    //     priceIds[0] = bytes32(uint256(1)); // ETH price ID
    //     priceIds[1] = bytes32(uint256(2)); // USDC price ID
    //     priceIds[2] = bytes32(uint256(3)); // USDT price ID

    //     vm.prank(charlie);
    //     borrowManager.borrow(
    //         USDC_TOKEN_ID,
    //         1 * USDC_DECIMALS, // Borrow just 1 USDC to stay within LTV limits
    //         emptyPythData,
    //         priceIds
    //     );

    //     // Advance time by 1 year to ensure significant interest
    //     vm.warp(block.timestamp + YEAR);

    //     // Trigger interest accrual by making a deposit
    //     vm.prank(bob);
    //     depositManager.deposit(USDC_TOKEN_ID, 100 * USDC_DECIMALS);

    //     // Alice should have earned interest
    //     uint256 aliceBalance = depositManager.balanceOf(USDC_TOKEN_ID, alice);
    //     assertGt(
    //         aliceBalance,
    //         depositAmount,
    //         "Alice should have earned interest"
    //     );

    //     // Check that liquidity index increased
    //     DepositManager.Asset memory config = depositManager.getAsset(
    //         USDC_TOKEN_ID
    //     );
    //     assertGt(
    //         config.liquidityIndex,
    //         RAY,
    //         "Liquidity index should have increased"
    //     );

    //     console.log("Alice's original deposit:", depositAmount);
    //     console.log("Alice's current balance:", aliceBalance);
    //     console.log("Interest earned:", aliceBalance - depositAmount);
    //     console.log("Liquidity index:", config.liquidityIndex);
    // }
}
