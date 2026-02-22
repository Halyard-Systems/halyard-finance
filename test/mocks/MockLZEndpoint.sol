// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @notice Minimal mock for LayerZero endpoint that can accept ETH
 * @dev All actual function calls will be mocked via vm.mockCall
 */
contract MockLZEndpoint {
    // Accept ETH
    receive() external payable {}

    // Fallback for any function calls
    fallback() external payable {}
}
