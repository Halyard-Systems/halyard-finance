// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {PythOracleAdapter} from "../../../src/hub/PythOracleAdapter.sol";
import {HubAccessManager} from "../../../src/hub/HubAccessManager.sol";
import {MockPyth} from "../../../lib/pyth-sdk-solidity/MockPyth.sol";
import {PythStructs} from "../../../lib/pyth-sdk-solidity/PythStructs.sol";

contract PythOracleAdapterTest is Test {
    receive() external payable {}

    PythOracleAdapter public adapter;
    MockPyth public mockPyth;
    HubAccessManager public accessManager;

    address public admin = address(0x5);
    address public weth = makeAddr("WETH");
    bytes32 public wethFeedId = bytes32(uint256(1));

    function setUp() public {
        vm.deal(address(this), 1 ether);
        mockPyth = new MockPyth(120, 1); // 120s valid period, 1 wei fee
        accessManager = new HubAccessManager(admin);

        vm.startPrank(admin);
        adapter = new PythOracleAdapter(address(accessManager), address(mockPyth), 60);
        adapter.setFeedId(weth, wethFeedId);
        vm.stopPrank();
    }

    // --- Helper to push a price into MockPyth ---
    function _pushPrice(bytes32 feedId, int64 price, uint64 conf, int32 expo) internal {
        bytes[] memory updateData = new bytes[](1);
        updateData[0] = mockPyth.createPriceFeedUpdateData(
            feedId, price, conf, expo, price, conf, uint64(block.timestamp)
        );
        mockPyth.updatePriceFeeds{value: 1}(updateData);
    }

    // --- getPriceE18: basic happy path ---

    function test_getPriceE18_basicPrice() public {
        // price=2000_00000000, expo=-8 => $2000.00
        _pushPrice(wethFeedId, 2000_00000000, 100000, -8);

        (uint256 priceE18, uint256 ts) = adapter.getPriceE18(weth);
        assertEq(priceE18, 2000e18);
        assertEq(ts, block.timestamp);
    }

    function test_getPriceE18_positiveExponent() public {
        // price=5, expo=2 => 500 (in whatever unit)
        _pushPrice(wethFeedId, 5, 0, 2);

        (uint256 priceE18,) = adapter.getPriceE18(weth);
        assertEq(priceE18, 500e18);
    }

    function test_getPriceE18_zeroExponent() public {
        // price=42, expo=0 => 42
        _pushPrice(wethFeedId, 42, 0, 0);

        (uint256 priceE18,) = adapter.getPriceE18(weth);
        assertEq(priceE18, 42e18);
    }

    // --- getPriceE18: revert cases ---

    function test_getPriceE18_revertsIfFeedNotSet() public {
        address unknown = makeAddr("UNKNOWN");
        vm.expectRevert(abi.encodeWithSelector(PythOracleAdapter.FeedNotSet.selector, unknown));
        adapter.getPriceE18(unknown);
    }

    function test_getPriceE18_revertsIfNegativePrice() public {
        _pushPrice(wethFeedId, -100, 10, -2);

        vm.expectRevert(); // Pyth returns negative, adapter reverts
        adapter.getPriceE18(weth);
    }

    // --- Confidence check ---

    function test_getPriceE18_revertsIfConfidenceTooWide() public {
        vm.prank(admin);
        adapter.setMaxConfidenceRatioBps(500); // 5%

        // price=1000, conf=60 => 6% > 5%
        _pushPrice(wethFeedId, 1000, 60, 0);

        vm.expectRevert(
            abi.encodeWithSelector(PythOracleAdapter.ConfidenceTooWide.selector, weth, uint64(60), int64(1000))
        );
        adapter.getPriceE18(weth);
    }

    function test_getPriceE18_passesIfConfidenceWithinLimit() public {
        vm.prank(admin);
        adapter.setMaxConfidenceRatioBps(500); // 5%

        // price=1000, conf=40 => 4% < 5%
        _pushPrice(wethFeedId, 1000, 40, 0);

        (uint256 priceE18,) = adapter.getPriceE18(weth);
        assertEq(priceE18, 1000e18);
    }

    function test_getPriceE18_skipsConfidenceCheckWhenDisabled() public {
        // maxConfidenceRatioBps defaults to 0 (disabled)
        // price=100, conf=99 => 99% but should not revert
        _pushPrice(wethFeedId, 100, 99, 0);

        (uint256 priceE18,) = adapter.getPriceE18(weth);
        assertEq(priceE18, 100e18);
    }

    // --- Admin functions ---

    function test_setFeedId_onlyAdmin() public {
        vm.expectRevert();
        adapter.setFeedId(weth, bytes32(uint256(99)));
    }

    function test_setMaxStaleness_onlyAdmin() public {
        vm.expectRevert();
        adapter.setMaxStaleness(120);
    }

    function test_setMaxStaleness_revertsOnZero() public {
        vm.prank(admin);
        vm.expectRevert(PythOracleAdapter.InvalidStaleness.selector);
        adapter.setMaxStaleness(0);
    }

    function test_setMaxConfidenceRatioBps_onlyAdmin() public {
        vm.expectRevert();
        adapter.setMaxConfidenceRatioBps(500);
    }

    // --- Constructor validation ---

    function test_constructor_revertsOnZeroAddress() public {
        vm.expectRevert(PythOracleAdapter.InvalidAddress.selector);
        new PythOracleAdapter(address(accessManager), address(0), 60);
    }

    function test_constructor_revertsOnZeroStaleness() public {
        vm.expectRevert(PythOracleAdapter.InvalidStaleness.selector);
        new PythOracleAdapter(address(accessManager), address(mockPyth), 0);
    }

    // --- Pyth passthroughs ---

    function test_updatePriceFeeds_forwardsToPyth() public {
        bytes[] memory updateData = new bytes[](1);
        updateData[0] = mockPyth.createPriceFeedUpdateData(
            wethFeedId, 2500_00000000, 100000, -8, 2500_00000000, 100000, uint64(block.timestamp)
        );

        adapter.updatePriceFeeds{value: 1}(updateData);

        (uint256 priceE18,) = adapter.getPriceE18(weth);
        assertEq(priceE18, 2500e18);
    }

    function test_getUpdateFee_forwardsToPyth() public {
        bytes[] memory updateData = new bytes[](2);
        updateData[0] = "";
        updateData[1] = "";

        uint256 fee = adapter.getUpdateFee(updateData);
        assertEq(fee, 2); // 2 updates * 1 wei per update
    }

    // --- Additional coverage ---

    function test_getPriceE18_revertsIfStale() public {
        _pushPrice(wethFeedId, 2000_00000000, 100000, -8);
        vm.warp(block.timestamp + 61); // exceed 60s maxStaleness
        vm.expectRevert(); // Pyth's getPriceNoOlderThan reverts on stale price
        adapter.getPriceE18(weth);
    }

    function test_setFeedId_revertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(PythOracleAdapter.InvalidAddress.selector);
        adapter.setFeedId(address(0), wethFeedId);
    }

    function test_getPriceE18_revertsIfExponentTooLarge() public {
        _pushPrice(wethFeedId, 100, 0, 60);
        vm.expectRevert(abi.encodeWithSelector(PythOracleAdapter.ExponentTooLarge.selector, int32(60)));
        adapter.getPriceE18(weth);
    }

    function test_getPriceE18_revertsIfExponentTooNegative() public {
        _pushPrice(wethFeedId, 100, 0, -19);
        vm.expectRevert(abi.encodeWithSelector(PythOracleAdapter.ExponentTooLarge.selector, int32(-19)));
        adapter.getPriceE18(weth);
    }

    function test_updatePriceFeeds_refundsExcessEth() public {
        bytes[] memory updateData = new bytes[](1);
        updateData[0] = mockPyth.createPriceFeedUpdateData(
            wethFeedId, 2500_00000000, 100000, -8, 2500_00000000, 100000, uint64(block.timestamp)
        );

        uint256 balBefore = address(this).balance;
        adapter.updatePriceFeeds{value: 0.1 ether}(updateData); // send way more than 1 wei fee
        uint256 balAfter = address(this).balance;

        // Should only have spent 1 wei (the MockPyth fee), rest refunded
        assertEq(balBefore - balAfter, 1);
    }
}
