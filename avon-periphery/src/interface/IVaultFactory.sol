// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

/**
 * @title IVaultFactory
 * @notice Interface for interacting with the Vault Factory
 */
interface IVaultFactory {
    /**
     * @notice Deploys a new Vault contract
     * @param token Token to be used in the vault
     * @param poolManager Address of the pool manager
     * @return vault Address of the newly created vault
     */
    function deployVault(address token, address poolManager) external returns (address vault);

    /**
     * @notice Checks if an address is a valid vault deployed by this factory
     * @param vault Address to check
     * @return True if the address is a valid vault
     */
    function isValidVault(address vault) external view returns (bool);

    /**
     * @notice Gets the address of the Orderbook Factory
     * @return Address of the Orderbook Factory
     */
    function orderbookFactory() external view returns (address);
}
