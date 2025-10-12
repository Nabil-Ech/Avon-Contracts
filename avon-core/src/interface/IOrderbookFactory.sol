// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

/**
 * @title IOrderbookFactory
 * @notice Interface for the OrderbookFactory contract
 * @dev This interface defines the functions for interacting with the OrderbookFactory contract
 */
interface IOrderbookFactory {
    /**
     * @notice Checks if the Interest Rate Model (IRM) is enabled for a given address
     * @param _address The address to check
     * @return True if the IRM is enabled, false otherwise
     */
    function isIRMEnabled(address _address) external view returns (bool);

    /**
     * @notice Gets the address of the fee recipient
     * @return The address of the fee recipient
     */
    function feeRecipient() external view returns (address);

    /**
     * @notice Gets the address of the matching keeper
     * @return The address of the matching keeper
     */
    function isKeeper(address _keeper) external view returns (bool);

    /**
     * @notice Sets the address of the fee recipient
     * @param _feeRecipient The new address of the fee recipient
     */
    function setFeeRecipient(address _feeRecipient) external;

    /**
     * @notice Creates a new orderbook
     * @param _loanToken The address of the loan token
     * @param _collateralToken The address of the collateral token
     * @param _poolMakers The addresses of the pool makers
     * @return The address of the newly created orderbook
     */
    function createOrderbook(address _loanToken, address _collateralToken, address[] memory _poolMakers)
        external
        returns (address);

    /**
     * @notice Gets the address of an orderbook for a given loan token and collateral token
     * @param _loanToken The address of the loan token
     * @param _collateralToken The address of the collateral token
     * @return The address of the orderbook
     */
    function getOrderbook(address _loanToken, address _collateralToken) external view returns (address);

    /**
     * @notice Gets the addresses of all orderbooks
     * @return An array of addresses of all orderbooks
     */
    function getAllOrderbooks() external view returns (address[] memory);

    function isPoolManager(address _poolManager) external view returns (bool);
    function isPoolFactory(address _poolFactory) external view returns (bool);
}
