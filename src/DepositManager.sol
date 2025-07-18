// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./interfaces/IStargateRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

contract DepositManager {
    uint256 public constant RAY = 1e27;
    address public immutable USDC;

    // Stargate router for liquidity operations
    IStargateRouter public immutable stargateRouter;
    uint256 public immutable poolId;

    // Interest rate model parameters (example values) - increased for testing
    uint256 public immutable baseRate = 0.1e27; // e.g. 10% in RAY = 0.1e27
    uint256 public immutable slope1 = 0.5e27; // e.g. 50% in RAY = 0.5e27
    uint256 public immutable slope2 = 5.0e27; // e.g. 500% in RAY = 5.0e27
    uint256 public immutable kink = 0.8e18; // e.g. 80% utilization in 1e18 = 0.8e18
    uint256 public immutable reserveFactor = 0.1e27; // percent of interest kept (e.g. 10% = 0.1e27)

    constructor(address _stargateRouter, uint256 _poolId, address _usdc) {
        stargateRouter = IStargateRouter(_stargateRouter);
        poolId = _poolId;
        USDC = _usdc;
    }

    uint256 public liquidityIndex = RAY; // 1e27
    uint256 public lastUpdateTimestamp = block.timestamp;
    mapping(address => uint256) public scaledBalance;

    uint256 public totalScaledSupply;
    uint256 public totalDeposits;
    uint256 public totalBorrows;

    function _updateLiquidityIndex() internal {
        console.log("Updating liquidity index");
        uint256 delta = block.timestamp - lastUpdateTimestamp;
        if (delta > 0) {
            console.log("Delta is greater than 0");
            console.log("Total deposits:", totalDeposits);
            console.log("Total borrows:", totalBorrows);

            if (totalDeposits == 0) {
                liquidityIndex = RAY;
                lastUpdateTimestamp = block.timestamp;
                return;
            }

            console.log("About to calculate U");
            uint256 U = (totalBorrows * 1e18) / totalDeposits;
            console.log("U is", U);
            uint256 supplyRate = _calculateSupplyRate(U); // define function to mirror Radiant/Aave dual-slope model
            console.log("Supply rate is", supplyRate);
            uint256 accrued = (supplyRate * delta) / (365 days);
            console.log("Accrued is", accrued);
            liquidityIndex = (liquidityIndex * (RAY + accrued)) / RAY;
            lastUpdateTimestamp = block.timestamp;
        }
    }

    function deposit(uint256 amount) external {
        // Transfer USDC from user to this contract
        bool success = IERC20(USDC).transferFrom(msg.sender, address(this), amount);
        require(success, "USDC transfer failed");

        _updateLiquidityIndex();

        // Mint scaled receipt tokens
        uint256 scaled = (amount * RAY) / liquidityIndex;
        scaledBalance[msg.sender] += scaled;
        totalScaledSupply += scaled;
        totalDeposits += amount;
    }

    function withdraw(uint256 amount) external {
        _updateLiquidityIndex();
        uint256 scaled = (amount * RAY) / liquidityIndex;
        scaledBalance[msg.sender] -= scaled;
        totalScaledSupply -= scaled;
        totalDeposits -= amount;
    }

    // TODO: implement
    function borrow(uint256 amount) external {
        _updateLiquidityIndex();
        totalBorrows += amount;
        //stargateRouter.instantSwapFromPool(...);
    }

    function balanceOf(address user) external view returns (uint256) {
        return (scaledBalance[user] * liquidityIndex) / RAY;
    }

    function _calculateSupplyRate(uint256 U) internal pure returns (uint256) {
        uint256 borrowRate;
        if (U <= kink) {
            borrowRate = baseRate + ((slope1 * U) / kink);
        } else {
            borrowRate = baseRate + slope1 + ((slope2 * (U - kink)) / (1e18 - kink));
        }
        uint256 netRate = (borrowRate * (RAY - reserveFactor)) / RAY;
        return (netRate * U) / RAY;
    }
}
