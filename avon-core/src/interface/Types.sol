// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {AugmentedRedBlackTreeLib} from "../libraries/AugmentedRedBlackTreeLib.sol";

struct TreeState {
    bytes32[] ptrs;
    uint256[] irs;
    uint256[] ltvs;
    AugmentedRedBlackTreeLib.Entry[][] entries;
    uint256[] totalAmounts;
    uint256[] entryCounts;
    uint256 total;
}

struct MatchedOrder {
    address[] counterParty;
    uint256[] amounts;
    uint256 totalMatched;
    uint256 totalCount;
}

struct PreviewMatchedOrder {
    address[] counterParty;
    uint256[] amounts;
    uint256[] irs;
    uint256[] ltvs;
    uint256 totalMatched;
    uint256 totalCount;
}

struct PreviewBorrowParams {
    address borrower;
    uint256 amount;
    uint256 collateralBuffer;
    uint64 rate;
    uint64 ltv;
    bool isMarketOrder;
    bool isCollateral;
}

struct OrderbookConfig {
    address loan_token;
    address collateral_token;
    uint256 creationNonce;
}

struct PoolData {
    address pool;
    uint256 amount;
    uint256 collateral;
}

struct BorrowerLimitOrder {
    uint256 rate;
    uint256 ltv;
    uint256 amount;
    uint256 minAmountExpected;
    uint256 collateralBuffer;
    uint256 collateralAmount;
}
