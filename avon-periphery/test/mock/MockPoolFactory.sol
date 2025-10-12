// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MockPoolFactory {
    address public owner;

    mapping(address => bool) public isValidPool;

    constructor() {
        owner = msg.sender;
    }

    // Mock: Set pool valid
    // By default, all pools deployed by the factory are valid
    function mockSetValidPool(address pool, bool status) external {
        if (msg.sender != owner) revert("Not the owner");
        isValidPool[pool] = status;
    }
}
