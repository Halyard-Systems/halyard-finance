// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DepositManager} from "../../../src/DepositManager.sol";
import {IStargateRouter} from "../../../src/interfaces/IStargateRouter.sol";
import {MockERC20} from "../../../test/mocks/MockERC20.sol";

contract DepositTest is Test {
    DepositManager public depositManager;
    MockERC20 public mockUSDC;
    MockERC20 public mockUSDT;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public mockStargateRouter = address(0x123);

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

        // Set up the test contract as the BorrowManager for testing
        depositManager.setBorrowManager(address(this));

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
        vm.mockCall(
            mockStargateRouter,
            abi.encodeWithSelector(IStargateRouter.addLiquidity.selector),
            abi.encode()
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

    function test_ETHDeposit() public {
        uint256 depositAmount = 1 ether;
        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        depositManager.deposit{value: depositAmount}(
            ETH_TOKEN_ID,
            depositAmount
        );

        assertEq(depositManager.balanceOf(ETH_TOKEN_ID, alice), depositAmount);
        assertEq(alice.balance, aliceBalanceBefore - depositAmount);

        DepositManager.Asset memory config = depositManager.getAsset(
            ETH_TOKEN_ID
        );
        assertEq(config.totalDeposits, depositAmount);
    }

    function test_USDCDeposit() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);

        assertEq(depositManager.balanceOf(USDC_TOKEN_ID, alice), depositAmount);

        DepositManager.Asset memory config = depositManager.getAsset(
            USDC_TOKEN_ID
        );
        assertEq(config.totalDeposits, depositAmount);
    }

    function test_USDTDeposit() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDT_TOKEN_ID, depositAmount);

        assertEq(depositManager.balanceOf(USDT_TOKEN_ID, alice), depositAmount);

        DepositManager.Asset memory config = depositManager.getAsset(
            USDT_TOKEN_ID
        );
        assertEq(config.totalDeposits, depositAmount);
    }

    function test_DepositZeroAmount() public {
        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, 0);

        assertEq(depositManager.balanceOf(USDC_TOKEN_ID, alice), 0);

        DepositManager.Asset memory config = depositManager.getAsset(
            USDC_TOKEN_ID
        );
        assertEq(config.totalDeposits, 0);
    }

    function test_DepositInsufficientAllowance() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        // Revoke allowance
        vm.prank(alice);
        mockUSDC.approve(address(depositManager), 0);

        vm.prank(alice);
        vm.expectRevert();
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);
    }

    function test_DepositInsufficientBalance() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        // Set balance to 0 by overriding the balance
        vm.store(
            address(mockUSDC),
            keccak256(abi.encode(alice, uint256(0))), // balanceOf[alice]
            bytes32(0)
        );

        vm.prank(alice);
        vm.expectRevert();
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);
    }

    function test_ETHDepositInsufficientValue() public {
        uint256 depositAmount = 1 ether;

        vm.prank(alice);
        vm.expectRevert("ETH amount mismatch");
        depositManager.deposit{value: 0.5 ether}(ETH_TOKEN_ID, depositAmount);
    }

    function test_ERC20DepositWithETHValue() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        vm.expectRevert("ETH not accepted for ERC20 deposits");
        depositManager.deposit{value: 1 ether}(USDC_TOKEN_ID, depositAmount);
    }

    function test_MultipleUserDeposits() public {
        uint256 aliceDeposit = 1000 * USDC_DECIMALS;
        uint256 bobDeposit = 500 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, aliceDeposit);

        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, bobDeposit);

        assertEq(depositManager.balanceOf(USDC_TOKEN_ID, alice), aliceDeposit);
        assertEq(depositManager.balanceOf(USDC_TOKEN_ID, bob), bobDeposit);

        DepositManager.Asset memory config = depositManager.getAsset(
            USDC_TOKEN_ID
        );
        assertEq(config.totalDeposits, aliceDeposit + bobDeposit);
    }

    function test_MultipleTokenDeposits() public {
        // Deposit different tokens
        vm.prank(alice);
        depositManager.deposit{value: 1 ether}(ETH_TOKEN_ID, 1 ether);

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, 1000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit(USDT_TOKEN_ID, 1000 * USDC_DECIMALS);

        // Check balances
        assertEq(depositManager.balanceOf(ETH_TOKEN_ID, alice), 1 ether);
        assertEq(
            depositManager.balanceOf(USDC_TOKEN_ID, alice),
            1000 * USDC_DECIMALS
        );
        assertEq(
            depositManager.balanceOf(USDT_TOKEN_ID, alice),
            1000 * USDC_DECIMALS
        );

        // Check total deposits for each token
        DepositManager.Asset memory ethConfig = depositManager.getAsset(
            ETH_TOKEN_ID
        );
        DepositManager.Asset memory usdcConfig = depositManager.getAsset(
            USDC_TOKEN_ID
        );
        DepositManager.Asset memory usdtConfig = depositManager.getAsset(
            USDT_TOKEN_ID
        );

        assertEq(ethConfig.totalDeposits, 1 ether);
        assertEq(usdcConfig.totalDeposits, 1000 * USDC_DECIMALS);
        assertEq(usdtConfig.totalDeposits, 1000 * USDC_DECIMALS);
    }

    function test_TokenNotSupported() public {
        bytes32 invalidTokenId = keccak256(abi.encodePacked("INVALID"));

        vm.prank(alice);
        vm.expectRevert();
        depositManager.deposit(invalidTokenId, 1000 * USDC_DECIMALS);
    }
}
