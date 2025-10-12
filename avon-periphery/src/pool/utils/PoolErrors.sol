// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @title PoolErrors
/// @author Avon Labs
/// @notice Library exposing error messages.
library PoolErrors {
    /// @notice Thrown when the value is already set.
    error AlreadySet();

    /// @notice Thrown when not exactly one of the input amount is zero.
    error InconsistentInput();

    /// @notice Thrown when zero assets is passed as input.
    error ZeroAssets();

    /// @notice Thrown when zero shares is passed as input.
    error ZeroShares();

    /// @notice Thrown when a zero address is passed as input.
    error ZeroAddress();

    /// @notice Thrown when the caller is not authorized to conduct an action.
    error Unauthorized();

    /// @notice Thrown when the collateral is insufficient to `borrow` or `withdrawCollateral`.
    error InsufficientCollateral();

    /// @notice Thrown when the liquidity is insufficient to `withdraw` or `borrow`.
    error InsufficientLiquidity();

    /// @notice Thrown when the position to liquidate is healthy.
    error HealthyPosition();

    /// @notice Thrown when the input is invalid.
    error InvalidInput();

    /// @notice Thrown when extreme slippage is detected.
    error InsufficientAmountReceived();

    /// @notice Thrown when the borrow amount is too small.
    error AccrueInterestIsMoreThanNewBorrow();

    /// @notice When the liquidation fails due to insufficient seized assets or repaid shares.
    error LiquidationFailed();

    /// @notice Thrown when the execution of a scheduled task fails.
    error ExecutionFailed();

    /// @notice Thrown when accrue interest is called too early.
    error NotEnoughTimePassed();

    /// @notice Thrown when attempting regular liquidation within auction priority window without auction bonus.
    /// @dev This ensures auction liquidations get priority when position is barely unhealthy.
    error NonAuctionLiquidationWithinAuctionPriorityWindow();

    /// @notice Thrown when deposit cap is exceeded.
    error DepositCapExceeded();

    /// @notice Thrown when borrow cap is exceeded.
    error BorrowCapExceeded();
}
