// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

/**
 * @title IOrderbook
 * @dev Interface for managing and interacting with orderbook.
 */
interface IOrderbook {
    /**
     * @notice Inserts multiple orders into the orderbook in a batch.
     * @param irs The maximum acceptable interest rates of the orders.
     * @param amounts The amounts of the orders.
     */
    function batchInsertOrder(uint64[] calldata irs, uint256[] calldata amounts) external;

    function newOrderbook() external view returns (address);

    function ORDERBOOK_FACTORY() external view returns (address);

    function owner() external view returns (address);
}
