// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {OrderbookFactoryStorage} from "./OrderbookFactoryStorage.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import {Orderbook} from "./Orderbook.sol";

/// @title OrderbookFactory
/// @author Avon Labs
/// @notice This contract is used to create and manage orderbooks.
/// @dev Manages the lifecycle of orderbooks and controls which Interest Rate Models (IRMs) are enabled and which addresses are designated as pool managers, factories, and keepers.
contract OrderbookFactory is Ownable2Step {
    using OrderbookFactoryStorage for OrderbookFactoryStorage.FactoryState;

    constructor(address _feeRecipient) Ownable(msg.sender) {
        OrderbookFactoryStorage.initialize(_feeRecipient);
    }

    /// @notice Enables an Interest Rate Model (IRM) for use in the protocol
    /// @dev IRMs determine how interest rates are calculated for loans.
    ///      If an IRM is disabled (i.e., setIrm(irm, false)), all pools
    ///      associated with that IRM must be manually removed or forcefully removed.
    /// @param irm The address of the IRM contract to enable
    function setIrm(address irm, bool status) external onlyOwner {
        OrderbookFactoryStorage.FactoryState storage s = OrderbookFactoryStorage._state();
        if (irm == address(0)) revert ErrorsLib.InvalidInput();
        if (s.isIRMEnabled[irm] == status) revert ErrorsLib.AlreadySet();
        s.isIRMEnabled[irm] = status;
        emit EventsLib.SetIrm(irm, status);
    }

    /// @notice Sets the fee recipient address
    /// @param newFeeRecipient The address of the new fee recipient
    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        OrderbookFactoryStorage.FactoryState storage s = OrderbookFactoryStorage._state();
        if (newFeeRecipient == address(0)) revert ErrorsLib.InvalidInput();
        if (newFeeRecipient == s.feeRecipient) revert ErrorsLib.AlreadySet();
        s.feeRecipient = newFeeRecipient;
        emit EventsLib.SetFeeRecipient(newFeeRecipient);
    }

    /// @notice Sets the status of a pool manager
    /// @param manager The address of the manager
    /// @param status The status to set for the manager
    /// @dev Only owner can distribute pool manager status
    function setPoolManager(address manager, bool status) external onlyOwner {
        if (manager == address(0)) revert ErrorsLib.ZeroAddress();
        OrderbookFactoryStorage._state().isPoolManager[manager] = status;
        emit EventsLib.PoolManagerSet(manager, status);
    }

    /// @notice Sets the status of a pool factory
    /// @param factory The address of the factory
    /// @param status The status to set for the factory
    /// @dev Only owner can distribute pool factory status
    function setPoolFactory(address factory, bool status) external onlyOwner {
        // maybe check that the factry is a contract ?
        if (factory == address(0)) revert ErrorsLib.ZeroAddress();
        OrderbookFactoryStorage._state().isPoolFactory[factory] = status;
        emit EventsLib.PoolFactorySet(factory, status);
    }

    /// @notice Grants or revokes keeper permissions
    /// @param newKeeper The address to update
    /// @param status True to grant keeper status, false to revoke
    function setKeeper(address newKeeper, bool status) external onlyOwner {
        OrderbookFactoryStorage.FactoryState storage s = OrderbookFactoryStorage._state();
        if (newKeeper == address(0)) revert ErrorsLib.InvalidInput();
        if (s.isKeeper[newKeeper] == status) revert ErrorsLib.AlreadySet();
        s.isKeeper[newKeeper] = status;
        emit EventsLib.SetKeeper(newKeeper, status);
    }

    /// @notice Creates a new orderbook
    /// @param _loanToken The address of the loan token
    /// @param _collateralToken The address of the collateral token
    /// @return orderbookAddress The address of the newly created orderbook
    /// @dev This function creates a new orderbook and stores its address in the mapping
    /// There can be only one orderbook for each unique combination of loanToken and collateralToken
    function createOrderbook(address _loanToken, address _collateralToken, address _feeRecipient)
        external
        onlyOwner
        returns (address orderbookAddress)
    {
        if (_loanToken == address(0) || _collateralToken == address(0) || _feeRecipient == address(0)) {
            revert ErrorsLib.InvalidInput();
        }

        OrderbookFactoryStorage.FactoryState storage s = OrderbookFactoryStorage._state();
        // what if tokens are reversed ?
        bytes32 orderbookId = _getOrderbookId(_loanToken, _collateralToken);
        if (s.orderBooks[orderbookId] != address(0)) revert ErrorsLib.OrderbookAlreadyExists();

        Orderbook orderbook = new Orderbook(_loanToken, _collateralToken, owner(), _feeRecipient);
        orderbookAddress = address(orderbook);

        s.orderBooks[orderbookId] = orderbookAddress;
        s.orderbookAddresses.push(orderbookAddress);

        emit EventsLib.OrderbookCreated(_loanToken, _collateralToken, orderbookAddress);
    }

    /// @notice Gets the address of an orderbook
    /// @param _loanToken The address of the loan token
    /// @param _collateralToken The address of the collateral token
    /// @return orderbook The address of the orderbook
    function getOrderbook(address _loanToken, address _collateralToken) external view returns (address orderbook) {
        bytes32 orderbookId = _getOrderbookId(_loanToken, _collateralToken);
        orderbook = OrderbookFactoryStorage._state().orderBooks[orderbookId];
        if (orderbook == address(0)) revert ErrorsLib.OrderbookNotFound();
    }

    /// @notice Gets the addresses of all orderbooks
    /// @return An array of orderbook addresses
    function getAllOrderbooks() external view returns (address[] memory) {
        return OrderbookFactoryStorage._state().orderbookAddresses;
    }

    function isKeeper(address keeper) external view returns (bool) {
        return OrderbookFactoryStorage._state().isKeeper[keeper];
    }

    function isIRMEnabled(address irm) external view returns (bool) {
        return OrderbookFactoryStorage._state().isIRMEnabled[irm];
    }

    function isPoolManager(address poolManager) external view returns (bool) {
        return OrderbookFactoryStorage._state().isPoolManager[poolManager];
    }

    function isPoolFactory(address poolFactory) external view returns (bool) {
        return OrderbookFactoryStorage._state().isPoolFactory[poolFactory];
    }

    function feeRecipient() external view returns (address) {
        return OrderbookFactoryStorage._state().feeRecipient;
    }

    /// @dev Mapping of orderbook IDs (keccak256(loanToken + collateralToken)) to their addresses
    function _getOrderbookId(address _loanToken, address _collateralToken) private pure returns (bytes32) {
        return keccak256(abi.encode(_loanToken, _collateralToken));
    }
}
