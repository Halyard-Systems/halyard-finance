// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "lib/forge-std/src/Test.sol";
import {DepositManager} from "../src/DepositManager.sol";
import {IStargateRouter} from "../src/interfaces/IStargateRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockUSDC {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint8 public decimals = 6;
    string public name = "USD Coin";
    string public symbol = "USDC";

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        require(balanceOf[from] >= amount, "USDC transfer failed");
        require(allowance[from][msg.sender] >= amount, "USDC transfer failed");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract MockUSDT {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint8 public decimals = 6;
    string public name = "Tether USD";
    string public symbol = "USDT";

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        require(balanceOf[from] >= amount, "USDT transfer failed");
        require(allowance[from][msg.sender] >= amount, "USDT transfer failed");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract DepositManagerTest is Test {
    DepositManager public depositManager;
    MockUSDC public mockUSDC;
    MockUSDT public mockUSDT;

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
        mockUSDC = new MockUSDC();
        mockUSDT = new MockUSDT();

        // Mock Stargate router address and pool ID for testing
        uint256 mockPoolId = 1;
        depositManager = new DepositManager(mockStargateRouter, mockPoolId);

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

    function test_InitialState() public view {
        assertEq(depositManager.RAY(), RAY);
        assertEq(depositManager.baseRate(), 0.1e27); // 10%
        assertEq(depositManager.slope1(), 0.5e27); // 50%
        assertEq(depositManager.slope2(), 5.0e27); // 500%
        assertEq(depositManager.kink(), 0.8e18); // 80%
        assertEq(depositManager.reserveFactor(), 0.1e27); // 10%
        assertEq(address(depositManager.stargateRouter()), address(0x123));
        assertEq(depositManager.poolId(), 1);

        // Check that tokens are initialized
        bytes32[] memory supportedTokens = depositManager.getSupportedTokens();
        assertEq(supportedTokens.length, 3);
        assertEq(supportedTokens[0], ETH_TOKEN_ID);
        assertEq(supportedTokens[1], USDC_TOKEN_ID);
        assertEq(supportedTokens[2], USDT_TOKEN_ID);

        // Check token configs
        DepositManager.Asset memory ethConfig = depositManager.getAsset(
            ETH_TOKEN_ID
        );
        assertEq(ethConfig.tokenAddress, address(0));
        assertEq(ethConfig.decimals, 18);
        assertTrue(ethConfig.isActive);
        assertEq(ethConfig.liquidityIndex, RAY);
        assertEq(ethConfig.totalDeposits, 0);
        assertEq(ethConfig.totalBorrows, 0);

        DepositManager.Asset memory usdcConfig = depositManager.getAsset(
            USDC_TOKEN_ID
        );
        assertEq(
            usdcConfig.tokenAddress,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
        );
        assertEq(usdcConfig.decimals, 6);
        assertTrue(usdcConfig.isActive);
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

        DepositManager.Asset memory config = depositManager
            .getAsset(USDC_TOKEN_ID);
        assertEq(config.totalDeposits, depositAmount);
    }

    function test_USDTDeposit() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDT_TOKEN_ID, depositAmount);

        assertEq(depositManager.balanceOf(USDT_TOKEN_ID, alice), depositAmount);

        DepositManager.Asset memory config = depositManager
            .getAsset(USDT_TOKEN_ID);
        assertEq(config.totalDeposits, depositAmount);
    }

    function test_DepositZeroAmount() public {
        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, 0);

        assertEq(depositManager.balanceOf(USDC_TOKEN_ID, alice), 0);

        DepositManager.Asset memory config = depositManager
            .getAsset(USDC_TOKEN_ID);
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

    function test_MultipleDeposits() public {
        uint256 aliceDeposit = 1000 * USDC_DECIMALS;
        uint256 bobDeposit = 500 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, aliceDeposit);

        vm.prank(bob);
        depositManager.deposit(USDC_TOKEN_ID, bobDeposit);

        assertEq(depositManager.balanceOf(USDC_TOKEN_ID, alice), aliceDeposit);
        assertEq(depositManager.balanceOf(USDC_TOKEN_ID, bob), bobDeposit);

        DepositManager.Asset memory config = depositManager
            .getAsset(USDC_TOKEN_ID);
        assertEq(config.totalDeposits, aliceDeposit + bobDeposit);
    }

    function test_ETHWithdraw() public {
        uint256 depositAmount = 1 ether;
        uint256 withdrawAmount = 0.3 ether;
        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        depositManager.deposit{value: depositAmount}(
            ETH_TOKEN_ID,
            depositAmount
        );

        vm.prank(alice);
        depositManager.withdraw(ETH_TOKEN_ID, withdrawAmount);

        assertEq(
            depositManager.balanceOf(ETH_TOKEN_ID, alice),
            depositAmount - withdrawAmount
        );
        assertEq(
            alice.balance,
            aliceBalanceBefore - depositAmount + withdrawAmount
        );

        DepositManager.Asset memory config = depositManager
            .getAsset(ETH_TOKEN_ID);
        assertEq(config.totalDeposits, depositAmount - withdrawAmount);
    }

    function test_USDCWithdraw() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;
        uint256 withdrawAmount = 300 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);

        vm.prank(alice);
        depositManager.withdraw(USDC_TOKEN_ID, withdrawAmount);

        assertEq(
            depositManager.balanceOf(USDC_TOKEN_ID, alice),
            depositAmount - withdrawAmount
        );

        DepositManager.Asset memory config = depositManager
            .getAsset(USDC_TOKEN_ID);
        assertEq(config.totalDeposits, depositAmount - withdrawAmount);
    }

    function test_WithdrawZeroAmount() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);

        vm.prank(alice);
        depositManager.withdraw(USDC_TOKEN_ID, 0);

        assertEq(depositManager.balanceOf(USDC_TOKEN_ID, alice), depositAmount);

        DepositManager.Asset memory config = depositManager
            .getAsset(USDC_TOKEN_ID);
        assertEq(config.totalDeposits, depositAmount);
    }

    function test_WithdrawMoreThanBalance() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;
        uint256 withdrawAmount = 1500 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);

        vm.prank(alice);
        vm.expectRevert();
        depositManager.withdraw(USDC_TOKEN_ID, withdrawAmount);
    }

    function test_WithdrawFromZeroBalance() public {
        vm.prank(alice);
        vm.expectRevert();
        depositManager.withdraw(USDC_TOKEN_ID, 100 * USDC_DECIMALS);
    }

    function test_WithdrawExactBalance() public {
        uint256 depositAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, depositAmount);

        vm.prank(alice);
        depositManager.withdraw(USDC_TOKEN_ID, depositAmount);

        assertEq(depositManager.balanceOf(USDC_TOKEN_ID, alice), 0);

        DepositManager.Asset memory config = depositManager
            .getAsset(USDC_TOKEN_ID);
        assertEq(config.totalDeposits, 0);
    }

    function test_ETHBorrow() public {
        uint256 borrowAmount = 1 ether;
        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        depositManager.borrow(ETH_TOKEN_ID, borrowAmount);

        assertEq(alice.balance, aliceBalanceBefore + borrowAmount);

        DepositManager.Asset memory config = depositManager
            .getAsset(ETH_TOKEN_ID);
        assertEq(config.totalBorrows, borrowAmount);
    }

    function test_USDCBorrow() public {
        uint256 borrowAmount = 1000 * USDC_DECIMALS;

        vm.prank(alice);
        depositManager.borrow(USDC_TOKEN_ID, borrowAmount);

        assertEq(
            mockUSDC.balanceOf(alice),
            10000 * USDC_DECIMALS + borrowAmount
        );

        DepositManager.Asset memory config = depositManager
            .getAsset(USDC_TOKEN_ID);
        assertEq(config.totalBorrows, borrowAmount);
    }

    function test_MultipleTokenOperations() public {
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
        DepositManager.Asset memory ethConfig = depositManager
            .getAsset(ETH_TOKEN_ID);
        DepositManager.Asset memory usdcConfig = depositManager
            .getAsset(USDC_TOKEN_ID);
        DepositManager.Asset memory usdtConfig = depositManager
            .getAsset(USDT_TOKEN_ID);

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

    function test_AddNewToken() public {
        string memory symbol = "DAI";
        address daiAddress = address(
            0x6B175474E89094C44Da98b954EedeAC495271d0F
        );
        uint8 decimals = 18;

        vm.prank(alice);
        depositManager.addToken(symbol, daiAddress, decimals);

        bytes32 daiTokenId = keccak256(abi.encodePacked(symbol));
        DepositManager.Asset memory config = depositManager
            .getAsset(daiTokenId);

        assertEq(config.tokenAddress, daiAddress);
        assertEq(config.decimals, decimals);
        assertTrue(config.isActive);
    }

    function test_SetTokenActive() public {
        vm.prank(alice);
        depositManager.setTokenActive(USDC_TOKEN_ID, false);

        DepositManager.Asset memory config = depositManager
            .getAsset(USDC_TOKEN_ID);
        assertFalse(config.isActive);

        vm.prank(alice);
        vm.expectRevert();
        depositManager.deposit(USDC_TOKEN_ID, 1000 * USDC_DECIMALS);
    }

    // function test_InterestAccrual() public {
    //     uint256 depositAmount = 1000 * USDC_DECIMALS;

    //     vm.prank(alice);
    //     depositManager.deposit(USDC_TOKEN_ID, depositAmount);

    //     // Create borrows organically to create utilization
    //     vm.prank(charlie);
    //     depositManager.borrow(USDC_TOKEN_ID, 500 * USDC_DECIMALS); // 50% utilization

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
    //     DepositManager.Asset memory config = depositManager.getAsset(USDC_TOKEN_ID);
    //     assertGt(
    //         config.liquidityIndex,
    //         RAY,
    //         "Liquidity index should have increased"
    //     );
    // }
}
