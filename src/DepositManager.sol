// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./interfaces/IStargateRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "forge-std/console.sol";

contract DepositManager is ReentrancyGuard {
    uint256 public constant RAY = 1e27;

    // Asset configuration
    struct Asset {
        address tokenAddress;
        string symbol;
        uint8 decimals;
        bool isActive;
        uint256 liquidityIndex;
        uint256 lastUpdateTimestamp;
        uint256 totalScaledSupply;
        uint256 totalDeposits;
        uint256 totalBorrows;
        // Interest rate model parameters
        uint256 baseRate;
        uint256 slope1;
        uint256 slope2;
        uint256 kink;
        uint256 reserveFactor;
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

    // Admin and BorrowManager address
    address public owner;
    address public borrowManager;

    // Events
    event TokenAdded(bytes32 indexed tokenId, address tokenAddress, uint8 decimals);
    event TokenDeposited(bytes32 indexed tokenId, address indexed user, uint256 amount);
    event TokenWithdrawn(bytes32 indexed tokenId, address indexed user, uint256 amount);
    event TokenBorrowed(bytes32 indexed tokenId, address indexed user, uint256 amount);
    event TotalBorrowsIncreased(bytes32 indexed tokenId, uint256 newTotal);
    event TotalBorrowsDecreased(bytes32 indexed tokenId, uint256 newTotal);

    // Custom errors
    error TokenNotSupported(bytes32 tokenId);
    error TokenNotActive(bytes32 tokenId);
    error InsufficientBalance(bytes32 tokenId, address user, uint256 requested, uint256 available);
    error TransferFailed();

    constructor(address _stargateRouter, uint256 _poolId) {
        stargateRouter = IStargateRouter(_stargateRouter);
        poolId = _poolId;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Must be owner");
        _;
    }

    modifier onlyBorrowManager() {
        require(msg.sender == borrowManager, "Must be BorrowManager");
        _;
    }

    function setBorrowManager(address _borrowManager) external onlyOwner {
        borrowManager = _borrowManager;
    }

    function addToken(
        string memory symbol,
        address tokenAddress,
        uint8 decimals,
        uint256 baseRate,
        uint256 slope1,
        uint256 slope2,
        uint256 kink,
        uint256 reserveFactor
    ) external onlyOwner {
        bytes32 tokenId = keccak256(abi.encodePacked(symbol));
        require(assets[tokenId].tokenAddress == address(0), "Token already exists");

        assets[tokenId] = Asset({
            tokenAddress: tokenAddress,
            symbol: symbol,
            decimals: decimals,
            isActive: true,
            liquidityIndex: RAY,
            lastUpdateTimestamp: block.timestamp,
            totalScaledSupply: 0,
            totalDeposits: 0,
            totalBorrows: 0,
            baseRate: baseRate,
            slope1: slope1,
            slope2: slope2,
            kink: kink,
            reserveFactor: reserveFactor
        });

        supportedTokens.push(tokenId);
        emit TokenAdded(tokenId, tokenAddress, decimals);
    }

    function _updateLiquidityIndex(bytes32 tokenId) internal {
        Asset storage asset = assets[tokenId];
        if (!asset.isActive) revert TokenNotActive(tokenId);

        uint256 delta = block.timestamp - asset.lastUpdateTimestamp;

        if (delta > 0) {
            if (asset.totalDeposits == 0) {
                asset.liquidityIndex = RAY;
                asset.lastUpdateTimestamp = block.timestamp;
                return;
            }

            uint256 U = (asset.totalBorrows * 1e18) / asset.totalDeposits;
            uint256 supplyRate =
                _calculateSupplyRate(U, asset.baseRate, asset.slope1, asset.slope2, asset.kink, asset.reserveFactor);
            uint256 accrued = (supplyRate * delta) / (365 days);
            asset.liquidityIndex = (asset.liquidityIndex * (RAY + accrued)) / RAY;
            asset.lastUpdateTimestamp = block.timestamp;
        }
    }

    // Add a private function for safe ERC20 transferFrom (handles USDT)
    function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferFrom failed");
    }

    // Add a private function for safe ERC20 transfer (handles USDT)
    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
    }

    function deposit(bytes32 tokenId, uint256 amount) external payable nonReentrant {
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
            _safeTransferFrom(config.tokenAddress, msg.sender, address(this), amount);
        }

        console.log("Deposited amount:", amount);
        console.log("Liquidity index:", config.liquidityIndex);

        // Mint scaled receipt tokens
        uint256 scaled = (amount * RAY) / config.liquidityIndex;
        userBalances[tokenId][msg.sender].scaledBalance += scaled;
        config.totalScaledSupply += scaled;
        config.totalDeposits += amount;

        emit TokenDeposited(tokenId, msg.sender, amount);
    }

    function withdraw(bytes32 tokenId, uint256 amount) external nonReentrant {
        Asset storage config = assets[tokenId];
        if (!config.isActive) revert TokenNotActive(tokenId);

        _updateLiquidityIndex(tokenId);

        uint256 scaled = (amount * RAY) / config.liquidityIndex;
        uint256 userScaledBalance = userBalances[tokenId][msg.sender].scaledBalance;

        if (scaled > userScaledBalance) {
            revert InsufficientBalance(tokenId, msg.sender, amount, balanceOf(tokenId, msg.sender));
        }

        userBalances[tokenId][msg.sender].scaledBalance -= scaled;
        config.totalScaledSupply -= scaled;
        config.totalDeposits -= amount;

        // Transfer tokens to user
        if (config.tokenAddress == address(0)) {
            // Handle ETH withdrawals
            (bool success,) = payable(msg.sender).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            // Handle ERC20 token withdrawals
            _safeTransfer(config.tokenAddress, msg.sender, amount);
        }

        emit TokenWithdrawn(tokenId, msg.sender, amount);
    }

    function balanceOf(bytes32 tokenId, address user) public view returns (uint256) {
        Asset storage config = assets[tokenId];
        if (!config.isActive) revert TokenNotActive(tokenId);

        return (userBalances[tokenId][user].scaledBalance * config.liquidityIndex) / RAY;
    }

    function getAsset(bytes32 tokenId) external view returns (Asset memory) {
        return assets[tokenId];
    }

    function getSupportedTokens() external view returns (bytes32[] memory) {
        return supportedTokens;
    }

    function setTokenActive(bytes32 tokenId, bool isActive) external onlyOwner {
        Asset storage config = assets[tokenId];
        if (config.tokenAddress == address(0)) {
            revert TokenNotSupported(tokenId);
        }
        config.isActive = isActive;
    }

    function _calculateSupplyRate(
        uint256 U,
        uint256 baseRate,
        uint256 slope1,
        uint256 slope2,
        uint256 kink,
        uint256 reserveFactor
    ) internal pure returns (uint256) {
        console.log("Base rate", baseRate);
        console.log("Slope1", slope1);
        console.log("Slope2", slope2);
        console.log("Kink", kink);
        console.log("Reserve factor", reserveFactor);
        console.log("U", U);
        uint256 borrowRate;
        if (U <= kink) {
            borrowRate = baseRate + ((slope1 * U) / kink);
        } else {
            borrowRate = baseRate + slope1 + ((slope2 * (U - kink)) / (1e18 - kink));
        }
        uint256 netRate = (borrowRate * (RAY - reserveFactor)) / RAY;
        // When U = 0, return 0 (no supply rate when no utilization)
        // When U > 0, return the supply rate based on utilization
        return (netRate * U) / RAY;
    }

    function _calculateBorrowRate(uint256 U, uint256 baseRate, uint256 slope1, uint256 slope2, uint256 kink)
        internal
        pure
        returns (uint256)
    {
        console.log("Borrow rate calculation - Base rate", baseRate);
        console.log("Borrow rate calculation - Slope1", slope1);
        console.log("Borrow rate calculation - Slope2", slope2);
        console.log("Borrow rate calculation - Kink", kink);
        console.log("Borrow rate calculation - U", U);

        uint256 borrowRate;
        if (U <= kink) {
            borrowRate = baseRate + ((slope1 * U) / kink);
        } else {
            borrowRate = baseRate + slope1 + ((slope2 * (U - kink)) / (1e18 - kink));
        }
        console.log("Borrow rate calculation - Final borrow rate", borrowRate);
        return borrowRate;
    }

    function transferOut(bytes32 tokenId, address to, uint256 amount) external onlyBorrowManager {
        Asset storage config = assets[tokenId];
        if (!config.isActive) revert TokenNotActive(tokenId);
        if (config.tokenAddress == address(0)) {
            (bool success,) = payable(to).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            _safeTransfer(config.tokenAddress, to, amount);
        }
    }

    // Allow BorrowManager to transfer tokens/ETH from user to protocol for repay
    function transferIn(bytes32 tokenId, address from, uint256 amount) external payable onlyBorrowManager {
        Asset storage config = assets[tokenId];
        if (!config.isActive) revert TokenNotActive(tokenId);
        if (config.tokenAddress == address(0)) {
            require(msg.value == amount, "ETH amount mismatch");
            // ETH is already in the contract
        } else {
            require(msg.value == 0, "ETH not accepted for ERC20 repay");
            _safeTransferFrom(config.tokenAddress, from, address(this), amount);
        }
    }

    function calculateBorrowRate(bytes32 tokenId, uint256 U) external view returns (uint256) {
        Asset storage config = assets[tokenId];
        return _calculateBorrowRate(U, config.baseRate, config.slope1, config.slope2, config.kink);
    }

    function setLastBorrowTime(bytes32 tokenId, uint256 timestamp) external onlyBorrowManager {
        Asset storage config = assets[tokenId];
        config.lastUpdateTimestamp = timestamp;
    }

    function incrementTotalBorrows(bytes32 tokenId, uint256 amount) external onlyBorrowManager {
        Asset storage config = assets[tokenId];
        if (!config.isActive) revert TokenNotActive(tokenId);
        config.totalBorrows += amount;
        emit TotalBorrowsIncreased(tokenId, config.totalBorrows);
    }

    function decrementTotalBorrows(bytes32 tokenId, uint256 amount) external onlyBorrowManager {
        Asset storage config = assets[tokenId];
        if (!config.isActive) revert TokenNotActive(tokenId);
        require(config.totalBorrows >= amount, "totalBorrows underflow");
        config.totalBorrows -= amount;
        emit TotalBorrowsDecreased(tokenId, config.totalBorrows);
    }

    // Emergency function for owner to recover stuck tokens
    function emergencyWithdraw(bytes32 tokenId, address to) external onlyOwner {
        Asset storage config = assets[tokenId];
        if (!config.isActive) revert TokenNotActive(tokenId);

        uint256 balance;
        if (config.tokenAddress == address(0)) {
            balance = address(this).balance;
            (bool success,) = payable(to).call{value: balance}("");
            if (!success) revert TransferFailed();
        } else {
            balance = IERC20(config.tokenAddress).balanceOf(address(this));
            _safeTransfer(config.tokenAddress, to, balance);
        }
    }

    // Allow the contract to receive ETH
    receive() external payable {}
}
