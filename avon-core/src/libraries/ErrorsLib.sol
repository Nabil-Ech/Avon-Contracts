// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

/// @title ErrorsLib
/// @author Avon Labs
/// @notice Library defining standardized error types used throughout the protocol
library ErrorsLib {
    // --------------------- General Errors ---------------------

    /// @notice Thrown when an input value is invalid or doesn't meet requirements
    error InvalidInput();

    /// @notice Thrown when a zero address is passed where a non-zero address is required
    error ZeroAddress();

    /// @notice Thrown when the caller is not authorized to perform an action
    error Unauthorized();

    /// @notice Thrown when an external call fails
    error CallFailed();

    /// @notice Thrown when a value has already been set to the same value
    error AlreadySet();

    /// @notice Thrown when an invalid function selector is provided
    error InvalidSelector();

    /// @notice Thrown when a function is called in an invalid state
    error NotKeeper();

    /// @notice Thrown when borrower orders are not found while canceling
    error OrderNotFound();

    /// @notice Thrown when there is not enough collateral for a borrow
    error NotEnoughCollateral();

    // --------------------- Asset-Related Errors ---------------------

    /// @notice Thrown when zero assets are provided where non-zero assets are required
    error ZeroAssets();

    /// @notice Thrown when zero shares are provided where non-zero shares are required
    error ZeroShares();

    /// @notice Thrown when order inputs are inconsistent (e.g., mismatched array lengths)
    error InconsistentInput();

    /// @notice Thrown when the received amount is less than the minimum expected
    error InsufficientAmountReceived();

    // --------------------- Pool-Related Errors ---------------------

    /// @notice Thrown when a pool factory is not found
    error NotPoolFactory();

    /// @notice Thrown when a pool is not from the expected factory
    error NotValidPool();

    /// @notice Thrown when an operation is attempted by a non-pool-manager
    error NotPoolManager();

    /// @notice Thrown when the IRM is not enabled for pool creation
    error IRMNotEnabled();

    /// @notice Thrown when pool is not whitelisted
    error NotWhitelisted();

    // --------------------- Orderbook-Related Errors ---------------------

    /// @notice Thrown when attempting to create an orderbook that already exists
    error OrderbookAlreadyExists();

    /// @notice Thrown when an orderbook cannot be found
    error OrderbookNotFound();

    error OrdersNotOrdered();

    // --------------------- Order-Related Errors ---------------------

    /// @notice Thrown when no orders are found for a given user
    error NoOrders();

    /// @notice Thrown when a user attempts to exceed the maximum number of allowed orders
    error MaxOrdersLimit();

    /// @notice Thrown when no matching orders are found
    error NoMatch();

    /// @notice Thrown when the collateral required exceeds the amount provided
    error OrderCollateralExceedsAmount();
}
