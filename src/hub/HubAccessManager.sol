// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

contract HubAccessManager is AccessManager {
    uint64 public constant ROLE_HUB_CONTROLLER = 1;
    uint64 public constant ROLE_DEBT_MANAGER = 2;
    uint64 public constant ROLE_POSITION_BOOK = 3;
    uint64 public constant ROLE_LIQUIDATION_ENGINE = 4;
    uint64 public constant ROLE_ASSET_REGISTRY = 5;
    uint64 public constant ROLE_RISK_ENGINE = 6;
    uint64 public constant ROLE_ROUTER = 7;

    constructor(address _owner) AccessManager(_owner) {}
}
