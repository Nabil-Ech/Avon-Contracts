// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

library PoolConstants {
    uint16 constant QUOTE_SUGGESTIONS = 10;
    uint64 constant WAD = 1e18;
    uint256 constant ORACLE_PRICE_SCALE = 1e36;
    uint256 constant ACCRUAL_INTERVAL = 12 hours;

    /// Time lock durations
    uint64 constant MIN_TIMELOCK_DURATION = 1 days;
    uint64 constant DEFAULT_TIMELOCK_DURATION = 2 days;
    uint64 constant MAX_TIMELOCK_DURATION = 7 days;

    /// Fee constants
    uint64 constant DEFAULT_PROTOCOL_FEE = 0.05e18;
    uint64 constant MAX_PROTOCOL_FEE = 0.1e18;
    uint64 constant MAX_TOTAL_FEE = 0.25e18;
    uint64 constant PROTOCOL_FLASH_LOAN_FEE = 0.3e18;
    uint64 constant MAX_PROTOCOL_FLASH_LOAN_FEE = 0.5e18;

    /// Flash loan fee constants
    uint64 constant DEFAULT_FLASH_LOAN_FEE = 0;
    uint64 constant MAX_FLASH_LOAN_FEE = 0.01e18; // 1%

    /// Loan-to-Value (LTV) constants
    uint64 constant MIN_LTV = 0.5e18;
    uint64 constant MAX_LTV = 0.99e18;
    uint64 constant MAX_UTILIZATION = 1e18;

    /// Liquidation constants
    uint256 public constant MIN_LIQ_BONUS = 1.03e18;
    uint256 public constant MAX_LIQ_BONUS = 1.15e18;
    uint256 public constant MIN_SOFT_RANGE = 0.03e18;
    uint256 public constant MAX_SOFT_RANGE = 0.07e18;
    uint256 public constant MIN_SOFT_SEIZE_CAP = 0.1e18;
    uint256 public constant MAX_SOFT_SEIZE_CAP = 0.5e18;
    uint256 public constant MAX_SOFT_RANGE_LIQ_BONUS = 1.1e18;

    /// @notice Maximum auction priority window size in basis points
    /// @dev Pools can configure their auction priority window from 0 up to this maximum.
    ///      A window of 0 means that auctions are not provided any liquidation threshold priority.
    ///      The window gives auction services exclusive access to liquidations within the health
    ///      score range of (1 − window, 1), designed for capturing interest-triggered liquidations.
    uint256 public constant MAX_AUCTION_PRIORITY_WINDOW = 0.001e18; // 10 bps maximum
}
