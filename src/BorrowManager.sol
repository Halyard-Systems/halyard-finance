// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./DepositManager.sol";
import {IPyth} from "../node_modules/@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "../node_modules/@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

contract BorrowManager {
    DepositManager public immutable depositMgr;
    IPyth public immutable pyth;

    // Mapping to track user borrow principal in scaled form
    mapping(bytes32 => mapping(address => uint256)) public userBorrowScaled;
    mapping(bytes32 => uint256) public totalBorrowScaled;
    mapping(bytes32 => uint256) public borrowIndex; // scale: RAY
    mapping(bytes32 => uint256) public lastPythUpdateTime;

    address public owner;
    uint256 public ltv;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    event Borrowed(
        bytes32 indexed tokenId,
        address indexed user,
        uint256 amount,
        uint256 collateralValueUsd
    );
    event Repaid(bytes32 indexed tokenId, address indexed user, uint256 amount);

    error PriceStale();
    error InsufficientCollateral();

    constructor(address _depositMgr, address _pyth) {
        depositMgr = DepositManager(payable(_depositMgr));
        pyth = IPyth(_pyth);
        owner = msg.sender;
        ltv = 0.50e18;
    }

    function setLtv(uint256 _ltv) external onlyOwner {
        require(_ltv <= 1e18, "LTV must be <= 100%");
        ltv = _ltv;
    }

    function getLtv() public view returns (uint256) {
        return ltv;
    }

    // Called when a user borrows; updates Pyth only for this asset
    function borrow(
        bytes32 tokenId,
        uint256 amount,
        bytes[] calldata pythUpdateData,
        bytes32[] calldata priceIds
    ) external payable {
        // Pull latest price updates for all relevant assets
        uint fee = pyth.getUpdateFee(pythUpdateData);
        pyth.updatePriceFeeds{value: fee}(pythUpdateData);

        bytes32[] memory tokens = depositMgr.getSupportedTokens();
        require(tokens.length == priceIds.length, "Mismatched tokens/prices");

        // Update borrow index and accrue interest for this asset
        _updateBorrowIndex(tokenId);

        // Scale new borrow
        uint256 scaledDelta = (amount * depositMgr.RAY()) /
            borrowIndex[tokenId];
        userBorrowScaled[tokenId][msg.sender] += scaledDelta;
        totalBorrowScaled[tokenId] += scaledDelta;
        depositMgr.incrementTotalBorrows(tokenId, amount);

        // Calculate new LTV after this borrow
        uint256 totalCollateralUsd = 0;
        uint256 totalBorrowUsd = 0;
        for (uint i = 0; i < tokens.length; i++) {
            bytes32 tid = tokens[i];
            PythStructs.Price memory price = pyth.getPriceNoOlderThan(
                priceIds[i],
                60
            );
            require(price.price >= 0, "Negative price");
            uint256 priceUint = uint256(uint64(price.price));

            // Collateral
            uint256 deposit = depositMgr.balanceOf(tid, msg.sender);
            totalCollateralUsd += (deposit * priceUint) / 1e8;

            // Borrow
            uint256 scaledBorrow = userBorrowScaled[tid][msg.sender];
            uint256 userBorrowAmount = (scaledBorrow * borrowIndex[tid]) /
                depositMgr.RAY();
            totalBorrowUsd += (userBorrowAmount * priceUint) / 1e8;
        }
        require(totalCollateralUsd > 0, "No collateral");
        uint256 userLtv = (totalBorrowUsd * 1e18) / totalCollateralUsd;
        require(userLtv <= getLtv(), "Insufficient collateral");

        // Transfer borrowed tokens
        depositMgr.transferOut(tokenId, msg.sender, amount);
        emit Borrowed(tokenId, msg.sender, amount, totalCollateralUsd);
    }

    // Repay borrowed tokens
    function repay(bytes32 tokenId, uint256 amount) external payable {
        // Accrue interest
        _updateBorrowIndex(tokenId);
        // Calculate scaled repayment
        uint256 scaledRepay = (amount * depositMgr.RAY()) /
            borrowIndex[tokenId];
        uint256 userScaled = userBorrowScaled[tokenId][msg.sender];
        require(scaledRepay <= userScaled, "Repay exceeds borrow");
        userBorrowScaled[tokenId][msg.sender] -= scaledRepay;
        totalBorrowScaled[tokenId] -= scaledRepay;
        depositMgr.decrementTotalBorrows(tokenId, amount);
        // Transfer tokens from user to protocol
        depositMgr.transferIn{value: msg.value}(tokenId, msg.sender, amount);
        emit Repaid(tokenId, msg.sender, amount);
    }

    function _updateBorrowIndex(bytes32 tokenId) internal {
        DepositManager.Asset memory cfg = depositMgr.getAsset(tokenId);
        uint256 delta = block.timestamp - cfg.lastUpdateTimestamp;
        if (delta == 0) return;
        uint256 U = (cfg.totalBorrows * 1e18) / cfg.totalDeposits;
        uint256 borrowRate = depositMgr.calculateBorrowRate(tokenId, U);
        borrowIndex[tokenId] =
            (borrowIndex[tokenId] *
                (depositMgr.RAY() + (borrowRate * delta) / 365 days)) /
            depositMgr.RAY();
        depositMgr.setLastBorrowTime(tokenId, block.timestamp);
    }

    // Calculate user's Loan-to-Value (LTV) ratio across all supported tokens
    // function getUserLtv(
    //     address user,
    //     bytes[] calldata pythUpdateData,
    //     bytes32[] calldata priceIds
    // ) external returns (uint256 userLtv) {
    //     // 1. Update all prices
    //     uint fee = pyth.getUpdateFee(pythUpdateData);
    //     pyth.updatePriceFeeds{value: fee}(pythUpdateData);

    //     bytes32[] memory tokens = depositMgr.getSupportedTokens();
    //     require(tokens.length == priceIds.length, "Mismatched tokens/prices");

    //     uint256 totalCollateralUsd = 0;
    //     uint256 totalBorrowUsd = 0;

    //     for (uint i = 0; i < tokens.length; i++) {
    //         bytes32 tokenId = tokens[i];
    //         PythStructs.Price memory price = pyth.getPriceNoOlderThan(
    //             priceIds[i],
    //             60
    //         );
    //         require(price.price >= 0, "Negative price");
    //         uint256 priceUint = uint256(uint64(price.price));

    //         // Collateral
    //         uint256 deposit = depositMgr.balanceOf(tokenId, user);
    //         totalCollateralUsd += (deposit * priceUint) / 1e8;

    //         // Borrow
    //         uint256 scaledBorrow = userBorrowScaled[tokenId][user];
    //         uint256 userBorrowAmount = (scaledBorrow * borrowIndex[tokenId]) /
    //             depositMgr.RAY();
    //         totalBorrowUsd += (userBorrowAmount * priceUint) / 1e8;
    //     }

    //     if (totalCollateralUsd == 0) return 0;
    //     ltv = (totalBorrowUsd * 1e18) / totalCollateralUsd;
    // }

    receive() external payable {}
}
