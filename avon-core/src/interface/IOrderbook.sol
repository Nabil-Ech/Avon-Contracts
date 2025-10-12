// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {TreeState, PreviewMatchedOrder, BorrowerLimitOrder, PreviewBorrowParams} from "../interface/Types.sol";

/**
 * @title IOrderbook
 * @dev Interface for managing and interacting with an orderbook instance.
 */
interface IOrderbook {
    // ===== Pool management =====
    /**
     * @notice Whitelists a pool for orderbook operations
     * @param pool The address of the pool to whitelist
     * @param poolFactory The address of the factory that created the pool
     */
    function whitelistPool(address pool, address poolFactory) external;

    /**
     * @notice Removes a pool from the whitelist and cancels its orders
     * @param pool The address of the pool to remove
     */
    function removePool(address pool) external;

    /**
     * @notice Forcefully removes a pool from the whitelist and cancels its orders
     * @param pool The address of the pool to remove
     * @param ltv The pool's current LTV, used to locate and cancel its orders
     */
    function forceRemovePool(address pool, uint64 ltv) external;

    /**
     * @notice Returns all whitelisted pool addresses
     */
    function getAllPools() external view returns (address[] memory);

    // ===== Configuration =====
    /**
     * @notice Sets the fee recipient address
     * @param _feeRecipient Address that will receive matching fees
     */
    function setFeeRecipient(address _feeRecipient) external;

    /**
     * @notice Sets the flat matching fee amount, denominated in collateral token
     * @param _flatMatchingFee Flat fee amount charged on matches
     */
    function setFlatMatchingFee(uint256 _flatMatchingFee) external;

    /**
     * @notice Sets the address of a successor orderbook (for migrations)
     * @param _newOrderbook Address of the new orderbook
     */
    function setNewOrderbook(address _newOrderbook) external;

    // ===== Orders (pools) =====
    /**
     * @notice Batch insert lender orders from a pool
     * @param irs Array of interest rates for each order (yearly rate per second)
     * @param amounts Array of token amounts for each order
     */
    function batchInsertOrder(uint64[] calldata irs, uint256[] calldata amounts) external;

    // ===== Orders (borrowers) =====
    /**
     * @notice Creates a limit borrow order
     */
    function insertLimitBorrowOrder(
        uint64 rate,
        uint64 ltv,
        uint256 amount,
        uint256 minAmountExpected,
        uint256 collateralBuffer,
        uint256 collateralAmount
    ) external;

    /**
     * @notice Matches a market borrow order at the best available terms
     */
    function matchMarketBorrowOrder(
        uint256 amount,
        uint256 minAmountExpected,
        uint256 collateralBuffer,
        uint64 ltv,
        uint64 rate
    ) external;

    /**
     * @notice Matches the specified borrower limit order
     */
    function matchLimitBorrowOrder(address borrower, uint256 index) external;

    /**
     * @notice Cancels a limit borrow order fully or partially
     */
    function cancelBorrowOrder(uint256 rate, uint256 ltv, uint256 amount, uint256 index) external;

    // ===== Views =====
    /**
     * @notice Simulates a borrow operation without executing it
     */
    function previewBorrow(PreviewBorrowParams memory previewBorrowParams)
        external
        view
        returns (
            PreviewMatchedOrder memory previewMatchedOrders,
            uint256 loanTokenAmount,
            uint256 collateralRequired,
            uint256 amountLeft
        );

    /**
     * @notice Retrieves all active limit orders for a borrower
     * @param borrower The address of the borrower to query
     * @return borrowerLimitOrder Array of the borrower's active limit orders
     */
    function getBorrowerOrders(address borrower)
        external
        view
        returns (BorrowerLimitOrder[] memory borrowerLimitOrder);

    /**
     * @notice Returns a paginated snapshot of the orderbook tree
     */
    function getTreeState(bool isLender, uint256 offset, uint256 limit)
        external
        view
        returns (TreeState memory state);

    /**
     * @notice Returns the address of the contract owner
     * @return The address of the current owner
     */
    function owner() external view returns (address);
}
