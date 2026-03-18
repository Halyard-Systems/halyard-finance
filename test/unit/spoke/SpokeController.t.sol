// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../../BaseTest.t.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

contract SpokeControllerTest is BaseTest {
    function test_ConfigureHub() public {
        vm.prank(admin);
        bytes32 testHub = bytes32(uint256(uint160(address(0xBEEF))));
        spokeController.configureHub(1, testHub);
        assertEq(spokeController.hubEid(), 1);
        assertEq(spokeController.trustedRemoteHub(), testHub);
    }

    function test_SetCollateralVault() public {
        vm.prank(admin);
        spokeController.setCollateralVault(address(0x1));
        assertEq(address(spokeController.collateralVault()), address(0x1));
    }

    function test_SetLiquidityVault() public {
        vm.prank(admin);
        spokeController.setLiquidityVault(address(0x1));
        assertEq(address(spokeController.liquidityVault()), address(0x1));
    }

    function test_SetTokenMapping() public {
        vm.prank(admin);
        spokeController.setTokenMapping(address(0x1), address(0x1));
        assertEq(address(spokeController.canonicalToSpoke(address(0x1))), address(0x1));
    }

    function test_onRepayNotified() public {
        vm.prank(address(liquidityVault));
        // forge-lint: disable-next-line(unsafe-typecast)
        spokeController.onRepayNotified(bytes32("test"), address(0x1), address(0x1), address(mockToken), 100);
        //  TODO: assertion
    }

    function test_configureSpokeEid() public {
        vm.prank(admin);
        spokeController.configureSpokeEid(1);
        assertEq(spokeController.spokeEid(), 1);
    }

    function test_depositAndNotify() public {
        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        vm.prank(alice);
        // forge-lint: disable-next-line(unsafe-typecast)
        spokeController.depositAndNotify(bytes32("test"), canonicalToken, 100, bytes(""), fee);

        assertEq(collateralVault.lockedBalanceOf(alice, address(mockToken)), 100);
    }

    function test_quoteDeposit() public {
        bytes memory options = hex"0003010011010000000000000000000000000000030d40";

        // Mock the LZ endpoint's quote function to return a known fee
        vm.mockCall(
            address(mockLzEndpoint),
            abi.encodeWithSelector(bytes4(keccak256("quote((uint32,bytes32,bytes,bytes,bool),address)"))),
            abi.encode(uint256(0.003 ether), uint256(0))
        );

        MessagingFee memory fee = spokeController.quoteDeposit(options);
        assertEq(fee.nativeFee, 0.003 ether);
        assertEq(fee.lzTokenFee, 0);
    }

    function test_quoteRepayReceipt() public {
        // Mock the LZ endpoint's quote function to return a known fee
        vm.mockCall(
            address(mockLzEndpoint),
            abi.encodeWithSelector(bytes4(keccak256("quote((uint32,bytes32,bytes,bytes,bool),address)"))),
            abi.encode(uint256(0.001 ether), uint256(0))
        );

        MessagingFee memory fee = spokeController.quoteRepayReceipt();
        assertEq(fee.nativeFee, 0.001 ether);
        assertEq(fee.lzTokenFee, 0);
    }
}
