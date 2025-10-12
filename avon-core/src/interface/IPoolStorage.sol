// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IPoolStorage {
    struct PoolConfig {
        address loanToken;
        address collateralToken;
        address oracle;
        address irm;
        uint64 lltv;
    }

    struct PoolState {
        PoolConfig config;
        address orderBook;
        address poolManager;
        address orderBookFactory;
        uint64 managerFee;
        uint64 protocolFee;
        uint256 poolApy;
        uint256 totalSupplyAssets;
        uint256 totalSupplyShares;
        uint256 totalBorrowAssets;
        uint256 totalBorrowShares;
        uint256 lastUpdate;
    }

    struct Position {
        uint256 borrowShares;
        uint256 collateral;
        uint256 poolBorrowAssets;
        uint256 poolBorrowShares;
        uint256 updatedAt;
    }
}
