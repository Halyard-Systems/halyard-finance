// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./interfaces/IStargateRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

contract DepositManager {
    uint256 public constant RAY = 1e27;

    // Asset configuration
    struct Asset {
        address tokenAddress;
        uint8 decimals;
        bool isActive;
        uint256 liquidityIndex;
        uint256 lastUpdateTimestamp;
        uint256 totalScaledSupply;
        uint256 totalDeposits;
        uint256 totalBorrows;
    }

    // User balance tracking per token
    struct UserBalance {
        uint256 scaledBalance;
        uint256 lastUpdateTimestamp;
    }

    // Stargate router for liquidity operations
    IStargateRouter public immutable stargateRouter;
    uint256 public immutable poolId;

    // Asset registry
    mapping(bytes32 => Asset) public assets;
    mapping(bytes32 => mapping(address => UserBalance)) public userBalances;
    bytes32[] public supportedTokens;

    // Interest rate model parameters (example values) - increased for testing
    uint256 public immutable baseRate = 0.1e27; // e.g. 10% in RAY = 0.1e27
    uint256 public immutable slope1 = 0.5e27; // e.g. 50% in RAY = 0.5e27
    uint256 public immutable slope2 = 5.0e27; // e.g. 500% in RAY = 5.0e27
    uint256 public immutable kink = 0.8e18; // e.g. 80% utilization in 1e18 = 0.8e18
    uint256 public immutable reserveFactor = 0.1e27; // percent of interest kept (e.g. 10% = 0.1e27)

    // Events
    event TokenAdded(
        bytes32 indexed tokenId,
        address tokenAddress,
        uint8 decimals
    );
    event TokenDeposited(
        bytes32 indexed tokenId,
        address indexed user,
        uint256 amount
    );
    event TokenWithdrawn(
        bytes32 indexed tokenId,
        address indexed user,
        uint256 amount
    );
    event TokenBorrowed(
        bytes32 indexed tokenId,
        address indexed user,
        uint256 amount
    );

    // Custom errors
    error TokenNotSupported(bytes32 tokenId);
    error TokenNotActive(bytes32 tokenId);
    error InsufficientBalance(
        bytes32 tokenId,
        address user,
        uint256 requested,
        uint256 available
    );
    error TransferFailed();

    constructor(address _stargateRouter, uint256 _poolId) {
        stargateRouter = IStargateRouter(_stargateRouter);
        poolId = _poolId;

        // Initialize supported tokens
        _addToken("ETH", address(0), 18); // ETH is represented as address(0)
        _addToken("USDC", 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 6);
        _addToken("USDT", 0xdAC17F958D2ee523a2206206994597C13D831ec7, 6);
    }

    function _addToken(
        string memory symbol,
        address tokenAddress,
        uint8 decimals
    ) internal {
        bytes32 tokenId = keccak256(abi.encodePacked(symbol));
        require(
            assets[tokenId].tokenAddress == address(0),
            "Token already exists"
        );

        assets[tokenId] = Asset({
            tokenAddress: tokenAddress,
            decimals: decimals,
            isActive: true,
            liquidityIndex: RAY,
            lastUpdateTimestamp: block.timestamp,
            totalScaledSupply: 0,
            totalDeposits: 0,
            totalBorrows: 0
        });

        supportedTokens.push(tokenId);
        emit TokenAdded(tokenId, tokenAddress, decimals);
    }

    function _updateLiquidityIndex(bytes32 tokenId) internal {
        Asset storage asset = assets[tokenId];
        if (!asset.isActive) revert TokenNotActive(tokenId);

        console.log(
            "Updating liquidity index for token:",
            string(abi.encodePacked(tokenId))
        );
        uint256 delta = block.timestamp - asset.lastUpdateTimestamp;

        if (delta > 0) {
            console.log("Delta is greater than 0");
            console.log("Total deposits:", asset.totalDeposits);
            console.log("Total borrows:", asset.totalBorrows);

            if (asset.totalDeposits == 0) {
                asset.liquidityIndex = RAY;
                asset.lastUpdateTimestamp = block.timestamp;
                return;
            }

            console.log("About to calculate U");
            uint256 U = (asset.totalBorrows * 1e18) / asset.totalDeposits;
            console.log("U is", U);
            uint256 supplyRate = _calculateSupplyRate(U);
            console.log("Supply rate is", supplyRate);
            uint256 accrued = (supplyRate * delta) / (365 days);
            console.log("Accrued is", accrued);
            asset.liquidityIndex =
                (asset.liquidityIndex * (RAY + accrued)) /
                RAY;
            asset.lastUpdateTimestamp = block.timestamp;
        }
    }

    function deposit(bytes32 tokenId, uint256 amount) external payable {
        Asset storage config = assets[tokenId];
        if (!config.isActive) revert TokenNotActive(tokenId);

        _updateLiquidityIndex(tokenId);

        // Handle ETH deposits
        if (config.tokenAddress == address(0)) {
            require(msg.value == amount, "ETH amount mismatch");
            // ETH is already in the contract
        } else {
            // Handle ERC20 token deposits
            require(msg.value == 0, "ETH not accepted for ERC20 deposits");
            bool success = IERC20(config.tokenAddress).transferFrom(
                msg.sender,
                address(this),
                amount
            );
            if (!success) revert TransferFailed();
        }

        // Mint scaled receipt tokens
        uint256 scaled = (amount * RAY) / config.liquidityIndex;
        userBalances[tokenId][msg.sender].scaledBalance += scaled;
        config.totalScaledSupply += scaled;
        config.totalDeposits += amount;

        emit TokenDeposited(tokenId, msg.sender, amount);
    }

    function withdraw(bytes32 tokenId, uint256 amount) external {
        Asset storage config = assets[tokenId];
        if (!config.isActive) revert TokenNotActive(tokenId);

        _updateLiquidityIndex(tokenId);

        uint256 scaled = (amount * RAY) / config.liquidityIndex;
        uint256 userScaledBalance = userBalances[tokenId][msg.sender]
            .scaledBalance;

        if (scaled > userScaledBalance) {
            revert InsufficientBalance(
                tokenId,
                msg.sender,
                amount,
                balanceOf(tokenId, msg.sender)
            );
        }

        userBalances[tokenId][msg.sender].scaledBalance -= scaled;
        config.totalScaledSupply -= scaled;
        config.totalDeposits -= amount;

        // Transfer tokens to user
        if (config.tokenAddress == address(0)) {
            // Handle ETH withdrawals
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            // Handle ERC20 token withdrawals
            bool success = IERC20(config.tokenAddress).transfer(
                msg.sender,
                amount
            );
            if (!success) revert TransferFailed();
        }

        emit TokenWithdrawn(tokenId, msg.sender, amount);
    }

    function borrow(bytes32 tokenId, uint256 amount) external {
        Asset storage config = assets[tokenId];
        if (!config.isActive) revert TokenNotActive(tokenId);

        _updateLiquidityIndex(tokenId);
        config.totalBorrows += amount;

        // Transfer tokens to user
        if (config.tokenAddress == address(0)) {
            // Handle ETH borrows
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            // Handle ERC20 token borrows
            bool success = IERC20(config.tokenAddress).transfer(
                msg.sender,
                amount
            );
            if (!success) revert TransferFailed();
        }

        emit TokenBorrowed(tokenId, msg.sender, amount);
    }

    function balanceOf(
        bytes32 tokenId,
        address user
    ) public view returns (uint256) {
        Asset storage config = assets[tokenId];
        if (!config.isActive) revert TokenNotActive(tokenId);

        return
            (userBalances[tokenId][user].scaledBalance *
                config.liquidityIndex) / RAY;
    }

    function getAsset(bytes32 tokenId) external view returns (Asset memory) {
        return assets[tokenId];
    }

    function getSupportedTokens() external view returns (bytes32[] memory) {
        return supportedTokens;
    }

    function addToken(
        string memory symbol,
        address tokenAddress,
        uint8 decimals
    ) external {
        // TODO: Add access control for admin functions
        _addToken(symbol, tokenAddress, decimals);
    }

    function setTokenActive(bytes32 tokenId, bool isActive) external {
        // TODO: Add access control for admin functions
        Asset storage config = assets[tokenId];
        if (config.tokenAddress == address(0))
            revert TokenNotSupported(tokenId);
        config.isActive = isActive;
    }

    function _calculateSupplyRate(uint256 U) internal pure returns (uint256) {
        uint256 borrowRate;
        if (U <= kink) {
            borrowRate = baseRate + ((slope1 * U) / kink);
        } else {
            borrowRate =
                baseRate +
                slope1 +
                ((slope2 * (U - kink)) / (1e18 - kink));
        }
        uint256 netRate = (borrowRate * (RAY - reserveFactor)) / RAY;
        return (netRate * U) / RAY;
    }

    // Allow the contract to receive ETH
    receive() external payable {}

    // Emergency function to recover stuck tokens (admin only)
    function emergencyWithdraw(bytes32 tokenId, address to) external {
        // TODO: Add access control for admin functions
        require(false, "Not implemented");
        Asset storage config = assets[tokenId];
        if (!config.isActive) revert TokenNotActive(tokenId);

        uint256 balance;
        if (config.tokenAddress == address(0)) {
            balance = address(this).balance;
            (bool success, ) = payable(to).call{value: balance}("");
            if (!success) revert TransferFailed();
        } else {
            balance = IERC20(config.tokenAddress).balanceOf(address(this));
            bool success = IERC20(config.tokenAddress).transfer(to, balance);
            if (!success) revert TransferFailed();
        }
    }
}
