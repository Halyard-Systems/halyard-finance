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

    function test_BorrowManagerInitialization() public view {
        // Check BorrowManager initial state
        assertEq(address(borrowManager.depositMgr()), address(depositManager));
        assertEq(address(borrowManager.pyth()), mockPyth);
        assertEq(borrowManager.owner(), address(this));
        assertEq(borrowManager.getLtv(), 0.5e18); // 50% LTV

        // Check initial borrow indices are 0
        assertEq(borrowManager.borrowIndex(ETH_TOKEN_ID), 0);
        assertEq(borrowManager.borrowIndex(USDC_TOKEN_ID), 0);
        assertEq(borrowManager.borrowIndex(USDT_TOKEN_ID), 0);

        // Check initial scaled borrows are 0
        assertEq(borrowManager.totalBorrowScaled(ETH_TOKEN_ID), 0);
        assertEq(borrowManager.totalBorrowScaled(USDC_TOKEN_ID), 0);
        assertEq(borrowManager.totalBorrowScaled(USDT_TOKEN_ID), 0);

        assertEq(borrowManager.userBorrowScaled(ETH_TOKEN_ID, alice), 0);
        assertEq(borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice), 0);
        assertEq(borrowManager.userBorrowScaled(USDT_TOKEN_ID, alice), 0);
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

    function test_SetLtv() public {
        // Test setting valid LTV
        borrowManager.setLtv(0.7e18); // 70%
        assertEq(borrowManager.getLtv(), 0.7e18);

        // Test setting to 100%
        borrowManager.setLtv(1e18);
        assertEq(borrowManager.getLtv(), 1e18);

        // Test setting to 0%
        borrowManager.setLtv(0);
        assertEq(borrowManager.getLtv(), 0);
    }

    function test_SetLtv_OnlyOwner() public {
        // Test that non-owner cannot set LTV
        vm.prank(alice);
        vm.expectRevert("Not owner");
        borrowManager.setLtv(0.8e18);

        // Verify LTV hasn't changed
        assertEq(borrowManager.getLtv(), 0.5e18);
    }

    function test_SetLtv_InvalidValue() public {
        // Test that LTV > 100% is rejected
        vm.expectRevert("LTV must be <= 100%");
        borrowManager.setLtv(1.5e18); // 150%

        // Verify LTV hasn't changed
        assertEq(borrowManager.getLtv(), 0.5e18);
    }

    function test_GetLtv() public view {
        // Test getLtv returns correct value
        assertEq(borrowManager.getLtv(), 0.5e18);
    }

    function test_RepayETH() public {
        uint256 borrowAmount = 0.1 ether;

        // Setup: Bob deposits ETH liquidity, Alice deposits USDC collateral and borrows ETH
        vm.prank(bob);
        depositManager.deposit{value: 2 ether}(ETH_TOKEN_ID, 2 ether);

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, 3 * USDC_DECIMALS);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        vm.prank(alice);
        borrowManager.borrow(ETH_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        uint256 aliceBalanceAfterBorrow = alice.balance;
        uint256 contractBalanceBeforeRepay = address(depositManager).balance;

        // Alice repays the ETH
        vm.prank(alice);
        borrowManager.repay{value: borrowAmount}(ETH_TOKEN_ID, borrowAmount);

        // Check balances
        assertEq(alice.balance, aliceBalanceAfterBorrow - borrowAmount);
        assertEq(address(depositManager).balance, contractBalanceBeforeRepay + borrowAmount);

        // Check borrow state is cleared
        assertEq(borrowManager.userBorrowScaled(ETH_TOKEN_ID, alice), 0);

        DepositManager.Asset memory config = depositManager.getAsset(ETH_TOKEN_ID);
        assertEq(config.totalBorrows, 0);
    }

    function test_RepayUSDC() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;

        // Setup: Bob deposits USDC liquidity, Alice deposits ETH collateral and borrows USDC
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        uint256 aliceBalanceAfterBorrow = mockUSDC.balanceOf(alice);
        uint256 contractBalanceBeforeRepay = mockUSDC.balanceOf(address(depositManager));

        // Alice approves and repays the USDC
        vm.prank(alice);
        mockUSDC.approve(address(depositManager), borrowAmount);

        vm.prank(alice);
        borrowManager.repay(USDC_TOKEN_ID, borrowAmount);

        // Check balances
        assertEq(mockUSDC.balanceOf(alice), aliceBalanceAfterBorrow - borrowAmount);
        assertEq(mockUSDC.balanceOf(address(depositManager)), contractBalanceBeforeRepay + borrowAmount);

        // Check borrow state is cleared
        assertEq(borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice), 0);

        DepositManager.Asset memory config = depositManager.getAsset(USDC_TOKEN_ID);
        assertEq(config.totalBorrows, 0);
    }

    function test_PartialRepay() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;
        uint256 repayAmount = USDC_DECIMALS / 2; // Partial repay (0.5 USDC)

        // Setup borrow
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        uint256 scaledBorrowAfterBorrow = borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice);

        // Partial repay
        vm.prank(alice);
        mockUSDC.approve(address(depositManager), repayAmount);

        vm.prank(alice);
        borrowManager.repay(USDC_TOKEN_ID, repayAmount);

        // Check that scaled borrow is reduced but not zero
        uint256 scaledBorrowAfterRepay = borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice);
        assertGt(scaledBorrowAfterRepay, 0);
        assertLt(scaledBorrowAfterRepay, scaledBorrowAfterBorrow);

        DepositManager.Asset memory config = depositManager.getAsset(USDC_TOKEN_ID);
        assertEq(config.totalBorrows, borrowAmount - repayAmount);
    }

    function test_RepayExceedsBorrow() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;
        uint256 repayAmount = 2 * USDC_DECIMALS; // Try to repay more than borrowed

        // Setup borrow
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        // Try to repay more than borrowed - should fail
        vm.prank(alice);
        mockUSDC.approve(address(depositManager), repayAmount);

        vm.prank(alice);
        vm.expectRevert("Repay exceeds borrow");
        borrowManager.repay(USDC_TOKEN_ID, repayAmount);
    }

    function test_BorrowInsufficientCollateral() public {
        uint256 borrowAmount = 1000 * USDC_DECIMALS; // Very large borrow amount

        // Setup liquidity
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        // Alice deposits small collateral
        vm.prank(alice);
        depositManager.deposit{value: 0.1 ether}(ETH_TOKEN_ID, 0.1 ether); // Very small collateral

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        // Should fail due to insufficient collateral
        vm.prank(alice);
        vm.expectRevert("Insufficient collateral");
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);
    }

    function test_BorrowNoCollateral() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;

        // Setup liquidity but Alice has no collateral
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        // Should fail due to no collateral
        vm.prank(alice);
        vm.expectRevert("No collateral");
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);
    }

    function test_BorrowMismatchedPriceIds() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;

        // Setup
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](2); // Wrong number of price IDs
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));

        // Should fail due to mismatched tokens/prices
        vm.prank(alice);
        vm.expectRevert("Mismatched tokens/prices");
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);
    }

    function test_BorrowNegativePrice() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;

        // Setup
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        // Mock negative price for one of the tokens
        bytes memory negativePriceData = abi.encode(
            int64(-100000000), // Negative price
            uint64(0),
            int32(-8),
            uint256(block.timestamp)
        );
        vm.mockCall(
            mockPyth, abi.encodeWithSignature("getPriceUnsafe(bytes32)", bytes32(uint256(1))), negativePriceData
        );

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        // Should fail due to negative price
        vm.prank(alice);
        vm.expectRevert("Negative price");
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);
    }

    function test_BorrowUSDTToken() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS; // USDT has same decimals as USDC

        // Setup: Bob deposits USDT liquidity, Alice deposits ETH collateral
        vm.prank(bob);
        depositManager.deposit(USDT_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        uint256 aliceBalanceBefore = mockUSDT.balanceOf(alice);

        vm.prank(alice);
        borrowManager.borrow(USDT_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        assertEq(mockUSDT.balanceOf(alice), aliceBalanceBefore + borrowAmount);

        DepositManager.Asset memory config = depositManager.getAsset(USDT_TOKEN_ID);
        assertEq(config.totalBorrows, borrowAmount);
    }

    function test_MultipleBorrowsSameUser() public {
        // Alice borrows from multiple tokens

        // Setup liquidity
        vm.prank(bob);
        depositManager.deposit{value: 10 ether}(ETH_TOKEN_ID, 10 ether);
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 5000 * USDC_DECIMALS);
        vm.prank(bob);
        depositManager.deposit(USDT_TOKEN_ID, 5000 * USDC_DECIMALS);

        // Alice deposits large collateral - need more for multiple borrows
        vm.prank(alice);
        depositManager.deposit{value: 100 ether}(ETH_TOKEN_ID, 100 ether); // Increased collateral

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        // Borrow smaller amounts to stay within LTV
        vm.prank(alice);
        borrowManager.borrow(
            USDC_TOKEN_ID,
            10 * USDC_DECIMALS, // Reduced from 100
            emptyPythData,
            priceIds
        );

        // Borrow USDT
        vm.prank(alice);
        borrowManager.borrow(
            USDT_TOKEN_ID,
            5 * USDC_DECIMALS, // Reduced from 50
            emptyPythData,
            priceIds
        );

        // Check both borrows are recorded
        assertGt(borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice), 0);
        assertGt(borrowManager.userBorrowScaled(USDT_TOKEN_ID, alice), 0);

        DepositManager.Asset memory usdcConfig = depositManager.getAsset(USDC_TOKEN_ID);
        assertEq(usdcConfig.totalBorrows, 10 * USDC_DECIMALS);

        DepositManager.Asset memory usdtConfig = depositManager.getAsset(USDT_TOKEN_ID);
        assertEq(usdtConfig.totalBorrows, 5 * USDC_DECIMALS);
    }

    function test_BorrowEvent() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;

        // Setup
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        // Expected collateral value: 5 ETH * $1000 = $5,000,000 (normalized to 18 decimals and divided by 1e8)
        uint256 expectedCollateralValue = (5 ether * 100000000) / 1e8; // = 5 * 10^18

        // Expect the Borrowed event
        vm.expectEmit(true, true, false, true);
        emit BorrowManager.Borrowed(USDC_TOKEN_ID, alice, borrowAmount, expectedCollateralValue);

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);
    }

    function test_RepayEvent() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;

        // Setup borrow first
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        // Now test repay event
        vm.prank(alice);
        mockUSDC.approve(address(depositManager), borrowAmount);

        // Expect the Repaid event
        vm.expectEmit(true, true, false, true);
        emit BorrowManager.Repaid(USDC_TOKEN_ID, alice, borrowAmount);

        vm.prank(alice);
        borrowManager.repay(USDC_TOKEN_ID, borrowAmount);
    }

    function test_BorrowIndexInitialization() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;

        // Setup
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        // Check initial borrow index is 0
        assertEq(borrowManager.borrowIndex(USDC_TOKEN_ID), 0);

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        // After first borrow, index should be initialized to RAY
        assertEq(borrowManager.borrowIndex(USDC_TOKEN_ID), RAY);
    }

    function test_BorrowIndexAccrual() public {
        uint256 borrowAmount = 20 * USDC_DECIMALS; // Further reduced to stay within 50% LTV

        // Setup with higher utilization for significant interest
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 200 * USDC_DECIMALS); // 200 USDC liquidity

        vm.prank(alice);
        depositManager.deposit{value: 50 ether}(ETH_TOKEN_ID, 50 ether); // ETH collateral

        // Also add USDC collateral to increase total collateral value
        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, 1000 * USDC_DECIMALS); // USDC collateral

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        uint256 initialBorrowIndex = borrowManager.borrowIndex(USDC_TOKEN_ID);
        assertEq(initialBorrowIndex, RAY);

        // Advance time by 1 year
        vm.warp(block.timestamp + YEAR);

        // Trigger borrow index update by making another small borrow
        vm.prank(alice);
        borrowManager.borrow(
            USDC_TOKEN_ID,
            USDC_DECIMALS / 10, // 0.1 USDC - very small amount
            emptyPythData,
            priceIds
        );

        uint256 finalBorrowIndex = borrowManager.borrowIndex(USDC_TOKEN_ID);

        // Borrow index should have increased due to interest accrual
        assertGt(finalBorrowIndex, initialBorrowIndex, "Borrow index should increase over time");

        console.log("Initial borrow index:", initialBorrowIndex);
        console.log("Final borrow index:", finalBorrowIndex);
        console.log("Interest accrued factor:", (finalBorrowIndex * 1e18) / initialBorrowIndex);
    }

    function test_InterestAccrualOnRepay() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;

        // Setup
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        uint256 initialBorrowIndex = borrowManager.borrowIndex(USDC_TOKEN_ID);
        uint256 initialScaledBorrow = borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice);

        // Advance time
        vm.warp(block.timestamp + (YEAR / 4)); // 3 months

        // Calculate expected amount owed (should be more than initial borrow due to interest)
        uint256 expectedAmountOwed = (initialScaledBorrow * borrowManager.borrowIndex(USDC_TOKEN_ID)) / RAY;

        // Alice needs to approve more than the original borrow amount to cover interest
        vm.prank(alice);
        mockUSDC.approve(address(depositManager), expectedAmountOwed);

        // Repay should work with the accrued amount
        vm.prank(alice);
        borrowManager.repay(USDC_TOKEN_ID, borrowAmount); // Repay original amount

        // Check that scaled borrow is reduced appropriately
        uint256 finalScaledBorrow = borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice);
        assertLt(finalScaledBorrow, initialScaledBorrow);
    }

    function test_ScaledBorrowCalculation() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;

        // Setup
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        uint256 borrowIndex = borrowManager.borrowIndex(USDC_TOKEN_ID);
        uint256 scaledBorrow = borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice);

        // Verify that scaled borrow * index = actual borrow amount
        uint256 actualBorrowAmount = (scaledBorrow * borrowIndex) / RAY;
        assertEq(actualBorrowAmount, borrowAmount, "Scaled borrow calculation should be correct");

        // Verify expected scaled amount
        uint256 expectedScaled = (borrowAmount * RAY) / borrowIndex;
        assertEq(scaledBorrow, expectedScaled, "Scaled borrow should match expected calculation");
    }

    function test_ReceiveETH() public {
        uint256 sendAmount = 1 ether;
        uint256 initialBalance = address(borrowManager).balance;

        // Send ETH to BorrowManager via receive function
        (bool success,) = address(borrowManager).call{value: sendAmount}("");
        assertTrue(success, "ETH transfer should succeed");

        // Check that BorrowManager received the ETH
        assertEq(address(borrowManager).balance, initialBalance + sendAmount);
    }

    function test_ZeroBorrowAmount() public {
        // Setup
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        // Try to borrow 0 amount
        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, 0, emptyPythData, priceIds);

        // Should succeed but with no effect
        assertEq(borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice), 0);

        DepositManager.Asset memory config = depositManager.getAsset(USDC_TOKEN_ID);
        assertEq(config.totalBorrows, 0);
    }

    function test_ZeroRepayAmount() public {
        uint256 borrowAmount = 1 * USDC_DECIMALS;

        // Setup borrow first
        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, 2000 * USDC_DECIMALS);

        vm.prank(alice);
        depositManager.deposit{value: 5 ether}(ETH_TOKEN_ID, 5 ether);

        bytes[] memory emptyPythData = new bytes[](0);
        bytes32[] memory priceIds = new bytes32[](3);
        priceIds[0] = bytes32(uint256(1));
        priceIds[1] = bytes32(uint256(2));
        priceIds[2] = bytes32(uint256(3));

        vm.prank(alice);
        borrowManager.borrow(USDC_TOKEN_ID, borrowAmount, emptyPythData, priceIds);

        uint256 initialScaledBorrow = borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice);

        // Try to repay 0 amount
        vm.prank(alice);
        borrowManager.repay(USDC_TOKEN_ID, 0);

        // Should succeed but with no effect
        assertEq(borrowManager.userBorrowScaled(USDC_TOKEN_ID, alice), initialScaledBorrow);
    }
}
