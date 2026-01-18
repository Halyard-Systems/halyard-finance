// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BaseSpokeTest} from "./BaseSpokeTest.t.sol";
import {SpokeController} from "../../../src/spoke/SpokeController.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

contract SpokeControllerTest is BaseSpokeTest {
    function test_ConfigureHub() public {
        spokeController.configureHub(1, bytes32("test"));
        assertEq(spokeController.hubEid(), 1);
        assertEq(spokeController.trustedRemoteHub(), bytes32("test"));
    }

    function test_SetCollateralVault() public {
        spokeController.setCollateralVault(address(0x1));
        assertEq(address(spokeController.collateralVault()), address(0x1));
    }

    function test_SetLiquidityVault() public {
        spokeController.setLiquidityVault(address(0x1));
        assertEq(address(spokeController.liquidityVault()), address(0x1));
    }

    function test_SetTokenMapping() public {
        spokeController.setTokenMapping(address(0x1), address(0x1));
        assertEq(address(spokeController.canonicalToSpoke(address(0x1))), address(0x1));
    }

    function test_onRepayNotified() public {
        vm.prank(address(liquidityVault));
        spokeController.onRepayNotified(bytes32("test"), address(0x1), address(0x1), address(mockToken), 100);
        //  TODO: assertion
    }

    function test_configureSpokeEid() public {
        spokeController.configureSpokeEid(1);
        assertEq(spokeController.spokeEid(), 1);
    }

    function test_depositAndNotify() public {
        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});
        spokeController.depositAndNotify(
            bytes32("test"), canonicalToken, 100, address(this), bytes(""), fee, address(this)
        );
        //  TODO: assertion
    }
}
