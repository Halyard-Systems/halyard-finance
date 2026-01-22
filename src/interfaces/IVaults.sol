// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IVaults
 * @notice Shared interfaces for CollateralVault and LiquidityVault
 */

interface ICollateralVault {
    function deposit(address asset, uint256 amount, address onBehalfOf) external;
    function withdrawByController(address user, address to, address asset, uint256 amount) external;
    function seizeByController(address user, address to, address asset, uint256 amount) external;
}

interface ILiquidityVault {
    function releaseBorrow(bytes32 borrowId, address user, address receiver, address asset, uint256 amount) external;
}

/// Push-driven hook from LiquidityVault to SpokeController
interface ISpokeRepayController {
    function onRepayNotified(bytes32 repayId, address payer, address onBehalfOf, address asset, uint256 amount) external;
}
