// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./interfaces/IStargateRouter.sol";

contract DepositManager {
    uint256 public constant RAY = 1e27;

    // Stargate router for liquidity operations
    IStargateRouter public immutable stargateRouter;
    uint256 public immutable poolId;

    // Interest rate model parameters (example values)
    uint256 public immutable baseRate = 0.02e27; // e.g. 2% in RAY = 0.02e27
    uint256 public immutable slope1 = 0.1e27; // e.g. 10% in RAY = 0.10e27
    uint256 public immutable slope2 = 3.0e27; // e.g. 300% in RAY = 3.0e27
    uint256 public immutable kink = 0.8e18; // e.g. 80% utilization in 1e18 = 0.8e18
    uint256 public immutable reserveFactor = 0.1e27; // percent of interest kept (e.g. 10% = 0.1e27)

    constructor(address _stargateRouter, uint256 _poolId) {
        stargateRouter = IStargateRouter(_stargateRouter);
        poolId = _poolId;
    }

    uint256 public liquidityIndex = RAY; // 1e27
    uint256 public lastUpdateTimestamp = block.timestamp;
    mapping(address => uint256) public scaledBalance;

    uint256 public totalScaledSupply;
    uint256 public totalDeposits;
    uint256 public totalBorrows;

    function _updateLiquidityIndex() internal {
        uint256 delta = block.timestamp - lastUpdateTimestamp;
        if (delta > 0) {
            uint256 U = (totalBorrows * 1e18) / totalDeposits;
            uint256 supplyRate = _calculateSupplyRate(U); // define function to mirror Radiant/Aave dual-slope model
            uint256 accrued = (supplyRate * delta) / (365 days);
            liquidityIndex = (liquidityIndex * (RAY + accrued)) / RAY;
            lastUpdateTimestamp = block.timestamp;
        }
    }

    function deposit(uint256 amount) external {
        _updateLiquidityIndex();
        stargateRouter.addLiquidity(poolId, amount, address(this));
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
        //stargateRouter.instantRedeemLocal(...);
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
            borrowRate = baseRate + slope1 + ((slope2 * (U - kink)) / (RAY - kink));
        }
        uint256 netRate = (borrowRate * (RAY - reserveFactor)) / RAY;
        return (netRate * U) / RAY;
    }
}
