// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MockOrderbook} from "./MockOrderbook.sol";

contract MockOrderbookFactory {
    address public feeRecipient;
    address public orderbook;
    address public owner;
    mapping(address => bool) public isPoolFactory;
    mapping(address => bool) public isPoolManager;

    event PoolManagerSet(address manager, bool status);
    event PoolFactorySet(address factory, bool status);

    // Mock: Set pool factory status
    function mockSetPoolFactory(address factory, bool status) external {
        if (msg.sender != owner) revert("Not the owner");
        isPoolFactory[factory] = status;
        emit PoolFactorySet(factory, status);
    }

    // Mock: Set pool manager status
    function mockSetPoolManager(address manager, bool status) external {
        if (msg.sender != owner) revert("Not the owner");
        isPoolManager[manager] = status;
        emit PoolManagerSet(manager, status);
    }

    function mockSetOrderbook(address _orderbook) external {
        if (msg.sender != owner) revert("Not the owner");
        orderbook = _orderbook;
    }

    function getOrderbook(address, address) external view returns (address) {
        return orderbook;
    }

    constructor(address _feeRecipient) {
        feeRecipient = _feeRecipient;
        owner = msg.sender;
    }
}
