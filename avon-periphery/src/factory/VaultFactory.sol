// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Vault} from "../vault/Vault.sol";
import {IOrderbookFactory} from "../interface/IOrderbookFactory.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title VaultFactory
 * @notice Factory contract for deploying and tracking Vault contracts
 */
contract VaultFactory is Ownable2Step {
    // State variables
    address public immutable orderbookFactory;

    // Mapping to track valid vaults deployed by this factory
    mapping(address => bool) public isValidVault;

    // Events
    event VaultCreated(address indexed vault, address indexed token, address indexed vaultManager);

    /**
     * @notice Constructor sets the OrderbookFactory address
     * @param _orderbookFactory Address of the OrderbookFactory contract
     */
    constructor(address _orderbookFactory) Ownable(msg.sender) {
        orderbookFactory = _orderbookFactory;
    }

    /**
     * @notice Deploys a new Vault contract
     * @param token Token to be used in the vault
     * @param vaultManager Address of the pool manager
     * @return vault Address of the newly created vault
     */
    function deployVault(address token, address vaultManager, address feeRecipient, uint256 managerFees)
        external
        returns (address vault)
    {
        // Verify the caller is an approved vault manager
        if (!IOrderbookFactory(orderbookFactory).isPoolManager(msg.sender)) {
            revert("Unauthorized");
        }

        if (token == address(0) || vaultManager == address(0)) revert("Invalid input");

        address owner = IOrderbookFactory(orderbookFactory).owner();

        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](2);
        proposers[0] = owner;
        executors[0] = owner;
        executors[1] = msg.sender; // Pool manager

        // Deploy the new vault
        vault = address(
            new Vault(
                token,
                vaultManager,
                orderbookFactory,
                feeRecipient,
                managerFees,
                proposers,
                executors,
                IOrderbookFactory(orderbookFactory).owner()
            )
        );

        // Mark the vault as valid
        isValidVault[vault] = true;

        // Emit vault creation event
        emit VaultCreated(vault, token, vaultManager);
    }

    /**
     * @notice Checks if an address is a valid vault deployed by this factory
     * @param vault Address to check
     * @return True if the address is a valid vault
     */
    function validateVault(address vault) external view returns (bool) {
        return isValidVault[vault];
    }
}
