// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DepositManager} from "../../../src/DepositManager.sol";
import {BaseTest} from "../BaseTest.t.sol";

contract AdminTest is BaseTest {
    function test_AddTokenOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert("Must be owner");
        depositManager.addToken("TEST", address(0x123), 18, 0.1e27, 0.5e27, 5.0e27, 0.8e18, 0.1e27);
    }

    function test_SetBorrowManagerOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert("Must be owner");
        depositManager.setBorrowManager(alice);
    }

    function test_SetTokenActiveOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert("Must be owner");
        depositManager.setTokenActive(USDC_TOKEN_ID, false);
    }

    function test_AddNewToken() public {
        string memory symbol = "DAI";
        address daiAddress = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        uint8 decimals = 18;

        vm.prank(address(this));
        depositManager.addToken(
            symbol,
            daiAddress,
            decimals,
            0.05e27, // 5% base rate
            0.3e27, // 30% slope1
            3.0e27, // 300% slope2
            0.8e18, // 80% utilization kink
            0.1e27 // 10% reserve factor
        );

        bytes32 daiTokenId = keccak256(abi.encodePacked(symbol));
        DepositManager.Asset memory config = depositManager.getAsset(daiTokenId);

        assertEq(config.tokenAddress, daiAddress);
        assertEq(config.decimals, decimals);
        assertTrue(config.isActive);
    }

    function test_SetTokenActive() public {
        vm.prank(address(this));
        depositManager.setTokenActive(USDC_TOKEN_ID, false);

        DepositManager.Asset memory config = depositManager.getAsset(USDC_TOKEN_ID);
        assertFalse(config.isActive);

        vm.prank(alice);
        vm.expectRevert();
        depositManager.deposit(USDC_TOKEN_ID, 1000 * USDC_DECIMALS);

        vm.prank(address(this));
        depositManager.setTokenActive(USDC_TOKEN_ID, true);

        vm.prank(alice);
        depositManager.deposit(USDC_TOKEN_ID, 1000 * USDC_DECIMALS);

        assertEq(depositManager.balanceOf(USDC_TOKEN_ID, alice), 1000 * USDC_DECIMALS);
    }

    function test_AddTokenAlreadyExists() public {
        vm.prank(address(this));
        vm.expectRevert("Token already exists");
        depositManager.addToken("USDC", address(0x123), 18, 0.1e27, 0.5e27, 5.0e27, 0.8e18, 0.1e27);
    }

    function test_SetTokenActiveForETH() public {
        vm.prank(address(this));
        vm.expectRevert(); // Should revert for ETH token
        depositManager.setTokenActive(ETH_TOKEN_ID, false);
    }

    function test_SetBorrowManager() public {
        address newBorrowManager = address(0x456);

        depositManager.setBorrowManager(newBorrowManager);
        assertEq(depositManager.borrowManager(), newBorrowManager);
    }

    function test_ReceiveFunction() public {
        // Test that the contract can receive ETH
        uint256 ethAmount = 1 ether;

        (bool success,) = address(depositManager).call{value: ethAmount}("");
        assertTrue(success, "Contract should be able to receive ETH");
        assertEq(address(depositManager).balance, ethAmount, "Contract should have received the ETH");
    }
}
