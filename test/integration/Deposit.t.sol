// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseIntegrationTest} from "./BaseIntegrationTest.t.sol";

contract DepositTest is BaseIntegrationTest {
    function test_DepositSuccess() public {
        uint256 depositAmount = 100e18;

        // forge-lint: disable-next-line(unsafe-typecast)
        _depositAndCredit(alice, bytes32("test"), canonicalToken, depositAmount);
    }
}
