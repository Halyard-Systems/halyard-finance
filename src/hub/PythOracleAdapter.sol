// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IPyth} from "../../lib/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "../../lib/pyth-sdk-solidity/PythStructs.sol";
import {IOracle} from "../interfaces/IOracle.sol";

/// @title PythOracleAdapter
/// @notice Wraps the on-chain Pyth contract to implement IOracle for RiskEngine.
///         Maps ERC-20 asset addresses to Pyth feed IDs, enforces staleness and
///         confidence checks, and normalizes prices to 1e18.
contract PythOracleAdapter is IOracle, AccessManaged {
    // --- Errors ---
    error InvalidAddress();
    error InvalidStaleness();
    error FeedNotSet(address asset);
    error NegativePrice(address asset);
    error ConfidenceTooWide(address asset, uint64 conf, int64 price);
    error ExponentTooLarge(int32 expo);
    error RefundFailed();

    // --- Events ---
    event FeedIdSet(address indexed asset, bytes32 feedId);
    event MaxStalenessSet(uint256 maxStaleness);
    event MaxConfidenceRatioBpsSet(uint256 maxConfidenceRatioBps);

    // --- Storage ---
    IPyth public immutable pyth;
    mapping(address => bytes32) public feedIds;
    uint256 public maxStaleness;
    uint256 public maxConfidenceRatioBps;

    constructor(address _authority, address _pyth, uint256 _maxStaleness) AccessManaged(_authority) {
        if (_pyth == address(0)) revert InvalidAddress();
        if (_maxStaleness == 0) revert InvalidStaleness();
        pyth = IPyth(_pyth);
        maxStaleness = _maxStaleness;
    }

    // --- Admin ---

    function setFeedId(address asset, bytes32 feedId) external restricted {
        if (asset == address(0)) revert InvalidAddress();
        feedIds[asset] = feedId;
        emit FeedIdSet(asset, feedId);
    }

    function setMaxStaleness(uint256 _maxStaleness) external restricted {
        if (_maxStaleness == 0) revert InvalidStaleness();
        maxStaleness = _maxStaleness;
        emit MaxStalenessSet(_maxStaleness);
    }

    function setMaxConfidenceRatioBps(uint256 _maxConfidenceRatioBps) external restricted {
        maxConfidenceRatioBps = _maxConfidenceRatioBps;
        emit MaxConfidenceRatioBpsSet(_maxConfidenceRatioBps);
    }

    // --- IOracle ---

    function getPriceE18(address asset) external view override returns (uint256 priceE18, uint256 lastUpdatedAt) {
        bytes32 feedId = feedIds[asset];
        if (feedId == bytes32(0)) revert FeedNotSet(asset);

        PythStructs.Price memory p = pyth.getPriceNoOlderThan(feedId, maxStaleness);

        if (p.price <= 0) revert NegativePrice(asset);

        // Confidence check
        if (maxConfidenceRatioBps > 0) {
            if ((uint256(p.conf) * 10_000) / uint64(p.price) > maxConfidenceRatioBps) {
                revert ConfidenceTooWide(asset, p.conf, p.price);
            }
        }

        if (p.expo > 59 || p.expo < -18) revert ExponentTooLarge(p.expo);

        // Normalize to 1e18
        uint256 rawPrice = uint256(uint64(p.price));
        if (p.expo >= 0) {
            priceE18 = rawPrice * 10 ** (18 + uint32(p.expo));
        } else {
            priceE18 = (rawPrice * 1e18) / 10 ** uint32(-p.expo);
        }

        lastUpdatedAt = p.publishTime;
    }

    // --- Pyth passthroughs ---

    function updatePriceFeeds(bytes[] calldata updateData) external payable {
        uint256 fee = pyth.getUpdateFee(updateData);
        pyth.updatePriceFeeds{value: fee}(updateData);
        if (msg.value > fee) {
            (bool ok,) = msg.sender.call{value: msg.value - fee}("");
            if (!ok) revert RefundFailed();
        }
    }

    function getUpdateFee(bytes[] calldata updateData) external view returns (uint256) {
        return pyth.getUpdateFee(updateData);
    }
}
