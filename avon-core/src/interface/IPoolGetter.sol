// SPDX-License-Identifier: Busl-1.1
pragma solidity ^0.8.28;

/**
 * @title IPoolGetter
 * @notice Interface for accessing pool data and position information
 */
interface IPoolGetter {
    struct PoolData {
        uint256 totalSupplyAssets;
        uint256 totalSupplyShares;
        uint256 totalBorrowAssets;
        uint256 totalBorrowShares;
        uint256 lastUpdate;
    }

    struct BorrowPosition {
        uint256 borrowAssets;
        uint256 borrowShares;
        uint256 collateral;
    }
}
