// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../../BaseTest.t.sol";
import {AssetRegistry} from "../../../src/hub/AssetRegistry.sol";
import {PositionBook} from "../../../src/hub/PositionBook.sol";

contract PositionBookTest is BaseTest {
    uint32 constant EID = 1;
    address constant ASSET = address(0x123);
    uint256 constant CAP = 1000e18;

    function test_CollateralOf() public {
        vm.prank(address(hubController));
        positionBook.creditCollateral(alice, 1, address(0x123), 100);
        assertEq(positionBook.collateralOf(alice, 1, address(0x123)), 100);
        assertEq(positionBook.collateralAssetsOf(alice).length, 1);
    }

    // -- Supply cap tests --

    function _setSupplyCap(uint256 cap) internal {
        vm.prank(admin);
        assetRegistry.setCollateralConfig(
            EID,
            ASSET,
            AssetRegistry.CollateralConfig({
                isSupported: true, ltvBps: 8000, liqThresholdBps: 8500, liqBonusBps: 500, decimals: 18, supplyCap: cap
            })
        );
    }

    function test_CreditWithinSupplyCap() public {
        _setSupplyCap(CAP);

        vm.prank(address(hubController));
        positionBook.creditCollateral(alice, EID, ASSET, 500e18);

        assertEq(positionBook.collateralOf(alice, EID, ASSET), 500e18);
        assertEq(positionBook.globalCollateralOf(EID, ASSET), 500e18);
    }

    function test_CreditExactlyAtSupplyCap() public {
        _setSupplyCap(CAP);

        vm.prank(address(hubController));
        positionBook.creditCollateral(alice, EID, ASSET, CAP);

        assertEq(positionBook.collateralOf(alice, EID, ASSET), CAP);
        assertEq(positionBook.globalCollateralOf(EID, ASSET), CAP);
    }

    function test_CreditExceedsSupplyCap_Reverts() public {
        _setSupplyCap(CAP);

        vm.prank(address(hubController));
        vm.expectRevert(abi.encodeWithSelector(PositionBook.SupplyCapExceeded.selector, EID, ASSET, CAP, CAP + 1));
        positionBook.creditCollateral(alice, EID, ASSET, CAP + 1);
    }

    function test_MultipleUsersExceedSupplyCap_Reverts() public {
        _setSupplyCap(CAP);

        vm.prank(address(hubController));
        positionBook.creditCollateral(alice, EID, ASSET, 600e18);

        vm.prank(address(hubController));
        vm.expectRevert(abi.encodeWithSelector(PositionBook.SupplyCapExceeded.selector, EID, ASSET, CAP, 1100e18));
        positionBook.creditCollateral(bob, EID, ASSET, 500e18);
    }

    function test_ZeroSupplyCapMeansUnlimited() public {
        // Default config has supplyCap: 0 (unlimited)
        vm.prank(address(hubController));
        positionBook.creditCollateral(alice, EID, ASSET, type(uint128).max);

        assertEq(positionBook.collateralOf(alice, EID, ASSET), type(uint128).max);
    }

    function test_GlobalCollateralDecrementsAfterWithdraw() public {
        _setSupplyCap(CAP);

        vm.prank(address(hubController));
        positionBook.creditCollateral(alice, EID, ASSET, CAP);
        assertEq(positionBook.globalCollateralOf(EID, ASSET), CAP);

        // Reserve + create pending withdraw
        vm.prank(address(riskEngine));
        positionBook.reserveCollateral(alice, EID, ASSET, 200e18);

        bytes32 wId = keccak256("test_withdraw");
        vm.prank(address(riskEngine));
        positionBook.createPendingWithdraw(wId, alice, EID, ASSET, 200e18);

        // Finalize withdraw — debits collateral
        vm.prank(address(hubRouter));
        positionBook.finalizePendingWithdraw(wId, true);

        assertEq(positionBook.globalCollateralOf(EID, ASSET), 800e18);

        // Bob can now deposit into the freed space
        vm.prank(address(hubController));
        positionBook.creditCollateral(bob, EID, ASSET, 200e18);
        assertEq(positionBook.globalCollateralOf(EID, ASSET), CAP);
    }

    // function test_ReservedCollateralOf() public {
    //     vm.prank(riskEngine);
    //     positionBook.reserveCollateral(alice, 1, address(0x123), 100);
    //     assertEq(positionBook.reservedCollateralOf(alice, 1, address(0x123)), 100);
    // }

    // function test_ReservedCollateralOf_InvalidAddress() public {
    //     vm.expectRevert(PositionBook.InvalidAddress.selector);
    //     positionBook.reservedCollateralOf(address(0), 1, address(0x123));
    // }

    // function test_ReservedCollateralOf_InvalidEid() public {
    //     vm.expectRevert(PositionBook.InvalidEid.selector);
    //     positionBook.reservedCollateralOf(alice, 0, address(0x123));
    // }

    // function test_ReservedCollateralOf_InvalidAmount() public {
    //     vm.expectRevert(PositionBook.InvalidAmount.selector);
    //     positionBook.reservedCollateralOf(alice, 1, address(0x123), 0);
    // }

    // function test_AvailableCollateralOf() public {
    //     vm.prank(hubAccessManager.ROLE_HUB_CONTROLLER());
    //     positionBook.creditCollateral(alice, 1, address(0x123), 100);
    //     vm.prank(hubAccessManager.ROLE_RISK_ENGINE());
    //     positionBook.reserveCollateral(alice, 1, address(0x123), 50);
    //     assertEq(positionBook.availableCollateralOf(alice, 1, address(0x123)), 50);
    // }

    // function test_AvailableCollateralOf_InvalidAddress() public {
    //     vm.expectRevert(PositionBook.InvalidAddress.selector);
    //     positionBook.availableCollateralOf(address(0), 1, address(0x123));
    // }

    // function test_AvailableCollateralOf_InvalidEid() public {
    //     vm.expectRevert(PositionBook.InvalidEid.selector);
    //     positionBook.availableCollateralOf(alice, 0, address(0x123));
    // }

    // function test_AvailableCollateralOf_InvalidAmount() public {
    //     vm.expectRevert(PositionBook.InvalidAmount.selector);
    //     positionBook.availableCollateralOf(alice, 1, address(0x123), 0);
    // }
}
