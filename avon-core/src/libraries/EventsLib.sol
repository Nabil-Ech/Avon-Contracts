// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title EventsLib
/// @author Avon Labs
/// @notice Library exposing standardized events used throughout the protocol
library EventsLib {
    // --------------------- Admin Events ---------------------

    /// @notice Emitted when an Interest Rate Model (IRM) status is changes
    /// @param irm The address of the IRM that was enabled or disabled
    /// @param status True if the IRM is enabled, false if disabled
    event SetIrm(address indexed irm, bool status);

    /// @notice Emitted when a pool manager status is updated
    /// @param manager The address of the pool manager
    /// @param status True if manager is being added, false if removed
    event PoolManagerSet(address indexed manager, bool status);

    /// @notice Emitted when a pool factory is set
    /// @param poolFactory The address of the pool factory
    /// @param status True if the pool factory is being added, false if removed
    event PoolFactorySet(address indexed poolFactory, bool status);

    /// @notice Emitted when the fee recipient address is updated
    /// @param newFeeRecipient The address of the new fee recipient
    event SetFeeRecipient(address indexed newFeeRecipient);

    /// @notice Emitted when the matching keeper address is updated
    /// @param newKeeper The address of the new matching keeper
    /// @param status True if the keeper is being added, false if removed
    event SetKeeper(address indexed newKeeper, bool status);

    /// @notice Emitted when a new orderbook is set
    /// @param newOrderbook The address of the new orderbook
    /// @dev This event is emitted when the orderbook is updated, allowing external systems to
    /// track changes to the orderbook address.
    event NewOrderbookSet(address indexed newOrderbook);

    /// @notice Emitted when fee recipient is set
    /// @param feeRecipient The address of the fee recipient
    /// @dev This event is emitted when the fee recipient is set
    event FeeRecipientSet(address indexed feeRecipient);

    /// @notice Emitted when the flat matching fee is set
    /// @param flatMatchingFee The new flat matching fee amount
    /// @dev This event is emitted when the flat matching fee is updated
    event FlatMatchingFeeSet(uint256 flatMatchingFee);

    /// @notice Emitted when matching fee is collected
    /// @param borrower The address of the borrower who paid the fee
    /// @param feeRecipient The address of the recipient of the matching fee
    /// @param flatMatchingFee The amount of the matching fee collected
    /// @dev This event is emitted when a matching fee is collected during the order matching process
    event MatchingFeeCollected(address indexed borrower, address indexed feeRecipient, uint256 flatMatchingFee);

    // --------------------- Orderbook Events ---------------------

    /// @notice Emitted when a new orderbook is created
    /// @param loanToken The address of the loan token
    /// @param collateralToken The address of the collateral token
    /// @param orderbook The address of the created orderbook
    event OrderbookCreated(address indexed loanToken, address indexed collateralToken, address orderbook);

    /// @notice Emitted when a new order is inserted into the orderbook
    /// @param isLender True if order is from a lender, false if from a borrower
    /// @param maker The address of the order maker
    /// @param rate The interest rate of the order
    /// @param ltv The loan-to-value ratio of the order
    /// @param amount The amount of the order
    event OrderInserted(bool indexed isLender, address indexed maker, uint256 rate, uint256 ltv, uint256 amount);

    /// @notice Emitted when an order is matched between a lender and a borrower
    /// @param lender The address of the lender providing funds
    /// @param borrower The address of the borrower receiving funds
    /// @param rate The interest rate of the matched order
    /// @param ltv The loan-to-value ratio of the matched order
    /// @param amount The amount of the matched order
    event OrderMatched(address indexed lender, address indexed borrower, uint256 rate, uint256 ltv, uint256 amount);

    /// @notice Emitted when an order is canceled by its maker
    /// @param isLender True if canceled order was from a lender, false if from a borrower
    /// @param maker The address of the order maker
    /// @param rate The interest rate of the canceled order
    /// @param ltv The loan-to-value ratio of the canceled order
    /// @param amount The amount of the canceled order
    event OrderCanceled(bool indexed isLender, address indexed maker, uint256 rate, uint256 ltv, uint256 amount);

    /// @notice Emitted when a borrower cancels their limit order
    /// @param borrower The address of the borrower canceling the order
    /// @param rate The interest rate of the canceled order
    /// @param ltv The loan-to-value ratio of the canceled order
    /// @param amount The amount of the canceled order
    event BorrowOrderCanceled(address indexed borrower, uint256 rate, uint256 ltv, uint256 amount);

    /// @notice Emitted when a borrower places a new limit order
    /// @param borrower The address of the borrower placing the order
    /// @param rate The maximum interest rate the borrower is willing to pay
    /// @param ltv The loan-to-value ratio requested by the borrower
    /// @param amount The loan amount requested by the borrower
    /// @param minAmountExpected The minimum amount the borrower expects to receive
    event BorrowOrderPlaced(
        address indexed borrower, uint256 rate, uint256 ltv, uint256 amount, uint256 minAmountExpected
    );

    /// @notice Emitted when a pool is created
    /// @param pool The address of the created pool
    event PoolWhitelisted(address indexed pool);

    /// @notice Emitted when a pool is removed from the whitelist
    /// @param pool The address of the removed pool
    event PoolRemoved(address indexed pool);
}
