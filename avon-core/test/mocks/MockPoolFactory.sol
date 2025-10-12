// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockPool} from "./MockPool.sol";

contract MockPoolFactory {
    mapping(address => bool) public isDeployed;

    function createPool(address asset, address orderbook, address irm, address collateral)
        external
        returns (MockPool)
    {
        MockPool pool = new MockPool(ERC20(asset), orderbook, irm, collateral);
        isDeployed[address(pool)] = true;
        return pool;
    }

    function isValidPool(address pool) external view returns (bool) {
        return isDeployed[pool];
    }
}
