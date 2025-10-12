// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AvonPoolFactory} from "../../src/factory/AvonPoolFactory.sol";
import {MockOrderbookFactory} from "./MockOrderbookFactory.sol";

/// @title OrderbookMock
/// @notice Minimal mock for pool testing, not inheriting Orderbook

contract MockOrderbook {
    address public owner;
    address public ORDERBOOK_FACTORY;
    address public newOrderbook;

    // Minimal pool whitelist logic
    mapping(address => bool) public isWhitelisted;
    mapping(address => uint256[]) public poolOrders;

    event PoolWhitelisted(address pool);

    constructor(address _orderbookFactory) {
        owner = msg.sender;
        ORDERBOOK_FACTORY = _orderbookFactory;
    }

    function setNewOrderbook(address _newOrderbook) external {
        if (msg.sender != owner) revert("Not the owner");
        newOrderbook = _newOrderbook;
    }

    // Mock: Whitelist a pool
    function mockWhitelistPool(address pool, address poolFactory) external {
        if (!MockOrderbookFactory(ORDERBOOK_FACTORY).isPoolManager(msg.sender)) revert("Not a pool manager");
        if (!MockOrderbookFactory(ORDERBOOK_FACTORY).isPoolFactory(poolFactory)) revert("Not a pool factory");
        if (!AvonPoolFactory(poolFactory).isValidPool(pool)) revert("Invalid pool");
        isWhitelisted[pool] = true;
        emit PoolWhitelisted(pool);
    }

    // Mock: Insert orders for a pool
    function batchInsertOrder(uint64[] calldata irs, uint256[] calldata amounts) external {
        require(isWhitelisted[msg.sender], "Not whitelisted");
        delete poolOrders[msg.sender];
        for (uint256 i; i < irs.length; ++i) {
            if (amounts[i] == 0) break;
            poolOrders[msg.sender].push(irs[i]);
        }
    }

    // Mock: Cancel all orders for a pool
    function mockCancelPoolOrders(address pool) external {
        delete poolOrders[pool];
    }

    // Mock: Get pool orders
    function getPoolOrders(address pool) external view returns (uint256[] memory) {
        return poolOrders[pool];
    }
}
