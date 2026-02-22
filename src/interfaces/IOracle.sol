// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IOracle {
    /// @notice Return price for asset in 1e18 units (e.g. USD price scaled by 1e18),
    /// along with last update timestamp (unix seconds).
    function getPriceE18(address asset) external view returns (uint256 priceE18, uint256 lastUpdatedAt);
}
