// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../../BaseTest.t.sol";
import {MessagingFee, Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {IMessageTypes} from "../../../src/interfaces/IMessageTypes.sol";
import {SpokeController} from "../../../src/spoke/SpokeController.sol";

contract SpokeControllerReceiptGasTest is BaseTest {
    bytes32 internal hubSender;
    uint256 internal constant RECEIPT_GAS = 0.01 ether;

    function setUp() public override {
        super.setUp();
        hubSender = bytes32(uint256(uint160(address(hubController))));

        // Provide liquidity so borrow releases can succeed
        mockToken.mint(address(liquidityVault), 1_000_000e18);

        // Set minimum receipt gas requirement
        vm.prank(admin);
        spokeController.setMinReceiptGas(RECEIPT_GAS);

        // Fund the mock endpoint so it can deliver native gas with lzReceive
        vm.deal(address(mockLzEndpoint), 100 ether);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Config
    // ──────────────────────────────────────────────────────────────────────────

    function test_SetMinReceiptGas() public {
        vm.prank(admin);
        spokeController.setMinReceiptGas(0.05 ether);
        assertEq(spokeController.minReceiptGas(), 0.05 ether);
    }

    function test_SetMinReceiptGasOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        spokeController.setMinReceiptGas(0.05 ether);
    }

    function test_RescueETH() public {
        // Send some ETH to spoke controller (simulates refund accumulation)
        vm.deal(address(spokeController), 1 ether);
        uint256 adminBalBefore = admin.balance;

        vm.prank(admin);
        spokeController.rescueETH(admin, 1 ether);

        assertEq(admin.balance, adminBalBefore + 1 ether);
    }

    function test_RescueETHOnlyOwner() public {
        vm.deal(address(spokeController), 1 ether);
        vm.prank(alice);
        vm.expectRevert();
        spokeController.rescueETH(alice, 1 ether);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────────────────

    function _buildBorrowCommand(bytes32 borrowId, address user, uint256 amount)
        internal
        view
        returns (bytes memory)
    {
        bytes memory payload = abi.encode(borrowId, user, user, canonicalToken, amount);
        return abi.encode(uint8(IMessageTypes.MsgType.CMD_RELEASE_BORROW), payload);
    }

    function _buildWithdrawCommand(bytes32 withdrawId, address user, uint256 amount)
        internal
        view
        returns (bytes memory)
    {
        bytes memory payload = abi.encode(withdrawId, user, user, canonicalToken, amount);
        return abi.encode(uint8(IMessageTypes.MsgType.CMD_RELEASE_WITHDRAW), payload);
    }

    function _buildSeizeCommand(bytes32 liqId, address user, address liquidator, uint256 amount)
        internal
        view
        returns (bytes memory)
    {
        bytes memory payload = abi.encode(liqId, user, liquidator, canonicalToken, amount);
        return abi.encode(uint8(IMessageTypes.MsgType.CMD_SEIZE_COLLATERAL), payload);
    }

    /// @dev Deliver a hub command to the spoke with native gas (simulating LZ
    ///      executor using addExecutorLzReceiveOption with nativeValue).
    function _deliverToSpoke(bytes memory message, uint64 nonce, uint256 nativeValue) internal {
        vm.prank(address(mockLzEndpoint));
        spokeController.lzReceive{value: nativeValue}(
            Origin({srcEid: hubEid, sender: hubSender, nonce: nonce}),
            bytes32(uint256(nonce)),
            message,
            address(0),
            bytes("")
        );
    }

    function _depositCollateral(address user, uint256 amount) internal {
        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});
        vm.prank(user);
        // forge-lint: disable-next-line(unsafe-typecast)
        spokeController.depositAndNotify(bytes32("setup_deposit"), canonicalToken, amount, bytes(""), fee);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Borrow release: rejects without gas, succeeds with gas
    // ──────────────────────────────────────────────────────────────────────────

    function test_BorrowReleaseRevertsWithoutReceiptGas() public {
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory message = _buildBorrowCommand(bytes32("borrow1"), alice, 10e18);

        vm.expectRevert(
            abi.encodeWithSelector(SpokeController.InsufficientReceiptGas.selector, RECEIPT_GAS, 0)
        );
        _deliverToSpoke(message, 1, 0);
    }

    function test_BorrowReleaseSucceedsWithReceiptGas() public {
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory message = _buildBorrowCommand(bytes32("borrow1"), alice, 10e18);
        _deliverToSpoke(message, 1, RECEIPT_GAS);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Withdraw release: rejects without gas, succeeds with gas
    // ──────────────────────────────────────────────────────────────────────────

    function test_WithdrawReleaseRevertsWithoutReceiptGas() public {
        _depositCollateral(alice, 100e18);

        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory message = _buildWithdrawCommand(bytes32("withdraw1"), alice, 10e18);

        vm.expectRevert(
            abi.encodeWithSelector(SpokeController.InsufficientReceiptGas.selector, RECEIPT_GAS, 0)
        );
        _deliverToSpoke(message, 1, 0);
    }

    function test_WithdrawReleaseSucceedsWithReceiptGas() public {
        _depositCollateral(alice, 100e18);

        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory message = _buildWithdrawCommand(bytes32("withdraw1"), alice, 10e18);
        _deliverToSpoke(message, 1, RECEIPT_GAS);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Collateral seizure: rejects without gas, succeeds with gas
    // ──────────────────────────────────────────────────────────────────────────

    function test_SeizeRevertsWithoutReceiptGas() public {
        _depositCollateral(alice, 100e18);

        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory message = _buildSeizeCommand(bytes32("liq1"), alice, bob, 10e18);

        vm.expectRevert(
            abi.encodeWithSelector(SpokeController.InsufficientReceiptGas.selector, RECEIPT_GAS, 0)
        );
        _deliverToSpoke(message, 1, 0);
    }

    function test_SeizeSucceedsWithReceiptGas() public {
        _depositCollateral(alice, 100e18);

        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory message = _buildSeizeCommand(bytes32("liq1"), alice, bob, 10e18);
        _deliverToSpoke(message, 1, RECEIPT_GAS);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Atomicity: vault operations roll back when receipt gas is missing
    // ──────────────────────────────────────────────────────────────────────────

    function test_BorrowReleaseAtomicRollback() public {
        uint256 vaultBalBefore = mockToken.balanceOf(address(liquidityVault));

        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory message = _buildBorrowCommand(bytes32("borrow1"), alice, 10e18);

        // No receipt gas → lzReceive reverts → vault transfer rolled back
        vm.expectRevert();
        _deliverToSpoke(message, 1, 0);

        // Vault balance unchanged — borrow was NOT released
        assertEq(mockToken.balanceOf(address(liquidityVault)), vaultBalBefore);
    }

    function test_WithdrawReleaseAtomicRollback() public {
        _depositCollateral(alice, 100e18);
        uint256 lockedBefore = collateralVault.lockedBalanceOf(alice, address(mockToken));

        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory message = _buildWithdrawCommand(bytes32("withdraw1"), alice, 10e18);

        vm.expectRevert();
        _deliverToSpoke(message, 1, 0);

        // Collateral still locked — withdraw was NOT released
        assertEq(collateralVault.lockedBalanceOf(alice, address(mockToken)), lockedBefore);
    }

    function test_SeizeAtomicRollback() public {
        _depositCollateral(alice, 100e18);
        uint256 lockedBefore = collateralVault.lockedBalanceOf(alice, address(mockToken));

        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory message = _buildSeizeCommand(bytes32("liq1"), alice, bob, 10e18);

        vm.expectRevert();
        _deliverToSpoke(message, 1, 0);

        // Collateral still locked — seizure was NOT executed
        assertEq(collateralVault.lockedBalanceOf(alice, address(mockToken)), lockedBefore);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Hub state cannot become permanently stuck: retry with gas succeeds
    // ──────────────────────────────────────────────────────────────────────────

    function test_RetryWithGasSucceeds() public {
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory message = _buildBorrowCommand(bytes32("borrow1"), alice, 10e18);

        // First attempt fails — no receipt gas
        vm.expectRevert();
        _deliverToSpoke(message, 1, 0);

        // Retry with gas — LayerZero would redeliver the stored message,
        // this time the caller includes addExecutorLzReceiveOption with nativeValue.
        _deliverToSpoke(message, 1, RECEIPT_GAS);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // User-initiated flows still work
    // ──────────────────────────────────────────────────────────────────────────

    function test_DepositAndNotifyStillWorksWithMsgValue() public {
        MessagingFee memory fee = MessagingFee({nativeFee: 0.1 ether, lzTokenFee: 0});

        vm.prank(alice);
        // forge-lint: disable-next-line(unsafe-typecast)
        spokeController.depositAndNotify{value: 0.1 ether}(
            bytes32("deposit1"), canonicalToken, 100e18, bytes(""), fee
        );

        assertEq(collateralVault.lockedBalanceOf(alice, address(mockToken)), 100e18);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Repay forwards value through LiquidityVault
    // ──────────────────────────────────────────────────────────────────────────

    function test_RepayForwardsValueForReceipt() public {
        // Seed liquidity vault with tokens so repay doesn't fail on balance
        mockToken.mint(alice, 100e18);
        vm.prank(alice);
        mockToken.approve(address(liquidityVault), type(uint256).max);

        // Repay with value to fund the receipt
        vm.prank(alice);
        // forge-lint: disable-next-line(unsafe-typecast)
        liquidityVault.repay{value: RECEIPT_GAS}(bytes32("repay1"), address(mockToken), 10e18, alice);
    }
}
