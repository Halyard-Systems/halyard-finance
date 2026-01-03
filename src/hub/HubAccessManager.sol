// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/access/manager/AccessManager.sol";

contract HubAccessManager is AccessManager {
    uint64 public constant ROLE_DEBT_MANAGER = 1;
    uint64 public constant ROLE_POSITION_BOOK = 2;
    uint64 public constant ROLE_LIQUIDATION_ENGINE = 3;

    constructor(address _owner) AccessManager(_owner) {}
}