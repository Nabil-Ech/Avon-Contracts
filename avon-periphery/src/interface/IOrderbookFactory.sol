// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

/**
 * @title IOrderbookFactory
 * @notice Interface for interacting with the Orderbook Factory
 */
interface IOrderbookFactory {
    /**
     * @notice Gets the address of an orderbook for a given loan token and collateral token
     * @param _loanToken The address of the loan token
     * @param _collateralToken The address of the collateral token
     * @return The address of the orderbook
     */
    function getOrderbook(address _loanToken, address _collateralToken) external view returns (address);

    /**
     * @notice Check if an address is a valid pool manager
     * @param _poolManager Address to check
     * @return True if the address is an authorized pool manager
     */
    function isPoolManager(address _poolManager) external view returns (bool);

    function isPoolFactory(address _poolFactory) external view returns (bool);

    /**
     * @notice Get the address that receives protocol fees
     * @return Address of the fee recipient
     */
    function feeRecipient() external view returns (address);

    function owner() external view returns (address);
}
